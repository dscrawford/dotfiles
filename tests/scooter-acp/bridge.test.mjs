import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { startBridge } from "./acp-client.mjs";
import { startFakeScooter } from "./fake-scooter.mjs";

let fake;
let bridge;

afterEach(async () => {
  await bridge?.stop();
  await fake?.close();
  bridge = fake = undefined;
});

const userTurn = (id, text) => [
  { type: "TEXT_MESSAGE_START", messageId: id, role: "user" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: id, delta: text },
  { type: "TEXT_MESSAGE_END", messageId: id },
];

const reply = (runId, text, threadId = "c1") => [
  { type: "RUN_STARTED", threadId, runId },
  ...userTurn(`u-${runId}`, `question ${runId}`),
  { type: "TEXT_MESSAGE_START", messageId: `a-${runId}`, role: "assistant" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `a-${runId}`, delta: text },
  { type: "TEXT_MESSAGE_END", messageId: `a-${runId}` },
  { type: "RUN_FINISHED", threadId, runId },
];

async function setup(env = {}, opts) {
  fake = await startFakeScooter(opts);
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good", ...env });
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
}

const declineSignIn = () => {
  throw Object.assign(new Error("sign-in cancelled"), { code: -32000 });
};

const texts = (kind) => bridge.updates.filter((u) => u.sessionUpdate === kind).map((u) => u.content.text).join("");

test("initialize advertises load, list, resume and steering", async () => {
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good" });
  const init = await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  assert.equal(init.agentCapabilities.loadSession, true);
  assert.deepEqual(init.agentCapabilities.sessionCapabilities, { list: {}, resume: {} });
  assert.equal(init._meta.steering.supported, true);
});

test("session/list returns the web sidebar: top-level, starred then newest, paged", async () => {
  await setup();
  Object.assign(fake.conv("old"), { title: "Old", lastActivityAt: 1000, status: "suspended" });
  Object.assign(fake.conv("new"), { title: "New", lastActivityAt: 2000, status: "running", runStartedAt: 1900 });
  Object.assign(fake.conv("pinned"), { title: "Pinned", lastActivityAt: 500, starred: true, status: "running", awaitingInputAt: 400 });
  Object.assign(fake.conv("child"), { parentId: "new", lastActivityAt: 3000 });
  const { sessions, nextCursor } = await bridge.request("session/list", { cwd: "/home/d/proj" });
  assert.deepEqual(sessions.map((s) => [s.sessionId, s.title, s.cwd]), [["pinned", "Pinned", "/home/d/proj"], ["new", "New", "/home/d/proj"], ["old", "Old", "/home/d/proj"]]);
  assert.deepEqual(sessions.map((s) => [s._meta.scooter.starred, s._meta.scooter.state]), [[true, "waiting"], [false, "working"], [false, "suspended"]]);
  assert.equal(sessions[1].updatedAt, new Date(2000).toISOString());
  assert.equal(nextCursor, undefined);
  for (let i = 0; i < 60; i++) fake.conv(`bulk${i}`);
  const page1 = await bridge.request("session/list", {});
  assert.equal(page1.sessions.length, 50);
  const page2 = await bridge.request("session/list", { cursor: page1.nextCursor });
  assert.equal(page2.sessions.length, 13);
});

test("a prompt streams the run and ends the turn without echoing the user", async () => {
  await setup();
  fake.setScript((body) => [
    { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
    ...userTurn("u1", body.messages[0].content),
    { type: "TOOL_CALL_START", toolCallId: "t1", toolCallName: "shell" },
    { type: "TOOL_CALL_ARGS", toolCallId: "t1", delta: '{"command":"ls"}' },
    { type: "TOOL_CALL_END", toolCallId: "t1" },
    { type: "TOOL_CALL_RESULT", toolCallId: "t1", messageId: "m", content: "a b" },
    { type: "TEXT_MESSAGE_START", messageId: "a1", role: "assistant" },
    { type: "TEXT_MESSAGE_CONTENT", messageId: "a1", delta: "done" },
    { type: "TEXT_MESSAGE_END", messageId: "a1" },
    { type: "CONTEXT_USAGE", usedTokens: 10, contextWindow: 100 },
    { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1" },
  ]);
  const { sessionId, configOptions } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  assert.equal(configOptions[0].currentValue, "sonnet");
  await bridge.request("session/set_config_option", { sessionId, configId: "model", value: "opus" });
  const res = await bridge.request("session/prompt", { sessionId, prompt: [{ type: "text", text: "list files" }] });
  assert.deepEqual(res, { stopReason: "end_turn" });
  assert.equal(texts("agent_message_chunk"), "done");
  assert.equal(texts("user_message_chunk"), "");
  const call = bridge.updates.find((u) => u.sessionUpdate === "tool_call");
  assert.deepEqual([call.toolCallId, call.kind], ["t1", "execute"]);
  const updates = bridge.updates.filter((u) => u.sessionUpdate === "tool_call_update");
  assert.equal(updates[0].title, "shell: ls");
  assert.equal(updates[1].status, "completed");
  assert.ok(bridge.updates.some((u) => u.sessionUpdate === "usage_update" && u.used === 10));
  const post = fake.requests.find((r) => r.path === "/agui");
  assert.equal(post.headers["x-agent-model"], "opus");
  assert.equal(post.headers.cookie, "_oauth2_proxy=good");
});

test("session/load replays only the last N user turns", async () => {
  await setup({ SCOOTER_REPLAY_TURNS: "2" });
  fake.conv("c1");
  for (const r of ["r1", "r2", "r3"]) for (const e of reply(r, `answer ${r}.`)) fake.append("c1", e);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  assert.equal(texts("agent_message_chunk"), "answer r2.answer r3.");
  assert.equal(texts("user_message_chunk"), "question r2question r3");
});

test("a run started from the web UI arrives as a session/push", async () => {
  await setup();
  fake.conv("c1");
  bridge.answer("session/push", () => null);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  await new Promise((r) => setTimeout(r, 100));
  for (const e of reply("web", "from the browser")) fake.append("c1", e);
  await bridge.waitFor(() => bridge.updates.find((u) => u.sessionUpdate === "session_push_end"));
  assert.equal(bridge.requests.filter((r) => r.method === "session/push").length, 1);
  assert.equal(texts("user_message_chunk"), "question web");
  assert.equal(texts("agent_message_chunk"), "from the browser");
});

test("events appended while the stream was down arrive once after reconnect", async () => {
  await setup();
  fake.conv("c1");
  bridge.answer("session/push", () => null);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  await bridge.waitFor(() => fake.streamCount("c1") === 1);
  fake.dropStreams();
  for (const e of reply("gap", "missed while offline")) fake.append("c1", e);
  await bridge.waitFor(() => bridge.updates.find((u) => u.sessionUpdate === "session_push_end"));
  for (const e of reply("live", " and live again")) fake.append("c1", e);
  await bridge.waitFor(() => bridge.updates.filter((u) => u.sessionUpdate === "session_push_end").length === 2);
  assert.equal(texts("agent_message_chunk"), "missed while offline and live again");
});

test("a permission interrupt round-trips through session/request_permission", async () => {
  await setup();
  const options = [
    { optionId: "yes", name: "Allow", kind: "allow_once" },
    { optionId: "no", name: "Deny", kind: "reject_once" },
  ];
  fake.setScript((body) =>
    body.resume
      ? [
          { type: "PERMISSION_RESOLVED", toolCallId: "t9", optionId: body.resume[0].payload.optionId },
          { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
          { type: "TEXT_MESSAGE_START", messageId: "a", role: "assistant" },
          { type: "TEXT_MESSAGE_CONTENT", messageId: "a", delta: "approved" },
          { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1" },
        ]
      : [
          { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
          { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1", outcome: { type: "interrupt", interrupts: [{ id: "t9", reason: "confirmation", message: "Push to main?", toolCallId: "t9", metadata: { options } }] } },
        ],
  );
  bridge.answer("session/request_permission", () => ({ outcome: { outcome: "selected", optionId: "yes" } }));
  const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  const res = await bridge.request("session/prompt", { sessionId, prompt: [{ type: "text", text: "push" }] });
  assert.equal(res.stopReason, "end_turn");
  const ask = bridge.requests.find((r) => r.method === "session/request_permission");
  assert.equal(ask.params.toolCall.title, "Push to main?");
  assert.deepEqual(ask.params.options.map((o) => o.optionId), ["yes", "no"]);
  const resume = fake.requests.find((r) => r.path === "/agui" && r.body.resume);
  assert.deepEqual(resume.body.resume, [{ interruptId: "t9", status: "resolved", payload: { optionId: "yes" } }]);
  assert.equal(texts("agent_message_chunk"), "approved");
});

test("steering posts to the running conversation; cancel stops it", async () => {
  await setup();
  fake.conv("c1");
  bridge.answer("session/push", () => null);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  assert.deepEqual(await bridge.request("_session/steering", { sessionId: "c1", prompt: [{ type: "text", text: "x" }] }), { outcome: "promptRequired" });
  fake.append("c1", { type: "RUN_STARTED", threadId: "c1", runId: "r" });
  await bridge.waitFor(() => bridge.requests.find((r) => r.method === "session/push"));
  assert.deepEqual(await bridge.request("_session/steering", { sessionId: "c1", prompt: [{ type: "text", text: "also this" }] }), { outcome: "injected" });
  assert.equal(fake.requests.find((r) => r.path === "/conversations/c1/messages").body.text, "also this");
  bridge.notify("session/cancel", { sessionId: "c1" });
  await bridge.waitFor(() => fake.requests.find((r) => r.path === "/conversations/c1/cancel"));
});

test("an expired session surfaces as an auth error naming the cookie file", async () => {
  const dir = mkdtempSync(join(tmpdir(), "scooter-acp-"));
  const file = join(dir, "cookie");
  writeFileSync(file, "stale");
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "", SCOOTER_COOKIE_FILE: file });
  bridge.answer("_scooter/login", declineSignIn);
  await bridge.request("initialize", { protocolVersion: 1 });
  await assert.rejects(bridge.request("session/list", {}), (e) => e.code === -32000 && e.message.includes(file));
});

test("a refreshed oauth2-proxy cookie is written back to the cookie file", async () => {
  const dir = mkdtempSync(join(tmpdir(), "scooter-acp-"));
  const file = join(dir, "cookie");
  writeFileSync(file, "good");
  fake = await startFakeScooter({ refreshTo: "_oauth2_proxy=fresh" });
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "", SCOOTER_COOKIE_FILE: file });
  await bridge.request("initialize", { protocolVersion: 1 });
  await bridge.request("session/list", {});
  assert.equal(readFileSync(file, "utf8").trim(), "_oauth2_proxy=fresh");
  await bridge.request("session/list", {});
  assert.equal(fake.requests.at(-1).headers.cookie, "_oauth2_proxy=fresh");
});

test("session/new fails fast when Scooter accepts the connection but never answers", async () => {
  fake = await startFakeScooter();
  fake.setRoutes(({ method, path }) => (method === "POST" && path === "/conversations" ? new Promise(() => {}) : undefined));
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good", SCOOTER_REQUEST_TIMEOUT_MS: "200" });
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  const started = Date.now();
  await assert.rejects(bridge.request("session/new", { cwd: "/tmp", mcpServers: [] }), /POST \/conversations did not answer within 200ms/);
  assert.ok(Date.now() - started < 2000);
});

test("session/new names the origin when Scooter is unreachable", async () => {
  bridge = startBridge({ SCOOTER_URL: "http://127.0.0.1:1", SCOOTER_COOKIE: "_oauth2_proxy=good" });
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  await assert.rejects(bridge.request("session/new", { cwd: "/tmp", mcpServers: [] }), /POST \/conversations unreachable: .*\(http:\/\/127\.0\.0\.1:1\)/);
});

test("a missing cookie file surfaces as an auth error naming the file", async () => {
  fake = await startFakeScooter();
  const file = join(mkdtempSync(join(tmpdir(), "scooter-")), "cookie");
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: file });
  bridge.answer("_scooter/login", declineSignIn);
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  await assert.rejects(bridge.request("session/new", { cwd: "/tmp", mcpServers: [] }), new RegExp(`refresh the session cookie in ${file}`));
});

const MAIN = fileURLToPath(new URL("../../pkgs/scooter-acp/src/main.mjs", import.meta.url));

const checkAuth = (env) =>
  new Promise((resolve) => {
    execFile(process.execPath, [MAIN, "--check-auth"], { timeout: 10000, env: { ...process.env, ...env } }, (e) => resolve(e ? e.code : 0));
  });

const cookieFile = (content) => {
  const file = join(mkdtempSync(join(tmpdir(), "scooter-")), "cookie");
  if (content) writeFileSync(file, content);
  return file;
};

test("--check-auth exits 0 for an accepted cookie", async () => {
  fake = await startFakeScooter();
  assert.equal(await checkAuth({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: cookieFile("_oauth2_proxy=good\n") }), 0);
});

test("--check-auth exits 77 for a rejected or missing cookie", async () => {
  fake = await startFakeScooter();
  assert.equal(await checkAuth({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: cookieFile("_oauth2_proxy=stale\n") }), 77);
  assert.equal(await checkAuth({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: cookieFile() }), 77);
});

test("--check-auth exits 1 when Scooter is unreachable, so a good cookie isn't asked for again", async () => {
  assert.equal(await checkAuth({ SCOOTER_URL: "http://127.0.0.1:1", SCOOTER_COOKIE_FILE: cookieFile("_oauth2_proxy=good\n") }), 1);
});
