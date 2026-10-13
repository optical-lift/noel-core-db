# Atlas Personal Google source transport — source-only API bridges

**Status: source candidate, not a generated or installed migration.**

The existing Atlas Next.js service RPC uses Supabase REST public schema. The canonical provider connection functions under the private atlas schema were deliberately service-only and are not reachable by assuming private schema Data API exposure.

This candidate provides exactly three public-profile service-role-only forwarding functions: complete verified provider identity, store refresh secret through existing Vault custody, and activate provider connection only after the credential exists. They all call the canonical atlas functions; they do not write tables or establish a second provider-account root.

The browser actor can only begin the session through already-governed public.begin_provider_connection_self_api_v1, which authenticates and verifies Principal ownership. The server must additionally verify an independent short-lived signed OAuth state, matching HttpOnly PKCE cookie, signed-in user, Google code/grant and provider account identity before using any service-only bridge. The service-role key is never in the browser.

**Preconditions:** 20260919233031 current-canon provider connection migration released; underlying atlas.store_connected_source_secret_service_v1 present. Release order must be verified in disposable production-schema clone. Without this source order, PostgreSQL function references will fail validation.

**Security:** PUBLIC, anon and authenticated cannot execute these bridges. service_role is the only grantee. SECURITY DEFINER here only narrows the public-profile transport to existing atlas service procedures and is never a repair for a failed owner-RLS check. No new account/credential permissions are granted to the user. The credential writer returns governed metadata, not refresh token content. New source auth and Google API access remain separate.

**Not included:** Gmail message sync, raw attachment storage, Connection source revocation, finance consent, Google OAuth credentials, Google consent-screen verification or provider send. The companion Atlas app code is draft PR #255 and must not be merged/released until the DB bridge is generated, production-schema-clone proven, deliberately released and real actor-provider proof completed.

Proof SQL checks function signatures and disallows PUBLIC/anon/authenticated execution. Additional dynamic actor and credential-custody tests are still required on the immutable generated migration before release.
