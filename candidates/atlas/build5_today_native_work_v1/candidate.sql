-- Atlas Build 5: candidate ONLY. No production execution.
-- Canonical work is institutional, accepted Person scope authorizes responsibility,
-- execution is a separate Person/Day plan on the existing work_execution_plans table.
begin;

-- An all-day deadline is not a midnight timestamp; do not invent a timezone.
alter table atlas.work_time_contracts
  add column if not exists due_on_date date;
comment on column atlas.work_time_contracts.due_on_date is
  'Canonical date-only Work deadline; distinct from a planned execution day and from timestamp time windows.';

-- Preserve the existing membership-based Worker Day validator unchanged in its
-- membership branch. Only exact accepted Person-native responsibility may use
-- the nullable carrier; this does not give nonmembers employee execution rights.
alter table atlas.work_execution_plans
  alter column assignee_membership_id drop not null;

create or replace function atlas.validate_work_execution_plan_v1()
returns trigger language plpgsql security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_delivery jsonb;
  v_ledger_id uuid;
begin
  select * into v_work from atlas.work_items where id=new.work_item_id;
  if v_work.id is null or v_work.organization_id<>new.organization_id then
    raise exception 'Execution plan must belong to its Company Work organization.'
      using errcode='23514';
  end if;
  select * into v_allocation from atlas.work_allocations
    where id=new.responsible_allocation_id;
  if v_allocation.id is null
    or v_allocation.organization_id<>new.organization_id
    or v_allocation.work_item_id<>new.work_item_id
    or v_allocation.assignee_membership_id is distinct from new.assignee_membership_id
    or v_allocation.allocation_role<>'responsible' then
    raise exception 'Execution plan must point to the exact responsible allocation.'
      using errcode='23514';
  end if;
  if new.plan_state='active' then
    -- The date-only deadline is independent of this service date, but a
    -- later plan cannot silently ignore the established deadline.
    if exists (
      select 1 from atlas.work_time_contracts t
      where t.work_item_id=new.work_item_id and t.contract_state='active'
        and t.due_on_date is not null
        and (new.planned_service_date>t.due_on_date
          or new.exposure_service_date>t.due_on_date)
    ) then
      raise exception 'Plan is beyond the governing date-only deadline.'
        using errcode='23514';
    end if;
    if v_work.work_state<>'open' or v_allocation.state<>'active' then
      raise exception 'Active plan requires open Work and active responsibility.'
        using errcode='23514';
    end if;
    if new.assignee_membership_id is not null then
      v_delivery:=atlas.company_work_execution_membership_check_v1(
        new.work_item_id,new.assignee_membership_id,new.planned_service_date);
      if not coalesce((v_delivery->>'allowed')::boolean,false) then
        raise exception 'Responsible membership is not eligible on planned day (%).',
          v_delivery->>'state' using errcode='23514';
      end if;
      v_delivery:=atlas.company_work_execution_membership_check_v1(
        new.work_item_id,new.assignee_membership_id,new.exposure_service_date);
      if not coalesce((v_delivery->>'allowed')::boolean,false) then
        raise exception 'Responsible membership is not eligible on exposure day (%).',
          v_delivery->>'state' using errcode='23514';
      end if;
    else
      -- A Person plan never creates a farm/employee execution credential.
      if v_allocation.assignee_canonical_person_id is null
        or v_allocation.establishment_basis_kind not in (
          'delegated_under_standing_scope','person_connection_receiver_uptake')
        or coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
             !~ '^[0-9a-fA-F-]{36}$' then
        raise exception 'Person plan requires accepted canonical Person responsibility.'
          using errcode='23514';
      end if;
      v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
      if not atlas.person_has_native_ledger_connection_v1(
          v_work.organization_id,v_ledger_id,v_allocation.assignee_canonical_person_id)
        or not exists (
          select 1 from atlas.company_work_native_ledger_relevance rel
          where rel.organization_id=v_work.organization_id and rel.work_item_id=v_work.id
            and rel.ledger_id=v_ledger_id and rel.attribution_state='active'
        ) then
        raise exception 'Person plan requires currently valid exact Ledger connection.'
          using errcode='23514';
      end if;
    end if;
  end if;
  new.updated_at:=now();
  return new;
end
$function$;

-- One source-owned command creates exactly one institutional Work identity,
-- establishes its Ledger relevance and its already-accepted responsibility,
-- records the date-only deadline separately, then places that Person's day.
-- Failure anywhere rolls back the whole write.
create or replace function atlas.owner_create_native_ledger_today_work_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
  p_sentence text,p_execution_date date,p_due_date date,
  p_source_action_id text,p_atlas_verification boolean default false)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_owner uuid;
  v_owner_membership uuid;
  v_scope atlas.company_work_standing_assignment_scopes%rowtype;
  v_work atlas.work_items%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_allocation jsonb;
  v_key text;
  v_title text:=nullif(btrim(coalesce(p_sentence,'')),'');
  v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_class text:=case when p_atlas_verification then 'atlas_verification'
                     else 'ordinary' end;
  v_new boolean:=false;
begin
  if auth.uid() is null or p_organization_id is null or p_ledger_id is null
    or p_scope_id is null or v_title is null or length(v_title)>500
    or p_execution_date is null or v_action is null
    or length(v_action)>128 or p_atlas_verification is null
    or (p_due_date is not null and p_execution_date>p_due_date) then
    raise exception 'Exact task sentence, Ledger, accepted recipient scope and valid dates required.'
      using errcode='22023';
  end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_owner_membership:=atlas.current_effective_organization_membership_v1(
    p_organization_id);
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_owner_membership and m.organization_id=p_organization_id
      and m.person_id=v_owner and m.role='owner' and m.active
  ) then
    raise exception 'Current authenticated owner authority required.' using errcode='42501';
  end if;
  select * into v_scope from atlas.company_work_standing_assignment_scopes
    where id=p_scope_id for share;
  if v_scope.id is null or v_scope.organization_id<>p_organization_id
    or v_scope.ledger_id<>p_ledger_id
    or v_scope.proposed_by_person_id is distinct from v_owner
    or v_scope.worker_membership_id is not null
    or v_scope.scope_state<>'active' or v_scope.accepted_at is null
    or v_scope.accepted_by_person_id is distinct from v_scope.worker_person_id
    or (v_scope.valid_until is not null and v_scope.valid_until<=now())
    or v_scope.coverage_mode not in ('ledger_all_work','operation_class')
    or not atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id) then
    raise exception 'Existing accepted exact Person/Ledger standing responsibility required.'
      using errcode='23514';
  end if;
  if not exists (
    select 1 from atlas.work_result_contract_policies policy
      where policy.contract_key='ordinary_company_work_worker_attestation_v1'
        and policy.active and policy.source_domain='organization'
        and policy.acceptance_mode='worker_attestation'
  ) then
    raise exception 'Ordinary Person result contract unavailable.' using errcode='23514';
  end if;
  v_key:='today-person-work:'||auth.uid()::text||':'||md5(v_action);
  perform pg_advisory_xact_lock(hashtextextended(
      'atlas.today.person.work:'||p_organization_id::text||':'||v_key,0));
  select * into v_work from atlas.work_items
    where organization_id=p_organization_id and stable_key=v_key for update;
  if v_work.id is not null then
    if v_work.title is distinct from v_title
      or v_work.work_state<>'open'
      or v_work.metadata->>'sourceActionId' is distinct from v_action
      or v_work.metadata->>'sourceScopeId' is distinct from p_scope_id::text
      or v_work.metadata->>'taskClassification' is distinct from v_class
      or not exists (
        select 1 from atlas.work_execution_plans p
          where p.work_item_id=v_work.id and p.plan_state='active'
          and p.planned_service_date=p_execution_date)
      or coalesce((select t.due_on_date from atlas.work_time_contracts t
          where t.work_item_id=v_work.id and t.contract_state='active'
          order by t.created_at desc limit 1),'0001-01-01'::date)
          is distinct from coalesce(p_due_date,'0001-01-01'::date) then
      raise exception 'Source action already belongs to a different Work request.'
        using errcode='23505';
    end if;
  else
    insert into atlas.work_items(
      organization_id,organization_unit_id,operation_class,
      title,work_state,source_object_type,source_object_id,
      created_by_user_id,stable_key,metadata)
    values (
      p_organization_id,
      case when v_scope.coverage_mode='operation_class'
        then v_scope.organization_unit_id else null end,
      case when v_scope.coverage_mode='operation_class'
        then v_scope.covered_operation_class else null end,
      v_title,'open',null,null,auth.uid(),v_key,
      jsonb_build_object(
        'sourceContract','today_native_ledger_work_v1',
        'sourceSurface','personal_notebook_daily_log',
        'sourceActionId',v_action,
        'sourceScopeId',p_scope_id,'taskClassification',v_class,
        'createdByPersonId',v_owner,'custody','institutional'))
    returning * into v_work;
    v_new:=true;

    insert into atlas.company_work_native_ledger_relevance(
      organization_id,work_item_id,ledger_id,evidence_kind,
      attestation_source_ref,attestation_reason,established_by_person_id)
    values (p_organization_id,v_work.id,p_ledger_id,'owner_attested',
      'atlas.work_items:'||v_work.id::text,
      'Owner-authored task on Today in the specified native Ledger.',v_owner);

    insert into atlas.company_work_result_contract_bindings_v1(
      organization_id,ledger_id,work_item_id,actor_person_id,
      actor_membership_id,contract_key,reason)
    values (p_organization_id,p_ledger_id,v_work.id,v_owner,v_owner_membership,
      'ordinary_company_work_worker_attestation_v1',
      'Owner issued ordinary notebook Work under an accepted Person responsibility.');
    update atlas.work_items set
      result_contract_key='ordinary_company_work_worker_attestation_v1'
    where id=v_work.id;

    v_allocation:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
      v_work.id,p_scope_id,
      'Owner gave exact Ledger Work through Today under a previously accepted standing responsibility.');
    if v_allocation->>'state'<>'assigned'
      or v_allocation->>'workItemId' is distinct from v_work.id::text then
      raise exception 'Canonical direct assignment was not confirmed.' using errcode='23514';
    end if;

    if p_due_date is not null then
      insert into atlas.work_time_contracts(
        organization_id,work_item_id,due_on_date,source_kind,metadata)
      values (p_organization_id,v_work.id,p_due_date,
        'owner_authored_date_only_deadline',
        jsonb_build_object('source','today_native_ledger_work_v1',
          'separateFromExecutionDate',true));
    end if;

    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,
      assignee_membership_id,planned_by_membership_id,
      plan_state,first_planned_service_date,planned_service_date,
      exposure_service_date,plan_reason,metadata)
    values (p_organization_id,v_work.id,
      (v_allocation->>'allocationId')::uuid,
      null,v_owner_membership,
      'active',p_execution_date,p_execution_date,p_execution_date,
      'Owner explicitly placed assigned connected Person Work on this date.',
      jsonb_build_object('source','today_native_ledger_work_v1',
        'personDayNotEmployeeWorkerDay',true))
    returning * into v_plan;
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      to_planned_service_date,to_exposure_service_date,
      actor_membership_id,reason,metadata)
    values (p_organization_id,v_work.id,v_plan.id,'planned',
      p_execution_date,p_execution_date,v_owner_membership,
      'Explicit Person Day placement from Today.',
      jsonb_build_object('source','today_native_ledger_work_v1'));
  end if;
  if v_plan.id is null then
    select * into v_plan from atlas.work_execution_plans
      where work_item_id=v_work.id and plan_state='active';
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','today_native_ledger_work_v1',
    'workItemId',v_work.id,'ledgerId',p_ledger_id,
    'organizationId',p_organization_id,'responsiblePersonId',v_scope.worker_person_id,
    'scopeId',p_scope_id,'planId',v_plan.id,
    'executionDate',v_plan.planned_service_date,'dueDate',p_due_date,
    'taskClassification',v_class,'createdNow',v_new,
    'individualAcceptanceRequired',false,
    'personDayPlacementEstablished',true,'employeeWorkerDayCredentialCreated',false,
    'workerReadProven',false,'completionProven',false);
end
$function$;

-- A Person can read only their own *actually placed* Work for the requested day.
-- Undated responsibility remains a separate read; it is not falsely due today.
create or replace function atlas.connected_person_company_work_day_self_api_v1(
  p_date date)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb;
begin
  if auth.uid() is null or v_self is null or p_date is null then
    raise exception 'Signed-in canonical Person and exact day required.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',w.id,'allocationId',a.id,'planId',p.id,
    'organizationId',w.organization_id,
    'ledgerId',(a.establishment_basis->>'nativeLedgerId')::uuid,
    'title',w.title,'instructions',w.instructions,
    'executionDate',p.planned_service_date,'exposureDate',p.exposure_service_date,
    'dueDate',t.due_on_date,'taskClassification',
      coalesce(w.metadata->>'taskClassification','ordinary'),
    'canReportOrdinaryCompletion',
      w.result_contract_key='ordinary_company_work_worker_attestation_v1')
    order by p.created_at,w.id),'[]'::jsonb) into v_items
  from atlas.work_allocations a
  join atlas.work_items w on w.id=a.work_item_id and w.organization_id=a.organization_id
  join atlas.work_execution_plans p on p.work_item_id=w.id
    and p.organization_id=w.organization_id
    and p.responsible_allocation_id=a.id
    and p.plan_state='active' and p.exposure_service_date=p_date
    and p.assignee_membership_id is null
  left join lateral (
    select due_on_date from atlas.work_time_contracts t
      where t.work_item_id=w.id and t.contract_state='active'
      order by t.created_at desc limit 1) t on true
  where a.assignee_canonical_person_id=v_self
    and a.assignee_membership_id is null
    and a.allocation_role='responsible' and a.state='active'
    and a.establishment_basis_kind in (
      'person_connection_receiver_uptake','delegated_under_standing_scope')
    and w.work_state='open'
    and atlas.person_has_native_ledger_connection_v1(
      w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self);
  return jsonb_build_object(
    'ok',true,'contractVersion','connected_person_company_work_day_v1',
    'date',p_date,'personId',v_self,'items',v_items,
    'oneCanonicalWorkIdentity',true,'deliveryReadProven',false);
end
$function$;

-- Archived personal sources are retained, but no longer occupy Today's
-- live responsibility space or resurface in ordinary dated-task projections.
alter table atlas.task_entries add column if not exists archived_at timestamptz;
comment on column atlas.task_entries.archived_at is
  'Owner-directed removal from active personal notebook views; original source remains recoverable.';

create or replace function atlas.atlas_task_day_self_api_v1(p_date date)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_rows jsonb;
begin
  if p_date is null then
    raise exception 'Date required.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
    'institutionalWorkItemId',wi.id,
    'institutionalWorkState',wi.work_state,
    'institutionalTransfer',wi.id is not null
  )) order by case when t.status='open' then 0 else 1 end,
    t.created_at,t.id),'[]'::jsonb)
  into v_rows
  from atlas.task_entries t
  left join lateral (
    select w.id,w.work_state from atlas.work_items w
    where w.source_object_type='personal_dated_task' and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
  ) wi on true
  where t.owner_user_id=auth.uid()
    and t.principal_id=v_principal and t.due_date=p_date
    and t.archived_at is null;
  return jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
end
$function$;

create or replace function atlas.set_personal_task_archive_self_api_v1(
  p_task_id uuid,p_archived boolean)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_task atlas.task_entries%rowtype;
  v_principal uuid:=atlas.require_active_task_principal_v1();
begin
  if auth.uid() is null or p_task_id is null or p_archived is null then
    raise exception 'Signed-in owner, original task and archive choice required.'
      using errcode='42501';
  end if;
  select * into v_task from atlas.task_entries
    where id=p_task_id and owner_user_id=auth.uid()
      and principal_id=v_principal for update;
  if v_task.id is null then
    raise exception 'Your original task is unavailable.' using errcode='42501';
  end if;
  update atlas.task_entries set
    archived_at=case when p_archived then coalesce(archived_at,now()) else null end
    where id=v_task.id;
  return jsonb_build_object(
    'ok',true,'contractVersion','personal_task_archive_v1',
    'taskId',v_task.id,'date',v_task.due_date,
    'archived',p_archived,'sourcePreserved',true);
end
$function$;

create or replace function atlas.personal_archived_tasks_day_self_api_v1(
  p_date date)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_items jsonb;
begin
  if auth.uid() is null or p_date is null then
    raise exception 'Signed-in original owner and date required.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
    'archivedAt',t.archived_at,'institutionalWorkItemId',w.id)
    order by t.archived_at desc,t.id),'[]'::jsonb) into v_items
  from atlas.task_entries t
  left join lateral (
    select id from atlas.work_items w
    where w.source_object_type='personal_dated_task'
      and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
  ) w on true
  where t.owner_user_id=auth.uid() and t.principal_id=v_principal
    and t.due_date=p_date and t.archived_at is not null;
  return jsonb_build_object('ok',true,
    'contractVersion','personal_task_archive_day_v1',
    'date',p_date,'items',v_items);
end
$function$;

revoke all on function atlas.set_personal_task_archive_self_api_v1(uuid,boolean)
  from public,anon;
revoke all on function atlas.personal_archived_tasks_day_self_api_v1(date)
  from public,anon;
grant execute on function atlas.set_personal_task_archive_self_api_v1(uuid,boolean)
  to authenticated;
grant execute on function atlas.personal_archived_tasks_day_self_api_v1(date)
  to authenticated;

-- Permanently remove a mistaken *personal-only* dated task after confirming
-- no institutional Work references it. No protected Company Work, accepted
-- worker results, or source-linked history is erased by this narrow command.
create or replace function atlas.delete_unlinked_personal_task_self_api_v1(
  p_task_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_task atlas.task_entries%rowtype;
  v_principal uuid:=atlas.require_active_task_principal_v1();
begin
  if auth.uid() is null or p_task_id is null then
    raise exception 'Signed-in Person and exact original task required.'
      using errcode='42501';
  end if;
  select * into v_task from atlas.task_entries
    where id=p_task_id and owner_user_id=auth.uid()
      and principal_id=v_principal for update;
  if v_task.id is null then
    raise exception 'Personal task was not found in your authenticated source.'
      using errcode='42501';
  end if;
  if exists (
    select 1 from atlas.work_items w
    where w.source_object_type='personal_dated_task'
      and w.source_object_id=v_task.id
  ) then
    raise exception 'Institutional Work has this source; use governed Work retirement.'
      using errcode='23514';
  end if;
  delete from atlas.task_entries
    where id=v_task.id and owner_user_id=auth.uid() and principal_id=v_principal;
  if not found then raise exception 'Original task deletion could not be confirmed.'
    using errcode='40001'; end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','personal_task_permanent_delete_v1',
    'deletedTaskId',v_task.id,'previousDate',v_task.due_date,
    'noInstitutionalWorkDeleted',true,'permanentlyDeleted',true);
end
$function$;

-- The same existing execution plan is rescheduled or withdrawn by an owner.
-- Person-native responsibility does not become an employee Worker Day, and no
-- second Work identity or due date is created.
create or replace function atlas.owner_set_connected_person_work_day_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid,p_service_date date,p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_old atlas.work_execution_plans%rowtype;
  v_owner uuid;
  v_owner_member uuid;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_window jsonb;
  v_event text;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null
    or v_reason is null or length(v_reason) not between 12 and 1200 then
    raise exception 'Exact owner Work, Ledger and meaningful planning reason required.'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.plan:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and work_state='open' for update;
  if v_work.id is null then raise exception 'Open Work required for date changes.'
    using errcode='23514'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,p_ledger_id);
  v_owner_member:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id);
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_owner_member and m.organization_id=v_work.organization_id
      and m.person_id=v_owner and m.role='owner' and m.active
  ) then raise exception 'Current authenticated owner membership required.'
    using errcode='42501'; end if;
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=v_work.organization_id
      and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind='owner_attested' or
        (rel.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table
            and proof.source_id=rel.source_id
        )))
  ) then raise exception 'Exact Ledger relevance required.' using errcode='42501'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible' and a.state='active'
      and a.assignee_membership_id is null
      and a.assignee_canonical_person_id is not null
      and a.establishment_basis_kind in (
        'delegated_under_standing_scope','person_connection_receiver_uptake')
      and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    limit 1;
  if v_allocation.id is null or not atlas.person_has_native_ledger_connection_v1(
    v_work.organization_id,p_ledger_id,v_allocation.assignee_canonical_person_id) then
    raise exception 'Active connected Person responsibility required.'
      using errcode='23514';
  end if;
  select * into v_old from atlas.work_execution_plans
    where work_item_id=v_work.id and plan_state in ('active','needs_replan')
    for update;
  if v_old.id is not null and
    v_old.responsible_allocation_id<>v_allocation.id then
    raise exception 'Current plan belongs to different responsibility.'
      using errcode='23514';
  end if;

  if p_service_date is null then
    if v_old.id is null then
      return jsonb_build_object('ok',true,
        'contractVersion','native_person_work_plan_v1',
        'state','already_unplanned','workItemId',v_work.id,
        'ledgerId',p_ledger_id,'responsiblePersonId',
        v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
    end if;
    update atlas.work_execution_plans
      set plan_state='withdrawn',plan_reason=v_reason,
      metadata=metadata||jsonb_build_object(
        'sourceChange','native_person_owner_unplan_v1',
        'withdrawalReason',v_reason)
    where id=v_old.id and plan_state in ('active','needs_replan');
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      from_planned_service_date,from_exposure_service_date,
      actor_membership_id,reason,metadata)
    values (v_work.organization_id,v_work.id,v_old.id,'withdrawn',
      v_old.planned_service_date,v_old.exposure_service_date,
      v_owner_member,v_reason,
      jsonb_build_object('source','native_person_owner_unplan_v1'));
    return jsonb_build_object('ok',true,
      'contractVersion','native_person_work_plan_v1',
      'state','unplanned','workItemId',v_work.id,'ledgerId',p_ledger_id,
      'planId',v_old.id,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
  end if;
  v_window:=atlas.company_work_execution_plan_window_check_v1(
    v_work.id,p_service_date);
  if not coalesce((v_window->>'allowed')::boolean,false) then
    raise exception 'Selected date conflicts with source-owned Work window (%).',
      v_window->>'state' using errcode='23514';
  end if;
  if v_old.id is null then
    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,
      assignee_membership_id,planned_by_membership_id,
      plan_state,first_planned_service_date,planned_service_date,
      exposure_service_date,plan_reason,metadata)
    values (v_work.organization_id,v_work.id,v_allocation.id,null,
      v_owner_member,'active',p_service_date,p_service_date,
      p_service_date,v_reason,
      jsonb_build_object('source','native_person_owner_plan_v1'))
    returning * into v_plan;
    v_event:='planned';
  else
    update atlas.work_execution_plans
      set planned_service_date=p_service_date,exposure_service_date=p_service_date,
        plan_state='active',plan_reason=v_reason,
        planned_by_membership_id=v_owner_member,
        metadata=metadata||jsonb_build_object(
          'sourceChange','native_person_owner_plan_v1'),
        rollover_count=0
      where id=v_old.id returning * into v_plan;
    v_event:=case when v_old.planned_service_date is distinct from p_service_date
      then 'rescheduled' else 'planned' end;
  end if;
  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
  values (v_work.organization_id,v_work.id,v_plan.id,v_event,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    v_owner_member,v_reason,
    jsonb_build_object('source','native_person_owner_plan_v1'));
  return jsonb_build_object('ok',true,
    'contractVersion','native_person_work_plan_v1',
    'state','planned','workItemId',v_work.id,
    'ledgerId',p_ledger_id,'planId',v_plan.id,
    'plannedServiceDate',v_plan.planned_service_date,
    'responsiblePersonId',v_allocation.assignee_canonical_person_id,
    'newWorkCreated',false,'workerReadProven',false);
end
$function$;

revoke all on function atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)
  from public,anon;
grant execute on function atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)
  to authenticated;

-- Owner-side blocker inspection is an explicit authenticated read,
-- NOT a notification claim or a new Principal escalation. It makes the
-- unresolved reason visible in the same Ledger Work identity.
create or replace function atlas.owner_native_ledger_blocker_detail_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_owner uuid;
  v_latest atlas.work_execution_results%rowtype;
  v_person uuid;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null then
    raise exception 'Exact authenticated owner, Work and Ledger required.'
      using errcode='42501';
  end if;
  select * into v_work from atlas.work_items
    where id=p_work_item_id;
  if v_work.id is null then raise exception 'Original Work unavailable.'
    using errcode='P0002'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,p_ledger_id);
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.work_item_id=v_work.id and rel.organization_id=v_work.organization_id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind='owner_attested' or
        (rel.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table
            and proof.source_id=rel.source_id
        )))
  ) then
    raise exception 'Current exact Ledger custody not proven.'
      using errcode='42501';
  end if;
  select * into v_latest from atlas.work_execution_results r
    where r.work_item_id=v_work.id and r.organization_id=v_work.organization_id
    order by r.reported_at desc,r.id desc limit 1;
  if v_latest.id is not null then
    select a.assignee_canonical_person_id into v_person
    from atlas.work_allocations a
    where a.id=v_latest.responsible_allocation_id
      and a.work_item_id=v_work.id;
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','native_ledger_blocker_owner_inspection_v1',
    'workItemId',v_work.id,'ledgerId',p_ledger_id,
    'latestResultKind',v_latest.result_kind,
    'latestResultId',v_latest.id,
    'latestResultAt',v_latest.reported_at,
    'responsiblePersonId',v_person,
    'routingState',case
      when v_work.work_state='open' and v_latest.result_kind='blocked'
        then 'unresolved_owner_review' else 'no_current_blocker' end,
    'blockerReason',case
      when v_work.work_state='open' and v_latest.result_kind='blocked'
        then nullif(btrim(v_latest.payload->>'blockerReason'),'') else null end,
    'notificationSentProven',false,
    'ownerReadReceiptProven',false,
    'independentHandoffCreated',false);
end
$function$;

revoke all on function atlas.owner_native_ledger_blocker_detail_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function atlas.owner_native_ledger_blocker_detail_self_api_v1(uuid,uuid)
  to authenticated;

-- Native institutional Work with a real accepted assignment is not silently
-- erased. A safe owner void removes it from active work while preserving its
-- source, accepted responsibility and dated-plan historical evidence.
create or replace function atlas.native_today_work_void_preflight_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_owner uuid;
  v_impact jsonb;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_applicable boolean:=false;
  v_safe boolean:=false;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null then
    raise exception 'Signed-in owner, Work and exact Ledger required.'
      using errcode='42501';
  end if;
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then raise exception 'Original Work missing.'
    using errcode='P0002'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,p_ledger_id);
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=v_work.organization_id
      and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and rel.evidence_kind='owner_attested'
  ) then raise exception 'Work is not source-proven for the exact native Ledger.'
    using errcode='42501'; end if;

  v_applicable:=v_work.metadata->>'sourceContract'='today_native_ledger_work_v1'
    and v_work.created_by_user_id=auth.uid();
  if not v_applicable then
    return jsonb_build_object('ok',true,
      'contractVersion','native_today_work_void_preflight_v1',
      'workItemId',v_work.id,'applies',false,'eligible',false);
  end if;
  v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.allocation_role='responsible'
      and a.state='active' limit 1;
  select * into v_plan from atlas.work_execution_plans p
    where p.work_item_id=v_work.id and p.plan_state='active' limit 1;

  v_safe:=v_work.work_state='open'
    and coalesce(jsonb_array_length(v_impact->'requirements'),1)=0
    and coalesce(jsonb_array_length(v_impact->'relations'),1)=0
    and coalesce(jsonb_array_length(v_impact->'pendingOfferIds'),1)=0
    and coalesce(jsonb_array_length(v_impact->'projectionIds'),1)=0
    and coalesce(jsonb_array_length(v_impact->'executionResultIds'),1)=0
    and not exists (
      select 1 from atlas.work_time_contracts t
      where t.work_item_id=v_work.id and t.contract_state='active'
        and t.source_kind<>'owner_authored_date_only_deadline'
    )
    and v_allocation.id is not null
    and v_allocation.assignee_membership_id is null
    and v_allocation.establishment_basis_kind='delegated_under_standing_scope'
    and v_allocation.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    and v_plan.id is not null and v_plan.assignee_membership_id is null
    and v_plan.responsible_allocation_id=v_allocation.id
    and v_plan.metadata->>'source'='today_native_ledger_work_v1';
  return jsonb_build_object('ok',true,
    'contractVersion','native_today_work_void_preflight_v1',
    'workItemId',v_work.id,'ledgerId',p_ledger_id,
    'applies',true,'eligible',v_safe,
    'state',case when v_safe then 'eligible_for_governed_void'
      else 'protected_history_or_other_dependency_requires_review' end,
    'permanentErasureAllowed',false,
    'reversibleFromHistory',false,'workerReadProven',false);
end
$function$;

create or replace function atlas.owner_void_native_today_work_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_preflight jsonb;
  v_plan atlas.work_execution_plans%rowtype;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_void_plan uuid;
  v_cancelled_contract_count integer:=0;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null
    or v_reason is null or length(v_reason) not between 12 and 1200 then
    raise exception 'Owner must provide exact Work, Ledger and substantive void reason.'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.plan:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Original Work missing.'
    using errcode='P0002'; end if;
  v_preflight:=atlas.native_today_work_void_preflight_self_api_v1(
    p_work_item_id,p_ledger_id);
  if v_preflight->>'applies'<>'true' or v_preflight->>'eligible'<>'true' then
    raise exception 'Protected or unrelated Work cannot be erased or voided here.'
      using errcode='23514';
  end if;
  select * into v_plan from atlas.work_execution_plans
    where work_item_id=v_work.id and plan_state='active' for update;
  if v_plan.id is null then
    raise exception 'Exact Person Day plan changed; refresh.' using errcode='40001';
  end if;

  update atlas.work_time_contracts
    set contract_state='cancelled',superseded_at=now(),updated_at=now(),
        metadata=metadata||jsonb_build_object(
          'ownerVoidReason',v_reason,'ownerVoidedAt',now())
    where work_item_id=v_work.id and contract_state='active'
      and source_kind='owner_authored_date_only_deadline';
  get diagnostics v_cancelled_contract_count=row_count;

  update atlas.work_execution_plans
    set plan_state='withdrawn',plan_reason=v_reason,
        metadata=metadata||jsonb_build_object(
          'ownerVoidedAt',now(),'ownerVoidReason',v_reason)
    where id=v_plan.id and plan_state='active';
  if not found then raise exception 'Work day plan changed during void.'
    using errcode='40001'; end if;
  v_void_plan:=v_plan.id;
  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,from_exposure_service_date,
    actor_membership_id,reason,metadata)
  values (v_work.organization_id,v_work.id,v_plan.id,'withdrawn',
    v_plan.planned_service_date,v_plan.exposure_service_date,
    atlas.current_effective_organization_membership_v1(v_work.organization_id),
    v_reason,jsonb_build_object('source','owner_void_native_today_work_v1',
      'ownerId',auth.uid(),'noCompletionFabricated',true));

  update atlas.work_allocations
    set state='released',released_at=now(),release_reason=v_reason,
        updated_at=now()
    where id=v_plan.responsible_allocation_id and state='active'
      and work_item_id=v_work.id;
  if not found then raise exception 'Responsibility changed during void.'
    using errcode='40001'; end if;
  update atlas.work_items
    set work_state='cancelled',cancelled_at=now(),
      updated_at=now(),
      metadata=metadata||jsonb_build_object(
        'voidContract','owner_void_native_today_work_v1',
        'ownerVoidReason',v_reason,'ownerVoidedAt',now(),
        'preserveAssignedPersonAndPlanHistory',true)
    where id=v_work.id and work_state='open';
  if not found then raise exception 'Work state changed during void.'
    using errcode='40001'; end if;
  return jsonb_build_object('ok',true,
    'contractVersion','native_today_work_owner_void_v1',
    'workItemId',v_work.id,'ledgerId',p_ledger_id,'workState','cancelled',
    'planId',v_void_plan,'cancelledTimeContracts',v_cancelled_contract_count,
    'permanentlyDeleted',false,'historyPreserved',true,
    'workerCompletionRecorded',false,'activeWorkRemoved',true);
end
$function$;

revoke all on function atlas.native_today_work_void_preflight_self_api_v1(uuid,uuid)
  from public,anon;
revoke all on function atlas.owner_void_native_today_work_self_api_v1(uuid,uuid,text)
  from public,anon;
grant execute on function atlas.native_today_work_void_preflight_self_api_v1(uuid,uuid)
  to authenticated;
grant execute on function atlas.owner_void_native_today_work_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.delete_unlinked_personal_task_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.delete_unlinked_personal_task_self_api_v1(uuid)
  to authenticated;

revoke all on function atlas.owner_create_native_ledger_today_work_self_api_v1(
  uuid,uuid,uuid,text,date,date,text,boolean) from public,anon;
grant execute on function atlas.owner_create_native_ledger_today_work_self_api_v1(
  uuid,uuid,uuid,text,date,date,text,boolean) to authenticated;
revoke all on function atlas.connected_person_company_work_day_self_api_v1(date)
  from public,anon;
grant execute on function atlas.connected_person_company_work_day_self_api_v1(date)
  to authenticated;

commit;
