import { setTimeout as sleep } from "node:timers/promises";
import { pipeline } from "node:stream/promises";
import { Transform } from "node:stream";

import { listServices } from "./webservices.mjs";
import { OP, encodeFrame, frameDecoder, openWebSocket } from "./websocket.mjs";

export const SSH_SERVICE = "ssh";

export class TunnelRefused extends Error {}

const isRefused = (status) => status === 401 || status === 403 || (status >= 300 && status < 400);

export async function sshServiceUrl(client, config, id) {
  const services = await listServices(client, config, id).catch(() => []);
  const ssh = services.find((s) => s.name === SSH_SERVICE);
  if (ssh) return ssh.url;
  const sibling = services.find((s) => new URL(s.url).pathname.endsWith(`/${s.name}/`));
  return sibling ? new URL(`../${SSH_SERVICE}/`, sibling.url).href : `${config.url}/c/${encodeURIComponent(id)}/${SSH_SERVICE}/`;
}

async function wakeSandbox(client, id, log) {
  const path = `/conversations/${encodeURIComponent(id)}`;
  const status = (await client.request("GET", path).catch(() => null))?.status;
  if (typeof status === "string" && status !== "running") {
    log(`resuming the ${status} sandbox`);
    await client.request("POST", `${path}/resume`, {}).catch((e) => log("could not resume it:", e.message));
  }
  await client.webServiceAction(id, SSH_SERVICE, "start").catch(() => {});
}

export async function connectTunnel({ client, config, id, log = () => {}, retryMs = 1000 }) {
  const url = await sshServiceUrl(client, config, id);
  const deadline = Date.now() + config.tunnelTimeoutMs;
  let woken = false;
  for (;;) {
    try {
      return await openWebSocket(url, { headers: client.authHeaders(), timeoutMs: config.requestTimeoutMs });
    } catch (e) {
      if (isRefused(e.status)) {
        throw new TunnelRefused(
          `Scooter refused the ssh tunnel to ${url} (${e.message}); sign in with M-x my/scooter-login or refresh the cookie in ${config.cookieFile ?? "SCOOTER_COOKIE"}`,
        );
      }
      if (Date.now() + retryMs > deadline) throw new Error(`the sandbox's ssh service at ${url} did not answer: ${e.message}`);
      if (!woken) {
        log(`waiting for the sandbox's ssh service (${e.message})`);
        await wakeSandbox(client, id, log);
        woken = true;
      }
      await sleep(retryMs);
    }
  }
}

const CLOSE_NORMAL = Buffer.from([0x03, 0xe8]);

function upstreamFrames() {
  return new Transform({
    transform(chunk, _enc, cb) {
      cb(null, encodeFrame(chunk));
    },
    flush(cb) {
      cb(null, encodeFrame(CLOSE_NORMAL, { opcode: OP.close }));
    },
  });
}

export async function runTunnel({ client, config, id, stdin, stdout, log = () => {} }) {
  const { socket } = await connectTunnel({ client, config, id, log });
  const decoder = frameDecoder({
    onControl: (opcode, payload) => {
      if (opcode === OP.ping && socket.writable) socket.write(encodeFrame(payload, { opcode: OP.pong }));
    },
  });
  pipeline(stdin, upstreamFrames(), socket).catch(() => {});
  await pipeline(socket, decoder, stdout);
}
