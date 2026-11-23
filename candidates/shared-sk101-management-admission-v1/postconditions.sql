-- Catalog-only postconditions for SK 101 management admission.
DO $postconditions$
DECLARE
  entry record;
  fn regprocedure;
BEGIN
  FOR entry IN SELECT * FROM (VALUES
    ('atlas.sk101_management_grant_current_v1(uuid,text)', false, false, false),
    ('atlas.sk101_compatible_management_peer_v1(uuid,uuid)', false, false, false),
    ('atlas.sk101_management_admissible_v1(uuid,text)', false, false, false),
    ('public.shared_private_atlas_carrier_enroll_management_self_api_v1(uuid,text,timestamptz)', true, true, false),
    ('public.shared_private_atlas_carrier_management_status_self_api_v1()', true, true, false),
    ('public.shared_private_atlas_carrier_revoke_management_self_api_v1(uuid,text)', true, true, false),
    ('public.shared_private_atlas_carrier_issue_management_service_v1(uuid,text,text)', true, false, true),
    ('public.shared_private_atlas_carrier_admit_management_service_v1(text,text,uuid)', true, false, true)
  ) AS expected(signature, definer, authenticated_exec, service_exec)
  LOOP
    fn := to_regprocedure(entry.signature);
    IF fn IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid = fn
        AND p.prosecdef = entry.definer
        AND p.proconfig @> ARRAY['search_path=pg_catalog']
    ) THEN
      RAISE EXCEPTION 'Missing function or unexpected execution context for %', entry.signature;
    END IF;

    IF has_function_privilege('anon', fn, 'EXECUTE')
       OR has_function_privilege('authenticated', fn, 'EXECUTE') IS DISTINCT FROM entry.authenticated_exec
       OR has_function_privilege('service_role', fn, 'EXECUTE') IS DISTINCT FROM entry.service_exec
       OR EXISTS (
         SELECT 1 FROM pg_proc p
         CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE p.oid = fn AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
       )
    THEN
      RAISE EXCEPTION 'Unexpected execution grants for %', entry.signature;
    END IF;
  END LOOP;
END;
$postconditions$;
