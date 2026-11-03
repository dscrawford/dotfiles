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

const pr = { source: "github", resourceType: "pull_request", url: "https://github.com/o/r/pull/7", title: "o/r#7 Fix login" };
const issue = { source: "jira", resourceType: "issue", url: "https://jira.example/browse/OPS-1" };

test("_scooter/links returns the conversation's links with labels", async () => {
  await setup();
  fake.conv("c1");
  fake.addLink("c1", pr);
  fake.addLink("c1", issue);
  const { links } = await bridge.request("_scooter/links", { sessionId: "c1" });
  assert.deepEqual(links.map((l) => [l.label, l.url]), [["o/r#7 Fix login", pr.url], ["jira issue", issue.url]]);
});

test("session/list titles carry the linked sources", async () => {
  await setup();
  Object.assign(fake.conv("c1"), { title: "Fix login" });
  fake.addLink("c1", pr);
  fake.addLink("c1", issue);
  const { sessions } = await bridge.request("session/list", {});
  assert.equal(sessions[0].title, "Fix login [github, jira]");
});

test("a link added to an open conversation is announced once", async () => {
  await setup();
  fake.conv("c1");
  fake.conv("other");
  fake.addLink("c1", pr);
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  await bridge.waitFor(() => fake.listStreamCount() === 1);
  fake.addLink("other", issue);
  fake.addLink("c1", issue);
  const note = await bridge.waitFor(() => bridge.requests.find((r) => r.method === "_scooter/links_changed"));
  assert.equal(note.params.sessionId, "c1");
  assert.deepEqual(note.params.added.map((l) => l.label), ["jira issue"]);
  assert.equal(note.params.links.length, 2);
  await new Promise((r) => setTimeout(r, 100));
  assert.equal(bridge.requests.filter((r) => r.method === "_scooter/links_changed").length, 1);
});

test("closing the last session drops the list stream", async () => {
  await setup();
  fake.conv("c1");
  await bridge.request("session/load", { sessionId: "c1", cwd: "/tmp", mcpServers: [] });
  await bridge.waitFor(() => fake.listStreamCount() === 1);
  await bridge.request("session/close", { sessionId: "c1" });
  await bridge.waitFor(() => fake.listStreamCount() === 0);
});
