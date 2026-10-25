# Signed native Ledger activation preflight v1

**Status: source-only candidate; absolutely no release or application activation grant.**

This is the first *real API step* of the existing institutional Implementation → native Ledger onboarding bridge, scoped to read-only signed practitioner previews.

The privately owned `atlas.native_ledger_activation_preflight_self_api_v1(uuid)` checks the **exact signed practitioner** and their **active assignment on the requested implementation case**, then assesses paid institutional case state, verified sponsor, canonical Auth→Person identity, and any `ledger.onboarding_cases` row explicitly sourced from that implementation case. It returns only bounded coded blockers; no sponsor email, private onboarding basis, source, private business name, other Person identity, or raw Ledger record.

The existing public wrapper exposes only that guarded response to `authenticated`. `anon` and direct private-execute rights are revoked. No direct Ledger/Reality INSERT or UPDATE privileges are added.

It **always returns `canActivate=false`** because the actual source-owned operating-model and runtime-proof decision, governed native admission linkage, and private signed activation command remain unbuilt. In particular, there is **no** UI activation enablement, creation of fake paid cases, or inheritance of legacy `atlas.ledgers`/Principal authorization. Previews are not authority decisions.

Existing native identity birth `20261023143542` remains the sole automatic Reality identity creator for successful admitted Ledger activations; do not alter its guards.

## Clone acceptance

The included postconditions prove the API exists; ordinary users cannot directly execute its internal function or write canonical tables; an unsigned request is rejected; it creates no Ledger, Reality context, or Seat; and the function's published incomplete-proof blocker remains present. Signed practitioner/outsider/withdrawn-session and genuine end-to-end tests are **still required** for a future activation writer; do not represent these structural postconditions as signed E2E proof.

Source governance: `optical-lift/noel-core-db` shared DB candidate. This is a deliberately incremental independent piece, not a new generic universal-Connection system. An optional Atlas Workbench read-panel follows only after controlled database release; activating new institutional Ledgers awaits the separately source-adjudicated operating-model/authorization/kernel acceptance.
