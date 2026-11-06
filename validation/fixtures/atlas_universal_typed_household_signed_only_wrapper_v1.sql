-- DISPOSABLE CLONE TEST-ONLY authenticated transport for private Household native evidence.
-- NOT IN A MIGRATION OR PRODUCT SOURCE. Do not install on production.
CREATE FUNCTION public.universal_typed_household_test_self_api_v1(
  p_household_id uuid,p_kernel_instance_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $test_transport$
  SELECT atlas.universal_rulebook_household_native_evidence_internal_v1(
    p_household_id,p_kernel_instance_id);
$test_transport$;
REVOKE ALL ON FUNCTION public.universal_typed_household_test_self_api_v1(
  uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.universal_typed_household_test_self_api_v1(
  uuid,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
