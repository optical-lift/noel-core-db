-- U2A postconditions; only within disposable BEGIN..ROLLBACK after candidate.
-- Structural/role boundary, not a signed acceptance or Work-admission test.
DO $u2a$
DECLARE v_count integer;
BEGIN
 IF pg_catalog.to_regclass('atlas.governed_prework_candidate_offers_v1') IS NULL
    OR pg_catalog.to_regprocedure(
     'public.offer_next_governed_prework_candidate_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)') IS NULL
    OR pg_catalog.to_regprocedure(
     'public.respond_governed_prework_candidate_self_api_v1(uuid,text,uuid)') IS NULL
    OR pg_catalog.to_regprocedure(
     'public.read_governed_prework_candidate_inbox_self_api_v1()') IS NULL THEN
   RAISE EXCEPTION 'U2A real source and exact signed transport absent';
 END IF;
 SELECT count(*) INTO v_count FROM atlas.governed_prework_candidate_offers_v1;
 IF v_count<>0 THEN RAISE EXCEPTION 'Unapproved pre-work offer state present'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas' AND c.relname='governed_prework_candidate_offers_v1'
      AND c.relrowsecurity) THEN
   RAISE EXCEPTION 'U2A RLS must be enabled';
 END IF;
 IF pg_catalog.has_table_privilege('authenticated',
      'atlas.governed_prework_candidate_offers_v1','SELECT')
    OR pg_catalog.has_table_privilege('authenticated',
      'atlas.governed_prework_candidate_offers_v1','UPDATE')
    OR pg_catalog.has_table_privilege('anon',
      'atlas.governed_prework_candidate_offers_v1','SELECT')
    OR pg_catalog.has_table_privilege('service_role',
      'atlas.governed_prework_candidate_offers_v1','INSERT')
 THEN RAISE EXCEPTION 'U2A private offer table privileges leaked'; END IF;
 IF pg_catalog.has_function_privilege('anon',
      'public.respond_governed_prework_candidate_self_api_v1(uuid,text,uuid)',
      'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated',
      'public.respond_governed_prework_candidate_self_api_v1(uuid,text,uuid)',
      'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated',
      'atlas.respond_governed_prework_candidate_self_api_v1(uuid,text,uuid)',
      'EXECUTE')
    OR pg_catalog.has_function_privilege('anon',
      'public.read_governed_prework_candidate_inbox_self_api_v1()',
      'EXECUTE')
 THEN RAISE EXCEPTION 'U2A signed current Person transport privileges invalid'; END IF;
END;
$u2a$;
