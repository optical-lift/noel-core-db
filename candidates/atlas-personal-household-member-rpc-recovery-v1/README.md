# Restore Personal Atlas Household member APIs — reviewed candidate

The authenticated Home notebook in optical-lift/atlas PR #277 failed real-user acceptance: the UI could read the canonical residence but received a source API error when calling `public.personal_household_members_self_api_v1()`. Live function introspection on 2026-10-14 shows the paired `atlas.` and `public.` read/writer functions **absent**. The original source migration `20260910043800_atlas_personal_household_setup_membrane_v1.sql` exists in main but is not recorded in live Supabase migration custody; do not fabricate its historical execution or replay its old version.

This packet restores its proven source in a NEW canonical `atlas_` release version through the normal generated migration path (not a SQL execution from this candidate).

## Contracts
- `public.personal_household_members_self_api_v1()` uses `auth.uid()` and `atlas.principal_current_household_id_v1()` to list active members under the signed-in Principal's household only. No cross-household leakage; no service-role client.
- `public.personal_household_upsert_member_self_api_v1(p_input jsonb)` uses a per-intent `requestKey` as an idempotency key when creating members, or `memberId` to correct an established non-principal member in the current household. It does NOT issue an Atlas login or create a new Household or Person.
- Preserves the existing `atlas.household_members` table and legacy data; applies a partial per-household request-key unique index. Does not modify existing `upsert_personal_household_member_self_api_v1` (the retired Welcome API).
- `GRANT EXECUTE` only to authenticated and service_role; never to anonymous.
- The notebook client PR must remain draft until database release, followed by separate guarded app Preview and production release.

## Required validation (disposable synthetic schema clone)
1. Authenticated Principal A sees only Household A; Principal B sees only Household B. Unauthenticated is denied.
2. A new, non-login member is created once even after exact `requestKey` replay; belongs to A only.
3. Existing `memberId` correction updates that member without creating another; cannot edit a member in B nor the Principal's own member row.
4. Blank names and new member without a `requestKey` are rejected; no created Person, credentials, or new Household.
5. Existing historical member rows remain untouched, including their `person_id` bindings; re-read shows current committed data.
6. Verify definitions, grants, index and migration custody after protected release.

No private household names, addresses or user identifiers appear in the candidate, tests, or fixture.