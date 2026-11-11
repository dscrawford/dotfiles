// A fake Scooter for the agent-shell e2e (emacs-e2e.sh): the slice of the HTTP
// API scooter-mode uses, with an integrity-checksummed event log per conversation.
import { createHash } from "node:crypto";
import { createServer } from "node:http";

const EMPTY = "0".repeat(64);

function canonical(event) {
  const sorted = {};
  for (const k of Object.keys(event).sort()) sorted[k] = event[k];
  return JSON.stringify(sorted);
}

export function startFakeScooter({ cookie = "__Host-scooter_oauth2=good", refreshTo } = {}) {
  const convs = new Map();
  const requests = [];
  const listStreams = new Set();
  const assets = new Map();
  let script = () => [];
  let routes = () => undefined;

  const conv = (id) => {
    if (!convs.has(id)) convs.set(id, { id, title: id, events: [], checksums: [], streams: new Set(), lastActivityAt: Date.now(), model: null, links: [] });
    return convs.get(id);
  };

  const append = (id, event) => {
    const c = conv(id);
    const prev = c.checksums.at(-1) ?? EMPTY;
    const checksum = createHash("sha256").update(prev).update(canonical(event)).digest("hex");
    c.events.push(event);
    c.checksums.push(checksum);
    for (const s of c.streams) s.write(`data: ${JSON.stringify({ kind: "event", event, prevChecksum: prev, checksum })}\n\n`);
  };

  const SIDEBAR = ["starred", "status", "visibility", "runStartedAt", "awaitingInputAt", "lastReplyAt"];
  const row = (c) => ({ id: c.id, title: c.title, lastActivityAt: c.lastActivityAt, parentId: c.parentId, ...Object.fromEntries(SIDEBAR.filter((k) => c[k] !== undefined).map((k) => [k, c[k]])), sources: [...new Set(c.links.map((l) => l.source))].sort(), links: c.links });

  const addLink = (id, link) => {
    const c = conv(id);
    c.links.push(link);
    for (const s of listStreams) s.write(`data: ${JSON.stringify({ kind: "upsert", conversation: row(c) })}\n\n`);
  };

  const body = (req) =>
    new Promise((resolve) => {
      let b = "";
      req.on("data", (d) => (b += d));
      req.on("end", () => resolve(b ? JSON.parse(b) : {}));
    });

  const json = (res, status, value, headers = {}) => {
    res.writeHead(status, { "Content-Type": "application/json", ...headers });
    res.end(JSON.stringify(value));
  };

  const server = createServer(async (req, res) => {
    const url = new URL(req.url, "http://x");
    const parts = url.pathname.split("/").filter(Boolean);
    const entry = { method: req.method, path: url.pathname + url.search, headers: req.headers };
    requests.push(entry);
    if (req.headers.cookie !== cookie && req.headers.cookie !== refreshTo) return json(res, 401, { error: "no session" });
    const refresh = refreshTo && req.headers.cookie !== refreshTo ? { "Set-Cookie": `${refreshTo}; Path=/; HttpOnly` } : {};
    const routed = await routes({ method: req.method, path: url.pathname, body: async () => (entry.body = await body(req)) });
    if (routed) return json(res, routed.status ?? 200, routed.json);

    if (req.method === "GET" && url.pathname === "/whoami") return json(res, 200, { id: "me" });
    if (req.method === "GET" && url.pathname === "/conversations") {
      return json(res, 200, [...convs.values()].map(row), refresh);
    }
    if (req.method === "GET" && url.pathname === "/conversations/events") {
      res.writeHead(200, { "Content-Type": "text/event-stream" });
      res.write(`data: ${JSON.stringify({ kind: "snapshot", conversations: [...convs.values()].map(row) })}\n\n`);
      listStreams.add(res);
      req.on("close", () => listStreams.delete(res));
      return;
    }
    if (req.method === "POST" && url.pathname === "/conversations") {
      const c = conv(`c${convs.size + 1}`);
      return json(res, 201, { id: c.id, model: null });
    }
    if (req.method === "GET" && url.pathname === "/models") {
      return json(res, 200, { default: "sonnet", available: ["sonnet", "opus"] });
    }
    if (parts[0] === "conversations" && parts[1]) {
      if (!convs.has(parts[1])) return json(res, 404, { error: "not found" });
      const c = conv(parts[1]);
      const tail = parts.slice(2).join("/");
      if (req.method === "GET" && tail === "") return json(res, 200, { id: c.id, model: c.model });
      if (req.method === "GET" && tail === "links") return json(res, 200, { links: c.links });
      if (req.method === "GET" && tail === "history") return json(res, 200, { events: c.events, checksum: c.checksums.at(-1) ?? EMPTY });
      if (req.method === "GET" && tail === "events.integrity") {
        res.writeHead(200, { "Content-Type": "text/event-stream" });
        res.write(`data: ${JSON.stringify({ kind: "event", event: { type: "MESSAGES_SNAPSHOT", messages: [] } })}\n\n`);
        res.write(`data: ${JSON.stringify({ kind: "synced" })}\n\n`);
        c.streams.add(res);
        req.on("close", () => c.streams.delete(res));
        return;
      }
      if (req.method === "POST" && tail === "cancel") {
        entry.body = await body(req);
        return json(res, 202, { ok: true });
      }
      if (req.method === "GET" && assets.has(url.pathname)) {
        const a = assets.get(url.pathname);
        res.writeHead(200, { "Content-Type": a.mimeType, "Content-Length": String(a.data.length) });
        return res.end(a.data);
      }
      if (req.method === "POST" && tail === "messages") {
        // scooter acp sends prompts here unless it carries a model pick or images.
        entry.body = await body(req);
        json(res, 202, { ok: true });
        const events = script({ threadId: c.id, messages: [{ role: "user", content: entry.body.text }] }, req.headers) ?? [];
        for (const e of events) append(c.id, e);
        return;
      }
      if (req.method === "GET" && tail === "web-services") return json(res, 200, { services: c.services ?? [] });
      const svc = tail.match(/^web-services\/([^/]+)\/(start|stop)$/);
      if (req.method === "POST" && svc) {
        const s = (c.services ?? []).find((x) => x.name === decodeURIComponent(svc[1]));
        if (!s) return json(res, 404, { error: "unknown web service" });
        s.running = svc[2] === "start";
        return json(res, 202, { ok: true });
      }
    }
    if (req.method === "POST" && url.pathname === "/agui") {
      entry.body = await body(req);
      res.writeHead(200, { "Content-Type": "text/event-stream" });
      const events = script(entry.body, req.headers) ?? [];
      for (const e of events) {
        append(entry.body.threadId, e);
        res.write(`data: ${JSON.stringify(e)}\n\n`);
      }
      res.end();
      return;
    }
    json(res, 404, { error: "no route" });
  });

  return new Promise((resolve) =>
    server.listen(0, "127.0.0.1", () =>
      resolve({
        url: `http://127.0.0.1:${server.address().port}`,
        requests,
        conv,
        append,
        setScript: (fn) => (script = fn),
        addLink,
        listStreamCount: () => listStreams.size,
        setRoutes: (fn) => (routes = fn),
        addAsset: (id, assetId, mimeType, data) => {
          const path = `/conversations/${id}/assets/${assetId}`;
          assets.set(path, { mimeType, data });
          return path;
        },
        dropStreams: () => {
          for (const c of convs.values()) for (const s of c.streams) s.destroy();
        },
        streamCount: (id) => conv(id).streams.size,
        close: () => {
          for (const c of convs.values()) for (const s of c.streams) s.end();
          for (const s of listStreams) s.end();
          server.closeAllConnections?.();
          return new Promise((r) => server.close(r));
        },
      }),
    ),
  );
}
