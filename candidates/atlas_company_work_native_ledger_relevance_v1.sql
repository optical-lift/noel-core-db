-- ATLAS BUILD 1/5 -- CANDIDATE ONLY, NOT RELEASED
-- Source owner: optical-lift/noel-core-db (atlas_ lane).
-- Promotion requires canonical timestamped migration, disposable clone tests,
-- authorization review and protected manual database release.
-- Existing Company Work is never backfilled or reassigned by this candidate.

create table if not exists atlas.company_work_native_ledger_relevance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  relation_kind text not null default 'serves_purpose'
    check (relation_kind = 'serves_purpose'),
  evidence_basis jsonb not null
    check (jsonb_typeof(evidence_basis) = 'object'
      and evidence_basis->>'evidenceClass' in ('owner_attestation','source_binding')
      and nullif(btrim(evidence_basis->>'sourceRef'),'') is not null),
  attribution_state text not null default 'active'
    check (attribution_state in ('active','withdrawn')),
  established_by_person_id uuid not null references reality.entities(id) on delete restrict,
  established_at timestamptz not null default now(),
  withdrawn_by_person_id uuid references reality.entities(id) on delete restrict,
  withdrawn_at timestamptz,
  withdrawal_reason text,
  check ((attribution_state='active' and withdrawn_at is null
       and withdrawn_by_person_id is null and withdrawal_reason is null)
    or (attribution_state='withdrawn' and withdrawn_at is not null
       and withdrawn_by_person_id is not null and nullif(btrim(withdrawal_reason),'') is not null))
);
create unique index if not exists company_work_native_ledger_relevance_active_once_v1
  on atlas.company_work_native_ledger_relevance(work_item_id,ledger_id)
  where attribution_state='active';
create index if not exists company_work_native_ledger_relevance_scope_v1
  on atlas.company_work_native_ledger_relevance(organization_id,ledger_id,work_item_id)
  where attribution_state='active';

create or replace function atlas.guard_company_work_native_ledger_relevance_v1()
returns trigger language plpgsql security definer
set search_path to 'pg_catalog','atlas','ledger' as $fn$
begin
  if tg_op='DELETE' then
    raise exception 'Ledger attribution history is not deletable.' using errcode='42501';
  end if;
  if tg_op='UPDATE' then
    if (new.id,new.organization_id,new.work_item_id,new.ledger_id,
        new.relation_kind,new.evidence_basis,new.established_by_person_id,new.established_at)
       is distinct from
       (old.id,old.organization_id,old.work_item_id,old.ledger_id,
        old.relation_kind,old.evidence_basis,old.established_by_person_id,old.established_at)
      or old.attribution_state <> 'active' or new.attribution_state <> 'withdrawn' then
      raise exception 'Only an active attribution can be withdrawn; identity and evidence are immutable.'
        using errcode='42501';
    end if;
  end if;
  if not exists (select 1 from atlas.work_items w
                 where w.id=new.work_item_id and w.organization_id=new.organization_id) then
    raise exception 'Work does not belong to the named organization.' using errcode='23514';
  end if;
  if not exists (
    select 1 from ledger.ledgers nl
    join atlas.ledgers ll on ll.id=nl.id and ll.status='active'
    join atlas.ledger_organization_participations lop
      on lop.ledger_id=ll.id and lop.organization_id=new.organization_id
     and lop.status='active' and lop.ended_at is null
     and lop.participation_kind in ('governing','operating')
    where nl.id=new.ledger_id and nl.ledger_state='active' and nl.retired_at is null
  ) then
    raise exception 'Native Ledger is not an active participant in the Work organization.'
      using errcode='23514';
  end if;
  return new;
end;
$fn$;
drop trigger if exists company_work_native_ledger_relevance_guard_v1
  on atlas.company_work_native_ledger_relevance;
create trigger company_work_native_ledger_relevance_guard_v1
before insert or update or delete on atlas.company_work_native_ledger_relevance
for each row execute function atlas.guard_company_work_native_ledger_relevance_v1();

create or replace function atlas.company_work_native_ledger_owner_self_v1(
  p_organization_id uuid,p_ledger_id uuid)
returns uuid language plpgsql stable security definer
set search_path to 'pg_catalog','atlas','ledger','auth' as $fn$
declare
  v_person uuid;
  v_principal uuid;
  v_native_principal uuid;
  v_org_principal uuid;
  v_primary_ledger uuid;
  v_primary_count integer;
begin
  if auth.uid() is null or atlas.reality_access_self_api_v1()->>'state' is distinct from 'ready' then
    raise exception 'Current authorized Atlas session required.' using errcode='42501';
  end if;
  select atlas.current_person_id_v1(),atlas.current_principal_id_v1()
    into v_person,v_principal;
  if v_person is null or v_principal is null then
    raise exception 'Canonical Person and Principal required.' using errcode='42501';
  end if;
  if not exists (
    select 1 from atlas.ledger_organization_participations lop
    join atlas.ledgers al on al.id=lop.ledger_id and al.status='active'
    join ledger.ledgers nl on nl.id=al.id
    where lop.ledger_id=p_ledger_id and lop.organization_id=p_organization_id
      and lop.status='active' and lop.ended_at is null
      and lop.participation_kind in ('governing','operating')
      and nl.ledger_state='active' and nl.retired_at is null
  ) then
    raise exception 'No current native Ledger participation in this organization.' using errcode='42501';
  end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  select c.principal_id into v_native_principal
    from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;
  select count(*)::integer
    into v_primary_count
  from atlas.ledger_organization_participations lop
  join atlas.ledgers al on al.id=lop.ledger_id and al.status='active'
  where lop.organization_id=p_organization_id and lop.status='active'
    and lop.ended_at is null and lop.participation_kind='governing'
    and lop.is_compatibility_primary;
  if v_primary_count<>1 then
    raise exception 'Organization governing Ledger is unresolved.' using errcode='42501';
  end if;
  select lop.ledger_id into v_primary_ledger
  from atlas.ledger_organization_participations lop
  where lop.organization_id=p_organization_id and lop.status='active'
    and lop.ended_at is null and lop.participation_kind='governing'
    and lop.is_compatibility_primary
  limit 1;
  select c.principal_id into v_org_principal
    from atlas.capability_root_authority_context_self_v1(v_primary_ledger) c;
  if v_principal is distinct from v_native_principal
     or v_principal is distinct from v_org_principal then
    raise exception 'Both native Ledger and institution root authority required.' using errcode='42501';
  end if;
  return v_person;
end;
$fn$;

create or replace function atlas.establish_company_work_native_ledger_relevance_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid,p_evidence_basis jsonb)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','atlas','ledger','auth' as $fn$
declare
  v_org uuid;
  v_person uuid;
  v_id uuid;
  v_existing boolean := false;
begin
  select w.organization_id into v_org
  from atlas.work_items w where w.id=p_work_item_id;
  if v_org is null then
    raise exception 'Work unavailable.' using errcode='42501';
  end if;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(v_org,p_ledger_id);
  if jsonb_typeof(p_evidence_basis) is distinct from 'object'
     or p_evidence_basis->>'evidenceClass' not in ('source_binding','owner_attestation')
     or nullif(btrim(p_evidence_basis->>'sourceRef'),'') is null then
    raise exception 'Explicit evidence class and source reference required.' using errcode='22023';
  end if;
  insert into atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_basis,established_by_person_id)
  values (v_org,p_work_item_id,p_ledger_id,p_evidence_basis,v_person)
  on conflict (work_item_id,ledger_id) where attribution_state='active'
  do nothing returning id into v_id;
  if v_id is null then
    v_existing:=true;
    select id into v_id from atlas.company_work_native_ledger_relevance
    where work_item_id=p_work_item_id and ledger_id=p_ledger_id
      and attribution_state='active';
  end if;
  return jsonb_build_object('workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'attributionId',v_id,'alreadyEstablished',v_existing,
    'authority','both_roots_plus_native_seat','evidenceClass',p_evidence_basis->>'evidenceClass');
end;
$fn$;

create or replace function atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(
  p_attribution_id uuid,p_reason text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','atlas','ledger','auth' as $fn$
declare v_link atlas.company_work_native_ledger_relevance%rowtype; v_person uuid;
begin
  select * into v_link from atlas.company_work_native_ledger_relevance
  where id=p_attribution_id and attribution_state='active' for update;
  if v_link.id is null then raise exception 'Active attribution unavailable.' using errcode='42501'; end if;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(v_link.organization_id,v_link.ledger_id);
  if nullif(btrim(p_reason),'') is null then
    raise exception 'Withdrawal reason required.' using errcode='22023';
  end if;
  update atlas.company_work_native_ledger_relevance
    set attribution_state='withdrawn',withdrawn_at=now(),
        withdrawn_by_person_id=v_person,withdrawal_reason=btrim(p_reason)
  where id=v_link.id;
  return jsonb_build_object('attributionId',v_link.id,'workItemId',v_link.work_item_id,
    'ledgerId',v_link.ledger_id,'attributionState','withdrawn');
end;
$fn$;

create or replace function atlas.company_work_native_ledger_scope_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 200,
  p_after_work_item_id uuid default null)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','atlas','ledger','auth' as $fn$
declare v_person uuid; v_rows jsonb; v_unknown bigint;
begin
  v_person:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  if p_limit is null or p_limit<1 or p_limit>500 then
    raise exception 'Limit must be 1..500.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.work_item_id),'[]'::jsonb)
  into v_rows from (
    select w.id as work_item_id,w.organization_id,w.organization_unit_id,
      w.work_state,w.source_object_type,w.source_object_id,
      r.id as attribution_id,r.evidence_basis,r.established_at
    from atlas.company_work_native_ledger_relevance r
    join atlas.work_items w on w.id=r.work_item_id and w.organization_id=r.organization_id
    where r.organization_id=p_organization_id and r.ledger_id=p_ledger_id
      and r.attribution_state='active'
      and (p_after_work_item_id is null or w.id>p_after_work_item_id)
    order by w.id limit p_limit
  ) x;
  select count(*) into v_unknown from atlas.work_items w
  where w.organization_id=p_organization_id
    and not exists (
      select 1 from atlas.company_work_native_ledger_relevance r
      where r.work_item_id=w.id and r.attribution_state='active'
    );
  return jsonb_build_object('contractVersion','company_work_native_ledger_scope_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'scopeRule','explicit_attribution_only',
    'items',v_rows,'organizationUnattributedWorkCount',v_unknown,
    'otherLedgerAttributionDoesNotProveExclusion',true);
end;
$fn$;

alter table atlas.company_work_native_ledger_relevance enable row level security;
revoke all on atlas.company_work_native_ledger_relevance from public,anon,authenticated;
revoke all on function atlas.company_work_native_ledger_owner_self_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function atlas.guard_company_work_native_ledger_relevance_v1() from public,anon,authenticated;
revoke all on function atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(uuid,text) from public,anon,authenticated;
revoke all on function atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid) from public,anon,authenticated;
grant execute on function atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb) to authenticated;
grant execute on function atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(uuid,text) to authenticated;
grant execute on function atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid) to authenticated;
