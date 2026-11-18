-- Held subsequent placement and plan closure only.
-- Depends on the read-only source in #2906, not a second reader migration.
begin;
do $prerequisite$
begin
 if to_regprocedure('public.household_person_my_work_self_api_v1(integer,uuid)') is null
 or to_regprocedure('atlas.household_person_my_work_self_api_v1(integer,uuid)') is null then
 raise exception 'Native Household Person Work read source must be released first'; end if;
end;
$prerequisite$;
-- Same-result terminal plan closure. Preserve the existing governor-only
-- guard for every nonterminal plan mutation. No new completion authority.
create or replace function atlas.guard_household_work_plan_v1()
returns trigger language plpgsql security definer set search_path to ''
as $body$
begin
 if NEW.household_id is null then return NEW; end if;
 if TG_OP='UPDATE' then
   if OLD.plan_state in ('active','needs_replan') and NEW.plan_state='completed'
     and (to_jsonb(NEW)-array['plan_state','updated_at']) =
         (to_jsonb(OLD)-array['plan_state','updated_at']) then
     perform atlas.household_work_actor_v1(NEW.household_id);
     if not exists(
       select 1 from atlas.work_items w
       join atlas.work_allocations al on al.id=NEW.responsible_allocation_id
         and al.work_item_id=w.id and al.household_id=w.household_id
         and al.allocation_role='responsible'
       join atlas.household_need_occurrences_v1 n on n.id=w.source_object_id
         and n.household_id=w.household_id and n.current_work_item_id=w.id
       join atlas.work_execution_results rr on rr.work_item_id=w.id and rr.household_id=w.household_id
       join atlas.work_result_acceptances aa on aa.execution_result_id=rr.id
         and aa.work_item_id=w.id and aa.household_id=w.household_id
       join atlas.care_result_events c on c.id::text=rr.payload->>'careResultId'
         and c.scope_id=w.household_id and c.scope_kind='household'
         and c.subject_id=n.instance_id::text
       where w.id=NEW.work_item_id and w.household_id=NEW.household_id
         and w.organization_id is null and w.work_state='completed'
         and w.result_contract_key='household_laundry_begin_cycle_v1'
         and rr.result_kind='completed' and rr.result_contract_key=w.result_contract_key
         and rr.reported_by_user_id=auth.uid() and rr.payload->>'step'='wash_started'
         and aa.decision='accepted' and aa.acceptance_kind='source_qualified_physical_actual'
         and aa.accepted_by_domain='household_laundry_actual'
         and c.source_kind='household_laundry_physical_actual' and c.condition_after='washing'
         and c.actor_user_id=auth.uid()
     ) then raise exception 'Terminal Household plan requires exact accepted physical Actual.'
       using errcode='23514'; end if;
     return NEW;
   end if;
 end if;
 perform atlas.require_household_governor_self_v1(NEW.household_id);
 if NEW.organization_id is not null or
   not exists(
     select 1 from atlas.work_items w
     join atlas.work_allocations a on a.work_item_id=w.id
       and a.household_id=w.household_id and a.id=NEW.responsible_allocation_id
     where w.id=NEW.work_item_id and w.household_id=NEW.household_id
       and w.work_state='open' and a.state='active'
       and a.allocation_role='responsible'
       and a.assignee_membership_id is null
       and NEW.assignee_membership_id is null
   ) then
    raise exception 'Household Work plan requires its own active original allocation.'
      using errcode='23514';
 end if;
 -- No completed-state shortcut through the normal planning branch.
 if NEW.plan_state='completed' then
   raise exception 'Plan completion requires accepted original Actual.' using errcode='23514';
 end if;
 return NEW;
end;
$body$;
revoke all on function atlas.guard_household_work_plan_v1() from public,anon,authenticated,service_role;

create or replace function atlas.complete_household_original_work_plan_v1()
returns trigger language plpgsql security definer set search_path to ''
as $body$
declare v_plan atlas.work_execution_plans%rowtype; v_result uuid; v_acceptance uuid;
begin
 if NEW.household_id is null or NEW.organization_id is not null
    or NEW.result_contract_key is distinct from 'household_laundry_begin_cycle_v1' then
   return NEW;
 end if;
 select * into v_plan from atlas.work_execution_plans
   where household_id=NEW.household_id and work_item_id=NEW.id
     and plan_state in ('active','needs_replan') for update;
 if v_plan.id is null then return NEW; end if;
 select rr.id,aa.id into strict v_result,v_acceptance
 from atlas.work_execution_results rr
 join atlas.work_result_acceptances aa on aa.execution_result_id=rr.id
   and aa.household_id=rr.household_id and aa.work_item_id=rr.work_item_id
 where rr.household_id=NEW.household_id and rr.work_item_id=NEW.id
   and rr.result_contract_key=NEW.result_contract_key and rr.result_kind='completed'
   and rr.reported_by_user_id=auth.uid()
   and aa.decision='accepted' and aa.acceptance_kind='source_qualified_physical_actual'
   and aa.accepted_by_domain='household_laundry_actual';
 update atlas.work_execution_plans set plan_state='completed',updated_at=now()
 where id=v_plan.id;
 insert into atlas.work_execution_plan_events(
   household_id,work_item_id,plan_id,event_kind,
   from_planned_service_date,to_planned_service_date,
   from_exposure_service_date,to_exposure_service_date,reason,metadata)
 values(NEW.household_id,NEW.id,v_plan.id,'completed',
   v_plan.planned_service_date,v_plan.planned_service_date,
   v_plan.exposure_service_date,v_plan.exposure_service_date,
   'Original Household Work physically completed.',
   jsonb_build_object('workResultId',v_result,'acceptanceId',v_acceptance,
     'completedAt',NEW.completed_at,'wholeLaundryDone',false));
 return NEW;
end;
$body$;
revoke all on function atlas.complete_household_original_work_plan_v1() from public,anon,authenticated,service_role;
create trigger work_items_complete_household_original_plan_v1
 after update of work_state on atlas.work_items for each row
 when (NEW.household_id is not null and OLD.work_state='open' and NEW.work_state='completed')
 execute function atlas.complete_household_original_work_plan_v1();

-- Bounded first placement proof: Household governor carrying their own
-- original Laundry Need, using existing provisional fit and explicit consent.
-- This establishes a date, never a clock slot or an automatic recurring Work.
create or replace function atlas.place_household_laundry_original_work_self_api_v1(
 p_work_item_id uuid,p_service_date date,p_action_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare
 v_work atlas.work_items%rowtype; v_allocation atlas.work_allocations%rowtype;
 v_old atlas.work_execution_plans%rowtype; v_plan atlas.work_execution_plans%rowtype;
 v_prior atlas.work_execution_plan_events%rowtype;
 v_person uuid; v_instance uuid; v_effort text; v_fit jsonb;
 v_reason text:=nullif(btrim(p_reason),''); v_kind text;
begin
 if p_work_item_id is null or p_service_date is null or p_action_id is null
   or v_reason is null or length(v_reason) not between 12 and 1200 then
   raise exception 'Exact Work, date, action and meaningful confirmation reason required.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('household-laundry-work:'||p_work_item_id::text,0));
 select * into v_work from atlas.work_items where id=p_work_item_id for update;
 if v_work.id is null or v_work.household_id is null or v_work.organization_id is not null
   or v_work.source_object_type is distinct from 'household_need_occurrence'
   or v_work.result_contract_key is distinct from 'household_laundry_begin_cycle_v1' then
   raise exception 'Original Household Laundry Work unavailable.' using errcode='42501';
 end if;
 v_person:=atlas.require_household_governor_self_v1(v_work.household_id);
 -- Serialize competing placements for this self-carrier within this command.
 perform pg_advisory_xact_lock(hashtextextended('household-person-placement:'||v_person::text,0));
 select * into v_prior from atlas.work_execution_plan_events e
 where e.household_id=v_work.household_id and e.work_item_id=v_work.id
   and e.metadata->>'sourceActionId'=p_action_id::text;
 if v_prior.id is not null then
   if v_prior.to_planned_service_date is distinct from p_service_date
      or v_prior.reason is distinct from v_reason
      or v_prior.metadata->>'actorPersonId' is distinct from v_person::text then
     raise exception 'Placement action cannot change meaning.' using errcode='23514';
   end if;
   select * into v_plan from atlas.work_execution_plans where id=v_prior.plan_id
     and household_id=v_work.household_id and work_item_id=v_work.id;
   if v_plan.id is null then raise exception 'Original plan receipt missing.' using errcode='23514'; end if;
   return jsonb_build_object('ok',true,'contractVersion','household_laundry_original_plan_v1',
     'workItemId',v_work.id,'householdId',v_work.household_id,'planId',v_plan.id,
     'eventId',v_prior.id,'planState',v_plan.plan_state,'workOn',v_plan.planned_service_date,
     'exposureDate',v_plan.exposure_service_date,'idempotent',true,'clockAdmitted',false,'newWorkCreated',false);
 end if;
 if v_work.work_state is distinct from 'open' then
   raise exception 'Open original Work required.' using errcode='23514';
 end if;
 select * into strict v_allocation from atlas.work_allocations a
 where a.household_id=v_work.household_id and a.work_item_id=v_work.id
   and a.organization_id is null and a.allocation_role='responsible' and a.state='active';
 if v_allocation.assignee_canonical_person_id is distinct from v_person
   or v_allocation.assignee_household_member_id is not null
   or v_allocation.establishment_basis_kind is distinct from 'household_explicit_carrier_v1' then
   raise exception 'First placement proof requires the governor as explicit self-carrier.' using errcode='42501';
 end if;
 select k.id,k.configuration->>'expectedMinutes' into v_instance,v_effort
 from atlas.household_need_occurrences_v1 n
 join atlas.household_kernel_instances k on k.id=n.instance_id and k.household_id=n.household_id
 join atlas.care_current_state c on c.scope_kind='household' and c.scope_id=n.household_id
   and c.subject_domain='household' and c.subject_kind='household_kernel_instance'
   and c.subject_id=k.id::text and c.condition_state='ready_for_cycle'
 where n.id=v_work.source_object_id and n.household_id=v_work.household_id
   and n.current_work_item_id=v_work.id and n.state='open' and k.state='active'
   and k.kernel_key='household.laundry';
 if v_instance is null or v_effort is null or v_effort !~ '^[0-9]{1,3}$' then
   raise exception 'Confirmed current Need and accepted estimate required.' using errcode='23514';
 end if;
 if v_effort::integer not between 1 and 600 then
   raise exception 'Invalid calibrated effort.' using errcode='23514';
 end if;
 v_fit:=atlas.personal_week_work_fit_preview_self_api_v1('household.laundry',p_service_date,null,v_effort::integer);
 if v_fit->>'state' is distinct from 'provisional_ranked'
   or v_fit#>>'{context,householdId}' is distinct from v_work.household_id::text
   or v_fit#>>'{context,personEntityId}' is distinct from v_person::text
   or not (
     coalesce(v_fit#>>'{recommendation,localDate}'=p_service_date::text,false)
     or exists(select 1 from jsonb_array_elements(coalesce(v_fit->'alternatives','[]'::jsonb)) x
       where x->>'localDate'=p_service_date::text)
   ) then raise exception 'No current source-backed candidate for this date.' using errcode='23514'; end if;
 -- Unknown workload is not free time. Do not silently stack another
 -- original Work date over already dated responsibility in this first slice.
 if exists(select 1 from atlas.work_execution_plans ep
   join atlas.work_allocations a on a.id=ep.responsible_allocation_id
     and a.work_item_id=ep.work_item_id
   where a.assignee_canonical_person_id=v_person and a.state='active'
     and ep.plan_state in ('active','needs_replan') and ep.work_item_id<>v_work.id
     and (ep.exposure_service_date=p_service_date or ep.planned_service_date=p_service_date))
 or exists(select 1 from atlas.work_time_contracts t where t.work_item_id=v_work.id
   and t.household_id=v_work.household_id and t.contract_state='active'
   and t.due_on_date is not null and t.due_on_date<p_service_date) then
   raise exception 'Other original Work or deadline needs explicit reconciliation.' using errcode='23514';
 end if;
 select * into v_old from atlas.work_execution_plans where work_item_id=v_work.id
   and household_id=v_work.household_id and plan_state in ('active','needs_replan') for update;
 if v_old.id is not null and v_old.responsible_allocation_id<>v_allocation.id then
   raise exception 'Existing plan belongs to different responsibility.' using errcode='23514';
 end if;
 if v_old.id is null then
   insert into atlas.work_execution_plans(household_id,work_item_id,responsible_allocation_id,
      plan_state,first_planned_service_date,planned_service_date,exposure_service_date,plan_reason,metadata)
   values(v_work.household_id,v_work.id,v_allocation.id,'active',p_service_date,p_service_date,p_service_date,
      v_reason,jsonb_build_object('source','household_laundry_original_plan_v1'))
   returning * into v_plan;
   v_kind:='planned';
 else
   update atlas.work_execution_plans set plan_state='active',planned_service_date=p_service_date,
      exposure_service_date=p_service_date,plan_reason=v_reason,rollover_count=0,updated_at=now()
   where id=v_old.id returning * into v_plan;
   v_kind:=case when v_old.planned_service_date is distinct from p_service_date then 'rescheduled' else 'planned' end;
 end if;
 insert into atlas.work_execution_plan_events(household_id,work_item_id,plan_id,event_kind,
   from_planned_service_date,to_planned_service_date,from_exposure_service_date,to_exposure_service_date,reason,metadata)
 values(v_work.household_id,v_work.id,v_plan.id,v_kind,v_old.planned_service_date,p_service_date,
   v_old.exposure_service_date,p_service_date,v_reason,jsonb_build_object(
   'source','household_laundry_original_plan_v1','actorPersonId',v_person,'sourceActionId',p_action_id,
   'estimatedMinutes',v_effort::integer,'fitState',v_fit->>'state','externalCoverageComplete',false))
 returning * into v_prior;
 return jsonb_build_object('ok',true,'contractVersion','household_laundry_original_plan_v1',
   'workItemId',v_work.id,'householdId',v_work.household_id,'planId',v_plan.id,
   'eventId',v_prior.id,'planState',v_plan.plan_state,'workOn',v_plan.planned_service_date,
   'exposureDate',v_plan.exposure_service_date,'idempotent',false,'clockAdmitted',false,'newWorkCreated',false);
end;
$body$;
revoke all on function atlas.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text) from public,anon,authenticated,service_role;
create or replace function public.place_household_laundry_original_work_self_api_v1(
 p_work_item_id uuid,p_service_date date,p_action_id uuid,p_reason text
) returns jsonb language sql security definer set search_path to ''
as $body$
 select atlas.place_household_laundry_original_work_self_api_v1(p_work_item_id,p_service_date,p_action_id,p_reason);
$body$;
revoke all on function public.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.place_household_laundry_original_work_self_api_v1(uuid,date,uuid,text) to authenticated;
commit;
