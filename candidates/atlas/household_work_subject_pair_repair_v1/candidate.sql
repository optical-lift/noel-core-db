-- Repair the original Work subject-pair seam, independently of placement.
-- Prior reviewed Household custody candidate already intended a Household branch.
-- Preserve every institutional subject pair and the existing signed exact-link guard.
begin;
do $preflight$
declare v_definition text;
begin
 select pg_get_constraintdef(c.oid) into v_definition from pg_constraint c
 where c.conrelid='atlas.work_item_context_links'::regclass
   and c.conname='work_item_context_links_subject_pair_v1' and c.contype='c' and c.convalidated;
 if v_definition is distinct from
  'CHECK ((((subject_domain = ''spatial''::text) AND (subject_kind = ANY (ARRAY[''zone''::text, ''place''::text, ''growing_object''::text]))) OR ((subject_domain = ''identity''::text) AND (subject_kind = ANY (ARRAY[''identity_subject''::text, ''external_relationship''::text]))) OR ((subject_domain = ''temporal''::text) AND (subject_kind = ''occurrence''::text))))'
 then raise exception 'Original subject pair changed; reconcile source before applying'; end if;
 if not exists(select 1 from pg_trigger
   where tgrelid='atlas.work_item_context_links'::regclass
    and tgname='z_guard_household_work_subject_link_v1'
    and tgfoid='atlas.guard_household_work_subject_link_v1()'::regprocedure
    and tgenabled='O' and not tgisinternal)
 then raise exception 'Required exact Household subject guard unavailable'; end if;
 if has_table_privilege('authenticated','atlas.work_item_context_links','INSERT')
 or has_table_privilege('authenticated','atlas.work_item_context_links','UPDATE')
 or has_table_privilege('anon','atlas.work_item_context_links','INSERT')
 then raise exception 'Private Work link write boundary not established'; end if;
end;
$preflight$;
alter table atlas.work_item_context_links
 drop constraint work_item_context_links_subject_pair_v1;
alter table atlas.work_item_context_links
 add constraint work_item_context_links_subject_pair_v1 check (
   (subject_domain='spatial' and subject_kind in ('zone','place','growing_object'))
   or (subject_domain='identity' and subject_kind in ('identity_subject','external_relationship'))
   or (subject_domain='temporal' and subject_kind='occurrence')
   or (household_id is not null and organization_id is null
      and subject_domain='household' and subject_kind='kernel_instance' and relation_kind='acts_on')
 );

-- Exact read-only native Person projection extracted from held #2902.
create or replace function atlas.household_person_my_work_self_api_v1(
 p_limit integer default 50, p_after_allocation_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path to ''
as $body$
declare
 v_person uuid;
 v_items jsonb;
 v_more boolean;
 v_next uuid;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
   raise exception 'Signed canonical Person required.' using errcode='42501';
 end if;
 v_person:=atlas.current_person_id_v1();
 if v_person is null then raise exception 'Canonical Person unavailable.' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then
   raise exception 'Bounded page size required.' using errcode='22023';
 end if;
 -- Never infer a signed actor from a child/member label, mere Household
 -- membership, governor visibility, or an unrelated institutional allocation.
 -- A competing active responsibility is surfaced as a source error.
 if exists(
   select 1
   from atlas.work_allocations a
   join atlas.work_items w on w.id=a.work_item_id and w.household_id=a.household_id
   join atlas.households h on h.id=w.household_id and h.status='active'
   join atlas.principals p on p.id=h.principal_id and p.status='active'
   where a.household_id is not null and a.organization_id is null
    and w.organization_id is null and w.work_state='open'
    and a.state='active' and a.allocation_role='responsible'
    and a.assignee_canonical_person_id=v_person
    and (
      (a.assignee_household_member_id is null and p.user_id=auth.uid() and p.person_id=v_person)
      or exists(select 1 from atlas.household_members m
        where m.id=a.assignee_household_member_id and m.household_id=a.household_id
        and m.active and m.person_id=v_person and m.user_id=auth.uid())
    )
    and exists(select 1 from atlas.work_allocations other
      where other.work_item_id=w.id and other.household_id=w.household_id
        and other.state='active' and other.allocation_role='responsible' and other.id<>a.id)
 ) then raise exception 'Competing original Household responsibilities require reconciliation.' using errcode='23514'; end if;
 with responsible as (
   select a.id allocation_id,a.allocated_at,a.establishment_basis_kind,
    w.id work_id,w.household_id,w.title,w.instructions,w.result_contract_key,
    w.source_object_id,n.instance_id,
    plan.id plan_id,plan.plan_state,plan.planned_service_date,plan.exposure_service_date,
    plan.responsible_allocation_id plan_allocation_id,
    (select count(*) from atlas.work_execution_plans all_plans
      where all_plans.work_item_id=w.id and all_plans.household_id=w.household_id
        and all_plans.plan_state in ('active','needs_replan')) plan_count
   from atlas.work_allocations a
   join atlas.work_items w on w.id=a.work_item_id and w.household_id=a.household_id
   join atlas.household_need_occurrences_v1 n on n.id=w.source_object_id
     and n.household_id=w.household_id and n.current_work_item_id=w.id and n.state='open'
   join atlas.households h on h.id=w.household_id and h.status='active'
   join atlas.principals p on p.id=h.principal_id and p.status='active'
   left join lateral (
     select ep.* from atlas.work_execution_plans ep
     where ep.work_item_id=w.id and ep.household_id=w.household_id
       and ep.organization_id is null and ep.plan_state in ('active','needs_replan')
     order by ep.updated_at desc,ep.id limit 1
   ) plan on true
   where a.household_id is not null and a.organization_id is null
     and w.organization_id is null and w.work_state='open'
     and w.source_object_type='household_need_occurrence'
     and a.state='active' and a.allocation_role='responsible'
     and a.establishment_basis_kind='household_explicit_carrier_v1'
     and a.assignee_membership_id is null and a.assignee_canonical_person_id=v_person
     and (
      (a.assignee_household_member_id is null and p.user_id=auth.uid() and p.person_id=v_person)
      or exists(select 1 from atlas.household_members m
        where m.id=a.assignee_household_member_id and m.household_id=a.household_id
          and m.active and m.person_id=v_person and m.user_id=auth.uid())
     )
     and (p_after_allocation_id is null or a.id>p_after_allocation_id)
   order by a.id limit p_limit+1
 ), page as (
   select * from responsible order by allocation_id limit p_limit
 ), shaped as (
   select allocation_id,jsonb_build_object(
     'scopeKind','household','householdId',household_id,
     'organizationId',null,'ledgerId',null,
     'workItemId',work_id,'allocationId',allocation_id,'allocatedAt',allocated_at,
     'establishmentBasisKind',establishment_basis_kind,
     'title',title,'instructions',instructions,'resultContractKey',result_contract_key,
     'needOccurrenceId',source_object_id,'subjectId',instance_id,
     'planId',case when plan_count=1 and plan_allocation_id=allocation_id then plan_id else null end,
     'planState',case when plan_count=1 and plan_allocation_id=allocation_id then plan_state else null end,
     'workOn',case when plan_count=1 and plan_allocation_id=allocation_id and plan_state='active' then planned_service_date else null end,
     'exposureDate',case when plan_count=1 and plan_allocation_id=allocation_id and plan_state='active' then exposure_service_date else null end,
     'scheduleState',case
       when plan_count=0 then 'unscheduled'
       when plan_count<>1 or plan_allocation_id is distinct from allocation_id then 'conflict'
       when plan_state='needs_replan' then 'needs_replan'
       when plan_state='active' then 'scheduled'
       else 'unverified_plan' end,
     'workRelevanceVerified',true,'canPlace',false,'clockAdmitted',false
   ) item from page
 )
 select coalesce((select jsonb_agg(item order by allocation_id) from shaped),'[]'::jsonb),
   (select count(*)>p_limit from responsible),
   (select allocation_id from page order by allocation_id desc limit 1)
 into v_items,v_more,v_next;
 return jsonb_build_object('ok',true,'contractVersion','household_person_my_work_v1',
  'sourceScope','active_responsible_person_native_household_work',
  'scheduleReadAcrossAllDates',true,'optionalRequestsExcluded',true,
  'items',v_items,'hasMore',v_more,'nextAllocationId',case when v_more then v_next else null end);
end;
$body$;
revoke all on function atlas.household_person_my_work_self_api_v1(integer,uuid) from public,anon,authenticated,service_role;
create or replace function public.household_person_my_work_self_api_v1(
 p_limit integer default 50,p_after_allocation_id uuid default null
) returns jsonb language sql stable security definer set search_path to ''
as $body$ select atlas.household_person_my_work_self_api_v1(p_limit,p_after_allocation_id); $body$;
revoke all on function public.household_person_my_work_self_api_v1(integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.household_person_my_work_self_api_v1(integer,uuid) to authenticated;
commit;
