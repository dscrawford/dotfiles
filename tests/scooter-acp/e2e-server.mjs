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
fake.conv("old").services = [
  { name: "vite", displayName: "Vite dev", url: "/c/old/vite/", running: false },
  { name: "docs", displayName: "Docs", url: "/c/old/docs/", running: true },
];
const serviceCall = [
  { type: "TOOL_CALL_START", toolCallId: "ws", toolCallName: "bash" },
  { type: "TOOL_CALL_ARGS", toolCallId: "ws", delta: JSON.stringify({ command: "scooter-service start vite" }) },
  { type: "TOOL_CALL_END", toolCallId: "ws" },
  { type: "TOOL_CALL_RESULT", toolCallId: "ws", messageId: "mws", content: "started" },
];
import { existsSync, readFileSync, rmSync } from "node:fs";
fake.addLink("old", { source: "github", resourceType: "pull_request", url: "https://github.com/o/r/pull/7", title: "o/r#7 Fix login" });
setInterval(() => {
  if (existsSync(process.env.TRIGGER_FILE)) {
    const what = readFileSync(process.env.TRIGGER_FILE, "utf8");
    rmSync(process.env.TRIGGER_FILE);
    if (what === "link") return fake.addLink("old", { source: "jira", resourceType: "issue", url: "https://jira.example/browse/OPS-1" });
    for (const e of run("old", "w1", "WEB-QUESTION", "WEB-ANSWER", serviceCall)) fake.append("old", e);
  }
}, 100);
console.log(fake.url);
