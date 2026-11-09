# No-cost production read-only source disclosure probe — 2026-10-28

**Scope:** Gate for draft Noel PR #2362, not a production release.  
**Production:** Noel `zirqkouammpwxlqfbsvf` only as a READ-ONLY source of SQL catalogs and live row-level-security behavior.  
**No charge:** No Supabase branch (quoted at $0.01344/hour), no new project, no GitHub Actions, no Docker.  
**No mutation:** No production candidate executed, no grants changed, no users or task rows created. Explicit runtime role probes used `BEGIN; SET TRANSACTION READ ONLY; SET LOCAL ROLE authenticated; ...; ROLLBACK;`. A transaction-local `request.jwt.claim.sub` selected from the existing assigned auth user simulates identity, **not a genuine issued GoTrue bearer/session**. Do not label this signed HTTP acceptance.

## Confirmed baseline

- Existing 19 canonical Work, Rhythm, Care, Ledger and native Person tables required by the candidate: **19/19 present**.
- Current `atlas.ensure_rhythm_task_v1(uuid,text,timestamptz)` `pg_get_functiondef` md5: **`d195ec2ccf9b36858cba9c5bfbfb2724`**, matching the held cutover precondition.
- Existing legacy underlying writer, scheduled tick, and real care-observation-to-current-state projection are present.
- Existing source versions of `atlas.zone_registry_source_v1`, `object_crop_bed_map_v1` and `farm_care_zone_v1` invoke `require_governed_farm_full_disclosure_self_v1`. That guard insists on actual native governing principal, not an older farm member.
- Existing `atlas.care_current_state`, `care_observation_events`, and `care_result_events` RLS SELECT policies use `can_read_farm_operations`, which allows farm owner/manager, not farm_hand. Read-only effective-role probe under the legacy assigned user returned **0 farm care rows** from all three tables.

## Confirmed raw Rhythm SELECT policy gap — source-level failure

**Existing RLS:** `atlas.rhythm_state` has SELECT permission for `authenticated`; its `rhythm_state_read_visible` policy invokes `atlas.can_read_rhythm_state_v1(id)`. Current helper includes:

```sql
WHEN 'assigned_worker' THEN
  atlas.is_farm_manager_or_owner(s.farm_id)
  OR s.assigned_user_id = auth.uid()
```

The older `assigned_user_id` path does **not** check current native Ledger connection or current identity/condition disclosure for each growing object. It bypasses the new bounded Work/Subject reader under database RLS.

**Production read-only evidence:**

1. 181 existing `assigned_worker` Rhythms: **102 growing_object**, 78 crop_cycle, 1 zone; all 181 assigned to one older auth user. That user has one active canonical Person binding and active legacy `farm_hand` membership (no identity exposed in report).
2. With `SET LOCAL ROLE authenticated` and transaction-local claims for that existing auth user, actual PostgreSQL RLS returned **181 Rhythm rows**, including **102 growing-object rows**. This was a real source SELECT on real tables under the authenticated database role, **not** a real GoTrue session or proof of external API reachability.
3. Using the current native governing Ledger and canonical Person, **all 102** of those growing objects lack current `identity` and `condition` grants in `atlas.subject_disclosure_decision_events_v1`. The claims model granted raw table rows nonetheless.
4. In the same read-only role context, requiring `atlas.is_farm_manager_or_owner(farm_id)` for the raw Rhythm source would admit **0** rows for that farm_hand account.

**Result:** This is a confirmed *database row-level source admission* gap for raw `atlas.rhythm_state`; do **not** assume any exposed Data API or client pathway exists from this observation alone. A genuine Auth/REST test still needs to test source exposure and actual connected Person reachability. It also does not establish access to farm care condition or Result rows, which returned zero.

## Draft correction (not installed)

Added `09_rhythm_state_raw_worker_disclosure_cutover.sql` with a pinned pre-replacement fingerprint `2b7d7019230d0a9bf172e5e1b3224db3` for `atlas.can_read_rhythm_state_v1(uuid)`. Reuses the existing RLS helper and replaces ONLY two raw admission lanes:

- `assigned_worker`: owner/manager full raw operations gate only; remove legacy `assigned_user_id = auth.uid()` automatic raw-row access. Connected Persons must use disclosure-aware, limited source APIs instead of raw Rhythm metadata.
- Unknown/NULL visibility: fail closed to owner/manager instead of broad `is_farm_member` fallback.

Existing `owner`, `management`, `project_shared`, and `system_internal` behavior is preserved. No historical assignment, Rhythm, crop, or task row is changed. Included in held `release_candidate.sql`; structural source postcondition appended to held `release_postconditions.sql`.

**Not green yet:** This is not an executed production fix or a full runtime acceptance. Protected production-shaped clone and genuine distinct GoTrue JWT/REST governor, connected Person, outsider, identity/condition grant and withhold tests remain mandatory. Withheld Bed 4 and older worker farm-role admission must be tested at every reachable source/read path, plus the real Ledger completion projector and Household Laundry regression. Historical farm-hand readers dependent on raw Rhythm rows may narrow; confirm any purposeful replacements before deployment.

**Disposition:** Keep PR #2362 DRAFT / HOLD. No production DDL, no paid resources, no login given to Anna, no exceptions to universal connected-Person disclosure.
