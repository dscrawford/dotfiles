import { INVALID_PARAMS, RpcError } from "./jsonrpc.mjs";
import { createSession } from "./session.mjs";

const PAGE_SIZE = 50;

function promptText(blocks = []) {
  return blocks
    .map((b) => {
      if (b.type === "text") return b.text;
      if (b.type === "resource_link") return `[${b.name ?? b.uri}](${b.uri})`;
      if (b.type === "resource" && typeof b.resource?.text === "string") {
        return `\n<context uri="${b.resource.uri}">\n${b.resource.text}\n</context>\n`;
      }
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function modelOption(models, current) {
  const ids = [...new Set([models?.default, ...(models?.available ?? [])].filter(Boolean))];
  if (!ids.length) return [];
  return [
    {
      id: "model",
      name: "Model",
      category: "model",
      type: "select",
      currentValue: current ?? models.default ?? ids[0],
      options: ids.map((value) => ({ value, name: value === models.default ? `${value} (default)` : value })),
    },
  ];
}

export function registerAgent({ peer, client, config, log, version }) {
  const sessions = new Map();

  const session = (sessionId) => {
    const s = sessions.get(sessionId);
    if (!s) throw new RpcError(INVALID_PARAMS, `unknown session ${sessionId}; load it first`);
    return s;
  };

  const configOptions = async (id, model) => modelOption(await client.models(id).catch(() => null), model);

  const open = async (sessionId, { replay }) => {
    sessions.get(sessionId)?.close();
    const conv = await client.getConversation(sessionId);
    const s = createSession({ id: sessionId, client, peer, config, log, model: conv?.model ?? undefined });
    sessions.set(sessionId, s);
    await s.attach({ replay });
    return { configOptions: await configOptions(sessionId, s.model) };
  };

  peer.on("initialize", async () => ({
    protocolVersion: 1,
    agentInfo: { name: "scooter-acp", title: `Scooter (${new URL(config.url).host})`, version },
    agentCapabilities: {
      loadSession: true,
      promptCapabilities: { embeddedContext: true },
      sessionCapabilities: { list: {}, resume: {} },
    },
    authMethods: [],
    _meta: { steering: { supported: true } },
  }));

  peer.on("authenticate", async () => ({}));

  peer.on("session/new", async () => {
    const conv = await client.createConversation({});
    const s = createSession({ id: conv.id, client, peer, config, log, model: conv.model ?? undefined });
    sessions.set(conv.id, s);
    await s.attach({ replay: false });
    return { sessionId: conv.id, configOptions: await configOptions(conv.id, s.model) };
  });

  peer.on("session/list", async ({ cursor, cwd }) => {
    const rows = (await client.listConversations())
      .filter((r) => !r.parentId)
      .sort((a, b) => (b.lastActivityAt ?? 0) - (a.lastActivityAt ?? 0));
    const offset = Number(cursor ?? 0) || 0;
    const page = rows.slice(offset, offset + PAGE_SIZE);
    return {
      sessions: page.map((r) => ({
        sessionId: r.id,
        cwd: cwd ?? "/workspace",
        title: r.title || r.id,
        ...(r.lastActivityAt ? { updatedAt: new Date(r.lastActivityAt).toISOString() } : {}),
      })),
      ...(offset + PAGE_SIZE < rows.length ? { nextCursor: String(offset + PAGE_SIZE) } : {}),
    };
  });

  peer.on("session/load", ({ sessionId }) => open(sessionId, { replay: true }));
  peer.on("session/resume", ({ sessionId }) => open(sessionId, { replay: false }));

  peer.on("session/prompt", async ({ sessionId, prompt }) => {
    const text = promptText(prompt);
    if (!text.trim()) throw new RpcError(INVALID_PARAMS, "empty prompt");
    return session(sessionId).prompt(text);
  });

  peer.on("_session/steering", async ({ sessionId, prompt }) => session(sessionId).steer(promptText(prompt)));

  peer.on("session/cancel", async ({ sessionId }) => {
    await sessions.get(sessionId)?.cancel();
  });

  peer.on("session/set_config_option", async ({ sessionId, configId, value }) => {
    const s = session(sessionId);
    if (configId !== "model") throw new RpcError(INVALID_PARAMS, `unknown config option ${configId}`);
    s.model = value;
    return { configOptions: await configOptions(sessionId, value) };
  });

  peer.on("session/set_model", async ({ sessionId, modelId }) => {
    session(sessionId).model = modelId;
    return {};
  });

  peer.on("session/close", async ({ sessionId }) => {
    sessions.get(sessionId)?.close();
    sessions.delete(sessionId);
    return {};
  });

  return {
    closeAll() {
      for (const s of sessions.values()) s.close();
      sessions.clear();
    },
    sessions,
  };
}
