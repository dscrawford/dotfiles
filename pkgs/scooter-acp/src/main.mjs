import { registerAgent } from "./agent.mjs";
import { createPeer } from "./jsonrpc.mjs";
import { login } from "./login.mjs";
import { registerSandbox } from "./sandbox.mjs";
import { createScooterClient, readConfig } from "./scooter.mjs";
import { TunnelRefused, runTunnel } from "./tunnel.mjs";
import { registerWebServices } from "./webservices.mjs";

const VERSION = "0.1.0";
const COOKIE_REFUSED = 77;
const log = (...args) => process.stderr.write(`[scooter-acp] ${args.join(" ")}\n`);

const config = readConfig();

if (process.argv[2] === "--login") {
  const failed = await login(config).catch((e) => {
    log(e.message);
    return true;
  });
  process.exit(failed ? 1 : 0);
}

const client = createScooterClient(config, { log });

if (process.argv[2] === "--check-auth") {
  const accepted = await client.checkAuth().catch((e) => {
    log("could not check the session cookie:", e?.cause?.message ?? e?.message ?? e);
    return undefined;
  });
  process.exit(accepted === undefined ? 1 : accepted ? 0 : COOKIE_REFUSED);
}

if (process.argv[2] === "--tunnel") {
  const id = process.argv[3];
  if (!id) {
    log("usage: scooter-acp --tunnel <conversation-id>");
    process.exit(2);
  }
  const code = await runTunnel({ client, config, id, stdin: process.stdin, stdout: process.stdout, log }).then(
    () => 0,
    (e) => {
      log(e.message);
      return e instanceof TunnelRefused ? COOKIE_REFUSED : 1;
    },
  );
  process.exit(code);
}

const peer = createPeer({ input: process.stdin, output: process.stdout, log });
const agent = registerAgent({ peer, client, config, log, version: VERSION });
registerWebServices({ peer, client, config });
registerSandbox({ peer, client, sessions: agent.sessions });

peer.onClose(() => {
  agent.closeAll();
  process.exit(0);
});
process.on("SIGTERM", () => {
  agent.closeAll();
  process.exit(0);
});
