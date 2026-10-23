# Gate 2 signed Foundry RPC — free local validation candidate V2

**Validation only; never deploy or merge this migration package.**

[Prior signed run](https://github.com/optical-lift/noel-core-db/actions/runs/40036684227) restored production schema and created the private Foundry candidate successfully, but the real local PostgREST request returned `404 PGRST202`, searching for `public.prepare_foundry_workspace_self_api_v1`. The implementation only offered the function in unexposed schema `atlas`.

V2 keeps `atlas` and `foundry` private and adds two narrow, **SECURITY INVOKER** `public.*` RPC bridges. The bridges pass the authenticated request unchanged to protected `atlas.*` functions. Exact EXECUTE grants to `authenticated`, explicit revokes from `PUBLIC`, `anon`, and `service_role`. The private functions still verify real `auth.sessions`, active Principals, owned workspace boundaries, provisional source-custody state, and denied/revoked sessions. This matches existing Noel public-to-atlas RPC patterns, not a new unrestricted API.

Candidate: `supabase/migrations/20261023232800_shared_foundry_connected_workspace_gate1_signed_v1.sql`.
Fictional fixture and rollback authorization suites share that version, all confined to the existing free GitHub protected disposable local Postgres+GoTrue+PostgREST workflow. Postconditions now reject a missing elevated public function bridge or incorrect grants.

The test makes no production modifications, authenticates three fictional people, checks foreign workspace denial, session revocation, and no canonical Atlas Reality mutation. It does not approve David/other subject consent or register a live carrier.
