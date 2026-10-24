
-- Today P0: three authenticated, source-owned READ APIs.
-- No modification of personal tasks, allocations, work or dates.
create or replace function atlas.person_open_task_backlog_self_api_v1(p_date date,p_limit integer default 150)
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare v_principal uuid; v_rows jsonb; v_count integer;
begin
 v_principal:=atlas.require_active_task_principal_v1();
 if auth.uid() is null or p_date is null or p_limit not between 1 and 200 then
   raise exception 'Valid signed-in Person, day and bounded limit required' using errcode='22023';
 end if;
 with eligible as (
   select t.id,t.sentence,t.due_date,t.status,t.created_at,
     transfer.id as institutional_id,transfer.work_state as institutional_state
   from atlas.task_entries t
   left join lateral (
    select w.id,w.work_state from atlas.work_items w
    where w.source_object_type='personal_dated_task' and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
   ) transfer on true
   where t.owner_user_id=auth.uid() and t.principal_id=v_principal
     and t.status='open' and t.due_date<p_date and t.archived_at is null
   order by t.due_date desc,t.created_at desc,t.id desc
   limit p_limit+1
 ), counted as (select count(*) n from eligible)
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',id,'sentence',sentence,'dueDate',due_date,'status',status,
   'institutionalWorkItemId',institutional_id,'institutionalWorkState',institutional_state
  ) order by due_date desc,created_at desc,id desc)
  filter (where rn<=p_limit),'[]'::jsonb), (select n from counted)
 into v_rows,v_count
 from (select *,row_number() over(order by due_date desc,created_at desc,id desc) rn from eligible) numbered;
 return jsonb_build_object('ok',true,'contractVersion','person_open_task_backlog_v1',
  'beforeDate',p_date,'items',v_rows,'hasMore',v_count>p_limit,
  'source','original_personal_tasks','authorization','own_signed_principal_only');
end $body$;
revoke all on function atlas.person_open_task_backlog_self_api_v1(date,integer) from public;
grant execute on function atlas.person_open_task_backlog_self_api_v1(date,integer) to authenticated;
create or replace function public.person_open_task_backlog_self_api_v1(p_date date,p_limit integer default 150)
returns jsonb language sql stable set search_path to ''
as $body$ select atlas.person_open_task_backlog_self_api_v1(p_date,p_limit) $body$;
revoke all on function public.person_open_task_backlog_self_api_v1(date,integer) from public;
grant execute on function public.person_open_task_backlog_self_api_v1(date,integer) to authenticated;

create or replace function atlas.connected_ledger_person_agenda_self_api_v1(
 p_ledger_id uuid,p_person_id uuid,p_date date,p_limit integer default 150
) returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare v_self uuid; v_rows jsonb; v_count int;
begin
 if auth.uid() is null or p_ledger_id is null or p_person_id is null or p_date is null
    or p_limit not between 1 and 200 or
    (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
   raise exception 'Active, bounded Ledger day and Person required' using errcode='42501';
 end if;
 v_self:=atlas.current_person_id_v1();
 perform atlas.current_active_ledger_seat_v1(p_ledger_id);
 if not exists(select 1 from ledger.seats s join reality.entities e on e.id=s.person_entity_id
     where s.ledger_id=p_ledger_id and s.person_entity_id=p_person_id
       and s.seat_state='active' and s.ended_at is null
       and e.entity_kind='person' and e.identity_state='canonical') then
   raise exception 'Recipient is not an active canonical Ledger Person' using errcode='42501';
 end if;
 with eligible as (
  select w.id,w.title,w.work_state,w.organization_id,a.id allocation_id,
   p.id plan_id,p.plan_state,p.exposure_service_date,p.planned_service_date,
   case when p.id is null then 'unscheduled'
        when p.plan_state='needs_replan' then 'needs_replan'
        when p.exposure_service_date < p_date then 'overdue'
        when p.exposure_service_date=p_date then 'scheduled_today'
        else 'future' end as date_state,
   w.created_at
  from atlas.work_items w
  join atlas.work_allocations a on a.work_item_id=w.id
      and a.organization_id=w.organization_id
      and a.assignee_canonical_person_id=p_person_id
      and a.allocation_role='responsible' and a.state='active'
  left join lateral (
    select ep.id,ep.plan_state,ep.exposure_service_date,ep.planned_service_date
    from atlas.work_execution_plans ep
    where ep.organization_id=w.organization_id and ep.work_item_id=w.id
      and ep.plan_state in ('active','needs_replan')
    order by ep.updated_at desc,ep.id desc limit 1
  ) p on true
  where w.work_state='open'
    and (w.created_by_user_id=auth.uid() or atlas.is_effective_organization_owner_v1(w.organization_id))
    and exists (
      select 1 from atlas.company_work_native_ledger_relevance rel
      where rel.work_item_id=w.id and rel.organization_id=w.organization_id
        and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
        and (rel.evidence_kind in ('owner_attested','participant_attested')
         or (rel.evidence_kind='source_verified' and exists(
           select 1 from atlas.company_work_native_ledger_exact_source_v1(w.id,p_ledger_id) proof
           where proof.source_schema=rel.source_schema and proof.source_table=rel.source_table
             and proof.source_id=rel.source_id
         )))
    )
    and (p.id is null or p.exposure_service_date<=p_date or p.plan_state='needs_replan')
  order by p.exposure_service_date nulls last,w.created_at,w.id
  limit p_limit+1
 ), counted as(select count(*) n from eligible)
 select coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',id,'title',title,'workState',work_state,'organizationId',organization_id,
  'allocationId',allocation_id,'planId',plan_id,'planState',plan_state,
  'exposureDate',exposure_service_date,'scheduledDate',planned_service_date,
  'dateState',date_state,'recipientPersonId',p_person_id,'ledgerId',p_ledger_id
 ) order by exposure_service_date nulls last,created_at,id)
 filter (where rn<=p_limit),'[]'::jsonb), (select n from counted)
 into v_rows,v_count
 from (select *,row_number() over(order by exposure_service_date nulls last,created_at,id) rn from eligible) ranked;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_person_agenda_v1',
  'date',p_date,'ledgerId',p_ledger_id,'personId',p_person_id,
  'items',v_rows,'hasMore',v_count>p_limit,
  'scopeRule','same_Ledger_active_seats_and_creator_or_effective_organization_owner',
  'sourceStatesPreserved',true);
end $body$;
revoke all on function atlas.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer) from public;
grant execute on function atlas.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer) to authenticated;
create or replace function public.connected_ledger_person_agenda_self_api_v1(
 p_ledger_id uuid,p_person_id uuid,p_date date,p_limit integer default 150
) returns jsonb language sql stable set search_path to ''
as $body$ select atlas.connected_ledger_person_agenda_self_api_v1(p_ledger_id,p_person_id,p_date,p_limit) $body$;
revoke all on function public.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer) from public;
grant execute on function public.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer) to authenticated;

create or replace function atlas.today_work_assignment_activity_self_api_v1(
 p_date date,p_timezone text default 'UTC',p_limit integer default 100
) returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare v_person uuid;v_rows jsonb;v_count int;
begin
 if auth.uid() is null or p_date is null or p_limit not between 1 and 200
   or p_timezone is null or not exists(select 1 from pg_catalog.pg_timezone_names tz where tz.name=p_timezone)
   or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
   raise exception 'Signed-in Person, real day and valid timezone required' using errcode='42501';
 end if;
 v_person:=atlas.current_person_id_v1();
 with eligible as(
  select w.id,w.title,w.created_at,a.allocated_at,a.state allocation_state,
    a.assignee_canonical_person_id recipient_id,e.display_name recipient_name,
    l.id ledger_id,l.name ledger_name,
    ep.exposure_service_date,ep.id plan_id,
    a.establishment_basis_kind as activity_kind
  from atlas.work_items w
  join atlas.work_allocations a on a.work_item_id=w.id and a.organization_id=w.organization_id
    and a.allocation_role='responsible'
    and a.establishment_basis_kind in ('ledger_connection_direct_assignment','delegated_under_standing_scope')
  join reality.entities e on e.id=a.assignee_canonical_person_id
    and e.entity_kind='person' and e.identity_state='canonical'
  join ledger.ledgers l on l.id=(a.establishment_basis->>'nativeLedgerId')::uuid
  left join lateral (
    select p.id,p.exposure_service_date from atlas.work_execution_plans p
    where p.work_item_id=w.id and p.organization_id=w.organization_id
      and p.responsible_allocation_id=a.id
    order by p.created_at desc,p.id desc limit 1
  ) ep on true
  where w.created_by_user_id=auth.uid()
    and a.establishment_basis->>'senderPersonId'=v_person::text
    and (a.allocated_at at time zone p_timezone)::date=p_date
    and exists(select 1 from ledger.seats s where s.ledger_id=l.id and s.person_entity_id=v_person
      and s.seat_state='active' and s.ended_at is null)
  order by a.allocated_at,w.id
  limit p_limit+1
 ), counted as(select count(*) n from eligible)
 select coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',id,'title',title,'allocatedAt',allocated_at,'createdAt',created_at,
  'allocationState',allocation_state,'recipientPersonId',recipient_id,
  'recipientName',recipient_name,'ledgerId',ledger_id,'ledgerName',ledger_name,
  'workOn',exposure_service_date,'planId',plan_id,'kind',activity_kind)
  order by allocated_at,id) filter(where rn<=p_limit),'[]'::jsonb),(select n from counted)
 into v_rows,v_count
 from (select *,row_number() over(order by allocated_at,id) rn from eligible) ranked;
 return jsonb_build_object('ok',true,'contractVersion','today_work_assignment_activity_v1',
  'date',p_date,'timezone',p_timezone,'items',v_rows,'hasMore',v_count>p_limit,
  'actorPersonId',v_person,'source','work_allocations_original',
  'noNewJournalTestimony',true);
end $body$;
revoke all on function atlas.today_work_assignment_activity_self_api_v1(date,text,integer) from public;
grant execute on function atlas.today_work_assignment_activity_self_api_v1(date,text,integer) to authenticated;
create or replace function public.today_work_assignment_activity_self_api_v1(
 p_date date,p_timezone text default 'UTC',p_limit integer default 100
) returns jsonb language sql stable set search_path to ''
as $body$ select atlas.today_work_assignment_activity_self_api_v1(p_date,p_timezone,p_limit) $body$;
revoke all on function public.today_work_assignment_activity_self_api_v1(date,text,integer) from public;
grant execute on function public.today_work_assignment_activity_self_api_v1(date,text,integer) to authenticated;
