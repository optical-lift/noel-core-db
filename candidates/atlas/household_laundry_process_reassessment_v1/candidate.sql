-- Process expectation is not physical evidence of completion, Work, or Clock admission.
-- Reuse the existing accepted Work result, immutable evidence and current care state.
begin;
create or replace function atlas.household_laundry_reassessment_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare
 h uuid; inst uuid; c atlas.care_current_state%rowtype;
 w uuid; result_id uuid; started_at timestamptz; ev atlas.evidence_records%rowtype;
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
 if c.condition_state is distinct from 'washing' then
  return jsonb_build_object('ok',true,'contractVersion','household_laundry_reassessment_v1',
    'state','not_applicable','asOf',as_of,'workCreated',false,'clockAdmitted',false,'physicalCompletionInferred',false);
 end if;
 -- A single current physical state, with the original accepted wash-start receipt.
 select wi.id,cr.id,cr.occurred_at into w,result_id,started_at
  from atlas.care_observation_events o
  join atlas.care_result_events cr on cr.id::text=o.metadata->>'careResultId'
   and cr.scope_kind='household' and cr.scope_id=h and cr.subject_domain='household'
   and cr.subject_kind='household_kernel_instance' and cr.subject_id=inst::text
   and cr.source_kind='household_laundry_physical_actual' and cr.condition_after='washing'
   and cr.metadata->>'completedStep'='wash_started'
  join atlas.work_items wi on wi.id::text=cr.metadata->>'workItemId' and wi.household_id=h
   and wi.organization_id is null and wi.work_state='completed'
   and wi.result_contract_key='household_laundry_begin_cycle_v1'
  join atlas.household_need_occurrences_v1 n on n.id=wi.source_object_id and n.household_id=h
   and n.instance_id=inst and n.current_work_item_id=wi.id and n.state='satisfied'
   and n.satisfied_by_care_result_id=cr.id
  where o.id=c.last_observation_id and o.scope_kind='household' and o.scope_id=h
   and o.subject_domain='household' and o.subject_kind='household_kernel_instance' and o.subject_id=inst::text
   and o.source_kind='household_laundry_actual_state' and o.condition_state='washing'
   and o.inferred_from_clock=false
   and exists(select 1 from atlas.work_execution_results wr
      join atlas.work_result_acceptances wa on wa.execution_result_id=wr.id and wa.work_item_id=wi.id
       and wa.household_id=h and wa.decision='accepted'
      where wr.household_id=h and wr.work_item_id=wi.id and wr.result_kind='completed'
       and wr.result_contract_key='household_laundry_begin_cycle_v1' and wr.payload->>'careResultId'=cr.id::text);
 if w is null then raise exception 'Current process lacks accepted original physical result.' using errcode='23514'; end if;
 select * into ev from atlas.evidence_records e where e.id::text=c.metadata->>'laundryReassessmentEvidenceId'
    and e.scope_kind='household' and e.scope_id=h and e.subject_domain='household'
    and e.subject_kind='household_kernel_instance' and e.subject_id=inst::text
    and e.evidence_kind='expected_process_reassessment' and e.source_kind='household_laundry_explicit_reassessment'
    and e.value->>'observationId'=c.last_observation_id::text
    and e.value->>'washResultId'=result_id::text and e.value->>'workItemId'=w::text;
 if ev.id is null then
  status:='needs_interval';
 else
  expected:=ev.effective_until;
  if expected is null or expected is distinct from c.next_reassess_at
    or jsonb_typeof(ev.value->'elapsedMinutes')<>'number'
    or (ev.value->>'elapsedMinutes')::integer not between 1 and 1440
    or expected is distinct from started_at+make_interval(mins=>(ev.value->>'elapsedMinutes')::integer)
  then raise exception 'Expected reassessment source requires reconciliation.' using errcode='23514'; end if;
  status:=case when expected<=as_of then 'due' else 'waiting' end;
 end if;
 return jsonb_build_object('ok',true,'contractVersion','household_laundry_reassessment_v1',
   'state',status,'asOf',as_of,'householdId',h,'instanceId',inst,'observationId',c.last_observation_id,
   'workItemId',w,'washResultId',result_id,'startedAt',started_at,'evidenceId',ev.id,
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
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 if packet->>'state' not in ('needs_interval','waiting','due')
  or packet->>'workItemId' is distinct from p_work_item_id::text
  or packet->>'observationId' is distinct from p_observation_id::text
 then raise exception 'Current original washing observation required.' using errcode='23514'; end if;
 h:=(packet->>'householdId')::uuid; inst:=(packet->>'instanceId')::uuid;
 perform atlas.require_household_governor_self_v1(h);
 perform 1 from atlas.care_current_state c where c.scope_kind='household' and c.scope_id=h
   and c.subject_domain='household' and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text
   and c.condition_state='washing' and c.last_observation_id=p_observation_id for update;
 if not found then raise exception 'Current physical state changed.' using errcode='23514'; end if;
 -- Re-read after locking exact state, including another session's explicit expectation.
 packet:=atlas.household_laundry_reassessment_self_api_v1();
 if packet->>'workItemId' is distinct from p_work_item_id::text
  or packet->>'observationId' is distinct from p_observation_id::text
 then raise exception 'Process changed.' using errcode='23514'; end if;
 result_id:=(packet->>'washResultId')::uuid; started_at:=(packet->>'startedAt')::timestamptz;
 expected:=started_at+make_interval(mins=>p_elapsed_minutes);
 src:='laundry-reassessment:'||p_action_id::text;
 select * into ev from atlas.evidence_records e where e.scope_kind='household' and e.scope_id=h
    and e.source_kind='household_laundry_explicit_reassessment' and e.source_key=src;
 if ev.id is not null then
  if ev.subject_id is distinct from inst::text or ev.value->>'observationId' is distinct from p_observation_id::text
    or ev.value->>'workItemId' is distinct from p_work_item_id::text
    or ev.value->>'washResultId' is distinct from result_id::text
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
   jsonb_build_object('workItemId',p_work_item_id,'observationId',p_observation_id,'washResultId',result_id,
      'elapsedMinutes',p_elapsed_minutes,'predictionOnly',true),
   statement_timestamp(),started_at,expected,
   jsonb_build_object('basis','explicit_governor_expected_elapsed_time','activeEffortInferred',false),'{}'::jsonb)
 returning * into ev;
 update atlas.care_current_state c set next_reassess_at=expected,
   metadata=c.metadata||jsonb_build_object('laundryReassessmentEvidenceId',ev.id)
 where c.scope_kind='household' and c.scope_id=h and c.subject_domain='household'
   and c.subject_kind='household_kernel_instance' and c.subject_id=inst::text
   and c.last_observation_id=p_observation_id and c.condition_state='washing';
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
commit;
