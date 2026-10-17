-- Atlas Company Work native-Ledger relevance v1 -- pending governed source release.
-- Structural change only. No historic Work attribution or backfill.
-- Evidence classes are independent: owner_attested != source_verified.

create table atlas.company_work_native_ledger_relevance (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  relation_kind text not null default 'serves_purpose'
    check (relation_kind = 'serves_purpose'),
  evidence_kind text not null
    check (evidence_kind in ('owner_attested','source_verified')),
  -- Human judgment is not source proof.
  attestation_source_ref text,
  attestation_reason text,
  -- Source proof is server-derived, never accepted from client JSON.
  source_schema text,
  source_table text,
  source_id uuid,
  verified_at timestamptz,
  attribution_state text not null default 'active'
    check (attribution_state in ('active','withdrawn')),
  established_by_person_id uuid not null references reality.entities(id) on delete restrict,
  established_at timestamptz not null default now(),
  withdrawn_by_person_id uuid references reality.entities(id) on delete restrict,
  withdrawn_at timestamptz,
  withdrawal_reason text,
  constraint company_work_relevance_evidence_separation_v1 check (
    (evidence_kind='owner_attested'
      and nullif(btrim(attestation_source_ref),'') is not null
      and nullif(btrim(attestation_reason),'') is not null
      and source_schema is null and source_table is null
      and source_id is null and verified_at is null)
    or
    (evidence_kind='source_verified'
      and attestation_source_ref is null and attestation_reason is null
      and source_schema='ledger' and source_table in ('booking_requests','booking_offerings')
      and source_id is not null and verified_at is not null)
  ),
  constraint company_work_relevance_withdrawal_v1 check (
    (attribution_state='active' and withdrawn_at is null
      and withdrawn_by_person_id is null and withdrawal_reason is null)
    or
    (attribution_state='withdrawn' and withdrawn_at is not null
      and withdrawn_by_person_id is not null
      and nullif(btrim(withdrawal_reason),'') is not null)
  )
);

-- Two active evidence classes for one Work/Ledger pair are lawful; neither
-- overwrites the other. There is still only ONE atlas.work_items identity.
create unique index company_work_native_ledger_evidence_active_once_v1
  on atlas.company_work_native_ledger_relevance(work_item_id,ledger_id,evidence_kind)
  where attribution_state='active';
create index company_work_native_ledger_scope_v1
  on atlas.company_work_native_ledger_relevance(organization_id,ledger_id,work_item_id)
  where attribution_state='active';

-- Real native foreign keys; never accept client-supplied proof identifiers.
-- Only two exact source-object kinds are admitted in v1. Other source kinds,
-- including every current legacy farm task, remain UNVERIFIED.
create function atlas.company_work_native_ledger_exact_source_v1(
  p_work_item_id uuid,p_ledger_id uuid)
returns table(source_schema text,source_table text,source_id uuid)
language sql stable security definer set search_path to ''
as $source$
  select 'ledger'::text,'booking_requests'::text,b.id
  from atlas.work_items w
  join ledger.booking_requests b
    on w.source_object_type='ledger_booking_request'
   and w.source_object_id=b.id
  where w.id=p_work_item_id and b.ledger_id=p_ledger_id
  union all
  select 'ledger'::text,'booking_offerings'::text,o.id
  from atlas.work_items w
  join ledger.booking_offerings o
    on w.source_object_type='ledger_booking_offering'
   and w.source_object_id=o.id
  where w.id=p_work_item_id and o.ledger_id=p_ledger_id;
$source$;

create function atlas.guard_company_work_native_ledger_relevance_v1()
returns trigger language plpgsql security definer
set search_path to '' as $guard$
begin
  if tg_op='DELETE' then
    raise exception 'Company Work Ledger relevance history cannot be deleted.'
      using errcode='42501';
  end if;

  if tg_op='UPDATE' then
    if (new.id,new.organization_id,new.work_item_id,new.ledger_id,new.relation_kind,
        new.evidence_kind,new.attestation_source_ref,new.attestation_reason,
        new.source_schema,new.source_table,new.source_id,new.verified_at,
        new.established_by_person_id,new.established_at)
        is distinct from
       (old.id,old.organization_id,old.work_item_id,old.ledger_id,old.relation_kind,
        old.evidence_kind,old.attestation_source_ref,old.attestation_reason,
        old.source_schema,old.source_table,old.source_id,old.verified_at,
        old.established_by_person_id,old.established_at)
       or old.attribution_state <> 'active' or new.attribution_state <> 'withdrawn'
       or new.withdrawn_at is null or new.withdrawn_by_person_id is null
       or nullif(btrim(new.withdrawal_reason),'') is null then
      raise exception 'Only reasoned withdrawal is permitted; source and evidence stay immutable.'
        using errcode='42501';
    end if;
    -- A historic source may now be missing; do not block corrective withdrawal.
    return new;
  end if;

  if not exists (
    select 1 from atlas.work_items w
    where w.id=new.work_item_id and w.organization_id=new.organization_id
  ) then
    raise exception 'Source Work and Organization mismatch.' using errcode='23514';
  end if;
  if not exists (
    select 1 from ledger.ledgers nl
    join atlas.ledgers al on al.id=nl.id and al.status='active'
    join atlas.ledger_organization_participations lop
      on lop.ledger_id=al.id and lop.organization_id=new.organization_id
      and lop.status='active' and lop.ended_at is null
      and lop.participation_kind in ('governing','operating')
    where nl.id=new.ledger_id and nl.ledger_state='active' and nl.retired_at is null
  ) then
    raise exception 'Ledger is not a current participating native Ledger of the Work institution.'
      using errcode='23514';
  end if;
  if new.evidence_kind='source_verified' and not exists (
    select 1 from atlas.company_work_native_ledger_exact_source_v1(
      new.work_item_id,new.ledger_id) s
    where s.source_schema=new.source_schema and s.source_table=new.source_table
      and s.source_id=new.source_id
  ) then
    raise exception 'No exact native Ledger source FK proves this attribution.'
      using errcode='23514';
  end if;
  return new;
end;
$guard$;

create trigger company_work_native_ledger_relevance_guard_v1
before insert or update or delete on atlas.company_work_native_ledger_relevance
for each row execute function atlas.guard_company_work_native_ledger_relevance_v1();

-- Deliberately conservative initial actor: ROOT owner of both Ledger and
-- governing institutional scope, plus live native seat and valid auth session.
create function atlas.company_work_native_ledger_owner_self_v1(
  p_organization_id uuid,p_ledger_id uuid)
returns uuid language plpgsql stable security definer
set search_path to '' as $authority$
declare
  v_person uuid;
  v_principal uuid;
  v_native_principal uuid;
  v_org_principal uuid;
  v_primary_ledger uuid;
  v_primary_count integer;
begin
  if auth.uid() is null or
     (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready' then
    raise exception 'Current authenticated Atlas session required.' using errcode='42501';
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
    raise exception 'No native Ledger participation in this Organization.'
      using errcode='42501';
  end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  select c.principal_id into v_native_principal
    from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;

  select count(*)::integer into v_primary_count
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
    and lop.is_compatibility_primary limit 1;
  select c.principal_id into v_org_principal
    from atlas.capability_root_authority_context_self_v1(v_primary_ledger) c;
  if v_principal is distinct from v_native_principal
    or v_principal is distinct from v_org_principal then
    raise exception 'Both native and institutional governing authority required.'
      using errcode='42501';
  end if;
  return v_person;
end;
$authority$;

-- The client supplies only its own attestation; never a verification status.
create function atlas.establish_company_work_native_ledger_relevance_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid,p_evidence_basis jsonb)
returns jsonb language plpgsql security definer
set search_path to '' as $attest$
declare v_org uuid;v_person uuid;v_id uuid;v_existing boolean:=false;
begin
  select w.organization_id into v_org
  from atlas.work_items w where w.id=p_work_item_id;
  if v_org is null then raise exception 'Work unavailable.' using errcode='42501'; end if;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(v_org,p_ledger_id);
  if jsonb_typeof(p_evidence_basis) is distinct from 'object'
    or p_evidence_basis->>'evidenceClass' is distinct from 'owner_attestation'
    or nullif(btrim(p_evidence_basis->>'sourceRef'),'') is null
    or nullif(btrim(p_evidence_basis->>'reason'),'') is null then
    raise exception 'Owner attestation requires sourceRef, reason and evidenceClass.'
      using errcode='22023';
  end if;
  insert into atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id)
  values (v_org,p_work_item_id,p_ledger_id,'owner_attested',
    btrim(p_evidence_basis->>'sourceRef'),
    btrim(p_evidence_basis->>'reason'),v_person)
  on conflict (work_item_id,ledger_id,evidence_kind)
    where attribution_state='active'
  do nothing returning id into v_id;
  if v_id is null then
    v_existing:=true;
    select id into v_id from atlas.company_work_native_ledger_relevance
    where work_item_id=p_work_item_id and ledger_id=p_ledger_id
      and evidence_kind='owner_attested' and attribution_state='active';
  end if;
  return jsonb_build_object('workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'attributionId',v_id,'alreadyEstablished',v_existing,
    'evidenceKind','owner_attested','isSourceVerified',false);
end;
$attest$;

-- Verification input is ONLY work+ledger identifiers. The database derives
-- and validates the source FK, withholding source_verified on any mismatch.
create function atlas.verify_company_work_native_ledger_source_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid)
returns jsonb language plpgsql security definer
set search_path to '' as $verify$
declare
  v_org uuid;v_person uuid;v_source record;v_id uuid;v_existing boolean:=false;
begin
  select w.organization_id into v_org
  from atlas.work_items w where w.id=p_work_item_id;
  if v_org is null then raise exception 'Work unavailable.' using errcode='42501'; end if;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(v_org,p_ledger_id);
  select s.source_schema,s.source_table,s.source_id into v_source
  from atlas.company_work_native_ledger_exact_source_v1(p_work_item_id,p_ledger_id) s;
  if v_source.source_id is null then
    raise exception 'No allowlisted source FK proves this Ledger attribution.'
      using errcode='23514';
  end if;
  insert into atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    source_schema,source_table,source_id,verified_at,established_by_person_id)
  values (v_org,p_work_item_id,p_ledger_id,'source_verified',
    v_source.source_schema,v_source.source_table,v_source.source_id,now(),v_person)
  on conflict (work_item_id,ledger_id,evidence_kind)
    where attribution_state='active'
  do nothing returning id into v_id;
  if v_id is null then
    v_existing:=true;
    select id into v_id from atlas.company_work_native_ledger_relevance
    where work_item_id=p_work_item_id and ledger_id=p_ledger_id
      and evidence_kind='source_verified' and attribution_state='active';
  end if;
  return jsonb_build_object('workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'attributionId',v_id,'alreadyEstablished',v_existing,
    'evidenceKind','source_verified','sourceTable',v_source.source_table,
    'sourceId',v_source.source_id);
end;
$verify$;

create function atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(
  p_attribution_id uuid,p_reason text)
returns jsonb language plpgsql security definer
set search_path to '' as $withdraw$
declare v_link atlas.company_work_native_ledger_relevance%rowtype; v_person uuid;
begin
  select * into v_link from atlas.company_work_native_ledger_relevance
  where id=p_attribution_id and attribution_state='active' for update;
  if v_link.id is null then
    raise exception 'Active attribution unavailable.' using errcode='42501';
  end if;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(
    v_link.organization_id,v_link.ledger_id);
  if nullif(btrim(p_reason),'') is null then
    raise exception 'Withdrawal reason required.' using errcode='22023';
  end if;
  update atlas.company_work_native_ledger_relevance
  set attribution_state='withdrawn',withdrawn_at=now(),
      withdrawn_by_person_id=v_person,withdrawal_reason=btrim(p_reason)
  where id=v_link.id;
  return jsonb_build_object('attributionId',v_link.id,
    'workItemId',v_link.work_item_id,'ledgerId',v_link.ledger_id,
    'evidenceKind',v_link.evidence_kind,'attributionState','withdrawn');
end;
$withdraw$;

-- One row PER work ID, including separate evidence records. Historical source
-- verification is rechecked on read; stale proof never counts as current scope.
create function atlas.company_work_native_ledger_scope_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 200,
  p_after_work_item_id uuid default null)
returns jsonb language plpgsql stable security definer
set search_path to '' as $scope$
declare v_person uuid;v_items jsonb;v_unknown bigint;
begin
  v_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if p_limit is null or p_limit<1 or p_limit>500 then
    raise exception 'Limit must be 1..500.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.work_item_id),'[]'::jsonb)
  into v_items from (
    select w.id as work_item_id,w.organization_id,w.organization_unit_id,
      w.work_state,w.source_object_type,w.source_object_id,
      e.evidence_records as evidence,
      e.has_current_scope as has_current_scope
    from atlas.work_items w
    join lateral (
      select
        coalesce(jsonb_agg(jsonb_build_object(
          'attributionId',r.id,'evidenceKind',r.evidence_kind,
          'attestationSourceRef',r.attestation_source_ref,
          'attestationReason',r.attestation_reason,
          'sourceSchema',r.source_schema,'sourceTable',r.source_table,
          'sourceId',r.source_id,'verifiedAt',r.verified_at,
          'currentSourceProof',case when r.evidence_kind='source_verified'
              then s.is_current else null end,
          'establishedByPersonId',r.established_by_person_id,
          'establishedAt',r.established_at)
        order by r.established_at,r.id),'[]'::jsonb) as evidence_records,
        bool_or(r.evidence_kind='owner_attested'
          or (r.evidence_kind='source_verified' and s.is_current))
          as has_current_scope
      from atlas.company_work_native_ledger_relevance r
      cross join lateral (
        select exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            r.work_item_id,r.ledger_id) p
          where p.source_schema=r.source_schema and p.source_table=r.source_table
            and p.source_id=r.source_id
        ) as is_current
      ) s
      where r.work_item_id=w.id and r.organization_id=w.organization_id
        and r.ledger_id=p_ledger_id and r.attribution_state='active'
    ) e on jsonb_array_length(e.evidence_records)>0
    where w.organization_id=p_organization_id
      and (p_after_work_item_id is null or w.id>p_after_work_item_id)
    order by w.id limit p_limit
  ) x;
  select count(*) into v_unknown
  from atlas.work_items w
  where w.organization_id=p_organization_id
    and not exists (
      select 1 from atlas.company_work_native_ledger_relevance r
      where r.work_item_id=w.id and r.attribution_state='active'
        and (r.evidence_kind='owner_attested'
          or (r.evidence_kind='source_verified' and exists (
            select 1 from atlas.company_work_native_ledger_exact_source_v1(
              r.work_item_id,r.ledger_id) p
            where p.source_schema=r.source_schema and p.source_table=r.source_table
              and p.source_id=r.source_id
          )))
    );
  return jsonb_build_object(
    'contractVersion','company_work_native_ledger_scope_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'scopeRule','explicit_attested_or_currently_source_verified',
    'items',v_items,'organizationWithoutCurrentLedgerEvidenceCount',v_unknown,
    'sourceProofRechecked',true,'unlinkedWorkIsUnknown',true,
    'otherLedgerEvidenceDoesNotProveExclusion',true);
end;
$scope$;

alter table atlas.company_work_native_ledger_relevance enable row level security;
revoke all on table atlas.company_work_native_ledger_relevance from public,anon,authenticated;
revoke all on function atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)
  from public,anon,authenticated;
revoke all on function atlas.guard_company_work_native_ledger_relevance_v1()
  from public,anon,authenticated;
revoke all on function atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)
  from public,anon,authenticated;
revoke all on function atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.verify_company_work_native_ledger_source_self_api_v1(uuid,uuid)
  from public,anon,authenticated;
revoke all on function atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(uuid,text)
  from public,anon,authenticated;
revoke all on function atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)
  from public,anon,authenticated;
grant execute on function atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)
  to authenticated;
grant execute on function atlas.verify_company_work_native_ledger_source_self_api_v1(uuid,uuid)
  to authenticated;
grant execute on function atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(uuid,text)
  to authenticated;
grant execute on function atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)
  to authenticated;
