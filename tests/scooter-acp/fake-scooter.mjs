import { createHash } from "node:crypto";
import { createServer } from "node:http";

const EMPTY = "0".repeat(64);

function canonical(event) {
  const sorted = {};
  for (const k of Object.keys(event).sort()) sorted[k] = event[k];
  return JSON.stringify(sorted);
}

export function startFakeScooter({ cookie = "_oauth2_proxy=good", refreshTo } = {}) {
  const convs = new Map();
  const requests = [];
  let script = () => [];

  const conv = (id) => {
    if (!convs.has(id)) convs.set(id, { id, title: id, events: [], checksums: [], streams: new Set(), lastActivityAt: Date.now(), model: null });
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

    if (req.method === "GET" && url.pathname === "/conversations") {
      return json(res, 200, [...convs.values()].map((c) => ({ id: c.id, title: c.title, lastActivityAt: c.lastActivityAt, parentId: c.parentId })), refresh);
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
      if (req.method === "POST" && tail === "messages") {
        entry.body = await body(req);
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
        dropStreams: () => {
          for (const c of convs.values()) for (const s of c.streams) s.destroy();
        },
        streamCount: (id) => conv(id).streams.size,
        close: () => {
          for (const c of convs.values()) for (const s of c.streams) s.end();
          server.closeAllConnections?.();
          return new Promise((r) => server.close(r));
        },
      }),
    ),
  );
}
