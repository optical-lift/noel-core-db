begin;

-- Laundry Household Evidence -> Person Consequence v1.
--
-- First executable Personal-domain causal rule:
-- accepted Laundry need_generation=accumulation_threshold
-- + observed Laundry present_state=ready_for_cycle
-- -> person-owned laundry_cycle_needed requirement.
--
-- Carrier, readiness, and Clock placement remain unresolved.

create or replace function atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(
  p_owner_user_id uuid,
  p_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_household_id uuid;
  v_claim atlas.claim_records%rowtype;
  v_need_kind text;
  v_requirement_key text;
  v_policy jsonb;
begin
  if p_owner_user_id is null or p_claim_id is null then
    raise exception 'owner user and need-generation Claim id are required.'
      using errcode='22023';
  end if;

  select h.id
  into v_household_id
  from atlas.households h
  join atlas.principals p on p.id=h.principal_id
  where p.user_id=p_owner_user_id
    and p.status='active'
    and h.status='active'
  order by
    case when p.active_household_id=h.id then 0 else 1 end,
    h.created_at,
    h.id
  limit 1;

  if v_household_id is null then
    raise exception 'Active Principal Household required.'
      using errcode='42501';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.id=p_claim_id
    and c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.claim_type='need_generation'
    and c.lifecycle_state='accepted'
    and c.authority_kind='household_principal_acceptance';

  if v_claim.id is null then
    raise exception 'Accepted current-Household Laundry need_generation Claim required.'
      using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.household_kernel_instances i
    where i.id::text=v_claim.subject_id
      and i.household_id=v_household_id
      and i.kernel_key='household.laundry'
      and i.state='active'
  ) then
    raise exception 'Laundry need-generation Claim does not target the active Household Laundry instance.'
      using errcode='23514';
  end if;

  v_need_kind := nullif(btrim(v_claim.value->>'kind'),'');
  v_requirement_key :=
    'household.laundry:'||v_claim.subject_id||':accumulation_cycle_required';

  if v_need_kind<>'accumulation_threshold' then
    return jsonb_build_object(
      'supported',false,
      'needGenerationKind',v_need_kind,
      'householdId',v_household_id,
      'instanceId',v_claim.subject_id,
      'sourceClaimId',v_claim.id,
      'policies','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'unsupportedNeedGenerationIsNotGuessed',true,
        'callerPolicyAuthority',false
      )
    );
  end if;

  v_policy := jsonb_build_object(
    'stableKey',v_requirement_key,
    'active',true,
    'subjectSelector',jsonb_build_object(
      'scope',jsonb_build_object(
        'kind','household',
        'id',v_household_id
      ),
      'subject',jsonb_build_object(
        'domain','household.laundry',
        'kind','kernel_instance',
        'id',v_claim.subject_id
      )
    ),
    'stateMatch',jsonb_build_object(
      'claim',jsonb_build_object(
        'claimType','present_state',
        'lifecycleState','observed',
        'value',jsonb_build_object('state','ready_for_cycle')
      )
    ),
    'consequenceRole','operation_requirement',
    'consequenceKind','laundry_cycle_needed',
    'actionKey','household.laundry:begin_cycle',
    'priority',100,
    'actionSpec',jsonb_build_object(
      'domain','household.laundry',
      'operation','begin_cycle'
    ),
    'metadata',jsonb_build_object(
      'requirementKey',v_requirement_key,
      'ruleSourceClaimId',v_claim.id,
      'needGenerationKind','accumulation_threshold',
      'carrierAuthority',false,
      'clockPlacementAuthority',false
    )
  );

  return jsonb_build_object(
    'supported',true,
    'needGenerationKind',v_need_kind,
    'householdId',v_household_id,
    'instanceId',v_claim.subject_id,
    'sourceClaimId',v_claim.id,
    'requirementKey',v_requirement_key,
    'policies',jsonb_build_array(v_policy),
    'truthBoundary',jsonb_build_object(
      'policyDerivedDeterministicallyFromAcceptedHouseholdFact',true,
      'callerPolicyAuthority',false,
      'carrierAuthority',false,
      'executionReadinessAuthority',false,
      'clockPlacementAuthority',false
    )
  );
end;
$$;

comment on function atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(uuid,uuid) is
  'Internal deterministic adapter from an accepted current-Household Laundry need_generation Claim to the narrow shared consequence policy set. V1 supports accumulation_threshold only and never accepts caller policy JSON.';

revoke all on function atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.guard_personal_laundry_consequence_definition_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_source_claim_id uuid;
  v_policy jsonb;
begin
  if new.signal_kind<>'consequence'
     or new.subject_domain<>'household.laundry' then
    return new;
  end if;

  if new.source_domain<>'claim_evidence'
     or new.source_kind<>'claim' then
    raise exception 'Laundry consequence definitions must be sourced from governed Claim/Evidence authority.'
      using errcode='23514';
  end if;

  begin
    v_source_claim_id := new.source_id::uuid;
  exception when invalid_text_representation then
    raise exception 'Laundry consequence definition source Claim id is invalid.'
      using errcode='23514';
  end;

  v_policy := atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(
    new.owner_user_id,
    v_source_claim_id
  );

  if not coalesce((v_policy->>'supported')::boolean,false) then
    raise exception 'Laundry need-generation Claim is valid household truth but has no executable consequence policy in V1.'
      using errcode='23514';
  end if;

  if new.subject_kind<>'kernel_instance'
     or new.subject_id is distinct from v_policy->>'instanceId' then
    raise exception 'Laundry consequence definition subject must be the same Laundry instance as its causal Claim.'
      using errcode='23514';
  end if;

  if new.engine_packet->'policies' is distinct from v_policy->'policies' then
    raise exception 'Laundry consequence definition policy must equal the deterministic policy derived from accepted need-generation truth.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_personal_laundry_consequence_definition_authority_v1() is
  'Persistence guard for person-owned Laundry consequence definitions. Requires the same current-Household Laundry instance and the exact deterministic policy derived from accepted need_generation truth.';

revoke all on function atlas.guard_personal_laundry_consequence_definition_authority_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists personal_laundry_consequence_definition_authority_guard_v1
  on atlas.person_life_definitions;

create trigger personal_laundry_consequence_definition_authority_guard_v1
before insert or update on atlas.person_life_definitions
for each row
execute function atlas.guard_personal_laundry_consequence_definition_authority_v1();


create or replace function atlas.ensure_personal_laundry_consequence_definition_self_api_v1(
  p_need_generation_claim_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_policy jsonb;
  v_requirement_key text;
  v_packet_policy jsonb;
  v_input_policy jsonb;
  v_signal jsonb;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_policy := atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(
    v_user_id,
    p_need_generation_claim_id
  );

  if not coalesce((v_policy->>'supported')::boolean,false) then
    raise exception 'This Laundry need-generation kind is not executable in consequence V1; Atlas will preserve the fact without guessing a rule.'
      using errcode='22023';
  end if;

  v_requirement_key := v_policy->>'requirementKey';
  v_packet_policy := v_policy->'policies'->0;

  -- life_signal_to_consequence_packet_v1 adds requirementKey into policy
  -- metadata, so remove only that adapter-added key for the canonical input.
  v_input_policy := v_packet_policy || jsonb_build_object(
    'metadata',
    coalesce(v_packet_policy->'metadata','{}'::jsonb) - 'requirementKey'
  );

  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object(
      'kind','person',
      'id',v_user_id
    ),
    'subject',jsonb_build_object(
      'domain','household.laundry',
      'kind','kernel_instance',
      'id',v_policy->>'instanceId'
    ),
    'signalKind','consequence',
    'state','{}'::jsonb,
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(jsonb_build_object(
      'requirementKind','operation_requirement',
      'requirementKey',v_requirement_key,
      'operationKey','household.laundry:begin_cycle',
      'policy',v_input_policy
    )),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object(
      'domain','claim_evidence',
      'kind','claim',
      'id',p_need_generation_claim_id
    ),
    'epistemic',jsonb_build_object(
      'factClass','accepted_household_causal_rule',
      'sourceScope','household',
      'sourceClaimId',p_need_generation_claim_id,
      'adapter','personal_laundry_consequence_policy_from_need_generation_claim_v1'
    )
  );

  v_result := atlas.create_person_life_definition_api_v1(jsonb_build_object(
    'sourceKey','household.laundry:need_generation:'||p_need_generation_claim_id::text,
    'signal',v_signal,
    'metadata',jsonb_build_object(
      'domain','household.laundry',
      'sourceAuthority','accepted_household_need_generation',
      'sourceClaimId',p_need_generation_claim_id,
      'policyDerivedNotCallerSupplied',true
    )
  ));

  return v_result || jsonb_build_object(
    'contractVersion','personal_laundry_consequence_definition_v1',
    'sourceNeedGenerationClaimId',p_need_generation_claim_id,
    'truthBoundary',jsonb_build_object(
      'acceptedNeedGenerationFactIsPolicyAuthority',true,
      'secondPolicyAcceptanceRequired',false,
      'callerPolicyAuthority',false,
      'definitionDoesNotCreateTask',true,
      'definitionDoesNotSelectCarrier',true,
      'definitionDoesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.ensure_personal_laundry_consequence_definition_self_api_v1(uuid) is
  'Ensure the person-owned Laundry consequence definition derived from one accepted current-Household need_generation Claim. Caller supplies Claim identity only; executable policy is deterministic and V1 supports accumulation_threshold only.';

revoke all on function atlas.ensure_personal_laundry_consequence_definition_self_api_v1(uuid)
  from public, anon;
grant execute on function atlas.ensure_personal_laundry_consequence_definition_self_api_v1(uuid)
  to authenticated, service_role;


create or replace function atlas.household_consequence_evidence_snapshot_v1(
  p_owner_user_id uuid,
  p_evidence_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_household_id uuid;
  v_evidence atlas.evidence_records%rowtype;
  v_claim atlas.claim_records%rowtype;
begin
  select h.id
  into v_household_id
  from atlas.households h
  join atlas.principals p on p.id=h.principal_id
  where p.user_id=p_owner_user_id
    and p.status='active'
    and h.status='active'
  order by
    case when p.active_household_id=h.id then 0 else 1 end,
    h.created_at,
    h.id
  limit 1;

  if v_household_id is null then
    raise exception 'Active Principal Household required.'
      using errcode='42501';
  end if;

  select *
  into v_evidence
  from atlas.evidence_records e
  where e.id=p_evidence_id
    and e.scope_kind='household'
    and e.scope_id=v_household_id;

  if v_evidence.id is null then
    raise exception 'Evidence must belong to the current Principal Household.'
      using errcode='42501';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.primary_evidence_id=v_evidence.id
    and c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain=v_evidence.subject_domain
    and c.subject_kind=v_evidence.subject_kind
    and c.subject_id=v_evidence.subject_id
    and c.lifecycle_state not in ('superseded','rejected','expired')
    and (
      c.valid_from is null
      or c.valid_from<=coalesce(v_evidence.observed_at,v_evidence.learned_at)
    )
    and (
      c.valid_until is null
      or c.valid_until>=coalesce(v_evidence.observed_at,v_evidence.learned_at)
    )
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_claim.id is null then
    raise exception 'Household Evidence has no current same-subject Claim and cannot drive a Consequence.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'scope',jsonb_build_object(
      'kind','household',
      'id',v_household_id
    ),
    'subject',jsonb_build_object(
      'domain',v_evidence.subject_domain,
      'kind',v_evidence.subject_kind,
      'id',v_evidence.subject_id
    ),
    'evidence',jsonb_strip_nulls(jsonb_build_object(
      'id',v_evidence.id,
      'kind',v_evidence.evidence_kind,
      'value',v_evidence.value,
      'observedAt',v_evidence.observed_at,
      'learnedAt',v_evidence.learned_at,
      'effectiveFrom',v_evidence.effective_from,
      'effectiveUntil',v_evidence.effective_until
    )),
    'claim',jsonb_strip_nulls(jsonb_build_object(
      'id',v_claim.id,
      'claimType',v_claim.claim_type,
      'lifecycleState',v_claim.lifecycle_state,
      'authorityKind',v_claim.authority_kind,
      'value',v_claim.value,
      'validFrom',v_claim.valid_from,
      'validUntil',v_claim.valid_until
    ))
  );
end;
$$;

comment on function atlas.household_consequence_evidence_snapshot_v1(uuid,uuid) is
  'Internal canonical snapshot builder for person-owned consequences driven by current Principal Household Evidence. It preserves Household custody and requires a current same-subject Claim.';

revoke all on function atlas.household_consequence_evidence_snapshot_v1(uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.guard_household_consequence_evaluation_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_owner uuid;
  v_kind text;
  v_status text;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_source_domain text;
  v_source_kind text;
  v_source_id text;
  v_packet jsonb;
  v_evidence_id uuid;
  v_policy_claim_id uuid;
  v_policy jsonb;
  v_snapshot jsonb;
  v_observation_claim_id uuid;
  v_expected_evaluation jsonb;
  v_expected_evidence jsonb;
  v_evidence_time timestamptz;
begin
  if new.event_kind<>'consequence_evaluation'
     or new.input_payload->>'evidenceScopeKind'<>'household' then
    return new;
  end if;

  select
    d.owner_user_id,
    d.signal_kind,
    d.status,
    d.subject_domain,
    d.subject_kind,
    d.subject_id,
    d.source_domain,
    d.source_kind,
    d.source_id,
    d.engine_packet
  into
    v_owner,
    v_kind,
    v_status,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    v_source_domain,
    v_source_kind,
    v_source_id,
    v_packet
  from atlas.person_life_definitions d
  where d.id=new.definition_id;

  if v_owner is null
     or v_owner is distinct from new.owner_user_id
     or v_kind<>'consequence'
     or v_status<>'active'
     or v_subject_domain<>'household.laundry'
     or v_subject_kind<>'kernel_instance' then
    raise exception 'Household consequence evaluation V1 is admitted only for the active same-owner Laundry consequence definition.'
      using errcode='23514';
  end if;

  if new.input_payload ? 'snapshot'
     or new.input_payload ? 'policies' then
    raise exception 'Household consequence evaluation cannot accept caller-supplied snapshot or policies.'
      using errcode='23514';
  end if;

  if new.input_payload->>'policyScopeKind'<>'household' then
    raise exception 'Laundry Household consequence policy scope must be household.'
      using errcode='23514';
  end if;

  begin
    v_evidence_id := nullif(new.input_payload->>'evidenceId','')::uuid;
    v_policy_claim_id := nullif(new.input_payload->>'policyClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'Household consequence evidenceId and policyClaimId must be UUIDs.'
      using errcode='22023';
  end;

  if v_evidence_id is null or v_policy_claim_id is null then
    raise exception 'Household consequence evaluation requires evidenceId and policyClaimId.'
      using errcode='22023';
  end if;

  if v_source_domain<>'claim_evidence'
     or v_source_kind<>'claim'
     or v_source_id is distinct from v_policy_claim_id::text then
    raise exception 'Laundry consequence policyClaimId must be the definition source Claim.'
      using errcode='23514';
  end if;

  v_policy := atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(
    new.owner_user_id,
    v_policy_claim_id
  );

  if not coalesce((v_policy->>'supported')::boolean,false)
     or v_policy->>'instanceId' is distinct from v_subject_id
     or v_packet->'policies' is distinct from v_policy->'policies' then
    raise exception 'Laundry consequence definition is no longer backed by current accepted need-generation authority.'
      using errcode='23514';
  end if;

  v_snapshot := atlas.household_consequence_evidence_snapshot_v1(
    new.owner_user_id,
    v_evidence_id
  );

  if v_snapshot#>>'{subject,domain}' is distinct from v_subject_domain
     or v_snapshot#>>'{subject,kind}' is distinct from v_subject_kind
     or v_snapshot#>>'{subject,id}' is distinct from v_subject_id then
    raise exception 'Laundry consequence Evidence must describe the same Laundry instance as the definition.'
      using errcode='23514';
  end if;

  select coalesce(e.observed_at,e.learned_at)
  into v_evidence_time
  from atlas.evidence_records e
  where e.id=v_evidence_id;

  if v_evidence_time is null then
    raise exception 'Laundry Household Evidence timestamp is missing.'
      using errcode='23514';
  end if;

  if new.occurred_at is distinct from v_evidence_time then
    raise exception 'Laundry consequence occurred_at must equal canonical Evidence observation/learning time.'
      using errcode='23514';
  end if;

  v_observation_claim_id := (v_snapshot->'claim'->>'id')::uuid;

  v_expected_evaluation := atlas.evaluate_life_state_consequence_policies_v1(
    v_snapshot,
    v_policy->'policies'
  );

  if new.evaluation is distinct from v_expected_evaluation then
    raise exception 'Laundry consequence evaluation must be database-recomputed from Household Evidence and deterministic accepted-rule policy.'
      using errcode='23514';
  end if;

  v_expected_evidence := jsonb_build_object(
    'evidenceId',v_evidence_id,
    'evidenceScopeKind','household',
    'observationClaimId',v_observation_claim_id,
    'policyClaimId',v_policy_claim_id,
    'policyScopeKind','household',
    'snapshot',v_snapshot,
    'policySet',v_policy->'policies',
    'authority',jsonb_build_object(
      'policyClaimType','need_generation',
      'policyClaimLifecycle','accepted',
      'policyAuthorityKind','household_principal_acceptance',
      'policyAdapter','personal_laundry_consequence_policy_from_need_generation_claim_v1',
      'ruleIsSeparateFromObservation',true,
      'causalRuleDerivedFromAcceptedNeedGeneration',true
    )
  );

  if new.evidence is distinct from v_expected_evidence then
    raise exception 'Laundry consequence event Evidence envelope must preserve exact Household observation and causal-rule provenance.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_household_consequence_evaluation_authority_v1() is
  'Persistence guard for Household-evidence person consequence evaluations. V1 admits only Laundry and independently reconstructs Household snapshot, accepted need-generation authority, deterministic policy, and evaluator output.';

revoke all on function atlas.guard_household_consequence_evaluation_authority_v1()
  from public, anon, authenticated, service_role;


-- Preserve the released person Evidence guard for ordinary/person evaluations,
-- but do not let it reject the separately-governed Household path.
drop trigger if exists person_consequence_evaluation_authority_guard_v1
  on atlas.person_life_state_events;

create trigger person_consequence_evaluation_authority_guard_v1
before insert or update on atlas.person_life_state_events
for each row
when (
  new.event_kind<>'consequence_evaluation'
  or coalesce(new.input_payload->>'evidenceScopeKind','person')<>'household'
)
execute function atlas.guard_person_consequence_evaluation_authority_v1();

drop trigger if exists household_consequence_evaluation_authority_guard_v1
  on atlas.person_life_state_events;

create trigger household_consequence_evaluation_authority_guard_v1
before insert or update on atlas.person_life_state_events
for each row
when (
  new.event_kind='consequence_evaluation'
  and new.input_payload->>'evidenceScopeKind'='household'
)
execute function atlas.guard_household_consequence_evaluation_authority_v1();


create or replace function atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(
  p_definition_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_source_key text;
  v_evidence_id uuid;
  v_definition atlas.person_life_definitions%rowtype;
  v_policy_claim_id uuid;
  v_policy jsonb;
  v_snapshot jsonb;
  v_observation_claim_id uuid;
  v_occurred_at timestamptz;
  v_evaluation jsonb;
  v_event_payload jsonb;
  v_event_evidence jsonb;
  v_event_id uuid;
  v_existing_definition_id uuid;
  v_existing_payload jsonb;
  v_existing_evaluation jsonb;
  v_existing_evidence jsonb;
  v_existing_occurred_at timestamptz;
  v_consequence jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Laundry consequence evaluation payload must be an object.'
      using errcode='22023';
  end if;

  v_source_key := nullif(btrim(p_payload->>'sourceKey'),'');
  begin
    v_evidence_id := nullif(p_payload->>'evidenceId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'evidenceId must be a UUID.' using errcode='22023';
  end;

  if v_source_key is null or v_evidence_id is null then
    raise exception 'sourceKey and evidenceId are required.'
      using errcode='22023';
  end if;

  if p_payload ? 'snapshot' or p_payload ? 'policies' then
    raise exception 'snapshot and policies are not accepted; Atlas reconstructs them from custody.'
      using errcode='22023';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance'
    and d.source_domain='claim_evidence'
    and d.source_kind='claim';

  if v_definition.id is null then
    raise exception 'Active governed Laundry consequence definition not found.'
      using errcode='42501';
  end if;

  begin
    v_policy_claim_id := v_definition.source_id::uuid;
  exception when invalid_text_representation then
    raise exception 'Stored Laundry consequence source Claim id is invalid.'
      using errcode='23514';
  end;

  v_policy := atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(
    v_user_id,
    v_policy_claim_id
  );

  if not coalesce((v_policy->>'supported')::boolean,false)
     or v_policy->>'instanceId' is distinct from v_definition.subject_id
     or v_definition.engine_packet->'policies' is distinct from v_policy->'policies' then
    raise exception 'Laundry consequence definition is no longer backed by current accepted need-generation authority.'
      using errcode='23514';
  end if;

  v_snapshot := atlas.household_consequence_evidence_snapshot_v1(
    v_user_id,
    v_evidence_id
  );

  if v_snapshot#>>'{subject,domain}'<>'household.laundry'
     or v_snapshot#>>'{subject,kind}'<>'kernel_instance'
     or v_snapshot#>>'{subject,id}' is distinct from v_definition.subject_id then
    raise exception 'Laundry consequence Evidence must describe the same Laundry instance as the definition.'
      using errcode='23514';
  end if;

  v_observation_claim_id := (v_snapshot->'claim'->>'id')::uuid;

  select coalesce(e.observed_at,e.learned_at)
  into v_occurred_at
  from atlas.evidence_records e
  where e.id=v_evidence_id;

  v_evaluation := atlas.evaluate_life_state_consequence_policies_v1(
    v_snapshot,
    v_policy->'policies'
  );

  v_event_payload := jsonb_build_object(
    'sourceKey',v_source_key,
    'eventKind','consequence_evaluation',
    'evidenceId',v_evidence_id,
    'evidenceScopeKind','household',
    'policyClaimId',v_policy_claim_id,
    'policyScopeKind','household'
  );

  v_event_evidence := jsonb_build_object(
    'evidenceId',v_evidence_id,
    'evidenceScopeKind','household',
    'observationClaimId',v_observation_claim_id,
    'policyClaimId',v_policy_claim_id,
    'policyScopeKind','household',
    'snapshot',v_snapshot,
    'policySet',v_policy->'policies',
    'authority',jsonb_build_object(
      'policyClaimType','need_generation',
      'policyClaimLifecycle','accepted',
      'policyAuthorityKind','household_principal_acceptance',
      'policyAdapter','personal_laundry_consequence_policy_from_need_generation_claim_v1',
      'ruleIsSeparateFromObservation',true,
      'causalRuleDerivedFromAcceptedNeedGeneration',true
    )
  );

  select
    e.id,
    e.definition_id,
    e.input_payload,
    e.evaluation,
    e.evidence,
    e.occurred_at
  into
    v_event_id,
    v_existing_definition_id,
    v_existing_payload,
    v_existing_evaluation,
    v_existing_evidence,
    v_existing_occurred_at
  from atlas.person_life_state_events e
  where e.owner_user_id=v_user_id
    and e.source_key=v_source_key;

  if v_event_id is not null then
    if v_existing_definition_id is distinct from p_definition_id
       or v_existing_payload is distinct from v_event_payload
       or v_existing_evaluation is distinct from v_evaluation
       or v_existing_evidence is distinct from v_event_evidence
       or v_existing_occurred_at is distinct from v_occurred_at then
      raise exception 'sourceKey retry does not match existing Laundry consequence evaluation.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'replayed',true,
      'eventId',v_event_id,
      'definitionId',p_definition_id,
      'evidenceId',v_evidence_id,
      'policyClaimId',v_policy_claim_id,
      'occurredAt',v_occurred_at,
      'evaluation',v_evaluation
    );
  end if;

  insert into atlas.person_life_state_events(
    definition_id,
    owner_user_id,
    event_kind,
    source_key,
    occurred_at,
    input_payload,
    evidence,
    evaluation
  ) values (
    p_definition_id,
    v_user_id,
    'consequence_evaluation',
    v_source_key,
    v_occurred_at,
    v_event_payload,
    v_event_evidence,
    v_evaluation
  )
  returning id into v_event_id;

  for v_consequence in
    select value
    from jsonb_array_elements(
      coalesce(v_evaluation->'openConsequences','[]'::jsonb)
    )
  loop
    insert into atlas.person_life_consequence_instances(
      definition_id,
      owner_user_id,
      stable_key,
      consequence_role,
      consequence_kind,
      action_key,
      requirement_state,
      carrier_ref,
      carrier_state,
      placement_state,
      execution_readiness,
      action_spec,
      evidence,
      opened_by_event_id,
      last_seen_event_id,
      status,
      opened_at
    ) values (
      p_definition_id,
      v_user_id,
      v_consequence->>'stableKey',
      v_consequence->>'consequenceRole',
      nullif(v_consequence->>'consequenceKind',''),
      nullif(v_consequence->>'actionKey',''),
      coalesce(nullif(v_consequence->>'requirementState',''),'established'),
      nullif(v_consequence->>'carrierRef',''),
      coalesce(nullif(v_consequence->>'carrierState',''),'unresolved'),
      coalesce(nullif(v_consequence->>'placementState',''),'unresolved'),
      coalesce(nullif(v_consequence->>'executionReadiness',''),'not_evaluated'),
      coalesce(v_consequence->'actionSpec','{}'::jsonb),
      coalesce(v_consequence->'evidence','{}'::jsonb)
        || jsonb_build_object(
          'sourceEventId',v_event_id,
          'evidenceId',v_evidence_id,
          'evidenceScopeKind','household',
          'observationClaimId',v_observation_claim_id,
          'policyClaimId',v_policy_claim_id,
          'policyScopeKind','household'
        ),
      v_event_id,
      v_event_id,
      'open',
      v_occurred_at
    )
    on conflict(definition_id,stable_key) do update set
      consequence_role=excluded.consequence_role,
      consequence_kind=excluded.consequence_kind,
      action_key=excluded.action_key,
      requirement_state=excluded.requirement_state,
      carrier_ref=excluded.carrier_ref,
      carrier_state=excluded.carrier_state,
      placement_state=excluded.placement_state,
      execution_readiness=excluded.execution_readiness,
      action_spec=excluded.action_spec,
      evidence=excluded.evidence,
      opened_by_event_id=case
        when atlas.person_life_consequence_instances.status='resolved'
          then excluded.opened_by_event_id
        else atlas.person_life_consequence_instances.opened_by_event_id
      end,
      last_seen_event_id=excluded.last_seen_event_id,
      status='open',
      opened_at=case
        when atlas.person_life_consequence_instances.status='resolved'
          then excluded.opened_at
        else atlas.person_life_consequence_instances.opened_at
      end,
      resolved_by_event_id=null,
      resolved_at=null,
      updated_at=now();
  end loop;

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'eventId',v_event_id,
    'definitionId',p_definition_id,
    'evidenceId',v_evidence_id,
    'observationClaimId',v_observation_claim_id,
    'policyClaimId',v_policy_claim_id,
    'occurredAt',v_occurred_at,
    'evaluation',v_evaluation,
    'truthBoundary',jsonb_build_object(
      'observationAndRuleRemainSeparate',true,
      'observationCustody','household',
      'policyAuthority','accepted_household_need_generation',
      'snapshotBuiltFromCanonicalEvidence',true,
      'policyDerivedNotCallerSupplied',true,
      'requirementDoesNotSelectCarrier',true,
      'executionReadinessRemainsSeparate',true,
      'doesNotCreateTask',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb) is
  'Evaluate the person-owned Laundry consequence definition from one current-Household Evidence record. Snapshot and executable policy are reconstructed under database custody from Household Claim/Evidence; carrier, readiness, and Clock placement remain separate.';

revoke all on function atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)
  from public, anon;
grant execute on function atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)
  to authenticated, service_role;


insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values
  (
    'atlas.ensure_personal_laundry_consequence_definition_self_api_v1(p_need_generation_claim_id uuid)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Create/replay the person-owned Laundry consequence definition derived from an accepted current-Household need_generation Claim.',
      'authorizationBoundary','Caller supplies Claim identity only. SECURITY DEFINER derives current Household custody and deterministic Laundry policy. V1 supports accumulation_threshold only and grants no task/carrier/Clock authority.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(p_definition_id uuid, p_payload jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Evaluate the governed person-owned Laundry consequence definition from current-Household Evidence.',
      'authorizationBoundary','SECURITY DEFINER reconstructs Household snapshot and deterministic accepted need-generation policy; caller cannot submit snapshot or policies; result creates requirement projection only and no task/carrier/readiness/Clock authority.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  )
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

do $$
begin
  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1()
  ) then
    raise exception 'Authenticated RPC registry drifted after Laundry Household consequence registration.';
  end if;
end
$$;

commit;
