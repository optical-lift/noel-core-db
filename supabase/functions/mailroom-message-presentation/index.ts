import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import PostalMime from "npm:postal-mime@3.0.0";
// @ts-types="npm:@types/sanitize-html@2.16.1"
import sanitizeHtml from "npm:sanitize-html@2.17.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/i;
const RAW_BUCKET = "atlas-communication-raw";
const MAX_RAW_BYTES = 10 * 1024 * 1024;
const MAX_INLINE_IMAGE_BYTES = 1536 * 1024;
const MAX_INLINE_IMAGE_TOTAL_BYTES = 4 * 1024 * 1024;
const SAFE_INLINE_IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/gif", "image/webp"]);

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json", "cache-control": "private, no-store" },
  });
}

type DetailMessage = { communication_event_id?: string };
type DetailPacket = { messages?: DetailMessage[] };
type CustodyRow = { raw_mime_sha256?: string | null; byte_length?: number | null; storage_locator?: string | null; custody_state?: string | null };
type InlineAttachment = { contentId?: string | null; mimeType?: string | null; content?: string | ArrayBuffer | Uint8Array | null };

type Presentation = {
  ok: true;
  eventId: string;
  kind: "html" | "text";
  document?: string;
  text?: string;
  remoteImagesBlocked: boolean;
  inlineImageCount: number;
};

async function rpc<T>(functionName: string, args: Record<string, unknown>, authorization: string, apikey: string): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(functionName)}`, {
    method: "POST",
    headers: { apikey, Authorization: authorization, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${functionName} failed (${response.status}): ${text.slice(0, 500)}`);
  return (text ? JSON.parse(text) : null) as T;
}

async function custodyForEvent(eventId: string): Promise<CustodyRow | null> {
  const params = new URLSearchParams({
    communication_event_id: `eq.${eventId}`,
    custody_state: "eq.stored",
    select: "raw_mime_sha256,byte_length,storage_locator,custody_state",
    order: "recorded_at.desc",
    limit: "1",
  });
  const response = await fetch(`${SUPABASE_URL}/rest/v1/communication_raw_message_custody?${params}`, {
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Accept-Profile": "atlas",
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Raw-message custody lookup failed (${response.status}): ${text.slice(0, 500)}`);
  const rows = (text ? JSON.parse(text) : []) as CustodyRow[];
  return rows[0] ?? null;
}

function storagePath(locator: string) {
  const prefix = `${RAW_BUCKET}/`;
  if (!locator.startsWith(prefix)) throw new Error("Raw-message storage locator is outside the governed custody bucket.");
  const path = locator.slice(prefix.length);
  if (!path || path.includes("..")) throw new Error("Raw-message storage locator is invalid.");
  return path;
}

async function downloadRawMessage(path: string, expectedBytes?: number | null) {
  if (expectedBytes && expectedBytes > MAX_RAW_BYTES) throw new Error("Raw email exceeds the presentation size limit.");
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${SUPABASE_URL}/storage/v1/object/authenticated/${encodeURIComponent(RAW_BUCKET)}/${encoded}`, {
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    },
  });
  if (!response.ok) throw new Error(`Raw email download failed (${response.status}).`);
  const length = Number(response.headers.get("content-length") ?? "0");
  if (length > MAX_RAW_BYTES) throw new Error("Raw email exceeds the presentation size limit.");
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_RAW_BYTES) throw new Error("Raw email exceeds the presentation size limit.");
  if (expectedBytes && bytes.byteLength !== expectedBytes) throw new Error("Raw email length does not match the custody record.");
  return bytes;
}

async function sha256Hex(bytes: Uint8Array) {
  const owned = new Uint8Array(bytes.byteLength);
  owned.set(bytes);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", owned.buffer));
  return Array.from(digest).map((value) => value.toString(16).padStart(2, "0")).join("");
}

function toBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + chunk, bytes.length)));
  }
  return btoa(binary);
}

function normalizeCid(value?: string | null) {
  return (value ?? "").trim().replace(/^<|>$/g, "").toLowerCase();
}

function ownedAttachmentBytes(content: InlineAttachment["content"]) {
  if (content instanceof Uint8Array) {
    const owned = new Uint8Array(content.byteLength);
    owned.set(content);
    return owned;
  }
  if (content instanceof ArrayBuffer) return new Uint8Array(content.slice(0));
  return null;
}

function stripRemoteCss(value: string) {
  return value
    .replace(/@import\s+(?:url\()?[^;]+;?/gi, "")
    .replace(/url\(\s*(['"]?)(?!data:)[^)]+\1\s*\)/gi, "none");
}

function buildInlineImages(attachments: InlineAttachment[]) {
  const images = new Map<string, string>();
  let total = 0;
  for (const attachment of attachments) {
    const cid = normalizeCid(attachment.contentId);
    const mime = (attachment.mimeType ?? "").toLowerCase();
    const content = ownedAttachmentBytes(attachment.content);
    if (!cid || !content || !SAFE_INLINE_IMAGE_TYPES.has(mime)) continue;
    if (content.byteLength > MAX_INLINE_IMAGE_BYTES || total + content.byteLength > MAX_INLINE_IMAGE_TOTAL_BYTES) continue;
    total += content.byteLength;
    images.set(cid, `data:${mime};base64,${toBase64(content)}`);
  }
  return images;
}

function safeImageSource(value: string | undefined, inlineImages: Map<string, string>) {
  const src = (value ?? "").trim();
  if (!src) return { src: "", blocked: false };
  if (/^cid:/i.test(src)) {
    const cid = normalizeCid(src.slice(4));
    return { src: inlineImages.get(cid) ?? "", blocked: !inlineImages.has(cid) };
  }
  if (/^data:image\/(?:png|jpeg|gif|webp);base64,/i.test(src)) return { src, blocked: false };
  return { src: "", blocked: /^(?:https?:)?\/\//i.test(src) };
}

function safeLinkHref(value?: string) {
  const href = (value ?? "").trim();
  return /^(?:https?:|mailto:|tel:)/i.test(href) ? href : "";
}

function sanitizedEmailDocument(sourceHtml: string, inlineImages: Map<string, string>) {
  let remoteImagesBlocked = false;
  const cleanedSource = stripRemoteCss(sourceHtml);
  const clean = sanitizeHtml(cleanedSource, {
    allowedTags: [
      "style","div","span","p","br","hr","pre","blockquote",
      "h1","h2","h3","h4","h5","h6","strong","b","em","i","u","s","small","sub","sup",
      "table","thead","tbody","tfoot","tr","th","td","colgroup","col","center","font","a","img",
      "ul","ol","li","dl","dt","dd",
    ],
    allowedAttributes: {
      "*": ["class","id","style","title","dir","lang","role","aria-*"],
      a: ["href","name","target","rel","class","id","style","title"],
      img: ["src","alt","width","height","border","class","id","style","title"],
      table: ["width","height","cellpadding","cellspacing","border","align","valign","bgcolor","class","id","style"],
      tr: ["align","valign","bgcolor","height","class","id","style"],
      td: ["width","height","colspan","rowspan","align","valign","bgcolor","class","id","style"],
      th: ["width","height","colspan","rowspan","align","valign","bgcolor","class","id","style"],
      col: ["width","span","class","style"],
      font: ["face","size","color","class","style"],
    },
    allowedSchemes: ["http","https","mailto","tel"],
    allowedSchemesByTag: { img: ["data"] },
    allowProtocolRelative: false,
    enforceHtmlBoundary: true,
    transformTags: {
      a: (_tagName, attribs) => {
        const href = safeLinkHref(attribs.href);
        const next = { ...attribs, target: "_blank", rel: "noreferrer noopener" };
        if (href) next.href = href;
        else delete next.href;
        return { tagName: "a", attribs: next };
      },
      img: (_tagName, attribs) => {
        const image = safeImageSource(attribs.src, inlineImages);
        if (image.blocked) remoteImagesBlocked = true;
        const next = { ...attribs };
        delete next.srcset;
        if (image.src) next.src = image.src;
        else delete next.src;
        if (image.blocked) next.class = `${next.class ?? ""} atlas-remote-image-blocked`.trim();
        return { tagName: "img", attribs: next };
      },
    },
  });

  const cssSafe = stripRemoteCss(clean);
  const csp = [
    "default-src 'none'",
    "img-src data:",
    "style-src 'unsafe-inline'",
    "font-src data:",
    "connect-src 'none'",
    "media-src 'none'",
    "object-src 'none'",
    "frame-src 'none'",
    "worker-src 'none'",
    "form-action 'none'",
    "base-uri 'none'",
  ].join("; ");
  const shellStyle = "html,body{margin:0;padding:0;max-width:100%;}body{overflow-wrap:anywhere;}img{max-width:100%;height:auto;}table{max-width:100%;}.atlas-remote-image-blocked{display:none!important;}";
  const document = `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${csp}"><meta name="referrer" content="no-referrer"><style>${shellStyle}</style></head><body>${cssSafe}</body></html>`;
  return { document, remoteImagesBlocked };
}

async function presentationForEvent(eventId: string): Promise<Presentation> {
  const custody = await custodyForEvent(eventId);
  if (!custody?.storage_locator || custody.custody_state !== "stored") throw new Error("Original email is not available in raw-message custody.");
  const expectedHash = custody.raw_mime_sha256?.trim().toLowerCase() ?? "";
  if (!SHA256.test(expectedHash)) throw new Error("Raw-message custody hash is unavailable or invalid.");
  const raw = await downloadRawMessage(storagePath(custody.storage_locator), custody.byte_length);
  if (await sha256Hex(raw) !== expectedHash) throw new Error("Raw email does not match the custody hash.");

  const parsed = await PostalMime.parse(raw);
  const html = parsed.html?.trim() ?? "";
  if (!html) {
    return { ok: true, eventId, kind: "text", text: parsed.text?.trim() ?? "", remoteImagesBlocked: false, inlineImageCount: 0 };
  }
  const inlineImages = buildInlineImages(parsed.attachments ?? []);
  const sanitized = sanitizedEmailDocument(html, inlineImages);
  return {
    ok: true,
    eventId,
    kind: "html",
    document: sanitized.document,
    remoteImagesBlocked: sanitized.remoteImagesBlocked,
    inlineImageCount: inlineImages.size,
  };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) return json({ error: "Presentation service configuration is unavailable." }, 503);

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: "Authentication required." }, 401);

  let conversationId = "";
  let eventId = "";
  try {
    const body = await request.json() as { conversationId?: string; eventId?: string };
    conversationId = body.conversationId?.trim() ?? "";
    eventId = body.eventId?.trim() ?? "";
  } catch {
    return json({ error: "Valid JSON body required." }, 400);
  }
  if (!UUID.test(conversationId) || !UUID.test(eventId)) return json({ error: "Conversation or message reference is invalid." }, 400);

  try {
    const detail = await rpc<DetailPacket>(
      "institutional_conversation_detail_self_v3",
      { p_institutional_conversation_id: conversationId },
      authorization,
      SUPABASE_ANON_KEY,
    );
    const authorized = (detail?.messages ?? []).some((message) => message.communication_event_id === eventId);
    if (!authorized) return json({ error: "That message is not available to this Atlas account." }, 403);
  } catch (error) {
    console.error("Mailroom presentation authorization failed", error instanceof Error ? error.message : String(error));
    return json({ error: "That message is not available to this Atlas account." }, 403);
  }

  try {
    return json(await presentationForEvent(eventId));
  } catch (error) {
    console.error("Mailroom presentation projection failed", { eventId, error: error instanceof Error ? error.message : String(error) });
    return json({ error: "Atlas could not prepare the sender-designed email view." }, 422);
  }
});
