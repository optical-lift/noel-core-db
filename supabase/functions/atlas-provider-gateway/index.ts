import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FAKE_PROVIDER_SECRET = Deno.env.get("ATLAS_FAKE_PROVIDER_SECRET") ?? "";

type Json = Record<string, unknown>;

type FakeMessage = {
  eventRef: string;
  threadRef?: string | null;
  occurredAt?: string | null;
  direction: "incoming" | "outgoing" | "unknown";
  speaker?: { isSelf?: boolean; address?: string | null };
  body?: string | null;
  participants: Array<{ addressKind: string; address: string; isSelf?: boolean; role?: string }>;
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function sha256(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function serviceRpc<T>(name: string, args: Json): Promise<T> {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Provider gateway service configuration is unavailable.");
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${name} failed (${r.status}): ${text.slice(0, 1000)}`);
  return (text ? JSON.parse(text) : null) as T;
}

function assertFakeMessage(value: unknown): asserts value is FakeMessage {
  if (!value || typeof value !== "object") throw new Error("Fake provider message must be an object.");
  const m = value as Record<string, unknown>;
  if (typeof m.eventRef !== "string" || !m.eventRef.trim()) throw new Error("eventRef is required.");
  if (!(["incoming", "outgoing", "unknown"] as unknown[]).includes(m.direction)) throw new Error("direction is invalid.");
  if (!Array.isArray(m.participants) || m.participants.length < 1) throw new Error("participants are required.");
}

async function canonicalFakeEvent(sourceAccountKey: string, message: FakeMessage) {
  const bodyState = message.body === null || message.body === undefined || message.body === "" ? "empty" : "exact_text";
  const sourcePayload = {
    adapter: "atlas_fake_provider_v1",
    threadRef: message.threadRef ?? null,
  };
  const hashMaterial = JSON.stringify({
    eventRef: message.eventRef,
    threadRef: message.threadRef ?? null,
    occurredAt: message.occurredAt ?? null,
    direction: message.direction,
    speaker: message.speaker ?? {},
    body: message.body ?? null,
    participants: message.participants,
  });
  return {
    schemaVersion: "atlas_communication_event_v1",
    source: {
      kind: "fake",
      accountRef: sourceAccountKey,
      eventRef: message.eventRef,
      threadRef: message.threadRef ?? null,
    },
    captureMode: "provider_webhook",
    occurredAt: message.occurredAt ?? null,
    capturedAt: new Date().toISOString(),
    direction: message.direction,
    speaker: {
      isSelf: Boolean(message.speaker?.isSelf),
      address: message.speaker?.address ?? null,
    },
    body: message.body ?? null,
    bodyState,
    participants: message.participants.map((p) => ({
      addressKind: p.addressKind,
      address: p.address,
      isSelf: Boolean(p.isSelf),
      role: p.role ?? "participant",
    })),
    sourcePayload,
    sourceAuthority: "evidence_only",
    permittedStateEffect: "append_source_attributed_evidence_only",
    governingStateChanged: false,
    contentHash: await sha256(hashMaterial),
  };
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname.endsWith("/health")) {
      return response({ ok: true, adapter: "atlas_fake_provider_v1" });
    }
    if (req.method !== "POST" || !url.pathname.endsWith("/fake/webhook")) return response({ error: "Not found" }, 404);

    if (!FAKE_PROVIDER_SECRET || req.headers.get("x-atlas-fake-provider-secret") !== FAKE_PROVIDER_SECRET) {
      return response({ error: "Invalid fake provider signature." }, 401);
    }

    const connectedSourceId = req.headers.get("x-atlas-connected-source-id")?.trim() ?? "";
    const providerAccountKey = req.headers.get("x-atlas-provider-account-key")?.trim() ?? "";
    const deliveryKey = req.headers.get("x-atlas-provider-delivery-key")?.trim() ?? "";
    if (!connectedSourceId || !providerAccountKey || !deliveryKey) return response({ error: "Source, account, and delivery headers are required." }, 400);

    const raw = await req.text();
    const payloadHash = await sha256(raw);
    const body = JSON.parse(raw) as { messages?: unknown[] };
    if (!Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 100) return response({ error: "messages must contain 1-100 fake provider messages." }, 400);

    const delivery = await serviceRpc<{ deliveryId: string; state: string; shouldProcess: boolean }>("record_provider_webhook_delivery_service_v1", {
      p_connected_source_id: connectedSourceId,
      p_provider_key: "fake",
      p_provider_delivery_key: deliveryKey,
      p_payload_sha256: payloadHash,
      p_metadata: { adapter: "atlas_fake_provider_v1" },
    });

    if (!delivery.shouldProcess) return response({ ok: delivery.state !== "conflict", delivery, replay: true }, delivery.state === "conflict" ? 409 : 200);

    const events = [];
    for (const item of body.messages) {
      assertFakeMessage(item);
      events.push(await canonicalFakeEvent(providerAccountKey, item));
    }

    const receipt = await serviceRpc<Json>("ingest_provider_webhook_events_service_v1", {
      p_provider_webhook_delivery_id: delivery.deliveryId,
      p_events: events,
      p_manifest: { adapter: "atlas_fake_provider_v1", providerDeliveryKey: deliveryKey },
    });

    return response({ ok: true, delivery, receipt });
  } catch (error) {
    console.error(error);
    return response({ error: error instanceof Error ? error.message : "Provider gateway failed." }, 500);
  }
});
