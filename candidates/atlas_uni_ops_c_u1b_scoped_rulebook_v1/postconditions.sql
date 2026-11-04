-- Apply after candidate.sql inside a disposable BEGIN..ROLLBACK only.
-- Structural test, NOT a signed/session, database release, or U2 test.
DO $checks$
DECLARE
 v_count integer;
BEGIN
 IF pg_catalog.to_regclass('atlas.governed_farm_rulebook_scope_versions_v1') IS NULL
    OR pg_catalog.to_regprocedure(
      'public.adopt_governed_farm_rulebook_scope_self_api_v1(uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)') IS NULL
    OR pg_catalog.to_regprocedure(
      'public.read_governed_farm_rulebook_effective_self_api_v1(uuid,uuid,uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'Held U1B source and exact RPC signatures absent';
 END IF;
 SELECT count(*) INTO v_count
 FROM atlas.governed_farm_rulebook_scope_versions_v1;
 IF v_count<>0 THEN
  RAISE EXCEPTION 'Unapproved or synthetic Rulebook decisions present';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas'
    AND c.relname='governed_farm_rulebook_scope_versions_v1'
    AND c.relrowsecurity=true)
   OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
     WHERE t.tgrelid='atlas.governed_farm_rulebook_scope_versions_v1'::regclass
       AND t.tgname='governed_farm_rulebook_versions_immutable_v1'
       AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'RLS or append-only evidence guard absent'; END IF;
 IF pg_catalog.has_table_privilege('authenticated',
    'atlas.governed_farm_rulebook_scope_versions_v1','SELECT')
   OR pg_catalog.has_table_privilege('authenticated',
    'atlas.governed_farm_rulebook_scope_versions_v1','INSERT')
   OR pg_catalog.has_table_privilege('anon',
    'atlas.governed_farm_rulebook_scope_versions_v1','SELECT')
   OR pg_catalog.has_table_privilege('service_role',
    'atlas.governed_farm_rulebook_scope_versions_v1','INSERT')
 THEN RAISE EXCEPTION 'Private U1B Rulebook table privilege leaked'; END IF;
 IF pg_catalog.has_function_privilege('anon',
   'public.adopt_governed_farm_rulebook_scope_self_api_v1(uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)',
   'EXECUTE')
   OR pg_catalog.has_function_privilege('anon',
   'public.read_governed_farm_rulebook_effective_self_api_v1(uuid,uuid,uuid,uuid,uuid)',
   'EXECUTE')
   OR NOT pg_catalog.has_function_privilege('authenticated',
   'public.adopt_governed_farm_rulebook_scope_self_api_v1(uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)',
   'EXECUTE')
   OR pg_catalog.has_function_privilege('authenticated',
   'atlas.adopt_governed_farm_rulebook_scope_self_api_v1(uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)',
   'EXECUTE')
 THEN RAISE EXCEPTION 'U1B signed transport or private-function ACL drift'; END IF;
END;
$checks$;
