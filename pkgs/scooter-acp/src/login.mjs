import { spawn, spawnSync } from "node:child_process";
import { accessSync, chmodSync, constants, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

import { firefoxCookies, firefoxProfileDir, isFirefoxDesktop } from "./firefox.mjs";
import { createScooterClient } from "./scooter.mjs";

const POLL_MS = 1000;
const LOGIN_TIMEOUT_MS = 5 * 60 * 1000;
const BROWSERS = ["chromium", "chromium-browser", "google-chrome-stable", "google-chrome", "brave"];

const isExecutable = (path) => {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

function findBrowser(env) {
  const candidates = env.SCOOTER_BROWSER
    ? [env.SCOOTER_BROWSER]
    : BROWSERS.flatMap((b) => (env.PATH ?? "").split(":").filter(Boolean).map((dir) => join(dir, b)));
  const found = candidates.find(isExecutable);
  if (!found) throw new Error(`No Chromium-based browser found; set SCOOTER_BROWSER (tried ${env.SCOOTER_BROWSER ?? BROWSERS.join(", ")})`);
  return found;
}

function cdpOverPipe(child) {
  const pending = new Map();
  let nextId = 1;
  let buffer = "";
  child.stdio[3].on("error", () => {});
  child.stdio[4].on("error", () => {});
  child.stdio[4].on("data", (chunk) => {
    buffer += chunk;
    for (let i; (i = buffer.indexOf("\0")) >= 0; buffer = buffer.slice(i + 1)) {
      const { id, result, error } = JSON.parse(buffer.slice(0, i));
      const settle = pending.get(id);
      pending.delete(id);
      settle?.(error, result);
    }
  });
  return (method) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, (error, result) => (error ? reject(new Error(error.message)) : resolve(result)));
      child.stdio[3].write(JSON.stringify({ id, method }) + "\0");
    });
}

async function waitForSession(cdp, config, signal) {
  const host = new URL(config.url).hostname;
  while (!signal.aborted) {
    const { cookies } = await cdp("Storage.getCookies");
    const header = await acceptedHeader(config, cookies.filter((c) => c.domain === host));
    if (header) return header;
    await sleep(POLL_MS);
  }
  throw new Error(`Sign-in not finished after ${LOGIN_TIMEOUT_MS / 60000} minutes`);
}

function defaultBrowserDesktopId(env) {
  if (process.platform !== "linux") return undefined;
  const probe = spawnSync("xdg-settings", ["get", "default-web-browser"], { env, encoding: "utf8" });
  return probe.status === 0 ? probe.stdout.trim() : undefined;
}

const saveCookie = (config, header) => {
  mkdirSync(dirname(config.cookieFile), { recursive: true, mode: 0o700 });
  writeFileSync(config.cookieFile, header + "\n", { mode: 0o600 });
  chmodSync(config.cookieFile, 0o600);
};

async function acceptedHeader(config, cookies) {
  const header = cookies.map((c) => `${c.name}=${c.value}`).join("; ");
  if (!header) return undefined;
  const client = createScooterClient({ ...config, cookie: header, cookieFile: undefined });
  return (await client.checkAuth().catch(() => false)) ? header : undefined;
}

/** Signs in through the user's own Firefox: reuses its session cookie, or opens the sign-in page there and waits for one. */
async function loginWithFirefox(config, env, profileDir) {
  const host = new URL(config.url).hostname;
  const read = () => acceptedHeader(config, firefoxCookies(profileDir, host));
  const existing = await read();
  if (existing) return saveCookie(config, existing);
  const opener = process.platform === "darwin" ? "open" : "xdg-open";
  const child = spawn(opener, [`${config.url}/oauth2/start?rd=%2F`], { env, stdio: "ignore", detached: true });
  await new Promise((resolve, reject) => {
    child.once("error", (e) => reject(new Error(`Could not start ${opener}: ${e.message}`)));
    child.once("exit", resolve);
  });
  child.unref();
  const deadline = Date.now() + LOGIN_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const header = await read();
    if (header) return saveCookie(config, header);
    await sleep(POLL_MS);
  }
  throw new Error(`Sign-in not finished after ${LOGIN_TIMEOUT_MS / 60000} minutes`);
}

/** Saves Scooter's session cookie: through the user's Firefox when that is the default browser, else a Chromium profile over DevTools. */
export async function login(config, env = process.env) {
  if (!config.cookieFile) throw new Error("SCOOTER_COOKIE_FILE is not set");
  const choice = env.SCOOTER_LOGIN_BROWSER ?? (env.SCOOTER_BROWSER ? "chromium" : undefined);
  const profileDir = firefoxProfileDir(env);
  if (choice === "firefox" || (choice === undefined && profileDir && isFirefoxDesktop(defaultBrowserDesktopId(env)))) {
    if (!profileDir) throw new Error("SCOOTER_LOGIN_BROWSER=firefox but no Firefox profile was found (profiles.ini missing)");
    return loginWithFirefox(config, env, profileDir);
  }
  return loginWithChromium(config, env);
}

async function loginWithChromium(config, env) {
  const browser = findBrowser(env);
  const stateDir = dirname(config.cookieFile);
  mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  const child = spawn(
    browser,
    [
      `--user-data-dir=${join(stateDir, "browser-profile")}`,
      "--remote-debugging-pipe",
      "--no-first-run",
      "--no-default-browser-check",
      `--app=${config.url}/oauth2/start?rd=%2F`,
    ],
    { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"] },
  );
  const stop = () => {
    child.kill();
    process.exit(1);
  };
  process.once("SIGTERM", stop);
  process.once("SIGHUP", stop);
  const closed = new Promise((_, reject) => {
    child.once("error", (e) => reject(new Error(`Could not start ${browser}: ${e.message}`)));
    child.once("exit", () => reject(new Error("The browser closed before sign-in finished")));
  });
  try {
    const session = await Promise.race([closed, waitForSession(cdpOverPipe(child), config, AbortSignal.timeout(LOGIN_TIMEOUT_MS))]);
    saveCookie(config, session);
  } finally {
    child.kill();
  }
}
