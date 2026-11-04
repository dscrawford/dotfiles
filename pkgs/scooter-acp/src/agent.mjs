import { INVALID_PARAMS, RpcError } from "./jsonrpc.mjs";
import { registerLinks, titleWithLinks } from "./links.mjs";
import { promptImages } from "./images.mjs";
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

// The web UI's byStarredThenRecent.
export function sidebarOrder(a, b) {
  return (b.starred ? 1 : 0) - (a.starred ? 1 : 0) || (b.lastActivityAt ?? 0) - (a.lastActivityAt ?? 0);
}

// What a web UI sidebar row shows next to the title: the star and the status
// dot. "Unread" is tracked per browser, so the server can't report it.
export function sidebarState(r) {
  let state = null;
  if (r.awaitingInputAt) state = "waiting";
  else if (r.runStartedAt) state = "working";
  else if (["failed", "suspended", "ended"].includes(r.status)) state = r.status;
  else if (r.status === "running") state = "idle";
  return { title: r.title || r.id, starred: !!r.starred, state, sources: r.sources ?? [], visibility: r.visibility ?? "shared" };
}

export function registerAgent({ peer, client, config, log, version }) {
  const sessions = new Map();
  const links = registerLinks({ peer, client, log });

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
    void links.watch(sessionId);
    return { configOptions: await configOptions(sessionId, s.model) };
  };

  peer.on("initialize", async () => ({
    protocolVersion: 1,
    agentInfo: { name: "scooter-acp", title: `Scooter (${new URL(config.url).host})`, version },
    agentCapabilities: {
      loadSession: true,
      promptCapabilities: { embeddedContext: true, image: true },
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
    void links.watch(conv.id);
    return { sessionId: conv.id, configOptions: await configOptions(conv.id, s.model) };
  });

  // The same rows, in the same order, as the web UI's sidebar: the caller's
  // scope, no subagents, starred first, then most recently active. A Scooter
  // conversation has no local directory, so the requested cwd is only echoed.
  peer.on("session/list", async ({ cursor, cwd }) => {
    const rows = (await client.listConversations()).filter((r) => !r.parentId).sort(sidebarOrder);
    const offset = Number(cursor ?? 0) || 0;
    const page = rows.slice(offset, offset + PAGE_SIZE);
    return {
      sessions: page.map((r) => ({
        sessionId: r.id,
        cwd: cwd ?? "/workspace",
        title: titleWithLinks(r),
        ...(r.lastActivityAt ? { updatedAt: new Date(r.lastActivityAt).toISOString() } : {}),
        _meta: { scooter: sidebarState(r) },
      })),
      ...(offset + PAGE_SIZE < rows.length ? { nextCursor: String(offset + PAGE_SIZE) } : {}),
    };
  });

  peer.on("session/load", ({ sessionId }) => open(sessionId, { replay: true }));
  peer.on("session/resume", ({ sessionId }) => open(sessionId, { replay: false }));

  peer.on("session/prompt", async ({ sessionId, prompt }) => {
    const text = promptText(prompt);
    const images = promptImages(prompt, config.imageMaxBytes);
    if (!text.trim() && !images.length) throw new RpcError(INVALID_PARAMS, "empty prompt");
    return session(sessionId).prompt(text, images);
  });

  peer.on("_session/steering", async ({ sessionId, prompt }) => session(sessionId).steer(promptText(prompt), promptImages(prompt, config.imageMaxBytes)));

  peer.on("_scooter/answer", async ({ sessionId, toolCallId, answers }) => session(sessionId).answer(toolCallId, answers));

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
    links.unwatch(sessionId);
    return {};
  });

  return {
    closeAll() {
      for (const s of sessions.values()) s.close();
      sessions.clear();
      links.stop();
    },
    sessions,
  };
}
