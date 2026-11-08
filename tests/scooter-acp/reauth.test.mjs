import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";

import { startBridge } from "./acp-client.mjs";
import { startFakeScooter } from "./fake-scooter.mjs";

let fake;
let bridge;

afterEach(async () => {
  await bridge?.stop();
  await fake?.close();
  bridge = fake = undefined;
});

const reply = (runId, text, threadId = "c1") => [
  { type: "RUN_STARTED", threadId, runId },
  { type: "TEXT_MESSAGE_START", messageId: `a-${runId}`, role: "assistant" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `a-${runId}`, delta: text },
  { type: "TEXT_MESSAGE_END", messageId: `a-${runId}` },
  { type: "RUN_FINISHED", threadId, runId },
];

const texts = () => bridge.updates.filter((u) => u.sessionUpdate === "agent_message_chunk").map((u) => u.content.text).join("");
const logins = () => bridge.requests.filter((r) => r.method === "_scooter/login");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function signedIn(env = {}) {
  const file = join(mkdtempSync(join(tmpdir(), "scooter-reauth-")), "cookie");
  writeFileSync(file, "_oauth2_proxy=good\n");
  fake = await startFakeScooter();
  fake.conv("c1");
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "", SCOOTER_COOKIE_FILE: file, ...env });
  bridge.answer("session/push", () => null);
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  await bridge.waitFor(() => fake.streamCount("c1") === 1);
  return file;
}

for (const refusal of [401, 403, 302, "html"]) {
  test(`a cookie refreshed on disk is picked up mid-session without asking (${refusal})`, async () => {
    const file = await signedIn();
    fake.expireSession("_oauth2_proxy=renewed", refusal);
    writeFileSync(file, "_oauth2_proxy=renewed\n");
    const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
    assert.equal(sessionId, "c2");
    assert.equal(logins().length, 0);
    await bridge.waitFor(() => fake.streamCount("c1") === 1, 5000);
    for (const e of reply("after", "stream is back")) fake.append("c1", e);
    await bridge.waitFor(() => texts().includes("stream is back"));
  });
}

test("a refused cookie asks the client to sign in once for concurrent failures, then retries them", async () => {
  const file = await signedIn();
  bridge.answer("_scooter/login", async (params) => {
    assert.equal(params.cookieFile, file);
    await sleep(200);
    writeFileSync(file, "_oauth2_proxy=renewed\n");
    return {};
  });
  fake.expireSession("_oauth2_proxy=renewed", 302);
  const results = await Promise.all([
    bridge.request("session/list", {}),
    bridge.request("session/list", {}),
    bridge.request("session/new", { cwd: "/tmp", mcpServers: [] }),
  ]);
  assert.equal(results[2].sessionId, "c2");
  assert.equal(logins().length, 1);
  await bridge.waitFor(() => fake.streamCount("c1") === 1, 5000);
  for (const e of reply("after", "stream is back")) fake.append("c1", e);
  await bridge.waitFor(() => texts().includes("stream is back"));
  assert.equal(logins().length, 1);
});

test("the event stream alone triggers the sign-in when the cookie expires while idle", async () => {
  const file = await signedIn();
  bridge.answer("_scooter/login", () => {
    writeFileSync(file, "_oauth2_proxy=renewed\n");
    return {};
  });
  fake.expireSession("_oauth2_proxy=renewed", 401);
  await bridge.waitFor(() => fake.streamCount("c1") === 1, 5000);
  for (const e of reply("after", "stream is back")) fake.append("c1", e);
  await bridge.waitFor(() => texts().includes("stream is back"));
  assert.equal(logins().length, 1);
});

test("answering a permission card after the cookie expired still resumes the run", async () => {
  const file = await signedIn();
  bridge.answer("_scooter/login", () => {
    writeFileSync(file, "_oauth2_proxy=renewed\n");
    return {};
  });
  const options = [{ optionId: "yes", name: "Allow", kind: "allow_once" }];
  fake.setScript((body) =>
    body.resume
      ? [{ type: "PERMISSION_RESOLVED", toolCallId: "t9", optionId: "yes" }, ...reply("r2", "approved", body.threadId)]
      : [
          { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
          { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1", outcome: { type: "interrupt", interrupts: [{ id: "t9", reason: "confirmation", message: "Push?", toolCallId: "t9", metadata: { options } }] } },
        ],
  );
  const turn = bridge.request("session/prompt", { sessionId: "c1", prompt: [{ type: "text", text: "push" }] });
  const ask = await bridge.waitFor(() => bridge.requests.find((r) => r.method === "session/request_permission"));
  fake.expireSession("_oauth2_proxy=renewed", 403);
  bridge.reply(ask.id, { outcome: { outcome: "selected", optionId: "yes" } });
  await bridge.waitFor(() => fake.requests.find((r) => r.path === "/agui" && r.body?.resume && r.headers.cookie === "_oauth2_proxy=renewed"), 5000);
  assert.equal((await turn).stopReason, "end_turn");
  assert.ok(texts().includes("approved"));
});

test("a declined sign-in fails the request; the stream doesn't ask again, the next request does", async () => {
  const file = await signedIn();
  let declines = 0;
  bridge.answer("_scooter/login", () => {
    declines += 1;
    throw Object.assign(new Error("Scooter sign-in failed: cancelled"), { code: -32000 });
  });
  fake.expireSession("_oauth2_proxy=renewed", 401);
  await assert.rejects(bridge.request("session/list", {}), (e) => e.code === -32000 && e.message.includes(file));
  await sleep(2500);
  assert.equal(declines, 1);
  await assert.rejects(bridge.request("session/list", {}), (e) => e.code === -32000);
  assert.equal(declines, 2);
  writeFileSync(file, "_oauth2_proxy=renewed\n");
  await bridge.waitFor(() => fake.streamCount("c1") === 1, 15000);
  assert.equal(declines, 2);
});

test("a client without _scooter/login gets the auth error naming the cookie file", async () => {
  const file = await signedIn();
  bridge.answer("_scooter/login", () => {
    throw Object.assign(new Error("Method not found: _scooter/login"), { code: -32601 });
  });
  fake.expireSession("_oauth2_proxy=renewed", 401);
  await assert.rejects(bridge.request("session/list", {}), (e) => e.code === -32000 && e.message.includes(`refresh the session cookie in ${file}`));
});

test("initialize offers browser sign-in as an ACP auth method", async () => {
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "", SCOOTER_COOKIE_FILE: join(tmpdir(), "nope") });
  const init = await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  assert.deepEqual(init.authMethods.map((m) => m.id), ["browser"]);
});
