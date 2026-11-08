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

const QUESTION = {
  id: "toolu_q",
  toolCallId: "toolu_q",
  message: "The agent has a question",
  metadata: {
    kind: "ask-user.questions",
    data: { questions: [{ question: "Which database?", header: "DB", options: [{ label: "Postgres" }, { label: "SQLite" }] }] },
    options: [{ optionId: "answer", name: "Answer", kind: "allow_once" }],
  },
};

const FORMS = { elicitation: { form: {} } };
const ANSWER = { action: "accept", content: { q0: "SQLite" } };

const resumedRun = (threadId, runId) => [
  { type: "PERMISSION_RESOLVED", toolCallId: "toolu_q", optionId: "answer" },
  { type: "RUN_STARTED", threadId, runId },
  { type: "RUN_FINISHED", threadId, runId },
];

async function ask({ resume, clientCapabilities = FORMS, env = {} }) {
  fake = await startFakeScooter();
  bridge = startBridge({ SCOOTER_URL: fake.url, SCOOTER_COOKIE: "_oauth2_proxy=good", ...env });
  await bridge.request("initialize", { protocolVersion: 1, clientCapabilities });
  let resumes = 0;
  fake.setScript((body) =>
    body.resume
      ? resume(++resumes, body)
      : [
          { type: "RUN_STARTED", threadId: body.threadId, runId: "r0" },
          { type: "RUN_FINISHED", threadId: body.threadId, runId: "r0", outcome: { type: "interrupt", interrupts: [{ reason: "confirmation", ...QUESTION }] } },
        ],
  );
  const { sessionId } = await bridge.request("session/new", { cwd: "/tmp", mcpServers: [] });
  const done = bridge.request("session/prompt", { sessionId, prompt: [{ type: "text", text: "go" }] });
  return { sessionId, done };
}

const nth = (method, n) => bridge.waitFor(() => bridge.requests.filter((r) => r.method === method)[n]);
const resumes = () => fake.requests.filter((r) => r.path === "/agui" && r.body?.resume);
const questionUpdates = () => bridge.updates.filter((u) => u.sessionUpdate === "tool_call_update" && u.toolCallId === "toolu_q");

test("an answer reaches Scooter when the resumed run takes longer to start than the request timeout", async () => {
  const { done } = await ask({
    env: { SCOOTER_REQUEST_TIMEOUT_MS: "200" },
    resume: (_, body) => ({ startAfterMs: 600, events: resumedRun(body.threadId, "r1") }),
  });
  bridge.reply((await nth("elicitation/create", 0)).id, ANSWER);
  assert.equal((await done).stopReason, "end_turn");
  assert.equal(resumes().length, 1);
  assert.equal(resumes()[0].abandoned, undefined);
  assert.deepEqual(resumes()[0].body.resume[0].payload.result.answers, { "Which database?": "SQLite" });
});

test("the question shows as answered only once Scooter has started the resumed run", async () => {
  let release;
  const started = new Promise((r) => (release = r));
  await ask({ resume: (_, body) => started.then(() => resumedRun(body.threadId, "r1")) });
  bridge.reply((await nth("elicitation/create", 0)).id, ANSWER);
  await bridge.waitFor(() => resumes().length === 1);
  assert.equal(questionUpdates().find((u) => u.status === "completed"), undefined);
  release();
  const answered = await bridge.waitFor(() => questionUpdates().find((u) => u.status === "completed"));
  assert.match(answered.content[0].content.text, /Which database\?: SQLite/);
});

test("a form answer Scooter turns down is reported on the question and asked again", async () => {
  const { done } = await ask({
    resume: (n, body) =>
      n === 1 ? { streamOnly: [{ type: "RUN_ERROR", threadId: body.threadId, message: "interrupt toolu_q is not waiting" }] } : resumedRun(body.threadId, "r2"),
  });
  bridge.reply((await nth("elicitation/create", 0)).id, ANSWER);
  const again = await nth("elicitation/create", 1);
  const failed = questionUpdates().find((u) => u.status === "failed");
  assert.match(failed.content[0].content.text, /Scooter did not take the answer: interrupt toolu_q is not waiting/);
  bridge.reply(again.id, ANSWER);
  assert.equal((await done).stopReason, "end_turn");
  assert.equal(resumes().length, 2);
});

test("a form answer Scooter rejects over HTTP is reported and asked again", async () => {
  let refused = false;
  await ask({ resume: (_, body) => resumedRun(body.threadId, "r1") });
  const first = await nth("elicitation/create", 0);
  fake.setRoutes(({ method, path }) => (method === "POST" && path === "/agui" && !refused ? ((refused = true), { status: 409, json: { error: "busy" } }) : undefined));
  bridge.reply(first.id, ANSWER);
  await nth("elicitation/create", 1);
  assert.match(questionUpdates().find((u) => u.status === "failed").content[0].content.text, /HTTP 409/);
});

test("a card answer Scooter turns down is reported and the card asked again", async () => {
  const { sessionId } = await ask({
    clientCapabilities: {},
    resume: (n, body) => (n === 1 ? { streamOnly: [{ type: "RUN_ERROR", threadId: body.threadId, message: "interrupt toolu_q is not waiting" }] } : resumedRun(body.threadId, "r2")),
  });
  const card = await nth("session/request_permission", 0);
  await bridge.request("_scooter/answer", { sessionId, toolCallId: "toolu_q", answers: [["SQLite"]] });
  bridge.reply(card.id, { outcome: { outcome: "selected", optionId: "scooter:answer" } });
  await nth("session/request_permission", 1);
  assert.match(questionUpdates().find((u) => u.status === "failed").content[0].content.text, /interrupt toolu_q is not waiting/);
});
