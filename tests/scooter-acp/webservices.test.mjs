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

async function setup() {
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good" });
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
}

test("list returns services with absolute URLs, refreshing the manifest", async () => {
  await setup();
  fake.conv("c1").services = [
    { name: "vite", displayName: "Vite dev", url: "/c/c1/vite/", running: true, fit: "needs 4Gi" },
    { name: "docs", url: "https://c1.sandbox.example/docs/", running: false },
  ];
  const { services } = await bridge.request("_scooter/web-services/list", { sessionId: "c1" });
  assert.deepEqual(services, [
    { name: "vite", displayName: "Vite dev", running: true, url: `${fake.url}/c/c1/vite/`, fit: "needs 4Gi" },
    { name: "docs", displayName: "docs", running: false, url: "https://c1.sandbox.example/docs/" },
  ]);
  assert.ok(fake.requests.some((r) => r.path === "/conversations/c1/web-services?refresh=1"));
});

test("start and stop post to the service and change its state", async () => {
  await setup();
  fake.conv("c1").services = [{ name: "vite", displayName: "Vite", url: "/c/c1/vite/", running: false }];
  assert.deepEqual(await bridge.request("_scooter/web-services/start", { sessionId: "c1", name: "vite" }), {});
  assert.equal(fake.conv("c1").services[0].running, true);
  await bridge.request("_scooter/web-services/stop", { sessionId: "c1", name: "vite" });
  assert.equal(fake.conv("c1").services[0].running, false);
  assert.ok(fake.requests.some((r) => r.method === "POST" && r.path === "/conversations/c1/web-services/vite/stop"));
});

test("an unknown service or missing name is an error", async () => {
  await setup();
  fake.conv("c1").services = [];
  await assert.rejects(bridge.request("_scooter/web-services/start", { sessionId: "c1", name: "nope" }), /HTTP 404/);
  await assert.rejects(bridge.request("_scooter/web-services/stop", { sessionId: "c1" }), /name is required/);
});

test("a scooter-service command in a tool call leaves a notice after its result", async () => {
  await setup();
  fake.setScript((body) => [
    { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
    { type: "TOOL_CALL_START", toolCallId: "t1", toolCallName: "bash" },
    { type: "TOOL_CALL_ARGS", toolCallId: "t1", delta: '{"command":"scooter-service start vite && scooter-service stop docs"}' },
    { type: "TOOL_CALL_END", toolCallId: "t1" },
    { type: "TOOL_CALL_RESULT", toolCallId: "t1", messageId: "m", content: "ok" },
    { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1" },
  ]);
  const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  await bridge.request("session/prompt", { sessionId, prompt: [{ type: "text", text: "serve it" }] });
  const kinds = bridge.updates.map((u) => u.sessionUpdate);
  const notices = bridge.updates.filter((u) => u.sessionUpdate === "agent_message_chunk").map((u) => u.content.text);
  assert.ok(kinds.lastIndexOf("tool_call_update") < kinds.indexOf("agent_message_chunk"));
  assert.match(notices[0], /web service `vite` started/);
  assert.match(notices[1], /web service `docs` stopped/);
});
