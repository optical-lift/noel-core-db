-- Atlas semantic exposure envelope v1
--
-- A worker-facing object being presentable does not authorize disclosure of every
-- fact reachable from that object. This membrane governs semantic disclosure
-- after identity/session/routing/presentability have already been established.
--
-- The contract is deliberately default-deny. No source field, claim, relation,
-- or derived fact crosses merely because a server reader can access it. A future
-- adapter must normalize one semantic candidate, and a canonical policy row must
-- explicitly admit that exact adapter + source kind + purpose + information class
-- + semantic predicate. Human prose is rendered after this membrane, never used
-- as the semantic payload that earns admission.

begin;

create table atlas.semantic_exposure_policies (
  policy_key text primary key,
  audience_kind text not null,
  purpose_key text not null,
  information_class text not null,
  semantic_kind text not null,
  predicate_key text not null,
  adapter_key text not null,
  source_domain text not null,
  source_kind text not null,
  allowed_modalities text[] not null default '{}'::text[],
  allowed_adjudication_states text[] not null default '{}'::text[],
  active boolean not null default true,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint semantic_exposure_policy_key_check
    check (policy_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint semantic_exposure_audience_kind_check
    check (audience_kind in ('organization_member')),
  constraint semantic_exposure_purpose_key_check
    check (purpose_key in ('worker_day','employer_drawer','worker_action')),
  constraint semantic_exposure_information_class_check
    check (information_class in (
      'worker_delivery_identity',
      'worker_execution_context',
      'worker_coordination_context',
      'worker_institutional_intelligence',
      'organization_internal',
      'person_private',
      'restricted'
    )),
  constraint semantic_exposure_semantic_kind_check
    check (semantic_kind in (
      'work_identity',
      'temporal_contract',
      'requirement_state',
      'claim',
      'result_summary',
      'reference'
    )),
  constraint semantic_exposure_predicate_key_check
    check (predicate_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint semantic_exposure_adapter_key_check
    check (adapter_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint semantic_exposure_source_domain_check
    check (source_domain ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint semantic_exposure_source_kind_check
    check (source_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint semantic_exposure_modalities_check
    check (
      allowed_modalities <@ array[
        'observed',
        'authoritative_assertion',
        'derived',
        'planned',
        'forecast',
        'estimated',
        'unknown'
      ]::text[]
    ),
  constraint semantic_exposure_adjudication_states_check
    check (
      allowed_adjudication_states <@ array[
        'current',
        'accepted',
        'disputed',
        'rejected',
        'superseded',
        'expired'
      ]::text[]
    ),
  constraint semantic_exposure_claim_policy_shape_check
    check (
      (
        semantic_kind = 'claim'
        and cardinality(allowed_modalities) > 0
        and cardinality(allowed_adjudication_states) > 0
      )
      or
      (
        semantic_kind <> 'claim'
        and cardinality(allowed_modalities) = 0
        and cardinality(allowed_adjudication_states) = 0
      )
    ),
  constraint semantic_exposure_forbidden_class_admission_check
    check (
      not active
      or information_class not in ('organization_internal','person_private','restricted')
    ),
  unique (
    audience_kind,
    purpose_key,
    information_class,
    semantic_kind,
    predicate_key,
    adapter_key,
    source_domain,
    source_kind
  )
);

comment on table atlas.semantic_exposure_policies is
  'Canonical allow-list for semantic disclosure after authorization and object presentability. Absence of an exact active policy is denial. This is not a role/permission system: audience identity is established elsewhere; this table governs which normalized semantic facts may cross for a declared purpose.';
comment on column atlas.semantic_exposure_policies.information_class is
  'Disclosure classification of the semantic candidate. organization_internal, person_private, and restricted cannot be actively admitted through the organization-member envelope.';
comment on column atlas.semantic_exposure_policies.adapter_key is
  'Exact reviewed adapter that is allowed to normalize this semantic candidate. Prevents a generic server reader from laundering arbitrary raw fields into an admitted class.';
comment on column atlas.semantic_exposure_policies.allowed_modalities is
  'For claim policies only. Claim modality remains explicit and is never inferred from wording.';
comment on column atlas.semantic_exposure_policies.allowed_adjudication_states is
  'For claim policies only. Adjudication is independent from epistemic modality.';

alter table atlas.semantic_exposure_policies enable row level security;
revoke all on table atlas.semantic_exposure_policies from public, anon, authenticated;
grant select,insert,update,delete on table atlas.semantic_exposure_policies to service_role;

create index semantic_exposure_policies_lookup_idx
  on atlas.semantic_exposure_policies(
    audience_kind,
    purpose_key,
    adapter_key,
    source_domain,
    source_kind,
    information_class,
    semantic_kind,
    predicate_key
  )
  where active;

create or replace function atlas.semantic_exposure_candidate_shape_valid_v1(p_candidate jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select
    jsonb_typeof(p_candidate) = 'object'
    and (
      p_candidate - array[
        'adapterKey',
        'informationClass',
        'semanticKind',
        'predicateKey',
        'sourceDomain',
        'sourceKind',
        'sourceId',
        'valueKind',
        'value',
        'valueUnit',
        'claimId'
      ]::text[]
    ) = '{}'::jsonb
    and jsonb_typeof(p_candidate->'adapterKey') = 'string'
    and jsonb_typeof(p_candidate->'informationClass') = 'string'
    and jsonb_typeof(p_candidate->'semanticKind') = 'string'
    and jsonb_typeof(p_candidate->'predicateKey') = 'string'
    and jsonb_typeof(p_candidate->'sourceDomain') = 'string'
    and jsonb_typeof(p_candidate->'sourceKind') = 'string'
    and jsonb_typeof(p_candidate->'sourceId') = 'string'
    and jsonb_typeof(p_candidate->'valueKind') = 'string'
    and p_candidate ? 'value'
    and (
      not (p_candidate ? 'valueUnit')
      or p_candidate->'valueUnit' = 'null'::jsonb
      or jsonb_typeof(p_candidate->'valueUnit') = 'string'
    )
    and (
      not (p_candidate ? 'claimId')
      or p_candidate->'claimId' = 'null'::jsonb
      or jsonb_typeof(p_candidate->'claimId') = 'string'
    );
$$;

comment on function atlas.semantic_exposure_candidate_shape_valid_v1(jsonb) is
  'Strict normalized-candidate shape validator. Unknown top-level keys are rejected, so raw title/instructions/detail/metadata fields cannot hitchhike through the exposure membrane.';

revoke all on function atlas.semantic_exposure_candidate_shape_valid_v1(jsonb) from public, anon, authenticated;
grant execute on function atlas.semantic_exposure_candidate_shape_valid_v1(jsonb) to service_role;

create or replace function atlas.semantic_exposure_envelope_v1(
  p_organization_id uuid,
  p_audience_membership_id uuid,
  p_purpose_key text,
  p_candidate jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_membership atlas.organization_memberships%rowtype;
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
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','invalid_audience_context'
    );
  end if;

  select * into v_membership
  from atlas.organization_memberships m
  where m.id = p_audience_membership_id
    and m.organization_id = p_organization_id
    and m.active = true;

  if v_membership.id is null then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','inactive_or_foreign_membership'
    );
  end if;

  if p_purpose_key not in ('worker_day','employer_drawer','worker_action') then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','unsupported_purpose'
    );
  end if;

  if not atlas.semantic_exposure_candidate_shape_valid_v1(p_candidate) then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','invalid_candidate_shape'
    );
  end if;

  v_adapter_key := btrim(p_candidate->>'adapterKey');
  v_information_class := btrim(p_candidate->>'informationClass');
  v_semantic_kind := btrim(p_candidate->>'semanticKind');
  v_predicate_key := btrim(p_candidate->>'predicateKey');
  v_source_domain := btrim(p_candidate->>'sourceDomain');
  v_source_kind := btrim(p_candidate->>'sourceKind');
  v_source_id := btrim(p_candidate->>'sourceId');
  v_value_kind := btrim(p_candidate->>'valueKind');
  v_value := p_candidate->'value';
  v_value_unit := nullif(btrim(coalesce(p_candidate->>'valueUnit','')),'');

  if v_adapter_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_predicate_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_domain !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_id = '' then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','invalid_semantic_identity'
    );
  end if;

  if v_information_class in ('organization_internal','person_private','restricted') then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','information_class_not_worker_exposable'
    );
  end if;

  if not atlas.claim_value_matches_kind_v2(v_value_kind, v_value) then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','invalid_typed_value'
    );
  end if;

  if v_value_unit is not null and (
    v_value_kind <> 'number'
    or v_value_unit !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','invalid_value_unit'
    );
  end if;

  select * into v_policy
  from atlas.semantic_exposure_policies p
  where p.active
    and p.audience_kind = 'organization_member'
    and p.purpose_key = p_purpose_key
    and p.information_class = v_information_class
    and p.semantic_kind = v_semantic_kind
    and p.predicate_key = v_predicate_key
    and p.adapter_key = v_adapter_key
    and p.source_domain = v_source_domain
    and p.source_kind = v_source_kind
  limit 1;

  if v_policy.policy_key is null then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','no_explicit_admission_policy'
    );
  end if;

  if v_semantic_kind = 'claim' then
    begin
      v_claim_id := nullif(btrim(coalesce(p_candidate->>'claimId','')),'')::uuid;
    exception when invalid_text_representation then
      v_claim_id := null;
    end;

    if v_claim_id is null then
      return jsonb_build_object(
        'contractVersion','semantic_exposure_envelope_v1',
        'admitted',false,
        'reason','claim_identity_required'
      );
    end if;

    select * into v_claim from atlas.claim_records c where c.id = v_claim_id;

    if v_claim.id is null
       or v_claim.semantic_contract_version is distinct from 'claim-v2'
       or v_claim.scope_kind is distinct from 'organization'
       or v_claim.scope_id is distinct from p_organization_id then
      return jsonb_build_object(
        'contractVersion','semantic_exposure_envelope_v1',
        'admitted',false,
        'reason','claim_outside_exposure_custody'
      );
    end if;

    if v_claim.predicate_key is distinct from v_predicate_key
       or v_claim.value_kind is distinct from v_value_kind
       or v_claim.value is distinct from v_value
       or v_claim.value_unit is distinct from v_value_unit then
      return jsonb_build_object(
        'contractVersion','semantic_exposure_envelope_v1',
        'admitted',false,
        'reason','claim_projection_mismatch'
      );
    end if;

    if not (v_claim.modality = any(v_policy.allowed_modalities)) then
      return jsonb_build_object(
        'contractVersion','semantic_exposure_envelope_v1',
        'admitted',false,
        'reason','claim_modality_not_admitted'
      );
    end if;

    if not (v_claim.adjudication_state = any(v_policy.allowed_adjudication_states)) then
      return jsonb_build_object(
        'contractVersion','semantic_exposure_envelope_v1',
        'admitted',false,
        'reason','claim_adjudication_not_admitted'
      );
    end if;

    if (v_claim.valid_from is not null and v_claim.valid_from > v_now)
       or (v_claim.valid_until is not null and v_claim.valid_until <= v_now) then
      return jsonb_build_object(
        'contractVersion','semantic_exposure_envelope_v1',
        'admitted',false,
        'reason','claim_not_current_in_time'
      );
    end if;
  elsif nullif(btrim(coalesce(p_candidate->>'claimId','')),'') is not null then
    return jsonb_build_object(
      'contractVersion','semantic_exposure_envelope_v1',
      'admitted',false,
      'reason','claim_identity_on_non_claim_candidate'
    );
  end if;

  v_envelope := jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','semantic_exposure_envelope_v1',
    'organizationId',p_organization_id,
    'audienceMembershipId',p_audience_membership_id,
    'audienceKind','organization_member',
    'purposeKey',p_purpose_key,
    'informationClass',v_information_class,
    'semanticKind',v_semantic_kind,
    'predicateKey',v_predicate_key,
    'value',jsonb_strip_nulls(jsonb_build_object(
      'kind',v_value_kind,
      'value',v_value,
      'unit',v_value_unit
    )),
    'provenance',jsonb_strip_nulls(jsonb_build_object(
      'policyKey',v_policy.policy_key,
      'adapterKey',v_adapter_key,
      'source',jsonb_build_object(
        'domain',v_source_domain,
        'kind',v_source_kind,
        'id',v_source_id
      ),
      'claim',case when v_claim.id is not null then jsonb_build_object(
        'id',v_claim.id,
        'modality',v_claim.modality,
        'adjudicationState',v_claim.adjudication_state,
        'primaryEvidenceId',v_claim.primary_evidence_id
      ) else null end
    ))
  ));

  return jsonb_build_object(
    'contractVersion','semantic_exposure_envelope_v1',
    'admitted',true,
    'reason','explicit_policy_admission',
    'envelope',v_envelope
  );
end;
$$;

comment on function atlas.semantic_exposure_envelope_v1(uuid,uuid,text,jsonb) is
  'Default-deny semantic disclosure membrane for organization-member surfaces. It validates active audience membership, strict normalized candidate shape, typed values, exact policy admission, and claim-v2 custody/modality/adjudication/time when the candidate is a claim. It never returns raw source rows or human prose.';

revoke all on function atlas.semantic_exposure_envelope_v1(uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function atlas.semantic_exposure_envelope_v1(uuid,uuid,text,jsonb) to service_role;

-- Deliberately seed no admission policies in v1. Existing title-only Worker Day
-- remains a compatibility surface from A1. Every new richer disclosure, including
-- future employer-drawer intelligence, must arrive with its own reviewed adapter
-- and exact policy migration. This makes the initial state fail closed.

commit;
