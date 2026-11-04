import assert from "node:assert/strict";
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

const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452", "hex");
const JPG = Buffer.from("ffd8ffe000104a464946", "hex");

async function setup(env = {}) {
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good", ...env });
  return bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
}

const ref = (url, mimeType = "image/png") => ({ type: "image", mimeType, assetId: url.split("/").pop(), url });

const imageRun = (shot, photo) => [
  { type: "RUN_STARTED", threadId: "c1", runId: "r1" },
  { type: "TEXT_MESSAGE_START", messageId: "u1", role: "user" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: "u1", delta: "what is this?" },
  { type: "TEXT_MESSAGE_END", messageId: "u1" },
  { type: "MESSAGE_IMAGES", messageId: "u1", images: [{ assetId: "p", mimeType: "image/jpeg", url: photo }] },
  { type: "TOOL_CALL_START", toolCallId: "t1", toolCallName: "view_image" },
  { type: "TOOL_CALL_END", toolCallId: "t1" },
  {
    type: "TOOL_CALL_RESULT",
    toolCallId: "t1",
    messageId: "m",
    content: JSON.stringify({ content: [{ type: "text", text: "shot.png 16 bytes" }, ref(shot), { type: "image", mimeType: "image/png", omitted: "too-large" }] }),
  },
  { type: "TEXT_MESSAGE_START", messageId: "a1", role: "assistant" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: "a1", delta: "a cat" },
  { type: "MESSAGE_IMAGES", messageId: "a1", images: [{ assetId: "s", mimeType: "image/png", url: shot }] },
  { type: "TEXT_MESSAGE_END", messageId: "a1" },
  { type: "RUN_FINISHED", threadId: "c1", runId: "r1" },
];

test("initialize advertises image prompts", async () => {
  const init = await setup();
  assert.deepEqual(init.agentCapabilities.promptCapabilities, { embeddedContext: true, image: true });
});

test("history replay inlines user, assistant and tool-result images fetched with the cookie", async () => {
  await setup();
  fake.conv("c1");
  const shot = fake.addAsset("c1", "s", "image/png", PNG);
  const photo = fake.addAsset("c1", "p", "image/jpeg", JPG);
  for (const e of imageRun(shot, photo)) fake.append("c1", e);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });

  const user = bridge.updates.filter((u) => u.sessionUpdate === "user_message_chunk").map((u) => u.content);
  assert.deepEqual(user[1], { type: "image", data: JPG.toString("base64"), mimeType: "image/jpeg" });

  const agent = bridge.updates.filter((u) => u.sessionUpdate === "agent_message_chunk");
  assert.deepEqual(agent.map((u) => [u.messageId, u.content.type]), [["a1", "text"], ["a1", "image"]]);
  assert.equal(agent[1].content.data, PNG.toString("base64"));

  const result = bridge.updates.find((u) => u.sessionUpdate === "tool_call_update" && u.status === "completed");
  const blocks = result.content.map((c) => c.content);
  assert.deepEqual(blocks[0], { type: "text", text: "shot.png 16 bytes" });
  assert.deepEqual(blocks.slice(1).map((b) => b.type), ["image", "text"]);
  assert.equal(blocks[1].data, PNG.toString("base64"));
  assert.match(blocks[2].text, /not shown: too-large/);

  const fetches = fake.requests.filter((r) => r.path.includes("/assets/"));
  assert.ok(fetches.length >= 3);
  assert.ok(fetches.every((r) => r.headers.cookie === "_oauth2_proxy=good"));
});

test("a missing or oversized asset becomes a placeholder instead of failing the replay", async () => {
  await setup({ SCOOTER_IMAGE_MAX_BYTES: "12" });
  fake.conv("c1");
  const big = fake.addAsset("c1", "big", "image/png", PNG);
  const events = [
    { type: "TEXT_MESSAGE_START", messageId: "a1", role: "assistant" },
    { type: "MESSAGE_IMAGES", messageId: "a1", images: [ref(big), ref("/conversations/c1/assets/gone"), ref("https://evil.example/x.png")] },
  ];
  for (const e of events) fake.append("c1", e);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  const texts = bridge.updates.filter((u) => u.sessionUpdate === "agent_message_chunk").map((u) => u.content.text);
  assert.equal(texts.length, 3);
  assert.match(texts[0], /too large/);
  assert.match(texts[1], /HTTP 404/);
  assert.match(texts[2], /unavailable/);
  assert.ok(!fake.requests.some((r) => r.path.includes("evil")));
});

test("a web-started run pushes its tool image live", async () => {
  await setup();
  fake.conv("c1");
  bridge.answer("session/push", () => null);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  await bridge.waitFor(() => fake.streamCount("c1") === 1);
  const shot = fake.addAsset("c1", "s", "image/png", PNG);
  const photo = fake.addAsset("c1", "p", "image/jpeg", JPG);
  for (const e of imageRun(shot, photo)) fake.append("c1", e);
  await bridge.waitFor(() => bridge.updates.find((u) => u.sessionUpdate === "session_push_end"));
  const images = bridge.updates.filter((u) => u.content?.type === "image" || u.content?.some?.((c) => c.content.type === "image"));
  assert.deepEqual(images.map((u) => u.sessionUpdate), ["user_message_chunk", "tool_call_update", "agent_message_chunk"]);
});

test("prompt images are posted as multimodal content; the echo is not refetched", async () => {
  await setup();
  fake.setScript((body) => [
    { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
    { type: "TEXT_MESSAGE_START", messageId: "u1", role: "user" },
    { type: "TEXT_MESSAGE_CONTENT", messageId: "u1", delta: "look" },
    { type: "MESSAGE_IMAGES", messageId: "u1", images: [{ assetId: "x", mimeType: "image/png", url: `/conversations/${body.threadId}/assets/x` }] },
    { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1" },
  ]);
  const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  const data = PNG.toString("base64");
  const res = await bridge.request("session/prompt", {
    sessionId,
    prompt: [
      { type: "text", text: "look" },
      { type: "image", data, mimeType: "image/png", uri: "file:///tmp/shot.png" },
    ],
  });
  assert.equal(res.stopReason, "end_turn");
  const post = fake.requests.find((r) => r.path === "/agui");
  assert.deepEqual(post.body.messages[0].content, [
    { type: "text", text: "look" },
    { type: "image", data, mimeType: "image/png" },
  ]);
  assert.ok(!fake.requests.some((r) => r.path.includes("/assets/")));
  assert.ok(!bridge.updates.some((u) => u.sessionUpdate === "user_message_chunk"));

  await bridge.request("session/prompt", { sessionId, prompt: [{ type: "image", data, mimeType: "image/png" }] });
  assert.deepEqual(fake.requests.filter((r) => r.path === "/agui")[1].body.messages[0].content, [{ type: "image", data, mimeType: "image/png" }]);
});

test("unsupported or oversized prompt images are refused before posting", async () => {
  await setup({ SCOOTER_IMAGE_MAX_BYTES: "8" });
  const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  await assert.rejects(
    bridge.request("session/prompt", { sessionId, prompt: [{ type: "image", data: "PHN2Zz4=", mimeType: "image/svg+xml" }] }),
    /not image\/svg\+xml/,
  );
  await assert.rejects(
    bridge.request("session/prompt", { sessionId, prompt: [{ type: "image", data: PNG.toString("base64"), mimeType: "image/png" }] }),
    /over the 8-byte limit/,
  );
  assert.ok(!fake.requests.some((r) => r.path === "/agui"));
});

test("steering with an image posts an interrupting /agui message", async () => {
  await setup();
  fake.conv("c1");
  bridge.answer("session/push", () => null);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  fake.append("c1", { type: "RUN_STARTED", threadId: "c1", runId: "r" });
  await bridge.waitFor(() => bridge.requests.find((r) => r.method === "session/push"));
  const data = PNG.toString("base64");
  const res = await bridge.request("_session/steering", { sessionId: "c1", prompt: [{ type: "text", text: "this one" }, { type: "image", data, mimeType: "image/png" }] });
  assert.deepEqual(res, { outcome: "injected" });
  const post = fake.requests.find((r) => r.path === "/agui");
  assert.equal(post.body.priority, 10);
  assert.deepEqual(post.body.messages[0].content, [{ type: "text", text: "this one" }, { type: "image", data, mimeType: "image/png" }]);
});
