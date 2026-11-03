import { INVALID_PARAMS, RpcError } from "./jsonrpc.mjs";

const SERVICE_CMD = /\bscooter-service\s+(start|stop|restart)\s+([\w.-]+)/g;
const VERBS = { start: "started", stop: "stopped", restart: "restarted" };

export function absoluteUrl(base, url) {
  return new URL(url, base + "/").href;
}

export async function listServices(client, config, id) {
  const { services = [] } = (await client.webServices(id)) ?? {};
  return services.map((s) => ({
    name: s.name,
    displayName: s.displayName ?? s.name,
    running: !!s.running,
    url: absoluteUrl(config.url, s.url),
    ...(s.fit ? { fit: s.fit } : {}),
  }));
}

export function serviceNotices(input) {
  const command = typeof input === "string" ? input : (input?.command ?? input?.cmd);
  if (typeof command !== "string") return [];
  return [...command.matchAll(SERVICE_CMD)].map(([, verb, name]) => `web service \`${name}\` ${VERBS[verb]} (M-x my/scooter-web-services)`);
}

function required(params, key) {
  const value = params?.[key];
  if (typeof value !== "string" || !value) throw new RpcError(INVALID_PARAMS, `${key} is required`);
  return value;
}

export function registerWebServices({ peer, client, config }) {
  peer.on("_scooter/web-services/list", async (params) => ({
    services: await listServices(client, config, required(params, "sessionId")),
  }));

  for (const action of ["start", "stop"]) {
    peer.on(`_scooter/web-services/${action}`, async (params) => {
      await client.webServiceAction(required(params, "sessionId"), required(params, "name"), action);
      return {};
    });
  }
}
