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

const QUESTIONS = [
  { question: "Which database?", header: "DB", options: [{ label: "Postgres", description: "Relational" }, { label: "SQLite" }] },
  { question: "Which extras?", header: "Extras", multiSelect: true, options: [{ label: "Cache" }, { label: "Search" }, { label: "Queue" }] },
  { question: "Name the service", header: "Name", options: [] },
];

const AWS = {
  account: "123456789012",
  risk: "high",
  justification: "deploy the stack",
  summary: "S3 write",
  policy_document: { Statement: [{ Effect: "Allow", Action: ["s3:GetObject", "s3:PutObject"], Resource: "arn:aws:s3:::b/*" }] },
  managed_policy_arns: ["arn:aws:iam::aws:policy/ReadOnlyAccess"],
  write_actions: ["s3:PutObject"],
  obligations: [{ rules: ["prod"], parts: [], approved_by: null }],
};

const APPROVE = [
  { optionId: "approve", name: "Approve", kind: "allow_once" },
  { optionId: "deny", name: "Deny", kind: "reject_once" },
];

async function raise(interrupt) {
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good" });
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities: {} });
  fake.setScript((body) =>
    body.resume
      ? [
          { type: "PERMISSION_RESOLVED", toolCallId: interrupt.toolCallId ?? interrupt.id, optionId: body.resume[0].payload?.optionId ?? null },
          { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
          { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1" },
        ]
      : [
          { type: "RUN_STARTED", threadId: body.threadId, runId: "r1" },
          { type: "RUN_FINISHED", threadId: body.threadId, runId: "r1", outcome: { type: "interrupt", interrupts: [{ reason: "confirmation", ...interrupt }] } },
        ],
  );
  const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  const done = bridge.request("session/prompt", { sessionId, prompt: [{ type: "text", text: "go" }] });
  const ask = await bridge.waitFor(() => bridge.requests.find((r) => r.method === "session/request_permission"));
  return { sessionId, ask, done };
}

const pick = (ask, optionId) => bridge.reply(ask.id, { outcome: { outcome: "selected", optionId } });
const detail = (ask) => ask.params.toolCall.content[0].content.text;
const resumed = () => fake.requests.find((r) => r.path === "/agui" && r.body.resume)?.body.resume;
const asks = () => bridge.requests.filter((r) => r.method === "session/request_permission");

test("ask-user questions are answered in Emacs and resume with { answers } keyed by question", async () => {
  const { sessionId, ask, done } = await raise({
    id: "toolu_1",
    toolCallId: "toolu_1",
    message: "The agent has a question",
    metadata: { kind: "ask-user.questions", data: { questions: QUESTIONS }, options: [{ optionId: "answer", name: "Answer", kind: "allow_once" }] },
  });
  assert.deepEqual(ask.params.options.map((o) => [o.optionId, o.kind]), [
    ["scooter:answer", "allow_once"],
    ["scooter:dismiss", "reject_once"],
    ["scooter:browser", "allow_always"],
  ]);
  assert.match(detail(ask), /1\. \[DB\] Which database\?\n {2}- Postgres — Relational\n {2}- SQLite/);
  assert.match(detail(ask), /2\. \[Extras\] Which extras\? \(pick any\)/);
  assert.deepEqual(ask.params.toolCall.rawInput.questions.map((q) => q.question), QUESTIONS.map((q) => q.question));

  await assert.rejects(
    bridge.request("_scooter/answer", { sessionId, toolCallId: "toolu_1", answers: [["Postgres"], [], ["svc"]] }),
    /no answer to: Which extras\?/,
  );
  await bridge.request("_scooter/answer", { sessionId, toolCallId: "toolu_1", answers: [["Postgres"], ["Queue", "my own", "Cache"], "billing"] });
  pick(ask, "scooter:answer");
  assert.equal((await done).stopReason, "end_turn");
  assert.deepEqual(resumed(), [
    {
      interruptId: "toolu_1",
      status: "resolved",
      payload: { optionId: "answer", result: { answers: { "Which database?": "Postgres", "Which extras?": "Cache, Queue, my own", "Name the service": "billing" } } },
    },
  ]);
});

test("Answer without collected answers asks again instead of resuming", async () => {
  const { ask } = await raise({
    id: "toolu_2",
    message: "Q",
    metadata: { kind: "ask-user.questions", data: { questions: QUESTIONS.slice(0, 1) }, options: [{ optionId: "answer", name: "Answer", kind: "allow_once" }] },
  });
  pick(ask, "scooter:answer");
  await bridge.waitFor(() => asks().length === 2);
  assert.equal(resumed(), undefined);
  pick(asks()[1], "scooter:dismiss");
  await bridge.waitFor(() => resumed());
  assert.deepEqual(resumed(), [{ interruptId: "toolu_2", status: "cancelled" }]);
});

test("an AWS grant shows account, risk, actions and approvals, and resumes with the picked option", async () => {
  const { ask, done } = await raise({
    id: "req-aws",
    message: "Grant S3 write?",
    metadata: { contrib: "aws", requestId: "req-aws", kind: "aws.permissions", data: AWS, options: APPROVE },
  });
  assert.equal(ask.params.toolCall.toolCallId, "req-aws");
  assert.equal(ask.params.toolCall.title, "Grant S3 write?");
  const text = detail(ask);
  for (const s of ["AWS account 123456789012, high risk", "Why: deploy the stack", "s3:PutObject (write)", "  - s3:GetObject\n", "on arn:aws:s3:::b/*", "ReadOnlyAccess", "prod: waiting"]) {
    assert.ok(text.includes(s), `missing ${s} in\n${text}`);
  }
  assert.deepEqual(ask.params.options.map((o) => o.optionId), ["approve", "deny", "scooter:browser"]);
  pick(ask, "approve");
  await done;
  assert.deepEqual(resumed(), [{ interruptId: "req-aws", status: "resolved", payload: { optionId: "approve" } }]);
});

test("a commit identity proposal shows the identity", async () => {
  const { ask } = await raise({
    id: "req-c",
    message: "The agent proposes your commit identity",
    metadata: { contrib: "commits", kind: "commits.identity", data: { name: "Ada", email: "ada@example.com" }, options: APPROVE },
  });
  assert.match(detail(ask), /Ada <ada@example\.com>/);
  pick(ask, "deny");
  await bridge.waitFor(() => resumed());
  assert.deepEqual(resumed(), [{ interruptId: "req-c", status: "resolved", payload: { optionId: "deny" } }]);
});

test("an unknown kind shows its raw data and offers the browser; a web answer dismisses the prompt", async () => {
  const { ask } = await raise({
    id: "req-x",
    message: "Pick a file",
    metadata: { kind: "files.pick", data: { glob: "*.txt" }, options: [{ optionId: "ok", name: "OK", kind: "allow_once" }] },
  });
  assert.match(detail(ask), /files\.pick[\s\S]*"glob": "\*\.txt"/);
  assert.deepEqual(ask.params.options.map((o) => o.optionId), ["ok", "scooter:browser"]);
  pick(ask, "scooter:browser");
  const again = await bridge.waitFor(() => asks()[1]);
  assert.equal(resumed(), undefined);
  fake.append("c1", { type: "PERMISSION_RESOLVED", toolCallId: "req-x", optionId: "ok" });
  await bridge.waitFor(() => bridge.requests.find((r) => r.method === "$/cancel_request" && r.params.requestId === again.id));
  await bridge.waitFor(() => bridge.updates.find((u) => u.sessionUpdate === "tool_call_update" && u.toolCallId === "req-x" && u.status === "completed"));
});

test("a known kind with data it cannot read falls back to the raw card", async () => {
  const { ask } = await raise({ id: "req-y", message: "Grant?", metadata: { kind: "aws.permissions", data: { nope: 1 }, options: APPROVE } });
  assert.match(detail(ask), /Emacs has no card for aws\.permissions requests/);
  assert.deepEqual(ask.params.options.map((o) => o.optionId), ["approve", "deny", "scooter:browser"]);
});
