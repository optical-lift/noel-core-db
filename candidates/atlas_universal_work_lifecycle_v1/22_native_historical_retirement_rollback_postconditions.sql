-- HELD disposable-clone checks. Must execute after 16,17,19,20,21.
-- This does NOT substitute for signed GoTrue/REST or actual-Result testing.
DO $assert$
DECLARE
 v_f regprocedure;
 v_s text;
 v_count integer;
BEGIN
 IF NOT EXISTS(
   SELECT 1 FROM pg_constraint c
   WHERE c.conrelid='atlas.work_lifecycle_events_v1'::regclass
     AND c.contype='c'
     AND pg_get_constraintdef(c.oid) LIKE '%historical_self_adoption_review_events_v1%'
 ) THEN RAISE EXCEPTION 'Historical review not admitted as exact event source'
   USING ERRCODE='23514'; END IF;
 FOR v_f IN SELECT unnest(ARRAY[
   to_regprocedure('atlas.governor_historical_retirement_preflight_self_api_v1(uuid,uuid,uuid)'),
   to_regprocedure('atlas.governor_retire_historical_work_self_api_v1(uuid,uuid,uuid,text,uuid)'),
   to_regprocedure('public.governor_historical_retirement_preflight_self_api_v1(uuid,uuid,uuid)'),
   to_regprocedure('public.governor_retire_historical_work_self_api_v1(uuid,uuid,uuid,text,uuid)')
 ]::regprocedure[]) LOOP
   IF v_f IS NULL
   OR has_function_privilege('anon',v_f,'EXECUTE')
   OR NOT has_function_privilege('authenticated',v_f,'EXECUTE')
   THEN RAISE EXCEPTION 'Native retirement RPC missing or grants unsafe'
   USING ERRCODE='42501'; END IF;
   SELECT pg_get_functiondef(v_f) INTO v_s;
   IF position('organization_memberships' in v_s)>0
      OR position('farm_memberships' in v_s)>0
   THEN RAISE EXCEPTION 'Historical retirement reintroduced legacy membership authority'
      USING ERRCODE='42501'; END IF;
 END LOOP;
 v_f:=to_regprocedure('atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)');
 IF v_f IS NULL OR has_function_privilege('anon',v_f,'EXECUTE')
   OR has_function_privilege('authenticated',v_f,'EXECUTE')
   OR has_function_privilege('service_role',v_f,'EXECUTE')
 THEN RAISE EXCEPTION 'One private terminal transition authority must stay hidden'
   USING ERRCODE='42501'; END IF;
 SELECT pg_get_functiondef(v_f) INTO v_s;
 IF position('p_transition_kind=''cancel''' in v_s)=0
  OR position('company_work_retirement_dependency_snapshot_v1' in v_s)=0
  OR position('historical_self_adoption_review_events_v1' in v_s)=0
  OR position('work_transition_applied' in v_s)=0
  OR position('work_state=''cancelled''' in v_s)=0
  OR position('result_reported' in v_s)>0
 THEN RAISE EXCEPTION 'Cancellation must share private core, guards and original projection'
 USING ERRCODE='23514'; END IF;
 -- Real history is unmodified by mere candidate installation.
 SELECT count(*) INTO v_count
 FROM atlas.work_lifecycle_events_v1
 WHERE event_kind='work_transition_applied' AND to_state='cancelled';
 IF v_count<>0 THEN RAISE EXCEPTION 'Unsolicited retirement event in rollback candidate'
   USING ERRCODE='23514'; END IF;
 RAISE NOTICE 'PASS: private native historical retirement structural gate; signed actor matrix still required';
END; $assert$;
