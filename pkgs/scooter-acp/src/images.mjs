import { INVALID_PARAMS, RpcError } from "./jsonrpc.mjs";

export const UPLOAD_MIME = new Set(["image/png", "image/jpeg", "image/gif", "image/webp"]);

const ASSET_PATH = /^\/conversations\/[^/]+\/assets\/[^/]+$/;
const MAX_DEPTH = 8;

export const pendingImage = (url, mimeType) => ({ type: "image", mimeType, _asset: url });

const omittedText = (mimeType, why) => ({ type: "text", text: `\n[${mimeType ?? "image"} not shown: ${why}]\n` });

export function messageImageBlocks(images = []) {
  return images.map((i) => (typeof i?.url === "string" && ASSET_PATH.test(i.url) ? pendingImage(i.url, i.mimeType) : omittedText(i?.mimeType, "unavailable")));
}

function isImageRef(v) {
  return v?.type === "image" && (typeof v.url === "string" || typeof v.omitted === "string");
}

function textOnly(v) {
  const onlyContent = v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === 1 && "content" in v;
  const blocks = Array.isArray(v) ? v : onlyContent ? v.content : undefined;
  if (!Array.isArray(blocks) || !blocks.length) return null;
  const texts = [];
  for (const b of blocks) {
    const t = b?.type === "content" ? b.content : b;
    if (t?.type !== "text" || typeof t.text !== "string") return null;
    texts.push(t.text);
  }
  return texts.join("\n");
}

export function splitResultImages(raw) {
  if (typeof raw !== "string" || !raw.includes('"image"') || !/^\s*[[{]/.test(raw)) return null;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  const blocks = [];
  const walk = (v, depth) => {
    if (depth > MAX_DEPTH || !v || typeof v !== "object") return v;
    if (isImageRef(v)) {
      blocks.push(typeof v.url === "string" && ASSET_PATH.test(v.url) ? pendingImage(v.url, v.mimeType) : omittedText(v.mimeType, v.omitted ?? "unavailable"));
      return undefined;
    }
    if (Array.isArray(v)) {
      const out = v.map((x) => walk(x, depth + 1)).filter((x) => x !== undefined);
      return out.length ? out : v.length ? undefined : v;
    }
    if (v.type === "content" && "content" in v) {
      const inner = walk(v.content, depth + 1);
      return inner === undefined ? undefined : { ...v, content: inner };
    }
    const out = {};
    for (const [k, x] of Object.entries(v)) {
      const y = walk(x, depth + 1);
      if (y !== undefined) out[k] = y;
    }
    return out;
  };
  const rest = walk(parsed, 0);
  if (!blocks.length) return null;
  const empty = rest === undefined || (typeof rest === "object" && Object.keys(rest).length === 0);
  return { text: empty ? undefined : (textOnly(rest) ?? JSON.stringify(rest)), images: blocks };
}

const needsFetch = (b) => b?.type === "image" && typeof b._asset === "string";

export function hasPendingImages(update) {
  return needsFetch(update.content) || (Array.isArray(update.content) && update.content.some((c) => needsFetch(c.content)));
}

export async function resolveImages(update, fetchAsset, log = () => {}) {
  const resolve = async (b) => {
    if (!needsFetch(b)) return b;
    try {
      const { data, mimeType } = await fetchAsset(b._asset);
      return { type: "image", data, mimeType };
    } catch (e) {
      log("image fetch failed", b._asset, e?.message ?? e);
      return omittedText(b.mimeType, e?.message ?? "fetch failed");
    }
  };
  if (Array.isArray(update.content)) {
    return { ...update, content: await Promise.all(update.content.map(async (c) => ({ ...c, content: await resolve(c.content) }))) };
  }
  return { ...update, content: await resolve(update.content) };
}

export async function readCapped(res, maxBytes) {
  const declared = Number(res.headers.get("content-length"));
  if (declared > maxBytes) {
    await res.body?.cancel();
    throw new Error(`too large (${declared} bytes, limit ${maxBytes})`);
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of res.body ?? []) {
    size += chunk.length;
    if (size > maxBytes) throw new Error(`too large (over ${maxBytes} bytes)`);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function promptImages(blocks = [], maxBytes) {
  const images = [];
  for (const b of blocks) {
    if (b.type !== "image") continue;
    if (typeof b.data !== "string" || !b.data) throw new RpcError(INVALID_PARAMS, "image block without base64 data");
    if (!UPLOAD_MIME.has(b.mimeType)) throw new RpcError(INVALID_PARAMS, `Scooter accepts png, jpeg, gif and webp images, not ${b.mimeType}`);
    const bytes = Math.floor((b.data.length * 3) / 4);
    if (bytes > maxBytes) throw new RpcError(INVALID_PARAMS, `image is ${bytes} bytes, over the ${maxBytes}-byte limit`);
    images.push({ type: "image", data: b.data, mimeType: b.mimeType });
  }
  return images;
}
