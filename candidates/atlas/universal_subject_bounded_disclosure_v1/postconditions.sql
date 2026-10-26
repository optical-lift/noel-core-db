-- Validate source structure on disposable production-shaped schema clone.
DO $test$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
    WHERE conname='subject_disclosure_action_identity_v1'
      AND conrelid='atlas.subject_disclosure_decision_events_v1'::regclass) THEN
  RAISE EXCEPTION 'Missing strict decision idempotency constraint'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='atlas'
      AND indexname='subject_disclosure_current_lookup_v1') THEN
  RAISE EXCEPTION 'Missing bounded exact-subject lookup index'; END IF;
 IF has_table_privilege('authenticated','atlas.subject_disclosure_decision_events_v1','SELECT')
  OR has_function_privilege('anon',
   'public.connected_person_original_work_subject_self_api_v1(uuid,uuid,uuid,text,text,uuid)',
   'EXECUTE') THEN
   RAISE EXCEPTION 'Unrestricted original Subject access'; END IF;
END $test$;
-- Mandatory signed tests: governor decides identity only, worker sees label
-- but not condition, condition separately granted/withheld, outsider and anon
-- denied, old grant revoked by later withhold, old farm paths still denied.
