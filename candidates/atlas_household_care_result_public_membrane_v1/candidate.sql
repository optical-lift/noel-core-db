-- SOURCE-ONLY candidate. Review and clone-validate in noel-core-db before any
-- protected production migration source generation/release. No data writes here.
BEGIN;

-- The actual care-result writer remains the Household-owned atlas function.
-- A verified signed-in Principal may submit exactly one physical-space result;
-- the underlying function verifies active household/space, validates result
-- and condition enums, owns event attribution and idempotent sourceKey replay.
CREATE OR REPLACE FUNCTION public.principal_record_household_care_result_api_v1(
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authenticated Principal required.' USING errcode='42501';
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'A Household care-result object is required.' USING errcode='22023';
  END IF;
  RETURN atlas.principal_record_household_care_result_api_v1(p_payload);
END;
$function$;

REVOKE ALL ON FUNCTION public.principal_record_household_care_result_api_v1(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.principal_record_household_care_result_api_v1(jsonb)
  TO authenticated;

COMMIT;
