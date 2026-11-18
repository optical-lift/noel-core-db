-- Process expectation is not physical evidence of completion, Work, or Clock admission.
-- Reuse the existing accepted Work result, immutable evidence and current care state.
begin;
create or replace function atlas.household_laundry_reassessment_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare
 h uuid; inst uuid; c atlas.care_current_state%rowtype;
 w uuid; result_id uuid; started_at timestamptz; check_from timestamptz; contract_key text; step_key text; ev atlas.evidence_records%rowtype;
 expected timestamptz; status text; as_of timestamptz:=statement_timestamp();
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed canonical Person required.' using errcode='42501'; end if;
 h:=atlas.principal_current_household_id_v1();
 if h is null then
  return jsonb_build_object('ok',true,'contractVersion','household_laundry_reassessment_v1',
    'state','not_applicable','asOf',as_of,'workCreated',false,'clockAdmitted',false,'physicalCompletionInferred',false);
 end if;
 perform atlas.require_household_governor_self_v1(h);
 select id into inst from atlas.household_kernel_instances
 where household_id=h and kernel_key='household.laundry' and state='active';
 if inst is not null then
  select * into c from atlas.care_current_state where scope_kind='household' and scope_id=h
   and subject_domain='household' and subject_kind='household_kernel_instance' and subject_id=inst::text;
 end if;
 if c.condition_state is null or c.condition_state not in ('washing','drying') then
  return jsonb_build_object('ok',true,'contractVersion','household_laundry_reassessment_v1',
    'state','not_applicable','asOf',as_of,'workCreated',false,'clockAdmitted',false,'physicalCompletionInferred',false);
 end if;
 -- A single current physical state, with the original accepted wash-start receipt.
 contract_key:=case c.condition_state when 'washing' then 'household_laundry_begin_cycle_v1' else 'household_laundry_begin_drying_v1' end;
 step_key:=case c.condition_state when 'washing' then 'wash_started' else 'drying_started' end;
 select wi.id,cr.id,cr.occurred_at,o.observed_at into w,result_id,started_at,check_from
  from atlas.care_observation_events o
  join atlas.care_result_events cr on cr.id::text=o.metadata->>'careResultId'
   and cr.scope_kind='household' and cr.scope_id=h and cr.subject_domain='household'
   and cr.subject_kind='household_kernel_instance' and cr.subject_id=inst::text
   and cr.source_kind='household_laundry_physical_actual' and cr.condition_after=c.condition_state
   and cr.metadata->>'completedStep'=step_key
  join atlas.work_items wi on wi.id::text=cr.metadata->>'workItemId' and wi.household_id=h
   and wi.organization_id is null and wi.work_state='completed'
   and wi.result_contract_key=contract_key
  join atlas.household_need_occurrences_v1 n on n.id=wi.source_object_id and n.household_id=h
   and n.instance_id=inst and n.current_work_item_id=wi.id and n.state='satisfied'
   and n.satisfied_by_care_result_id=cr.id
  where o.id=c.last_observation_id and o.scope_kind='household' and o.scope_id=h
   and o.subject_domain='household' and o.subject_kind='household_kernel_instance' and o.subject_id=inst::text
   and o.source_kind in ('household_laundry_actual_state','household_laundry_still_running_observation') and o.condition_state=c.condition_state
   and o.inferred_from_clock=false
   and exists(select 1 from atlas.work_execution_results wr
      join atlas.work_result_acceptances wa on wa.execution_result_id=wr.id and wa.work_item_id=wi.id
       and wa.household_id=h and wa.decision='accepted'
      where wr.household_id=h and wr.work_item_id=wi.id and wr.result_kind='completed'
       and wr.result_contract_key=contract_key and wr.payload->>'careResultId'=cr.id::text);
 if w is null then raise exception 'Current process lacks accepted original physical result.' using errcode='23514'; end if;
 select * into ev from atlas.evidence_records e where e.id::text=c.metadata->>'laundryReassessmentEvidenceId'
    and e.scope_kind='household' and e.scope_id=h and e.subject_domain='household'
    and e.subject_kind='household_kernel_instance' and e.subject_id=inst::text
    and e.evidence_kind='expected_process_reassessment' and e.source_kind='household_laundry_explicit_reassessment'
    and e.value->>'observationId'=c.last_observation_id::text
    and e.value->>'processResultId'=result_id::text and e.value->>'workItemId'=w::text;
 if ev.id is null then
  status:='needs_interval';
 else
  expected:=ev.effective_until;
  if expected is null or expected is distinct from c.next_reassess_at
    or jsonb_typeof(ev.value->'elapsedMinutes')<>'number'
    or (ev.value->>'elapsedMinutes')::integer not between 1 and 1440
    or expected is distinct from check_from+make_interval(mins=>(ev.value->>'elapsedMinutes')::integer)
  then raise exception 'Expected reassessment source requires reconciliation.' using errcode='23514'; end if;
  status:=case when expected<=as_of then 'due' else 'waiting' end;
 end if;
 return jsonb_build_object('ok',true,'contractVersion','household_laundry_reassessment_v1',
   'state',status,'asOf',as_of,'householdId',h,'instanceId',inst,'observationId',c.last_observation_id,
   'workItemId',w,'processResultId',result_id,'processKind',c.condition_state,'startedAt',started_at,'checkFromAt',check_from,'evidenceId',ev.id,
   'elapsedMinutes',ev.value->'elapsedMinutes','expectedReassessAt',expected,
   'workCreated',false,'clockAdmitted',false,'physicalCompletionInferred',false);
end;
$body$;
revoke all on function atlas.household_laundry_reassessment_self_api_v1() from public,anon,authenticated,service_role;
create or replace function public.household_laundry_reassessment_self_api_v1()
returns jsonb language sql stable security definer set search_path to ''
as $body$ select atlas.household_laundry_reassessment_self_api_v1(); $body$;
revoke all on function public.household_laundry_reassessment_self_api_v1() from public,anon,authenticated,service_role;
grant execute on function public.household_laundry_reassessment_self_api_v1() to authenticated;

create or replace function atlas.record_household_laundry_reassessment_self_api_v1(
 p_work_item_id uuid,p_observation_id uuid,p_elapsed_minutes integer,p_action_id uuid
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare
 packet jsonb; h uuid; inst uuid; result_id uuid; ev atlas.evidence_records%rowtype;
 started_at timestamptz; expected timestamptz; src text;
begin
 if p_work_item_id is null or p_observation_id is null or p_action_id is null
  or p_elapsed_minutes is null or p_elapsed_minutes not between 1 and 1440
 then raise exception 'Exact original process and bounded elapsed minutes required.' using errcode='22023'; end if;
 -- A read may lawfully return not_applicable; a mutation must establish
 -- signed Household jurisdiction before distinguishing stale process state.
 h:=atlas.principal_current_household_id_v1();
 if h is null then raise exception 'Original Household unavailable.' using errcode='42501'; end if;
 perform atlas.require_household_governor_self_v1(h);
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 if packet->>'state' not in ('needs_interval','waiting','due')
  or packet->>'workItemId' is distinct from p_work_item_id::text
  or packet->>'observationId' is distinct from p_observation_id::text
 then raise exception 'Current original washing observation required.' using errcode='23514'; end if;
 h:=(packet->>'householdId')::uuid; inst:=(packet->>'instanceId')::uuid;
 perform atlas.require_household_governor_self_v1(h);
 perform 1 from atlas.care_current_state c where c.scope_kind='household' and c.scope_id=h
   and c.subject_domain='household' and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text
   and c.condition_state=packet->>'processKind' and c.last_observation_id=p_observation_id for update;
 if not found then raise exception 'Current physical state changed.' using errcode='23514'; end if;
 -- Re-read after locking exact state, including another session's explicit expectation.
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 if packet->>'workItemId' is distinct from p_work_item_id::text
  or packet->>'observationId' is distinct from p_observation_id::text
 then raise exception 'Process changed.' using errcode='23514'; end if;
 result_id:=(packet->>'processResultId')::uuid; started_at:=(packet->>'checkFromAt')::timestamptz;
 expected:=started_at+make_interval(mins=>p_elapsed_minutes);
 src:='laundry-reassessment:'||p_action_id::text;
 select * into ev from atlas.evidence_records e where e.scope_kind='household' and e.scope_id=h
    and e.source_kind='household_laundry_explicit_reassessment' and e.source_key=src;
 if ev.id is not null then
  if ev.subject_id is distinct from inst::text or ev.value->>'observationId' is distinct from p_observation_id::text
    or ev.value->>'workItemId' is distinct from p_work_item_id::text
    or ev.value->>'processResultId' is distinct from result_id::text
    or ev.value->>'elapsedMinutes' is distinct from p_elapsed_minutes::text
    or ev.id::text is distinct from packet->>'evidenceId'
  then raise exception 'Earlier or conflicting expectation action; reread current source.' using errcode='23505'; end if;
  return packet||jsonb_build_object('idempotent',true);
 end if;
 -- Only the initial estimate is admitted here. Revision and fresh observation get
 -- separate source contracts rather than overwriting a prior explicit decision.
 if packet->>'state'<>'needs_interval' then
  raise exception 'An original expectation already exists.' using errcode='23514'; end if;
 insert into atlas.evidence_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
   source_kind,source_key,actor_user_id,value,observed_at,effective_from,effective_until,provenance,metadata)
 values('household',h,'household','household_kernel_instance',inst::text,'expected_process_reassessment',
   'household_laundry_explicit_reassessment',src,auth.uid(),
   jsonb_build_object('workItemId',p_work_item_id,'observationId',p_observation_id,'processResultId',result_id,
      'elapsedMinutes',p_elapsed_minutes,'predictionOnly',true),
   statement_timestamp(),started_at,expected,
   jsonb_build_object('basis','explicit_governor_expected_elapsed_time','activeEffortInferred',false),'{}'::jsonb)
 returning * into ev;
 update atlas.care_current_state c set next_reassess_at=expected,
   metadata=c.metadata||jsonb_build_object('laundryReassessmentEvidenceId',ev.id)
 where c.scope_kind='household' and c.scope_id=h and c.subject_domain='household'
   and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text
   and c.last_observation_id=p_observation_id and c.condition_state=packet->>'processKind';
 if not found then raise exception 'Original current state not retained.' using errcode='23514'; end if;
 return atlas.household_laundry_reassessment_self_api_v1()||jsonb_build_object('idempotent',false);
end;
$body$;
revoke all on function atlas.record_household_laundry_reassessment_self_api_v1(uuid,uuid,integer,uuid) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_reassessment_self_api_v1(
 p_work_item_id uuid,p_observation_id uuid,p_elapsed_minutes integer,p_action_id uuid
) returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_reassessment_self_api_v1(p_work_item_id,p_observation_id,p_elapsed_minutes,p_action_id); $body$;
revoke all on function public.record_household_laundry_reassessment_self_api_v1(uuid,uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_reassessment_self_api_v1(uuid,uuid,integer,uuid) to authenticated;

insert into atlas.work_result_contract_policies(contract_key,source_domain,acceptance_mode,active,description,metadata)
values('household_laundry_begin_drying_v1','household','domain_adapter',true,'Actual drying start satisfies only the begin-drying transition.',
jsonb_build_object('qualificationEvent','drying_started','physicalStepOnly',true,'noAutomaticRhythm',true))
on conflict(contract_key) do nothing;
do $policy$ begin
 if not exists(select 1 from atlas.work_result_contract_policies where contract_key='household_laundry_begin_drying_v1'
 and source_domain='household' and acceptance_mode='domain_adapter' and active
 and metadata->>'qualificationEvent'='drying_started') then raise exception 'Drying policy conflict'; end if;
end $policy$;
CREATE OR REPLACE FUNCTION atlas.guard_original_household_work_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 IF TG_OP='INSERT' THEN
   PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 ELSIF NEW.work_state='completed' AND OLD.work_state='open'
   AND NEW.title IS NOT DISTINCT FROM OLD.title
   AND NEW.instructions IS NOT DISTINCT FROM OLD.instructions
   AND NEW.metadata IS NOT DISTINCT FROM OLD.metadata
   AND NEW.stable_key IS NOT DISTINCT FROM OLD.stable_key
   AND NEW.operation_class IS NOT DISTINCT FROM OLD.operation_class THEN
   -- The signed carrier may close only one original Work with the accepted
   -- qualifying physical Actual, not revise its Work scope or instructions.
   PERFORM atlas.household_work_actor_v1(NEW.household_id);
 ELSE
   PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 END IF;
 IF NEW.organization_id IS NOT NULL OR NEW.organization_unit_id IS NOT NULL
    OR NOT EXISTS(
      SELECT 1 FROM atlas.household_need_occurrences_v1 need
      WHERE need.id=NEW.source_object_id
        AND need.household_id=NEW.household_id
        AND ((need.need_key='begin_cycle' AND NEW.result_contract_key='household_laundry_begin_cycle_v1')
          OR (need.need_key='begin_drying' AND NEW.result_contract_key='household_laundry_begin_drying_v1')
          OR (need.need_key='return_to_use' AND NEW.result_contract_key='household_laundry_return_to_use_v1'))
    )
    OR NEW.work_definition_id IS NOT NULL
    OR NEW.source_object_type<>'household_need_occurrence'
    OR NEW.source_object_id IS NULL THEN
  RAISE EXCEPTION 'Household Work must remain an original protected Need-bound Work.'
    USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD.household_id IS DISTINCT FROM NEW.household_id
     OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
     OR OLD.source_object_type IS DISTINCT FROM NEW.source_object_type
     OR OLD.source_object_id IS DISTINCT FROM NEW.source_object_id
     OR OLD.result_contract_key IS DISTINCT FROM NEW.result_contract_key THEN
    RAISE EXCEPTION 'Canonical Work custody and source cannot be reassigned.'
     USING ERRCODE='23514';
  END IF;
  IF NEW.work_state='completed' AND OLD.work_state IS DISTINCT FROM 'completed'
   AND NOT EXISTS(
     SELECT 1 FROM atlas.work_result_acceptances a
     JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
     WHERE a.household_id=NEW.household_id
       AND a.work_item_id=NEW.id AND a.decision='accepted'
       AND r.household_id=NEW.household_id AND r.work_item_id=NEW.id
       AND r.result_kind='completed'
       AND r.result_contract_key=NEW.result_contract_key
   ) THEN
    RAISE EXCEPTION 'Household Work cannot complete without accepted physical Actual.'
     USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.guard_household_work_actual_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.household_work_actor_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL
    OR NEW.result_kind<>'completed'
    OR NEW.result_contract_key NOT IN ('household_laundry_begin_cycle_v1','household_laundry_begin_drying_v1','household_laundry_return_to_use_v1')
    OR NEW.reported_by_user_id IS DISTINCT FROM auth.uid()
    OR NOT EXISTS (
      SELECT 1 FROM atlas.work_items w
      JOIN atlas.household_need_occurrences_v1 need
        ON need.id=w.source_object_id AND need.household_id=w.household_id
      JOIN atlas.care_result_events r
        ON r.id=(NEW.payload->>'careResultId')::uuid
        AND r.scope_id=w.household_id AND r.scope_kind='household'
        AND r.subject_domain='household'
        AND r.subject_kind='household_kernel_instance'
        AND r.subject_id=need.instance_id::text
        AND r.actor_user_id=auth.uid()
        AND ((need.need_key='begin_cycle' AND NEW.result_contract_key='household_laundry_begin_cycle_v1'
           AND r.condition_after='washing') OR
         (need.need_key='begin_drying' AND NEW.result_contract_key='household_laundry_begin_drying_v1'
           AND r.condition_before='wet_ready_for_drying' AND r.condition_after='drying'
           AND r.metadata->>'completedStep'='drying_started'
           AND r.metadata->>'workItemId'=w.id::text) OR
         (need.need_key='return_to_use' AND NEW.result_contract_key='household_laundry_return_to_use_v1'
           AND r.condition_before='dry_ready_for_return' AND r.condition_after='returned_to_use'
           AND r.metadata->>'completedStep'='returned_to_use' AND r.metadata->>'workItemId'=w.id::text))
        AND r.result_kind='improved_more_remains'
      WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
        AND w.result_contract_key=NEW.result_contract_key
        AND need.state='open'
        AND (
          EXISTS(
             SELECT 1 FROM atlas.households h
             JOIN atlas.principals p ON p.id=h.principal_id
             WHERE h.id=w.household_id AND p.status='active'
               AND p.user_id=auth.uid()
               AND p.person_id=atlas.current_person_id_v1()
          )
          OR EXISTS(
             SELECT 1 FROM atlas.work_allocations a
             WHERE a.work_item_id=w.id AND a.household_id=w.household_id
               AND a.state='active' AND a.allocation_role='responsible'
               AND (
                  a.assignee_canonical_person_id=atlas.current_person_id_v1()
                  OR EXISTS(
                    SELECT 1 FROM atlas.household_members hm
                    WHERE hm.id=a.assignee_household_member_id
                      AND hm.household_id=w.household_id AND hm.active
                      AND hm.user_id=auth.uid()
                      AND hm.person_id=atlas.current_person_id_v1()
                  )
               )
          )
        )
    ) THEN
  RAISE EXCEPTION 'Work Result needs real accepted Laundry step evidence.'
    USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.guard_household_work_acceptance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.household_work_actor_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL
   OR NEW.decision<>'accepted'
   OR NEW.accepted_by_domain<>'household_laundry_actual'
   OR NOT EXISTS(
     SELECT 1 FROM atlas.work_execution_results r
     WHERE r.id=NEW.execution_result_id
       AND r.household_id=NEW.household_id
       AND r.work_item_id=NEW.work_item_id
       AND r.result_kind='completed'
       AND r.result_contract_key IN ('household_laundry_begin_cycle_v1','household_laundry_begin_drying_v1','household_laundry_return_to_use_v1')
   ) THEN
   RAISE EXCEPTION 'Household acceptance requires the original physical Work Result.'
     USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.household_laundry_current_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_kernel atlas.household_kernel_instances%rowtype;
 v_condition text;v_observation uuid;v_need atlas.household_need_occurrences_v1%rowtype;
 v_work atlas.work_items%rowtype;v_allocation atlas.work_allocations%rowtype;
 v_last_completed_work_id uuid;v_last_completed_at timestamptz;
 v_rhythm atlas.household_rhythms%rowtype;
 v_rhythm_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
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
  -- The original Household Rhythm remains a separate decision, not a
  -- presumed side effect of calibrating the world kernel.
  SELECT * INTO v_rhythm FROM atlas.household_rhythms r
   WHERE r.household_id=v_household
     AND r.stable_key='kernel:household.laundry:general';
  IF v_rhythm.id IS NOT NULL THEN
   SELECT * INTO v_rhythm_decision
   FROM atlas.household_rhythm_explicit_decisions_v1 d
   WHERE d.household_id=v_household AND d.rhythm_id=v_rhythm.id
     AND d.instance_id=v_kernel.id
   ORDER BY d.decision_seq DESC LIMIT 1;
  END IF;
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
  'rhythmId',v_rhythm.id,
  'rhythmDecisionId',v_rhythm_decision.decision_id,
  'rhythmDecisionKind',v_rhythm_decision.decision_kind,
  'rhythmRenewAfterDays',v_rhythm_decision.renew_after_days,
  'rhythmCurrentlyEstablished',v_rhythm.active IS TRUE
    AND v_rhythm_decision.decision_kind='establish',
  'rhythmNextWindowStart',CASE WHEN v_rhythm.active
    AND v_rhythm_decision.decision_kind='establish'
    THEN v_rhythm.next_window_start ELSE NULL END,
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
 -- Do not let a later ready-for-wash report overwrite an open wet-load drying Need.
 PERFORM 1 FROM atlas.care_current_state c WHERE c.scope_kind='household' AND c.scope_id=v_household
   AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
   AND c.subject_id=p_kernel_instance_id::text FOR UPDATE;
 IF EXISTS(SELECT 1 FROM atlas.care_current_state c WHERE c.scope_kind='household' AND c.scope_id=v_household
    AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
    AND c.subject_id=p_kernel_instance_id::text AND c.condition_state IN ('washing','wet_ready_for_drying','drying','dry_ready_for_return'))
 AND NOT EXISTS(SELECT 1 FROM atlas.care_observation_events o
   WHERE o.source_key='household-laundry-observation:'||v_household::text||':'||p_action_id::text
     AND o.scope_id=v_household AND o.subject_id=p_kernel_instance_id::text AND o.note=btrim(p_observation)
     AND o.condition_state='ready_for_cycle') THEN
  RAISE EXCEPTION 'Current tracked Laundry load has not returned to use.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.household_need_occurrences_v1 n WHERE n.household_id=v_household
    AND n.instance_id=p_kernel_instance_id AND n.need_key in ('begin_drying','return_to_use') AND n.state='open') THEN
  RAISE EXCEPTION 'Current load needs its existing original Work first.' USING ERRCODE='23514'; END IF;
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
  -- Existing care_apply_observation_current_state_v1 is the single
  -- observation-to-state writer. A second unconditional update here could
  -- overwrite a newer physical observation made in another session.
  NULL;
 END IF;
 RETURN jsonb_build_object('ok',true,
    'contractVersion','household_laundry_observation_v1',
    'householdId',v_household,'instanceId',p_kernel_instance_id,
    'observationId',v_id,'conditionState','ready_for_cycle',
    'workCreated',false,'idempotent',NOT v_new);
END;
$function$;


-- Observed wash finished, with an explicit decision to carry (or not carry) the next actual Work.
create or replace function atlas.record_household_laundry_wash_finished_self_api_v1(
 p_work_item_id uuid,p_observation_id uuid,p_action_id uuid,p_self_carried boolean
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare h uuid; inst uuid; actor uuid; packet jsonb; obs uuid; n atlas.household_need_occurrences_v1%rowtype;
 w uuid; allocation uuid; prior atlas.care_observation_events%rowtype;
 at_time timestamptz:=clock_timestamp(); src text;
begin
 if p_work_item_id is null or p_observation_id is null or p_action_id is null or p_self_carried is null then
  raise exception 'Exact process and explicit carrier choice required.' using errcode='22023'; end if;
 h:=atlas.principal_current_household_id_v1(); actor:=atlas.require_household_governor_self_v1(h);
 select id into inst from atlas.household_kernel_instances where household_id=h and kernel_key='household.laundry' and state='active';
 if inst is null then raise exception 'Current Laundry unavailable.' using errcode='42501'; end if;
 -- Same current care row serializes expectation, wash-finished and new ready observations.
 perform 1 from atlas.care_current_state c where c.scope_kind='household' and c.scope_id=h
  and c.subject_domain='household' and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text for update;
 if not found then raise exception 'Current state unavailable.' using errcode='23514'; end if;
 src:='laundry-wash-finished:'||h::text||':'||p_action_id::text;
 select * into prior from atlas.care_observation_events where source_key=src;
 if prior.id is not null then
  if prior.scope_id is distinct from h or prior.subject_id is distinct from inst::text
   or prior.observed_by_user_id is distinct from auth.uid() or prior.condition_state<>'wet_ready_for_drying'
   or prior.metadata->>'priorObservationId' is distinct from p_observation_id::text
   or prior.metadata->>'washWorkId' is distinct from p_work_item_id::text
   or prior.metadata->>'selfCarried' is distinct from p_self_carried::text
  then raise exception 'Conflicting physical action.' using errcode='23505'; end if;
  select * into n from atlas.household_need_occurrences_v1 where household_id=h and instance_id=inst
    and source_action_id=p_action_id and opened_by_observation_id=prior.id and need_key='begin_drying';
  if n.current_work_item_id is null then raise exception 'Incomplete original receipt.' using errcode='23514'; end if;
  w:=n.current_work_item_id;obs:=prior.id;
  select a.id into allocation from atlas.work_allocations a where a.household_id=h and a.work_item_id=w
    and a.allocation_role='responsible' and a.state='active';
  return jsonb_build_object('ok',true,'contractVersion','household_laundry_wash_finished_v1',
    'householdId',h,'instanceId',inst,'observationId',obs,'priorObservationId',p_observation_id,
    'washWorkId',p_work_item_id,'needOccurrenceId',n.id,'workItemId',w,'allocationId',allocation,
    'workCreated',false,'idempotent',true,'conditionState','wet_ready_for_drying','clockAdmitted',false,'laundryCompletelyDone',false);
 end if;
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 if packet->>'processKind' is distinct from 'washing' or packet->>'state' not in ('needs_interval','waiting','due') or packet->>'observationId' is distinct from p_observation_id::text
  or packet->>'workItemId' is distinct from p_work_item_id::text
  or packet->>'instanceId' is distinct from inst::text
  or exists(select 1 from atlas.household_need_occurrences_v1 where household_id=h and instance_id=inst and state='open')
 then raise exception 'Original accepted wash no longer current.' using errcode='23514'; end if;
 -- A human can observe finish even before the predicted check time.
 insert into atlas.care_observation_events(subject_domain,subject_kind,subject_id,scope_kind,scope_id,observed_at,
 condition_state,disposition,observed_by_user_id,source_kind,source_key,note,inferred_from_clock,metadata)
 values('household','household_kernel_instance',inst::text,'household',h,at_time,
 'wet_ready_for_drying','intervene',auth.uid(),'household_laundry_wash_finished_observation',src,null,false,
 jsonb_build_object('priorObservationId',p_observation_id,'washWorkId',p_work_item_id,'washResultId',packet->>'processResultId',
  'selfCarried',p_self_carried,'actualPhysicalObservation',true))
 returning id into obs;
 update atlas.care_current_state c set next_reassess_at=null,metadata=c.metadata-'laundryReassessmentEvidenceId'
  where c.scope_kind='household' and c.scope_id=h and c.subject_domain='household' and c.subject_kind='household_kernel_instance'
   and c.subject_id=inst::text and c.last_observation_id=obs and c.condition_state='wet_ready_for_drying';
 if not found then raise exception 'Physical observation readback failed.' using errcode='23514'; end if;
 insert into atlas.household_need_occurrences_v1(household_id,instance_id,need_key,state,opened_by_observation_id,source_action_id)
 values(h,inst,'begin_drying','open',obs,p_action_id) returning * into n;
 insert into atlas.work_items(household_id,organization_id,source_object_type,source_object_id,work_state,title,instructions,stable_key,
 result_contract_key,created_by_user_id,metadata)
 values(h,null,'household_need_occurrence',n.id,'open','Start drying the laundry',
 'Place the wet laundry into its actual drying arrangement and begin drying. This does not establish that it is dry or returned to use.',
 'household:laundry:begin_drying:'||n.id::text,'household_laundry_begin_drying_v1',auth.uid(),
 jsonb_build_object('needOccurrenceId',n.id,'worldKernelKey','household.laundry','partiallyCompletable',true,'carrierEstablishedOnlyByExplicitDecision',true))
 returning id into w;
 update atlas.household_need_occurrences_v1 set current_work_item_id=w,updated_at=now() where id=n.id;
 insert into atlas.work_item_context_links(household_id,organization_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind,provenance,metadata)
 values(h,null,w,'household','kernel_instance',inst,'acts_on',jsonb_build_object('source','household_laundry_need','needOccurrenceId',n.id),'{}'::jsonb);
 if p_self_carried then
  insert into atlas.work_allocations(household_id,organization_id,work_item_id,allocation_role,state,assignee_canonical_person_id,
   establishment_basis_kind,establishment_basis,metadata)
  values(h,null,w,'responsible','active',actor,'household_explicit_carrier_v1',
   jsonb_build_object('householdId',h,'workItemId',w,'senderPersonId',actor,'decisionReason','Explicit carrier for observed wet Laundry','sourceActionId',p_action_id),'{}'::jsonb)
  returning id into allocation;
 end if;
 return jsonb_build_object('ok',true,'contractVersion','household_laundry_wash_finished_v1',
    'householdId',h,'instanceId',inst,'observationId',obs,'priorObservationId',p_observation_id,
    'washWorkId',p_work_item_id,'needOccurrenceId',n.id,'workItemId',w,'allocationId',allocation,
    'workCreated',true,'idempotent',false,'conditionState','wet_ready_for_drying','clockAdmitted',false,'laundryCompletelyDone',false);
end;
$body$;
revoke all on function atlas.record_household_laundry_wash_finished_self_api_v1(uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_wash_finished_self_api_v1(p_work_item_id uuid,p_observation_id uuid,p_action_id uuid,p_self_carried boolean)
returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_wash_finished_self_api_v1(p_work_item_id,p_observation_id,p_action_id,p_self_carried); $body$;
revoke all on function public.record_household_laundry_wash_finished_self_api_v1(uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_wash_finished_self_api_v1(uuid,uuid,uuid,boolean) to authenticated;


CREATE OR REPLACE FUNCTION atlas.record_household_laundry_drying_started_self_api_v1(
 p_work_item_id uuid,p_action_id uuid,p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_rhythm atlas.household_rhythms%rowtype;
 v_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_satisfaction uuid;v_interval integer;
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
    'acceptanceId',v_acceptance,'rhythmSatisfactionId',v_satisfaction,
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
   'rhythmSatisfactionId',v_satisfaction,
   'workCompleted',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;


revoke all on function atlas.record_household_laundry_drying_started_self_api_v1(uuid,uuid,text) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_drying_started_self_api_v1(p_work_item_id uuid,p_action_id uuid,p_note text default null)
returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_drying_started_self_api_v1(p_work_item_id,p_action_id,p_note); $body$;
revoke all on function public.record_household_laundry_drying_started_self_api_v1(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_drying_started_self_api_v1(uuid,uuid,text) to authenticated;


insert into atlas.work_result_contract_policies(contract_key,source_domain,acceptance_mode,active,description,metadata)
values('household_laundry_return_to_use_v1','household','domain_adapter',true,'Actual return of this observed dry load to use.',
jsonb_build_object('qualificationEvent','returned_to_use','physicalStepOnly',true,'noAutomaticRhythm',true))
on conflict(contract_key) do nothing;
do $policy$ begin
 if not exists(select 1 from atlas.work_result_contract_policies where contract_key='household_laundry_return_to_use_v1'
 and source_domain='household' and acceptance_mode='domain_adapter' and active
 and metadata->>'qualificationEvent'='returned_to_use') then raise exception 'Return policy conflict'; end if;
end $policy$;

CREATE OR REPLACE FUNCTION atlas.household_original_work_focus_self_api_v1(
 p_household_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_governor boolean:=false;
 v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_allocation atlas.work_allocations%rowtype;
 v_accepted atlas.work_result_acceptances%rowtype;
 v_result atlas.work_execution_results%rowtype;
BEGIN
 v_person:=atlas.household_work_actor_v1(p_household_id);
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND household_id=p_household_id
  AND organization_id IS NULL AND source_object_type='household_need_occurrence';
 IF v_work.id IS NULL THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 n
 WHERE n.id=v_work.source_object_id AND n.household_id=p_household_id
   AND n.current_work_item_id=v_work.id;
 IF v_need.id IS NULL THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT EXISTS(
  SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
  WHERE h.id=p_household_id AND p.status='active' AND p.user_id=auth.uid()
    AND p.person_id=v_person
 ) INTO v_governor;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.household_id=p_household_id AND a.work_item_id=v_work.id
  AND a.allocation_role='responsible' AND a.state='active'
 ORDER BY a.allocated_at DESC LIMIT 1;
 IF NOT v_governor AND (
   v_allocation.assignee_canonical_person_id=v_person OR EXISTS(
    SELECT 1 FROM atlas.household_members hm
    WHERE hm.id=v_allocation.assignee_household_member_id AND hm.active
     AND hm.household_id=p_household_id AND hm.user_id=auth.uid()
     AND hm.person_id=v_person)
 ) IS NOT TRUE THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.household_id=p_household_id AND r.work_item_id=v_work.id
 ORDER BY r.reported_at DESC,r.id DESC LIMIT 1;
 IF v_result.id IS NOT NULL THEN
  SELECT * INTO v_accepted FROM atlas.work_result_acceptances a
   WHERE a.execution_result_id=v_result.id
    AND a.household_id=p_household_id AND a.decision='accepted';
 END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','household_original_work_focus_v1',
  'householdId',p_household_id,'workItemId',v_work.id,
  'subjectDomain','household','subjectKind','kernel_instance',
  'subjectId',v_need.instance_id,'needOccurrenceId',v_need.id,
  'needState',v_need.state,
  'title',v_work.title,'instructions',v_work.instructions,
  'workState',v_work.work_state,
  'allocationId',v_allocation.id,
  'assignedCanonicalPersonId',v_allocation.assignee_canonical_person_id,
  'resultContractKey',v_work.result_contract_key,
  'latestReportKind',v_result.result_kind,
  'acceptedResultKind',CASE WHEN v_accepted.id IS NOT NULL
   THEN v_result.result_kind ELSE NULL END,
  'canReportPhysicalActual',v_work.work_state='open' AND v_need.state='open'
   AND (v_governor OR v_allocation.id IS NOT NULL),
  'isSignedHouseholdPerson',true,'isCompany',false
 );
END;
$function$;

create or replace function atlas.record_household_laundry_still_running_self_api_v1(
 p_work_item_id uuid,p_observation_id uuid,p_elapsed_minutes integer,p_action_id uuid
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare h uuid; inst uuid; packet jsonb; prior atlas.care_observation_events%rowtype; obs uuid; src text;
 at_time timestamptz:=statement_timestamp(); state_kind text;
begin
 if p_work_item_id is null or p_observation_id is null or p_action_id is null or
  p_elapsed_minutes is null or p_elapsed_minutes not between 1 and 1440 then
  raise exception 'Exact observation and next check interval required.' using errcode='22023'; end if;
 h:=atlas.principal_current_household_id_v1(); perform atlas.require_household_governor_self_v1(h);
 select id into inst from atlas.household_kernel_instances where household_id=h and kernel_key='household.laundry' and state='active';
 perform 1 from atlas.care_current_state c where c.scope_kind='household' and c.scope_id=h
 and c.subject_domain='household' and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text for update;
 if not found then raise exception 'Current process unavailable.' using errcode='23514'; end if;
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 src:='laundry-still-running:'||h::text||':'||p_action_id::text;
 select * into prior from atlas.care_observation_events where source_key=src;
 if prior.id is not null then
  if prior.scope_id is distinct from h or prior.subject_id is distinct from inst::text
    or prior.observed_by_user_id is distinct from auth.uid()
    or prior.metadata->>'priorObservationId' is distinct from p_observation_id::text
    or prior.metadata->>'workItemId' is distinct from p_work_item_id::text
    or prior.metadata->>'elapsedMinutes' is distinct from p_elapsed_minutes::text
    or packet->>'observationId' is distinct from prior.id::text
    or packet->>'workItemId' is distinct from p_work_item_id::text
  then raise exception 'Stale or conflicting observation action.' using errcode='23505'; end if;
  return atlas.record_household_laundry_reassessment_self_api_v1(p_work_item_id,prior.id,p_elapsed_minutes,p_action_id);
 end if;
 if packet->>'state' not in ('needs_interval','waiting','due') or packet->>'workItemId' is distinct from p_work_item_id::text
 or packet->>'observationId' is distinct from p_observation_id::text then
  raise exception 'Original running process no longer current.' using errcode='23514'; end if;
 state_kind:=packet->>'processKind';
 insert into atlas.care_observation_events(subject_domain,subject_kind,subject_id,scope_kind,scope_id,observed_at,
 condition_state,disposition,observed_by_user_id,source_kind,source_key,inferred_from_clock,metadata)
 values('household','household_kernel_instance',inst::text,'household',h,at_time,state_kind,'observe',auth.uid(),
 'household_laundry_still_running_observation',src,false,
 jsonb_build_object('careResultId',packet->>'processResultId','priorObservationId',p_observation_id,
 'workItemId',p_work_item_id,'elapsedMinutes',p_elapsed_minutes,'actualPhysicalObservation',true))
 returning id into obs;
 update atlas.care_current_state c set next_reassess_at=null,metadata=c.metadata-'laundryReassessmentEvidenceId'
 where c.scope_kind='household' and c.scope_id=h and c.subject_domain='household'
 and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text and c.last_observation_id=obs;
 if not found then raise exception 'New actual observation was not retained.' using errcode='23514'; end if;
 return atlas.record_household_laundry_reassessment_self_api_v1(p_work_item_id,obs,p_elapsed_minutes,p_action_id);
end;
$body$;
revoke all on function atlas.record_household_laundry_still_running_self_api_v1(uuid,uuid,integer,uuid) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_still_running_self_api_v1(p_work_item_id uuid,p_observation_id uuid,p_elapsed_minutes integer,p_action_id uuid)
returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_still_running_self_api_v1(p_work_item_id,p_observation_id,p_elapsed_minutes,p_action_id); $body$;
revoke all on function public.record_household_laundry_still_running_self_api_v1(uuid,uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_still_running_self_api_v1(uuid,uuid,integer,uuid) to authenticated;


create or replace function atlas.record_household_laundry_dry_finished_self_api_v1(
 p_work_item_id uuid,p_observation_id uuid,p_action_id uuid,p_self_carried boolean
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare h uuid; inst uuid; actor uuid; packet jsonb; obs uuid; n atlas.household_need_occurrences_v1%rowtype;
 w uuid; allocation uuid; prior atlas.care_observation_events%rowtype;
 at_time timestamptz:=clock_timestamp(); src text;
begin
 if p_work_item_id is null or p_observation_id is null or p_action_id is null or p_self_carried is null then
  raise exception 'Exact process and explicit carrier choice required.' using errcode='22023'; end if;
 h:=atlas.principal_current_household_id_v1(); actor:=atlas.require_household_governor_self_v1(h);
 select id into inst from atlas.household_kernel_instances where household_id=h and kernel_key='household.laundry' and state='active';
 if inst is null then raise exception 'Current Laundry unavailable.' using errcode='42501'; end if;
 -- Same current care row serializes expectation, wash-finished and new ready observations.
 perform 1 from atlas.care_current_state c where c.scope_kind='household' and c.scope_id=h
  and c.subject_domain='household' and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text for update;
 if not found then raise exception 'Current state unavailable.' using errcode='23514'; end if;
 src:='laundry-dry-finished:'||h::text||':'||p_action_id::text;
 select * into prior from atlas.care_observation_events where source_key=src;
 if prior.id is not null then
  if prior.scope_id is distinct from h or prior.subject_id is distinct from inst::text
   or prior.observed_by_user_id is distinct from auth.uid() or prior.condition_state<>'dry_ready_for_return'
   or prior.metadata->>'priorObservationId' is distinct from p_observation_id::text
   or prior.metadata->>'dryWorkId' is distinct from p_work_item_id::text
   or prior.metadata->>'selfCarried' is distinct from p_self_carried::text
  then raise exception 'Conflicting physical action.' using errcode='23505'; end if;
  select * into n from atlas.household_need_occurrences_v1 where household_id=h and instance_id=inst
    and source_action_id=p_action_id and opened_by_observation_id=prior.id and need_key='return_to_use';
  if n.current_work_item_id is null then raise exception 'Incomplete original receipt.' using errcode='23514'; end if;
  w:=n.current_work_item_id;obs:=prior.id;
  select a.id into allocation from atlas.work_allocations a where a.household_id=h and a.work_item_id=w
    and a.allocation_role='responsible' and a.state='active';
  return jsonb_build_object('ok',true,'contractVersion','household_laundry_dry_finished_v1',
    'householdId',h,'instanceId',inst,'observationId',obs,'priorObservationId',p_observation_id,
    'dryWorkId',p_work_item_id,'needOccurrenceId',n.id,'workItemId',w,'allocationId',allocation,
    'workCreated',false,'idempotent',true,'conditionState','dry_ready_for_return','clockAdmitted',false,'laundryCompletelyDone',false);
 end if;
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 if packet->>'processKind' is distinct from 'drying' or packet->>'state' not in ('needs_interval','waiting','due') or packet->>'observationId' is distinct from p_observation_id::text
  or packet->>'workItemId' is distinct from p_work_item_id::text
  or packet->>'instanceId' is distinct from inst::text
  or exists(select 1 from atlas.household_need_occurrences_v1 where household_id=h and instance_id=inst and state='open')
 then raise exception 'Original accepted drying no longer current.' using errcode='23514'; end if;
 -- A human can observe finish even before the predicted check time.
 insert into atlas.care_observation_events(subject_domain,subject_kind,subject_id,scope_kind,scope_id,observed_at,
 condition_state,disposition,observed_by_user_id,source_kind,source_key,note,inferred_from_clock,metadata)
 values('household','household_kernel_instance',inst::text,'household',h,at_time,
 'dry_ready_for_return','intervene',auth.uid(),'household_laundry_dry_finished_observation',src,null,false,
 jsonb_build_object('priorObservationId',p_observation_id,'dryWorkId',p_work_item_id,'dryResultId',packet->>'processResultId',
  'selfCarried',p_self_carried,'actualPhysicalObservation',true))
 returning id into obs;
 update atlas.care_current_state c set next_reassess_at=null,metadata=c.metadata-'laundryReassessmentEvidenceId'
  where c.scope_kind='household' and c.scope_id=h and c.subject_domain='household' and c.subject_kind='household_kernel_instance'
   and c.subject_id=inst::text and c.last_observation_id=obs and c.condition_state='dry_ready_for_return';
 if not found then raise exception 'Physical observation readback failed.' using errcode='23514'; end if;
 insert into atlas.household_need_occurrences_v1(household_id,instance_id,need_key,state,opened_by_observation_id,source_action_id)
 values(h,inst,'return_to_use','open',obs,p_action_id) returning * into n;
 insert into atlas.work_items(household_id,organization_id,source_object_type,source_object_id,work_state,title,instructions,stable_key,
 result_contract_key,created_by_user_id,metadata)
 values(h,null,'household_need_occurrence',n.id,'open','Return laundry to use',
 'Return this observed dry load to its usable place or condition. Do not claim other loads are finished.',
 'household:laundry:return_to_use:'||n.id::text,'household_laundry_return_to_use_v1',auth.uid(),
 jsonb_build_object('needOccurrenceId',n.id,'worldKernelKey','household.laundry','partiallyCompletable',true,'carrierEstablishedOnlyByExplicitDecision',true))
 returning id into w;
 update atlas.household_need_occurrences_v1 set current_work_item_id=w,updated_at=now() where id=n.id;
 insert into atlas.work_item_context_links(household_id,organization_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind,provenance,metadata)
 values(h,null,w,'household','kernel_instance',inst,'acts_on',jsonb_build_object('source','household_laundry_need','needOccurrenceId',n.id),'{}'::jsonb);
 if p_self_carried then
  insert into atlas.work_allocations(household_id,organization_id,work_item_id,allocation_role,state,assignee_canonical_person_id,
   establishment_basis_kind,establishment_basis,metadata)
  values(h,null,w,'responsible','active',actor,'household_explicit_carrier_v1',
   jsonb_build_object('householdId',h,'workItemId',w,'senderPersonId',actor,'decisionReason','Explicit carrier for observed dry Laundry','sourceActionId',p_action_id),'{}'::jsonb)
  returning id into allocation;
 end if;
 return jsonb_build_object('ok',true,'contractVersion','household_laundry_dry_finished_v1',
    'householdId',h,'instanceId',inst,'observationId',obs,'priorObservationId',p_observation_id,
    'dryWorkId',p_work_item_id,'needOccurrenceId',n.id,'workItemId',w,'allocationId',allocation,
    'workCreated',true,'idempotent',false,'conditionState','dry_ready_for_return','clockAdmitted',false,'laundryCompletelyDone',false);
end;
$body$;

revoke all on function atlas.record_household_laundry_dry_finished_self_api_v1(uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_dry_finished_self_api_v1(p_work_item_id uuid,p_observation_id uuid,p_action_id uuid,p_self_carried boolean)
returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_dry_finished_self_api_v1(p_work_item_id,p_observation_id,p_action_id,p_self_carried); $body$;
revoke all on function public.record_household_laundry_dry_finished_self_api_v1(uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_dry_finished_self_api_v1(uuid,uuid,uuid,boolean) to authenticated;

CREATE OR REPLACE FUNCTION atlas.record_household_laundry_returned_to_use_self_api_v1(
 p_work_item_id uuid,p_action_id uuid,p_note text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_person uuid;v_source_key text;v_result uuid;v_observation uuid;v_work_result uuid;
 v_acceptance uuid;v_existing boolean:=false;v_before text;
 v_rhythm atlas.household_rhythms%rowtype;
 v_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_satisfaction uuid;v_interval integer;
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
    'acceptanceId',v_acceptance,'rhythmSatisfactionId',v_satisfaction,
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
   'rhythmSatisfactionId',v_satisfaction,
   'workCompleted',true,'loadReturnedToUse',true,'laundryCompletelyDone',false,
   'idempotent',false);
END;
$function$;

revoke all on function atlas.record_household_laundry_returned_to_use_self_api_v1(uuid,uuid,text) from public,anon,authenticated,service_role;
create or replace function public.record_household_laundry_returned_to_use_self_api_v1(p_work_item_id uuid,p_action_id uuid,p_note text default null)
returns jsonb language sql security definer set search_path to ''
as $body$ select atlas.record_household_laundry_returned_to_use_self_api_v1(p_work_item_id,p_action_id,p_note); $body$;
revoke all on function public.record_household_laundry_returned_to_use_self_api_v1(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.record_household_laundry_returned_to_use_self_api_v1(uuid,uuid,text) to authenticated;
commit;
