# Atlas Ledger Event public REST boundary — 22 October 2026

## Reproduced incident

The signed-in Elm Venue Ledger Events Index displayed **“Event records are not available from a verified source.”** The Supabase edge log contains `POST /rest/v1/rpc/ledger_occurrence_shared_index_self_api_v1 → 404` at **2026-10-22T13:12:54Z**. The browser client defaults to Supabase public schema. The 11 new Event browser RPCs exist in private `atlas` schema but have no matching `public` delegates.

The canonical Venue Ledger contains **31 source-bound Occurrences** with one active Organization binding each, including the already-existing 2026-10-30 Harvest Party. This is an API exposure defect, *not a missing Event or an identity/seat policy change*.

## Repair

Install exactly the 11 browser-used `public` RPC wrappers, matching the proven `public.ledger_workspace_self_api_v1` pattern. Each wrapper:
- is `SECURITY INVOKER` and `SET search_path TO ''`;
- delegates the exact arguments to the same-named `atlas` operation;
- matches source STABLE/VOLATILE volatility;
- revokes PUBLIC and anon EXECUTE, explicitly grants authenticated only;
- never grants public table access, exposes an `atlas` schema table, or bypasses native authenticated Person, Ledger Seat, Organization, Occurrence and result-contract policies;
- provides no service-role/admin credential in client code.

The live source APIs already check current authenticated Person + native Ledger connection, exact Organization–Occurrence binding and source Work contract. The wrappers do not grant additional data scope.

### Deployment/order and proof

1. This source-only candidate through Atlas migration-generation lane.
2. Disposable production-shaped schema clone: postconditions above, no new lint errors, anonymous/denied test and positive synthetic signed-style Event source test where feasible.
3. Manual protected production release, then read-only catalog check that all 11 `public` wrappers exist and anon has no EXECUTE.
4. Browser hard refresh and verify Events Index displays the actual 31 authorized bound occurrences; click Harvest Party, load exact Work + extension and test source-resolved attention. Real signed-in participant and unauthorized participant tests remain distinct from schema proof.
5. Only after repair decide Packet 0/1 of `Atlas_Unified_Subject_Workspace_and_Temporal_Field_Build_Plan_20261021_v3`; it adds One Date conflict/source coverage and completion evidence rules, which are not addressed by these wrappers.

**No hardcoded Elm UUID in migration. No user data or synthetic identities in public source.**
