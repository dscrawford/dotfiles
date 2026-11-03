import { readFileSync, writeFileSync } from "node:fs";

import { AUTH_REQUIRED, RpcError } from "./jsonrpc.mjs";

export function readConfig(env = process.env) {
  const url = (env.SCOOTER_URL ?? "").replace(/\/+$/, "");
  if (!url) throw new Error("SCOOTER_URL is not set");
  return {
    url,
    cookie: env.SCOOTER_COOKIE?.trim() || undefined,
    cookieFile: env.SCOOTER_COOKIE_FILE || undefined,
    bearer: env.SCOOTER_TOKEN?.trim() || undefined,
    scope: env.SCOOTER_LIST_SCOPE || "mine",
    replayTurns: Number(env.SCOOTER_REPLAY_TURNS ?? 30),
  };
}

function cookieFromFile(path) {
  const raw = readFileSync(path, "utf8").trim();
  return raw.includes("=") ? raw : `_oauth2_proxy=${raw}`;
}

function mergeSetCookies(cookie, setCookies) {
  const jar = new Map(
    (cookie ?? "")
      .split(";")
      .map((c) => c.trim())
      .filter(Boolean)
      .map((c) => [c.slice(0, c.indexOf("=")), c.slice(c.indexOf("=") + 1)]),
  );
  for (const sc of setCookies) {
    const pair = sc.split(";")[0];
    const eq = pair.indexOf("=");
    if (eq > 0) jar.set(pair.slice(0, eq).trim(), pair.slice(eq + 1));
  }
  return [...jar].map(([k, v]) => `${k}=${v}`).join("; ");
}

export function createScooterClient(config, { fetchImpl = fetch, log = () => {} } = {}) {
  let cookie = config.cookie ?? (config.cookieFile ? cookieFromFile(config.cookieFile) : undefined);

  const headers = (extra = {}) => ({
    ...(cookie ? { Cookie: cookie } : {}),
    ...(config.bearer ? { Authorization: `Bearer ${config.bearer}` } : {}),
    ...extra,
  });

  const keepRefreshedCookie = (res) => {
    const set = res.headers.getSetCookie?.() ?? [];
    if (!set.length || !cookie) return;
    const merged = mergeSetCookies(cookie, set);
    if (merged === cookie) return;
    cookie = merged;
    if (config.cookieFile) {
      try {
        writeFileSync(config.cookieFile, cookie + "\n", { mode: 0o600 });
      } catch (e) {
        log("could not persist refreshed cookie", e.message);
      }
    }
  };

  const call = async (method, path, { body, signal, extraHeaders } = {}) => {
    const res = await fetchImpl(config.url + path, {
      method,
      headers: headers({ ...(body !== undefined ? { "Content-Type": "application/json" } : {}), ...extraHeaders }),
      body: body !== undefined ? JSON.stringify(body) : undefined,
      redirect: "manual",
      signal,
    });
    keepRefreshedCookie(res);
    if (res.status === 401 || res.status === 403 || (res.status >= 300 && res.status < 400)) {
      await res.body?.cancel();
      throw new RpcError(
        AUTH_REQUIRED,
        `Scooter refused ${method} ${path} (HTTP ${res.status}); refresh the session cookie in ${config.cookieFile ?? "SCOOTER_COOKIE"}`,
      );
    }
    return res;
  };

  const json = async (method, path, opts) => {
    const res = await call(method, path, opts);
    const text = await res.text();
    if (!res.ok) throw new RpcError(-32000, `Scooter ${method} ${path} failed: HTTP ${res.status} ${text.slice(0, 200)}`);
    return text ? JSON.parse(text) : null;
  };

  const fireAndForget = async (path, body, extraHeaders) => {
    const res = await call("POST", path, { body, extraHeaders });
    await res.body?.cancel();
    if (!res.ok) throw new RpcError(-32000, `Scooter POST ${path} failed: HTTP ${res.status}`);
  };

  const conv = (id) => `/conversations/${encodeURIComponent(id)}`;

  return {
    listConversations: () => json("GET", `/conversations?scope=${encodeURIComponent(config.scope)}`),
    getConversation: (id) => json("GET", conv(id)),
    createConversation: (body) => json("POST", "/conversations", { body }),
    history: (id) => json("GET", `${conv(id)}/history`),
    models: (id) => json("GET", `/models${id ? `?conversation=${encodeURIComponent(id)}` : ""}`),
    sendPrompt: async (id, text, model) => {
      const res = await call("POST", "/agui", {
        body: { threadId: id, runId: crypto.randomUUID(), messages: [{ id: crypto.randomUUID(), role: "user", content: text }] },
        extraHeaders: model ? { "X-Agent-Model": model } : undefined,
      });
      if (!res.ok) {
        await res.body?.cancel();
        throw new RpcError(-32000, `Scooter refused the prompt: HTTP ${res.status}`);
      }
      return res;
    },
    resume: (id, interruptId, entry) =>
      fireAndForget("/agui", { threadId: id, runId: crypto.randomUUID(), messages: [], resume: [{ interruptId, ...entry }] }),
    steer: (id, text) => json("POST", `${conv(id)}/messages`, { body: { text } }),
    cancel: (id) => json("POST", `${conv(id)}/cancel`, { body: {} }),
    openIntegrityStream: (id, signal) => call("GET", `${conv(id)}/events.integrity`, { signal, extraHeaders: { Accept: "text/event-stream" } }),
  };
}

export async function* sseFrames(body) {
  const decoder = new TextDecoder();
  let buf = "";
  for await (const chunk of body) {
    buf += decoder.decode(chunk, { stream: true });
    let sep;
    while ((sep = buf.search(/\r?\n\r?\n/)) >= 0) {
      const block = buf.slice(0, sep);
      buf = buf.slice(sep).replace(/^\r?\n\r?\n/, "");
      const data = block
        .split(/\r?\n/)
        .filter((l) => l.startsWith("data:"))
        .map((l) => l.slice(5).replace(/^ /, ""))
        .join("\n");
      if (!data) continue;
      try {
        yield JSON.parse(data);
      } catch {
        continue;
      }
    }
  }
}
