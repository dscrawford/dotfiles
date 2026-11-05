#!/usr/bin/env node
// Stands in for Chromium: answers CDP over --remote-debugging-pipe (reads fd 3, writes fd 4).
import { createReadStream, createWriteStream, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
if (process.env.FAKE_BROWSER_ARGS_FILE) writeFileSync(process.env.FAKE_BROWSER_ARGS_FILE, args.join("\n"));
if (process.env.FAKE_BROWSER_EXIT) process.exit(0);

const host = new URL(args.find((a) => a.startsWith("--app=")).slice("--app=".length)).hostname;
const [name, value] = (process.env.FAKE_BROWSER_COOKIE ?? "_oauth2_proxy=good").split("=");
const cookies = [
  { name, value, domain: host },
  { name: "other_app", value: "parent-domain", domain: `.${host}` },
  { name: "user_session", value: "github-secret", domain: "github.com" },
];

const out = createWriteStream(null, { fd: 4 });
let buffer = "";
createReadStream(null, { fd: 3 }).on("data", (d) => {
  buffer += d;
  for (let i; (i = buffer.indexOf("\0")) >= 0; buffer = buffer.slice(i + 1)) {
    const { id, method } = JSON.parse(buffer.slice(0, i));
    out.write(JSON.stringify({ id, result: method === "Storage.getCookies" ? { cookies } : {} }) + "\0");
  }
});
setInterval(() => {}, 1000);
