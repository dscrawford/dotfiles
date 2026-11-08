import { readFileSync, writeFileSync } from "node:fs";

import { readCapped } from "./images.mjs";
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
    imageMaxBytes: Number(env.SCOOTER_IMAGE_MAX_BYTES ?? 5 * 1024 * 1024),
    requestTimeoutMs: Number(env.SCOOTER_REQUEST_TIMEOUT_MS ?? 15000),
    loginTimeoutMs: Number(env.SCOOTER_LOGIN_TIMEOUT_MS ?? 6 * 60 * 1000),
    tunnelTimeoutMs: Number(env.SCOOTER_TUNNEL_TIMEOUT_MS ?? 90000),
  };
}

function cookieFromFile(path) {
  let raw;
  try {
    raw = readFileSync(path, "utf8").trim();
  } catch (e) {
    if (e.code === "ENOENT") return undefined;
    throw e;
  }
  return raw.includes("=") ? raw : `_oauth2_proxy=${raw}`;
}

const isSignInPage = (res) => res.ok && (res.headers.get("content-type") ?? "").startsWith("text/html");
const isRefused = (res) => res.status === 401 || res.status === 403 || (res.status >= 300 && res.status < 400) || isSignInPage(res);

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

/**
 * reauthenticate() asks for a new cookie in config.cookieFile and resolves once it is there.
 * A refused request re-reads the file, then signs in once for every caller refused meanwhile.
 * After a declined sign-in, background streams only re-read the file until a request asks again.
 */
export function createScooterClient(config, { fetchImpl = fetch, log = () => {}, reauthenticate } = {}) {
  const fromFile = !config.cookie && config.cookieFile;
  let cookie = config.cookie ?? (config.cookieFile ? cookieFromFile(config.cookieFile) : undefined);
  let signingIn;
  let declined = false;

  const reloadCookie = () => {
    if (!fromFile) return;
    try {
      cookie = cookieFromFile(config.cookieFile);
    } catch (e) {
      log("could not re-read the cookie file", e.message);
    }
  };

  const signIn = (reason, background) => {
    if (!signingIn && reauthenticate && fromFile && !(background && declined)) {
      log("session refused, asking the client to sign in:", reason);
      signingIn = Promise.resolve()
        .then(() => reauthenticate({ reason, cookieFile: config.cookieFile, url: config.url }))
        .then(
          () => true,
          (e) => (log("sign-in did not finish:", e?.message ?? e), false),
        )
        .then((ok) => {
          declined = !ok;
          signingIn = undefined;
          reloadCookie();
          return ok;
        });
    }
    return signingIn ?? Promise.resolve(false);
  };

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

  const send = async (method, path, { body, signal, extraHeaders, stream }) => {
    const deadline = stream ? undefined : AbortSignal.timeout(config.requestTimeoutMs);
    let res;
    try {
      res = await fetchImpl(config.url + path, {
        method,
        headers: headers({ ...(body !== undefined ? { "Content-Type": "application/json" } : {}), ...extraHeaders }),
        body: body !== undefined ? JSON.stringify(body) : undefined,
        redirect: "manual",
        signal: signal ?? deadline,
      });
    } catch (e) {
      if (deadline?.aborted) {
        throw new RpcError(-32000, `Scooter ${method} ${path} did not answer within ${config.requestTimeoutMs}ms (${config.url})`);
      }
      throw new RpcError(-32000, `Scooter ${method} ${path} unreachable: ${e?.cause?.message ?? e?.message ?? e} (${config.url})`);
    }
    keepRefreshedCookie(res);
    return res;
  };

  const call = async (method, path, { background = false, ...opts } = {}) => {
    opts.stream ??= Boolean(opts.signal);
    const sent = cookie;
    let res = await send(method, path, opts);
    if (!isRefused(res)) return res;
    await res.body?.cancel();
    reloadCookie();
    if (cookie === sent) await signIn(`Scooter refused ${method} ${path} (HTTP ${res.status})`, background);
    if (cookie !== sent && !opts.signal?.aborted) {
      res = await send(method, path, opts);
      if (!isRefused(res)) {
        declined = false;
        return res;
      }
      await res.body?.cancel();
    }
    throw new RpcError(
      AUTH_REQUIRED,
      `Scooter refused ${method} ${path} (HTTP ${res.status}); refresh the session cookie in ${config.cookieFile ?? "SCOOTER_COOKIE"}`,
    );
  };

  const json = async (method, path, opts) => {
    const res = await call(method, path, opts);
    const text = await res.text();
    if (!res.ok) throw new RpcError(-32000, `Scooter ${method} ${path} failed: HTTP ${res.status} ${text.slice(0, 200)}`, { status: res.status, body: text });
    return text ? JSON.parse(text) : null;
  };

  const fireAndForget = async (path, body, extraHeaders) => {
    const res = await call("POST", path, { body, extraHeaders });
    await res.body?.cancel();
    if (!res.ok) throw new RpcError(-32000, `Scooter POST ${path} failed: HTTP ${res.status}`);
  };

  const conv = (id) => `/conversations/${encodeURIComponent(id)}`;

  return {
    reloadCookie,
    authHeaders: () => headers(),
    checkAuth: async () => {
      const res = await fetchImpl(`${config.url}/conversations?scope=${encodeURIComponent(config.scope)}`, {
        headers: headers(),
        redirect: "manual",
        signal: AbortSignal.timeout(config.requestTimeoutMs),
      });
      keepRefreshedCookie(res);
      await res.body?.cancel();
      return !isRefused(res);
    },
    request: (method, path, body) => json(method, path, { body }),
    listConversations: () => json("GET", `/conversations?scope=${encodeURIComponent(config.scope)}`),
    getConversation: (id) => json("GET", conv(id)),
    createConversation: (body) => json("POST", "/conversations", { body }),
    history: (id) => json("GET", `${conv(id)}/history`),
    webServices: (id) => json("GET", `${conv(id)}/web-services?refresh=1`),
    webServiceAction: (id, name, action) => json("POST", `${conv(id)}/web-services/${encodeURIComponent(name)}/${action}`),
    models: (id) => json("GET", `/models${id ? `?conversation=${encodeURIComponent(id)}` : ""}`),
    sendPrompt: async (id, text, model, { images = [], priority } = {}) => {
      const content = images.length ? [...(text ? [{ type: "text", text }] : []), ...images] : text;
      const res = await call("POST", "/agui", {
        body: { threadId: id, runId: crypto.randomUUID(), messages: [{ id: crypto.randomUUID(), role: "user", content }], ...(priority ? { priority } : {}) },
        extraHeaders: model ? { "X-Agent-Model": model } : undefined,
        stream: true,
      });
      if (!res.ok) {
        await res.body?.cancel();
        throw new RpcError(-32000, `Scooter refused the prompt: HTTP ${res.status}`);
      }
      return res;
    },
    resume: (id, interruptId, entry) =>
      fireAndForget("/agui", { threadId: id, runId: crypto.randomUUID(), messages: [], resume: [{ interruptId, ...entry }] }),
    asset: async (path) => {
      const res = await call("GET", path, { extraHeaders: { Accept: "image/*" } });
      if (!res.ok) {
        await res.body?.cancel();
        throw new Error(`HTTP ${res.status}`);
      }
      const mimeType = (res.headers.get("content-type") ?? "").split(";")[0].trim();
      if (!mimeType.startsWith("image/")) {
        await res.body?.cancel();
        throw new Error(`not an image (${mimeType || "no content type"})`);
      }
      return { mimeType, data: (await readCapped(res, config.imageMaxBytes)).toString("base64") };
    },
    steer: (id, text) => json("POST", `${conv(id)}/messages`, { body: { text } }),
    cancel: (id) => json("POST", `${conv(id)}/cancel`, { body: {} }),
    openIntegrityStream: (id, signal) => call("GET", `${conv(id)}/events.integrity`, { signal, background: true, extraHeaders: { Accept: "text/event-stream" } }),
    links: async (id) => (await json("GET", `${conv(id)}/links`))?.links ?? [],
    openListStream: (signal) =>
      call("GET", `/conversations/events?scope=${encodeURIComponent(config.scope)}`, { signal, background: true, extraHeaders: { Accept: "text/event-stream" } }),
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
