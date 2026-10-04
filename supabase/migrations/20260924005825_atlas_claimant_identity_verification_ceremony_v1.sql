-- Atlas Claimant Identity Verification Ceremony v1.
-- Separates private recognition from claimant-safe verification and durable identity binding.

create table if not exists atlas.claimant_identity_factor_kinds (
  factor_kind text primary key,
  factor_family text not null,
  assurance_level text not null,
  factor_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claimant_identity_factor_kinds_kind_v1
    check (factor_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint claimant_identity_factor_kinds_family_v1
    check (factor_family in ('contact_possession','identity_document','trusted_presence')),
  constraint claimant_identity_factor_kinds_assurance_v1
    check (assurance_level in ('medium','high')),
  constraint claimant_identity_factor_kinds_state_v1
    check (factor_state in ('active','retired')),
  constraint claimant_identity_factor_kinds_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.claimant_identity_factor_kinds(
  factor_kind,factor_family,assurance_level,factor_state,metadata
)
values
(
  'verified_contact_possession',
  'contact_possession',
  'medium',
  'active',
  '{"rawValueRetention":"forbidden"}'::jsonb
),
(
  'government_identity_document',
  'identity_document',
  'high',
  'active',
  '{"rawDocumentRetention":"outside_ceremony_kernel"}'::jsonb
),
(
  'trusted_in_person',
  'trusted_presence',
  'high',
  'active',
  '{"rawObservationRetention":"forbidden"}'::jsonb
)
on conflict (factor_kind) do update
set factor_family=excluded.factor_family,
    assurance_level=excluded.assurance_level,
    factor_state='active',
    metadata=atlas.claimant_identity_factor_kinds.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.claimant_identity_verification_policies (
  policy_key text primary key,
  minimum_passed_factors integer not null,
  minimum_distinct_families integer not null,
  require_high_assurance boolean not null default true,
  case_ttl_seconds integer not null,
  policy_state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claimant_identity_verification_policies_key_v1
    check (policy_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint claimant_identity_verification_policies_counts_v1
    check (
      minimum_passed_factors between 2 and 10
      and minimum_distinct_families between 2 and minimum_passed_factors
    ),
  constraint claimant_identity_verification_policies_ttl_v1
    check (case_ttl_seconds between 300 and 3600),
  constraint claimant_identity_verification_policies_state_v1
    check (policy_state in ('active','retired')),
  constraint claimant_identity_verification_policies_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

insert into atlas.claimant_identity_verification_policies(
  policy_key,minimum_passed_factors,minimum_distinct_families,
  require_high_assurance,case_ttl_seconds,policy_state,metadata
)
values(
  'person_binding_v1',2,2,true,1800,'active',
  '{"basis":"two_independent_factor_families_with_high_assurance"}'::jsonb
)
on conflict (policy_key) do update
set minimum_passed_factors=excluded.minimum_passed_factors,
    minimum_distinct_families=excluded.minimum_distinct_families,
    require_high_assurance=excluded.require_high_assurance,
    case_ttl_seconds=excluded.case_ttl_seconds,
    policy_state='active',
    metadata=atlas.claimant_identity_verification_policies.metadata || excluded.metadata,
    updated_at=now();

create table if not exists atlas.claimant_identity_verification_cases (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references atlas.people(id) on delete restrict,
  canonical_entity_id uuid not null references local_intel.entities(id) on delete restrict,
  case_state text not null default 'pending_proof',
  policy_key text not null
    references atlas.claimant_identity_verification_policies(policy_key) on delete restrict,
  candidate_origin text not null,
  candidate_basis_hash text not null,
  claimant_projection jsonb not null,
  minimum_passed_factors integer not null,
  minimum_distinct_families integer not null,
  require_high_assurance boolean not null,
  initiated_by_principal_id uuid references atlas.principals(id) on delete restrict,
  expires_at timestamptz not null,
  ready_at timestamptz,
  verified_at timestamptz,
  cancelled_at timestamptz,
  rejected_at timestamptz,
  conflicted_at timestamptz,
  verified_binding_id uuid
    references atlas.person_canonical_entity_bindings(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claimant_identity_verification_cases_state_v1
    check (case_state in (
      'pending_proof','ready_to_commit','verified',
      'rejected','cancelled','expired','conflicted'
    )),
  constraint claimant_identity_verification_cases_origin_v1
    check (candidate_origin in (
      'identity_resolution','operator_selected',
      'recovery_continuity','migration_review'
    )),
  constraint claimant_identity_verification_cases_hash_v1
    check (candidate_basis_hash ~ '^[0-9a-f]{64}$'),
  constraint claimant_identity_verification_cases_projection_v1
    check (
      jsonb_typeof(claimant_projection)='object'
      and not (claimant_projection ? 'canonicalEntityId')
    ),
  constraint claimant_identity_verification_cases_counts_v1
    check (
      minimum_passed_factors between 2 and 10
      and minimum_distinct_families between 2 and minimum_passed_factors
    ),
  constraint claimant_identity_verification_cases_expiry_v1
    check (expires_at > created_at and expires_at <= created_at + interval '1 hour'),
  constraint claimant_identity_verification_cases_shape_v1
    check (
      (case_state='pending_proof'
        and ready_at is null and verified_at is null and cancelled_at is null
        and rejected_at is null and conflicted_at is null and verified_binding_id is null)
      or
      (case_state='ready_to_commit'
        and ready_at is not null and verified_at is null and cancelled_at is null
        and rejected_at is null and conflicted_at is null and verified_binding_id is null)
      or
      (case_state='verified'
        and ready_at is not null and verified_at is not null
        and verified_binding_id is not null and cancelled_at is null
        and rejected_at is null and conflicted_at is null)
      or
      (case_state='cancelled'
        and cancelled_at is not null and verified_at is null and verified_binding_id is null)
      or
      (case_state='rejected'
        and rejected_at is not null and verified_at is null and verified_binding_id is null)
      or
      (case_state='expired'
        and verified_at is null and verified_binding_id is null)
      or
      (case_state='conflicted'
        and conflicted_at is not null and verified_at is null and verified_binding_id is null)
    ),
  constraint claimant_identity_verification_cases_metadata_v1
    check (
      jsonb_typeof(metadata)='object'
      and not (metadata ?| array[
        'otp','code','email','phone','document','rawValue',
        'resolverEvidence','blindToken','privateIdentifier'
      ])
    )
);

create unique index if not exists claimant_identity_verification_cases_live_uq_v1
  on atlas.claimant_identity_verification_cases(person_id,canonical_entity_id)
  where case_state in ('pending_proof','ready_to_commit');

create index if not exists claimant_identity_verification_cases_person_idx_v1
  on atlas.claimant_identity_verification_cases(person_id,created_at desc);

comment on table atlas.claimant_identity_verification_cases is
  'Claimant-safe verification ceremony. Candidate identity is private; claimant projection omits canonical id and private resolver evidence. Durable identity truth is created only by separate commit after factor threshold.';

create table if not exists atlas.claimant_identity_verification_factors (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null
    references atlas.claimant_identity_verification_cases(id) on delete restrict,
  factor_kind text not null
    references atlas.claimant_identity_factor_kinds(factor_kind) on delete restrict,
  factor_family text not null,
  assurance_level text not null,
  factor_state text not null,
  verifier_key text not null,
  proof_artifact_hash text not null unique,
  verified_by_principal_id uuid references atlas.principals(id) on delete restrict,
  verified_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint claimant_identity_verification_factors_family_v1
    check (factor_family in ('contact_possession','identity_document','trusted_presence')),
  constraint claimant_identity_verification_factors_assurance_v1
    check (assurance_level in ('medium','high')),
  constraint claimant_identity_verification_factors_state_v1
    check (factor_state in ('passed','failed')),
  constraint claimant_identity_verification_factors_verifier_v1
    check (verifier_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint claimant_identity_verification_factors_hash_v1
    check (proof_artifact_hash ~ '^[0-9a-f]{64}$'),
  constraint claimant_identity_verification_factors_metadata_v1
    check (
      jsonb_typeof(metadata)='object'
      and not (metadata ?| array[
        'otp','code','email','phone','document','rawValue',
        'resolverEvidence','blindToken','privateIdentifier'
      ])
    )
);

create index if not exists claimant_identity_verification_factors_case_idx_v1
  on atlas.claimant_identity_verification_factors(case_id,verified_at,id);

comment on table atlas.claimant_identity_verification_factors is
  'Trusted-verifier factor receipts only. Raw OTPs, contact values, documents, private resolver evidence, and blind tokens do not belong in this table.';

alter table atlas.claimant_identity_factor_kinds enable row level security;
alter table atlas.claimant_identity_verification_policies enable row level security;
alter table atlas.claimant_identity_verification_cases enable row level security;
alter table atlas.claimant_identity_verification_factors enable row level security;

revoke all on table atlas.claimant_identity_factor_kinds
  from public,anon,authenticated;
revoke all on table atlas.claimant_identity_verification_policies
  from public,anon,authenticated;
revoke all on table atlas.claimant_identity_verification_cases
  from public,anon,authenticated,service_role;
revoke all on table atlas.claimant_identity_verification_factors
  from public,anon,authenticated,service_role;

grant select on table atlas.claimant_identity_factor_kinds to service_role;
grant select on table atlas.claimant_identity_verification_policies to service_role;

create or replace function atlas.set_claimant_identity_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists claimant_identity_factor_kinds_updated_at_v1
  on atlas.claimant_identity_factor_kinds;
create trigger claimant_identity_factor_kinds_updated_at_v1
before update on atlas.claimant_identity_factor_kinds
for each row execute function atlas.set_claimant_identity_updated_at_v1();

drop trigger if exists claimant_identity_verification_policies_updated_at_v1
  on atlas.claimant_identity_verification_policies;
create trigger claimant_identity_verification_policies_updated_at_v1
before update on atlas.claimant_identity_verification_policies
for each row execute function atlas.set_claimant_identity_updated_at_v1();

drop trigger if exists claimant_identity_verification_cases_updated_at_v1
  on atlas.claimant_identity_verification_cases;
create trigger claimant_identity_verification_cases_updated_at_v1
before update on atlas.claimant_identity_verification_cases
for each row execute function atlas.set_claimant_identity_updated_at_v1();

create or replace function atlas.claimant_identity_case_threshold_internal_v1(
  p_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  with c as (
    select *
    from atlas.claimant_identity_verification_cases
    where id=p_case_id
  ),
  f as (
    select
      count(*) filter (where factor_state='passed')::integer as passed_count,
      count(distinct factor_family) filter (where factor_state='passed')::integer as family_count,
      count(*) filter (
        where factor_state='passed' and assurance_level='high'
      )::integer as high_count
    from atlas.claimant_identity_verification_factors
    where case_id=p_case_id
  )
  select jsonb_build_object(
    'passedFactorCount',coalesce(f.passed_count,0),
    'distinctFamilyCount',coalesce(f.family_count,0),
    'highAssuranceFactorCount',coalesce(f.high_count,0),
    'minimumPassedFactors',c.minimum_passed_factors,
    'minimumDistinctFamilies',c.minimum_distinct_families,
    'requireHighAssurance',c.require_high_assurance,
    'thresholdSatisfied',
      coalesce(f.passed_count,0)>=c.minimum_passed_factors
      and coalesce(f.family_count,0)>=c.minimum_distinct_families
      and (not c.require_high_assurance or coalesce(f.high_count,0)>=1)
  )
  from c
  cross join f;
$function$;

revoke all on function atlas.claimant_identity_case_threshold_internal_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function atlas.start_claimant_identity_case_service_v1(
  p_person_id uuid,
  p_canonical_entity_id uuid,
  p_candidate_origin text,
  p_candidate_basis_hash text,
  p_initiated_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_origin text:=lower(btrim(coalesce(p_candidate_origin,'')));
  v_hash text:=lower(btrim(coalesce(p_candidate_basis_hash,'')));
  v_policy atlas.claimant_identity_verification_policies%rowtype;
  v_projection jsonb;
  v_case atlas.claimant_identity_verification_cases%rowtype;
  v_existing_binding atlas.person_canonical_entity_bindings%rowtype;
begin
  if v_origin not in (
    'identity_resolution','operator_selected',
    'recovery_continuity','migration_review'
  ) or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Trusted candidate origin and candidate-basis hash are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object'
     or coalesce(p_metadata,'{}'::jsonb) ?| array[
       'otp','code','email','phone','document','rawValue',
       'resolverEvidence','blindToken','privateIdentifier'
     ] then
    raise exception 'Case metadata contains prohibited raw/private verification material.'
      using errcode='22023';
  end if;

  if not exists(
    select 1 from atlas.people p
    where p.id=p_person_id and p.status='active'
  ) then
    raise exception 'Active Atlas Person not found.' using errcode='P0002';
  end if;

  if not exists(
    select 1 from local_intel.entities e
    where e.id=p_canonical_entity_id
      and e.entity_type='person'
      and e.status='active'
  ) then
    raise exception 'Active canonical person candidate not found.'
      using errcode='P0002';
  end if;

  if p_initiated_by_principal_id is not null
     and not exists(
       select 1 from atlas.principals p
       where p.id=p_initiated_by_principal_id and p.status='active'
     ) then
    raise exception 'Initiating Principal is not active.' using errcode='P0002';
  end if;

  select * into v_existing_binding
  from atlas.person_canonical_entity_bindings b
  where b.binding_state='verified'
    and (
      b.person_id=p_person_id
      or b.canonical_entity_id=p_canonical_entity_id
    )
  limit 1;

  if v_existing_binding.id is not null then
    if v_existing_binding.person_id=p_person_id
       and v_existing_binding.canonical_entity_id=p_canonical_entity_id then
      return jsonb_build_object(
        'contractVersion','claimant_identity_verification_case_v1',
        'alreadyVerified',true,
        'bindingId',v_existing_binding.id
      );
    end if;

    raise exception 'Claim candidate conflicts with an existing verified identity binding.'
      using errcode='23505';
  end if;

  update atlas.claimant_identity_verification_cases
  set case_state='expired',
      updated_at=now()
  where person_id=p_person_id
    and canonical_entity_id=p_canonical_entity_id
    and case_state in ('pending_proof','ready_to_commit')
    and expires_at<=now();

  select * into v_case
  from atlas.claimant_identity_verification_cases c
  where c.person_id=p_person_id
    and c.canonical_entity_id=p_canonical_entity_id
    and c.case_state in ('pending_proof','ready_to_commit')
    and c.expires_at>now()
  order by c.created_at desc
  limit 1;

  if v_case.id is not null then
    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_case_v1',
      'idempotentReplay',true,
      'caseId',v_case.id,
      'caseState',v_case.case_state,
      'expiresAt',v_case.expires_at,
      'claimantProjection',v_case.claimant_projection,
      'requirements',jsonb_build_object(
        'minimumPassedFactors',v_case.minimum_passed_factors,
        'minimumDistinctFamilies',v_case.minimum_distinct_families,
        'requireHighAssurance',v_case.require_high_assurance
      )
    );
  end if;

  select * into v_policy
  from atlas.claimant_identity_verification_policies p
  where p.policy_key='person_binding_v1'
    and p.policy_state='active';

  if v_policy.policy_key is null then
    raise exception 'Active claimant identity verification policy not found.'
      using errcode='P0002';
  end if;

  v_projection:=atlas.claimant_safe_identity_projection_service_v1(
    p_canonical_entity_id
  ) - 'canonicalEntityId';

  insert into atlas.claimant_identity_verification_cases(
    person_id,canonical_entity_id,case_state,policy_key,
    candidate_origin,candidate_basis_hash,claimant_projection,
    minimum_passed_factors,minimum_distinct_families,require_high_assurance,
    initiated_by_principal_id,expires_at,metadata
  )
  values(
    p_person_id,p_canonical_entity_id,'pending_proof',v_policy.policy_key,
    v_origin,v_hash,v_projection,
    v_policy.minimum_passed_factors,v_policy.minimum_distinct_families,
    v_policy.require_high_assurance,p_initiated_by_principal_id,
    now()+make_interval(secs=>v_policy.case_ttl_seconds),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_case;

  return jsonb_build_object(
    'contractVersion','claimant_identity_verification_case_v1',
    'idempotentReplay',false,
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'expiresAt',v_case.expires_at,
    'claimantProjection',v_case.claimant_projection,
    'requirements',jsonb_build_object(
      'minimumPassedFactors',v_case.minimum_passed_factors,
      'minimumDistinctFamilies',v_case.minimum_distinct_families,
      'requireHighAssurance',v_case.require_high_assurance
    )
  );
end
$function$;

create or replace function atlas.record_claimant_identity_factor_service_v1(
  p_case_id uuid,
  p_factor_kind text,
  p_factor_state text,
  p_verifier_key text,
  p_proof_artifact_hash text,
  p_verified_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_kind text:=lower(btrim(coalesce(p_factor_kind,'')));
  v_state text:=lower(btrim(coalesce(p_factor_state,'')));
  v_verifier text:=lower(btrim(coalesce(p_verifier_key,'')));
  v_hash text:=lower(btrim(coalesce(p_proof_artifact_hash,'')));
  v_case atlas.claimant_identity_verification_cases%rowtype;
  v_kind_row atlas.claimant_identity_factor_kinds%rowtype;
  v_factor atlas.claimant_identity_verification_factors%rowtype;
  v_threshold jsonb;
begin
  if v_state not in ('passed','failed')
     or v_verifier !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Trusted factor state, verifier key, and proof-artifact hash are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object'
     or coalesce(p_metadata,'{}'::jsonb) ?| array[
       'otp','code','email','phone','document','rawValue',
       'resolverEvidence','blindToken','privateIdentifier'
     ] then
    raise exception 'Factor metadata contains prohibited raw/private verification material.'
      using errcode='22023';
  end if;

  select * into v_case
  from atlas.claimant_identity_verification_cases c
  where c.id=p_case_id
  for update;

  if v_case.id is null then
    raise exception 'Claimant identity verification case not found.'
      using errcode='P0002';
  end if;

  if v_case.case_state not in ('pending_proof','ready_to_commit') then
    raise exception 'Claimant identity verification case is not accepting proof factors.'
      using errcode='55000';
  end if;

  if v_case.expires_at<=now() then
    update atlas.claimant_identity_verification_cases
    set case_state='expired'
    where id=v_case.id;

    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_factor_v1',
      'accepted',false,
      'caseId',v_case.id,
      'caseState','expired',
      'reason','case_expired'
    );
  end if;

  select * into v_kind_row
  from atlas.claimant_identity_factor_kinds k
  where k.factor_kind=v_kind
    and k.factor_state='active';

  if v_kind_row.factor_kind is null then
    raise exception 'Active claimant identity factor kind not found.'
      using errcode='P0002';
  end if;

  if p_verified_by_principal_id is not null
     and not exists(
       select 1 from atlas.principals p
       where p.id=p_verified_by_principal_id and p.status='active'
     ) then
    raise exception 'Factor-verifying Principal is not active.'
      using errcode='P0002';
  end if;

  insert into atlas.claimant_identity_verification_factors(
    case_id,factor_kind,factor_family,assurance_level,factor_state,
    verifier_key,proof_artifact_hash,verified_by_principal_id,metadata
  )
  values(
    v_case.id,v_kind,v_kind_row.factor_family,v_kind_row.assurance_level,v_state,
    v_verifier,v_hash,p_verified_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_factor;

  v_threshold:=atlas.claimant_identity_case_threshold_internal_v1(v_case.id);

  if coalesce((v_threshold->>'thresholdSatisfied')::boolean,false)
     and v_case.case_state='pending_proof' then
    update atlas.claimant_identity_verification_cases
    set case_state='ready_to_commit',
        ready_at=now()
    where id=v_case.id;
    v_case.case_state:='ready_to_commit';
  end if;

  return jsonb_build_object(
    'contractVersion','claimant_identity_verification_factor_v1',
    'accepted',true,
    'factorId',v_factor.id,
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'factorKind',v_factor.factor_kind,
    'factorFamily',v_factor.factor_family,
    'assuranceLevel',v_factor.assurance_level,
    'factorState',v_factor.factor_state,
    'threshold',v_threshold
  );
end
$function$;

create or replace function atlas.commit_claimant_identity_case_service_v1(
  p_case_id uuid,
  p_committed_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','extensions','local_intel'
as $function$
declare
  v_case atlas.claimant_identity_verification_cases%rowtype;
  v_threshold jsonb;
  v_factor_material text;
  v_ceremony_hash text;
  v_binding jsonb;
begin
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object'
     or coalesce(p_metadata,'{}'::jsonb) ?| array[
       'otp','code','email','phone','document','rawValue',
       'resolverEvidence','blindToken','privateIdentifier'
     ] then
    raise exception 'Commit metadata contains prohibited raw/private verification material.'
      using errcode='22023';
  end if;

  select * into v_case
  from atlas.claimant_identity_verification_cases c
  where c.id=p_case_id
  for update;

  if v_case.id is null then
    raise exception 'Claimant identity verification case not found.'
      using errcode='P0002';
  end if;

  if v_case.case_state='verified' then
    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_commit_v1',
      'verified',true,
      'idempotentReplay',true,
      'caseId',v_case.id,
      'bindingId',v_case.verified_binding_id
    );
  end if;

  if v_case.case_state not in ('pending_proof','ready_to_commit') then
    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_commit_v1',
      'verified',false,
      'caseId',v_case.id,
      'caseState',v_case.case_state,
      'reason','case_not_committable'
    );
  end if;

  if v_case.expires_at<=now() then
    update atlas.claimant_identity_verification_cases
    set case_state='expired'
    where id=v_case.id;

    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_commit_v1',
      'verified',false,
      'caseId',v_case.id,
      'caseState','expired',
      'reason','case_expired'
    );
  end if;

  v_threshold:=atlas.claimant_identity_case_threshold_internal_v1(v_case.id);

  if not coalesce((v_threshold->>'thresholdSatisfied')::boolean,false) then
    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_commit_v1',
      'verified',false,
      'caseId',v_case.id,
      'caseState',v_case.case_state,
      'reason','verification_threshold_not_satisfied',
      'threshold',v_threshold
    );
  end if;

  if p_committed_by_principal_id is not null
     and not exists(
       select 1 from atlas.principals p
       where p.id=p_committed_by_principal_id and p.status='active'
     ) then
    raise exception 'Committing Principal is not active.'
      using errcode='P0002';
  end if;

  if not exists(
    select 1 from local_intel.entities e
    where e.id=v_case.canonical_entity_id
      and e.entity_type='person'
      and e.status='active'
  ) then
    update atlas.claimant_identity_verification_cases
    set case_state='rejected',
        rejected_at=now()
    where id=v_case.id;

    return jsonb_build_object(
      'contractVersion','claimant_identity_verification_commit_v1',
      'verified',false,
      'caseId',v_case.id,
      'caseState','rejected',
      'reason','canonical_person_no_longer_active'
    );
  end if;

  select string_agg(
    f.factor_kind||':'||f.proof_artifact_hash,
    '|'
    order by f.factor_kind,f.proof_artifact_hash
  )
  into v_factor_material
  from atlas.claimant_identity_verification_factors f
  where f.case_id=v_case.id
    and f.factor_state='passed';

  v_ceremony_hash:=encode(
    extensions.digest(
      v_case.id::text||'|'||coalesce(v_factor_material,''),
      'sha256'
    ),
    'hex'
  );

  begin
    v_binding:=atlas.establish_verified_person_canonical_binding_service_v1(
      v_case.person_id,
      v_case.canonical_entity_id,
      'claimant_verified',
      v_ceremony_hash,
      'atlas_claimant_identity_verification_v1',
      p_committed_by_principal_id,
      jsonb_build_object(
        'caseId',v_case.id,
        'policyKey',v_case.policy_key,
        'passedFactorCount',(v_threshold->>'passedFactorCount')::integer,
        'distinctFamilyCount',(v_threshold->>'distinctFamilyCount')::integer,
        'highAssuranceFactorCount',(v_threshold->>'highAssuranceFactorCount')::integer
      ),
      coalesce(p_metadata,'{}'::jsonb)
    );
  exception
    when unique_violation then
      update atlas.claimant_identity_verification_cases
      set case_state='conflicted',
          conflicted_at=now()
      where id=v_case.id;

      return jsonb_build_object(
        'contractVersion','claimant_identity_verification_commit_v1',
        'verified',false,
        'caseId',v_case.id,
        'caseState','conflicted',
        'reason','verified_identity_binding_conflict'
      );
  end;

  update atlas.claimant_identity_verification_cases
  set case_state='verified',
      ready_at=coalesce(ready_at,now()),
      verified_at=now(),
      verified_binding_id=(v_binding->>'bindingId')::uuid,
      metadata=metadata || coalesce(p_metadata,'{}'::jsonb)
  where id=v_case.id
  returning * into v_case;

  return jsonb_build_object(
    'contractVersion','claimant_identity_verification_commit_v1',
    'verified',true,
    'idempotentReplay',false,
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'bindingId',v_case.verified_binding_id,
    'verifiedAt',v_case.verified_at
  );
end
$function$;

create or replace function atlas.claimant_identity_case_self_api_v1(
  p_case_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_person_id uuid;
  v_case atlas.claimant_identity_verification_cases%rowtype;
  v_threshold jsonb;
  v_factors jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    raise exception 'Active Atlas Person required.' using errcode='42501';
  end if;

  select * into v_case
  from atlas.claimant_identity_verification_cases c
  where c.id=p_case_id
    and c.person_id=v_person_id;

  if v_case.id is null then
    raise exception 'Claimant identity verification case not found for current Person.'
      using errcode='P0002';
  end if;

  if v_case.case_state in ('pending_proof','ready_to_commit')
     and v_case.expires_at<=now() then
    update atlas.claimant_identity_verification_cases
    set case_state='expired'
    where id=v_case.id;
    v_case.case_state:='expired';
  end if;

  v_threshold:=atlas.claimant_identity_case_threshold_internal_v1(v_case.id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'factorKind',f.factor_kind,
      'factorFamily',f.factor_family,
      'assuranceLevel',f.assurance_level,
      'factorState',f.factor_state,
      'verifiedAt',f.verified_at
    )
    order by f.verified_at,f.id
  ),'[]'::jsonb)
  into v_factors
  from atlas.claimant_identity_verification_factors f
  where f.case_id=v_case.id;

  return jsonb_build_object(
    'contractVersion','claimant_identity_verification_case_self_v1',
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'expiresAt',v_case.expires_at,
    'claimantProjection',v_case.claimant_projection,
    'requirements',jsonb_build_object(
      'minimumPassedFactors',v_case.minimum_passed_factors,
      'minimumDistinctFamilies',v_case.minimum_distinct_families,
      'requireHighAssurance',v_case.require_high_assurance
    ),
    'threshold',v_threshold,
    'factors',v_factors,
    'readyToCommit',v_case.case_state='ready_to_commit',
    'verified',v_case.case_state='verified'
  );
end
$function$;

create or replace function atlas.cancel_claimant_identity_case_self_api_v1(
  p_case_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_person_id uuid;
  v_case atlas.claimant_identity_verification_cases%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    raise exception 'Active Atlas Person required.' using errcode='42501';
  end if;

  if btrim(coalesce(p_reason,''))='' then
    raise exception 'Cancellation reason is required.' using errcode='22023';
  end if;

  select * into v_case
  from atlas.claimant_identity_verification_cases c
  where c.id=p_case_id
    and c.person_id=v_person_id
  for update;

  if v_case.id is null then
    raise exception 'Claimant identity verification case not found for current Person.'
      using errcode='P0002';
  end if;

  if v_case.case_state in ('pending_proof','ready_to_commit') then
    update atlas.claimant_identity_verification_cases
    set case_state='cancelled',
        cancelled_at=now(),
        metadata=metadata || jsonb_build_object(
          'claimantCancellationReason',btrim(p_reason)
        )
    where id=v_case.id
    returning * into v_case;
  end if;

  return jsonb_build_object(
    'contractVersion','claimant_identity_verification_cancel_v1',
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'cancelledAt',v_case.cancelled_at
  );
end
$function$;

revoke all on function atlas.start_claimant_identity_case_service_v1(
  uuid,uuid,text,text,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.start_claimant_identity_case_service_v1(
  uuid,uuid,text,text,uuid,jsonb
) to service_role;

revoke all on function atlas.record_claimant_identity_factor_service_v1(
  uuid,text,text,text,text,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_claimant_identity_factor_service_v1(
  uuid,text,text,text,text,uuid,jsonb
) to service_role;

revoke all on function atlas.commit_claimant_identity_case_service_v1(
  uuid,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.commit_claimant_identity_case_service_v1(
  uuid,uuid,jsonb
) to service_role;

revoke all on function atlas.claimant_identity_case_self_api_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.claimant_identity_case_self_api_v1(uuid)
  to authenticated;

revoke all on function atlas.cancel_claimant_identity_case_self_api_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function atlas.cancel_claimant_identity_case_self_api_v1(uuid,text)
  to authenticated;
