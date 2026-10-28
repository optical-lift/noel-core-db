-- Source-only guard. Run after candidate.sql in ONE ROLLBACK transaction
-- in a fully shaped test database. Never infer signed human acceptance.
DO $check$
DECLARE
 v_d record;
 v_def text;
 v_acl record;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint c
   WHERE c.conrelid='atlas.subject_disclosure_decision_events_v1'::regclass
   AND c.conname='subject_disclosure_supported_subject_v1'
   AND pg_get_constraintdef(c.oid) LIKE '%current_inventory%') THEN
   RAISE EXCEPTION 'Farm current-inventory decision missing exact subject scope';
 END IF;
 FOR v_d IN SELECT p.oid,p.proname,p.prosecdef,p.proconfig FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname IN (
     'governor_set_farm_current_inventory_self_api_v1',
     'connected_person_farm_current_inventory_self_api_v1',
     'connected_person_current_farm_inventory_sources_self_api_v1') LOOP
   IF NOT v_d.prosecdef OR
     NOT('search_path=""'=ANY(v_d.proconfig) OR
       'search_path='=ANY(v_d.proconfig)) OR
     has_function_privilege('anon',v_d.oid,'EXECUTE') OR
     has_function_privilege('authenticated',v_d.oid,'EXECUTE')
   THEN RAISE EXCEPTION 'Unvalidated inventory function prematurely exposed: %',v_d.proname; END IF;
 END LOOP;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname IN (
     'governor_set_farm_current_inventory_self_api_v1',
     'connected_person_farm_current_inventory_self_api_v1',
     'connected_person_current_farm_inventory_sources_self_api_v1'))<>3 THEN
   RAISE EXCEPTION 'Missing exact three inventory contracts'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname='governor_set_farm_current_inventory_self_api_v1';
 IF v_def NOT LIKE '%company_work_native_ledger_owner_self_v1%'
   OR v_def NOT LIKE '%person_has_native_ledger_connection_v1%'
   OR v_def NOT LIKE '%subject_disclosure_decision_events_v1%'
   OR v_def NOT LIKE '%source_action_id%'
 THEN RAISE EXCEPTION 'Ledger root action or exact append-only evidence missing'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname='connected_person_farm_current_inventory_self_api_v1';
 IF v_def NOT LIKE '%person_has_native_ledger_connection_v1%'
   OR v_def NOT LIKE '%current_inventory%'
   OR v_def NOT LIKE '%subject_disclosure_decision_events_v1%'
   OR v_def NOT LIKE '%lifecycle_status%'
   OR v_def NOT LIKE '%cycle_state NOT IN%'
   OR v_def NOT LIKE '%financialsIncluded%'
   OR v_def LIKE '%SELECT * FROM atlas.zone_registry_source_v1%'
 THEN RAISE EXCEPTION 'Inventory reader is not exactly source gated'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
   AND p.proname='connected_person_current_farm_inventory_sources_self_api_v1';
 IF v_def NOT LIKE '%has_current_subject_disclosure_v1%'
   OR v_def NOT LIKE '%person_has_native_ledger_connection_v1%'
 THEN RAISE EXCEPTION 'Farm list discloses ungranted source'; END IF;
END;
$check$;

-- Unauthenticated and unsigned sessions may neither list a Ledger's farms
-- nor get an individual bed's current crop evidence.
DO $unsigned$
DECLARE v_denied integer:=0;
BEGIN
 BEGIN
   PERFORM atlas.connected_person_current_farm_inventory_sources_self_api_v1(
     '00000000-0000-4000-8000-000000000010'::uuid);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_denied:=v_denied+1; END;
 BEGIN
   PERFORM atlas.connected_person_farm_current_inventory_self_api_v1(
     '00000000-0000-4000-8000-000000000011'::uuid,
     '00000000-0000-4000-8000-000000000010'::uuid,
     '00000000-0000-4000-8000-000000000012'::uuid);
 EXCEPTION WHEN SQLSTATE '42501' THEN v_denied:=v_denied+1; END;
 IF v_denied<>2 THEN RAISE EXCEPTION 'Unsigned exact inventory access did not fail closed'; END IF;
END;
$unsigned$;
-- Before exposing functions, run genuine GoTrue/PostgREST positives and
-- negatives: governor grant, Anna browse, explicit bed identity withhold,
-- bed condition withheld, revoked person, different farm, different Ledger,
-- unauthorized worker write, planned-only crop absent, expected dates/price
-- undiscoverable and alternate old reader denied.
