import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const INSTAGRAM_APP_ID = Deno.env.get("ATLAS_INSTAGRAM_APP_ID") ?? "";
const INSTAGRAM_APP_SECRET = Deno.env.get("ATLAS_INSTAGRAM_APP_SECRET") ?? "";
const INSTAGRAM_REDIRECT_URI = Deno.env.get("ATLAS_INSTAGRAM_REDIRECT_URI") ?? "";
const META_GRAPH_VERSION = Deno.env.get("ATLAS_META_GRAPH_VERSION") ?? "";
const META_WEBHOOK_VERIFY_TOKEN = Deno.env.get("ATLAS_META_WEBHOOK_VERIFY_TOKEN") ?? "";
const AFTER_CONNECT_URI = Deno.env.get("ATLAS_META_AFTER_CONNECT_URI") ?? "";

type Json = Record<string, unknown>;

type SourceResolution = {
  connectedSourceId: string;
  providerKey: string;
  providerAccountKey: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function requiredConfig() {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Supabase service configuration is unavailable.");
  if (!INSTAGRAM_APP_ID || !INSTAGRAM_APP_SECRET || !INSTAGRAM_REDIRECT_URI || !META_GRAPH_VERSION) {
    throw new Error("Instagram provider configuration is incomplete.");
  }
}

async function sha256(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function stableEventProjection(event: Json) {
  const copy = structuredClone(event);
  delete copy.capturedAt;
  delete copy.contentHash;
  return copy;
}

async function hmacSha256Hex(secret: string, text: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text));
  return Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
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

async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, init);
  const text = await r.text();
  if (!r.ok) throw new Error(`Meta request failed (${r.status}): ${text.slice(0, 1000)}`);
  const parsed = text ? JSON.parse(text) : {};
  if (parsed && typeof parsed === "object" && "error" in parsed) throw new Error(`Meta request returned an error: ${text.slice(0, 1000)}`);
  return parsed as T;
}

function parseSessionIdFromState(state: string) {
  const dot = state.indexOf(".");
  const candidate = dot > 0 ? state.slice(0, dot) : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate)) {
    throw new Error("OAuth state does not contain a valid Atlas connection session.");
  }
  return candidate;
}

function instagramAuthorizeUrl(state: string) {
  requiredConfig();
  const u = new URL("https://www.instagram.com/oauth/authorize");
  u.searchParams.set("client_id", INSTAGRAM_APP_ID);
  u.searchParams.set("redirect_uri", INSTAGRAM_REDIRECT_URI);
  u.searchParams.set("response_type", "code");
  u.searchParams.set("scope", [
    "instagram_business_basic",
    "instagram_business_manage_messages",
    "instagram_business_manage_comments",
  ].join(","));
  u.searchParams.set("state", state);
  u.searchParams.set("enable_fb_login", "0");
  u.searchParams.set("force_authentication", "1");
  return u.toString();
}

async function exchangeInstagramCode(code: string) {
  const body = new FormData();
  body.set("client_id", INSTAGRAM_APP_ID);
  body.set("client_secret", INSTAGRAM_APP_SECRET);
  body.set("grant_type", "authorization_code");
  body.set("redirect_uri", INSTAGRAM_REDIRECT_URI);
  body.set("code", code);
  const shortToken = await fetchJson<{ access_token: string; user_id?: string | number }>(
    "https://api.instagram.com/oauth/access_token",
    { method: "POST", body },
  );
  if (!shortToken.access_token) throw new Error("Instagram did not return a short-lived access token.");

  const longUrl = new URL("https://graph.instagram.com/access_token");
  longUrl.searchParams.set("grant_type", "ig_exchange_token");
  longUrl.searchParams.set("client_secret", INSTAGRAM_APP_SECRET);
  longUrl.searchParams.set("access_token", shortToken.access_token);
  const longToken = await fetchJson<{ access_token: string; token_type?: string; expires_in?: number }>(longUrl.toString());
  if (!longToken.access_token) throw new Error("Instagram did not return a long-lived access token.");
  return { ...longToken, shortUserId: shortToken.user_id == null ? null : String(shortToken.user_id) };
}

async function fetchInstagramIdentity(accessToken: string, shortUserId: string | null) {
  const profileUrl = new URL(`https://graph.instagram.com/${META_GRAPH_VERSION}/me`);
  profileUrl.searchParams.set("fields", "id,username");
  profileUrl.searchParams.set("access_token", accessToken);
  const profile = await fetchJson<{ id?: string; username?: string }>(profileUrl.toString());
  const id = String(profile.id ?? shortUserId ?? "").trim();
  if (!id) throw new Error("Instagram account identity was not returned.");
  return { id, username: profile.username?.trim() || id };
}

async function subscribeInstagramWebhooks(accountId: string, accessToken: string) {
  const u = new URL(`https://graph.instagram.com/${META_GRAPH_VERSION}/${encodeURIComponent(accountId)}/subscribed_apps`);
  u.searchParams.set("subscribed_fields", "messages,comments");
  u.searchParams.set("access_token", accessToken);
  const result = await fetchJson<{ success?: boolean }>(u.toString(), { method: "POST" });
  if (result.success !== true) throw new Error("Instagram webhook subscription was not accepted.");
}

async function completeInstagramConnection(state: string, code: string) {
  requiredConfig();
  const sessionId = parseSessionIdFromState(state);
  const stateDigest = await sha256(state);
  await serviceRpc<Json>("validate_provider_connection_callback_service_v1", {
    p_session_id: sessionId,
    p_provider_key: "instagram",
    p_state_nonce_digest: stateDigest,
  });

  const token = await exchangeInstagramCode(code);
  const identity = await fetchInstagramIdentity(token.access_token, token.shortUserId);
  await subscribeInstagramWebhooks(identity.id, token.access_token);

  const completed = await serviceRpc<{ connectedSourceId: string }>("complete_provider_connection_identity_service_v1", {
    p_session_id: sessionId,
    p_provider_account_key: identity.id,
    p_display_label: `@${identity.username}`,
    p_account_hint: identity.username,
    p_granted_scopes: ["instagram_business_basic", "instagram_business_manage_messages", "instagram_business_manage_comments"],
    p_capabilities: {
      communicationCapture: true,
      communicationSend: true,
      directMessages: true,
      comments: true,
    },
    p_metadata: {
      adapter: "atlas_instagram_login_v1",
      tokenExpiresInSeconds: token.expires_in ?? null,
      webhookFields: ["messages", "comments"],
    },
  });

  await serviceRpc<Json>("store_connected_source_secret_service_v1", {
    p_connected_source_id: completed.connectedSourceId,
    p_credential_kind: "access_token",
    p_secret: token.access_token,
    p_description: "Instagram Login long-lived access token",
  });
  await serviceRpc<Json>("activate_provider_connection_service_v1", {
    p_session_id: sessionId,
    p_required_credential_kind: "access_token",
    p_metadata: { adapter: "atlas_instagram_login_v1", webhookSubscribed: true },
  });

  return {
    ok: true,
    provider: "instagram",
    accountId: identity.id,
    username: identity.username,
    connectedSourceId: completed.connectedSourceId,
  };
}

function canonicalMessage(accountId: string, envelope: Json) {
  const sender = String((envelope.sender as Json | undefined)?.id ?? "");
  const recipient = String((envelope.recipient as Json | undefined)?.id ?? "");
  const message = (envelope.message as Json | undefined) ?? {};
  const mid = String(message.mid ?? "").trim();
  if (!mid || !sender || !recipient) return null;
  const incoming = recipient === accountId;
  const other = incoming ? sender : recipient;
  const text = typeof message.text === "string" ? message.text : null;
  return {
    deliveryKey: `message:${mid}`,
    event: {
      schemaVersion: "atlas_communication_event_v1",
      source: { kind: "instagram", accountRef: accountId, eventRef: mid, threadRef: `dm:${other}` },
      captureMode: "provider_webhook",
      occurredAt: typeof envelope.timestamp === "number" ? new Date(envelope.timestamp).toISOString() : null,
      capturedAt: new Date().toISOString(),
      direction: incoming ? "incoming" : "outgoing",
      speaker: { isSelf: !incoming, address: incoming ? sender : accountId },
      body: text,
      bodyState: text ? "exact_text" : "empty",
      participants: [
        { addressKind: "social", address: accountId, isSelf: true, role: "account" },
        { addressKind: "social", address: other, isSelf: false, role: "participant" },
      ],
      sourcePayload: { adapter: "atlas_instagram_login_v1", field: "messages", messageId: mid },
      sourceAuthority: "evidence_only",
      permittedStateEffect: "append_source_attributed_evidence_only",
      governingStateChanged: false,
    } as Json,
  };
}

function canonicalComment(accountId: string, change: Json) {
  if (change.field !== "comments") return null;
  const value = (change.value as Json | undefined) ?? {};
  const id = String(value.id ?? "").trim();
  if (!id) return null;
  const from = (value.from as Json | undefined) ?? {};
  const fromId = String(from.id ?? from.username ?? "unknown");
  const media = (value.media as Json | undefined) ?? {};
  const parentId = String(value.parent_id ?? "").trim();
  const threadRef = parentId ? `comment:${parentId}` : `comment:${id}`;
  const text = typeof value.text === "string" ? value.text : null;
  return {
    deliveryKey: `comment:${id}`,
    event: {
      schemaVersion: "atlas_communication_event_v1",
      source: { kind: "instagram", accountRef: accountId, eventRef: id, threadRef },
      captureMode: "provider_webhook",
      occurredAt: typeof value.timestamp === "string" ? value.timestamp : null,
      capturedAt: new Date().toISOString(),
      direction: "incoming",
      speaker: { isSelf: false, address: fromId },
      body: text,
      bodyState: text ? "exact_text" : "empty",
      participants: [
        { addressKind: "social", address: accountId, isSelf: true, role: "account" },
        { addressKind: "social", address: fromId, isSelf: false, role: "commenter" },
      ],
      sourcePayload: { adapter: "atlas_instagram_login_v1", field: "comments", commentId: id, mediaId: media.id ?? null, parentId: parentId || null },
      sourceAuthority: "evidence_only",
      permittedStateEffect: "append_source_attributed_evidence_only",
      governingStateChanged: false,
    } as Json,
  };
}

async function ingestCanonical(accountId: string, deliveryKey: string, event: Json) {
  event.contentHash = await sha256(JSON.stringify(stableEventProjection(event)));
  const source = await serviceRpc<SourceResolution>("resolve_provider_webhook_source_service_v1", {
    p_provider_key: "instagram",
    p_provider_account_key: accountId,
  });
  const payloadHash = await sha256(JSON.stringify(stableEventProjection(event)));
  const delivery = await serviceRpc<{ deliveryId: string; state: string; shouldProcess: boolean }>("record_provider_webhook_delivery_service_v1", {
    p_connected_source_id: source.connectedSourceId,
    p_provider_key: "instagram",
    p_provider_delivery_key: deliveryKey,
    p_payload_sha256: payloadHash,
    p_metadata: { adapter: "atlas_instagram_login_v1", providerAccountKey: accountId },
  });
  if (!delivery.shouldProcess) return { delivery, replay: true };
  const receipt = await serviceRpc<Json>("ingest_provider_webhook_events_service_v1", {
    p_provider_webhook_delivery_id: delivery.deliveryId,
    p_events: [event],
    p_manifest: { adapter: "atlas_instagram_login_v1", providerDeliveryKey: deliveryKey },
  });
  return { delivery, receipt, replay: false };
}

async function handleInstagramWebhook(raw: string) {
  const body = JSON.parse(raw) as { object?: string; entry?: Json[] };
  if (!Array.isArray(body.entry)) return { accepted: 0, results: [] };
  const results: unknown[] = [];
  for (const entry of body.entry) {
    const accountId = String(entry.id ?? "").trim();
    if (!accountId) continue;
    const messaging = Array.isArray(entry.messaging) ? entry.messaging as Json[] : [];
    for (const envelope of messaging) {
      const normalized = canonicalMessage(accountId, envelope);
      if (normalized) results.push(await ingestCanonical(accountId, normalized.deliveryKey, normalized.event));
    }
    const changes = Array.isArray(entry.changes) ? entry.changes as Json[] : [];
    for (const change of changes) {
      const normalized = canonicalComment(accountId, change);
      if (normalized) results.push(await ingestCanonical(accountId, normalized.deliveryKey, normalized.event));
    }
  }
  return { accepted: results.length, results };
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname.endsWith("/health")) {
      return json({ ok: true, adapter: "atlas_instagram_login_v1" });
    }

    if (req.method === "GET" && url.pathname.endsWith("/instagram/start")) {
      const state = url.searchParams.get("state") ?? "";
      parseSessionIdFromState(state);
      return json({ authorizeUrl: instagramAuthorizeUrl(state), provider: "instagram" });
    }

    if (req.method === "GET" && url.pathname.endsWith("/instagram/callback")) {
      const error = url.searchParams.get("error");
      if (error) return json({ ok: false, provider: "instagram", error, errorDescription: url.searchParams.get("error_description") }, 400);
      const state = url.searchParams.get("state") ?? "";
      const code = url.searchParams.get("code") ?? "";
      if (!state || !code) return json({ error: "Instagram callback requires code and state." }, 400);
      const result = await completeInstagramConnection(state, code);
      if (AFTER_CONNECT_URI) {
        const destination = new URL(AFTER_CONNECT_URI);
        destination.searchParams.set("provider", "instagram");
        destination.searchParams.set("connected", "1");
        destination.searchParams.set("account", result.accountId);
        return Response.redirect(destination.toString(), 303);
      }
      return json(result);
    }

    if (req.method === "GET" && url.pathname.endsWith("/instagram/webhook")) {
      const mode = url.searchParams.get("hub.mode");
      const token = url.searchParams.get("hub.verify_token");
      const challenge = url.searchParams.get("hub.challenge");
      if (mode === "subscribe" && META_WEBHOOK_VERIFY_TOKEN && token === META_WEBHOOK_VERIFY_TOKEN && challenge) {
        return new Response(challenge, { status: 200, headers: { "content-type": "text/plain" } });
      }
      return new Response("Forbidden", { status: 403 });
    }

    if (req.method === "POST" && url.pathname.endsWith("/instagram/webhook")) {
      requiredConfig();
      const raw = await req.text();
      const supplied = (req.headers.get("x-hub-signature-256") ?? "").replace(/^sha256=/i, "").toLowerCase();
      const expected = await hmacSha256Hex(INSTAGRAM_APP_SECRET, raw);
      if (!supplied || !constantTimeEqual(supplied, expected)) return json({ error: "Invalid Meta webhook signature." }, 401);
      const result = await handleInstagramWebhook(raw);
      return json({ ok: true, ...result });
    }

    return json({ error: "Not found" }, 404);
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Meta provider gateway failed." }, 500);
  }
});
