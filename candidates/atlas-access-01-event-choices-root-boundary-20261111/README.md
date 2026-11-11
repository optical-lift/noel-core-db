# ACCESS-01 — Event access is not a roster or unrelated Work search

**Status:** unmerged security candidate; no production permissions, migration, signed actor tests or UI acceptance implied.

## Current source evidence (November 11, 2026)

The installed `atlas.ledger_occurrence_shared_work_actor_self_v1` correctly permits current exact-Ledger roots or Persons with explicit Event-identity disclosure to open the selected Event. Both `ledger_event_attention_people_self_api_v1` and `event_existing_work_choices_self_api_v1` reuse that helper but also return information **beyond that Event**: the first returns the active Ledger personnel roster, and the second returns open unrelated Ledger Work choices. Event disclosure alone is not a personnel-directory or other-Work read grant.

## Bounded proposal

In these **two** existing Atlas SECURITY DEFINER functions, retain the original exact Event identity/access helper and additionally call `atlas.capability_root_authority_context_self_v1(p_ledger_id)` **before** querying a roster or other Work. This checks the current signed canonical Principal and `root_governing` authority for the *same exact Ledger*. Do not infer authority from Organization owner, other Ledger root, seat, Work allocation, Event identity grant, or historical role.

No changes to `atlas.ledger_occurrence_shared_work_self_api_v1`, `atlas.ledger_occurrence_shared_work_actor_self_v1`, Event identity reader, existing Event-linked Work assigned-reader, any original Person/Work/Event, existing data, public facades, GRANT/RLS, Titus, Atlas app or production release workflow.

## Acceptance before release

1. Exact source and existing public wrapper argument/return/EXECUTE contracts unchanged, with only the two new root checks; regression structural postconditions pass in disposable current-schema clone.
2. Signed **root of Ledger A** with source-bound Event reads both choice functions; current returned packet shape intact.
3. Signed **Event-only Person on Ledger A**, with genuine identity disclosure but no root, can still read the permitted Event and their independently authorized linked Work; both broader choice functions return 42501 with zero Personnel or unrelated Work data.
4. Signed ordinary seat without Event permission, unrelated outsider, wrong-Ledger root, revoked/expired authority, other Organization Person and anonymous actor are denied, including direct public RPC and pagination/count/metadata probes.
5. Recheck independent Event-owned contextual readers and remaining alternate legacy readers before calling ACCESS-01 complete. Explicitly record any separate routes (including `direct_ledger_event_work_attention_self_api_v1`) requiring distinct authorization review rather than claiming this two-function fix closes them.
6. Separately authorize canonical migration generation, protected genuine signed schema-clone testing, migration/release, and browser testing. Do not expose or import private user rows as fixtures.

**Owning work:** Atlas #445, Noel #2409, Atlas #437, existing Atlas integration completion register and human acceptance issue #556. This is one limited source fix, not a claim that outsider admission is ready.

## Test-only candidate and custody additions — November 11

- `candidate.sql` now includes a **pre-write expected-source fingerprint gate**, pinned from read-only live `pg_get_functiondef` on November 11: unrelated changes to either installed function abort before replacing either definition. This may reject a clone whose restored definition is not byte-equivalent; that is a hold for investigation, **not** a reason to skip the gate.
- `validation.sql` independently checks both native SECURITY DEFINER and public SECURITY INVOKER contracts, stable/jsonb/empty search path, authenticated-only EXECUTE and no PUBLIC/anon grant; it checks Event actor admission and the new exact-Root decision happen before roster or Work enumeration. **This is structural evidence only.**
- `fictional_other_event_work_TEST_ONLY.sql` adds one extra synthetic Work on **a different canonical Event** to the existing held `validation/fixtures/20261027210656_atlas_unified_today_event_disclosure_work_authority_v1.sql`. The Event A recipient must not learn this unrelated Work's existence, while the authentic Ledger root must retain the same original Work choice. The fixture must never be applied to production.
- `scripts/validate-atlas-access01-event-choices-signed-http.py` reuses the existing signed local GoTrue/PostgREST helper and *fictional* identities. It checks genuine distinct JWT sessions for current Event Ledger root, Event-only recipient and unrelated outsider; a separate C1-root signed session proves cross-Ledger denial. It tests root positive roster/unrelated Work reads, recipient's Event grant/revocation without roster/Work leakage, anonymous rejection and ended root with stale valid token. It asserts no Work count changes. **The signed test has been authored, NOT executed or admitted into a trusted protected workflow.**

### Strict next gate (not an invitation to release)

1. Review the five-file source/test diff on this existing draft PR, including the full original function-preservation and preflight fingerprint checks.
2. An authorized engineer/owner must *separately* admit the isolated local signed test to a guarded, main-owned runner. Use the existing canonical full-schema harness and its pinned Supabase CLI **v2.116.0**, local GoTrue and PostgREST; never run against production. Do not edit a protected workflow through an unapproved workaround or turn an OWNER-only issue into an agent-created authorization.
3. Assemble locally: existing wholly fictional unified-Today Event fixture, then the small additional fictional Work fixture; apply **only to the disposable clone** the two-function candidate and structural postconditions. Run the signed script against local 127.0.0.1 DB/API; record exact source head and allow/deny counts, not tokens, emails or SQL dumps.
4. If any preflight fingerprint, clone grant, data shape, signed root allow, recipient deny or cross-Ledger/revocation test fails, remain HELD, diagnose from safe bounded errors and correct through review.
5. Only after protected signed proof can the source owner separately review migration generation, independent production custody/release, and downstream Atlas human acceptance (E05). This branch is **not a generated migration**, not a release authorization, and does not change Event attention commands or wider older reader gates.
