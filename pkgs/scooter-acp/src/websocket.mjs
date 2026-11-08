import { createHash, randomBytes } from "node:crypto";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import { Transform } from "node:stream";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
export const OP = { continuation: 0, text: 1, binary: 2, close: 8, ping: 9, pong: 10 };

export const acceptKey = (key) => createHash("sha1").update(key + GUID).digest("base64");

export function encodeFrame(payload, { opcode = OP.binary, mask = true } = {}) {
  const len = payload.length;
  const lenBytes = len < 126 ? 0 : len < 65536 ? 2 : 8;
  const head = Buffer.alloc(2 + lenBytes + (mask ? 4 : 0));
  head[0] = 0x80 | opcode;
  head[1] = (mask ? 0x80 : 0) | (lenBytes === 0 ? len : lenBytes === 2 ? 126 : 127);
  if (lenBytes === 2) head.writeUInt16BE(len, 2);
  if (lenBytes === 8) head.writeBigUInt64BE(BigInt(len), 2);
  if (!mask) return Buffer.concat([head, payload]);
  const key = randomBytes(4);
  key.copy(head, 2 + lenBytes);
  const body = Buffer.from(payload);
  for (let i = 0; i < body.length; i++) body[i] ^= key[i & 3];
  return Buffer.concat([head, body]);
}

export function frameDecoder({ onControl = () => {} } = {}) {
  let buf = Buffer.alloc(0);
  return new Transform({
    transform(chunk, _enc, cb) {
      buf = buf.length ? Buffer.concat([buf, chunk]) : chunk;
      while (buf.length >= 2) {
        const opcode = buf[0] & 0x0f;
        const masked = (buf[1] & 0x80) !== 0;
        let len = buf[1] & 0x7f;
        let at = 2;
        if (len === 126) {
          if (buf.length < 4) break;
          len = buf.readUInt16BE(2);
          at = 4;
        } else if (len === 127) {
          if (buf.length < 10) break;
          len = Number(buf.readBigUInt64BE(2));
          at = 10;
        }
        const keyAt = at;
        if (masked) at += 4;
        if (buf.length < at + len) break;
        const payload = Buffer.from(buf.subarray(at, at + len));
        if (masked) for (let i = 0; i < payload.length; i++) payload[i] ^= buf[keyAt + (i & 3)];
        buf = buf.subarray(at + len);
        if (opcode === OP.close) {
          onControl(OP.close, payload);
          this.push(null);
          buf = Buffer.alloc(0);
          return cb();
        }
        if (opcode >= 8) onControl(opcode, payload);
        else if (payload.length) this.push(payload);
      }
      cb();
    },
  });
}

export class UpgradeError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

export function openWebSocket(url, { headers = {}, timeoutMs = 15000 } = {}) {
  const target = new URL(url);
  const request = target.protocol === "https:" || target.protocol === "wss:" ? httpsRequest : httpRequest;
  const key = randomBytes(16).toString("base64");
  return new Promise((resolve, reject) => {
    const req = request(target.href.replace(/^ws/, "http"), {
      headers: {
        ...headers,
        Connection: "Upgrade",
        Upgrade: "websocket",
        "Sec-WebSocket-Version": "13",
        "Sec-WebSocket-Key": key,
      },
      timeout: timeoutMs,
    });
    req.on("timeout", () => req.destroy(new UpgradeError(`no answer within ${timeoutMs}ms`)));
    req.on("error", (e) => reject(e instanceof UpgradeError ? e : new UpgradeError(e.message)));
    req.on("response", (res) => {
      res.resume();
      reject(new UpgradeError(`HTTP ${res.statusCode}`, res.statusCode));
    });
    req.on("upgrade", (res, socket, head) => {
      if (res.headers["sec-websocket-accept"] !== acceptKey(key)) {
        socket.destroy();
        return reject(new UpgradeError("the server did not accept the WebSocket handshake", res.statusCode));
      }
      socket.setNoDelay(true);
      if (head.length) socket.unshift(head);
      resolve({ socket, headers: res.headers });
    });
    req.end();
  });
}
