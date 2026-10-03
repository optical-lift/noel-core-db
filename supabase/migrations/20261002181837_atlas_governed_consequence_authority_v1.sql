create table if not exists atlas.governed_consequences (
  id uuid primary key default gen_random_uuid(),
  consequence_identity_key text not null unique,
  consequence_kind text not null,
  subject_ref text not null,
  basis_ref text not null,
  policy_ref text not null,
  policy_version_ref text not null,
  requirement_ref text not null,
  authority_ref text not null,
  establishment_operation text not null,
  temporal_boundary_intent_key text not null,
  boundary_kind text not null,
  boundary_at timestamptz not null,
  operator_user_id uuid not null,
  operator_authorization_ref text not null,
  admission_ref text not null,
  authorized_at timestamptz not null,
  invocation_id text not null,
  offer_ref text not null,
  capability_ref text not null,
  release_ref text not null,
  idempotency_key text not null,
  established_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint governed_consequences_identity_nonblank check (btrim(consequence_identity_key) <> ''),
  constraint governed_consequences_kind_nonblank check (btrim(consequence_kind) <> ''),
  constraint governed_consequences_subject_nonblank check (btrim(subject_ref) <> ''),
  constraint governed_consequences_basis_nonblank check (btrim(basis_ref) <> ''),
  constraint governed_consequences_policy_nonblank check (btrim(policy_ref) <> ''),
  constraint governed_consequences_policy_version_nonblank check (btrim(policy_version_ref) <> ''),
  constraint governed_consequences_requirement_nonblank check (btrim(requirement_ref) <> ''),
  constraint governed_consequences_authority_nonblank check (btrim(authority_ref) <> ''),
  constraint governed_consequences_operation_nonblank check (btrim(establishment_operation) <> ''),
  constraint governed_consequences_intent_nonblank check (btrim(temporal_boundary_intent_key) <> ''),
  constraint governed_consequences_boundary_kind_nonblank check (btrim(boundary_kind) <> ''),
  constraint governed_consequences_operator_authorization_nonblank check (btrim(operator_authorization_ref) <> ''),
  constraint governed_consequences_admission_nonblank check (btrim(admission_ref) <> ''),
  constraint governed_consequences_invocation_nonblank check (btrim(invocation_id) <> ''),
  constraint governed_consequences_offer_nonblank check (btrim(offer_ref) <> ''),
  constraint governed_consequences_capability_nonblank check (btrim(capability_ref) <> ''),
  constraint governed_consequences_release_nonblank check (btrim(release_ref) <> ''),
  constraint governed_consequences_idempotency_nonblank check (btrim(idempotency_key) <> '')
);

alter table atlas.governed_consequences enable row level security;
revoke all on table atlas.governed_consequences from public, anon, authenticated;

create or replace function atlas.prevent_governed_consequence_mutation_v1()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Governed consequences are append-only canonical records.' using errcode='55000';
end;
$function$;

revoke all on function atlas.prevent_governed_consequence_mutation_v1() from public, anon, authenticated;

drop trigger if exists governed_consequences_append_only_v1 on atlas.governed_consequences;
create trigger governed_consequences_append_only_v1
before update or delete on atlas.governed_consequences
for each row execute function atlas.prevent_governed_consequence_mutation_v1();

create or replace function atlas.establish_governed_consequence_service_v1(
  p_admission jsonb,
  p_operator_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_invocation jsonb;
  v_payload jsonb;
  v_identity text;
  v_expected_operator text;
  v_invocation_id text;
  v_inquiry_id text;
  v_offer_ref text;
  v_authority_ref text;
  v_capability_ref text;
  v_release_ref text;
  v_idempotency_key text;
  v_operator_authorization_ref text;
  v_admission_ref text;
  v_authorized_at timestamptz;
  v_kind text;
  v_subject_ref text;
  v_basis_ref text;
  v_policy_ref text;
  v_policy_version_ref text;
  v_requirement_ref text;
  v_operation text;
  v_intent_key text;
  v_boundary_kind text;
  v_boundary_at timestamptz;
  v_row atlas.governed_consequences%rowtype;
  v_created boolean := false;
begin
  if p_operator_user_id is null then
    raise exception 'Verified operator user id is required.' using errcode='22023';
  end if;
  if p_admission is null or jsonb_typeof(p_admission) <> 'object' then
    raise exception 'admission must be an object.' using errcode='22023';
  end if;
  if p_admission->>'contract_version' <> 'consequence_establishment_admission_experiment_v1'
     or p_admission->>'state' <> 'admitted' then
    raise exception 'An admitted consequence establishment contract is required.' using errcode='22023';
  end if;
  if coalesce((p_admission->'truth_boundary'->>'authorityMustRevalidateExactIdentityAtExecution')::boolean,false) is not true
     or coalesce((p_admission->'truth_boundary'->>'admissionExecutesConsequence')::boolean,true) is not false
     or coalesce((p_admission->'truth_boundary'->>'consequenceEstablished')::boolean,true) is not false then
    raise exception 'Admission truth boundary is not executable by this authority.' using errcode='22023';
  end if;

  v_identity := btrim(coalesce(p_admission->>'consequence_identity_key',''));
  v_operator_authorization_ref := btrim(coalesce(p_admission->>'operator_authorization_ref',''));
  v_admission_ref := btrim(coalesce(p_admission->>'admission_ref',''));
  begin
    v_authorized_at := (p_admission->>'authorized_at')::timestamptz;
  exception when others then
    raise exception 'authorized_at must be a timestamp with time zone.' using errcode='22023';
  end;
  if v_identity = '' or v_operator_authorization_ref = '' or v_admission_ref = '' or v_authorized_at is null then
    raise exception 'Admission identity and operator authorization coordinates are required.' using errcode='22023';
  end if;

  v_invocation := p_admission->'invocation';
  if jsonb_typeof(v_invocation) <> 'object'
     or v_invocation->>'contract_version' <> 'reality_capability_invocation_v1' then
    raise exception 'Admission must contain a Reality Capability invocation.' using errcode='22023';
  end if;

  v_invocation_id := btrim(coalesce(v_invocation->>'invocation_id',''));
  v_inquiry_id := btrim(coalesce(v_invocation->>'inquiry_id',''));
  v_offer_ref := btrim(coalesce(v_invocation->>'offer_ref',''));
  v_authority_ref := btrim(coalesce(v_invocation->>'authority_ref',''));
  v_capability_ref := btrim(coalesce(v_invocation->>'capability_ref',''));
  v_release_ref := btrim(coalesce(v_invocation->>'release_ref',''));
  v_idempotency_key := btrim(coalesce(v_invocation->>'idempotency_key',''));
  v_expected_operator := 'auth.users:' || p_operator_user_id::text;

  if v_invocation_id = '' or v_inquiry_id = '' or v_offer_ref = '' or v_idempotency_key = '' then
    raise exception 'Invocation identity fields are required.' using errcode='22023';
  end if;
  if v_invocation->>'operator_ref' is distinct from v_expected_operator then
    raise exception 'Invocation operator does not match the verified operator.' using errcode='42501';
  end if;
  if v_authority_ref <> 'atlas.governed_consequence_authority:v1'
     or v_capability_ref <> 'atlas.capabilities:governed_consequence_establishment_v1'
     or v_release_ref <> 'noel-core-db:governed-consequence-authority-v1' then
    raise exception 'Invocation does not target the admitted governed consequence authority release.' using errcode='22023';
  end if;

  v_payload := v_invocation->'input_payload';
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'Invocation input_payload must be an object.' using errcode='22023';
  end if;

  if btrim(coalesce(v_payload->>'consequence_identity_key','')) is distinct from v_identity then
    raise exception 'Admission and invocation consequence identity differ.' using errcode='22023';
  end if;

  v_kind := btrim(coalesce(v_payload->>'consequence_kind',''));
  v_requirement_ref := btrim(coalesce(v_payload->>'requirement_ref',''));
  v_subject_ref := btrim(coalesce(v_payload->>'subject_ref',''));
  v_basis_ref := btrim(coalesce(v_payload->>'basis_ref',''));
  v_policy_ref := btrim(coalesce(v_payload->>'policy_ref',''));
  v_policy_version_ref := btrim(coalesce(v_payload->>'policy_version_ref',''));
  v_operation := btrim(coalesce(v_payload->>'establishment_operation',''));
  v_intent_key := btrim(coalesce(v_payload->>'temporal_boundary_intent_key',''));
  v_boundary_kind := btrim(coalesce(v_payload->>'boundary_kind',''));

  if v_kind = '' or v_requirement_ref = '' or v_subject_ref = ''
     or v_basis_ref = '' or v_policy_ref = '' or v_policy_version_ref = ''
     or v_operation = '' or v_intent_key = '' or v_boundary_kind = '' then
    raise exception 'Invocation consequence coordinates are incomplete.' using errcode='22023';
  end if;
  if v_operation <> 'consequence.establish' then
    raise exception 'Unsupported governed consequence establishment operation.' using errcode='22023';
  end if;
  begin
    v_boundary_at := (v_payload->>'boundary_at')::timestamptz;
  exception when others then
    raise exception 'boundary_at must be a timestamp with time zone.' using errcode='22023';
  end;
  if v_boundary_at is null then
    raise exception 'boundary_at is required.' using errcode='22023';
  end if;

  insert into atlas.governed_consequences(
    consequence_identity_key, consequence_kind, subject_ref, basis_ref,
    policy_ref, policy_version_ref, requirement_ref, authority_ref,
    establishment_operation, temporal_boundary_intent_key, boundary_kind,
    boundary_at, operator_user_id, operator_authorization_ref, admission_ref,
    authorized_at, invocation_id, offer_ref, capability_ref, release_ref,
    idempotency_key, metadata
  ) values (
    v_identity, v_kind, v_subject_ref, v_basis_ref,
    v_policy_ref, v_policy_version_ref, v_requirement_ref, v_authority_ref,
    v_operation, v_intent_key, v_boundary_kind,
    v_boundary_at, p_operator_user_id, v_operator_authorization_ref, v_admission_ref,
    v_authorized_at, v_invocation_id, v_offer_ref, v_capability_ref, v_release_ref,
    v_idempotency_key,
    jsonb_build_object(
      'inquiryId',v_inquiry_id,
      'receiptIsCanonicalTruth',false,
      'atomicIdentityRevalidation',true,
      'serviceRoleCreatesOperatorAuthority',false
    )
  )
  on conflict (consequence_identity_key) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_row
    from atlas.governed_consequences
    where consequence_identity_key = v_identity;

    if v_row.id is null then
      raise exception 'Canonical consequence identity could not be resolved after conflict.' using errcode='40001';
    end if;

    if v_row.consequence_kind is distinct from v_kind
       or v_row.subject_ref is distinct from v_subject_ref
       or v_row.basis_ref is distinct from v_basis_ref
       or v_row.policy_ref is distinct from v_policy_ref
       or v_row.policy_version_ref is distinct from v_policy_version_ref
       or v_row.requirement_ref is distinct from v_requirement_ref
       or v_row.authority_ref is distinct from v_authority_ref
       or v_row.establishment_operation is distinct from v_operation
       or v_row.temporal_boundary_intent_key is distinct from v_intent_key
       or v_row.boundary_kind is distinct from v_boundary_kind
       or v_row.boundary_at is distinct from v_boundary_at then
      raise exception 'Canonical consequence identity conflicts with existing Reality.' using errcode='23505';
    end if;
  else
    v_created := true;
  end if;

  return jsonb_build_object(
    'contract_version','reality_capability_receipt_v1',
    'receipt_ref','governed-consequence-receipt:' || v_invocation_id,
    'invocation_id',v_invocation_id,
    'inquiry_id',v_inquiry_id,
    'offer_ref',v_offer_ref,
    'authority_ref',v_authority_ref,
    'capability_ref',v_capability_ref,
    'release_ref',v_release_ref,
    'result_state','completed',
    'canonical_result_refs',jsonb_build_array('atlas.governed_consequences:' || v_row.id::text),
    'effect_refs',jsonb_build_array(case when v_created then 'governed-consequence:created' else 'governed-consequence:already-established' end),
    'basis_refs',jsonb_build_array(v_identity,v_requirement_ref,v_basis_ref,v_policy_version_ref),
    'recorded_at',clock_timestamp(),
    'created',v_created,
    'consequence_identity_key',v_identity,
    'truth_boundary',jsonb_build_object(
      'receiptIsCanonicalTruth',false,
      'canonicalReadbackRequired',true,
      'atomicIdentityRevalidationPerformed',true,
      'serviceRoleCreatesOperatorAuthority',false
    )
  );
end;
$function$;

revoke all on function atlas.establish_governed_consequence_service_v1(jsonb,uuid) from public, anon, authenticated;
grant execute on function atlas.establish_governed_consequence_service_v1(jsonb,uuid) to service_role;

create or replace function public.establish_governed_consequence_service_v1(
  p_admission jsonb,
  p_operator_user_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select atlas.establish_governed_consequence_service_v1(p_admission,p_operator_user_id);
$function$;

revoke all on function public.establish_governed_consequence_service_v1(jsonb,uuid) from public, anon, authenticated;
grant execute on function public.establish_governed_consequence_service_v1(jsonb,uuid) to service_role;

create or replace function atlas.governed_consequence_by_identity_service_v1(
  p_consequence_identity_key text,
  p_as_of timestamptz
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select case when c.id is null then null else jsonb_build_object(
    'contractVersion','governed_consequence_canonical_read_v1',
    'consequenceRef','atlas.governed_consequences:' || c.id::text,
    'consequenceIdentityKey',c.consequence_identity_key,
    'consequenceKind',c.consequence_kind,
    'subjectRef',c.subject_ref,
    'basisRef',c.basis_ref,
    'policyRef',c.policy_ref,
    'policyVersionRef',c.policy_version_ref,
    'requirementRef',c.requirement_ref,
    'authorityRef',c.authority_ref,
    'establishmentOperation',c.establishment_operation,
    'temporalBoundaryIntentKey',c.temporal_boundary_intent_key,
    'boundaryKind',c.boundary_kind,
    'boundaryAt',c.boundary_at,
    'operatorRef','auth.users:' || c.operator_user_id::text,
    'operatorAuthorizationRef',c.operator_authorization_ref,
    'admissionRef',c.admission_ref,
    'authorizedAt',c.authorized_at,
    'invocationId',c.invocation_id,
    'offerRef',c.offer_ref,
    'capabilityRef',c.capability_ref,
    'releaseRef',c.release_ref,
    'establishedAt',c.established_at,
    'readAsOf',p_as_of,
    'truthBoundary',jsonb_build_object(
      'canonicalAuthorityRead',true,
      'receiptRequiredForTruth',false
    )
  ) end
  from (
    select gc.*
    from atlas.governed_consequences gc
    where gc.consequence_identity_key = btrim(p_consequence_identity_key)
      and gc.established_at <= p_as_of
    limit 1
  ) c;
$function$;

revoke all on function atlas.governed_consequence_by_identity_service_v1(text,timestamptz) from public, anon, authenticated;
grant execute on function atlas.governed_consequence_by_identity_service_v1(text,timestamptz) to service_role;

create or replace function public.governed_consequence_by_identity_service_v1(
  p_consequence_identity_key text,
  p_as_of timestamptz
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select atlas.governed_consequence_by_identity_service_v1(p_consequence_identity_key,p_as_of);
$function$;

revoke all on function public.governed_consequence_by_identity_service_v1(text,timestamptz) from public, anon, authenticated;
grant execute on function public.governed_consequence_by_identity_service_v1(text,timestamptz) to service_role;
