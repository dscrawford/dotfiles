import { createInterface } from "node:readline";

export class RpcError extends Error {
  constructor(code, message, data) {
    super(message);
    this.code = code;
    this.data = data;
  }
}

export const METHOD_NOT_FOUND = -32601;
export const INVALID_PARAMS = -32602;
export const INTERNAL_ERROR = -32603;
export const AUTH_REQUIRED = -32000;

export function createPeer({ input, output, log = () => {} }) {
  const handlers = new Map();
  const pending = new Map();
  let nextId = 1;
  let onClose = () => {};

  const write = (msg) => output.write(JSON.stringify({ jsonrpc: "2.0", ...msg }) + "\n");

  const respond = async (msg) => {
    const handler = handlers.get(msg.method);
    const isRequest = msg.id !== undefined && msg.id !== null;
    if (!handler) {
      if (isRequest) write({ id: msg.id, error: { code: METHOD_NOT_FOUND, message: `method not found: ${msg.method}` } });
      return;
    }
    try {
      const result = await handler(msg.params ?? {});
      if (isRequest) write({ id: msg.id, result: result ?? null });
    } catch (e) {
      log("handler failed", msg.method, e?.message ?? e);
      if (isRequest) {
        const error = { code: e instanceof RpcError ? e.code : INTERNAL_ERROR, message: e?.message ?? String(e) };
        if (e instanceof RpcError && e.data !== undefined) error.data = e.data;
        write({ id: msg.id, error });
      }
    }
  };

  const lines = createInterface({ input, crlfDelay: Infinity });
  lines.on("line", (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      log("dropping unparsable line");
      return;
    }
    if (msg.method !== undefined) {
      void respond(msg);
      return;
    }
    const waiter = pending.get(msg.id);
    if (!waiter) return;
    pending.delete(msg.id);
    if (msg.error) waiter.reject(new RpcError(msg.error.code, msg.error.message, msg.error.data));
    else waiter.resolve(msg.result);
  });
  lines.on("close", () => {
    for (const waiter of pending.values()) waiter.reject(new RpcError(INTERNAL_ERROR, "client closed"));
    pending.clear();
    onClose();
  });

  return {
    on(method, handler) {
      handlers.set(method, handler);
    },
    notify(method, params) {
      write({ method, params });
    },
    request(method, params) {
      const id = nextId++;
      const promise = new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
      write({ id, method, params });
      return { id, promise };
    },
    onClose(fn) {
      onClose = fn;
    },
  };
}
