begin;

-- Laundry Actual -> Consequence Resolution v1.
--
-- Physical Household actuals are source truth. The first consequence clearing
-- law is narrow: laundry_cycle_needed is satisfied by entered_washing.

create or replace function atlas.record_personal_laundry_actual_self_api_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_instance atlas.household_kernel_instances%rowtype;
  v_source_action_id text;
  v_transition text;
  v_to_state text;
  v_occurred_at timestamptz;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Laundry actual input must be an object.' using errcode='22023';
  end if;

  v_source_action_id := nullif(btrim(p_input->>'sourceActionId'),'');
  v_transition := nullif(btrim(p_input->>'transition'),'');

  if v_source_action_id is null or v_transition is null then
    raise exception 'sourceActionId and transition are required.' using errcode='22023';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_input) k(key)
    where k.key not in ('sourceActionId','transition','occurredAt')
  ) then
    raise exception 'Laundry actual V1 accepts sourceActionId, transition, and occurredAt only.'
      using errcode='22023';
  end if;

  if not atlas.personal_reality_timestamp_is_explicit_v1(p_input->>'occurredAt') then
    raise exception 'Laundry actual occurredAt requires an explicit timestamp offset.'
      using errcode='22023';
  end if;

  begin
    v_occurred_at := (p_input->>'occurredAt')::timestamptz;
  exception when others then
    raise exception 'Laundry actual occurredAt is invalid.' using errcode='22023';
  end;

  v_to_state := case v_transition
    when 'entered_washing' then 'washing'
    when 'entered_drying' then 'drying'
    when 'entered_readying' then 'readying'
    when 'returned_to_available' then 'available'
    when 'became_blocked' then 'blocked'
    else null
  end;

  if v_to_state is null then
    raise exception 'Unsupported Laundry actual transition.'
      using errcode='22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  select *
  into v_instance
  from atlas.household_kernel_instances i
  where i.household_id=v_household_id
    and i.kernel_key='household.laundry'
    and i.state='active'
  limit 1;

  if v_instance.id is null then
    raise exception 'Active Laundry instance required before recording an actual.'
      using errcode='42501';
  end if;

  v_result := atlas.record_current_household_claim_evidence_api_v1(
    jsonb_build_object(
      'sourceKey',v_source_action_id||':laundry_actual:'||v_transition,
      'subject',jsonb_build_object(
        'domain','household.laundry',
        'kind','kernel_instance',
        'id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','physical_process_actual',
        'value',jsonb_build_object(
          'transition',v_transition,
          'toState',v_to_state
        ),
        'confidence',1,
        'observedAt',v_occurred_at,
        'provenance',jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'actualContract','personal_laundry_process_actual_v1'
        )
      ),
      'claim',jsonb_build_object(
        'claimType','process_actual',
        'lifecycleState','observed',
        'value',jsonb_build_object(
          'transition',v_transition,
          'toState',v_to_state
        ),
        'confidence',1,
        'validFrom',v_occurred_at,
        'metadata',jsonb_build_object(
          'actualContract','personal_laundry_process_actual_v1',
          'stateTransitionAuthority',true
        )
      )
    )
  );

  return v_result || jsonb_build_object(
    'contractVersion','personal_laundry_process_actual_v1',
    'householdId',v_household_id,
    'instanceId',v_instance.id,
    'transition',v_transition,
    'toState',v_to_state,
    'occurredAt',v_occurred_at,
    'truthBoundary',jsonb_build_object(
      'actualIsPhysicalStateEvidence',true,
      'actualIsNotTaskCompletion',true,
      'actualDoesNotResolveUnrelatedConsequences',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_personal_laundry_actual_self_api_v1(jsonb) is
  'Record one explicit physical Laundry process transition as current-Household Evidence plus observed process_actual Claim. Actual truth is distinct from task completion, Rhythm, and Clock placement.';

revoke all on function atlas.record_personal_laundry_actual_self_api_v1(jsonb)
  from public, anon;
grant execute on function atlas.record_personal_laundry_actual_self_api_v1(jsonb)
  to authenticated, service_role;


create or replace function atlas.personal_laundry_actual_resolution_authority_v1(
  p_owner_user_id uuid,
  p_consequence_instance_id uuid,
  p_actual_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_household_id uuid;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_definition atlas.person_life_definitions%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_transition text;
  v_to_state text;
  v_occurred_at timestamptz;
begin
  if p_owner_user_id is null
     or p_consequence_instance_id is null
     or p_actual_claim_id is null then
    raise exception 'owner, consequence instance, and actual Claim are required.'
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
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  select *
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=p_owner_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open Person Life consequence not found for this owner.'
      using errcode='42501';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=v_instance.definition_id
    and d.owner_user_id=p_owner_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Consequence is not governed by an active Laundry definition.'
      using errcode='42501';
  end if;

  if v_instance.consequence_kind<>'laundry_cycle_needed'
     or v_instance.action_key<>'household.laundry:begin_cycle' then
    raise exception 'Laundry actual resolution V1 supports laundry_cycle_needed only.'
      using errcode='23514';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.id=p_actual_claim_id
    and c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=v_definition.subject_id
    and c.claim_type='process_actual'
    and c.lifecycle_state='observed'
    and c.authority_kind='household_principal_observation';

  if v_claim.id is null then
    raise exception 'Current same-instance Household Laundry process_actual Claim required.'
      using errcode='42501';
  end if;

  select *
  into v_evidence
  from atlas.evidence_records e
  where e.id=v_claim.primary_evidence_id
    and e.scope_kind='household'
    and e.scope_id=v_household_id
    and e.subject_domain='household.laundry'
    and e.subject_kind='kernel_instance'
    and e.subject_id=v_definition.subject_id
    and e.evidence_kind='physical_process_actual'
    and e.source_kind='household_principal_capture'
    and e.provenance->>'actualContract'='personal_laundry_process_actual_v1';

  if v_evidence.id is null then
    raise exception 'Laundry process actual requires same-scope physical_process_actual primary Evidence.'
      using errcode='23514';
  end if;

  if v_claim.value is distinct from v_evidence.value then
    raise exception 'Laundry actual Claim value must equal its primary physical Evidence value.'
      using errcode='23514';
  end if;

  v_transition := nullif(btrim(v_claim.value->>'transition'),'');
  v_to_state := nullif(btrim(v_claim.value->>'toState'),'');
  v_occurred_at := coalesce(v_evidence.observed_at,v_evidence.learned_at);

  if v_transition<>'entered_washing' or v_to_state<>'washing' then
    raise exception 'laundry_cycle_needed is resolved only by entered_washing actual.'
      using errcode='23514';
  end if;

  if v_occurred_at is null then
    raise exception 'Laundry actual lacks canonical occurrence time.'
      using errcode='23514';
  end if;

  if v_occurred_at < v_instance.opened_at then
    raise exception 'Laundry actual predates the consequence requirement it would resolve.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'authorized',true,
    'householdId',v_household_id,
    'consequenceInstanceId',v_instance.id,
    'definitionId',v_definition.id,
    'stableKey',v_instance.stable_key,
    'consequenceKind',v_instance.consequence_kind,
    'actionKey',v_instance.action_key,
    'actualClaimId',v_claim.id,
    'actualEvidenceId',v_evidence.id,
    'transition',v_transition,
    'toState',v_to_state,
    'occurredAt',v_occurred_at,
    'truthBoundary',jsonb_build_object(
      'resolutionComesFromPhysicalActual',true,
      'taskCompletionAuthority',false,
      'actualMustPostdateRequirement',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_actual_resolution_authority_v1(uuid,uuid,uuid) is
  'Internal proof that one Household Laundry process_actual legitimately resolves one open person-owned Laundry consequence. V1 admits entered_washing for laundry_cycle_needed only.';

revoke all on function atlas.personal_laundry_actual_resolution_authority_v1(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.guard_personal_laundry_consequence_resolution_actual_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_definition atlas.person_life_definitions%rowtype;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_actual_claim_id uuid;
  v_authority jsonb;
  v_expected_evidence jsonb;
  v_expected_evaluation jsonb;
begin
  if new.event_kind<>'consequence_resolution' then
    return new;
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=new.definition_id;

  if v_definition.id is null
     or v_definition.subject_domain<>'household.laundry'
     or v_definition.subject_kind<>'kernel_instance' then
    return new;
  end if;

  select *
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.definition_id=new.definition_id
    and i.owner_user_id=new.owner_user_id
    and i.stable_key=new.input_payload->>'stableKey'
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Laundry resolution requires the current open consequence instance.'
      using errcode='23514';
  end if;

  begin
    v_actual_claim_id := nullif(new.input_payload->>'resolutionActualClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'resolutionActualClaimId must be a UUID.'
      using errcode='22023';
  end;

  if v_actual_claim_id is null then
    raise exception 'Laundry consequence resolution requires resolutionActualClaimId; arbitrary completion evidence is not sufficient.'
      using errcode='23514';
  end if;

  v_authority := atlas.personal_laundry_actual_resolution_authority_v1(
    new.owner_user_id,
    v_instance.id,
    v_actual_claim_id
  );

  if new.occurred_at is distinct from (v_authority->>'occurredAt')::timestamptz then
    raise exception 'Laundry consequence resolved_at must equal canonical physical actual time.'
      using errcode='23514';
  end if;

  v_expected_evidence := jsonb_build_object(
    'resolutionAuthority','physical_laundry_actual',
    'consequenceInstanceId',v_instance.id,
    'actualClaimId',(v_authority->>'actualClaimId')::uuid,
    'actualEvidenceId',(v_authority->>'actualEvidenceId')::uuid,
    'transition',v_authority->>'transition',
    'toState',v_authority->>'toState',
    'sourceScope','household'
  );

  if new.evidence is distinct from v_expected_evidence then
    raise exception 'Laundry consequence resolution Evidence must equal the canonical physical-actual envelope.'
      using errcode='23514';
  end if;

  v_expected_evaluation := jsonb_build_object(
    'contractVersion','person_life_consequence_resolution_v1',
    'stableKey',v_instance.stable_key,
    'state','resolved',
    'resolvedAt',new.occurred_at,
    'explicitResolutionEvidence',v_expected_evidence,
    'truthBoundary',jsonb_build_object(
      'resolutionIsExplicitNotInferredFromAbsence',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );

  if new.evaluation is distinct from v_expected_evaluation then
    raise exception 'Laundry consequence resolution evaluation must be database-verifiable from the physical actual.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_personal_laundry_consequence_resolution_actual_v1() is
  'Persistence guard requiring source-backed physical Laundry actual authority for Laundry Person Life consequence resolution. Arbitrary caller completion evidence is rejected.';

revoke all on function atlas.guard_personal_laundry_consequence_resolution_actual_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists personal_laundry_consequence_resolution_actual_guard_v1
  on atlas.person_life_state_events;

create trigger personal_laundry_consequence_resolution_actual_guard_v1
before insert on atlas.person_life_state_events
for each row
execute function atlas.guard_personal_laundry_consequence_resolution_actual_v1();


create or replace function atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(
  p_consequence_instance_id uuid,
  p_actual_claim_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_authority jsonb;
  v_evidence jsonb;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_consequence_instance_id is null or p_actual_claim_id is null then
    raise exception 'consequenceInstanceId and actualClaimId are required.'
      using errcode='22023';
  end if;

  v_authority := atlas.personal_laundry_actual_resolution_authority_v1(
    v_user_id,
    p_consequence_instance_id,
    p_actual_claim_id
  );

  v_evidence := jsonb_build_object(
    'resolutionAuthority','physical_laundry_actual',
    'consequenceInstanceId',p_consequence_instance_id,
    'actualClaimId',(v_authority->>'actualClaimId')::uuid,
    'actualEvidenceId',(v_authority->>'actualEvidenceId')::uuid,
    'transition',v_authority->>'transition',
    'toState',v_authority->>'toState',
    'sourceScope','household'
  );

  v_result := atlas.record_person_life_state_api_v1(
    (v_authority->>'definitionId')::uuid,
    jsonb_build_object(
      'sourceKey',
        'household.laundry:actual_resolution:'
        ||p_consequence_instance_id::text||':'||p_actual_claim_id::text,
      'eventKind','consequence_resolution',
      'stableKey',v_authority->>'stableKey',
      'resolvedAt',v_authority->>'occurredAt',
      'resolutionActualClaimId',p_actual_claim_id,
      'evidence',v_evidence
    )
  );

  return v_result || jsonb_build_object(
    'contractVersion','personal_laundry_actual_consequence_resolution_v1',
    'consequenceInstanceId',p_consequence_instance_id,
    'actualClaimId',p_actual_claim_id,
    'actualEvidenceId',v_authority->>'actualEvidenceId',
    'transition',v_authority->>'transition',
    'toState',v_authority->>'toState',
    'truthBoundary',jsonb_build_object(
      'physicalActualResolvedRequirement',true,
      'taskCompletionDidNotResolveRequirement',true,
      'resolutionUsesExistingPersonLifeEventAuthority',true,
      'resolvedConsequenceLeavesClockCandidateInventoryByStatus',true,
      'doesNotMutateClock',true
    )
  );
end;
$$;

comment on function atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid) is
  'Resolve one owned open Laundry consequence only from a validated same-Household physical process_actual. Uses existing Person Life consequence_resolution persistence after domain-specific authority proof.';

revoke all on function atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)
  from public, anon;
grant execute on function atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)
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
    'atlas.record_personal_laundry_actual_self_api_v1(jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Record explicit physical Laundry state transitions as current-Household Evidence and observed process_actual Claims.',
      'authorizationBoundary','SECURITY DEFINER fixes current Household to auth.uid(); transition vocabulary is closed; occurredAt is explicit; actual is not task completion and creates no Clock placement.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Resolve one owned open Laundry consequence from a validated same-instance physical Household actual.',
      'authorizationBoundary','SECURITY DEFINER requires an open governed Laundry consequence and qualifying Household process_actual. V1 resolves laundry_cycle_needed only from entered_washing and passes canonical evidence through existing Person Life resolution authority.',
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

commit;
