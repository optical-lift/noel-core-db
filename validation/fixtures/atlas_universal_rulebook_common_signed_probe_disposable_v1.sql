-- TEST-ONLY synthetic public transport. Never a migration, product surface,
-- default grant or source of Root/Subject permission. The underlying held
-- UNIVERSAL private common function still rechecks native signed authority.
-- Install ONLY on disposable PG17+GoTrue/PostgREST with fictional C1 data.
CREATE FUNCTION public.universal_rulebook_common_test_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_requirement_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $disposable_test$
  SELECT atlas.universal_rulebook_common_source_preflight_internal_v1(
    p_organization_id,p_ledger_id,p_requirement_id);
$disposable_test$;
REVOKE ALL ON FUNCTION public.universal_rulebook_common_test_self_api_v1(
  uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.universal_rulebook_common_test_self_api_v1(
  uuid,uuid,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
