begin;

-- Build 5 principal-worker crossover: an organization owner is a legitimate
-- Person who can self-adopt, see and complete existing Company Work.
-- No employee seat, new recurring requirement, new Work item, or fake plan.
-- Only the exact open existing Work and current native Ledger may be used.

create or replace function atlas.self_adopt_existing_company_work_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_person uuid;
  v_membership uuid;
  v_work atlas.work_items%rowtype;
  v_contract text:='ordinary_company_work_worker_attestation_v1';
  v_receipt jsonb;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if auth.uid() is null or p_work_item_id is null
    or v_reason is null or length(v_reason) not between 8 and 1200 then
    raise exception 'Exact open Work and self-adoption reason required'
      using errcode='22023';
  end if;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_membership:=atlas.current_effective_organization_membership_v1(
    p_organization_id);
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_membership and m.organization_id=p_organization_id
      and m.person_id=v_person and m.active and m.role='owner'
  ) then
    raise exception 'Current owner self-capacity membership not established'
      using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and organization_id=p_organization_id
    for update;
  if v_work.id is null or v_work.work_state<>'open' then
    raise exception 'Existing open Company Work required' using errcode='23514';
  end if;
  if v_work.source_object_type not in ('personal_dated_task','legacy_task')
    or v_work.source_object_id is null then
    raise exception 'This Work has another source-specific execution contract; generic self-adoption is not permitted'
      using errcode='23514';
  end if;
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=p_organization_id and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind='owner_attested' or
        (rel.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table
            and proof.source_id=rel.source_id)))
  ) then
    raise exception 'Exact Ledger source relevance not proven'
      using errcode='23514';
  end if;
  if exists (select 1 from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.allocation_role='responsible'
      and a.state='active') then
    raise exception 'Work already has a responsible Person; use governed transfer'
      using errcode='23514';
  end if;
  if exists (select 1 from atlas.company_work_initial_responsibility_offers o
    where o.work_item_id=v_work.id and o.offer_state='offered') then
    raise exception 'Resolve the outstanding receiver offer before self-adoption'
      using errcode='23514';
  end if;
  if exists (select 1 from atlas.work_execution_results r
    where r.work_item_id=v_work.id) then
    raise exception 'Previously reported Work requires result adjudication'
      using errcode='23514';
  end if;

  if v_work.result_contract_key is null then
    if not exists (select 1 from atlas.work_result_contract_policies policy
      where policy.contract_key=v_contract and policy.active
        and policy.source_domain='organization'
        and policy.acceptance_mode='worker_attestation') then
      raise exception 'Ordinary self-attestation result contract unavailable'
        using errcode='23514';
    end if;
    insert into atlas.company_work_result_contract_bindings_v1(
      organization_id,ledger_id,work_item_id,actor_person_id,
      actor_membership_id,contract_key,reason
    ) values (
      p_organization_id,p_ledger_id,v_work.id,v_person,v_membership,
      v_contract,'Owner self-adopts existing Work: '||v_reason
    );
    update atlas.work_items
      set result_contract_key=v_contract,updated_at=now()
      where id=v_work.id and result_contract_key is null and work_state='open';
  elsif v_work.result_contract_key<>v_contract then
    raise exception 'Existing result contract requires its own governed reporting path'
      using errcode='23514';
  end if;

  v_receipt:=atlas.set_company_work_responsibility_with_basis_internal_v2(
    v_work.id,v_membership,v_membership,'self_adoption',
    jsonb_build_object(
      'sourceKind','owner_self_adoption_existing_company_work',
      'sourceId',v_work.id,'nativeLedgerId',p_ledger_id,
      'selfPersonId',v_person,'sourceObjectId',v_work.source_object_id),
    v_reason,jsonb_build_object(
      'source','self_adopt_existing_company_work_owner_self_api_v1',
      'selfAdoption',true,'noNewWorkCreated',true
    ));
  if v_receipt->>'state' not in ('established','unchanged') then
    raise exception 'Self-adopted canonical responsibility not established'
      using errcode='23514';
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','owner_self_adopt_existing_company_work_v1',
    'workItemId',v_work.id,'allocationId',v_receipt->>'allocationId',
    'responsiblePersonId',v_person,'resultContractKey',v_contract,
    'newWorkCreated',false,'employeeSeatRequired',false,
    'planCreated',false,'sourceHistoryPreserved',true);
end
$fn$;
revoke all on function atlas.self_adopt_existing_company_work_owner_self_api_v1(
  uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function atlas.self_adopt_existing_company_work_owner_self_api_v1(
  uuid,uuid,uuid,text) to authenticated;

create or replace function atlas.self_responsible_company_work_today_self_api_v1(
  p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare v_person uuid:=atlas.current_person_id_v1(); v_items jsonb;
begin
  if auth.uid() is null or v_person is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_limit<1 or p_limit>100 then
    raise exception 'Limit must be between 1 and 100' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',w.id,'organizationId',w.organization_id,
    'organizationName',org.name,'title',w.title,'instructions',w.instructions,
    'workState',w.work_state,'allocationId',a.id,
    'allocationRole','responsible',
    'sourceObjectType',w.source_object_type,
    'sourceObjectId',w.source_object_id,
    'sourceDate',w.metadata->>'sourceTaskDate',
    'sourceDateIsNotInstitutionalSchedule',true,
    'resultContractKey',w.result_contract_key,
    'establishmentBasisKind',a.establishment_basis_kind,
    'assigneePersonId',v_person,
    'completionEnabled',w.result_contract_key=
      'ordinary_company_work_worker_attestation_v1'
  ) order by a.allocated_at desc,w.id),'[]'::jsonb) into v_items
  from (
    select a.* from atlas.work_allocations a
    join atlas.organization_memberships m
      on m.id=a.assignee_membership_id and m.organization_id=a.organization_id
      and m.person_id=v_person and m.active
    where a.state='active' and a.allocation_role='responsible'
      and a.establishment_basis_kind='self_adoption'
      and a.establishment_basis->>'sourceKind'=
        'owner_self_adoption_existing_company_work'
    order by a.allocated_at desc,a.id limit p_limit
  ) a
  join atlas.work_items w on w.id=a.work_item_id
    and w.organization_id=a.organization_id and w.work_state='open'
  join atlas.organizations org on org.id=w.organization_id;
  return jsonb_build_object('ok',true,
    'contractVersion','self_responsible_company_work_today_v1',
    'personId',v_person,'items',v_items,
    'truthBoundary',jsonb_build_object(
      'workSourceNotDuplicated',true,
      'sourceDateNotManagerSchedule',true,
      'onlyMyActiveSelfAdoptedResponsibility',true,
      'notAnEmployeeDay',true));
end
$fn$;
revoke all on function atlas.self_responsible_company_work_today_self_api_v1(
  integer) from public,anon,authenticated,service_role;
grant execute on function atlas.self_responsible_company_work_today_self_api_v1(
  integer) to authenticated;

create or replace function atlas.report_self_responsible_company_work_self_api_v1(
  p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_person uuid:=atlas.current_person_id_v1();
  v_uid uuid:=auth.uid();
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_institutional uuid;
begin
  if v_uid is null or v_person is null then
    raise exception 'Signed-in canonical Person required' using errcode='42501';
  end if;
  if p_work_item_id is null or v_kind not in ('completed','partial','blocked','unable')
    or v_key is null or length(v_key)>160
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Exact Work, supported result, idempotency and object payload required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id for update;
  if v_work.id is null then
    raise exception 'Company Work not found' using errcode='P0002';
  end if;
  select a.* into v_allocation
  from atlas.work_allocations a
  join atlas.organization_memberships m
    on m.id=a.assignee_membership_id and m.organization_id=a.organization_id
      and m.person_id=v_person and m.active and m.user_id=v_uid
  where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
    and a.state in ('active','completed') and a.allocation_role='responsible'
    and a.establishment_basis_kind='self_adoption'
    and a.establishment_basis->>'sourceKind'=
      'owner_self_adoption_existing_company_work'
    and a.establishment_basis->>'selfPersonId'=v_person::text
  order by a.allocated_at desc limit 1;
  if v_allocation.id is null then
    raise exception 'Caller is not the exact self-adopted responsible Person'
      using errcode='42501';
  end if;
  select * into v_existing from atlas.work_execution_results r
    where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id or v_existing.result_kind<>v_kind
      or v_existing.responsible_allocation_id<>v_allocation.id
      or v_existing.reported_by_user_id is distinct from v_uid
      or v_existing.payload is distinct from p_payload then
      raise exception 'Result idempotency key collides' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'workItemId',v_work.id,
      'resultId',v_existing.id,'workState',v_work.work_state);
  end if;
  if v_work.work_state<>'open' or v_allocation.state<>'active' then
    raise exception 'Already terminal Work cannot be reported again' using errcode='23514';
  end if;
  if v_work.result_contract_key<>'ordinary_company_work_worker_attestation_v1'
    or not exists (
      select 1 from atlas.work_result_contract_policies policy
      where policy.contract_key=v_work.result_contract_key and policy.active
        and policy.acceptance_mode='worker_attestation'
        and policy.source_domain='organization'
    ) then
    raise exception 'This Work does not permit an ordinary self result'
      using errcode='23514';
  end if;
  select ipr.id into v_institutional
  from atlas.institutional_person_records ipr
  join atlas.organization_memberships m
    on m.institutional_person_record_id=ipr.id and m.id=v_allocation.assignee_membership_id
  where ipr.organization_id=v_work.organization_id and ipr.person_id=v_person
    and ipr.status='active';
  if v_institutional is null then
    raise exception 'Exact institutional Person attribution unavailable'
      using errcode='23514';
  end if;
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values (
    v_work.organization_id,v_work.id,v_allocation.id,
    v_uid,v_allocation.assignee_membership_id,v_institutional,
    v_kind,v_work.result_contract_key,v_key,p_payload,
    jsonb_build_object('source','report_self_responsible_company_work_self_api_v1',
      'selfResponsiblePersonId',v_person,'employeeSeatRequired',false,
      'workerDayProjectionRequired',false,'ownerSelfAdoption',true)
  ) returning * into v_result;
  if v_kind='completed' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,
      decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values(
      v_work.organization_id,v_work.id,v_result.id,
      'accepted','self_responsible_person_attestation','organization',
      jsonb_build_object('responsibleAllocationId',v_allocation.id,
        'reportedByCanonicalPersonId',v_person,
        'resultContractKey',v_work.result_contract_key),
      jsonb_build_object('source','report_self_responsible_company_work_self_api_v1',
        'attestationIsOwnWork',true,'notManagerAcceptance',true)
    ) returning * into v_acceptance;
    update atlas.work_items
      set work_state='completed',completed_at=coalesce(completed_at,now()),
          updated_at=now()
      where id=v_work.id and work_state='open';
    update atlas.work_allocations
      set state='completed',completed_at=coalesce(completed_at,now()),
          updated_at=now()
      where id=v_allocation.id and state='active';
  end if;
  return jsonb_build_object('ok',true,'idempotent',false,
    'contractVersion','self_responsible_company_work_report_v1',
    'workItemId',v_work.id,'resultId',v_result.id,'resultKind',v_kind,
    'acceptanceDecision',v_acceptance.decision,
    'workState',case when v_kind='completed' then 'completed' else 'open' end,
    'employeeSeatRequired',false,'sourceHistoryPreserved',true);
end
$fn$;
revoke all on function atlas.report_self_responsible_company_work_self_api_v1(
  uuid,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function atlas.report_self_responsible_company_work_self_api_v1(
  uuid,text,text,jsonb) to authenticated;

create or replace function public.self_adopt_existing_company_work_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path to ''
as $fn$ select atlas.self_adopt_existing_company_work_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_work_item_id,p_reason) $fn$;
revoke all on function public.self_adopt_existing_company_work_owner_self_api_v1(
  uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.self_adopt_existing_company_work_owner_self_api_v1(
  uuid,uuid,uuid,text) to authenticated;

create or replace function public.self_responsible_company_work_today_self_api_v1(
  p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.self_responsible_company_work_today_self_api_v1(
  p_limit) $fn$;
revoke all on function public.self_responsible_company_work_today_self_api_v1(
  integer) from public,anon,authenticated,service_role;
grant execute on function public.self_responsible_company_work_today_self_api_v1(
  integer) to authenticated;

create or replace function public.report_self_responsible_company_work_self_api_v1(
  p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path to ''
as $fn$ select atlas.report_self_responsible_company_work_self_api_v1(
  p_work_item_id,p_result_kind,p_idempotency_key,p_payload) $fn$;
revoke all on function public.report_self_responsible_company_work_self_api_v1(
  uuid,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.report_self_responsible_company_work_self_api_v1(
  uuid,text,text,jsonb) to authenticated;

commit;
