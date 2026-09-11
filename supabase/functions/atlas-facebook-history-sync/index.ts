import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const META_GRAPH_VERSION = Deno.env.get("ATLAS_META_GRAPH_VERSION") ?? "";

type Json = Record<string, unknown>;
type Conversation = {
  id?: string;
  updated_time?: string;
  participants?: { data?: Array<{ id?: string; name?: string }> };
};
type ProviderMessage = {
  id?: string;
  created_time?: string;
  from?: { id?: string; name?: string };
  to?: { data?: Array<{ id?: string; name?: string }> };
  message?: string;
  attachments?: { data?: Json[] };
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function requiredConfig() {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !META_GRAPH_VERSION) {
    throw new Error("Facebook history sync configuration is incomplete.");
  }
}

async function sha256(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function rpc<T>(name: string, args: Json, authorization: string) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${name} failed (${r.status}): ${text.slice(0, 1000)}`);
  return (text ? JSON.parse(text) : null) as T;
}

function serviceRpc<T>(name: string, args: Json) {
  return rpc<T>(name, args, `Bearer ${SERVICE_ROLE_KEY}`);
}

async function metaJson<T>(url: string) {
  const r = await fetch(url);
  const text = await r.text();
  if (!r.ok) throw new Error(`Meta request failed (${r.status}): ${text.slice(0, 1000)}`);
  const parsed = text ? JSON.parse(text) : {};
  if (parsed && typeof parsed === "object" && "error" in parsed) {
    throw new Error(`Meta request returned an error: ${text.slice(0, 1000)}`);
  }
  return parsed as T;
}

function stableEventProjection(event: Json) {
  const copy = structuredClone(event);
  delete copy.capturedAt;
  delete copy.contentHash;
  return copy;
}

async function finalizeEvent(event: Json) {
  event.contentHash = await sha256(JSON.stringify(stableEventProjection(event)));
  return event;
}

function canonicalParticipants(pageId: string, message: ProviderMessage) {
  const seen = new Set<string>();
  const participants: Json[] = [];
  const push = (id: string, name: string | undefined, isSelf: boolean, role: string) => {
    const key = id.trim();
    if (!key || seen.has(key)) return;
    seen.add(key);
    participants.push({
      addressKind: "social",
      address: key,
      displayName: name ?? null,
      isSelf,
      role,
    });
  };

  push(pageId, undefined, true, "page");
  const fromId = String(message.from?.id ?? "");
  if (fromId) push(fromId, message.from?.name, fromId === pageId, "sender");
  for (const recipient of message.to?.data ?? []) {
    const id = String(recipient.id ?? "");
    if (id) push(id, recipient.name, id === pageId, "recipient");
  }
  return participants;
}

async function canonicalHistoryMessage(pageId: string, conversationId: string, message: ProviderMessage) {
  const id = String(message.id ?? "").trim();
  const fromId = String(message.from?.id ?? "").trim();
  if (!id || !fromId) return null;

  const isSelf = fromId === pageId;
  const body = typeof message.message === "string" ? message.message : null;
  const providerAttachments = Array.isArray(message.attachments?.data) ? message.attachments!.data! : [];
  const event: Json = {
    schemaVersion: "atlas_communication_event_v1",
    source: {
      kind: "facebook",
      accountRef: pageId,
      eventRef: id,
      threadRef: `messenger-conversation:${conversationId}`,
    },
    captureMode: "provider_sync",
    occurredAt: message.created_time ?? null,
    capturedAt: new Date().toISOString(),
    direction: isSelf ? "outgoing" : "incoming",
    speaker: {
      isSelf,
      address: fromId,
      displayName: message.from?.name ?? null,
    },
    body,
    bodyState: body ? "exact_text" : "empty",
    participants: canonicalParticipants(pageId, message),
    sourcePayload: {
      adapter: "atlas_facebook_history_sync_v1",
      conversationId,
      messageId: id,
      providerAttachments,
      historicalBackfill: true,
    },
    sourceAuthority: "evidence_only",
    permittedStateEffect: "append_source_attributed_evidence_only",
    governingStateChanged: false,
  };
  return await finalizeEvent(event);
}

async function listConversations(pageId: string, pageToken: string, after: string | null, limit: number) {
  const u = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/${encodeURIComponent(pageId)}/conversations`);
  u.searchParams.set("platform", "messenger");
  u.searchParams.set("fields", "id,updated_time,participants");
  u.searchParams.set("limit", String(limit));
  u.searchParams.set("access_token", pageToken);
  if (after) u.searchParams.set("after", after);
  return await metaJson<{
    data?: Conversation[];
    paging?: { cursors?: { after?: string }; next?: string };
  }>(u.toString());
}

async function listAllMessages(conversationId: string, pageToken: string) {
  let next: string | null = (() => {
    const u = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/${encodeURIComponent(conversationId)}/messages`);
    u.searchParams.set("fields", "id,created_time,from,to,message,attachments");
    u.searchParams.set("limit", "100");
    u.searchParams.set("access_token", pageToken);
    return u.toString();
  })();
  const messages: ProviderMessage[] = [];
  let pages = 0;
  while (next && pages < 25 && messages.length < 1000) {
    const result = await metaJson<{ data?: ProviderMessage[]; paging?: { next?: string } }>(next);
    messages.push(...(Array.isArray(result.data) ? result.data : []));
    next = result.paging?.next ?? null;
    pages += 1;
  }
  return { messages: messages.slice(0, 1000), truncated: Boolean(next) };
}

async function ingestChunk(sourceId: string, pageId: string, conversation: Conversation, events: Json[]) {
  if (!events.length) return null;
  return await serviceRpc<Json>("ingest_provider_history_events_service_v1", {
    p_connected_source_id: sourceId,
    p_events: events,
    p_manifest: {
      adapter: "atlas_facebook_history_sync_v1",
      provider: "facebook",
      providerAccountKey: pageId,
      providerConversationId: conversation.id ?? null,
      providerConversationUpdatedAt: conversation.updated_time ?? null,
      historicalCoverage: {
        providerReportedOnly: true,
        requestsFolderInactiveOver30DaysMayBeAbsent: true,
        completenessNotAsserted: true,
      },
    },
  });
}

async function syncHistory(req: Request) {
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: "Signed-in Atlas session required." }, 401);

  const body = await req.json() as {
    connectedSourceId?: string;
    after?: string | null;
    conversationLimit?: number;
  };
  const sourceId = String(body.connectedSourceId ?? "").trim();
  if (!sourceId) return json({ error: "connectedSourceId is required." }, 400);
  const limit = Math.max(1, Math.min(Number(body.conversationLimit ?? 25) || 25, 100));
  const after = typeof body.after === "string" && body.after.trim() ? body.after.trim() : null;

  const context = await rpc<Json>("provider_history_sync_context_self_api_v1", {
    p_connected_source_id: sourceId,
  }, authorization);
  if (String(context.providerKey ?? "") !== "facebook") {
    return json({ error: "This history adapter currently supports Facebook Page sources only." }, 400);
  }

  const pageId = String(context.providerAccountKey ?? "").trim();
  if (!pageId) throw new Error("Facebook Page source identity is unavailable.");
  const pageToken = await serviceRpc<string>("read_connected_source_secret_service_v1", {
    p_connected_source_id: sourceId,
    p_credential_kind: "page_access_token",
  });
  if (!pageToken) throw new Error("Facebook Page access token is unavailable from Vault custody.");

  const conversations = await listConversations(pageId, pageToken, after, limit);
  const receipts: Json[] = [];
  let suppliedMessages = 0;
  let truncatedConversations = 0;

  for (const conversation of conversations.data ?? []) {
    const conversationId = String(conversation.id ?? "").trim();
    if (!conversationId) continue;
    const history = await listAllMessages(conversationId, pageToken);
    if (history.truncated) truncatedConversations += 1;
    const events: Json[] = [];
    for (const message of history.messages) {
      const event = await canonicalHistoryMessage(pageId, conversationId, message);
      if (event) events.push(event);
    }
    suppliedMessages += events.length;
    for (let start = 0; start < events.length; start += 500) {
      const receipt = await ingestChunk(sourceId, pageId, conversation, events.slice(start, start + 500));
      if (receipt) receipts.push(receipt);
    }
  }

  const nextAfter = conversations.paging?.cursors?.after ?? null;
  return json({
    ok: true,
    contractVersion: "facebook_history_sync_receipt_v1",
    connectedSourceId: sourceId,
    provider: "facebook",
    providerAccountKey: pageId,
    conversationsVisited: conversations.data?.length ?? 0,
    messagesSupplied: suppliedMessages,
    ingestReceipts: receipts,
    nextAfter,
    hasMore: Boolean(conversations.paging?.next),
    truncatedConversations,
    coverage: {
      providerReportedOnly: true,
      requestsFolderInactiveOver30DaysMayBeAbsent: true,
      completenessNotAsserted: true,
    },
    truthBoundary: {
      historicalBackfill: true,
      responseWorkCreated: false,
      readStateInferred: false,
      responsibilityInferred: false,
      captureTimeIsNotSourceContent: true,
    },
  });
}

Deno.serve(async (req) => {
  try {
    requiredConfig();
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname.endsWith("/health")) {
      return json({ ok: true, adapter: "atlas_facebook_history_sync_v1" });
    }
    if (req.method === "POST" && url.pathname.endsWith("/facebook/history-sync")) {
      return await syncHistory(req);
    }
    return json({ error: "Not found" }, 404);
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Facebook history sync failed." }, 500);
  }
});
