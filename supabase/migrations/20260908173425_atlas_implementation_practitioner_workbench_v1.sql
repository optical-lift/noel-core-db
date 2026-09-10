begin;

create table if not exists atlas.implementation_practitioners (
  human_user_id uuid primary key references auth.users(id) on delete restrict,
  status text not null default 'active' check (status in ('active','suspended','ended')),
  authorized_at timestamptz not null default now(),
  ended_at timestamptz,
  authorization_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(authorization_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status='ended' and ended_at is not null) or (status<>'ended' and ended_at is null))
);
comment on table atlas.implementation_practitioners is
  'Atlas-side authority registry for humans permitted to enter the practitioner implementation Workbench. This is vendor-side authority and creates no relationship, membership, permission, or authority inside any client Organization.';

alter table atlas.implementation_practitioners enable row level security;
revoke all on table atlas.implementation_practitioners from public, anon, authenticated;
grant select, insert, update, delete on table atlas.implementation_practitioners to service_role;

create or replace function atlas.implementation_practitioner_authorized_self_v1()
returns boolean
language sql stable security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select auth.uid() is not null and exists (
    select 1 from atlas.implementation_practitioners p
    where p.human_user_id=auth.uid() and p.status='active'
  );
$function$;

create or replace function atlas.implementation_workbench_self_api_v1()
returns jsonb
language sql stable security definer
set search_path=pg_catalog,atlas,auth
as $function$
  with allowed as (
    select atlas.implementation_practitioner_authorized_self_v1() as ok
  ), cases as (
    select
      c.id,
      c.state,
      c.opened_at,
      p.starting_label,
      p.payment_option,
      p.setup_contract_amount_cents,
      p.monthly_ledger_unit_price_cents,
      p.purchased_at,
      exists (
        select 1 from atlas.implementation_case_participants cp
        where cp.implementation_case_id=c.id
          and cp.relationship_kind='setup_sponsor' and cp.active
      ) as has_setup_sponsor,
      (select count(*) from atlas.ledger_entitlements le where le.implementation_case_id=c.id) as entitlement_count,
      (select count(*) from atlas.ledger_entitlements le where le.implementation_case_id=c.id and le.state='activated') as activated_entitlement_count,
      exists (
        select 1 from atlas.implementation_case_participants cp
        where cp.implementation_case_id=c.id
          and cp.relationship_kind='practitioner' and cp.active
          and cp.human_user_id=auth.uid()
      ) as assigned_to_me,
      exists (
        select 1 from atlas.implementation_case_participants cp
        where cp.implementation_case_id=c.id
          and cp.relationship_kind='practitioner' and cp.active
      ) as has_practitioner
    from atlas.implementation_cases c
    join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
    where c.state not in ('closed','cancelled')
  )
  select case when not (select ok from allowed) then
    jsonb_build_object('ok',false,'code','practitioner_authority_required','items','[]'::jsonb)
  else jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_workbench_self_api_v1',
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'implementationCaseId',id,
        'state',state,
        'startingLabel',starting_label,
        'paymentOption',payment_option,
        'setupContractAmountCents',setup_contract_amount_cents,
        'monthlyLedgerUnitPriceCents',monthly_ledger_unit_price_cents,
        'purchasedAt',purchased_at,
        'openedAt',opened_at,
        'hasSetupSponsor',has_setup_sponsor,
        'ledgerEntitlementCount',entitlement_count,
        'activatedLedgerEntitlementCount',activated_entitlement_count,
        'assignedToMe',assigned_to_me,
        'hasPractitioner',has_practitioner
      ) order by purchased_at desc,id)
      from cases
    ),'[]'::jsonb)
  ) end;
$function$;

create or replace function atlas.claim_implementation_case_self_api_v1(p_implementation_case_id uuid)
returns jsonb
language plpgsql security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_participant_id uuid;
  v_other uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;
  if not exists (select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id and c.state not in ('closed','cancelled')) then
    raise exception 'Open implementation case not found.' using errcode='23503';
  end if;

  select cp.human_user_id into v_other
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner' and cp.active
  limit 1;

  if v_other is not null and v_other<>v_uid then
    raise exception 'Implementation case already has an active practitioner.' using errcode='23505';
  end if;

  select cp.id into v_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner' and cp.active and cp.human_user_id=v_uid
  limit 1;

  if v_participant_id is null then
    insert into atlas.implementation_case_participants(
      implementation_case_id,human_user_id,relationship_kind,active,started_at,basis,metadata
    ) values(
      p_implementation_case_id,v_uid,'practitioner',true,now(),
      jsonb_build_object('source','claim_implementation_case_self_api_v1'),
      jsonb_build_object('vendorSideAuthority',true)
    ) returning id into v_participant_id;
  end if;

  update atlas.implementation_cases
  set state=case when state='ready_for_practitioner' then 'in_implementation' else state end,
      updated_at=now()
  where id=p_implementation_case_id;

  return jsonb_build_object('ok',true,'implementationCaseId',p_implementation_case_id,'practitionerParticipantId',v_participant_id);
end;
$function$;

create or replace function atlas.implementation_case_self_api_v1(p_implementation_case_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required');
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_case_self_api_v1',
    'case',jsonb_build_object(
      'id',c.id,'state',c.state,'openedAt',c.opened_at,
      'purchase',jsonb_build_object(
        'id',p.id,'startingLabel',p.starting_label,'paymentOption',p.payment_option,
        'setupContractAmountCents',p.setup_contract_amount_cents,
        'monthlyLedgerUnitPriceCents',p.monthly_ledger_unit_price_cents,
        'purchasedAt',p.purchased_at,'purchaseState',p.purchase_state
      ),
      'participants',coalesce((select jsonb_agg(jsonb_build_object(
        'id',cp.id,'relationshipKind',cp.relationship_kind,'active',cp.active,
        'verifiedAt',cp.verified_at,'startedAt',cp.started_at,
        'isMe',cp.human_user_id=auth.uid()
      ) order by cp.started_at,cp.id) from atlas.implementation_case_participants cp where cp.implementation_case_id=c.id),'[]'::jsonb),
      'ledgerEntitlements',coalesce((select jsonb_agg(jsonb_build_object(
        'id',le.id,'number',le.entitlement_number,'state',le.state,
        'priceClass',le.price_class,'setupPriceCents',le.setup_price_cents,
        'monthlyPriceCents',le.monthly_price_cents,'recurringStartsAt',le.recurring_starts_at,
        'binding',(
          select jsonb_build_object(
            'id',b.id,'state',b.state,'organizationId',b.organization_id,
            'organizationUnitId',b.organization_unit_id,'boundAt',b.bound_at,'activatedAt',b.activated_at
          ) from atlas.ledger_entitlement_bindings b
          where b.ledger_entitlement_id=le.id and b.ended_at is null limit 1
        )
      ) order by le.entitlement_number) from atlas.ledger_entitlements le where le.implementation_case_id=c.id),'[]'::jsonb)
    )
  ) into v_result
  from atlas.implementation_cases c
  join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
  where c.id=p_implementation_case_id;

  return coalesce(v_result,jsonb_build_object('ok',false,'code','case_not_found'));
end;
$function$;

revoke all on function atlas.implementation_practitioner_authorized_self_v1() from public,anon;
revoke all on function atlas.implementation_workbench_self_api_v1() from public,anon;
revoke all on function atlas.claim_implementation_case_self_api_v1(uuid) from public,anon;
revoke all on function atlas.implementation_case_self_api_v1(uuid) from public,anon;
grant execute on function atlas.implementation_practitioner_authorized_self_v1() to authenticated,service_role;
grant execute on function atlas.implementation_workbench_self_api_v1() to authenticated,service_role;
grant execute on function atlas.claim_implementation_case_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.implementation_case_self_api_v1(uuid) to authenticated,service_role;

commit;