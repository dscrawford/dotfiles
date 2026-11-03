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

async function loaded(routes = {}) {
  fake = await startFakeScooter();
  fake.conv("c1");
  fake.setRoutes(async ({ method, path, body }) => {
    const route = routes[`${method} ${path}`];
    if (!route) return undefined;
    if (method !== "GET") await body();
    return typeof route === "function" ? route() : route;
  });
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good" });
  bridge.answer("session/push", () => null);
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
}

const sandbox = (action, params = {}) => bridge.request(`_scooter/sandbox/${action}`, { sessionId: "c1", ...params });
const sent = (method, path) => fake.requests.filter((r) => r.method === method && r.path === path);
const texts = () => bridge.updates.filter((u) => u.sessionUpdate === "agent_message_chunk").map((u) => u.content.text).join("");

async function runningTurn() {
  fake.append("c1", { type: "RUN_STARTED", threadId: "c1", runId: "r" });
  await bridge.waitFor(() => bridge.requests.find((r) => r.method === "session/push"));
}

test("status gathers the conversation, resources, readiness and size presets", async () => {
  await loaded({
    "GET /conversations/c1": { json: { id: "c1", title: "Work", status: "running", starred: true, visibility: "private" } },
    "GET /conversations/c1/resources": { json: { resources: { limits: { cpu: "2", memory: "4Gi" } }, pendingRestart: { size: true } } },
    "GET /conversations/c1/ready": { json: { ready: true, status: "running" } },
    "GET /sandbox-sizes": { json: { sizes: { small: { cpu: "1", memory: "2Gi" }, large: { cpu: "4", memory: "8Gi" } }, default: "small" } },
  });
  const s = await sandbox("status");
  assert.equal(s.conversation.visibility, "private");
  assert.equal(s.resources.pendingRestart.size, true);
  assert.equal(s.ready.ready, true);
  assert.deepEqual(Object.keys(s.sizes.sizes), ["small", "large"]);
  assert.equal(s.running, false);
});

test("status tolerates a deployment without sandbox resources", async () => {
  await loaded({ "GET /sandbox-sizes": { status: 500, json: { error: "boom" } } });
  const s = await sandbox("status");
  assert.equal(s.conversation.id, "c1");
  assert.equal(s.sizes, null);
});

test("resize, rename and star send their PATCH bodies", async () => {
  await loaded({
    "PATCH /conversations/c1/size": { json: { size: "large" } },
    "PATCH /conversations/c1/title": { json: { title: "Renamed" } },
    "PATCH /conversations/c1/starred": { json: { starred: true } },
  });
  assert.deepEqual(await sandbox("resize", { size: "large" }), { size: "large" });
  await sandbox("rename", { title: "  Renamed  " });
  await sandbox("star", { starred: true });
  assert.deepEqual(sent("PATCH", "/conversations/c1/size")[0].body, { size: "large" });
  assert.deepEqual(sent("PATCH", "/conversations/c1/title")[0].body, { title: "Renamed" });
  assert.deepEqual(sent("PATCH", "/conversations/c1/starred")[0].body, { starred: true });
});

test("visibility confirms only when a private conversation goes shared", async () => {
  let visibility = "private";
  await loaded({
    "GET /conversations/c1": () => ({ json: { id: "c1", visibility } }),
    "PATCH /conversations/c1/visibility": () => {
      visibility = sent("PATCH", "/conversations/c1/visibility").at(-1).body.visibility;
      return { json: { id: "c1", visibility } };
    },
  });
  await sandbox("visibility", { visibility: "shared" });
  await sandbox("visibility", { visibility: "private" });
  assert.deepEqual(sent("PATCH", "/conversations/c1/visibility").map((r) => r.body), [
    { visibility: "shared", confirm: true },
    { visibility: "private" },
  ]);
});

test("suspend, restart and compact are refused while a turn runs", async () => {
  await loaded();
  await runningTurn();
  for (const action of ["suspend", "restart", "compact"]) {
    await assert.rejects(sandbox(action), (e) => e.message.includes("cancel the turn first (C-c C-c)"));
  }
  assert.equal((await sandbox("status")).running, true);
  assert.equal(fake.requests.filter((r) => r.method === "POST" && /suspend|restart|compact/.test(r.path)).length, 0);
});

test("a 409 comes back as Scooter's own message", async () => {
  await loaded({ "POST /conversations/c1/restart": { status: 409, json: { error: "conversation c2 is running in this sandbox; restart after it finishes" } } });
  await assert.rejects(sandbox("restart"), (e) => e.message === "conversation c2 is running in this sandbox; restart after it finishes");
});

test("a suspend that fails with a 500 says the sandbox is probably busy", async () => {
  await loaded({ "POST /conversations/c1/suspend": { status: 500, json: { error: "internal" } } });
  await assert.rejects(sandbox("suspend"), (e) => /could not suspend the sandbox \(HTTP 500\); it is probably busy/.test(e.message));
});

for (const action of ["resume", "restart", "compact"]) {
  test(`${action} resyncs history the stream did not deliver`, async () => {
    await loaded({
      [`POST /conversations/c1/${action}`]: () => {
        const c = fake.conv("c1");
        c.events.push({ type: "SYSTEM_MESSAGE", source: "scooter", text: `after ${action}` });
        c.checksums.push("unstreamed");
        return { json: { ok: true } };
      },
    });
    await sandbox(action);
    assert.match(texts(), new RegExp(`after ${action}`));
  });
}
