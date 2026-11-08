import { proxyUpgradeTo, startFakeScooter } from "./fake-scooter.mjs";
import { cardScript, cardTrigger } from "./e2e-cards.mjs";
const fake = await startFakeScooter();
fake.conv("old");
Object.assign(fake.conv("old"), { title: "Fix the login redirect" });
Object.assign(fake.conv("pinned"), { title: "Pinned", starred: true, status: "running", awaitingInputAt: 1, lastActivityAt: 0 });
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
fake.setScript((body) => cardScript(body) ?? run(body.threadId, `p${++n}`, describe(body.messages[0].content), Array.isArray(body.messages[0].content) ? describe(body.messages[0].content) : "LIVE-ANSWER", [
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
const filesCall = [
  { type: "TOOL_CALL_START", toolCallId: "wf", toolCallName: "bash" },
  { type: "TOOL_CALL_ARGS", toolCallId: "wf", delta: JSON.stringify({ command: "sed -i 2p hello.txt" }) },
  { type: "TOOL_CALL_END", toolCallId: "wf" },
  { type: "TOOL_CALL_RESULT", toolCallId: "wf", messageId: "mwf", content: `wrote ${process.env.SANDBOX_DIR}/hello.txt:2` },
];
if (process.env.SSH_BACKEND_PORT) fake.setUpgrade(proxyUpgradeTo(Number(process.env.SSH_BACKEND_PORT)));
import { existsSync, readFileSync, rmSync } from "node:fs";
fake.addLink("old", { source: "github", resourceType: "pull_request", url: "https://github.com/o/r/pull/7", title: "o/r#7 Fix login" });
setInterval(() => {
  if (existsSync(process.env.TRIGGER_FILE)) {
    const what = readFileSync(process.env.TRIGGER_FILE, "utf8");
    rmSync(process.env.TRIGGER_FILE);
    if (cardTrigger(fake, what)) return;
    if (what === "link") return fake.addLink("old", { source: "jira", resourceType: "issue", url: "https://jira.example/browse/OPS-1" });
    if (what === "files") return run("old", "f1", "FILES-QUESTION", `FILES-ANSWER`, filesCall).forEach((e) => fake.append("old", e));
    for (const e of run("old", "w1", "WEB-QUESTION", "WEB-ANSWER", serviceCall)) fake.append("old", e);
  }
}, 100);
fake.setRoutes(({ method, path }) => {
  if (method === "GET" && path === "/conversations/old") return { json: { id: "old", title: "Fix the login redirect", status: "running", visibility: "shared" } };
  if (method !== "POST" || path !== "/conversations/old/compact") return undefined;
  fake.append("old", { type: "COMPACTION_MARKER", summary: "s", summarizedTurns: 3, keptRuns: 1, ts: Date.now() });
  return { status: 202, json: { ok: true, compacted: true, summarizedTurns: 3, keptRuns: 1 } };
});
console.log(fake.url);
