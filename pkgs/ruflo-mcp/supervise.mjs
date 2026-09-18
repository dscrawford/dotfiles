#!/usr/bin/env node
// stdio supervisor for `ruflo mcp start`: the client's transport is this process,
// so a crashed or wedged ruflo costs one retryable JSON-RPC error and a respawn
// rather than the rest of the session. See docs/ruflo-mcp-crash-research.md.
import { spawn } from 'node:child_process';

const COMMAND = process.env.RUFLO_MCP_COMMAND ?? 'ruflo';
const ARGS = process.env.RUFLO_MCP_ARGS ? process.env.RUFLO_MCP_ARGS.split(' ') : ['mcp', 'start'];
const MAX_RESTARTS = Number(process.env.RUFLO_MCP_MAX_RESTARTS ?? 20);
const RESTART_WINDOW_MS = Number(process.env.RUFLO_MCP_RESTART_WINDOW_MS ?? 600_000);
const TOOL_TIMEOUT_MS = Number(process.env.RUFLO_MCP_TOOL_TIMEOUT_MS ?? 180_000);
const WATCHDOG_INTERVAL_MS = Number(process.env.RUFLO_MCP_WATCHDOG_INTERVAL_MS ?? 10_000);

const log = (msg) => process.stderr.write(`[ruflo-mcp] ${msg}\n`);
const writeClient = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');

// id -> { method, dispatchedAt }; dispatchedAt is null while a request waits on
// a restarting server, so neither the watchdog nor failPending charges it.
const pending = new Map();
// Ids already answered with an error, plus replayed handshakes: their real
// response must never reach the client.
const suppressed = new Set();

let child = null;
let dispatchable = false;
let childBuffer = '';
let clientBuffer = '';
let queued = [];
let handshake = null;
let restarts = [];
let shuttingDown = false;

const failPending = (reason) => {
  for (const [id, { method, dispatchedAt }] of pending) {
    if (dispatchedAt === null) continue;
    suppressed.add(id);
    writeClient({
      jsonrpc: '2.0',
      id,
      error: { code: -32603, message: `ruflo MCP server ${reason} during ${method}; retry the call` },
    });
    pending.delete(id);
  }
};

const sendChild = (line, id) => {
  if (dispatchable && child?.stdin?.writable) {
    child.stdin.write(line + '\n');
    const entry = pending.get(id);
    if (entry) pending.set(id, { ...entry, dispatchedAt: Date.now() });
    return;
  }
  queued = [...queued, { line, id }];
};

const onClientLine = (line) => {
  let msg = null;
  try {
    msg = JSON.parse(line);
  } catch {
    sendChild(line);
    return;
  }
  if (msg.method === 'initialize') handshake = line;
  if (msg.id !== undefined && msg.method) pending.set(msg.id, { method: msg.method, dispatchedAt: null });
  sendChild(line, msg.id);
};

const onChildLine = (line) => {
  let msg = null;
  try {
    msg = JSON.parse(line);
  } catch {
    process.stdout.write(line + '\n');
    return;
  }
  if (msg.id !== undefined) {
    pending.delete(msg.id);
    if (suppressed.delete(msg.id)) return;
  }
  process.stdout.write(line + '\n');
};

const consume = (buffer, chunk, onLine) => {
  const lines = (buffer + chunk).split('\n');
  const rest = lines.pop() ?? '';
  for (const line of lines) if (line.trim()) onLine(line);
  return rest;
};

const spawnChild = (isRestart) => {
  child = spawn(COMMAND, ARGS, { stdio: ['pipe', 'pipe', 'inherit'] });
  dispatchable = true;
  childBuffer = '';
  child.on('error', (err) => {
    dispatchable = false;
    log(`spawn failed: ${err.message}`);
    failPending('could not be started');
  });
  // A write racing the child's death lands on a closed pipe; without this the
  // EPIPE would take the supervisor down with it.
  child.stdin.on('error', (err) => {
    dispatchable = false;
    log(`write to server failed: ${err.code ?? err.message}`);
  });
  child.stdout.on('data', (chunk) => {
    childBuffer = consume(childBuffer, chunk, onChildLine);
  });
  child.on('exit', (code, signal) => {
    dispatchable = false;
    if (shuttingDown) return;
    log(`server exited (code=${code} signal=${signal}); restarting`);
    failPending(`exited (code=${code} signal=${signal})`);
    scheduleRestart();
  });
  if (isRestart && handshake) {
    const replayId = JSON.parse(handshake).id;
    if (replayId !== undefined) suppressed.add(replayId);
    sendChild(handshake);
    sendChild(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }));
  }
  const flush = queued;
  queued = [];
  for (const { line, id } of flush) sendChild(line, id);
};

const scheduleRestart = () => {
  const now = Date.now();
  restarts = [...restarts.filter((t) => now - t < RESTART_WINDOW_MS), now];
  if (restarts.length > MAX_RESTARTS) {
    log(`giving up after ${restarts.length} restarts in ${RESTART_WINDOW_MS}ms`);
    process.exit(1);
  }
  child = null;
  setTimeout(() => {
    if (!shuttingDown) spawnChild(true);
  }, Math.min(250 * restarts.length, 5_000)).unref();
};

const watchdog = () => {
  if (TOOL_TIMEOUT_MS <= 0 || !child) return;
  const now = Date.now();
  const stuck = [...pending].filter(([, { dispatchedAt }]) => dispatchedAt !== null && now - dispatchedAt > TOOL_TIMEOUT_MS);
  if (stuck.length === 0) return;
  log(`no response for ${stuck.map(([, m]) => m.method).join(', ')} after ${TOOL_TIMEOUT_MS}ms; restarting`);
  failPending(`stopped responding after ${TOOL_TIMEOUT_MS}ms`);
  dispatchable = false;
  child.kill('SIGKILL');
};

const shutdown = (signal) => {
  shuttingDown = true;
  child?.kill(signal ?? 'SIGTERM');
  process.exit(0);
};

process.stdin.on('data', (chunk) => {
  clientBuffer = consume(clientBuffer, chunk, onClientLine);
});
process.stdin.on('end', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

setInterval(watchdog, WATCHDOG_INTERVAL_MS).unref();
spawnChild(false);
