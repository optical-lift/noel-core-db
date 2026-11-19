-- HELD source; destructive clean cutover requires exact clone proof and separate production authorization.
-- No retained legacy Laundry rhythm, compatibility adapter, window, or satisfaction.
BEGIN;
LOCK TABLE atlas.household_rhythms,atlas.household_rhythm_explicit_decisions_v1,atlas.rhythm_satisfactions IN ACCESS EXCLUSIVE MODE;
DO $preflight$ BEGIN
 IF EXISTS(SELECT 1 FROM atlas.household_rhythm_explicit_decisions_v1)
 OR EXISTS(SELECT 1 FROM atlas.rhythm_satisfactions WHERE household_id IS NOT NULL)
 THEN RAISE EXCEPTION 'Unexpected accepted evidence; clean-cutover review required'; END IF;
 IF md5(pg_get_functiondef('atlas.household_laundry_current_self_api_v1()'::regprocedure)) IS DISTINCT FROM '3381e926d13e305ff8cca0075e83688d' THEN RAISE EXCEPTION 'Source drift: household_laundry_current_self_api_v1'; END IF;
 IF md5(pg_get_functiondef('atlas.household_laundry_explicit_rhythm_decide_self_api_v1(uuid,uuid,text,integer,text)'::regprocedure)) IS DISTINCT FROM '7381c42fc05572c960600693e1ee89d2' THEN RAISE EXCEPTION 'Source drift: household_laundry_explicit_rhythm_decide_self_api_v1'; END IF;
 IF md5(pg_get_functiondef('atlas.personal_laundry_kernel_self_api_v1()'::regprocedure)) IS DISTINCT FROM '621fd80ff743778d1aa515e0334761bb' THEN RAISE EXCEPTION 'Source drift: personal_laundry_kernel_self_api_v1'; END IF;
 IF md5(pg_get_functiondef('atlas.record_household_laundry_drying_started_self_api_v1(uuid,uuid,text)'::regprocedure)) IS DISTINCT FROM '0a501641e0272840545293abf428c53a' THEN RAISE EXCEPTION 'Source drift: record_household_laundry_drying_started_self_api_v1'; END IF;
 IF md5(pg_get_functiondef('atlas.record_household_laundry_returned_to_use_self_api_v1(uuid,uuid,text)'::regprocedure)) IS DISTINCT FROM '2aac371f39bbe4b3249ee556562aabfc' THEN RAISE EXCEPTION 'Source drift: record_household_laundry_returned_to_use_self_api_v1'; END IF;
 IF md5(pg_get_functiondef('atlas.record_household_laundry_wash_started_self_api_v1(uuid,uuid,text)'::regprocedure)) IS DISTINCT FROM '1a6941c7c89265c2276f7b7939167945' THEN RAISE EXCEPTION 'Source drift: record_household_laundry_wash_started_self_api_v1'; END IF;
END $preflight$;
-- Reuse the empty governed-decision carrier, eliminating its obsolete foreign key.
ALTER TABLE atlas.household_rhythm_explicit_decisions_v1 DROP COLUMN rhythm_id RESTRICT;
ALTER TABLE atlas.household_rhythm_explicit_decisions_v1 RENAME TO household_need_renewal_decisions_v1;
CREATE INDEX household_need_renewal_latest_v1 ON atlas.household_need_renewal_decisions_v1(household_id,instance_id,decision_seq DESC);
-- Actual deletion, not inactivation or archival. Parent row has no accepted dependents.
DELETE FROM atlas.household_rhythms WHERE stable_key='kernel:household.laundry:general';
-- This key is no longer a valid scheduled Rhythm. An integrity constraint is
-- not a compatibility reader/authority; neither generic writer may recreate it.
ALTER TABLE atlas.household_rhythms ADD CONSTRAINT household_rhythm_not_laundry_kernel_v1 CHECK(stable_key IS DISTINCT FROM 'kernel:household.laundry:general');
CREATE OR REPLACE FUNCTION atlas.household_laundry_current_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_kernel atlas.household_kernel_instances%rowtype;
 v_condition text;v_observation uuid;v_need atlas.household_need_occurrences_v1%rowtype;
 v_work atlas.work_items%rowtype;v_allocation atlas.work_allocations%rowtype;
 v_last_completed_work_id uuid;v_last_completed_at timestamptz;
 v_renewal_decision atlas.household_need_renewal_decisions_v1%rowtype;
BEGIN
 v_household:=atlas.principal_current_household_id_v1();
 IF v_household IS NULL THEN
  RAISE EXCEPTION 'Original Household unavailable.' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_household_governor_self_v1(v_household);
 SELECT * INTO v_kernel FROM atlas.household_kernel_instances
 WHERE household_id=v_household AND kernel_key='household.laundry'
 ORDER BY created_at DESC LIMIT 1;
 IF v_kernel.id IS NOT NULL THEN
  SELECT condition_state,last_observation_id INTO v_condition,v_observation
  FROM atlas.care_current_state
  WHERE scope_kind='household' AND scope_id=v_household
   AND subject_domain='household' AND subject_kind='household_kernel_instance'
   AND subject_id=v_kernel.id::text;
  -- Only current unsatisfied Need/Work belongs in this slot.
  -- Completed wash-started Work remains original history but must not
  -- prevent the next genuine observed Laundry cycle from being established.
  SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
  WHERE household_id=v_household AND instance_id=v_kernel.id
    AND state='open'
  ORDER BY created_at DESC,id DESC LIMIT 1;
  SELECT w.id,n.satisfied_at INTO v_last_completed_work_id,v_last_completed_at
  FROM atlas.household_need_occurrences_v1 n
  JOIN atlas.work_items w ON w.id=n.current_work_item_id
    AND w.household_id=n.household_id
  WHERE n.household_id=v_household AND n.instance_id=v_kernel.id
    AND n.state='satisfied' AND w.work_state='completed'
    AND n.need_key='begin_cycle' AND w.result_contract_key='household_laundry_begin_cycle_v1'
  ORDER BY n.satisfied_at DESC,n.id DESC LIMIT 1;
  -- The single original Subject decision governs expected future inspection.
  SELECT * INTO v_renewal_decision FROM atlas.household_need_renewal_decisions_v1 d
   WHERE d.household_id=v_household AND d.instance_id=v_kernel.id
   ORDER BY d.decision_seq DESC LIMIT 1;
  IF v_need.id IS NOT NULL THEN
    SELECT * INTO v_work FROM atlas.work_items w WHERE w.id=v_need.current_work_item_id
       AND w.household_id=v_household;
    SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.household_id=v_household AND a.work_item_id=v_work.id
      AND a.allocation_role='responsible' AND a.state='active'
    ORDER BY a.allocated_at DESC LIMIT 1;
  END IF;
 END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','household_laundry_current_v1',
  'householdId',v_household,
  'instanceId',v_kernel.id,
  'instanceState',v_kernel.state,
  'currentCondition',v_condition,
  'lastObservationId',v_observation,
  'needOccurrenceId',v_need.id,
  'needState',v_need.state,
  'workItemId',v_work.id,
  'lastCompletedWorkItemId',v_last_completed_work_id,
  'lastCompletedWashStartedAt',v_last_completed_at,
  'renewalDecisionId',v_renewal_decision.decision_id,
  'renewalDecisionKind',v_renewal_decision.decision_kind,
  'renewAfterDays',v_renewal_decision.renew_after_days,
  'renewalEstablished',coalesce(v_renewal_decision.decision_kind='establish',false),
  'workTitle',v_work.title,
  'workState',v_work.work_state,
  'carrierAllocationId',v_allocation.id,
  'assignedCanonicalPersonId',v_allocation.assignee_canonical_person_id,
  'assignedHouseholdMemberId',v_allocation.assignee_household_member_id,
  'workOnDate',NULL,
  'clockAdmitted',false,
  'wholeLaundryDone',false,
  'oneOriginalWork',true
 );
END;
$function$;
CREATE OR REPLACE FUNCTION atlas.personal_laundry_kernel_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_household_id uuid;
  v_kernel atlas.world_kernel_definitions%rowtype;
  v_instance atlas.household_kernel_instances%rowtype;
  v_member_count integer := 0;
  v_child_count integer := 0;
  v_composition_complete boolean := false;
  v_audience_key text := 'general';
  v_models jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  select * into v_kernel
  from atlas.world_kernel_definitions k
  where k.kernel_key = 'household.laundry'
    and k.active
  order by k.version desc
  limit 1;

  select count(*)::integer,
         count(*) filter (where lower(coalesce(m.relationship,'')) in ('child','son','daughter','dependent_child'))::integer
    into v_member_count, v_child_count
  from atlas.household_members m
  where m.household_id = v_household_id
    and m.active;

  select coalesce((h.metadata->>'compositionComplete')::boolean, false)
    into v_composition_complete
  from atlas.households h
  where h.id = v_household_id;

  if v_member_count >= 5 or v_child_count >= 3 then
    v_audience_key := 'family_busy';
  elsif v_member_count >= 2 then
    v_audience_key := 'shared_household';
  elsif v_member_count = 1 and v_composition_complete then
    v_audience_key := 'one_person';
  else
    v_audience_key := 'general';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'modelKey', m.model_key,
    'audienceKey', m.audience_key,
    'title', m.title,
    'summary', m.summary,
    'configuration', m.configuration
  ) order by m.position), '[]'::jsonb)
    into v_models
  from atlas.world_kernel_models m
  where m.kernel_key = v_kernel.kernel_key
    and m.kernel_version = v_kernel.version
    and m.audience_key = v_audience_key
    and m.active;

  select * into v_instance
  from atlas.household_kernel_instances i
  where i.household_id = v_household_id
    and i.kernel_key = 'household.laundry'
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'personal_laundry_kernel_self_api_v1',
    'householdId', v_household_id,
    'modelSelection', jsonb_build_object(
      'audienceKey', v_audience_key,
      'knownMemberCount', v_member_count,
      'knownChildCount', v_child_count,
      'compositionComplete', v_composition_complete,
      'basis', case
        when v_audience_key = 'family_busy' then 'known_household_size'
        when v_audience_key = 'shared_household' then 'known_shared_household'
        when v_audience_key = 'one_person' then 'confirmed_one_person_household'
        else 'household_composition_not_yet_complete'
      end
    ),
    'models', v_models,
    'kernel', jsonb_build_object(
      'key', v_kernel.kernel_key,
      'version', v_kernel.version,
      'title', v_kernel.title,
      'definition', v_kernel.definition,
      'ordinaryRealityExpected', true
    ),
    'instance', case when v_instance.id is null then null else jsonb_build_object(
      'id', v_instance.id,
      'state', v_instance.state,
      'configuration', v_instance.configuration,
      'calibratedAt', v_instance.calibrated_at,
      'metadata', v_instance.metadata
    ) end
  );
end;
$function$;
CREATE OR REPLACE FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(p_work_item_id uuid, p_action_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_at timestamptz:=clock_timestamp();
BEGIN
 IF p_work_item_id IS NULL OR p_action_id IS NULL OR
  length(coalesce(p_note,''))>1500 THEN
  RAISE EXCEPTION 'Exact Work and physical Actual action required.' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'household-laundry-work:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.household_id IS NULL OR
  v_work.organization_id IS NOT NULL OR
  v_work.source_object_type<>'household_need_occurrence' OR
  v_work.result_contract_key<>'household_laundry_begin_cycle_v1' THEN
   RAISE EXCEPTION 'Original Household Laundry Work unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.household_work_actor_v1(v_work.household_id);
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 need
  WHERE need.id=v_work.source_object_id AND need.household_id=v_work.household_id
    AND need.current_work_item_id=v_work.id FOR UPDATE;
 IF v_need.id IS NULL THEN
  RAISE EXCEPTION 'Work original Need record unavailable.' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=v_work.household_id AND p.status='active'
     AND p.user_id=auth.uid() AND p.person_id=v_person
 ) AND NOT EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   LEFT JOIN atlas.household_members hm ON hm.id=a.assignee_household_member_id
   WHERE a.household_id=v_work.household_id AND a.work_item_id=v_work.id
     AND a.allocation_role='responsible' AND a.state='active'
     AND (a.assignee_canonical_person_id=v_person
       OR (hm.person_id=v_person AND hm.user_id=auth.uid() AND hm.active))
 ) THEN
  RAISE EXCEPTION 'Physical Work Actual requires authorized original carrier.'
   USING ERRCODE='42501';
 END IF;
  v_source_key:='household-laundry-wash-started:'||v_work.id::text||':'||p_action_id::text;
 SELECT id INTO v_result FROM atlas.care_result_events
 WHERE source_key=v_source_key AND scope_id=v_work.household_id
  AND subject_id=v_need.instance_id::text
  AND result_kind='improved_more_remains' AND condition_after='washing'
  AND note IS NOT DISTINCT FROM nullif(btrim(p_note),'');
 IF v_result IS NOT NULL THEN
  v_existing:=true;
  SELECT id INTO v_work_result FROM atlas.work_execution_results
  WHERE household_id=v_work.household_id AND work_item_id=v_work.id
    AND idempotency_key=v_source_key;
  IF v_work_result IS NULL OR v_work.work_state<>'completed' THEN
    RAISE EXCEPTION 'Partial physical Actual receipt requires source reconciliation.'
      USING ERRCODE='23514';
  END IF;
  SELECT id INTO v_acceptance FROM atlas.work_result_acceptances
   WHERE household_id=v_work.household_id AND execution_result_id=v_work_result;
  IF v_acceptance IS NULL OR v_need.state<>'satisfied' THEN
    RAISE EXCEPTION 'No accepted complete physical receipt for replay.'
     USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_wash_started_v1',
    'householdId',v_work.household_id,'instanceId',v_need.instance_id,
    'workItemId',v_work.id,'needOccurrenceId',v_need.id,
    'careResultId',v_result,'workResultId',v_work_result,
    'acceptanceId',v_acceptance,
    'workCompleted',true,'laundryCompletelyDone',false,'idempotent',true);
 END IF;
 IF v_work.work_state<>'open' OR v_need.state<>'open' THEN
  RAISE EXCEPTION 'Work transition already closed or unavailable.'
   USING ERRCODE='23514';
 END IF;
 SELECT c.condition_state INTO v_before FROM atlas.care_current_state c
 WHERE c.scope_kind='household' AND c.scope_id=v_work.household_id
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
   AND c.subject_id=v_need.instance_id::text FOR UPDATE;
 IF v_before<>'ready_for_cycle' THEN
  RAISE EXCEPTION 'Current confirmed Laundry need is no longer ready.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.care_result_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   result_kind,condition_before,condition_after,actor_user_id,
   source_kind,source_key,note,metadata,occurred_at
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,'improved_more_remains',
   v_before,'washing',auth.uid(),'household_laundry_physical_actual',
   v_source_key,nullif(btrim(p_note),''),
   jsonb_build_object('workItemId',v_work.id,'needOccurrenceId',v_need.id,
     'completedStep','wash_started','wholeLaundryDone',false),v_at
 ) RETURNING id INTO v_result;
 INSERT INTO atlas.care_observation_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   observed_at,condition_state,disposition,observed_by_user_id,
   source_kind,source_key,note,inferred_from_clock,metadata
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,v_at,'washing','observe',auth.uid(),
   'household_laundry_actual_state',
   'household-laundry-actual-observation:'||v_result::text,
   nullif(btrim(p_note),''),false,jsonb_build_object('careResultId',v_result)
 ) RETURNING id INTO v_observation;
 -- Existing observation trigger already applied the genuine
 -- 'washing' observation by observed_at; no second state update or
 -- silent overwrite of a newer independent observation.
 IF NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state current_state
   WHERE current_state.scope_kind='household'
     AND current_state.scope_id=v_work.household_id
     AND current_state.subject_domain='household'
     AND current_state.subject_kind='household_kernel_instance'
     AND current_state.subject_id=v_need.instance_id::text
     AND current_state.condition_state='washing'
     AND current_state.last_observation_id=v_observation
 ) THEN
   RAISE EXCEPTION 'Original Laundry state readback failed after physical observation.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.work_execution_results(
   household_id,organization_id,work_item_id,reported_by_user_id,
   result_kind,result_contract_key,idempotency_key,payload,metadata,reported_at
 ) VALUES (
   v_work.household_id,NULL,v_work.id,auth.uid(),'completed',
   'household_laundry_begin_cycle_v1',v_source_key,
   jsonb_build_object('careResultId',v_result,'careObservationId',v_observation,
                      'step','wash_started','isWholeLaundryDone',false),
   jsonb_build_object('needOccurrenceId',v_need.id),v_at
 ) RETURNING id INTO v_work_result;
 INSERT INTO atlas.work_result_acceptances(
   household_id,organization_id,work_item_id,execution_result_id,
   decision,acceptance_kind,accepted_by_domain,evidence
 ) VALUES (
   v_work.household_id,NULL,v_work.id,v_work_result,'accepted',
   'source_qualified_physical_actual','household_laundry_actual',
   jsonb_build_object('careResultId',v_result,'step','wash_started')
 ) RETURNING id INTO v_acceptance;
 UPDATE atlas.work_items SET work_state='completed',completed_at=v_at,updated_at=now()
 WHERE id=v_work.id;
 UPDATE atlas.household_need_occurrences_v1
 SET state='satisfied',satisfied_at=v_at,
   satisfied_by_care_result_id=v_result,updated_at=now()
 WHERE id=v_need.id;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_wash_started_v1',
   'householdId',v_work.household_id,'instanceId',v_need.instance_id,
   'workItemId',v_work.id,'needOccurrenceId',v_need.id,
   'careResultId',v_result,'careObservationId',v_observation,
   'workResultId',v_work_result,'acceptanceId',v_acceptance,
   'workCompleted',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;
CREATE OR REPLACE FUNCTION atlas.record_household_laundry_drying_started_self_api_v1(p_work_item_id uuid, p_action_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_at timestamptz:=clock_timestamp();
BEGIN
 IF p_work_item_id IS NULL OR p_action_id IS NULL OR
  length(coalesce(p_note,''))>1500 THEN
  RAISE EXCEPTION 'Exact Work and physical Actual action required.' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'household-laundry-work:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.household_id IS NULL OR
  v_work.organization_id IS NOT NULL OR
  v_work.source_object_type<>'household_need_occurrence' OR
  v_work.result_contract_key<>'household_laundry_begin_drying_v1' THEN
   RAISE EXCEPTION 'Original Household Laundry Work unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.household_work_actor_v1(v_work.household_id);
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 need
  WHERE need.id=v_work.source_object_id AND need.household_id=v_work.household_id
    AND need.current_work_item_id=v_work.id FOR UPDATE;
 IF v_need.id IS NULL OR v_need.need_key<>'begin_drying' THEN
  RAISE EXCEPTION 'Work original Need record unavailable.' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=v_work.household_id AND p.status='active'
     AND p.user_id=auth.uid() AND p.person_id=v_person
 ) AND NOT EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   LEFT JOIN atlas.household_members hm ON hm.id=a.assignee_household_member_id
   WHERE a.household_id=v_work.household_id AND a.work_item_id=v_work.id
     AND a.allocation_role='responsible' AND a.state='active'
     AND (a.assignee_canonical_person_id=v_person
       OR (hm.person_id=v_person AND hm.user_id=auth.uid() AND hm.active))
 ) THEN
  RAISE EXCEPTION 'Physical Work Actual requires authorized original carrier.'
   USING ERRCODE='42501';
 END IF;
  v_source_key:='household-laundry-drying-started:'||v_work.id::text||':'||p_action_id::text;
 SELECT id INTO v_result FROM atlas.care_result_events
 WHERE source_key=v_source_key AND scope_id=v_work.household_id
  AND subject_id=v_need.instance_id::text
  AND result_kind='improved_more_remains' AND condition_after='drying'
  AND note IS NOT DISTINCT FROM nullif(btrim(p_note),'');
 IF v_result IS NOT NULL THEN
  v_existing:=true;
  SELECT id INTO v_work_result FROM atlas.work_execution_results
  WHERE household_id=v_work.household_id AND work_item_id=v_work.id
    AND idempotency_key=v_source_key;
  IF v_work_result IS NULL OR v_work.work_state<>'completed' THEN
    RAISE EXCEPTION 'Partial physical Actual receipt requires source reconciliation.'
      USING ERRCODE='23514';
  END IF;
  SELECT id INTO v_acceptance FROM atlas.work_result_acceptances
   WHERE household_id=v_work.household_id AND execution_result_id=v_work_result;
  IF v_acceptance IS NULL OR v_need.state<>'satisfied' THEN
    RAISE EXCEPTION 'No accepted complete physical receipt for replay.'
     USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_drying_started_v1',
    'householdId',v_work.household_id,'instanceId',v_need.instance_id,
    'workItemId',v_work.id,'needOccurrenceId',v_need.id,
    'careResultId',v_result,'workResultId',v_work_result,
    'acceptanceId',v_acceptance,
    'workCompleted',true,'laundryCompletelyDone',false,'idempotent',true);
 END IF;
 IF v_work.work_state<>'open' OR v_need.state<>'open' THEN
  RAISE EXCEPTION 'Work transition already closed or unavailable.'
   USING ERRCODE='23514';
 END IF;
 SELECT c.condition_state INTO v_before FROM atlas.care_current_state c
 WHERE c.scope_kind='household' AND c.scope_id=v_work.household_id
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
   AND c.subject_id=v_need.instance_id::text FOR UPDATE;
 IF v_before IS DISTINCT FROM 'wet_ready_for_drying' OR NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state c WHERE c.scope_kind='household' AND c.scope_id=v_work.household_id
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance' AND c.subject_id=v_need.instance_id::text
   AND c.last_observation_id=v_need.opened_by_observation_id) THEN
  RAISE EXCEPTION 'Current confirmed Laundry need is no longer ready.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.care_result_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   result_kind,condition_before,condition_after,actor_user_id,
   source_kind,source_key,note,metadata,occurred_at
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,'improved_more_remains',
   v_before,'drying',auth.uid(),'household_laundry_physical_actual',
   v_source_key,nullif(btrim(p_note),''),
   jsonb_build_object('workItemId',v_work.id,'needOccurrenceId',v_need.id,
     'completedStep','drying_started','wholeLaundryDone',false),v_at
 ) RETURNING id INTO v_result;
 INSERT INTO atlas.care_observation_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   observed_at,condition_state,disposition,observed_by_user_id,
   source_kind,source_key,note,inferred_from_clock,metadata
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,v_at,'drying','observe',auth.uid(),
   'household_laundry_actual_state',
   'household-laundry-actual-observation:'||v_result::text,
   nullif(btrim(p_note),''),false,jsonb_build_object('careResultId',v_result)
 ) RETURNING id INTO v_observation;
 -- Existing observation trigger already applied the genuine
 -- 'drying' observation by observed_at; no second state update or
 -- silent overwrite of a newer independent observation.
 IF NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state current_state
   WHERE current_state.scope_kind='household'
     AND current_state.scope_id=v_work.household_id
     AND current_state.subject_domain='household'
     AND current_state.subject_kind='household_kernel_instance'
     AND current_state.subject_id=v_need.instance_id::text
     AND current_state.condition_state='drying'
     AND current_state.last_observation_id=v_observation
 ) THEN
   RAISE EXCEPTION 'Original Laundry state readback failed after physical observation.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.work_execution_results(
   household_id,organization_id,work_item_id,reported_by_user_id,
   result_kind,result_contract_key,idempotency_key,payload,metadata,reported_at
 ) VALUES (
   v_work.household_id,NULL,v_work.id,auth.uid(),'completed',
   'household_laundry_begin_drying_v1',v_source_key,
   jsonb_build_object('careResultId',v_result,'careObservationId',v_observation,
                      'step','drying_started','isWholeLaundryDone',false),
   jsonb_build_object('needOccurrenceId',v_need.id),v_at
 ) RETURNING id INTO v_work_result;
 INSERT INTO atlas.work_result_acceptances(
   household_id,organization_id,work_item_id,execution_result_id,
   decision,acceptance_kind,accepted_by_domain,evidence
 ) VALUES (
   v_work.household_id,NULL,v_work.id,v_work_result,'accepted',
   'source_qualified_physical_actual','household_laundry_actual',
   jsonb_build_object('careResultId',v_result,'step','drying_started')
 ) RETURNING id INTO v_acceptance;
 UPDATE atlas.work_items SET work_state='completed',completed_at=v_at,updated_at=now()
 WHERE id=v_work.id;
 UPDATE atlas.household_need_occurrences_v1
 SET state='satisfied',satisfied_at=v_at,
   satisfied_by_care_result_id=v_result,updated_at=now()
 WHERE id=v_need.id;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_drying_started_v1',
   'householdId',v_work.household_id,'instanceId',v_need.instance_id,
   'workItemId',v_work.id,'needOccurrenceId',v_need.id,
   'careResultId',v_result,'careObservationId',v_observation,
   'workResultId',v_work_result,'acceptanceId',v_acceptance,
   'workCompleted',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;
CREATE OR REPLACE FUNCTION atlas.record_household_laundry_returned_to_use_self_api_v1(p_work_item_id uuid, p_action_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_at timestamptz:=clock_timestamp();
BEGIN
 IF p_work_item_id IS NULL OR p_action_id IS NULL OR
  length(coalesce(p_note,''))>1500 THEN
  RAISE EXCEPTION 'Exact Work and physical Actual action required.' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'household-laundry-work:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.household_id IS NULL OR
  v_work.organization_id IS NOT NULL OR
  v_work.source_object_type<>'household_need_occurrence' OR
  v_work.result_contract_key<>'household_laundry_return_to_use_v1' THEN
   RAISE EXCEPTION 'Original Household Laundry Work unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.household_work_actor_v1(v_work.household_id);
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 need
  WHERE need.id=v_work.source_object_id AND need.household_id=v_work.household_id
    AND need.current_work_item_id=v_work.id FOR UPDATE;
 IF v_need.id IS NULL OR v_need.need_key<>'return_to_use' THEN
  RAISE EXCEPTION 'Work original Need record unavailable.' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=v_work.household_id AND p.status='active'
     AND p.user_id=auth.uid() AND p.person_id=v_person
 ) AND NOT EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   LEFT JOIN atlas.household_members hm ON hm.id=a.assignee_household_member_id
   WHERE a.household_id=v_work.household_id AND a.work_item_id=v_work.id
     AND a.allocation_role='responsible' AND a.state='active'
     AND (a.assignee_canonical_person_id=v_person
       OR (hm.person_id=v_person AND hm.user_id=auth.uid() AND hm.active))
 ) THEN
  RAISE EXCEPTION 'Physical Work Actual requires authorized original carrier.'
   USING ERRCODE='42501';
 END IF;
  v_source_key:='household-laundry-returned-to-use:'||v_work.id::text||':'||p_action_id::text;
 SELECT id INTO v_result FROM atlas.care_result_events
 WHERE source_key=v_source_key AND scope_id=v_work.household_id
  AND subject_id=v_need.instance_id::text
  AND result_kind='improved_more_remains' AND condition_after='returned_to_use'
  AND note IS NOT DISTINCT FROM nullif(btrim(p_note),'');
 IF v_result IS NOT NULL THEN
  v_existing:=true;
  SELECT id INTO v_work_result FROM atlas.work_execution_results
  WHERE household_id=v_work.household_id AND work_item_id=v_work.id
    AND idempotency_key=v_source_key;
  IF v_work_result IS NULL OR v_work.work_state<>'completed' THEN
    RAISE EXCEPTION 'Partial physical Actual receipt requires source reconciliation.'
      USING ERRCODE='23514';
  END IF;
  SELECT id INTO v_acceptance FROM atlas.work_result_acceptances
   WHERE household_id=v_work.household_id AND execution_result_id=v_work_result;
  IF v_acceptance IS NULL OR v_need.state<>'satisfied' THEN
    RAISE EXCEPTION 'No accepted complete physical receipt for replay.'
     USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_returned_to_use_v1',
    'householdId',v_work.household_id,'instanceId',v_need.instance_id,
    'workItemId',v_work.id,'needOccurrenceId',v_need.id,
    'careResultId',v_result,'workResultId',v_work_result,
    'acceptanceId',v_acceptance,
    'workCompleted',true,'loadReturnedToUse',true,'laundryCompletelyDone',false,'idempotent',true);
 END IF;
 IF v_work.work_state<>'open' OR v_need.state<>'open' THEN
  RAISE EXCEPTION 'Work transition already closed or unavailable.'
   USING ERRCODE='23514';
 END IF;
 SELECT c.condition_state INTO v_before FROM atlas.care_current_state c
 WHERE c.scope_kind='household' AND c.scope_id=v_work.household_id
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
   AND c.subject_id=v_need.instance_id::text FOR UPDATE;
 IF v_before IS DISTINCT FROM 'dry_ready_for_return' OR NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state c WHERE c.scope_kind='household' AND c.scope_id=v_work.household_id
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance' AND c.subject_id=v_need.instance_id::text
   AND c.last_observation_id=v_need.opened_by_observation_id) THEN
  RAISE EXCEPTION 'Current confirmed Laundry need is no longer ready.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.care_result_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   result_kind,condition_before,condition_after,actor_user_id,
   source_kind,source_key,note,metadata,occurred_at
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,'improved_more_remains',
   v_before,'returned_to_use',auth.uid(),'household_laundry_physical_actual',
   v_source_key,nullif(btrim(p_note),''),
   jsonb_build_object('workItemId',v_work.id,'needOccurrenceId',v_need.id,
     'completedStep','returned_to_use','wholeLaundryDone',false),v_at
 ) RETURNING id INTO v_result;
 INSERT INTO atlas.care_observation_events(
   subject_domain,subject_kind,subject_id,scope_kind,scope_id,
   observed_at,condition_state,disposition,observed_by_user_id,
   source_kind,source_key,note,inferred_from_clock,metadata
 ) VALUES(
   'household','household_kernel_instance',v_need.instance_id::text,
   'household',v_work.household_id,v_at,'returned_to_use','observe',auth.uid(),
   'household_laundry_actual_state',
   'household-laundry-actual-observation:'||v_result::text,
   nullif(btrim(p_note),''),false,jsonb_build_object('careResultId',v_result)
 ) RETURNING id INTO v_observation;
 -- Existing observation trigger already applied the genuine
 -- 'returned_to_use' observation by observed_at; no second state update or
 -- silent overwrite of a newer independent observation.
 IF NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state current_state
   WHERE current_state.scope_kind='household'
     AND current_state.scope_id=v_work.household_id
     AND current_state.subject_domain='household'
     AND current_state.subject_kind='household_kernel_instance'
     AND current_state.subject_id=v_need.instance_id::text
     AND current_state.condition_state='returned_to_use'
     AND current_state.last_observation_id=v_observation
 ) THEN
   RAISE EXCEPTION 'Original Laundry state readback failed after physical observation.'
    USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.work_execution_results(
   household_id,organization_id,work_item_id,reported_by_user_id,
   result_kind,result_contract_key,idempotency_key,payload,metadata,reported_at
 ) VALUES (
   v_work.household_id,NULL,v_work.id,auth.uid(),'completed',
   'household_laundry_return_to_use_v1',v_source_key,
   jsonb_build_object('careResultId',v_result,'careObservationId',v_observation,
                      'step','returned_to_use','isWholeLaundryDone',false),
   jsonb_build_object('needOccurrenceId',v_need.id),v_at
 ) RETURNING id INTO v_work_result;
 INSERT INTO atlas.work_result_acceptances(
   household_id,organization_id,work_item_id,execution_result_id,
   decision,acceptance_kind,accepted_by_domain,evidence
 ) VALUES (
   v_work.household_id,NULL,v_work.id,v_work_result,'accepted',
   'source_qualified_physical_actual','household_laundry_actual',
   jsonb_build_object('careResultId',v_result,'step','returned_to_use')
 ) RETURNING id INTO v_acceptance;
 UPDATE atlas.work_items SET work_state='completed',completed_at=v_at,updated_at=now()
 WHERE id=v_work.id;
 UPDATE atlas.household_need_occurrences_v1
 SET state='satisfied',satisfied_at=v_at,
   satisfied_by_care_result_id=v_result,updated_at=now()
 WHERE id=v_need.id;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_returned_to_use_v1',
   'householdId',v_work.household_id,'instanceId',v_need.instance_id,
   'workItemId',v_work.id,'needOccurrenceId',v_need.id,
   'careResultId',v_result,'careObservationId',v_observation,
   'workResultId',v_work_result,'acceptanceId',v_acceptance,
   'workCompleted',true,'loadReturnedToUse',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;
CREATE OR REPLACE FUNCTION atlas.household_need_renewal_decide_self_api_v1(p_kernel_instance_id uuid, p_action_id uuid, p_decision_kind text, p_renew_after_days integer, p_decision_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_instance atlas.household_kernel_instances%rowtype;
 v_person uuid;
 v_existing atlas.household_need_renewal_decisions_v1%rowtype;
 v_decision atlas.household_need_renewal_decisions_v1%rowtype;
 v_latest atlas.household_need_renewal_decisions_v1%rowtype;
 v_is_new boolean:=false;
 v_reason text:=nullif(btrim(coalesce(p_decision_reason,'')),'');
BEGIN
 IF p_kernel_instance_id IS NULL OR p_action_id IS NULL
   OR p_decision_kind IS NULL OR p_decision_kind NOT IN ('establish','withdraw')
   OR (p_decision_kind='establish' AND
      (p_renew_after_days IS NULL OR p_renew_after_days NOT BETWEEN 1 AND 365))
   OR (p_decision_kind='withdraw' AND p_renew_after_days IS NOT NULL)
   OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1200 THEN
  RAISE EXCEPTION 'Explicit bounded Household Need renewal decision required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_instance FROM atlas.household_kernel_instances
 WHERE id=p_kernel_instance_id AND kernel_key='household.laundry'
   AND state='active';
 IF v_instance.id IS NULL THEN
  RAISE EXCEPTION 'Original Laundry Subject not admitted' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.require_household_governor_self_v1(v_instance.household_id);
 PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.household.need.renewal:'||v_instance.household_id::text,0));
 SELECT * INTO v_existing FROM atlas.household_need_renewal_decisions_v1
 WHERE household_id=v_instance.household_id AND source_action_id=p_action_id;
 IF v_existing.decision_id IS NOT NULL THEN
   IF v_existing.instance_id IS DISTINCT FROM v_instance.id
      OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
      OR v_existing.renew_after_days IS DISTINCT FROM p_renew_after_days
      OR v_existing.decision_reason IS DISTINCT FROM v_reason
      OR v_existing.governor_person_id IS DISTINCT FROM v_person THEN
      RAISE EXCEPTION 'Renewal decision ID previously used for different intent'
       USING ERRCODE='23505';
   END IF;
   v_decision:=v_existing;
 ELSE
   SELECT * INTO v_latest FROM atlas.household_need_renewal_decisions_v1
   WHERE household_id=v_instance.household_id AND instance_id=v_instance.id
   ORDER BY decision_seq DESC LIMIT 1;
   IF p_decision_kind='withdraw' AND v_latest.decision_kind IS DISTINCT FROM 'establish' THEN
     RAISE EXCEPTION 'No established inspection interval to withdraw' USING ERRCODE='23514';
   END IF;
   INSERT INTO atlas.household_need_renewal_decisions_v1(
     household_id,instance_id,decision_kind,qualifying_event,
     renew_after_days,source_action_id,decision_reason,governor_person_id)
   VALUES (
     v_instance.household_id,v_instance.id,p_decision_kind,
     'wash_started',p_renew_after_days,p_action_id,v_reason,v_person
   ) RETURNING * INTO v_decision;
   v_is_new:=true;
 END IF;
 SELECT * INTO v_latest FROM atlas.household_need_renewal_decisions_v1
 WHERE household_id=v_instance.household_id AND instance_id=v_instance.id
 ORDER BY decision_seq DESC LIMIT 1;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','household_need_renewal_decision_v1',
   'householdId',v_instance.household_id,'instanceId',v_instance.id,
   'decisionId',v_decision.decision_id,
   'actionId',p_action_id,'decisionKind',p_decision_kind,
   'renewAfterDays',p_renew_after_days,
   'currentlyEstablished',v_latest.decision_kind='establish',
   'isGovernedByOriginalDecision',true,
   'clockAdmitted',false,'needCreated',false,
   'workCreated',false,'idempotent',NOT v_is_new);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_need_renewal_decide_self_api_v1(uuid,uuid,text,integer,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.household_need_renewal_decide_self_api_v1(p_kernel_instance_id uuid,p_action_id uuid,p_decision_kind text,p_renew_after_days integer,p_decision_reason text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $body$
 SELECT atlas.household_need_renewal_decide_self_api_v1(p_kernel_instance_id,p_action_id,p_decision_kind,p_renew_after_days,p_decision_reason);
$body$;
REVOKE ALL ON FUNCTION public.household_need_renewal_decide_self_api_v1(uuid,uuid,text,integer,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.household_need_renewal_decide_self_api_v1(uuid,uuid,text,integer,text) TO authenticated;
DROP FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(uuid,uuid,text,integer,text) RESTRICT;
DROP FUNCTION atlas.household_laundry_explicit_rhythm_decide_self_api_v1(uuid,uuid,text,integer,text) RESTRICT;
-- Held source only. One original Care/Need/Work chain; no new schedule or Work issuer.
create or replace function atlas.household_laundry_renewal_attention_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare
 h uuid; inst uuid; p jsonb; obs atlas.care_observation_events%rowtype;
 closed_obs atlas.care_observation_events%rowtype; cfg jsonb;
 started timestamptz; anchor_at timestamptz; expected_at timestamptz;
 days integer; status text; as_of timestamptz:=statement_timestamp();
 empty_packet jsonb;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed canonical Person required.' using errcode='42501'; end if;
 empty_packet:=jsonb_build_object('ok',true,'contractVersion','household_laundry_renewal_attention_v1',
   'state','not_applicable','asOf',as_of,'workCreated',false,'needCreated',false,
   'clockAdmitted',false,'physicalNeedInferred',false);
 h:=atlas.principal_current_household_id_v1();
 if h is null then return empty_packet; end if;
 perform atlas.require_household_governor_self_v1(h);
 p:=atlas.household_laundry_current_self_api_v1();
 if p->>'householdId' is distinct from h::text or p->>'instanceState' is distinct from 'active'
    or p->>'instanceId' is null or p->>'currentCondition' is null
    or p->>'currentCondition' not in ('returned_to_use','accumulating')
    or p->>'workItemId' is not null or p->>'needOccurrenceId' is not null
    or p->>'lastCompletedWashStartedAt' is null then return empty_packet; end if;
 inst:=(p->>'instanceId')::uuid;
 select configuration into cfg from atlas.household_kernel_instances
 where id=inst and household_id=h and kernel_key='household.laundry' and state='active';
 if not found then return empty_packet; end if;
 select * into obs from atlas.care_observation_events
 where id=(p->>'lastObservationId')::uuid and scope_kind='household' and scope_id=h
   and subject_domain='household' and subject_kind='household_kernel_instance' and subject_id=inst::text
   and condition_state=p->>'currentCondition' and inferred_from_clock=false;
 if obs.id is null then return empty_packet; end if;
 -- The initial anchor is an actual accepted closed load, never an inferred completion.
 if obs.source_kind='household_laundry_actual_state' and obs.condition_state='returned_to_use' then
   closed_obs:=obs;
 elsif obs.source_kind='household_laundry_renewal_not_ready' and obs.condition_state='accumulating' then
   select * into closed_obs from atlas.care_observation_events
   where id::text=obs.metadata->>'closedLoadObservationId' and scope_kind='household' and scope_id=h
    and subject_domain='household' and subject_kind='household_kernel_instance' and subject_id=inst::text
    and condition_state='returned_to_use' and source_kind='household_laundry_actual_state' and inferred_from_clock=false;
 else return empty_packet; end if;
 if closed_obs.id is null or not exists(
  select 1 from atlas.care_result_events cr
  join atlas.work_items w on w.id::text=cr.metadata->>'workItemId' and w.household_id=h
   and w.organization_id is null and w.work_state='completed' and w.result_contract_key='household_laundry_return_to_use_v1'
  join atlas.household_need_occurrences_v1 n on n.id=w.source_object_id and n.household_id=h
   and n.instance_id=inst and n.current_work_item_id=w.id and n.state='satisfied'
   and n.satisfied_by_care_result_id=cr.id
  join atlas.work_execution_results wr on wr.work_item_id=w.id and wr.household_id=h
   and wr.result_contract_key='household_laundry_return_to_use_v1' and wr.result_kind='completed'
   and wr.payload->>'careResultId'=cr.id::text
  join atlas.work_result_acceptances wa on wa.execution_result_id=wr.id and wa.work_item_id=w.id
   and wa.household_id=h and wa.decision='accepted'
  where cr.id::text=closed_obs.metadata->>'careResultId' and cr.scope_kind='household' and cr.scope_id=h
   and cr.subject_domain='household' and cr.subject_kind='household_kernel_instance' and cr.subject_id=inst::text
   and cr.condition_after='returned_to_use' and cr.source_kind='household_laundry_physical_actual'
 ) then return empty_packet; end if;
 started:=(p->>'lastCompletedWashStartedAt')::timestamptz;
 if started>closed_obs.observed_at or closed_obs.observed_at>obs.observed_at or obs.observed_at>as_of
 then return empty_packet; end if;
 -- Calibration supplies only a proposed interval. Do not resurrect a withdrawn decision.
 if p->>'renewalDecisionKind'='withdraw' then return empty_packet; end if;
 if (p->>'renewalEstablished')::boolean is true and p->>'renewalDecisionKind'='establish'
    and p->>'renewalDecisionId' is not null
    and (p->>'renewAfterDays')::integer between 1 and 365 then
   days:=(p->>'renewAfterDays')::integer;
   anchor_at:=case when obs.source_kind='household_laundry_renewal_not_ready'
     then greatest(started,obs.observed_at) else started end;
   expected_at:=anchor_at+make_interval(secs=>days*86400);
   status:=case when expected_at<=as_of then 'due' else 'waiting' end;
 elsif p->>'renewalDecisionId' is null and cfg->>'usualPattern'='little_most_days' then
   days:=1; status:='proposal';
 else return empty_packet; end if;
 return empty_packet||jsonb_build_object('state',status,'householdId',h,'instanceId',inst,
    'observationId',obs.id,'closedLoadObservationId',closed_obs.id,'washStartedAt',started,
    'anchorAt',anchor_at,'expectedCheckAt',expected_at,'renewAfterDays',days,
    'decisionId',case when status='proposal' then null else p->>'renewalDecisionId' end,
    'proposalBasis',case when status='proposal' then 'declared_pattern_little_most_days' else null end);
end;
$body$;
revoke all on function atlas.household_laundry_renewal_attention_self_api_v1() from public,anon,authenticated,service_role;
create or replace function public.household_laundry_renewal_attention_self_api_v1()
returns jsonb language sql stable security definer set search_path to ''
as $body$ select atlas.household_laundry_renewal_attention_self_api_v1(); $body$;
revoke all on function public.household_laundry_renewal_attention_self_api_v1() from public,anon,authenticated,service_role;
grant execute on function public.household_laundry_renewal_attention_self_api_v1() to authenticated;

-- A negative physical observation renews attention, not the accepted Rhythm or any Work.
create or replace function atlas.record_household_laundry_renewal_not_ready_self_api_v1(
 p_instance_id uuid,p_observation_id uuid,p_decision_id uuid,p_action_id uuid
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare h uuid; packet jsonb; prior atlas.care_observation_events%rowtype;
 new_id uuid; src text;
begin
 h:=atlas.principal_current_household_id_v1();
 if h is null then raise exception 'Original Household unavailable.' using errcode='42501'; end if;
 perform atlas.require_household_governor_self_v1(h);
 if p_instance_id is null or p_observation_id is null or p_decision_id is null or p_action_id is null
 then raise exception 'Exact current observation and governing decision required.' using errcode='22023'; end if;
 -- Serialize with the existing explicit Rhythm decision writer, then the current Care row.
 perform pg_advisory_xact_lock(hashtextextended('atlas.household.need.renewal:'||h::text,0));
 perform 1 from atlas.care_current_state where subject_domain='household'
  and subject_kind='household_kernel_instance' and subject_id=p_instance_id::text
  and scope_kind='household' and scope_id=h for update;
 if not found then raise exception 'Original Care state unavailable.' using errcode='23514'; end if;
 src:='household-laundry-renewal-not-ready:'||h::text||':'||p_action_id::text;
 select * into prior from atlas.care_observation_events where source_key=src;
 if prior.id is not null then
   if prior.scope_kind is distinct from 'household' or prior.scope_id is distinct from h
      or prior.subject_domain is distinct from 'household' or prior.subject_kind is distinct from 'household_kernel_instance'
      or prior.subject_id is distinct from p_instance_id::text
      or prior.source_kind is distinct from 'household_laundry_renewal_not_ready'
      or prior.observed_by_user_id is distinct from auth.uid()
      or prior.metadata->>'previousObservationId' is distinct from p_observation_id::text
      or prior.metadata->>'renewalDecisionId' is distinct from p_decision_id::text
   then raise exception 'Action already used for different evidence.' using errcode='23505'; end if;
   packet:=atlas.household_laundry_renewal_attention_self_api_v1();
   if packet->>'observationId' is distinct from prior.id::text or packet->>'decisionId' is distinct from p_decision_id::text
   then raise exception 'Earlier observation; reread current source.' using errcode='23514'; end if;
   return packet||jsonb_build_object('idempotent',true);
 end if;
 packet:=atlas.household_laundry_renewal_attention_self_api_v1();
 if packet->>'state' is distinct from 'due' or packet->>'instanceId' is distinct from p_instance_id::text
    or packet->>'observationId' is distinct from p_observation_id::text
    or packet->>'decisionId' is distinct from p_decision_id::text
 then raise exception 'Current due check and accepted interval required.' using errcode='23514'; end if;
 insert into atlas.care_observation_events(subject_domain,subject_kind,subject_id,scope_kind,scope_id,
  observed_at,condition_state,disposition,observed_by_user_id,source_kind,source_key,note,inferred_from_clock,metadata)
 values('household','household_kernel_instance',p_instance_id::text,'household',h,
  statement_timestamp(),'accumulating','hold',auth.uid(),'household_laundry_renewal_not_ready',src,
  'Not enough laundry for another load.',false,
  jsonb_build_object('previousObservationId',p_observation_id,'renewalDecisionId',p_decision_id,
     'closedLoadObservationId',packet->>'closedLoadObservationId','isWorkCreation',false))
 returning id into new_id;
 packet:=atlas.household_laundry_renewal_attention_self_api_v1();
 if packet->>'state' is distinct from 'waiting' or packet->>'observationId' is distinct from new_id::text
    or packet->>'decisionId' is distinct from p_decision_id::text
 then raise exception 'New actual observation not verified.' using errcode='23514'; end if;
 return packet||jsonb_build_object('idempotent',false);
end;
$body$;
revoke all on function atlas.record_household_laundry_renewal_not_ready_self_api_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_renewal_not_ready_self_api_v1(
 p_instance_id uuid,p_observation_id uuid,p_decision_id uuid,p_action_id uuid
) returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_renewal_not_ready_self_api_v1(p_instance_id,p_observation_id,p_decision_id,p_action_id); $body$;
revoke all on function public.record_household_laundry_renewal_not_ready_self_api_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_renewal_not_ready_self_api_v1(uuid,uuid,uuid,uuid) to authenticated;

COMMIT;
