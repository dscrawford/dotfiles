import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { startFakeScooter } from "./fake-scooter.mjs";

const MAIN = fileURLToPath(new URL("../../pkgs/scooter-acp/src/main.mjs", import.meta.url));
const BROWSER = fileURLToPath(new URL("./fake-browser.mjs", import.meta.url));

let fake;

afterEach(async () => {
  await fake?.close();
  fake = undefined;
});

const login = (env, base = { SCOOTER_BROWSER: BROWSER }) =>
  new Promise((resolve) => {
    execFile(process.execPath, [MAIN, "--login"], { timeout: 10000, env: { ...process.env, ...base, ...env } }, (e, _out, stderr) =>
      resolve({ code: e ? e.code : 0, stderr }),
    );
  });

function fakeFirefoxHome({ cookie } = {}) {
  const home = mkdtempSync(join(tmpdir(), "scooter-home-"));
  const profile = join(home, ".mozilla", "firefox", "abc123.default-release");
  mkdirSync(profile, { recursive: true });
  writeFileSync(join(home, ".mozilla", "firefox", "profiles.ini"), "[Profile0]\nName=default-release\nIsRelative=1\nPath=abc123.default-release\nDefault=1\n");
  const db = new DatabaseSync(join(profile, "cookies.sqlite"));
  db.exec("CREATE TABLE moz_cookies (id INTEGER PRIMARY KEY, name TEXT, value TEXT, host TEXT, path TEXT)");
  if (cookie) db.prepare("INSERT INTO moz_cookies (name, value, host, path) VALUES (?, ?, ?, '/')").run(cookie.name, cookie.value, cookie.host);
  db.close();
  return { home, cookieDb: join(profile, "cookies.sqlite") };
}

function fakeXdgTools({ cookieDb, cookie, openedFile }) {
  const bin = mkdtempSync(join(tmpdir(), "scooter-bin-"));
  writeFileSync(join(bin, "xdg-settings"), "#!/bin/sh\necho firefox.desktop\n");
  const insert = cookie
    ? `${process.execPath} -e "const {DatabaseSync}=require('node:sqlite');const db=new DatabaseSync(process.argv[1]);db.prepare(\\"INSERT INTO moz_cookies (name, value, host, path) VALUES (?, ?, ?, '/')\\").run(process.argv[2], process.argv[3], process.argv[4])" '${cookieDb}' '${cookie.name}' '${cookie.value}' '${cookie.host}'\n`
    : "";
  writeFileSync(join(bin, "xdg-open"), `#!/bin/sh\nprintf '%s' "$1" > '${openedFile}'\n${insert}`);
  for (const tool of ["xdg-settings", "xdg-open"]) chmodSync(join(bin, tool), 0o755);
  return bin;
}

const tempFile = (name) => join(mkdtempSync(join(tmpdir(), "scooter-")), name);

test("--login opens the sign-in page and saves only Scooter's accepted cookies, privately", async () => {
  fake = await startFakeScooter();
  const file = tempFile("cookie");
  const argsFile = tempFile("args");
  const { code, stderr } = await login({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: file, FAKE_BROWSER_ARGS_FILE: argsFile });
  assert.equal(code, 0, stderr);
  assert.equal(readFileSync(file, "utf8"), "_oauth2_proxy=good\n");
  assert.equal(statSync(file).mode & 0o777, 0o600);
  const args = readFileSync(argsFile, "utf8").split("\n");
  assert.ok(args.includes(`--app=${fake.url}/oauth2/start?rd=%2F`), args.join(" "));
  assert.ok(args.includes("--remote-debugging-pipe"), args.join(" "));
  assert.ok(args.some((a) => a.startsWith("--user-data-dir=")), args.join(" "));
});

test("--login gives up with a message when the browser is closed before sign-in", async () => {
  fake = await startFakeScooter();
  const file = tempFile("cookie");
  const { code, stderr } = await login({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: file, FAKE_BROWSER_EXIT: "1" });
  assert.equal(code, 1);
  assert.match(stderr, /closed before/);
});

test("--login names the fix when no browser is installed", async () => {
  const { code, stderr } = await login({ SCOOTER_URL: "http://127.0.0.1:1", SCOOTER_COOKIE_FILE: tempFile("cookie"), SCOOTER_BROWSER: "/nonexistent/browser" });
  assert.equal(code, 1);
  assert.match(stderr, /SCOOTER_BROWSER/);
});

test("--login reuses the session already in the default Firefox profile without opening anything", async () => {
  fake = await startFakeScooter();
  const host = new URL(fake.url).hostname;
  const { home, cookieDb } = fakeFirefoxHome({ cookie: { name: "_oauth2_proxy", value: "good", host } });
  const openedFile = tempFile("opened");
  const bin = fakeXdgTools({ cookieDb, openedFile });
  const file = tempFile("cookie");
  const { code, stderr } = await login({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: file, HOME: home, PATH: `${bin}:${process.env.PATH}` }, {});
  assert.equal(code, 0, stderr);
  assert.equal(readFileSync(file, "utf8"), "_oauth2_proxy=good\n");
  assert.equal(statSync(file).mode & 0o777, 0o600);
  assert.throws(() => readFileSync(openedFile), /ENOENT/);
});

test("--login opens the sign-in page in the default Firefox and waits for its cookie", async () => {
  fake = await startFakeScooter();
  const host = new URL(fake.url).hostname;
  const { home, cookieDb } = fakeFirefoxHome();
  const openedFile = tempFile("opened");
  const bin = fakeXdgTools({ cookieDb, openedFile, cookie: { name: "_oauth2_proxy", value: "good", host } });
  const file = tempFile("cookie");
  const { code, stderr } = await login({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: file, HOME: home, PATH: `${bin}:${process.env.PATH}` }, {});
  assert.equal(code, 0, stderr);
  assert.equal(readFileSync(openedFile, "utf8"), `${fake.url}/oauth2/start?rd=%2F`);
  assert.equal(readFileSync(file, "utf8"), "_oauth2_proxy=good\n");
});

test("--login ignores a stale Firefox cookie Scooter refuses and keeps waiting", async () => {
  fake = await startFakeScooter();
  const host = new URL(fake.url).hostname;
  const { home, cookieDb } = fakeFirefoxHome({ cookie: { name: "_oauth2_proxy", value: "expired", host } });
  const openedFile = tempFile("opened");
  const bin = fakeXdgTools({ cookieDb, openedFile });
  const { code } = await login({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: tempFile("cookie"), HOME: home, PATH: `${bin}:${process.env.PATH}` }, {});
  assert.notEqual(code, 0);
  assert.equal(readFileSync(openedFile, "utf8"), `${fake.url}/oauth2/start?rd=%2F`);
});

test("SCOOTER_BROWSER still forces the Chromium flow even when Firefox is the default", async () => {
  fake = await startFakeScooter();
  const { home, cookieDb } = fakeFirefoxHome();
  const openedFile = tempFile("opened");
  const bin = fakeXdgTools({ cookieDb, openedFile });
  const file = tempFile("cookie");
  const { code, stderr } = await login({ SCOOTER_URL: fake.url, SCOOTER_COOKIE_FILE: file, HOME: home, PATH: `${bin}:${process.env.PATH}` });
  assert.equal(code, 0, stderr);
  assert.equal(readFileSync(file, "utf8"), "_oauth2_proxy=good\n");
  assert.throws(() => readFileSync(openedFile), /ENOENT/);
});
