const QUESTIONS = [
  { question: "Which database?", header: "DB", options: [{ label: "Postgres", description: "Relational" }, { label: "SQLite" }] },
  { question: "Which extras?", header: "Extras", multiSelect: true, options: [{ label: "Cache" }, { label: "Queue" }] },
  { question: "Name the service", header: "Name", options: [] },
];

const GRANT = {
  account: "123456789012",
  risk: "high",
  justification: "deploy",
  policy_document: { Statement: [{ Effect: "Allow", Action: ["s3:PutObject"], Resource: "arn:aws:s3:::b/*" }] },
  write_actions: ["s3:PutObject"],
};

const pending = new Map();

const interrupt = (threadId, runId, intr) => [
  { type: "RUN_STARTED", threadId, runId },
  { type: "RUN_FINISHED", threadId, runId, outcome: { type: "interrupt", interrupts: [{ reason: "confirmation", ...intr }] } },
];

const finish = (threadId, runId, id, optionId, text) => [
  { type: "PERMISSION_RESOLVED", toolCallId: id, optionId },
  { type: "RUN_STARTED", threadId, runId },
  { type: "TEXT_MESSAGE_START", messageId: `a-${runId}`, role: "assistant" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `a-${runId}`, delta: text },
  { type: "TEXT_MESSAGE_END", messageId: `a-${runId}` },
  { type: "RUN_FINISHED", threadId, runId },
];

export function cardScript(body) {
  const { threadId } = body;
  if (body.resume) {
    const [r] = body.resume;
    pending.delete(r.interruptId);
    return finish(threadId, `${r.interruptId}-done`, r.interruptId, r.payload?.optionId ?? null, `ANSWERED ${JSON.stringify(r.payload?.result?.answers ?? r.status)}`);
  }
  const text = body.messages[0]?.content;
  if (text === "ask me") {
    pending.set("toolu_ask", threadId);
    return interrupt(threadId, "ask", {
      id: "toolu_ask",
      toolCallId: "toolu_ask",
      message: "The agent has a question",
      metadata: { kind: "ask-user.questions", data: { questions: QUESTIONS }, options: [{ optionId: "answer", name: "Answer", kind: "allow_once" }] },
    });
  }
  if (text === "grant") {
    pending.set("req-aws", threadId);
    return interrupt(threadId, "grant", {
      id: "req-aws",
      message: "Grant S3 write?",
      metadata: { contrib: "aws", kind: "aws.permissions", data: GRANT, options: [{ optionId: "approve", name: "Approve", kind: "allow_once" }, { optionId: "deny", name: "Deny", kind: "reject_once" }] },
    });
  }
  return undefined;
}

export function cardTrigger(fake, name) {
  if (name === "answer-in-web" && pending.has("toolu_ask")) {
    const threadId = pending.get("toolu_ask");
    pending.delete("toolu_ask");
    for (const e of finish(threadId, "web-answer", "toolu_ask", "answer", "WEB-ANSWERED")) fake.append(threadId, e);
    return true;
  }
  if (name !== "approve-in-web" || !pending.has("req-aws")) return false;
  const threadId = pending.get("req-aws");
  pending.delete("req-aws");
  for (const e of finish(threadId, "web-approve", "req-aws", "approve", "WEB-APPROVED")) fake.append(threadId, e);
  return true;
}
