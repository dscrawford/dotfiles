import { INVALID_PARAMS, RpcError } from "./jsonrpc.mjs";

const PREFIX = "_scooter/sandbox/";

function serverMessage(body) {
  try {
    return JSON.parse(body).error ?? body;
  } catch {
    return body;
  }
}

function plainError(e, action) {
  const status = e?.data?.status;
  if (status === 409) return new RpcError(-32000, serverMessage(e.data.body));
  if (status === 500 && action === "suspend") {
    return new RpcError(-32000, "Scooter could not suspend the sandbox (HTTP 500); it is probably busy with a run, try again once it finishes");
  }
  return e;
}

export function registerSandbox({ peer, client, sessions }) {
  const path = (id, tail = "") => `/conversations/${encodeURIComponent(id)}${tail}`;
  const orNull = (p) => p.catch(() => null);

  const refuseWhileRunning = (id) => {
    if (sessions.get(id)?.busy()) throw new RpcError(-32000, "a turn is running; cancel the turn first (C-c C-c)");
  };

  const resync = async (id) => {
    await sessions.get(id)?.resync();
  };

  const handlers = {
    status: async ({ sessionId }) => {
      const [conversation, resources, ready, sizes] = await Promise.all([
        client.request("GET", path(sessionId)),
        orNull(client.request("GET", path(sessionId, "/resources"))),
        orNull(client.request("GET", path(sessionId, "/ready"))),
        orNull(client.request("GET", "/sandbox-sizes")),
      ]);
      return { conversation, resources, ready, sizes, running: sessions.get(sessionId)?.busy() ?? false };
    },
    resize: ({ sessionId, size }) => {
      if (typeof size !== "string" || !size) throw new RpcError(INVALID_PARAMS, "size must be a preset name");
      return client.request("PATCH", path(sessionId, "/size"), { size });
    },
    suspend: ({ sessionId }) => {
      refuseWhileRunning(sessionId);
      return client.request("POST", path(sessionId, "/suspend"), {});
    },
    resume: async ({ sessionId }) => {
      const res = await client.request("POST", path(sessionId, "/resume"), {});
      await resync(sessionId);
      return res;
    },
    restart: async ({ sessionId }) => {
      refuseWhileRunning(sessionId);
      const res = await client.request("POST", path(sessionId, "/restart"), {});
      await resync(sessionId);
      return res;
    },
    compact: async ({ sessionId }) => {
      refuseWhileRunning(sessionId);
      const res = await client.request("POST", path(sessionId, "/compact"), {});
      await resync(sessionId);
      return res;
    },
    rename: ({ sessionId, title }) => {
      if (typeof title !== "string" || !title.trim()) throw new RpcError(INVALID_PARAMS, "title must not be empty");
      return client.request("PATCH", path(sessionId, "/title"), { title: title.trim() });
    },
    star: ({ sessionId, starred }) => client.request("PATCH", path(sessionId, "/starred"), { starred: starred === true }),
    visibility: async ({ sessionId, visibility }) => {
      if (visibility !== "shared" && visibility !== "private") throw new RpcError(INVALID_PARAMS, "visibility must be shared or private");
      const current = (await client.request("GET", path(sessionId)))?.visibility ?? "shared";
      const confirm = current === "private" && visibility === "shared";
      return client.request("PATCH", path(sessionId, "/visibility"), { visibility, ...(confirm ? { confirm: true } : {}) });
    },
  };

  for (const [action, handler] of Object.entries(handlers)) {
    peer.on(PREFIX + action, async (params = {}) => {
      if (!params.sessionId) throw new RpcError(INVALID_PARAMS, "sessionId is required");
      try {
        return await handler(params);
      } catch (e) {
        throw plainError(e, action);
      }
    });
  }
}
