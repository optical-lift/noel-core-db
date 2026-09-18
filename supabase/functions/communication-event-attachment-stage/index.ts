import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import PostalMime from "npm:postal-mime@3.0.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/i;
const RAW_BUCKET = "atlas-communication-raw";
const OUTBOUND_BUCKET = "atlas-communication-outbound-attachments";
const MAX_RAW_BYTES = 10 * 1024 * 1024;
const MAX_OUTBOUND_ATTACHMENT_BYTES = 50 * 1024 * 1024;

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type DetailAttachment = { attachmentId?: string | null };
type DetailEvent = {
  communicationEventId?: string;
  communicationEndpointId?: string | null;
  presentationAvailable?: boolean;
  attachments?: DetailAttachment[];
};
type DetailPacket = {
  identityRoot?: string;
  communicationConversationId?: string;
  events?: DetailEvent[];
};
type CustodyRow = {
  raw_mime_sha256?: string | null;
  byte_length?: number | null;
  storage_locator?: string | null;
  custody_state?: string | null;
};
type AttachmentRow = {
  id: string;
  event_id: string;
  source_attachment_ref: string;
  source_content_hash?: string | null;
  transfer_name?: string | null;
  mime_type?: string | null;
};
type PreparedAttachment = {
  attachmentId: string;
  storageBucket: string;
  storageObjectPath: string;
  fileName?: string | null;
  mimeType?: string | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json", "cache-control": "private, no-store" },
  });
}

async function rpc<T>(
  functionName: string,
  args: Record<string, unknown>,
  authorization: string,
  apikey = SUPABASE_ANON_KEY,
): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(functionName)}`, {
    method: "POST",
    headers: { apikey, Authorization: authorization, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${functionName} failed (${response.status}): ${text.slice(0, 500)}`);
  return (text ? JSON.parse(text) : null) as T;
}

async function serviceRows<T>(path: string): Promise<T[]> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      "Accept-Profile": "atlas",
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Custody lookup failed (${response.status}): ${text.slice(0, 500)}`);
  return (text ? JSON.parse(text) : []) as T[];
}

async function custodyForEvent(eventId: string): Promise<CustodyRow | null> {
  const params = new URLSearchParams({
    communication_event_id: `eq.${eventId}`,
    custody_state: "eq.stored",
    select: "raw_mime_sha256,byte_length,storage_locator,custody_state",
    order: "recorded_at.desc",
    limit: "1",
  });
  return (await serviceRows<CustodyRow>(`communication_raw_message_custody?${params}`))[0] ?? null;
}

async function attachmentEvidence(eventId: string, attachmentId: string): Promise<AttachmentRow | null> {
  const params = new URLSearchParams({
    id: `eq.${attachmentId}`,
    event_id: `eq.${eventId}`,
    select: "id,event_id,source_attachment_ref,source_content_hash,transfer_name,mime_type",
    limit: "1",
  });
  return (await serviceRows<AttachmentRow>(`communication_attachments?${params}`))[0] ?? null;
}

function storagePath(locator: string) {
  const prefix = `${RAW_BUCKET}/`;
  if (!locator.startsWith(prefix)) throw new Error("Raw-message storage locator is outside the governed custody bucket.");
  const path = locator.slice(prefix.length);
  if (!path || path.includes("..")) throw new Error("Raw-message storage locator is invalid.");
  return path;
}

async function downloadRawMessage(path: string, expectedBytes?: number | null) {
  if (expectedBytes && expectedBytes > MAX_RAW_BYTES) throw new Error("Raw email exceeds the attachment recovery size limit.");
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(
    `${SUPABASE_URL}/storage/v1/object/authenticated/${encodeURIComponent(RAW_BUCKET)}/${encoded}`,
    {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  );
  if (!response.ok) throw new Error(`Raw email download failed (${response.status}).`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_RAW_BYTES) throw new Error("Raw email exceeds the attachment recovery size limit.");
  if (expectedBytes && bytes.byteLength !== expectedBytes) throw new Error("Raw email length does not match the custody record.");
  return bytes;
}

async function sha256Hex(bytes: Uint8Array) {
  const owned = new Uint8Array(bytes.byteLength);
  owned.set(bytes);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", owned.buffer));
  return Array.from(digest).map((value) => value.toString(16).padStart(2, "0")).join("");
}

function ownedBytes(content: unknown) {
  if (content instanceof Uint8Array) {
    const bytes = new Uint8Array(content.byteLength);
    bytes.set(content);
    return bytes;
  }
  if (content instanceof ArrayBuffer) return new Uint8Array(content.slice(0));
  throw new Error("Parsed attachment has no recoverable byte content.");
}

function normalizeCid(value?: string | null) {
  return (value ?? "").trim().replace(/^<|>$/g, "").toLowerCase();
}

async function recoverAttachment(raw: Uint8Array, evidence: AttachmentRow) {
  const parsed = await PostalMime.parse(raw);
  const attachments = parsed.attachments ?? [];
  const sourceRef = evidence.source_attachment_ref.trim();
  const indexed = sourceRef.match(/^(\d+):([0-9a-f]{64})$/i);
  let candidate: (typeof attachments)[number] | undefined;

  if (indexed) {
    candidate = attachments[Number(indexed[1])];
  } else {
    const wantedCid = normalizeCid(sourceRef);
    candidate = attachments.find((attachment) => normalizeCid(attachment.contentId) === wantedCid);
  }
  if (!candidate) throw new Error("The exact source attachment is not present in raw-message custody.");

  const bytes = ownedBytes(candidate.content);
  const hash = await sha256Hex(bytes);
  const expectedHash = (evidence.source_content_hash ?? "").trim().toLowerCase();
  if (!SHA256.test(expectedHash) || hash !== expectedHash) {
    throw new Error("Recovered attachment bytes do not match the immutable attachment evidence hash.");
  }
  if (indexed && indexed[2].toLowerCase() !== hash) {
    throw new Error("Recovered attachment does not match its source attachment reference.");
  }
  if (bytes.byteLength > MAX_OUTBOUND_ATTACHMENT_BYTES) {
    throw new Error("Recovered attachment exceeds the outbound attachment size limit.");
  }

  return {
    bytes,
    sha256: hash,
    fileName: evidence.transfer_name?.trim() || candidate.filename?.trim() || "forwarded-attachment",
    mimeType: evidence.mime_type?.trim() || candidate.mimeType?.trim() || "application/octet-stream",
  };
}

async function uploadOutbound(path: string, mimeType: string, bytes: Uint8Array) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(
    `${SUPABASE_URL}/storage/v1/object/${encodeURIComponent(OUTBOUND_BUCKET)}/${encoded}`,
    {
      method: "POST",
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        "content-type": mimeType,
        "x-upsert": "false",
      },
      body: bytes,
    },
  );
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Outbound attachment staging upload failed (${response.status}): ${detail.slice(0, 300)}`);
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return json({ error: "Attachment staging configuration is unavailable." }, 503);
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: "Authentication required." }, 401);

  let communicationConversationId = "";
  let eventId = "";
  let attachmentId = "";
  let communicationEndpointId = "";
  try {
    const body = await request.json() as {
      communicationConversationId?: string;
      eventId?: string;
      attachmentId?: string;
      communicationEndpointId?: string;
    };
    communicationConversationId = body.communicationConversationId?.trim() ?? "";
    eventId = body.eventId?.trim() ?? "";
    attachmentId = body.attachmentId?.trim() ?? "";
    communicationEndpointId = body.communicationEndpointId?.trim() ?? "";
  } catch {
    return json({ error: "Valid JSON body required." }, 400);
  }

  if (
    !UUID.test(communicationConversationId)
    || !UUID.test(eventId)
    || !UUID.test(attachmentId)
    || !UUID.test(communicationEndpointId)
  ) return json({ error: "Conversation, Event, attachment, or Endpoint reference is invalid." }, 400);

  let authorizedEvent: DetailEvent | undefined;
  try {
    const detail = await rpc<DetailPacket>(
      "organization_correspondence_conversation_self_api_v5",
      { p_communication_conversation_id: communicationConversationId },
      authorization,
    );
    if (
      detail?.identityRoot !== "communication_conversation"
      || detail.communicationConversationId !== communicationConversationId
    ) throw new Error("Conversation custody mismatch.");
    authorizedEvent = (detail.events ?? []).find((event) => event.communicationEventId === eventId);
    if (
      !authorizedEvent
      || authorizedEvent.communicationEndpointId !== communicationEndpointId
      || !(authorizedEvent.attachments ?? []).some((attachment) => attachment.attachmentId === attachmentId)
    ) throw new Error("Attachment is outside the exact Event/Endpoint custody boundary.");
  } catch (error) {
    console.error("Communication attachment authorization failed", error instanceof Error ? error.message : String(error));
    return json({ error: "That Communication Event attachment is not available to this Atlas account." }, 403);
  }

  try {
    const [custody, evidence] = await Promise.all([
      custodyForEvent(eventId),
      attachmentEvidence(eventId, attachmentId),
    ]);
    if (!custody?.storage_locator || custody.custody_state !== "stored") {
      return json({ error: "Original attachment bytes are not available in raw-message custody." }, 422);
    }
    if (!evidence) return json({ error: "Attachment evidence is unavailable." }, 422);

    const expectedRawHash = custody.raw_mime_sha256?.trim().toLowerCase() ?? "";
    if (!SHA256.test(expectedRawHash)) throw new Error("Raw-message custody hash is unavailable or invalid.");
    const raw = await downloadRawMessage(storagePath(custody.storage_locator), custody.byte_length);
    if (await sha256Hex(raw) !== expectedRawHash) throw new Error("Raw email does not match the custody hash.");

    const recovered = await recoverAttachment(raw, evidence);
    const prepared = await rpc<PreparedAttachment>(
      "prepare_communication_outbound_attachment_self_api_v1",
      {
        p_communication_endpoint_id: communicationEndpointId,
        p_file_name: recovered.fileName,
        p_mime_type: recovered.mimeType,
        p_metadata: {
          source: "communication_event_attachment_forward",
          sourceCommunicationConversationId: communicationConversationId,
          sourceCommunicationEventId: eventId,
          sourceAttachmentId: attachmentId,
          sourceContentHash: recovered.sha256,
        },
      },
      authorization,
    );

    if (prepared.storageBucket !== OUTBOUND_BUCKET || !prepared.storageObjectPath || !UUID.test(prepared.attachmentId)) {
      throw new Error("Outbound attachment preparation returned an invalid custody target.");
    }
    await uploadOutbound(prepared.storageObjectPath, recovered.mimeType, recovered.bytes);

    await rpc(
      "confirm_communication_outbound_attachment_self_api_v1",
      {
        p_attachment_id: prepared.attachmentId,
        p_sha256: recovered.sha256,
        p_byte_length: recovered.bytes.byteLength,
      },
      authorization,
    );

    return json({
      ok: true,
      contractVersion: "communication_event_attachment_stage_v1",
      identityRoot: "communication_event",
      communicationConversationId,
      sourceCommunicationEventId: eventId,
      sourceAttachmentId: attachmentId,
      communicationEndpointId,
      outboundAttachment: {
        attachmentId: prepared.attachmentId,
        fileName: recovered.fileName,
        mimeType: recovered.mimeType,
        byteLength: recovered.bytes.byteLength,
        sha256: recovered.sha256,
        state: "ready",
      },
    });
  } catch (error) {
    console.error("Communication attachment staging failed", {
      eventId,
      attachmentId,
      error: error instanceof Error ? error.message : String(error),
    });
    return json({ error: "Atlas could not stage that exact attachment for forwarding." }, 422);
  }
});
