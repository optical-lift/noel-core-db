import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FACEBOOK_APP_ID = Deno.env.get("ATLAS_FACEBOOK_APP_ID") ?? "";
const FACEBOOK_APP_SECRET = Deno.env.get("ATLAS_FACEBOOK_APP_SECRET") ?? "";
const FACEBOOK_REDIRECT_URI = Deno.env.get("ATLAS_FACEBOOK_REDIRECT_URI") ?? "";
const META_GRAPH_VERSION = Deno.env.get("ATLAS_META_GRAPH_VERSION") ?? "";
const AFTER_DISCOVERY_URI = Deno.env.get("ATLAS_META_AFTER_DISCOVERY_URI") ?? "";

type Json = Record<string, unknown>;
type PageAsset = { id: string; name?: string; access_token?: string; tasks?: string[]; instagram_business_account?: { id?: string } };

function responseJson(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

function requiredConfig() {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Supabase service configuration is unavailable.");
  if (!FACEBOOK_APP_ID || !FACEBOOK_APP_SECRET || !FACEBOOK_REDIRECT_URI || !META_GRAPH_VERSION) throw new Error("Facebook provider configuration is incomplete.");
}

async function sha256(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function parseSessionIdFromState(state: string) {
  const dot = state.indexOf(".");
  const candidate = dot > 0 ? state.slice(0, dot) : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate)) throw new Error("OAuth state does not contain a valid Atlas connection session.");
  return candidate;
}

async function rpc<T>(name: string, args: Json, authorization: string) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${encodeURIComponent(name)}`, {
    method: "POST",
    headers: { apikey: SERVICE_ROLE_KEY, authorization, "content-type": "application/json" },
    body: JSON.stringify(args),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${name} failed (${r.status}): ${text.slice(0, 1000)}`);
  return (text ? JSON.parse(text) : null) as T;
}

function serviceRpc<T>(name: string, args: Json) {
  return rpc<T>(name, args, `Bearer ${SERVICE_ROLE_KEY}`);
}

async function metaJson<T>(url: string, init?: RequestInit) {
  const r = await fetch(url, init);
  const text = await r.text();
  if (!r.ok) throw new Error(`Meta request failed (${r.status}): ${text.slice(0, 1000)}`);
  const parsed = text ? JSON.parse(text) : {};
  if (parsed && typeof parsed === "object" && "error" in parsed) throw new Error(`Meta request returned an error: ${text.slice(0, 1000)}`);
  return parsed as T;
}

function facebookAuthorizeUrl(state: string) {
  const u = new URL(`https://www.facebook.com/${META_GRAPH_VERSION}/dialog/oauth`);
  u.searchParams.set("client_id", FACEBOOK_APP_ID);
  u.searchParams.set("redirect_uri", FACEBOOK_REDIRECT_URI);
  u.searchParams.set("response_type", "code");
  u.searchParams.set("state", state);
  u.searchParams.set("scope", [
    "pages_show_list",
    "pages_manage_metadata",
    "pages_read_engagement",
    "pages_messaging",
    "instagram_basic",
    "instagram_manage_messages",
    "instagram_manage_comments",
  ].join(","));
  return u.toString();
}

async function exchangeCode(code: string) {
  const u = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/oauth/access_token`);
  u.searchParams.set("client_id", FACEBOOK_APP_ID);
  u.searchParams.set("client_secret", FACEBOOK_APP_SECRET);
  u.searchParams.set("redirect_uri", FACEBOOK_REDIRECT_URI);
  u.searchParams.set("code", code);
  const token = await metaJson<{ access_token?: string; token_type?: string; expires_in?: number }>(u.toString());
  if (!token.access_token) throw new Error("Facebook did not return a user access token.");
  return token;
}

async function facebookIdentity(userToken: string) {
  const u = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/me`);
  u.searchParams.set("fields", "id,name");
  u.searchParams.set("access_token", userToken);
  const me = await metaJson<{ id?: string; name?: string }>(u.toString());
  if (!me.id) throw new Error("Facebook user identity was not returned.");
  return { id: String(me.id), name: me.name ?? String(me.id) };
}

async function managedPages(userToken: string): Promise<PageAsset[]> {
  let next: string | null = `https://graph.facebook.com/${META_GRAPH_VERSION}/me/accounts?fields=id,name,access_token,tasks,instagram_business_account&limit=100&access_token=${encodeURIComponent(userToken)}`;
  const pages: PageAsset[] = [];
  while (next) {
    const page = await metaJson<{ data?: PageAsset[]; paging?: { next?: string } }>(next);
    pages.push(...(Array.isArray(page.data) ? page.data : []));
    next = page.paging?.next ?? null;
  }
  return pages;
}

function candidateCapabilities(tasks: string[]) {
  const normalized = new Set(tasks.map((task) => task.toUpperCase()));
  return {
    messagingTask: normalized.has("MESSAGING"),
    moderateTask: normalized.has("MODERATE"),
    createContentTask: normalized.has("CREATE_CONTENT"),
    manageTask: normalized.has("MANAGE"),
  };
}

function candidatesFromPages(pages: PageAsset[]) {
  const candidates: Json[] = [];
  for (const page of pages) {
    if (!page.id) continue;
    const tasks = Array.isArray(page.tasks) ? page.tasks : [];
    candidates.push({
      assetKind: "facebook_page",
      providerAssetKey: String(page.id),
      displayLabel: page.name ?? String(page.id),
      providerTasks: tasks,
      capabilities: candidateCapabilities(tasks),
      metadata: { linkedInstagramBusinessAccountId: page.instagram_business_account?.id ?? null },
    });
    if (page.instagram_business_account?.id) {
      candidates.push({
        assetKind: "instagram_business",
        providerAssetKey: String(page.instagram_business_account.id),
        parentProviderAssetKey: String(page.id),
        displayLabel: `${page.name ?? page.id} · Instagram`,
        providerTasks: tasks,
        capabilities: { ...candidateCapabilities(tasks), linkedFromFacebookPage: true },
        metadata: { parentPageName: page.name ?? null },
      });
    }
  }
  return candidates;
}

async function discover(state: string, code: string) {
  requiredConfig();
  const sessionId = parseSessionIdFromState(state);
  await serviceRpc<Json>("validate_provider_connection_callback_service_v1", {
    p_session_id: sessionId,
    p_provider_key: "facebook",
    p_state_nonce_digest: await sha256(state),
  });
  const token = await exchangeCode(code);
  const identity = await facebookIdentity(token.access_token!);
  const pages = await managedPages(token.access_token!);
  const candidates = candidatesFromPages(pages);
  const expiresAt = new Date(Date.now() + Math.min(Math.max(token.expires_in ?? 7200, 300), 86400) * 1000).toISOString();
  const grant = await serviceRpc<{ authorizationId: string; candidateCount: number; expiresAt: string }>("create_provider_asset_authorization_service_v1", {
    p_provider_connection_session_id: sessionId,
    p_provider_key: "facebook",
    p_authorization_subject_key: identity.id,
    p_access_token: token.access_token,
    p_expires_at: expiresAt,
    p_candidates: candidates,
    p_metadata: { adapter: "atlas_facebook_asset_discovery_v1", authorizationSubjectName: identity.name },
  });
  return { ok: true, provider: "facebook", authorizationId: grant.authorizationId, candidateCount: grant.candidateCount, expiresAt: grant.expiresAt };
}

async function reacquireSelectedPage(context: Json) {
  const token = String(context.authorizationAccessToken ?? "");
  if (!token) throw new Error("Temporary Facebook authorization token is unavailable.");
  const pages = await managedPages(token);
  const assetKind = String(context.assetKind ?? "");
  const providerAssetKey = String(context.providerAssetKey ?? "");
  const parent = String(context.parentProviderAssetKey ?? "");
  const pageId = assetKind === "facebook_page" ? providerAssetKey : parent;
  const page = pages.find((item) => String(item.id) === pageId);
  if (!page?.access_token) throw new Error("Selected Page is no longer available through this Facebook authorization.");
  if (assetKind === "instagram_business" && String(page.instagram_business_account?.id ?? "") !== providerAssetKey) throw new Error("Selected Instagram account is no longer linked to the expected Page.");
  return page;
}

async function subscribeSelectedAsset(assetKind: string, providerAssetKey: string, pageId: string, pageToken: string) {
  const targetId = assetKind === "facebook_page" ? pageId : providerAssetKey;
  const u = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/${encodeURIComponent(targetId)}/subscribed_apps`);
  u.searchParams.set("access_token", pageToken);
  u.searchParams.set("subscribed_fields", assetKind === "facebook_page" ? "messages,feed" : "messages,comments");
  const result = await metaJson<{ success?: boolean }>(u.toString(), { method: "POST" });
  if (result.success !== true) throw new Error("Meta webhook subscription was not accepted for the selected asset.");
}

async function bindOrganizationCommunicationEndpoint(
  context: Json,
  sourceId: string,
  sourceProvider: string,
  canSend: boolean,
  authorization: string,
) {
  if (String(context.custodianKind ?? "") !== "organization") return null;
  const organizationId = String(context.organizationId ?? "").trim();
  const providerAccountKey = String(context.providerAssetKey ?? "").trim();
  if (!organizationId || !providerAccountKey) throw new Error("Organization/provider identity is unavailable for communication endpoint setup.");

  const address = sourceProvider === "facebook"
    ? `facebook:page:${providerAccountKey}`
    : `instagram:business:${providerAccountKey}`;
  const displayLabel = String(context.displayLabel ?? "").trim() || address;
  const endpoint = await rpc<{ communicationEndpointId: string }>("upsert_communication_endpoint_self_api_v1", {
    p_organization_id: organizationId,
    p_organization_unit_id: null,
    p_endpoint_kind: "social",
    p_address: address,
    p_display_name: displayLabel,
    p_metadata: {
      provider: sourceProvider,
      providerAccountKey,
      connectedSourceId: sourceId,
      setupSource: "atlas_facebook_asset_discovery_v1",
    },
  }, authorization);
  if (!endpoint.communicationEndpointId) throw new Error("Atlas did not return the organization social communication endpoint.");

  const bindingRole = canSend ? "send_receive" : "receive";
  await rpc<Json>("bind_communication_endpoint_source_self_api_v1", {
    p_communication_endpoint_id: endpoint.communicationEndpointId,
    p_connected_source_id: sourceId,
    p_binding_role: bindingRole,
    p_transport_metadata: {
      provider: sourceProvider,
      providerAccountKey,
      setupSource: "atlas_facebook_asset_discovery_v1",
    },
  }, authorization);

  return {
    communicationEndpointId: endpoint.communicationEndpointId,
    endpointAddress: address,
    bindingRole,
  };
}

async function completeSelection(selectionId: string, authorization: string) {
  const context = await serviceRpc<Json>("provider_asset_selection_context_service_v1", { p_provider_asset_selection_id: selectionId });
  const page = await reacquireSelectedPage(context);
  const assetKind = String(context.assetKind ?? "");
  const sourceProvider = assetKind === "facebook_page" ? "facebook" : "instagram";
  const tasks = Array.isArray(page.tasks) ? page.tasks : [];
  const canSend = tasks.map((x) => x.toUpperCase()).includes("MESSAGING");
  const source = await serviceRpc<{ connectedSourceId: string }>("create_provider_asset_connected_source_service_v1", {
    p_provider_asset_selection_id: selectionId,
    p_source_provider_key: sourceProvider,
    p_granted_scopes: assetKind === "facebook_page"
      ? ["pages_show_list", "pages_manage_metadata", "pages_read_engagement", "pages_messaging"]
      : ["instagram_basic", "instagram_manage_messages", "instagram_manage_comments", "pages_manage_metadata"],
    p_capabilities: {
      communicationCapture: true,
      communicationSend: canSend,
      directMessages: canSend,
      comments: true,
      providerTasks: tasks,
    },
    p_metadata: { adapter: "atlas_facebook_asset_discovery_v1", parentFacebookPageId: page.id },
  });
  await serviceRpc<Json>("store_connected_source_secret_service_v1", {
    p_connected_source_id: source.connectedSourceId,
    p_credential_kind: "page_access_token",
    p_secret: page.access_token,
    p_description: `Meta Page access token for selected ${assetKind}`,
  });
  await subscribeSelectedAsset(assetKind, String(context.providerAssetKey ?? ""), String(page.id), page.access_token!);

  const communication = await bindOrganizationCommunicationEndpoint(
    context,
    source.connectedSourceId,
    sourceProvider,
    canSend,
    authorization,
  );

  await serviceRpc<Json>("complete_provider_asset_selection_service_v1", {
    p_provider_asset_selection_id: selectionId,
    p_required_credential_kind: "page_access_token",
    p_metadata: {
      webhookSubscribed: true,
      adapter: "atlas_facebook_asset_discovery_v1",
      communicationEndpointId: communication?.communicationEndpointId ?? null,
      communicationBindingRole: communication?.bindingRole ?? null,
    },
  });
  return {
    ok: true,
    selectionId,
    connectedSourceId: source.connectedSourceId,
    provider: sourceProvider,
    providerAccountKey: context.providerAssetKey,
    communication,
  };
}

Deno.serve(async (req) => {
  try {
    requiredConfig();
    const url = new URL(req.url);

    if (req.method === "GET" && url.pathname.endsWith("/health")) return responseJson({ ok: true, adapter: "atlas_facebook_asset_discovery_v1" });

    if (req.method === "GET" && url.pathname.endsWith("/facebook/start")) {
      const state = url.searchParams.get("state") ?? "";
      parseSessionIdFromState(state);
      return responseJson({ provider: "facebook", authorizeUrl: facebookAuthorizeUrl(state) });
    }

    if (req.method === "GET" && url.pathname.endsWith("/facebook/callback")) {
      const providerError = url.searchParams.get("error");
      if (providerError) return responseJson({ ok: false, provider: "facebook", error: providerError, errorDescription: url.searchParams.get("error_description") }, 400);
      const state = url.searchParams.get("state") ?? "";
      const code = url.searchParams.get("code") ?? "";
      if (!state || !code) return responseJson({ error: "Facebook callback requires code and state." }, 400);
      const result = await discover(state, code);
      if (AFTER_DISCOVERY_URI) {
        const destination = new URL(AFTER_DISCOVERY_URI);
        destination.searchParams.set("provider", "facebook");
        destination.searchParams.set("authorization", result.authorizationId);
        return Response.redirect(destination.toString(), 303);
      }
      return responseJson(result);
    }

    if (req.method === "POST" && url.pathname.endsWith("/facebook/select")) {
      const authorization = req.headers.get("authorization") ?? "";
      if (!/^Bearer\s+\S+/i.test(authorization)) return responseJson({ error: "Signed-in Atlas session required." }, 401);
      const body = await req.json() as { authorizationId?: string; candidateId?: string };
      if (!body.authorizationId || !body.candidateId) return responseJson({ error: "authorizationId and candidateId are required." }, 400);
      const selection = await rpc<{ selectionId: string }>("begin_provider_asset_selection_self_api_v1", {
        p_provider_asset_authorization_id: body.authorizationId,
        p_provider_asset_candidate_id: body.candidateId,
      }, authorization);
      return responseJson(await completeSelection(selection.selectionId, authorization));
    }

    return responseJson({ error: "Not found" }, 404);
  } catch (error) {
    console.error(error);
    return responseJson({ error: error instanceof Error ? error.message : "Facebook provider adapter failed." }, 500);
  }
});
