-- Held source only. One original Care/Need/Work chain; no new schedule or Work issuer.
begin;
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
 if p->>'rhythmDecisionKind'='withdraw' then return empty_packet; end if;
 if (p->>'rhythmCurrentlyEstablished')::boolean is true and p->>'rhythmDecisionKind'='establish'
    and p->>'rhythmDecisionId' is not null
    and (p->>'rhythmRenewAfterDays')::integer between 1 and 365 then
   days:=(p->>'rhythmRenewAfterDays')::integer;
   anchor_at:=case when obs.source_kind='household_laundry_renewal_not_ready'
     then greatest(started,obs.observed_at) else started end;
   expected_at:=anchor_at+make_interval(secs=>days*86400);
   status:=case when expected_at<=as_of then 'due' else 'waiting' end;
 elsif p->>'rhythmDecisionId' is null and cfg->>'usualPattern'='little_most_days' then
   days:=1; status:='proposal';
 else return empty_packet; end if;
 return empty_packet||jsonb_build_object('state',status,'householdId',h,'instanceId',inst,
    'observationId',obs.id,'closedLoadObservationId',closed_obs.id,'washStartedAt',started,
    'anchorAt',anchor_at,'expectedCheckAt',expected_at,'renewAfterDays',days,
    'rhythmId',case when status='proposal' then null else p->>'rhythmId' end,
    'decisionId',case when status='proposal' then null else p->>'rhythmDecisionId' end,
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
 perform pg_advisory_xact_lock(hashtextextended('atlas.household.laundry.explicit_rhythm:'||h::text,0));
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
      or prior.metadata->>'rhythmDecisionId' is distinct from p_decision_id::text
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
  jsonb_build_object('previousObservationId',p_observation_id,'rhythmDecisionId',p_decision_id,
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
commit;
