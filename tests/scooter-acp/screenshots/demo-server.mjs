// A fake Scooter with a believable conversation list, for screenshots.sh.
import { existsSync, readFileSync, rmSync } from "node:fs";
import { startFakeScooter } from "../fake-scooter.mjs";
import { cardScript, cardTrigger } from "../e2e-cards.mjs";

const fake = await startFakeScooter();
const now = Date.now();
const min = 60_000;
const day = 24 * 60 * min;

const conversations = [
  ["kube", "KubeServer: bump scooter to 0.42", { starred: true, status: "running", lastActivityAt: now - 3 * day }],
  ["gotg", "GOTG importer retries", { starred: true, status: "suspended", lastActivityAt: now - 9 * day }],
  ["login", "Fix the login redirect", { status: "running", lastActivityAt: now - 4 * min }],
  ["jelly", "Jellyfin transcoding stalls on 4K", { status: "running", runStartedAt: now - min, lastActivityAt: now - min }],
  ["deploy", "Website deploy approval", { status: "running", awaitingInputAt: now - 20 * min, lastActivityAt: now - 25 * min }],
  ["deck", "deckkm: Esc hold timeout", { status: "failed", lastActivityAt: now - day - 2 * 60 * min }],
  ["resume", "Resume: LaTeX spacing", { status: "suspended", lastActivityAt: now - 2 * day }],
  ["matrix", "Matrix bridge certificates", { status: "ended", lastActivityAt: now - 40 * day }],
];
for (const [id, title, extra] of conversations) Object.assign(fake.conv(id), { title }, extra);
fake.addLink("login", { source: "github", resourceType: "pull_request", url: "https://github.com/dscrawford/website/pull/12", title: "website#12 Fix login redirect" });
fake.addLink("deploy", { source: "slack", resourceType: "thread", url: "https://slack.example/archives/C1/p1", title: "#ops thread" });

const turn = (threadId, runId, question, answer, tools = []) => [
  { type: "RUN_STARTED", threadId, runId },
  { type: "TEXT_MESSAGE_START", messageId: `u${runId}`, role: "user" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `u${runId}`, delta: question },
  { type: "TEXT_MESSAGE_END", messageId: `u${runId}` },
  ...tools.flatMap(([id, name, args, result]) => [
    { type: "TOOL_CALL_START", toolCallId: id, toolCallName: name },
    { type: "TOOL_CALL_ARGS", toolCallId: id, delta: JSON.stringify(args) },
    { type: "TOOL_CALL_END", toolCallId: id },
    { type: "TOOL_CALL_RESULT", toolCallId: id, messageId: `m${id}`, content: result },
  ]),
  { type: "TEXT_MESSAGE_START", messageId: `a${runId}`, role: "assistant" },
  { type: "TEXT_MESSAGE_CONTENT", messageId: `a${runId}`, delta: answer },
  { type: "TEXT_MESSAGE_END", messageId: `a${runId}` },
  { type: "RUN_FINISHED", threadId, runId },
];

for (const e of turn(
  "login",
  "h1",
  "After signing in, users land on / instead of the page they came from. Can you find out why?",
  "The OAuth callback drops the `next` parameter. `handleCallback` in `src/auth.ts` redirects to `/` unconditionally:\n\n```ts\nreturn res.redirect(\"/\");\n```\n\nI changed it to redirect to the `next` value saved in the session, accepting only same-origin paths, and added a test. Opened **website#12**.",
  [
    ["t1", "bash", { command: "grep -rn \"redirect(\" src/auth.ts" }, "src/auth.ts:41:  return res.redirect(\"/\");"],
    ["t2", "bash", { command: "npm test -- auth" }, "PASS test/auth.test.ts (4 tests)"],
  ],
)) fake.append("login", e);

let n = 0;
const trimmed = (body) => ({ ...body, messages: body.messages?.map((m) => ({ ...m, content: typeof m.content === "string" ? m.content.trim() : m.content })) });
fake.setScript((body) => cardScript(trimmed(body)) ?? turn(body.threadId, `p${++n}`, body.messages[0].content, "Done."));
fake.setRoutes(({ method, path }) => {
  if (method === "GET" && path === "/conversations/login") return { json: { id: "login", title: "Fix the login redirect", status: "running", visibility: "shared" } };
  return undefined;
});

setInterval(() => {
  if (!existsSync(process.env.TRIGGER_FILE)) return;
  const what = readFileSync(process.env.TRIGGER_FILE, "utf8");
  rmSync(process.env.TRIGGER_FILE);
  if (cardTrigger(fake, what)) return;
  if (what === "web") {
    for (const e of turn(
      "login",
      "w1",
      "Does the fix also cover the logout redirect?",
      "Yes. Logout goes through the same `safeNext` helper now, so it also returns you to the page you were on.",
      [["t3", "bash", { command: "grep -n safeNext src/*.ts" }, "src/auth.ts:12:export function safeNext(\nsrc/logout.ts:8:  safeNext(req.query.next)"]],
    )) fake.append("login", e);
  }
}, 100);

console.log(fake.url);
