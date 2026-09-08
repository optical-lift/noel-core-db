begin;

-- Atlas employee-seat identity v1
-- Separates institutional person, organization membership, paid employee seat,
-- credential carrier, and semantic exposure grants. Existing auth.users records
-- remain credential carriers during migration; they are no longer the intended
-- source of institutional identity.

alter table atlas.organization_memberships
  add column if not exists identity_subject_id uuid references atlas.identity_subjects(id) on delete restrict;

alter table atlas.farm_memberships
  add column if not exists identity_subject_id uuid references atlas.identity_subjects(id) on delete restrict;

comment on column atlas.organization_memberships.identity_subject_id is
  'Institutional person anchor for this organization membership. The auth user is a credential carrier, not the source of institutional identity.';
comment on column atlas.farm_memberships.identity_subject_id is
  'Institutional person anchor for this operating-unit membership. The auth user is a compatibility credential carrier during migration.';

create unique index if not exists organization_memberships_org_subject_active_uq
  on atlas.organization_memberships(organization_id, identity_subject_id)
  where identity_subject_id is not null and active;

create unique index if not exists farm_memberships_farm_subject_active_uq
  on atlas.farm_memberships(farm_id, identity_subject_id)
  where identity_subject_id is not null and active;

create table if not exists atlas.organization_employee_seats (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  identity_subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  seat_class text not null default 'employee' check (seat_class in ('employee')),
  status text not null default 'active' check (status in ('active','suspended','ended')),
  billing_state text not null default 'active' check (billing_state in ('active','past_due','waived','ended')),
  billing_unit_price_cents integer not null default 700 check (billing_unit_price_cents >= 0),
  activated_at timestamptz not null default now(),
  suspended_at timestamptz,
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_employee_seats_membership_uq unique (organization_membership_id),
  constraint organization_employee_seats_subject_membership_match check (organization_membership_id is not null)
);

comment on table atlas.organization_employee_seats is
  'Organization-paid Atlas access seat. A seat establishes licensed product access only; it does not itself grant work authority or information exposure.';

create index if not exists organization_employee_seats_org_status_idx
  on atlas.organization_employee_seats(organization_id,status);
create index if not exists organization_employee_seats_subject_idx
  on atlas.organization_employee_seats(identity_subject_id,status);

create table if not exists atlas.organization_member_credentials (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_membership_id uuid not null references atlas.organization_memberships(id) on delete cascade,
  employee_seat_id uuid references atlas.organization_employee_seats(id) on delete cascade,
  identity_subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  credential_kind text not null check (credential_kind in ('auth_user','work_pass_bootstrap','passkey','email_magic_link')),
  auth_user_id uuid references auth.users(id) on delete restrict,
  credential_key text,
  status text not null default 'active' check (status in ('active','revoked','expired')),
  issued_by_organization_id uuid not null references atlas.organizations(id) on delete cascade,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz,
  expires_at timestamptz,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_member_credentials_identity_shape check (
    (credential_kind='auth_user' and auth_user_id is not null)
    or (credential_kind<>'auth_user' and credential_key is not null and btrim(credential_key)<>'')
  )
);

comment on table atlas.organization_member_credentials is
  'Authentication carriers bound to an institutional membership/seat. Credentials do not create membership, authority, or exposure.';

create unique index if not exists organization_member_credentials_active_auth_user_uq
  on atlas.organization_member_credentials(organization_id,auth_user_id)
  where credential_kind='auth_user' and status='active';
create index if not exists organization_member_credentials_membership_idx
  on atlas.organization_member_credentials(organization_membership_id,status);
create index if not exists organization_member_credentials_seat_idx
  on atlas.organization_member_credentials(employee_seat_id,status);

create table if not exists atlas.organization_member_exposure_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_membership_id uuid not null references atlas.organization_memberships(id) on delete cascade,
  employee_seat_id uuid references atlas.organization_employee_seats(id) on delete cascade,
  information_class text not null check (information_class in (
    'worker_delivery_identity',
    'worker_execution_context',
    'worker_coordination_context',
    'worker_institutional_intelligence'
  )),
  scope_kind text not null default 'related_work' check (scope_kind in ('assigned_work','related_work','team','organization')),
  active boolean not null default true,
  granted_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_member_exposure_grants_uq unique (organization_membership_id,information_class,scope_kind)
);

comment on table atlas.organization_member_exposure_grants is
  'Per-membership maximum semantic exposure ceiling. Global semantic exposure policy makes a fact class eligible in principle; this grant determines whether the organization has actually entrusted that information class to this member.';

create index if not exists organization_member_exposure_grants_active_idx
  on atlas.organization_member_exposure_grants(organization_membership_id,active,information_class);

-- Require a paid/active seat and an explicit per-member grant in the semantic membrane.
create or replace function atlas.semantic_exposure_envelope_v1(
  p_organization_id uuid,
  p_audience_membership_id uuid,
  p_purpose_key text,
  p_candidate jsonb
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_membership atlas.organization_memberships%rowtype;
  v_seat atlas.organization_employee_seats%rowtype;
  v_policy atlas.semantic_exposure_policies%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_claim_id uuid;
  v_adapter_key text;
  v_information_class text;
  v_semantic_kind text;
  v_predicate_key text;
  v_source_domain text;
  v_source_kind text;
  v_source_id text;
  v_value_kind text;
  v_value jsonb;
  v_value_unit text;
  v_now timestamptz := now();
  v_envelope jsonb;
begin
  if p_organization_id is null or p_audience_membership_id is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_audience_context');
  end if;

  select * into v_membership
  from atlas.organization_memberships m
  where m.id=p_audience_membership_id
    and m.organization_id=p_organization_id
    and m.active=true;

  if v_membership.id is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','inactive_or_foreign_membership');
  end if;

  select * into v_seat
  from atlas.organization_employee_seats s
  where s.organization_membership_id=v_membership.id
    and s.organization_id=p_organization_id
    and s.status='active'
    and s.billing_state in ('active','waived');

  if v_seat.id is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','active_employee_seat_required');
  end if;

  if p_purpose_key not in ('worker_day','employer_drawer','worker_action') then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','unsupported_purpose');
  end if;

  if not atlas.semantic_exposure_candidate_shape_valid_v1(p_candidate) then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_candidate_shape');
  end if;

  v_adapter_key:=btrim(p_candidate->>'adapterKey');
  v_information_class:=btrim(p_candidate->>'informationClass');
  v_semantic_kind:=btrim(p_candidate->>'semanticKind');
  v_predicate_key:=btrim(p_candidate->>'predicateKey');
  v_source_domain:=btrim(p_candidate->>'sourceDomain');
  v_source_kind:=btrim(p_candidate->>'sourceKind');
  v_source_id:=btrim(p_candidate->>'sourceId');
  v_value_kind:=btrim(p_candidate->>'valueKind');
  v_value:=p_candidate->'value';
  v_value_unit:=nullif(btrim(coalesce(p_candidate->>'valueUnit','')),'');

  if v_adapter_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_predicate_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_domain !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_id='' then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_semantic_identity');
  end if;

  if v_information_class in ('organization_internal','person_private','restricted') then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','information_class_not_worker_exposable');
  end if;

  if not exists (
    select 1 from atlas.organization_member_exposure_grants g
    where g.organization_id=p_organization_id
      and g.organization_membership_id=p_audience_membership_id
      and g.active=true
      and g.information_class=v_information_class
  ) then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','member_exposure_not_granted');
  end if;

  if not atlas.claim_value_matches_kind_v2(v_value_kind,v_value) then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_typed_value');
  end if;

  if v_value_unit is not null and (v_value_kind<>'number' or v_value_unit !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$') then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_value_unit');
  end if;

  select * into v_policy
  from atlas.semantic_exposure_policies p
  where p.active
    and p.audience_kind='organization_member'
    and p.purpose_key=p_purpose_key
    and p.information_class=v_information_class
    and p.semantic_kind=v_semantic_kind
    and p.predicate_key=v_predicate_key
    and p.adapter_key=v_adapter_key
    and p.source_domain=v_source_domain
    and p.source_kind=v_source_kind
  limit 1;

  if v_policy.policy_key is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','no_explicit_admission_policy');
  end if;

  if v_semantic_kind='claim' then
    begin v_claim_id:=nullif(btrim(coalesce(p_candidate->>'claimId','')),'')::uuid;
    exception when invalid_text_representation then v_claim_id:=null;
    end;
    if v_claim_id is null then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_identity_required');
    end if;
    select * into v_claim from atlas.claim_records c where c.id=v_claim_id;
    if v_claim.id is null
       or v_claim.semantic_contract_version is distinct from 'claim-v2'
       or v_claim.scope_kind is distinct from 'organization'
       or v_claim.scope_id is distinct from p_organization_id then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_outside_exposure_custody');
    end if;
    if v_claim.predicate_key is distinct from v_predicate_key
       or v_claim.value_kind is distinct from v_value_kind
       or v_claim.value is distinct from v_value
       or v_claim.value_unit is distinct from v_value_unit then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_projection_mismatch');
    end if;
    if not (v_claim.modality=any(v_policy.allowed_modalities)) then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_modality_not_admitted');
    end if;
    if not (v_claim.adjudication_state=any(v_policy.allowed_adjudication_states)) then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_adjudication_not_admitted');
    end if;
    if (v_claim.valid_from is not null and v_claim.valid_from>v_now)
       or (v_claim.valid_until is not null and v_claim.valid_until<=v_now) then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_not_current_in_time');
    end if;
  elsif nullif(btrim(coalesce(p_candidate->>'claimId','')),'') is not null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_identity_on_non_claim_candidate');
  end if;

  v_envelope:=jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','semantic_exposure_envelope_v1',
    'organizationId',p_organization_id,
    'audienceMembershipId',p_audience_membership_id,
    'employeeSeatId',v_seat.id,
    'audienceKind','organization_member',
    'purposeKey',p_purpose_key,
    'informationClass',v_information_class,
    'semanticKind',v_semantic_kind,
    'predicateKey',v_predicate_key,
    'value',jsonb_strip_nulls(jsonb_build_object('kind',v_value_kind,'value',v_value,'unit',v_value_unit)),
    'provenance',jsonb_strip_nulls(jsonb_build_object(
      'policyKey',v_policy.policy_key,
      'adapterKey',v_adapter_key,
      'source',jsonb_build_object('domain',v_source_domain,'kind',v_source_kind,'id',v_source_id),
      'claim',case when v_claim.id is not null then jsonb_build_object('id',v_claim.id,'modality',v_claim.modality,'adjudicationState',v_claim.adjudication_state,'primaryEvidenceId',v_claim.primary_evidence_id) else null end
    ))
  ));

  return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',true,'reason','explicit_policy_and_member_grant','envelope',v_envelope);
end;
$function$;

revoke all on function atlas.semantic_exposure_envelope_v1(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.semantic_exposure_envelope_v1(uuid,uuid,text,jsonb) to service_role;

-- Establish Anna as the first real Elm organization-paid employee seat while
-- preserving her historical membership IDs and current auth user as a credential carrier.
do $anna$
declare
  v_org uuid := '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  v_farm uuid := '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
  v_org_membership uuid := '4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid;
  v_farm_membership uuid := '23e98e5e-16ca-40d8-872c-c77e06baa167'::uuid;
  v_user uuid := '21436a28-40fd-4914-8015-a248d0dca14e'::uuid;
  v_subject uuid;
  v_seat uuid;
begin
  select s.id into v_subject
  from atlas.identity_subjects s
  join atlas.identity_subject_projections p on p.subject_id=s.id
  where s.organization_id=v_org and p.subject_kind='person' and lower(coalesce(p.display_name,''))='anna'
  limit 1;

  if v_subject is null then
    insert into atlas.identity_subjects(organization_id,state,created_by_user_id,creation_basis)
    values(v_org,'active',null,jsonb_build_object('source','atlas_employee_seat_identity_v1','basis','owner-established institutional worker identity','legacyAuthUserId',v_user))
    returning id into v_subject;

    insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,aliases,contact_points,unresolved_identity,confidence,projection_basis)
    values(v_subject,v_org,'person','Anna','[]'::jsonb,'[]'::jsonb,false,1.0,jsonb_build_object('source','atlas_employee_seat_identity_v1','authority','owner-established'));
  end if;

  update atlas.organization_memberships
  set identity_subject_id=v_subject,
      active=true,
      role='member',
      eligibility_begins_on=coalesce(eligibility_begins_on,current_date),
      eligibility_ends_on=null,
      updated_at=now()
  where id=v_org_membership and organization_id=v_org;

  update atlas.farm_memberships
  set identity_subject_id=v_subject,
      active=true,
      role='farm_hand',
      worker_key='anna',
      eligibility_begins_on=coalesce(eligibility_begins_on,current_date),
      eligibility_ends_on=null,
      permissions=jsonb_build_object('view_assigned_work',true,'submit_task_results',true),
      updated_at=now()
  where id=v_farm_membership and farm_id=v_farm;

  insert into atlas.organization_employee_seats(
    organization_id,organization_membership_id,identity_subject_id,seat_class,status,billing_state,billing_unit_price_cents,metadata
  ) values(
    v_org,v_org_membership,v_subject,'employee','active','active',700,
    jsonb_build_object('source','atlas_employee_seat_identity_v1','commercialMeaning','Elm-paid employee Atlas seat; no Personal Atlas included')
  )
  on conflict (organization_membership_id) do update
  set identity_subject_id=excluded.identity_subject_id,status='active',billing_state='active',billing_unit_price_cents=700,ended_at=null,suspended_at=null,updated_at=now(),metadata=atlas.organization_employee_seats.metadata||excluded.metadata
  returning id into v_seat;

  insert into atlas.organization_member_credentials(
    organization_id,organization_membership_id,employee_seat_id,identity_subject_id,credential_kind,auth_user_id,status,issued_by_organization_id,provenance
  ) values(
    v_org,v_org_membership,v_seat,v_subject,'auth_user',v_user,'active',v_org,
    jsonb_build_object('source','atlas_employee_seat_identity_v1','migrationMeaning','Existing auth user retained only as credential carrier; not Personal Atlas entitlement')
  )
  on conflict (organization_id,auth_user_id) where credential_kind='auth_user' and status='active'
  do update set organization_membership_id=excluded.organization_membership_id,employee_seat_id=excluded.employee_seat_id,identity_subject_id=excluded.identity_subject_id,updated_at=now(),provenance=atlas.organization_member_credentials.provenance||excluded.provenance;

  -- Constitutional default: title-only. No semantic exposure grants are seeded.
  delete from atlas.organization_member_exposure_grants
  where organization_membership_id=v_org_membership;
end;
$anna$;

-- Seat-aware institutional employee context resolver for application sessions.
create or replace function atlas.organization_employee_context_by_auth_user_v1(
  p_auth_user_id uuid,
  p_organization_id uuid default null
)
returns jsonb
language sql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select coalesce((
    select jsonb_build_object(
      'ok',true,
      'organizationId',m.organization_id,
      'organizationMembershipId',m.id,
      'identitySubjectId',m.identity_subject_id,
      'employeeSeatId',s.id,
      'seatClass',s.seat_class,
      'billingState',s.billing_state,
      'credentialId',c.id
    )
    from atlas.organization_member_credentials c
    join atlas.organization_memberships m on m.id=c.organization_membership_id
    join atlas.organization_employee_seats s on s.id=c.employee_seat_id
    where c.credential_kind='auth_user'
      and c.auth_user_id=p_auth_user_id
      and c.status='active'
      and m.active=true
      and s.status='active'
      and s.billing_state in ('active','waived')
      and (p_organization_id is null or m.organization_id=p_organization_id)
    limit 1
  ),jsonb_build_object('ok',false,'code','no_active_employee_seat'));
$function$;

revoke all on function atlas.organization_employee_context_by_auth_user_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.organization_employee_context_by_auth_user_v1(uuid,uuid) to service_role;

-- Acceptance assertions: Anna is active, licensed, credential-bound, and has no
-- semantic exposure grants beyond the title-only compatibility floor.
do $assert$
declare
  v_org_membership uuid := '4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid;
  v_farm_membership uuid := '23e98e5e-16ca-40d8-872c-c77e06baa167'::uuid;
  v_subject uuid;
  v_seat_count integer;
  v_credential_count integer;
  v_grant_count integer;
begin
  select identity_subject_id into v_subject from atlas.organization_memberships where id=v_org_membership and active;
  if v_subject is null then raise exception 'Anna organization membership lacks institutional person identity.'; end if;
  if not exists(select 1 from atlas.farm_memberships where id=v_farm_membership and active and identity_subject_id=v_subject) then
    raise exception 'Anna farm membership is not active on the same institutional person.';
  end if;
  select count(*) into v_seat_count from atlas.organization_employee_seats where organization_membership_id=v_org_membership and status='active' and billing_state='active' and billing_unit_price_cents=700;
  if v_seat_count<>1 then raise exception 'Anna must have exactly one active $7 employee seat.'; end if;
  select count(*) into v_credential_count from atlas.organization_member_credentials where organization_membership_id=v_org_membership and credential_kind='auth_user' and status='active';
  if v_credential_count<>1 then raise exception 'Anna must have exactly one active auth-user credential binding.'; end if;
  select count(*) into v_grant_count from atlas.organization_member_exposure_grants where organization_membership_id=v_org_membership and active;
  if v_grant_count<>0 then raise exception 'Anna must begin at title-only semantic exposure.'; end if;
end;
$assert$;

commit;
