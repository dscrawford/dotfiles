import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { sshServiceUrl } from "../../pkgs/scooter-acp/src/tunnel.mjs";
import { OP, encodeFrame, frameDecoder } from "../../pkgs/scooter-acp/src/websocket.mjs";
import { echoWebSocket, startFakeScooter } from "./fake-scooter.mjs";

const MAIN = fileURLToPath(new URL("../../pkgs/scooter-acp/src/main.mjs", import.meta.url));

let fake;

afterEach(async () => {
  await fake?.close();
  fake = undefined;
});

function tunnel(id, input, env = {}) {
  const child = spawn(process.execPath, [MAIN, "--tunnel", id], {
    env: { ...process.env, SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good", ...env },
  });
  const out = [];
  let stderr = "";
  child.stdout.on("data", (d) => out.push(d));
  child.stderr.on("data", (d) => (stderr += d));
  child.stdin.end(input);
  return new Promise((resolve) => child.on("close", (code) => resolve({ code, stdout: Buffer.concat(out), stderr })));
}

const upgrades = () => fake.requests.filter((r) => r.method === "UPGRADE");

test("frames survive arriving one byte at a time, at every length encoding", () => {
  const payloads = [0, 1, 125, 126, 65535, 65536, 200000].map((n) => randomBytes(n));
  const pings = [];
  const decoder = frameDecoder({ onControl: (op, p) => pings.push([op, p.toString()]) });
  const got = [];
  decoder.on("data", (d) => got.push(d));
  const wire = Buffer.concat([
    ...payloads.slice(0, 3).map((p) => encodeFrame(p)),
    encodeFrame(Buffer.from("hi"), { opcode: OP.ping }),
    ...payloads.slice(3).map((p, i) => encodeFrame(p, { mask: i % 2 === 0 })),
  ]);
  for (let i = 0; i < 300; i++) decoder.write(wire.subarray(i, i + 1));
  for (let i = 300; i < wire.length; i += 4093) decoder.write(wire.subarray(i, i + 4093));
  assert.deepEqual(Buffer.concat(got), Buffer.concat(payloads));
  assert.deepEqual(pings, [[OP.ping, "hi"]]);
});

test("the fake's WebSocket codec speaks to Node's own WebSocket client", async () => {
  fake = await startFakeScooter();
  fake.setUpgrade(echoWebSocket);
  const ws = new WebSocket(`${fake.url.replace("http", "ws")}/c/c1/ssh/`, { headers: { Cookie: "_oauth2_proxy=good" } });
  ws.binaryType = "arraybuffer";
  const payload = randomBytes(70000);
  const echoed = await new Promise((resolve, reject) => {
    ws.onopen = () => ws.send(payload);
    ws.onmessage = (m) => resolve(Buffer.from(m.data));
    ws.onerror = reject;
  });
  ws.close();
  assert.deepEqual(echoed, payload);
});

test("the tunnel pipes stdio through the sandbox's ssh service with the session cookie", async () => {
  fake = await startFakeScooter();
  fake.conv("c1").services = [{ name: "vite", url: "/c/c1/vite/", running: true }];
  fake.setUpgrade(echoWebSocket);
  const input = randomBytes(300000);
  const { code, stdout, stderr } = await tunnel("c1", input);
  assert.equal(code, 0, stderr);
  assert.deepEqual(stdout, input);
  assert.deepEqual(
    upgrades().map((r) => [r.path, r.headers.cookie]),
    [["/c/c1/ssh/", "_oauth2_proxy=good"]],
  );
  assert.ok(!fake.requests.some((r) => r.path.includes("/resume")), "a running sandbox is not resumed");
});

test("a listed ssh service's URL wins, as on a deployment with per-conversation origins", async () => {
  fake = await startFakeScooter();
  fake.conv("c1").services = [{ name: "ssh", url: "/origin-c1/ssh/", running: false }];
  fake.setUpgrade(echoWebSocket);
  const { code, stdout } = await tunnel("c1", "ping");
  assert.equal(code, 0);
  assert.equal(stdout.toString(), "ping");
  assert.deepEqual(upgrades().map((r) => r.path), ["/origin-c1/ssh/"]);
});

test("without any listed service the URL is the main host's /c/<id>/ssh/", async () => {
  const client = { webServices: async () => ({ services: [] }) };
  assert.equal(await sshServiceUrl(client, { url: "https://s.example" }, "a b"), "https://s.example/c/a%20b/ssh/");
});

test("a refused cookie exits 77 and says how to sign in", async () => {
  fake = await startFakeScooter();
  fake.conv("c1");
  fake.setUpgrade(echoWebSocket);
  const { code, stderr, stdout } = await tunnel("c1", "x", { SCOOTER_COOKIE: "_oauth2_proxy=stale" });
  assert.equal(code, 77);
  assert.match(stderr, /refused the ssh tunnel .*HTTP 302.*my\/scooter-login/);
  assert.equal(stdout.length, 0);
});

test("a sleeping sandbox is resumed and its ssh service started before the tunnel connects", async () => {
  fake = await startFakeScooter();
  fake.conv("c1").services = [];
  let refusals = 2;
  fake.setUpgrade((req, socket, head) => (refusals-- > 0 ? socket.end("HTTP/1.1 502 Bad Gateway\r\n\r\n") : echoWebSocket(req, socket, head)));
  fake.setRoutes(({ method, path }) => {
    if (method === "GET" && path === "/conversations/c1") return { json: { id: "c1", status: "suspended" } };
    if (method === "POST" && path === "/conversations/c1/resume") return { status: 202, json: { ok: true } };
    return undefined;
  });
  const { code, stdout, stderr } = await tunnel("c1", "hello");
  assert.equal(code, 0, stderr);
  assert.equal(stdout.toString(), "hello");
  assert.match(stderr, /waiting for the sandbox's ssh service \(HTTP 502\)/);
  const posts = fake.requests.filter((r) => r.method === "POST").map((r) => r.path);
  assert.deepEqual(posts, ["/conversations/c1/resume", "/conversations/c1/web-services/ssh/start"]);
  assert.equal(upgrades().length, 3);
});

test("a service that never answers fails once the tunnel timeout passes", async () => {
  fake = await startFakeScooter();
  fake.conv("c1");
  fake.setUpgrade((_req, socket) => socket.end("HTTP/1.1 503 Service Unavailable\r\n\r\n"));
  const started = Date.now();
  const { code, stderr } = await tunnel("c1", "x", { SCOOTER_TUNNEL_TIMEOUT_MS: "1500" });
  assert.equal(code, 1);
  assert.match(stderr, /ssh service at .*\/c\/c1\/ssh\/ did not answer: HTTP 503/);
  assert.ok(Date.now() - started < 5000);
});
