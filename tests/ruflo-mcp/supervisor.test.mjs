import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPERVISOR = new URL('../../pkgs/ruflo-mcp/supervise.mjs', import.meta.url).pathname;
const FAKE = new URL('./fake-server.mjs', import.meta.url).pathname;

const startSupervisor = (t, env = {}) => {
  const state = join(mkdtempSync(join(tmpdir(), 'ruflo-mcp-test-')), 'state');
  writeFileSync(state, '');
  const proc = spawn(process.execPath, [SUPERVISOR], {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: {
      ...process.env,
      FAKE_STATE: state,
      RUFLO_MCP_COMMAND: process.execPath,
      RUFLO_MCP_ARGS: FAKE,
      ...env,
    },
  });
  const frames = [];
  const waiters = [];
  let buffer = '';
  proc.stdout.on('data', (chunk) => {
    const lines = (buffer + chunk).split('\n');
    buffer = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) continue;
      frames.push(JSON.parse(line));
      for (const w of [...waiters]) if (w.match(frames.at(-1))) waiters.splice(waiters.indexOf(w), 1), w.resolve(frames.at(-1));
    }
  });
  const send = (msg) => proc.stdin.write(JSON.stringify(msg) + '\n');
  const waitFor = (match) =>
    new Promise((resolve, reject) => {
      const hit = frames.find(match);
      if (hit) return resolve(hit);
      const timer = setTimeout(() => reject(new Error('timed out waiting for frame')), 10_000);
      waiters.push({ match, resolve: (f) => (clearTimeout(timer), resolve(f)) });
    });
  const call = (id, name) => send({ jsonrpc: '2.0', id, method: 'tools/call', params: { name } });
  t.after(() => proc.kill('SIGKILL'));
  return { proc, frames, send, waitFor, call, readState: () => readFileSync(state, 'utf8') };
};

const handshake = async (s) => {
  s.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05' } });
  await s.waitFor((f) => f.id === 1);
};

test('forwards calls and responses', async (t) => {
  const s = startSupervisor(t);
  await handshake(s);
  s.call(2, 'echo');
  const res = await s.waitFor((f) => f.id === 2);
  assert.match(res.result.content[0].text, /^echo:\d+$/);
});

test('a crashed server fails the in-flight call and keeps serving', async (t) => {
  const s = startSupervisor(t);
  await handshake(s);
  s.call(2, 'crash');
  const err = await s.waitFor((f) => f.id === 2);
  assert.equal(err.error.code, -32603);
  assert.match(err.error.message, /restarted|exited/);

  s.call(3, 'echo');
  const res = await s.waitFor((f) => f.id === 3);
  assert.match(res.result.content[0].text, /^echo:\d+$/);
  assert.equal(s.frames.filter((f) => f.id === 2).length, 1);
  assert.equal(s.readState().split('\n').filter((l) => l.endsWith('initialize')).length, 2);
});

test('the second server is a new process, not the crashed one', async (t) => {
  const s = startSupervisor(t);
  await handshake(s);
  s.call(2, 'echo');
  const first = await s.waitFor((f) => f.id === 2);
  s.call(3, 'crash');
  await s.waitFor((f) => f.id === 3);
  s.call(4, 'echo');
  const second = await s.waitFor((f) => f.id === 4);
  assert.notEqual(first.result.content[0].text, second.result.content[0].text);
});

test('a wedged call times out instead of hanging the session', async (t) => {
  const s = startSupervisor(t, { RUFLO_MCP_TOOL_TIMEOUT_MS: '300', RUFLO_MCP_WATCHDOG_INTERVAL_MS: '100' });
  await handshake(s);
  s.call(2, 'hang');
  const err = await s.waitFor((f) => f.id === 2);
  assert.equal(err.error.code, -32603);
  assert.match(err.error.message, /stopped responding/);

  s.call(3, 'echo');
  const res = await s.waitFor((f) => f.id === 3);
  assert.match(res.result.content[0].text, /^echo:\d+$/);
});

test('a crash under a burst of calls answers every id and keeps the supervisor up', async (t) => {
  const s = startSupervisor(t);
  await handshake(s);
  const ids = [...Array(20).keys()].map((i) => i + 10);
  for (const id of ids) s.call(id, id === 14 ? 'crash' : 'echo');
  for (const id of ids) await s.waitFor((f) => f.id === id);
  assert.equal(s.proc.exitCode, null);
  for (const id of ids) assert.equal(s.frames.filter((f) => f.id === id).length, 1);
});

test('restart storms give up instead of spinning forever', async (t) => {
  const s = startSupervisor(t, { RUFLO_MCP_MAX_RESTARTS: '2' });
  await handshake(s);
  const exited = new Promise((resolve) => s.proc.on('exit', resolve));
  for (const id of [2, 3, 4]) {
    s.call(id, 'crash');
    await s.waitFor((f) => f.id === id);
  }
  assert.equal(await exited, 1);
});
