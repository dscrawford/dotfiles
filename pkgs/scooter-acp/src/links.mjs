import { sseFrames } from "./scooter.mjs";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const key = (l) => [l.source, l.resourceType, l.url ?? "", l.title ?? ""].join("\u0000");

export const linkLabel = (l) => l.title || `${l.source} ${String(l.resourceType ?? "").replace(/_/g, " ")}`;

const labelled = (links) => links.map((l) => ({ ...l, label: linkLabel(l) }));

export function titleWithLinks(row) {
  const title = row.title || row.id;
  const sources = row.sources?.length ? row.sources : [...new Set((row.links ?? []).map((l) => l.source))];
  return sources.length ? `${title} [${sources.join(", ")}]` : title;
}

export function registerLinks({ peer, client, log, backoffMs = [1000, 2000, 5000, 15000, 60000] }) {
  const known = new Map();
  let controller;

  const seen = (id, links) => {
    const before = known.get(id);
    if (!before) return;
    const keys = new Set(links.map(key));
    known.set(id, keys);
    const added = links.filter((l) => !before.has(key(l)));
    if (added.length) peer.notify("_scooter/links_changed", { sessionId: id, added: labelled(added), links: labelled(links) });
  };

  const run = async (signal) => {
    let attempt = 0;
    while (!signal.aborted) {
      try {
        const res = await client.openListStream(signal);
        if (res.status === 404) {
          await res.body?.cancel();
          log("no /conversations/events; live link notices are off");
          return;
        }
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        for await (const frame of sseFrames(res.body)) {
          attempt = 0;
          if (frame.kind === "snapshot") for (const c of frame.conversations ?? []) seen(c.id, c.links ?? []);
          else if (frame.kind === "upsert" && frame.conversation) seen(frame.conversation.id, frame.conversation.links ?? []);
        }
      } catch (e) {
        if (signal.aborted) return;
        log("conversation list stream dropped", e?.message ?? e);
      }
      await sleep(backoffMs[Math.min(attempt++, backoffMs.length - 1)]);
    }
  };

  const stop = () => {
    controller?.abort();
    controller = undefined;
  };

  peer.on("_scooter/links", async ({ sessionId }) => ({ links: labelled(await client.links(sessionId)) }));

  return {
    async watch(id) {
      const links = await client.links(id).catch(() => null);
      if (!links) return;
      known.set(id, new Set(links.map(key)));
      if (!controller) {
        controller = new AbortController();
        void run(controller.signal);
      }
    },
    unwatch(id) {
      known.delete(id);
      if (!known.size) stop();
    },
    stop,
  };
}
