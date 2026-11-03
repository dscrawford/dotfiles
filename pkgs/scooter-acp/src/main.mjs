import { registerAgent } from "./agent.mjs";
import { createPeer } from "./jsonrpc.mjs";
import { createScooterClient, readConfig } from "./scooter.mjs";

const VERSION = "0.1.0";
const log = (...args) => process.stderr.write(`[scooter-acp] ${args.join(" ")}\n`);

const config = readConfig();
const client = createScooterClient(config, { log });
const peer = createPeer({ input: process.stdin, output: process.stdout, log });
const agent = registerAgent({ peer, client, config, log, version: VERSION });

peer.onClose(() => {
  agent.closeAll();
  process.exit(0);
});
process.on("SIGTERM", () => {
  agent.closeAll();
  process.exit(0);
});
