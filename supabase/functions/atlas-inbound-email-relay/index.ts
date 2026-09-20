import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import PostalMime from "npm:postal-mime@2.7.3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RAW_BUCKET = "atlas-communication-raw";
const MAX_BYTES = 50 * 1024 * 1024;

async function sha256Hex(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Supabase service environment unavailable");
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      "Content-Profile": "atlas",
      "Accept-Profile": "atlas",
    },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${name} failed (${response.status}): ${text.slice(0, 800)}`);
  return text ? JSON.parse(text) as T : (null as T);
}

function clean(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function addressEntries(value: any): Array<{ name?: string; address: string }> {
  const values = !value ? [] : Array.isArray(value) ? value : [value];
  return values.flatMap((entry: any) => {
    const address = clean(entry?.address);
    return address ? [{ name: clean(entry?.name) ?? undefined, address }] : [];
  });
}

function participant(role: string, entry: { name?: string; address: string }, endpointAddress: string) {
  return { role, addressKind: "email", address: entry.address, isSelf: entry.address.trim().toLowerCase() === endpointAddress.trim().toLowerCase(), metadata: entry.name ? { displayName: entry.name } : {} };
}

function referenceIds(value: unknown): string[] {
  const text = Array.isArray(value) ? value.join(" ") : clean(value) ?? "";
  const bracketed = text.match(/<[^>]+>/g);
  if (bracketed?.length) return [...new Set(bracketed.map((v) => v.trim()))];
  return [...new Set(text.split(/\s+/).map((v) => v.trim()).filter(Boolean))];
}

function isoDate(value: unknown, fallback: string) {
  if (typeof value !== "string" || !value.trim()) return fallback;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? fallback : date.toISOString();
}

async function uploadRaw(path: string, bytes: Uint8Array) {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(`${SUPABASE_URL}/storage/v1/object/${RAW_BUCKET}/${encodedPath}`, {
    method: "POST",
    headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}`, "Content-Type": "message/rfc822", "x-upsert": "false" },
    body: bytes,
  });
  if (response.ok || response.status === 409) return;
  const text = await response.text();
  if (response.status === 400 && /duplicate|already exists|resource already exists/i.test(text)) return;
  throw new Error(`raw MIME upload failed (${response.status}): ${text.slice(0, 800)}`);
}

Deno.serve(async (request: Request) => {
  let stage = "request";
  let authenticated = false;
  try {
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    const relayKey = request.headers.get("x-atlas-relay-key")?.trim() ?? "";
    const relaySecret = request.headers.get("x-atlas-relay-secret") ?? "";
    if (!relayKey || !relaySecret) return new Response("Missing relay authentication", { status: 401 });
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > MAX_BYTES) return new Response("Message too large", { status: 413 });

    stage = "authenticate";
    const secretHash = await sha256Hex(relaySecret);
    const auth = await rpc<any>("authenticate_communication_inbound_relay_service_v1", { p_relay_key: relayKey, p_secret_sha256: secretHash });
    if (!auth?.authorized) return new Response("Unauthorized relay", { status: 401 });
    authenticated = true;
    if (auth.endpointKind !== "email") return new Response("Relay endpoint is not email", { status: 409 });

    stage = "read_raw";
    const raw = new Uint8Array(await request.arrayBuffer());
    if (!raw.length) return new Response("Empty message", { status: 400 });
    if (raw.length > MAX_BYTES) return new Response("Message too large", { status: 413 });

    stage = "parse_mime";
    const rawHash = await sha256Hex(raw);
    const parsed = await PostalMime.parse(raw.buffer);
    const messageId = clean(parsed.messageId);
    const refs = referenceIds(parsed.references);
    const inReplyTo = clean(parsed.inReplyTo);
    const eventRef = messageId ? `rfc-message-id:${messageId}` : `relay-raw-sha256:${rawHash}`;
    const threadRef = `rfc-root:${refs[0] ?? inReplyTo ?? messageId ?? rawHash}`;
    const from = addressEntries(parsed.from)[0];
    const to = addressEntries(parsed.to);
    const cc = addressEntries(parsed.cc);
    const bcc = addressEntries(parsed.bcc);
    const participants = [ ...(from ? [participant("sender", from, auth.endpointAddress)] : []), ...to.map((entry) => participant("to", entry, auth.endpointAddress)), ...cc.map((entry) => participant("cc", entry, auth.endpointAddress)), ...bcc.map((entry) => participant("bcc", entry, auth.endpointAddress)) ];
    const exactText = typeof parsed.text === "string" ? parsed.text : undefined;
    const html = typeof parsed.html === "string" ? parsed.html : undefined;
    const body = exactText ?? html ?? null;
    const bodyState = exactText ? "exact_text" : body ? "attributed_body_preserved" : "empty";
    const capturedAt = new Date().toISOString();
    const attachmentRows = await Promise.all((parsed.attachments ?? []).map(async (attachment: any, index: number) => ({
      sourceAttachmentRef: clean(attachment.contentId) ?? `${index}:${await sha256Hex(attachment.content ?? new Uint8Array())}`,
      mimeType: clean(attachment.mimeType) ?? undefined,
      transferName: clean(attachment.filename) ?? undefined,
      sourceContentHash: await sha256Hex(attachment.content ?? new Uint8Array()),
      metadata: { contentId: clean(attachment.contentId), contentDisposition: clean(attachment.disposition), size: attachment.content?.length ?? 0, custody: "preserved_inside_raw_mime" },
    })));

    const canonical = {
      schemaVersion: "atlas_communication_event_v1", sourceAuthority: "evidence_only", permittedStateEffect: "append_source_attributed_evidence_only", governingStateChanged: false,
      source: { kind: auth.providerKey, accountRef: auth.providerAccountKey, eventRef, threadRef }, direction: "incoming",
      speaker: { isSelf: Boolean(from && from.address.toLowerCase() === String(auth.endpointAddress).toLowerCase()), address: from?.address ?? null },
      occurredAt: isoDate(parsed.date, capturedAt), capturedAt, captureMode: "live_relay", bodyState, body, subject: clean(parsed.subject), contentHash: rawHash, participants, attachments: attachmentRows,
      sourcePayload: { messageId, inReplyTo, references: refs, rawMimeSha256: rawHash, htmlAvailable: Boolean(html), relayKey, relayTransport: auth.transportKind },
    };

    stage = "store_raw";
    const rawPath = `org/${auth.organizationId}/source/${auth.connectedSourceId}/${rawHash}.eml`;
    const rawStorageLocator = `${RAW_BUCKET}/${rawPath}`;
    await uploadRaw(rawPath, raw);

    stage = "ingest";
    const ingest = await rpc<any>("ingest_inbound_email_relay_event_service_v1", {
      p_connected_source_id: auth.connectedSourceId,
      p_event: canonical,
      p_manifest: {
        relayKey,
        relayTransport: auth.transportKind,
        rawMimeSha256: rawHash,
        rawByteLength: raw.length,
        rawStorageLocator,
      },
    });

    const ingestReceipt = ingest?.ingestReceipt ?? {};
    const conflicts = Number(ingestReceipt?.conflicts ?? 0);
    const durableDomainConflict = Number.isFinite(conflicts) && conflicts > 0;

    // A conflicting provider revision is durable source evidence, but it is not the
    // canonical Communication Event's raw MIME. The Communication conflict owns the
    // disagreement. Attaching this raw hash to the existing event would incorrectly
    // collapse provider acquisition into domain admission and currently raises a 500.
    if (!durableDomainConflict) {
      stage = "record_raw_custody";
      await rpc("record_communication_raw_message_custody_service_v1", {
        p_communication_event_id: ingest.communicationEventId,
        p_raw_mime_sha256: rawHash,
        p_byte_length: raw.length,
        p_storage_locator: rawStorageLocator,
        p_custody_state: "stored",
        p_metadata: { relayKey, relayTransport: auth.transportKind },
      });
    }

    return Response.json({
      ok: true,
      contractVersion: "atlas_inbound_email_relay_v2",
      acquisitionDisposition: durableDomainConflict ? "domain_conflict_durable" : "domain_admission_complete",
      checkpointSafe: true,
      connectedSourceId: auth.connectedSourceId,
      communicationEventId: ingest.communicationEventId,
      rawMimeSha256: rawHash,
      rawStorageLocator,
      ingestReceipt,
      conversationAdmission: ingest.conversationAdmission,
      responseAdmission: ingest.responseAdmission,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("Inbound email relay failed", { stage, message });
    if (!authenticated) return Response.json({ ok: false, stage, error: "relay authentication path failed", checkpointSafe: false }, { status: 500 });
    return Response.json({ ok: false, stage, error: message.slice(0, 1200), checkpointSafe: false }, { status: 500 });
  }
});
