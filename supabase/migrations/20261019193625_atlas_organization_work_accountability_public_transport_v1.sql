-- Build 5: restore authenticated Today owner-work review over the
-- existing source-gated atlas function. This is transport only; neither
-- native Ledger seats nor organization memberships are created here.
BEGIN;

CREATE OR REPLACE FUNCTION public.organization_work_accountability_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.organization_work_accountability_self_api_v1();
$function$;

REVOKE ALL ON FUNCTION public.organization_work_accountability_self_api_v1()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.organization_work_accountability_self_api_v1()
  TO authenticated;

COMMENT ON FUNCTION public.organization_work_accountability_self_api_v1() IS
  'Authenticated PostgREST transport only. The atlas source checks auth.uid() and returns owner-only organizational work review; no anonymous or seat-derived read.';
COMMIT;
