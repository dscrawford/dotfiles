import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const MAIN = fileURLToPath(new URL("../../pkgs/scooter-acp/src/main.mjs", import.meta.url));

export function startBridge(env) {
  const child = spawn(process.execPath, [MAIN], { env: { ...process.env, ...env }, stdio: ["pipe", "pipe", "pipe"] });
  const updates = [];
  const requests = [];
  const pending = new Map();
  const waiters = [];
  let stderr = "";
  let nextId = 1;
  const autoAnswers = new Map();

  child.stderr.on("data", (d) => (stderr += d));
  const write = (m) => child.stdin.write(JSON.stringify({ jsonrpc: "2.0", ...m }) + "\n");

  const check = () => {
    for (const w of [...waiters]) {
      const hit = w.pred();
      if (hit) {
        waiters.splice(waiters.indexOf(w), 1);
        w.resolve(hit);
      }
    }
  };

  createInterface({ input: child.stdout }).on("line", (line) => {
    const msg = JSON.parse(line);
    if (msg.method === "session/update") updates.push(msg.params.update);
    else if (msg.method && msg.id !== undefined) {
      requests.push(msg);
      const answer = autoAnswers.get(msg.method);
      if (answer) write({ id: msg.id, result: answer(msg.params) });
    } else if (msg.method) requests.push(msg);
    else if (pending.has(msg.id)) {
      const p = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? p.reject(Object.assign(new Error(msg.error.message), msg.error)) : p.resolve(msg.result);
    }
    check();
  });

  return {
    updates,
    requests,
    stderr: () => stderr,
    answer: (method, fn) => autoAnswers.set(method, fn),
    reply: (id, result) => write({ id, result }),
    fail: (id, error) => write({ id, error }),
    request(method, params = {}) {
      const id = nextId++;
      write({ id, method, params });
      return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
    },
    notify: (method, params) => write({ method, params }),
    waitFor(pred, timeoutMs = 3000) {
      return new Promise((resolve, reject) => {
        const w = { pred, resolve: (v) => (clearInterval(poll), resolve(v)) };
        const poll = setInterval(check, 20);
        waiters.push(w);
        check();
        setTimeout(() => {
          clearInterval(poll);
          if (waiters.includes(w)) {
            waiters.splice(waiters.indexOf(w), 1);
            reject(new Error(`timed out; stderr: ${stderr}`));
          }
        }, timeoutMs);
      });
    },
    stop() {
      child.stdin.end();
      return new Promise((r) => child.on("exit", r));
    },
  };
}
