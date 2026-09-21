# Personal Laundry Closed Loop v2 — Product RPC Surface

Status: **source-complete replacement candidate; inert, not migration-identified, not clone-validated, not released**.

This candidate supersedes the unreleased v1 closed-loop migration package before production release.

The v1 closed-loop architecture and validation remain intact. V2 adds the missing product exposure membrane required by the actual Personal Atlas notebook.

## Why V2 exists

The canonical Laundry authorities live in the `atlas` schema. Atlas's browser product, like existing Notebook and Person Life surfaces, calls public PostgREST wrapper functions.

Clone validation of v1 proved the domain architecture itself, but product integration found that most newly added authenticated Laundry APIs had no `public.*` wrappers. Calling them from the ordinary Supabase browser client would therefore target a nonexistent public RPC.

V2 repairs that seam **before release**.

## Public membrane law

Each signed-in wrapper:

- lives in `public`;
- is `SECURITY DEFINER`;
- owns no domain logic;
- delegates one hop to the same-named canonical `atlas.*` authority;
- grants EXECUTE only to `authenticated` and `service_role`;
- denies `anon` and PUBLIC default execution.

The trusted Personal Reality human-decision-receipt wrapper is stricter:

- it delegates to `atlas.issue_personal_reality_human_decision_receipt_serv_v1`;
- only `service_role` may execute it;
- authenticated and anonymous callers remain denied;
- the Atlas server must derive the owner identity from a verified bearer token before calling it.

## Exposed signed-in Laundry surface

- `record_current_household_claim_evidence_api_v1(jsonb)`
- `current_household_claim_evidence_state_api_v1()`
- `calibrate_personal_laundry_kernel_self_api_v2(jsonb)`
- `personal_laundry_kernel_self_api_v2()`
- `apply_personal_reality_household_claim_effect_self_api_v1(uuid)`
- `ensure_personal_laundry_consequence_definition_self_api_v1(uuid)`
- `evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)`
- `record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)`
- `person_life_consequence_clock_admission_self_api_v1(uuid)`
- `reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)`
- `principal_clock_api_v2(date,timestamptz)`
- `record_personal_laundry_actual_self_api_v1(jsonb)`
- `resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)`
- `propose_personal_laundry_weekly_pattern_self_api_v1()`

## Trusted server surface

- `issue_personal_reality_human_decision_receipt_serv_v1(uuid,uuid,text,text,jsonb)`

This wrapper is not a browser endpoint.

## Replacement rule

The already-generated v1 migration `20260921005012_atlas_personal_laundry_closed_loop_v1` is **not live in production** and must be removed from canonical migration history before the V2 generated migration is merged.

V2 must be generated through the governed migration-source workflow and must independently pass Production Schema Clone Validation against current production.

No production release is authorized by this candidate.
