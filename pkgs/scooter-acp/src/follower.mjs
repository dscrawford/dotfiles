import { sseFrames } from "./scooter.mjs";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function createFollower({ client, id, onEvents, onGone = () => {}, log = () => {}, backoffMs = [500, 1000, 2000, 5000, 10000] }) {
  let count = 0;
  let checksum;
  let frameSeq = 0;
  let coveredThrough = 0;
  let stopped = false;
  let queue = Promise.resolve();
  const controller = new AbortController();

  const serialize = (fn) => {
    queue = queue.then(fn).catch((e) => log("follower step failed", id, e?.message ?? e));
    return queue;
  };

  const catchUp = async (replay) => {
    coveredThrough = frameSeq;
    const { events, checksum: through } = await client.history(id);
    const fresh = events.length >= count ? events.slice(count) : [];
    count = events.length;
    checksum = through;
    if (fresh.length) await onEvents(fresh, { replay });
  };

  const onFrame = async (frame, seq) => {
    if (frame.kind !== "event" || !frame.event) return;
    if (seq <= coveredThrough) return;
    if (frame.prevChecksum === checksum) {
      count += 1;
      checksum = frame.checksum;
      await onEvents([frame.event], { replay: false });
      return;
    }
    await catchUp(false);
  };

  const run = async () => {
    let attempt = 0;
    while (!stopped) {
      try {
        const res = await client.openIntegrityStream(id, controller.signal);
        if (res.status === 404) {
          await res.body?.cancel();
          stopped = true;
          onGone();
          return;
        }
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        let synced = false;
        for await (const frame of sseFrames(res.body)) {
          if (stopped) break;
          if (!synced) {
            if (frame.kind === "synced") {
              synced = true;
              attempt = 0;
              serialize(() => catchUp(false));
            }
            continue;
          }
          const seq = ++frameSeq;
          serialize(() => onFrame(frame, seq));
        }
      } catch (e) {
        if (stopped) return;
        log("integrity stream dropped", id, e?.message ?? e);
      }
      if (stopped) return;
      await sleep(backoffMs[Math.min(attempt++, backoffMs.length - 1)]);
    }
  };

  return {
    async start({ replay }) {
      await serialize(() => catchUp(replay));
      void run();
    },
    stop() {
      stopped = true;
      controller.abort();
    },
    resync: () => serialize(() => catchUp(false)),
    settled: () => queue,
  };
}
