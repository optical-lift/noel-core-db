-- Candidate source proof, intended for disposable production-schema clone.
DO $verify$
DECLARE
  v_oid oid;
BEGIN
  IF to_regclass('atlas.personal_atlas_complimentary_test_invitations') IS NULL THEN
    RAISE EXCEPTION 'Complimentary invitations table missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='atlas.personal_atlas_complimentary_test_invitations'::regclass) THEN
    RAISE EXCEPTION 'Invitation custody requires RLS';
  END IF;
  IF has_table_privilege('anon','atlas.personal_atlas_complimentary_test_invitations','SELECT') OR
     has_table_privilege('authenticated','atlas.personal_atlas_complimentary_test_invitations','SELECT') OR
     has_table_privilege('anon','atlas.personal_atlas_complimentary_test_invitations','INSERT') OR
     has_table_privilege('authenticated','atlas.personal_atlas_complimentary_test_invitations','INSERT') THEN
    RAISE EXCEPTION 'Direct invitations table access is forbidden';
  END IF;
  IF has_function_privilege('anon','public.redeem_personal_atlas_complimentary_test_self_api_v1(text)','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous invitation redemption forbidden';
  END IF;
  IF NOT has_function_privilege('authenticated','public.redeem_personal_atlas_complimentary_test_self_api_v1(text)','EXECUTE') THEN
    RAISE EXCEPTION 'Verified human must be able to request invitation redemption';
  END IF;
  IF NOT has_function_privilege('service_role','public.grant_personal_atlas_access_v1(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'Original canonical grant writer missing';
  END IF;
  -- The new route must not create a parallel paid purchase.
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.personal_atlas_complimentary_test_invitations'::regclass
      AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Unexpected side-effect triggers on invitation source';
  END IF;
END
$verify$;

-- Negative proof: no session -> no code validation, no principal, no grant.
DO $negative$
BEGIN
  BEGIN
    PERFORM public.redeem_personal_atlas_complimentary_test_self_api_v1('THIS-IS-A-FAKE-LONG-CODE-000000000000');
    RAISE EXCEPTION 'Unexpected unauthenticated redemption success';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$negative$;
