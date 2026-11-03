import { startFakeScooter } from "./fake-scooter.mjs";
const fake = await startFakeScooter();
fake.conv("old");
Object.assign(fake.conv("old"), { title: "Fix the login redirect" });
const run = (threadId, runId, q, a, extra = []) => [
  { type: "RUN_STARTED", threadId, runId },
  { type: "TEXT_MESSAGE_START", messageId: `u${runId}`, role: "user" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `u${runId}`, delta: q },
  { type: "TEXT_MESSAGE_END", messageId: `u${runId}` },
  ...extra,
  { type: "TEXT_MESSAGE_START", messageId: `a${runId}`, role: "assistant" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `a${runId}`, delta: a },
  { type: "TEXT_MESSAGE_END", messageId: `a${runId}` },
  { type: "RUN_FINISHED", threadId, runId },
];
for (const e of run("old", "h1", "HISTORY-QUESTION", "HISTORY-ANSWER")) fake.append("old", e);
let n = 0;
fake.setScript((body) => run(body.threadId, `p${++n}`, body.messages[0].content, "LIVE-ANSWER", [
  { type: "TOOL_CALL_START", toolCallId: `t${n}`, toolCallName: "shell" },
  { type: "TOOL_CALL_ARGS", toolCallId: `t${n}`, delta: '{"command":"ls /workspace"}' },
  { type: "TOOL_CALL_END", toolCallId: `t${n}` },
  { type: "TOOL_CALL_RESULT", toolCallId: `t${n}`, messageId: "m", content: "dotfiles scooter" },
]));
import { existsSync, rmSync } from "node:fs";
setInterval(() => {
  if (existsSync(process.env.TRIGGER_FILE)) {
    rmSync(process.env.TRIGGER_FILE);
    for (const e of run("old", "w1", "WEB-QUESTION", "WEB-ANSWER")) fake.append("old", e);
  }
}, 100);
fake.setRoutes(({ method, path }) => {
  if (method === "GET" && path === "/conversations/old") return { json: { id: "old", title: "Fix the login redirect", status: "running", visibility: "shared" } };
  if (method !== "POST" || path !== "/conversations/old/compact") return undefined;
  fake.append("old", { type: "COMPACTION_MARKER", summary: "s", summarizedTurns: 3, keptRuns: 1, ts: Date.now() });
  return { status: 202, json: { ok: true, compacted: true, summarizedTurns: 3, keptRuns: 1 } };
});
console.log(fake.url);
