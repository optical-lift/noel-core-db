-- A connected Person may PROPOSE a work-on day. A recipient can confirm a
-- different day, and only acceptance establishes Work and Person Day placement.
-- Existing accepted Work can be scheduled/rescheduled by its own canonical Person.
-- No personal-task duplicate, employee credential, manager impersonation or root gate.
begin;
alter table atlas.ledger_person_dispatches
  add column proposed_work_on date;
alter table atlas.ledger_person_dispatches
  add constraint ledger_person_dispatches_notice_no_work_date_v1
  check(dispatch_kind='work_request' or proposed_work_on is null);

create or replace function atlas.connected_ledger_send_dated_self_api_v1(
 p_ledger_id uuid,p_recipient_person_id uuid,p_body text,p_kind text,
 p_source_action_id text,p_proposed_work_on date)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_sender uuid; v_prior atlas.ledger_person_dispatches%rowtype;
 v_receipt jsonb;v_id uuid;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in canonical Person required' using errcode='42501';end if;
 if p_kind='notice' and p_proposed_work_on is not null
 then raise exception 'Informational notices cannot carry a Work date' using errcode='22023';end if;
 v_sender:=atlas.current_person_id_v1();
 -- Same advisory lock and source action as the immutable existing send carrier.
 perform pg_advisory_xact_lock(hashtextextended('atlas.ledger.peer:'||v_sender::text||':'||btrim(coalesce(p_source_action_id,'')),0));
 select * into v_prior from atlas.ledger_person_dispatches
   where sender_person_id=v_sender and source_action_id=btrim(coalesce(p_source_action_id,'')) for update;
 if v_prior.id is not null and v_prior.proposed_work_on is distinct from p_proposed_work_on then
    raise exception 'Source action replay cannot change its original proposed Work date' using errcode='23505';
 end if;
 v_receipt:=atlas.connected_ledger_send_self_api_v1(
   p_ledger_id,p_recipient_person_id,p_body,p_kind,p_source_action_id);
 v_id:=(v_receipt->>'dispatchId')::uuid;
 if v_prior.id is null then
   update atlas.ledger_person_dispatches set proposed_work_on=p_proposed_work_on where id=v_id
   and sender_person_id=v_sender and dispatch_state='pending';
 end if;
 return v_receipt||jsonb_build_object(
  'contractVersion','connected_ledger_dated_dispatch_v1',
  'proposedWorkOn',p_proposed_work_on,
  'dateIsProposalOnly',true,'recipientAccepted',false,
  'executionDateEstablished',false);
end$fn$;

create or replace function atlas.connected_person_place_work_self_api_v1(
 p_work_item_id uuid,p_service_date date,p_reason text default 'Recipient selected the work day for their accepted Ledger responsibility.')
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_person uuid;v_w atlas.work_items%rowtype;v_a atlas.work_allocations%rowtype;
 v_ledger uuid;v_old atlas.work_execution_plans%rowtype;
 v_plan atlas.work_execution_plans%rowtype;v_window jsonb;v_kind text;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in canonical Person required' using errcode='42501';end if;
 v_person:=atlas.current_person_id_v1();
 if p_work_item_id is null or v_reason is null or length(v_reason) not between 12 and 1200
 then raise exception 'Exact Work and meaningful placement reason required' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.plan:'||p_work_item_id::text,0));
 select * into v_w from atlas.work_items where id=p_work_item_id and work_state='open' for update;
 if v_w.id is null then raise exception 'Open Company Work required' using errcode='23514';end if;
 select * into v_a from atlas.work_allocations a
  where a.work_item_id=v_w.id and a.organization_id=v_w.organization_id
   and a.allocation_role='responsible' and a.state='active'
   and a.assignee_membership_id is null
   and a.assignee_canonical_person_id=v_person
   and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope')
  order by a.allocated_at desc,a.id desc limit 1;
 if v_a.id is null then raise exception 'Only the active responsible Person may place their accepted Work' using errcode='42501';end if;
 v_ledger:=(v_a.establishment_basis->>'nativeLedgerId')::uuid;
 if v_ledger is null
   or not atlas.person_has_native_ledger_connection_v1(v_w.organization_id,v_ledger,v_person)
   or not exists(select 1 from atlas.company_work_native_ledger_relevance r
     where r.organization_id=v_w.organization_id and r.work_item_id=v_w.id
      and r.ledger_id=v_ledger and r.attribution_state='active')
 then raise exception 'Exact current Ledger connection and Work relevance required' using errcode='42501';end if;
 select * into v_old from atlas.work_execution_plans
   where work_item_id=v_w.id and organization_id=v_w.organization_id
     and plan_state in ('active','needs_replan') for update;
 if v_old.id is not null and v_old.responsible_allocation_id<>v_a.id
 then raise exception 'Existing plan belongs to another responsibility' using errcode='23514';end if;
 if v_old.id is not null and v_old.plan_state='active'
  and v_old.planned_service_date is not distinct from p_service_date
  and v_old.exposure_service_date is not distinct from p_service_date then
   return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
    'state','already_placed','workItemId',v_w.id,'ledgerId',v_ledger,
    'responsiblePersonId',v_person,'planId',v_old.id,'executionDate',p_service_date,
    'newWorkCreated',false,'idempotent',true);
 end if;
 if p_service_date is null then
   if v_old.id is null then
    return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
     'state','already_unplanned','workItemId',v_w.id,'ledgerId',v_ledger,
     'responsiblePersonId',v_person,'executionDate',null,'newWorkCreated',false);
   end if;
   update atlas.work_execution_plans set plan_state='withdrawn',plan_reason=v_reason,
    metadata=metadata||jsonb_build_object('actorPersonId',v_person,'source','person_self_unplan_v1')
    where id=v_old.id;
   insert into atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     from_planned_service_date,from_exposure_service_date,actor_membership_id,reason,metadata)
   values(v_w.organization_id,v_w.id,v_old.id,'withdrawn',
     v_old.planned_service_date,v_old.exposure_service_date,null,v_reason,
     jsonb_build_object('actorPersonId',v_person,'source','person_self_unplan_v1'));
   return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
    'state','unplanned','workItemId',v_w.id,'ledgerId',v_ledger,
    'responsiblePersonId',v_person,'planId',v_old.id,'executionDate',null,'newWorkCreated',false);
 end if;
 v_window:=atlas.company_work_execution_plan_window_check_v1(v_w.id,p_service_date);
 if not coalesce((v_window->>'allowed')::boolean,false) then
  raise exception 'Requested work-on day conflicts with source Work window' using errcode='23514';end if;
 if v_old.id is null then
   insert into atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,assignee_membership_id,
    planned_by_membership_id,plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata)
   values(v_w.organization_id,v_w.id,v_a.id,null,null,'active',
     p_service_date,p_service_date,p_service_date,v_reason,
     jsonb_build_object('actorPersonId',v_person,'source','person_self_place_v1',
      'personNative',true))
   returning * into v_plan;
   v_kind:='planned';
 else
   update atlas.work_execution_plans set
    planned_service_date=p_service_date,exposure_service_date=p_service_date,
    plan_state='active',plan_reason=v_reason,planned_by_membership_id=null,
    rollover_count=0,
    metadata=metadata||jsonb_build_object('actorPersonId',v_person,'sourceChange','person_self_place_v1')
    where id=v_old.id returning * into v_plan;
   v_kind:=case when v_old.planned_service_date is distinct from p_service_date
     then 'rescheduled' else 'planned' end;
 end if;
 insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
 values(v_w.organization_id,v_w.id,v_plan.id,v_kind,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    null,v_reason,jsonb_build_object('actorPersonId',v_person,'source','person_self_place_v1'));
 return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
   'state','placed','workItemId',v_w.id,'ledgerId',v_ledger,
   'responsiblePersonId',v_person,'planId',v_plan.id,'executionDate',p_service_date,
   'newWorkCreated',false,'workerReadProven',false);
end$fn$;

create or replace function atlas.connected_ledger_respond_dated_self_api_v1(
 p_dispatch_id uuid,p_decision text,p_work_on date)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare v_d atlas.ledger_person_dispatches%rowtype;v_self uuid;
 v_res jsonb;v_day jsonb;v_selected date;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in canonical Person required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 select * into v_d from atlas.ledger_person_dispatches where id=p_dispatch_id for update;
 if v_d.id is null or v_d.recipient_person_id<>v_self
 then raise exception 'Only exact recipient may decide the Work day' using errcode='42501';end if;
 if v_d.dispatch_kind='notice' and p_work_on is not null then
  raise exception 'Notice has no execution day' using errcode='22023';end if;
 if v_d.dispatch_kind='work_request' and lower(btrim(coalesce(p_decision,'')))='accept' then
   -- An explicit recipient override wins over a sender's proposed date.
   v_selected:=coalesce(p_work_on,v_d.proposed_work_on);
 end if;
 v_res:=atlas.connected_ledger_respond_self_api_v1(p_dispatch_id,p_decision);
 if v_res->>'state'='accepted' and v_selected is not null then
   v_day:=atlas.connected_person_place_work_self_api_v1(
     (v_res->>'workItemId')::uuid,v_selected,
     'Recipient accepted the requested Work and selected its first execution day.');
   if v_day->>'state' not in ('placed','already_placed')
     or v_day->>'executionDate' is distinct from v_selected::text
   then raise exception 'Accepted Work was not placed on the requested day' using errcode='23514';end if;
 end if;
 return v_res||jsonb_build_object('contractVersion','connected_ledger_dated_response_v1',
  'proposedWorkOn',v_d.proposed_work_on,'executionDate',v_selected,
  'personDayPlacementEstablished',v_selected is not null,
  'newWorkCreated',v_res->>'workCreated'='true');
end$fn$;

create or replace function atlas.connected_ledger_inbox_dated_self_api_v1(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_packet jsonb;v_items jsonb;
begin
 v_packet:=atlas.connected_ledger_inbox_self_api_v1(p_limit);
 select coalesce(jsonb_agg(i.payload||jsonb_build_object(
   'proposedWorkOn',d.proposed_work_on,
   'dateIsProposalOnly',true)
   order by i.ord),'[]'::jsonb) into v_items
 from jsonb_array_elements(v_packet->'items') with ordinality i(payload,ord)
 join atlas.ledger_person_dispatches d on d.id=(i.payload->>'dispatchId')::uuid;
 return v_packet||jsonb_build_object('contractVersion','connected_ledger_dated_inbox_v1','items',v_items);
end$fn$;

-- Browser-facing PostgREST routes must live in the explicitly exposed public API.
create or replace function public.connected_ledger_send_dated_self_api_v1(
 p_ledger_id uuid,p_recipient_person_id uuid,p_body text,p_kind text,
 p_source_action_id text,p_proposed_work_on date)
returns jsonb language sql security invoker set search_path='pg_catalog' as $fn$
 select atlas.connected_ledger_send_dated_self_api_v1($1,$2,$3,$4,$5,$6);
$fn$;
create or replace function public.connected_ledger_respond_dated_self_api_v1(
 p_dispatch_id uuid,p_decision text,p_work_on date)
returns jsonb language sql security invoker set search_path='pg_catalog' as $fn$
 select atlas.connected_ledger_respond_dated_self_api_v1($1,$2,$3);
$fn$;
create or replace function public.connected_ledger_inbox_dated_self_api_v1(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog' as $fn$
 select atlas.connected_ledger_inbox_dated_self_api_v1($1);
$fn$;
create or replace function public.connected_person_place_work_self_api_v1(
 p_work_item_id uuid,p_service_date date,p_reason text default 'Recipient selected the work day for their accepted Ledger responsibility.')
returns jsonb language sql security invoker set search_path='pg_catalog' as $fn$
 select atlas.connected_person_place_work_self_api_v1($1,$2,$3);
$fn$;

revoke all on function atlas.connected_ledger_send_dated_self_api_v1(uuid,uuid,text,text,text,date) from public,anon;
revoke all on function atlas.connected_ledger_respond_dated_self_api_v1(uuid,text,date) from public,anon;
revoke all on function atlas.connected_ledger_inbox_dated_self_api_v1(integer) from public,anon;
revoke all on function atlas.connected_person_place_work_self_api_v1(uuid,date,text) from public,anon;
revoke all on function public.connected_ledger_send_dated_self_api_v1(uuid,uuid,text,text,text,date) from public,anon;
revoke all on function public.connected_ledger_respond_dated_self_api_v1(uuid,text,date) from public,anon;
revoke all on function public.connected_ledger_inbox_dated_self_api_v1(integer) from public,anon;
revoke all on function public.connected_person_place_work_self_api_v1(uuid,date,text) from public,anon;
grant execute on function atlas.connected_ledger_send_dated_self_api_v1(uuid,uuid,text,text,text,date) to authenticated;
grant execute on function atlas.connected_ledger_respond_dated_self_api_v1(uuid,text,date) to authenticated;
grant execute on function atlas.connected_ledger_inbox_dated_self_api_v1(integer) to authenticated;
grant execute on function atlas.connected_person_place_work_self_api_v1(uuid,date,text) to authenticated;
grant execute on function public.connected_ledger_send_dated_self_api_v1(uuid,uuid,text,text,text,date) to authenticated;
grant execute on function public.connected_ledger_respond_dated_self_api_v1(uuid,text,date) to authenticated;
grant execute on function public.connected_ledger_inbox_dated_self_api_v1(integer) to authenticated;
grant execute on function public.connected_person_place_work_self_api_v1(uuid,date,text) to authenticated;
notify pgrst,'reload schema';
commit;
