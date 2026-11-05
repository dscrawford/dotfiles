import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const FIREFOX_LIKE = /firefox|librewolf|floorp|waterfox|zen/i;

export const isFirefoxDesktop = (desktopId) => FIREFOX_LIKE.test(desktopId ?? "");

function parseIni(text) {
  const sections = [];
  let current;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith(";") || line.startsWith("#")) continue;
    const header = line.match(/^\[(.+)\]$/);
    if (header) {
      current = { name: header[1], values: {} };
      sections.push(current);
      continue;
    }
    const eq = line.indexOf("=");
    if (eq > 0 && current) current.values[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return sections;
}

export function firefoxRoot(env = process.env) {
  const home = env.HOME ?? homedir();
  return process.platform === "darwin" ? join(home, "Library", "Application Support", "Firefox") : join(home, ".mozilla", "firefox");
}

/** The profile Firefox opens by default, from profiles.ini; undefined when Firefox has never run. */
export function firefoxProfileDir(env = process.env) {
  const root = firefoxRoot(env);
  const ini = join(root, "profiles.ini");
  if (!existsSync(ini)) return undefined;
  const sections = parseIni(readFileSync(ini, "utf8"));
  const installed = sections.find((s) => s.name.startsWith("Install") && s.values.Default);
  if (installed) return join(root, installed.values.Default);
  const profiles = sections.filter((s) => s.name.startsWith("Profile")).map((s) => s.values);
  const profile = profiles.find((p) => p.Default === "1") ?? profiles[0];
  if (!profile?.Path) return undefined;
  return profile.IsRelative === "0" ? profile.Path : join(root, profile.Path);
}

/** Cookies set for exactly HOST, read from a copy of the profile's cookies.sqlite so Firefox's own lock doesn't matter. */
export function firefoxCookies(profileDir, host) {
  const source = join(profileDir, "cookies.sqlite");
  if (!existsSync(source)) return [];
  const dir = mkdtempSync(join(tmpdir(), "scooter-cookies-"));
  try {
    for (const suffix of ["", "-wal"]) {
      if (existsSync(source + suffix)) copyFileSync(source + suffix, join(dir, "cookies.sqlite" + suffix));
    }
    const db = new DatabaseSync(join(dir, "cookies.sqlite"));
    try {
      return db.prepare("SELECT name, value FROM moz_cookies WHERE host = ?").all(host);
    } finally {
      db.close();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
