-- U2C lightweight schema/ACL/guard contract (HELD).
-- Apply only AFTER 01, 02, 03 in a job-owned disposable PG17
-- BEGIN ... ROLLBACK on an authentic U1A/U1B/U2A/R01/R02 source clone.
-- Not run, not a signed Person/regression test and not a release certificate.
DO $check$
DECLARE v_writer text;
BEGIN
 IF pg_catalog.to_regprocedure(
   'atlas.resolve_governed_canonical_farm_rule_authority_v1(uuid,uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
   'public.read_governed_canonical_rulebook_root_self_api_v1(uuid,uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
   'atlas.require_accepted_prework_standing_original_v1(uuid,uuid,uuid,uuid,text,date,date,smallint[],uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
   'public.finalize_accepted_governed_prework_self_api_v1(uuid)') IS NULL
 THEN RAISE EXCEPTION 'U2C canonical authority, accept-first gate or finalizer absent';
 END IF;

 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
   WHERE t.tgname='governed_single_rulebook_u1a_source_lock_v1'
     AND t.tgrelid='atlas.governed_rulebook_versions_v1'::regclass
     AND NOT t.tgisinternal)
 OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t
   WHERE t.tgname='governed_prework_canonical_rulebook_gate_v1'
     AND t.tgrelid='atlas.governed_prework_candidate_offers_v1'::regclass
     AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'Cross-source serialized Rulebook authority trigger missing';
 END IF;

 SELECT pg_catalog.pg_get_functiondef(
  'atlas.owner_establish_standing_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])'::pg_catalog.regprocedure
 ) INTO v_writer;
 IF v_writer IS NULL OR pg_catalog.strpos(
  v_writer,'require_accepted_prework_standing_original_v1')=0
 THEN RAISE EXCEPTION 'Native original writer lacks the mandatory consent gate';
 END IF;

 IF pg_catalog.has_function_privilege('anon',
   'public.read_governed_canonical_rulebook_root_self_api_v1(uuid,uuid,uuid,uuid,uuid)',
   'EXECUTE')
 OR NOT pg_catalog.has_function_privilege('authenticated',
   'public.read_governed_canonical_rulebook_root_self_api_v1(uuid,uuid,uuid,uuid,uuid)',
   'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
   'atlas.resolve_governed_canonical_farm_rule_authority_v1(uuid,uuid,uuid,uuid,uuid)',
   'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
   'atlas.require_accepted_prework_standing_original_v1(uuid,uuid,uuid,uuid,text,date,date,smallint[],uuid)',
   'EXECUTE')
 THEN RAISE EXCEPTION 'Private arbiter, original gate or signed root reader ACL drift';
 END IF;

 IF pg_catalog.has_function_privilege('authenticated',
   'public.owner_establish_standing_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])',
   'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
   'public.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)',
   'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
   'public.admit_standing_continuing_source_work_self_api_v1(uuid,uuid,uuid,uuid,date)',
   'EXECUTE')
 OR pg_catalog.has_function_privilege('service_role',
   'public.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)',
   'EXECUTE')
 OR NOT pg_catalog.has_function_privilege('authenticated',
   'public.finalize_accepted_governed_prework_self_api_v1(uuid)',
   'EXECUTE')
 THEN RAISE EXCEPTION 'Older direct Work creator bypasses worker acceptance';
 END IF;

 -- A schema test proves structure ONLY, not signed principal response,
 -- native subject custody, worker assent, concurrency, live installation,
 -- performance, or a faithful migrated release.
END;
$check$;
