-- HELD U1A structural postconditions. Run only inside a disposable
-- production-schema-shaped clone after candidate.sql, then ROLLBACK.
DO $u1a_postconditions$
DECLARE
 v_version_table oid:=to_regclass('atlas.governed_rulebook_versions_v1');
 v_binding_table oid:=to_regclass('atlas.governed_rulebook_bindings_v1');
 v_private text;
BEGIN
 IF v_version_table IS NULL OR v_binding_table IS NULL THEN
   RAISE EXCEPTION 'U1A private rulebook tables missing';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.oid=v_version_table AND c.relrowsecurity)
    OR NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.oid=v_binding_table AND c.relrowsecurity) THEN
   RAISE EXCEPTION 'U1A tables require RLS';
 END IF;
 IF has_table_privilege('authenticated',v_version_table,'SELECT')
    OR has_table_privilege('authenticated',v_binding_table,'SELECT')
    OR has_table_privilege('anon',v_version_table,'SELECT')
    OR has_table_privilege('anon',v_binding_table,'SELECT')
    OR has_table_privilege('service_role',v_version_table,'SELECT')
    OR has_table_privilege('service_role',v_binding_table,'SELECT')
    OR has_table_privilege('authenticated',v_version_table,'INSERT')
    OR has_table_privilege('authenticated',v_binding_table,'INSERT') THEN
    RAISE EXCEPTION 'U1A private table grant leaked';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=v_version_table
                AND tgname='governed_rulebook_versions_immutable_v1'
                AND tgenabled IN ('O','A'))
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid=v_binding_table
                AND tgname='governed_rulebook_bindings_immutable_v1'
                AND tgenabled IN ('O','A')) THEN
    RAISE EXCEPTION 'U1A immutable evidence triggers missing';
 END IF;

 FOREACH v_private IN ARRAY ARRAY[
  'atlas.require_governed_rulebook_root_source_v1(uuid,uuid,uuid)',
  'atlas.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)',
  'atlas.read_governed_rulebook_current_self_api_v1(uuid,uuid,uuid,text)',
  'atlas.block_governed_rulebook_evidence_mutation_v1()'
 ] LOOP
  IF to_regprocedure(v_private) IS NULL THEN
    RAISE EXCEPTION 'U1A private source function missing: %',v_private;
  END IF;
  IF has_function_privilege('authenticated',to_regprocedure(v_private),'EXECUTE')
      OR has_function_privilege('anon',to_regprocedure(v_private),'EXECUTE')
      OR has_function_privilege('service_role',to_regprocedure(v_private),'EXECUTE') THEN
    RAISE EXCEPTION 'U1A private source function grants leaked: %',v_private;
  END IF;
 END LOOP;
 IF to_regprocedure('public.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)') IS NULL
   OR to_regprocedure('public.read_governed_rulebook_current_self_api_v1(uuid,uuid,uuid,text)') IS NULL THEN
   RAISE EXCEPTION 'U1A public transport absent';
 END IF;
 IF NOT has_function_privilege('authenticated',to_regprocedure(
   'public.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)'),'EXECUTE')
   OR NOT has_function_privilege('authenticated',to_regprocedure(
   'public.read_governed_rulebook_current_self_api_v1(uuid,uuid,uuid,text)'),'EXECUTE') THEN
   RAISE EXCEPTION 'U1A signed public transports unavailable';
 END IF;
 IF has_function_privilege('anon',to_regprocedure(
   'public.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)'),'EXECUTE')
   OR has_function_privilege('anon',to_regprocedure(
   'public.read_governed_rulebook_current_self_api_v1(uuid,uuid,uuid,text)'),'EXECUTE') THEN
   RAISE EXCEPTION 'U1A anon transport leaked';
 END IF;
 IF EXISTS (SELECT 1 FROM atlas.governed_rulebook_versions_v1)
   OR EXISTS (SELECT 1 FROM atlas.governed_rulebook_bindings_v1) THEN
   RAISE EXCEPTION 'Candidate installation created policy rows';
 END IF;
 RAISE NOTICE 'U1A private evidence, RLS/ACL, immutable triggers, signed transport and no seeding: PASS';
END;
$u1a_postconditions$;

-- U1A unsigned transport smoke: no invented Person, Subject, Requirement,
-- Foundry event or policy. This proves only unsigned default denial in the
-- disposable clone; it does not replace real signed governor/worker tests.
DO $u1a_unsigned$
DECLARE
 v_nil uuid:='00000000-0000-0000-0000-000000000000';
BEGIN
 IF auth.uid() IS NOT NULL THEN
   RAISE EXCEPTION 'Unsigned smoke requires an unclaimed local session';
 END IF;
 BEGIN
   PERFORM atlas.read_governed_rulebook_current_self_api_v1(
     v_nil,v_nil,v_nil,'fixture.read');
   RAISE EXCEPTION 'Unsigned private Rulebook read unexpectedly succeeded';
 EXCEPTION WHEN SQLSTATE '42501' THEN
   NULL;
 END;
 BEGIN
   PERFORM atlas.adopt_governed_rulebook_version_self_api_v1(
     v_nil,v_nil,v_nil,'fixture.write',
     '{"eligibilityMode":"standing_stewardship","desiredOutcome":"Observe only","standingPurpose":"Inspect the fixture"}'::jsonb,
     'fixture-isolated-only','fixture-entry',0,'active',NULL,v_nil);
   RAISE EXCEPTION 'Unsigned private Rulebook writer unexpectedly succeeded';
 EXCEPTION WHEN SQLSTATE '42501' THEN
   NULL;
 END;
 RAISE NOTICE 'U1A unsigned private read/write default-denial smoke: PASS (no rows written)';
END;
$u1a_unsigned$;
