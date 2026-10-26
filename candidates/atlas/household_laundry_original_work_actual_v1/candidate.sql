BEGIN;
-- After universal_household_canonical_work_custody_v1 and
-- universal_household_canonical_work_guards_v1. Use exact original Work IDs.
INSERT INTO atlas.work_result_contract_policies(
 contract_key,source_domain,acceptance_mode,description,metadata
) VALUES ('household_laundry_begin_cycle_v1','household','domain_adapter',
 'A genuine wash_started physical Actual satisfies only the begin_cycle Need/Work; drying and return_to_use are separate.',
 jsonb_build_object('qualificationEvent','wash_started',
                    'noAutomaticRhythm',true,'physicalStepOnly',true))
ON CONFLICT (contract_key) DO NOTHING;
CREATE UNIQUE INDEX IF NOT EXISTS work_execution_results_household_idempotency_v1
 ON atlas.work_execution_results(household_id,idempotency_key)
 WHERE household_id IS NOT NULL;

CREATE OR REPLACE FUNCTION atlas.record_household_laundry_observation_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_observation text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_id uuid;v_new boolean:=false;
 v_old atlas.care_observation_events%rowtype;
BEGIN
 IF p_kernel_instance_id IS NULL OR p_action_id IS NULL
   OR nullif(btrim(coalesce(p_observation,'')),'') IS NULL
   OR length(btrim(p_observation))>1200 THEN
   RAISE EXCEPTION 'Exact Laundry observation and action required.'
    USING ERRCODE='22023';
 END IF;
 SELECT i.household_id INTO v_household
 FROM atlas.household_kernel_instances i
 WHERE i.id=p_kernel_instance_id AND i.kernel_key='household.laundry'
   AND i.state='active';
 IF v_household IS NULL THEN RAISE EXCEPTION 'Original Laundry unavailable.'
   USING ERRCODE='42501'; END IF;
 PERFORM atlas.require_household_governor_self_v1(v_household);
 INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    condition_state,disposition,observed_by_user_id,source_kind,source_key,
    note,inferred_from_clock,metadata
 ) VALUES(
    'household','household_kernel_instance',p_kernel_instance_id::text,
    'household',v_household,'ready_for_cycle','intervene',auth.uid(),
    'household_laundry_confirmed_observation',
    'household-laundry-observation:'||v_household::text||':'||p_action_id::text,
    btrim(p_observation),false,
    jsonb_build_object('observationRole','physical_state_confirmed',
                       'isWorkCreation',false)
 ) ON CONFLICT (source_key) DO NOTHING RETURNING id INTO v_id;
 v_new:=v_id IS NOT NULL;
 IF NOT v_new THEN
  SELECT * INTO v_old FROM atlas.care_observation_events o
  WHERE o.source_key='household-laundry-observation:'||
    v_household::text||':'||p_action_id::text;
  IF v_old.id IS NULL OR v_old.scope_id<>v_household
    OR v_old.subject_id<>p_kernel_instance_id::text
    OR v_old.note IS DISTINCT FROM btrim(p_observation)
    OR v_old.condition_state<>'ready_for_cycle' THEN
    RAISE EXCEPTION 'Observation action key was used for different evidence.'
      USING ERRCODE='23505';
  END IF;
  v_id:=v_old.id;
 ELSE
  INSERT INTO atlas.care_current_state(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    condition_state,disposition,last_observed_at,last_observation_id,metadata
  ) VALUES(
    'household','household_kernel_instance',p_kernel_instance_id::text,
    'household',v_household,'ready_for_cycle','intervene',now(),v_id,
    jsonb_build_object('evidenceKind','confirmed_observation')
  ) ON CONFLICT(scope_kind,scope_id,subject_domain,subject_kind,subject_id)
    DO UPDATE SET condition_state='ready_for_cycle',disposition='intervene',
      last_observed_at=excluded.last_observed_at,
      last_observation_id=excluded.last_observation_id,
      updated_at=now();
 END IF;
 RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_observation_v1',
    'householdId',v_household,'instanceId',p_kernel_instance_id,
    'observationId',v_id,'conditionState','ready_for_cycle',
    'workCreated',false,'idempotent',NOT v_new);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.record_household_laundry_observation_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_observation text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.record_household_laundry_observation_self_api_v1(
   p_kernel_instance_id,p_action_id,p_observation);
$function$;
REVOKE ALL ON FUNCTION public.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.establish_household_laundry_original_work_self_api_v1(
 p_kernel_instance_id uuid,p_observation_id uuid,p_action_id uuid,
 p_self_carried boolean DEFAULT false,p_assignee_household_member_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_governor uuid;v_need atlas.household_need_occurrences_v1%rowtype;
 v_work uuid;v_allocation uuid;v_person uuid;v_source_new boolean:=false;
BEGIN
 IF p_kernel_instance_id IS NULL OR p_observation_id IS NULL OR p_action_id IS NULL
    OR (p_self_carried AND p_assignee_household_member_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Exact confirmed Need and one or no carrier required.'
     USING ERRCODE='22023';
 END IF;
 SELECT household_id INTO v_household FROM atlas.household_kernel_instances
 WHERE id=p_kernel_instance_id AND kernel_key='household.laundry'
    AND state='active';
 IF v_household IS NULL THEN
  RAISE EXCEPTION 'Original Laundry unavailable.' USING ERRCODE='42501';
 END IF;
 v_governor:=atlas.require_household_governor_self_v1(v_household);
 IF NOT EXISTS(
   SELECT 1 FROM atlas.care_observation_events o
   WHERE o.id=p_observation_id
     AND o.scope_kind='household' AND o.scope_id=v_household
     AND o.subject_domain='household' AND o.subject_kind='household_kernel_instance'
     AND o.subject_id=p_kernel_instance_id::text
     AND o.condition_state='ready_for_cycle'
     AND o.source_kind='household_laundry_confirmed_observation'
 ) OR NOT EXISTS(
   SELECT 1 FROM atlas.care_current_state c
   WHERE c.scope_kind='household' AND c.scope_id=v_household
    AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
    AND c.subject_id=p_kernel_instance_id::text AND c.condition_state='ready_for_cycle'
 ) THEN
   RAISE EXCEPTION 'Laundry Need requires present confirmed physical state.'
     USING ERRCODE='23514';
 END IF;
 IF p_assignee_household_member_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM atlas.household_members m
    WHERE m.id=p_assignee_household_member_id
      AND m.household_id=v_household AND m.active
 ) THEN
   RAISE EXCEPTION 'Carrier must be a real active Household member.'
     USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
    'household-laundry-need:'||p_kernel_instance_id::text||':begin_cycle',0));
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
 WHERE instance_id=p_kernel_instance_id AND need_key='begin_cycle' AND state='open'
 FOR UPDATE;
 IF v_need.id IS NOT NULL THEN
   IF v_need.current_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Existing Need lacks original Work; repair required.'
      USING ERRCODE='23514';
   END IF;
   -- Reading the same existing Need cannot assign somebody else by accident.
   RETURN jsonb_build_object('ok',true,
     'contractVersion','household_laundry_original_work_v1',
     'householdId',v_household,'instanceId',p_kernel_instance_id,
     'needOccurrenceId',v_need.id,'workItemId',v_need.current_work_item_id,
     'existingCurrentNeed',true,'noNewWorkCreated',true);
 END IF;
 INSERT INTO atlas.household_need_occurrences_v1(
   household_id,instance_id,need_key,state,opened_by_observation_id,source_action_id
 ) VALUES(
   v_household,p_kernel_instance_id,'begin_cycle','open',p_observation_id,p_action_id
 ) RETURNING * INTO v_need;
 INSERT INTO atlas.work_items(
  household_id,organization_id,source_object_type,source_object_id,
  work_state,title,instructions,stable_key,result_contract_key,
  created_by_user_id,metadata
 ) VALUES (
  v_household,NULL,'household_need_occurrence',v_need.id,
  'open','Start the wash',
  'Begin the actual wash. This step alone does not complete drying, readying, or return-to-use.',
  'household:laundry:begin_cycle:'||v_need.id::text,
  'household_laundry_begin_cycle_v1',auth.uid(),
  jsonb_build_object('needOccurrenceId',v_need.id,
    'worldKernelKey','household.laundry','partiallyCompletable',true,
    'carrierEstablishedOnlyByExplicitDecision',true)
 ) RETURNING id INTO v_work;
 UPDATE atlas.household_need_occurrences_v1
 SET current_work_item_id=v_work,updated_at=now() WHERE id=v_need.id;
 INSERT INTO atlas.work_item_context_links(
   household_id,organization_id,work_item_id,
   subject_domain,subject_kind,subject_id,relation_kind,
   provenance,metadata
 ) VALUES(
   v_household,NULL,v_work,'household','kernel_instance',
   p_kernel_instance_id,'acts_on',
   jsonb_build_object('source','household_laundry_need',
       'needOccurrenceId',v_need.id),'{}'::jsonb
 );
 IF p_self_carried OR p_assignee_household_member_id IS NOT NULL THEN
  IF p_self_carried THEN v_person:=v_governor;
  ELSE
   SELECT m.person_id INTO v_person FROM atlas.household_members m
   WHERE m.id=p_assignee_household_member_id AND m.household_id=v_household;
  END IF;
  INSERT INTO atlas.work_allocations(
   household_id,organization_id,work_item_id,allocation_role,state,
   assignee_household_member_id,assignee_canonical_person_id,
   establishment_basis_kind,establishment_basis,metadata
  ) VALUES(
   v_household,NULL,v_work,'responsible','active',
   p_assignee_household_member_id,v_person,
   'household_explicit_carrier_v1',jsonb_build_object(
     'householdId',v_household,'workItemId',v_work,
     'senderPersonId',v_governor,
     'decisionReason','Governor established exact Laundry Work carrier',
     'sourceActionId',p_action_id),
   jsonb_build_object('source','household_explicit_laundry_work_v1')
  ) RETURNING id INTO v_allocation;
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_original_work_v1',
   'householdId',v_household,'instanceId',p_kernel_instance_id,
   'observationId',p_observation_id,'needOccurrenceId',v_need.id,
   'workItemId',v_work,'allocationId',v_allocation,
   'assignedCanonicalPersonId',v_person,
   'childrenWithoutAccountsAreNotSignedUsers',true,
   'workOnDate',NULL,'clockAdmitted',false,
   'existingCurrentNeed',false,'noNewWorkCreated',false);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 p_kernel_instance_id uuid,p_observation_id uuid,p_action_id uuid,
 p_self_carried boolean DEFAULT false,p_assignee_household_member_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.establish_household_laundry_original_work_self_api_v1(
  p_kernel_instance_id,p_observation_id,p_action_id,
  p_self_carried,p_assignee_household_member_id);
$function$;
REVOKE ALL ON FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) TO authenticated;

-- A real physical Actual is accepted as exactly ONE work transition. It
-- cannot assert that the entire Laundry kernel or every Household Need is done.
CREATE OR REPLACE FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(
 p_work_item_id uuid,p_action_id uuid,p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_rhythm atlas.household_rhythms%rowtype;v_satisfaction uuid;v_interval integer;
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
 v_source_key:='household-laundry-wash-started:'||v_work.id::text||':'||p_action_id::text;
 SELECT id INTO v_result FROM atlas.care_result_events
 WHERE source_key=v_source_key AND scope_id=v_work.household_id
  AND subject_id=v_need.instance_id::text
  AND result_kind='improved_more_remains' AND condition_after='washing';
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
  RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_wash_started_v1',
    'householdId',v_work.household_id,'instanceId',v_need.instance_id,
    'workItemId',v_work.id,'needOccurrenceId',v_need.id,
    'careResultId',v_result,'workResultId',v_work_result,
    'acceptanceId',v_acceptance,'rhythmSatisfactionId',NULL,
    'workCompleted',true,'laundryCompletelyDone',false,'idempotent',true);
 END IF;
 IF v_work.work_state<>'open' OR v_need.state<>'open' THEN
  RAISE EXCEPTION 'Work transition already closed or unavailable.'
   USING ERRCODE='23514';
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
 UPDATE atlas.care_current_state
 SET condition_state='washing',disposition='observe',
   last_observed_at=v_at,last_observation_id=v_observation,updated_at=now()
 WHERE scope_kind='household' AND scope_id=v_work.household_id
   AND subject_domain='household' AND subject_kind='household_kernel_instance'
   AND subject_id=v_need.instance_id::text;
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
 -- Household Rhythm satisfaction is optional and exists only when separately
 -- explicitly established with a qualifying touch. Pattern/calibration alone
 -- is NOT a rhythm or a recurring task. Wash start is a conditional step.
 SELECT * INTO v_rhythm FROM atlas.household_rhythms h
 WHERE h.household_id=v_work.household_id
   AND h.stable_key='kernel:household.laundry:general'
   AND h.active
   AND h.metadata->>'establishedByExplicitDecision'='true'
   AND h.metadata->>'qualifyingEvent'='wash_started'
 ORDER BY h.created_at DESC LIMIT 1 FOR UPDATE;
 IF v_rhythm.id IS NOT NULL THEN
  v_interval:=NULLIF(v_rhythm.metadata->>'renewAfterSeconds','')::integer;
  IF v_interval IS NOT NULL AND v_interval>0 THEN
   INSERT INTO atlas.rhythm_satisfactions(
     household_id,household_rhythm_id,organization_id,farm_id,
     rhythm_state_id,rhythm_rule_id,rhythm_binding_id,
     rhythm_key,subject_kind,subject_id,satisfaction_key,
     satisfaction_kind,satisfied_at,source_kind,source_id,source_event,
     policy_match,evidence,created_by_user_id
   ) VALUES(
     v_work.household_id,v_rhythm.id,NULL,NULL,NULL,NULL,NULL,
     v_rhythm.stable_key,'household_kernel_instance',v_need.instance_id,
     'wash_started:'||v_work.id::text,'conditional',v_at,
     'household_laundry_physical_actual',v_result,'wash_started',
     jsonb_build_object('qualifyingEvent','wash_started',
       'acceptedExplicitRhythm',true,'satisfiesOnly','begin_cycle'),
     jsonb_build_object('workItemId',v_work.id,'careResultId',v_result),
     auth.uid()
   ) RETURNING id INTO v_satisfaction;
   UPDATE atlas.household_rhythms SET
     next_window_start=v_at+make_interval(secs=>v_interval),
     next_window_end=CASE WHEN next_window_start IS NOT NULL
        AND next_window_end IS NOT NULL
       THEN v_at+make_interval(secs=>v_interval)+
           (next_window_end-next_window_start)
       ELSE NULL END,
     updated_at=now()
   WHERE id=v_rhythm.id;
  END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','household_laundry_wash_started_v1',
   'householdId',v_work.household_id,'instanceId',v_need.instance_id,
   'workItemId',v_work.id,'needOccurrenceId',v_need.id,
   'careResultId',v_result,'careObservationId',v_observation,
   'workResultId',v_work_result,'acceptanceId',v_acceptance,
   'rhythmSatisfactionId',v_satisfaction,
   'workCompleted',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 p_work_item_id uuid,p_action_id uuid,p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.record_household_laundry_wash_started_self_api_v1(
   p_work_item_id,p_action_id,p_note);
$function$;
REVOKE ALL ON FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) TO authenticated;
COMMIT;
