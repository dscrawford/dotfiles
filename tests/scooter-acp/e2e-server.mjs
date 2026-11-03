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
const PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
const shot = fake.addAsset("old", "shot", "image/png", Buffer.from(PNG, "base64"));
fake.append("old", { type: "TEXT_MESSAGE_START", messageId: "ah1", role: "assistant" });
fake.append("old", { type: "MESSAGE_IMAGES", messageId: "ah1", images: [{ assetId: "shot", mimeType: "image/png", url: shot }] });
const describe = (content) =>
  Array.isArray(content)
    ? content.map((p) => (p.type === "image" ? `IMAGE-RECEIVED ${p.mimeType} ${p.data === PNG ? "intact" : "corrupt"}` : p.text)).join(" ")
    : content;
let n = 0;
fake.setScript((body) => run(body.threadId, `p${++n}`, describe(body.messages[0].content), Array.isArray(body.messages[0].content) ? describe(body.messages[0].content) : "LIVE-ANSWER", [
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
console.log(fake.url);
