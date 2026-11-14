-- UNI-OPS-01 / U2C HELD CUTOVER: public execution membrane.
-- Source-only, never run on production. Apply LAST after the pinned R02
-- source and U2C guarded private owner writer in a disposable clone.
--
-- Existing direct R02 standing-visit and physical standing-admission public
-- endpoints could create original Work without U2A signed recipient uptake.
-- Retain their internal immutable source/Result implementations for controlled
-- composition, but make their client wrappers uncallable for ALL ordinary
-- tokens, including service_role. The only new signed external Work issuer is
-- public.finalize_accepted_governed_prework_self_api_v1(uuid).
-- This does not retire an independent Household or Event source writer.

DO $preflight$
BEGIN
 IF pg_catalog.to_regprocedure(
  'public.owner_establish_standing_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])') IS NULL
   OR pg_catalog.to_regprocedure(
  'public.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)') IS NULL
   OR pg_catalog.to_regprocedure(
  'public.admit_standing_continuing_source_work_self_api_v1(uuid,uuid,uuid,uuid,date)') IS NULL
   OR pg_catalog.to_regprocedure(
  'public.finalize_accepted_governed_prework_self_api_v1(uuid)') IS NULL
   OR pg_catalog.to_regprocedure(
  'atlas.require_accepted_prework_standing_original_v1(uuid,uuid,uuid,uuid,text,date,date,smallint[],uuid)') IS NULL
 THEN
  RAISE EXCEPTION 'U2C cutover requires exact, source-identical R02 and U2B contracts';
 END IF;
END;
$preflight$;

REVOKE ALL ON FUNCTION
 public.owner_establish_standing_continuing_care_work_self_api_v1(
 uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])
 FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION
 public.governor_approve_rhythm_opportunity_self_api_v1(
 uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)
 FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION
 public.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date)
 FROM PUBLIC,anon,authenticated,service_role;

-- Only a signed current root can now finalize one already-accepted offer
-- through its source-qualified internal original Work writer.
REVOKE ALL ON FUNCTION
 public.finalize_accepted_governed_prework_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
 public.finalize_accepted_governed_prework_self_api_v1(uuid)
 TO authenticated;

COMMENT ON FUNCTION
 public.governor_approve_rhythm_opportunity_self_api_v1(
 uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)
 IS 'U2C HELD: direct client original approval retired. The native function is only an internal source adapter of finalize_accepted_governed_prework_self_api_v1; no client skips prior signed worker acceptance.';
COMMENT ON FUNCTION
 public.owner_establish_standing_continuing_care_work_self_api_v1(
 uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])
 IS 'U2C HELD: direct client source writer retired; preserve canonical original and Actual. All new standing Work requires exact prior worker acceptance.';
COMMENT ON FUNCTION
 public.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date)
 IS 'U2C HELD: previous worker direct physical-source admission closed until independent accept-first physical-condition path is implemented.';
