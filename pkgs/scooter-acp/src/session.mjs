import { createFollower } from "./follower.mjs";
import { hasPendingImages, resolveImages } from "./images.mjs";
import { sseFrames } from "./scooter.mjs";
import { createTranslator, userTurnStarts } from "./translate.mjs";

const PRIORITY_INTERRUPT = 10;

const isExt = (e) => typeof e.runId === "string" && e.runId.startsWith("ext-");

export function createSession({ id, client, peer, config, log, model }) {
  const translate = createTranslator();
  const interrupts = new Map();
  const asked = new Map();
  let running = false;
  let turn;
  let live = false;

  const send = (update) => peer.notify("session/update", { sessionId: id, update });

  const endTurn = (stopReason) => {
    const t = turn;
    turn = undefined;
    if (!t) return;
    if (t.kind === "prompt") t.resolve({ stopReason });
    else {
      send({ sessionUpdate: "session_push_end" });
      t.request.promise.catch(() => {});
    }
  };

  const ask = (intr) => {
    if (asked.has(intr.id)) return;
    const options = Array.isArray(intr.metadata?.options) ? intr.metadata.options : [];
    if (!options.length) return;
    const req = peer.request("session/request_permission", {
      sessionId: id,
      toolCall: { toolCallId: intr.toolCallId ?? intr.id, title: intr.message ?? "Scooter needs your choice", status: "pending" },
      options: options.map((o) => ({ optionId: o.optionId, name: o.name ?? o.optionId, kind: o.kind ?? "allow_once" })),
    });
    asked.set(intr.id, req.id);
    req.promise
      .then((res) => {
        if (!interrupts.has(intr.id)) return;
        const optionId = res?.outcome?.outcome === "selected" ? res.outcome.optionId : undefined;
        return client.resume(id, intr.id, optionId);
      })
      .catch((e) => log("permission answer failed", id, e?.message ?? e));
  };

  const startPush = () => {
    const request = peer.request("session/push", { sessionId: id });
    request.promise.catch((e) => log("client declined push", id, e?.message ?? e));
    turn = { kind: "push", request };
  };

  const track = (e, replay) => {
    if (e.type === "RUN_STARTED" && !isExt(e)) {
      running = true;
      if (!replay && live && !turn) startPush();
      if (turn?.kind === "prompt") turn.started = true;
    } else if (e.type === "RUN_FINISHED" && e.outcome?.type === "interrupt") {
      for (const intr of e.outcome.interrupts ?? []) {
        interrupts.set(intr.id, intr);
        if (!replay && live) ask(intr);
      }
    } else if (e.type === "PERMISSION_RESOLVED") {
      const key = [...interrupts.keys()].find((k) => k === e.toolCallId || interrupts.get(k)?.toolCallId === e.toolCallId);
      if (key !== undefined) {
        interrupts.delete(key);
        const reqId = asked.get(key);
        asked.delete(key);
        if (reqId !== undefined) peer.notify("$/cancel_request", { requestId: reqId });
      }
    } else if ((e.type === "RUN_FINISHED" || e.type === "RUN_ERROR") && !isExt(e)) {
      running = false;
      if (!replay && live && (turn?.kind === "push" || turn?.started)) endTurn(e.cancelled ? "cancelled" : "end_turn");
    }
  };

  const onEvents = async (events, { replay }) => {
    let firstShown = 0;
    if (replay) {
      const starts = userTurnStarts(events);
      if (config.replayTurns >= 0 && starts.length > config.replayTurns) firstShown = config.replayTurns === 0 ? events.length : starts[starts.length - config.replayTurns];
    }
    const withImages = (u) => (hasPendingImages(u) ? resolveImages(u, client.asset, log) : u);
    const translated = events.map((e, i) => {
      const updates = translate(e);
      if (i < firstShown) return [];
      return replay ? updates.map(withImages) : updates;
    });
    for (const [i, e] of events.entries()) {
      const updates = translated[i];
      const userEcho = !replay && turn?.kind === "prompt" && updates.some((u) => u.sessionUpdate === "user_message_chunk");
      if (!userEcho) {
        for (const u of updates) {
          if (u.sessionUpdate === "user_message_chunk" && !replay && !turn) continue;
          send(await withImages(await u));
        }
      }
      track(e, replay);
    }
  };

  const watchRunStream = async (res, mine) => {
    try {
      for await (const e of sseFrames(res.body)) {
        if (e.type === "RUN_STARTED") {
          mine.started = true;
          break;
        }
        if (e.type === "RUN_ERROR" && turn === mine && !mine.started) {
          send({ sessionUpdate: "agent_message_chunk", content: { type: "text", text: `**Scooter could not start the run:** ${e.message}` } });
          endTurn("end_turn");
        }
      }
    } catch (e) {
      log("run stream ended", id, e?.message ?? e);
    }
  };

  const follower = createFollower({
    client,
    id,
    log,
    onEvents,
    onGone: () => {
      log("conversation disappeared", id);
      endTurn("cancelled");
    },
  });

  return {
    id,
    model,
    async attach({ replay }) {
      await follower.start({ replay });
      setTimeout(() => {
        live = true;
        if (running && !turn) startPush();
        for (const intr of interrupts.values()) ask(intr);
      }, 0);
    },
    async prompt(text, images = []) {
      if (turn?.kind === "push") endTurn("end_turn");
      const done = new Promise((resolve) => {
        turn = { kind: "prompt", resolve, started: false };
      });
      const mine = turn;
      try {
        const res = await client.sendPrompt(id, text, this.model, { images });
        void watchRunStream(res, mine);
      } catch (e) {
        if (turn === mine) turn = undefined;
        throw e;
      }
      return done;
    },
    async steer(text, images = []) {
      if (!turn && !running) return { outcome: "promptRequired" };
      if (images.length) await (await client.sendPrompt(id, text, this.model, { images, priority: PRIORITY_INTERRUPT })).body?.cancel();
      else await client.steer(id, text);
      return { outcome: "injected" };
    },
    async cancel() {
      await client.cancel(id);
    },
    close() {
      follower.stop();
      endTurn("cancelled");
    },
    settled: () => follower.settled(),
  };
}
