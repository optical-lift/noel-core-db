import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const META_GRAPH_VERSION = Deno.env.get("ATLAS_META_GRAPH_VERSION") ?? "";

type Json = Record<string, unknown>;
type RelayAuth = {
  authorized?: boolean;
  transportKind?: string;
  connectedSourceId?: string;
  providerKey?: string;
  providerAccountKey?: string;
  communicationEndpointId?: string;
};
type LeaseItem = {
  id?: string;
  operation_kind?: string;
};
type TransportPayload = {
  outboundOperationId?: string;
  connectedSourceId?: string;
  communicationEndpointId?: string;
  institutionalConversationId?: string;
  initiatedByMembershipId?: string;
  to?: Array<{ addressKind?: string; address?: string; role?: string; provider?: string }>;
  bodyText?: string;
  replyToCommunicationEventId?: string;
  contentSha256?: string;
};

type ReplyContext = {
  sourceThreadRef?: string;
  messageId?: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function requiredConfig() {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !META_GRAPH_VERSION) {
    throw new Error("Facebook outbound transport configuration is incomplete.");
  }
}

async function sha256(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function rpc<T>(name: string, args: Json) {
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

function safeProviderBody(text: string) {
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object") return parsed as Json;
  } catch {
    // Keep an intentionally short non-secret body excerpt for transport diagnostics.
  }
  return { rawExcerpt: text.slice(0, 500) };
}

function stableEventProjection(event: Json) {
  const copy = structuredClone(event);
  delete copy.capturedAt;
  delete copy.contentHash;
  return copy;
}

async function canonicalAcceptedEvent(
  pageId: string,
  recipient: string,
  messageId: string,
  bodyText: string,
  threadRef: string,
  replyToProviderMessageId: string | null,
  outboundOperationId: string,
) {
  const occurredAt = new Date().toISOString();
  const event: Json = {
    schemaVersion: "atlas_communication_event_v1",
    source: {
      kind: "facebook",
      accountRef: pageId,
      eventRef: messageId,
      threadRef,
    },
    captureMode: "provider_transport",
    occurredAt,
    capturedAt: occurredAt,
    direction: "outgoing",
    speaker: { isSelf: true, address: pageId },
    body: bodyText,
    bodyState: "exact_text",
    participants: [
      { addressKind: "social", address: pageId, isSelf: true, role: "page" },
      { addressKind: "social", address: recipient, isSelf: false, role: "recipient" },
    ],
    sourcePayload: {
      adapter: "atlas_facebook_outbound_v1",
      messageId,
      replyTo: replyToProviderMessageId,
      outboundOperationId,
    },
    sourceAuthority: "evidence_only",
    permittedStateEffect: "append_source_attributed_evidence_only",
    governingStateChanged: false,
  };
  event.contentHash = await sha256(JSON.stringify(stableEventProjection(event)));
  return event;
}

async function sendFacebookText(pageId: string, pageToken: string, recipient: string, bodyText: string) {
  const url = `https://graph.facebook.com/${META_GRAPH_VERSION}/${encodeURIComponent(pageId)}/messages`;
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${pageToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        recipient: { id: recipient },
        messaging_type: "RESPONSE",
        message: { text: bodyText },
      }),
    });
  } catch (error) {
    return {
      proven: false as const,
      uncertainty: "network_error_after_transport_attempt",
      diagnostic: error instanceof Error ? error.message.slice(0, 500) : "network error",
    };
  }

  const text = await response.text();
  const providerBody = safeProviderBody(text);
  if (response.ok) {
    const messageId = String(providerBody.message_id ?? "").trim();
    const recipientId = String(providerBody.recipient_id ?? "").trim();
    if (!messageId) {
      return {
        proven: false as const,
        uncertainty: "provider_success_without_message_id",
        status: response.status,
        providerBody,
      };
    }
    return {
      proven: true as const,
      accepted: true as const,
      status: response.status,
      messageId,
      recipientId,
      providerBody,
    };
  }

  if (response.status === 429) {
    return {
      proven: true as const,
      accepted: false as const,
      resultState: "temporary_failure" as const,
      status: response.status,
      providerBody,
    };
  }
  if (response.status >= 500) {
    return {
      proven: false as const,
      uncertainty: "provider_5xx_after_transport_attempt",
      status: response.status,
      providerBody,
    };
  }
  return {
    proven: true as const,
    accepted: false as const,
    resultState: "rejected" as const,
    status: response.status,
    providerBody,
  };
}

async function processOperation(
  sourceId: string,
  pageId: string,
  pageToken: string,
  leaseOwner: string,
  item: LeaseItem,
) {
  const operationId = String(item.id ?? "").trim();
  if (!operationId) return { state: "ignored", reason: "missing_operation_id" };
  if (String(item.operation_kind ?? "") !== "social_reply") {
    return { outboundOperationId: operationId, state: "left_leased_for_uncertainty_reconciliation", reason: "unsupported_operation_kind" };
  }

  const payload = await rpc<TransportPayload>("communication_outbound_transport_payload_service_v1", {
    p_outbound_operation_id: operationId,
  });
  if (String(payload.connectedSourceId ?? "") !== sourceId) {
    return { outboundOperationId: operationId, state: "left_leased_for_uncertainty_reconciliation", reason: "source_mismatch" };
  }
  const recipients = Array.isArray(payload.to) ? payload.to : [];
  if (recipients.length !== 1) {
    return { outboundOperationId: operationId, state: "left_leased_for_uncertainty_reconciliation", reason: "social_reply_requires_one_recipient" };
  }
  const recipient = String(recipients[0]?.address ?? "").trim();
  const bodyText = String(payload.bodyText ?? "");
  const replyEventId = String(payload.replyToCommunicationEventId ?? "").trim();
  if (!recipient || !bodyText.trim() || !replyEventId) {
    return { outboundOperationId: operationId, state: "left_leased_for_uncertainty_reconciliation", reason: "incomplete_authorized_payload" };
  }

  const replyContext = await rpc<ReplyContext>("communication_reply_transport_context_service_v1", {
    p_communication_event_id: replyEventId,
  });
  const threadRef = String(replyContext.sourceThreadRef ?? "").trim();
  if (!threadRef) {
    return { outboundOperationId: operationId, state: "left_leased_for_uncertainty_reconciliation", reason: "missing_source_thread_continuity" };
  }

  const transport = await sendFacebookText(pageId, pageToken, recipient, bodyText);
  if (!transport.proven) {
    return {
      outboundOperationId: operationId,
      state: "transport_uncertain_pending_lease_reconciliation",
      uncertainty: transport.uncertainty,
      status: "status" in transport ? transport.status : null,
    };
  }

  if (!transport.accepted) {
    const receipt = await rpc<Json>("record_communication_outbound_result_service_v1", {
      p_outbound_operation_id: operationId,
      p_lease_owner: leaseOwner,
      p_result_state: transport.resultState,
      p_provider_message_ref: null,
      p_provider_response: {
        provider: "facebook",
        httpStatus: transport.status,
        response: transport.providerBody,
        deliveryProven: false,
        readProven: false,
      },
      p_canonical_event: null,
    });
    return { outboundOperationId: operationId, state: transport.resultState, receipt };
  }

  const canonicalEvent = await canonicalAcceptedEvent(
    pageId,
    recipient,
    transport.messageId,
    bodyText,
    threadRef,
    replyContext.messageId ? String(replyContext.messageId) : null,
    operationId,
  );
  const receipt = await rpc<Json>("record_communication_outbound_result_service_v1", {
    p_outbound_operation_id: operationId,
    p_lease_owner: leaseOwner,
    p_result_state: "accepted",
    p_provider_message_ref: transport.messageId,
    p_provider_response: {
      provider: "facebook",
      httpStatus: transport.status,
      recipientId: transport.recipientId || recipient,
      messageId: transport.messageId,
      deliveryProven: false,
      readProven: false,
    },
    p_canonical_event: canonicalEvent,
  });
  return { outboundOperationId: operationId, state: "accepted", providerMessageRef: transport.messageId, receipt };
}

async function drain(req: Request) {
  const relayKey = req.headers.get("x-atlas-relay-key") ?? "";
  const relaySecret = req.headers.get("x-atlas-relay-secret") ?? "";
  if (!relayKey || !relaySecret) return json({ error: "Outbound relay credentials required." }, 401);

  const relay = await rpc<RelayAuth>("authenticate_communication_outbound_transport_relay_service_v1", {
    p_relay_key: relayKey,
    p_secret_sha256: await sha256(relaySecret),
  });
  if (!relay.authorized) return json({ error: "Outbound relay authorization failed." }, 403);
  if (relay.providerKey !== "facebook" || !relay.connectedSourceId || !relay.providerAccountKey) {
    return json({ error: "Relay is not bound to a Facebook connected source." }, 400);
  }

  let requestedLimit = 10;
  try {
    const body = await req.json() as { limit?: number };
    requestedLimit = Number(body.limit ?? 10) || 10;
  } catch {
    // Empty body uses the safe default.
  }
  const limit = Math.max(1, Math.min(requestedLimit, 20));
  const sourceId = relay.connectedSourceId;
  const pageId = relay.providerAccountKey;

  const reconciliation = await rpc<Json>("mark_expired_communication_outbound_leases_uncertain_service_v1", {
    p_connected_source_id: sourceId,
  });
  const leaseOwner = `facebook-outbound:${crypto.randomUUID()}`;
  const lease = await rpc<{ items?: LeaseItem[] }>("lease_communication_outbound_operations_service_v1", {
    p_connected_source_id: sourceId,
    p_lease_owner: leaseOwner,
    p_limit: limit,
    p_lease_seconds: 120,
  });
  const items = Array.isArray(lease.items) ? lease.items : [];
  if (!items.length) {
    return json({ ok: true, contractVersion: "facebook_outbound_drain_v1", leased: 0, results: [], reconciliation });
  }

  const pageToken = await rpc<string>("read_connected_source_secret_service_v1", {
    p_connected_source_id: sourceId,
    p_credential_kind: "page_access_token",
  });
  if (!pageToken) throw new Error("Facebook Page access token is unavailable from Vault custody.");

  const results: unknown[] = [];
  for (const item of items) {
    try {
      results.push(await processOperation(sourceId, pageId, pageToken, leaseOwner, item));
    } catch (error) {
      console.error("Facebook outbound operation became uncertain", item.id, error);
      results.push({
        outboundOperationId: item.id ?? null,
        state: "transport_uncertain_pending_lease_reconciliation",
        reason: "unhandled_transport_worker_error",
      });
    }
  }
  return json({
    ok: true,
    contractVersion: "facebook_outbound_drain_v1",
    connectedSourceId: sourceId,
    communicationEndpointId: relay.communicationEndpointId ?? null,
    leased: items.length,
    results,
    reconciliation,
    truthBoundary: {
      providerAcceptanceRequiredForSentState: true,
      networkAmbiguityIsNotFailureProof: true,
      automaticResendAfterAmbiguity: false,
      deliveryProvenBySendApiResponse: false,
      readProvenBySendApiResponse: false,
    },
  });
}

Deno.serve(async (req) => {
  try {
    requiredConfig();
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname.endsWith("/health")) {
      return json({ ok: true, adapter: "atlas_facebook_outbound_v1" });
    }
    if (req.method === "POST" && url.pathname.endsWith("/facebook/drain")) {
      return await drain(req);
    }
    return json({ error: "Not found" }, 404);
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Facebook outbound transport failed." }, 500);
  }
});
