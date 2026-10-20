begin;

-- Shared Identity / Atlas Ledger Build 5: organization-local Person -> Reality
-- identity resolution. This links existing history; it never rewrites people,
-- credentials, source memberships, work, or canonical Reality identities.
create table if not exists atlas.person_reality_connection_resolutions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  atlas_person_id uuid not null references atlas.people(id),
  canonical_reality_person_id uuid not null references reality.entities(id),
  resolution_state text not null default 'active'
    check (resolution_state in ('active','retired')),
  resolution_basis jsonb not null,
  asserted_by_person_id uuid not null references reality.entities(id),
  asserted_at timestamptz not null default now(),
  retired_by_person_id uuid references reality.entities(id),
  retired_at timestamptz,
  retirement_reason text,
  constraint person_reality_resolution_basis_object_v1
    check (jsonb_typeof(resolution_basis)='object'),
  constraint person_reality_resolution_retirement_v1
    check ((resolution_state='active' and retired_at is null)
       or (resolution_state='retired' and retired_at is not null))
);
create unique index if not exists person_reality_one_active_alias_v1
  on atlas.person_reality_connection_resolutions(organization_id,atlas_person_id)
  where resolution_state='active';
create index if not exists person_reality_canonical_context_v1
  on atlas.person_reality_connection_resolutions(
    organization_id,canonical_reality_person_id)
  where resolution_state='active';
alter table atlas.person_reality_connection_resolutions enable row level security;
revoke all on atlas.person_reality_connection_resolutions
  from public,anon,authenticated,service_role;

create or replace function atlas.organization_person_canonical_reality_v1(
  p_organization_id uuid,p_atlas_person_id uuid)
returns uuid language sql stable security definer set search_path to ''
as $fn$
  select coalesce(
    (select r.canonical_reality_person_id
     from atlas.person_reality_connection_resolutions r
     join atlas.institutional_person_records ipr
       on ipr.organization_id=r.organization_id
      and ipr.person_id=r.atlas_person_id
      and ipr.status='active'
     join reality.entities e on e.id=r.canonical_reality_person_id
       and e.entity_kind='person' and e.identity_state='canonical'
     where r.organization_id=p_organization_id
       and r.atlas_person_id=p_atlas_person_id
       and r.resolution_state='active'
     limit 1),
    (select e.id from reality.entities e
     join atlas.institutional_person_records ipr
       on ipr.organization_id=p_organization_id
      and ipr.person_id=e.id and ipr.status='active'
     where e.id=p_atlas_person_id
       and e.entity_kind='person' and e.identity_state='canonical')
  );
$fn$;
revoke all on function atlas.organization_person_canonical_reality_v1(uuid,uuid)
  from public,anon,authenticated,service_role;
-- Private resolver: never grant arbitrary canonical identity lookups to API roles.

create or replace function atlas.attest_person_reality_connection_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_atlas_person_id uuid,
  p_canonical_reality_person_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_actor uuid;
  v_found atlas.person_reality_connection_resolutions%rowtype;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if auth.uid() is null or p_atlas_person_id is null
    or p_canonical_reality_person_id is null
    or v_reason is null or length(v_reason)>1200 then
    raise exception 'Signed-in owner, exact identities and attestation required'
      using errcode='22023';
  end if;
  -- A native seat does not grant authority to make identity assertions.
  v_actor:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if not exists (
    select 1 from atlas.institutional_person_records ipr
    join atlas.people p on p.id=ipr.person_id and p.status='active'
    where ipr.organization_id=p_organization_id
      and ipr.person_id=p_atlas_person_id and ipr.status='active'
  ) or not exists (
    select 1 from reality.entities e
    where e.id=p_canonical_reality_person_id
      and e.entity_kind='person' and e.identity_state='canonical'
  ) then
    raise exception 'Both active Person records must exist within their own identity custody'
      using errcode='23514';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.person_reality_connection:'||p_organization_id||':'||p_atlas_person_id,0));
  select * into v_found from atlas.person_reality_connection_resolutions
   where organization_id=p_organization_id and atlas_person_id=p_atlas_person_id
     and resolution_state='active' for update;
  if v_found.id is not null then
    if v_found.canonical_reality_person_id<>p_canonical_reality_person_id then
      raise exception 'Conflicting active Person resolution requires explicit retirement/review'
        using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotent',true,'resolutionId',v_found.id,
      'canonicalRealityPersonId',v_found.canonical_reality_person_id,
      'authBindingsChanged',false,'historyRewritten',false);
  end if;
  insert into atlas.person_reality_connection_resolutions (
    organization_id,atlas_person_id,canonical_reality_person_id,
    asserted_by_person_id,resolution_basis
  ) values (
    p_organization_id,p_atlas_person_id,p_canonical_reality_person_id,
    v_actor,jsonb_build_object(
      'basisKind','organization_owner_identity_attestation',
      'nativeLedgerId',p_ledger_id,'statement',v_reason,
      'source','attest_person_reality_connection_owner_self_api_v1',
      'assertedByRealityPersonId',v_actor,
      'doesNotBindAuth',true,'doesNotMergeHistories',true,
      'doesNotGrantLedgerSeat',true
    )
  ) returning * into v_found;
  return jsonb_build_object('ok',true,'idempotent',false,
    'resolutionId',v_found.id,
    'canonicalRealityPersonId',v_found.canonical_reality_person_id,
    'authBindingsChanged',false,'historyRewritten',false);
end
$fn$;
revoke all on function atlas.attest_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function atlas.attest_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function atlas.retire_person_reality_connection_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_atlas_person_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare v_actor uuid; v_count int; v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if p_atlas_person_id is null or v_reason is null or length(v_reason)>1200 then
    raise exception 'Exact Person and retirement reason required' using errcode='22023';
  end if;
  v_actor:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  update atlas.person_reality_connection_resolutions
     set resolution_state='retired',retired_at=now(),
       retired_by_person_id=v_actor,retirement_reason=v_reason
   where organization_id=p_organization_id and atlas_person_id=p_atlas_person_id
     and resolution_state='active';
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',true,'retiredCount',v_count,
    'historyDeleted',false,'authBindingsChanged',false);
end
$fn$;
revoke all on function atlas.retire_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function atlas.retire_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,text) to authenticated;

-- Reuse the previously released owner-only Person projection. It is
-- intentionally *not* a generic seat-only directory or source disclosure.
create or replace function atlas.company_people_native_ledger_scope_self_api_v2(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 50,
  p_after_person_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_base jsonb;
  v_items jsonb:='[]'::jsonb;
  v_item jsonb;
  v_canonical uuid;
  v_has_seat boolean;
begin
  v_base:=atlas.company_people_native_ledger_scope_self_api_v1(
    p_organization_id,p_ledger_id,p_limit,p_after_person_id);
  for v_item in select value from jsonb_array_elements(v_base->'items') loop
    v_canonical:=atlas.organization_person_canonical_reality_v1(
      p_organization_id,(v_item->>'personId')::uuid);
    select exists(
      select 1 from ledger.seats s
      where s.ledger_id=p_ledger_id and s.person_entity_id=v_canonical
        and s.seat_state='active' and s.ended_at is null)
      into v_has_seat;
    v_items:=v_items||jsonb_build_array(
      v_item||jsonb_build_object(
        'canonicalRealityPersonId',v_canonical,
        'nativeLedgerSeatState',
          case when v_has_seat then 'active_participation_only' else 'not_proven' end,
        'canonicalIdentityResolution',
          case when v_canonical is null then 'unresolved'
               when v_canonical=(v_item->>'personId')::uuid then 'direct'
               else 'owner_attested_alias' end,
        'atlasAccountRequiredForSeat',false
      ));
  end loop;
  return v_base||jsonb_build_object(
    'contractVersion','company_people_native_ledger_scope_v2',
    'items',v_items,
    'truthBoundary',(v_base->'truthBoundary')||jsonb_build_object(
      'historicalInstitutionalRecordPreserved',true,
      'identityResolutionGrantsNoCredentialOrAuthority',true,
      'LedgerSeatNotAnEmployeeSeat',true));
end
$fn$;
revoke all on function atlas.company_people_native_ledger_scope_self_api_v2(
  uuid,uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.company_people_native_ledger_scope_self_api_v2(
  uuid,uuid,integer,uuid) to authenticated;

create or replace function public.company_people_native_ledger_scope_self_api_v2(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 50,
  p_after_person_id uuid default null)
returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.company_people_native_ledger_scope_self_api_v2(
  p_organization_id,p_ledger_id,p_limit,p_after_person_id) $fn$;
revoke all on function public.company_people_native_ledger_scope_self_api_v2(
  uuid,uuid,integer,uuid) from public,anon,authenticated,service_role;
grant execute on function public.company_people_native_ledger_scope_self_api_v2(
  uuid,uuid,integer,uuid) to authenticated;

create or replace function public.attest_person_reality_connection_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_atlas_person_id uuid,
  p_canonical_reality_person_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path to ''
as $fn$ select atlas.attest_person_reality_connection_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_atlas_person_id,
  p_canonical_reality_person_id,p_reason) $fn$;
revoke all on function public.attest_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.attest_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function public.retire_person_reality_connection_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_atlas_person_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path to ''
as $fn$ select atlas.retire_person_reality_connection_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_atlas_person_id,p_reason) $fn$;
revoke all on function public.retire_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.retire_person_reality_connection_owner_self_api_v1(
  uuid,uuid,uuid,text) to authenticated;

commit;
