begin;

-- ============================================================================
-- Laundry closed-loop tranche 1: atlas-personal-laundry-authority-split-v1
-- ============================================================================

-- Atlas Personal Laundry authority split v1.
--
-- This candidate repairs one invalid authority transition:
-- household-specific Laundry calibration may establish descriptive instance truth,
-- but it may not manufacture Household Rhythm, Principal responsibility, capacity
-- blocking, or Clock priority.
--
-- The existing public wrapper remains unchanged and continues to call this
-- function by signature.

create or replace function atlas.calibrate_personal_laundry_kernel_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_kernel_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_model_key text;
  v_config jsonb := '{}'::jsonb;
  v_location text;
  v_pattern text;
  v_special text[];
  v_notes text;
  v_expected integer;
  v_instance atlas.household_kernel_instances%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'Laundry calibration input must be an object.' using errcode = '22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  select max(k.version) into v_kernel_version
  from atlas.world_kernel_definitions k
  where k.kernel_key = 'household.laundry'
    and k.active;

  if v_kernel_version is null then
    raise exception 'Active Laundry world kernel required.' using errcode = '23514';
  end if;

  v_model_key := nullif(trim(p_input->>'modelKey'), '');
  if v_model_key is not null then
    select * into v_model
    from atlas.world_kernel_models m
    where m.kernel_key = 'household.laundry'
      and m.kernel_version = v_kernel_version
      and m.model_key = v_model_key
      and m.active;

    if v_model.model_key is null then
      raise exception 'Unknown Laundry model.' using errcode = '22023';
    end if;

    -- A model is generic starting knowledge. Its values become household
    -- calibration only because this signed-in Principal explicitly selected it.
    v_config := v_model.configuration;
  end if;

  v_config := v_config || jsonb_strip_nulls(jsonb_build_object(
    'laundryLocation', nullif(trim(p_input->>'laundryLocation'), ''),
    'usualPattern', nullif(trim(p_input->>'usualPattern'), ''),
    'notes', nullif(trim(p_input->>'notes'), ''),
    'expectedMinutes',
      case
        when nullif(p_input->>'expectedMinutes','') is null then null
        else (p_input->>'expectedMinutes')::integer
      end
  ));

  if p_input ? 'specialTurnaround' then
    v_config := v_config || jsonb_build_object('specialTurnaround', p_input->'specialTurnaround');
  end if;

  v_location := nullif(trim(v_config->>'laundryLocation'), '');
  v_pattern := nullif(trim(v_config->>'usualPattern'), '');
  v_notes := nullif(trim(v_config->>'notes'), '');
  v_expected := coalesce(nullif(v_config->>'expectedMinutes','')::integer, 45);

  if v_location is not null
     and v_location not in ('home','shared_machines','laundromat','service','other') then
    raise exception 'Unsupported laundryLocation.' using errcode = '22023';
  end if;

  if v_pattern is not null
     and v_pattern not in ('little_most_days','few_times_week','main_day','as_needed','other') then
    raise exception 'Unsupported usualPattern.' using errcode = '22023';
  end if;

  if v_expected <= 0 then
    raise exception 'expectedMinutes must be positive.' using errcode = '22023';
  end if;

  select coalesce(array_agg(x), '{}'::text[])
    into v_special
  from jsonb_array_elements_text(coalesce(v_config->'specialTurnaround', '[]'::jsonb)) t(x);

  v_config := v_config || jsonb_build_object('specialTurnaround', to_jsonb(v_special));

  if v_location is null or v_pattern is null then
    raise exception 'Laundry location and usual pattern are required after model selection/calibration.'
      using errcode = '22023';
  end if;

  insert into atlas.household_kernel_instances (
    household_id,
    kernel_key,
    kernel_version,
    state,
    configuration,
    calibrated_at,
    metadata
  ) values (
    v_household_id,
    'household.laundry',
    v_kernel_version,
    'active',
    v_config,
    now(),
    jsonb_strip_nulls(jsonb_build_object(
      'source', 'principal_calibration',
      'calibratedBy', auth.uid(),
      'calibrationContract', 'household_laundry_calibration_v2',
      'selectedModelKey', v_model_key,
      'selectedModelAudience',
        case when v_model_key is null then null else v_model.audience_key end,
      'rhythmAuthoritySeparate', true
    ))
  )
  on conflict (household_id, kernel_key) do update set
    kernel_version = excluded.kernel_version,
    state = 'active',
    configuration = atlas.household_kernel_instances.configuration || excluded.configuration,
    calibrated_at = now(),
    metadata = atlas.household_kernel_instances.metadata || excluded.metadata,
    updated_at = now()
  returning * into v_instance;

  -- Intentionally no Household Rhythm write here.
  --
  -- usualPattern remains descriptive calibration evidence only. A future or
  -- existing Rhythm must be established through its own authority path from
  -- explicit recurrence truth or evidence-backed learning. Calibration also
  -- does not delete an already-authorized Rhythm.

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'household_laundry_calibration_v2',
    'selectedModelKey', v_model_key,
    'instance', jsonb_build_object(
      'id', v_instance.id,
      'state', v_instance.state,
      'configuration', v_instance.configuration,
      'calibratedAt', v_instance.calibrated_at
    ),
    'rhythm', null,
    'rhythmMutation', 'none',
    'truthBoundary', jsonb_build_object(
      'calibrationEstablishesInstanceOnly', true,
      'usualPatternIsDescriptiveNotScheduleAuthority', true,
      'calibrationDoesNotCreateRhythm', true,
      'calibrationDoesNotModifyRhythm', true,
      'calibrationDoesNotDeleteRhythm', true,
      'calibrationDoesNotAssignPrincipalResponsibility', true,
      'calibrationDoesNotCreateClockPlacement', true
    ),
    'claimsCreated', jsonb_build_object(
      'washerOwned', false,
      'dryerOwned', false,
      'childExists', false,
      'sportsUniformExists', false
    )
  );
end;
$$;

comment on function atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb) is
  'Calibrate the signed-in Principal household Laundry instance from explicit/model-backed household input. Calibration is descriptive instance authority only: it creates, modifies, and deletes no Household Rhythm and grants no Clock or Principal-responsibility authority.';

-- ============================================================================
-- Laundry closed-loop tranche 2: atlas-household-claim-evidence-membrane-v1
-- ============================================================================

-- Atlas Household Claim / Evidence authority membrane v1.
--
-- The universal Claim/Evidence tables already support arbitrary custody scopes,
-- but their initial authenticated membrane intentionally exposed person scope only.
-- This candidate opens exactly one additional authority envelope:
-- the signed-in active Principal may record explicit first-party evidence/claims
-- for that Principal's current active Household.
--
-- No direct authenticated table write is granted. No task, carrier, consequence,
-- rhythm, or Clock authority is granted.

create or replace function atlas.record_current_household_claim_evidence_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_household_id uuid;
  v_source_key text;
  v_subject jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_evidence jsonb;
  v_claim jsonb;
  v_evidence_kind text;
  v_claim_type text;
  v_lifecycle text;
  v_authority text;
  v_confidence numeric;
  v_evidence_confidence numeric;
  v_supersedes_claim_id uuid;
  v_old_state text;
  v_evidence_id uuid;
  v_claim_id uuid;
  v_created_evidence boolean := false;
  v_created_claim boolean := false;
  v_existing_value jsonb;
  v_existing_metadata jsonb;
  v_existing_provenance jsonb;
  v_existing_observed_at timestamptz;
  v_existing_effective_from timestamptz;
  v_existing_effective_until timestamptz;
  v_existing_confidence numeric;
  v_existing_claim_type text;
  v_existing_lifecycle text;
  v_existing_authority text;
  v_existing_primary_evidence_id uuid;
  v_existing_supersedes_claim_id uuid;
  v_existing_valid_from timestamptz;
  v_existing_valid_until timestamptz;
  v_updated integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  v_subject := p_payload->'subject';
  v_evidence := p_payload->'evidence';
  v_claim := p_payload->'claim';

  if v_source_key='' then
    raise exception 'sourceKey is required.' using errcode='22023';
  end if;
  if jsonb_typeof(v_subject)<>'object'
     or jsonb_typeof(v_evidence)<>'object'
     or jsonb_typeof(v_claim)<>'object' then
    raise exception 'subject, evidence, and claim objects are required.' using errcode='22023';
  end if;

  v_subject_domain := btrim(coalesce(v_subject->>'domain',''));
  v_subject_kind := btrim(coalesce(v_subject->>'kind',''));
  v_subject_id := btrim(coalesce(v_subject->>'id',''));

  if v_subject_domain='' or v_subject_kind='' or v_subject_id='' then
    raise exception 'subject.domain, subject.kind, and subject.id are required.' using errcode='22023';
  end if;

  -- This membrane is intentionally Household-domain-only. A current Household
  -- does not become authority for arbitrary person, organization, money, health,
  -- or other domain Claims merely because the same Principal can reach them.
  if v_subject_domain <> 'household'
     and v_subject_domain not like 'household.%' then
    raise exception 'Household Claim/Evidence subjects must use the household domain.'
      using errcode='22023';
  end if;

  v_evidence_kind := btrim(coalesce(v_evidence->>'kind',''));
  v_claim_type := btrim(coalesce(v_claim->>'claimType',''));
  v_lifecycle := btrim(coalesce(v_claim->>'lifecycleState',''));

  if v_evidence_kind='' or v_claim_type='' or v_lifecycle='' then
    raise exception 'evidence.kind, claim.claimType, and claim.lifecycleState are required.'
      using errcode='22023';
  end if;

  if v_lifecycle not in ('reported','observed','proposed','accepted','rejected','unknown') then
    raise exception 'Household first-party capture cannot author inferred, superseded, or expired claim state.'
      using errcode='22023';
  end if;

  if not (v_evidence ? 'value') or not (v_claim ? 'value') then
    raise exception 'evidence.value and claim.value are required, including explicit JSON null when that is the evidence.'
      using errcode='22023';
  end if;

  if v_evidence ? 'confidence' then
    v_evidence_confidence := (v_evidence->>'confidence')::numeric;
    if v_evidence_confidence < 0 or v_evidence_confidence > 1 then
      raise exception 'evidence confidence must be between 0 and 1.' using errcode='22023';
    end if;
  end if;

  if v_claim ? 'confidence' then
    v_confidence := (v_claim->>'confidence')::numeric;
    if v_confidence < 0 or v_confidence > 1 then
      raise exception 'claim confidence must be between 0 and 1.' using errcode='22023';
    end if;
  end if;

  begin
    v_supersedes_claim_id := nullif(v_claim->>'supersedesClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'supersedesClaimId must be a UUID.' using errcode='22023';
  end;

  v_authority := case
    when v_supersedes_claim_id is not null then 'household_principal_correction'
    when v_lifecycle='observed' then 'household_principal_observation'
    when v_lifecycle='accepted' then 'household_principal_acceptance'
    when v_lifecycle='rejected' then 'household_principal_rejection'
    when v_lifecycle='proposed' then 'household_principal_proposal'
    else 'household_principal_report'
  end;

  if v_supersedes_claim_id is not null then
    select c.lifecycle_state
      into v_old_state
    from atlas.claim_records c
    where c.id=v_supersedes_claim_id
      and c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain=v_subject_domain
      and c.subject_kind=v_subject_kind
      and c.subject_id=v_subject_id;

    if v_old_state is null then
      raise exception 'supersedesClaimId must identify the current Principal household claim for the same subject.'
        using errcode='42501';
    end if;
  end if;

  insert into atlas.evidence_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    evidence_kind,
    source_kind,
    source_key,
    actor_user_id,
    value,
    confidence,
    observed_at,
    effective_from,
    effective_until,
    provenance,
    metadata
  ) values (
    'household',
    v_household_id,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    v_evidence_kind,
    'household_principal_capture',
    v_source_key,
    v_user_id,
    v_evidence->'value',
    v_evidence_confidence,
    nullif(v_evidence->>'observedAt','')::timestamptz,
    nullif(v_evidence->>'effectiveFrom','')::timestamptz,
    nullif(v_evidence->>'effectiveUntil','')::timestamptz,
    coalesce(v_evidence->'provenance','{}'::jsonb)
      || jsonb_build_object('householdId',v_household_id,'principalUserId',v_user_id),
    coalesce(v_evidence->'metadata','{}'::jsonb)
  )
  on conflict (scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_id;

  if v_evidence_id is not null then
    v_created_evidence := true;
  else
    select
      e.id,
      e.value,
      e.metadata,
      e.provenance,
      e.observed_at,
      e.effective_from,
      e.effective_until,
      e.confidence
    into
      v_evidence_id,
      v_existing_value,
      v_existing_metadata,
      v_existing_provenance,
      v_existing_observed_at,
      v_existing_effective_from,
      v_existing_effective_until,
      v_existing_confidence
    from atlas.evidence_records e
    where e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.source_kind='household_principal_capture'
      and e.source_key=v_source_key
      and e.subject_domain=v_subject_domain
      and e.subject_kind=v_subject_kind
      and e.subject_id=v_subject_id
      and e.evidence_kind=v_evidence_kind;

    if v_evidence_id is null
       or v_existing_value is distinct from v_evidence->'value'
       or v_existing_metadata is distinct from coalesce(v_evidence->'metadata','{}'::jsonb)
       or v_existing_provenance is distinct from (
         coalesce(v_evidence->'provenance','{}'::jsonb)
         || jsonb_build_object('householdId',v_household_id,'principalUserId',v_user_id)
       )
       or v_existing_observed_at is distinct from nullif(v_evidence->>'observedAt','')::timestamptz
       or v_existing_effective_from is distinct from nullif(v_evidence->>'effectiveFrom','')::timestamptz
       or v_existing_effective_until is distinct from nullif(v_evidence->>'effectiveUntil','')::timestamptz
       or v_existing_confidence is distinct from v_evidence_confidence then
      raise exception 'sourceKey retry does not match existing Household evidence.'
        using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    claim_type,
    lifecycle_state,
    authority_kind,
    source_kind,
    source_key,
    value,
    confidence,
    primary_evidence_id,
    supersedes_claim_id,
    valid_from,
    valid_until,
    metadata
  ) values (
    'household',
    v_household_id,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    v_claim_type,
    v_lifecycle,
    v_authority,
    'household_principal_capture',
    v_source_key,
    v_claim->'value',
    v_confidence,
    v_evidence_id,
    v_supersedes_claim_id,
    nullif(v_claim->>'validFrom','')::timestamptz,
    nullif(v_claim->>'validUntil','')::timestamptz,
    coalesce(v_claim->'metadata','{}'::jsonb)
  )
  on conflict (scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_claim_id;

  if v_claim_id is not null then
    v_created_claim := true;
  else
    select
      c.id,
      c.claim_type,
      c.lifecycle_state,
      c.authority_kind,
      c.value,
      c.metadata,
      c.confidence,
      c.primary_evidence_id,
      c.supersedes_claim_id,
      c.valid_from,
      c.valid_until
    into
      v_claim_id,
      v_existing_claim_type,
      v_existing_lifecycle,
      v_existing_authority,
      v_existing_value,
      v_existing_metadata,
      v_existing_confidence,
      v_existing_primary_evidence_id,
      v_existing_supersedes_claim_id,
      v_existing_valid_from,
      v_existing_valid_until
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.source_kind='household_principal_capture'
      and c.source_key=v_source_key
      and c.subject_domain=v_subject_domain
      and c.subject_kind=v_subject_kind
      and c.subject_id=v_subject_id;

    if v_claim_id is null
       or v_existing_claim_type is distinct from v_claim_type
       or v_existing_lifecycle is distinct from v_lifecycle
       or v_existing_authority is distinct from v_authority
       or v_existing_value is distinct from v_claim->'value'
       or v_existing_metadata is distinct from coalesce(v_claim->'metadata','{}'::jsonb)
       or v_existing_confidence is distinct from v_confidence
       or v_existing_primary_evidence_id is distinct from v_evidence_id
       or v_existing_supersedes_claim_id is distinct from v_supersedes_claim_id
       or v_existing_valid_from is distinct from nullif(v_claim->>'validFrom','')::timestamptz
       or v_existing_valid_until is distinct from nullif(v_claim->>'validUntil','')::timestamptz then
      raise exception 'sourceKey retry does not match existing Household claim.'
        using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata)
  values (
    v_claim_id,
    v_evidence_id,
    'supports',
    jsonb_build_object('primary',true,'scopeKind','household')
  )
  on conflict do nothing;

  if v_created_claim and v_supersedes_claim_id is not null then
    update atlas.claim_records c
       set lifecycle_state='superseded',
           superseded_at=now()
     where c.id=v_supersedes_claim_id
       and c.scope_kind='household'
       and c.scope_id=v_household_id
       and c.lifecycle_state<>'superseded';

    get diagnostics v_updated = row_count;

    if v_updated <> 1 then
      raise exception 'The Household claim being corrected was already superseded.'
        using errcode='23505';
    end if;

    insert into atlas.claim_evidence_links(claim_id,evidence_id,relation_kind,metadata)
    values (
      v_claim_id,
      v_evidence_id,
      'corrects',
      jsonb_build_object('supersedesClaimId',v_supersedes_claim_id,'scopeKind','household')
    )
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok',true,
    'created',v_created_claim,
    'scope',jsonb_build_object('kind','household','id',v_household_id),
    'subject',v_subject,
    'evidenceId',v_evidence_id,
    'claimId',v_claim_id,
    'claimType',v_claim_type,
    'lifecycleState',v_lifecycle,
    'authorityKind',v_authority,
    'supersedesClaimId',v_supersedes_claim_id,
    'truthBoundary',jsonb_build_object(
      'currentPrincipalHouseholdOnly',true,
      'directTableWriteGranted',false,
      'evidenceIsNotTask',true,
      'claimIsNotTask',true,
      'doesNotEstablishCausation',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateClockPlacement',true,
      'inferenceAuthorityGranted',false
    )
  );
end;
$$;

comment on function atlas.record_current_household_claim_evidence_api_v1(jsonb) is
  'Atomic first-party Household Claim/Evidence writer. Household custody is derived from the signed-in active Principal current Household. Subjects are restricted to the Household domain; no task, carrier, consequence, Rhythm, inference, or Clock authority is granted.';

create or replace function atlas.current_household_claim_evidence_state_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_household_id uuid;
  v_evidence jsonb;
  v_claims jsonb;
  v_current_claims jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'evidenceId',e.id,
    'subject',jsonb_build_object('domain',e.subject_domain,'kind',e.subject_kind,'id',e.subject_id),
    'evidenceKind',e.evidence_kind,
    'sourceKind',e.source_kind,
    'sourceKey',e.source_key,
    'actorUserId',e.actor_user_id,
    'value',e.value,
    'confidence',e.confidence,
    'observedAt',e.observed_at,
    'learnedAt',e.learned_at,
    'effectiveFrom',e.effective_from,
    'effectiveUntil',e.effective_until,
    'provenance',e.provenance,
    'metadata',e.metadata
  ) order by e.learned_at,e.id),'[]'::jsonb)
    into v_evidence
  from atlas.evidence_records e
  where e.scope_kind='household'
    and e.scope_id=v_household_id
    and (e.subject_domain='household' or e.subject_domain like 'household.%');

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,
    'subject',jsonb_build_object('domain',c.subject_domain,'kind',c.subject_kind,'id',c.subject_id),
    'claimType',c.claim_type,
    'lifecycleState',c.lifecycle_state,
    'authorityKind',c.authority_kind,
    'sourceKind',c.source_kind,
    'sourceKey',c.source_key,
    'value',c.value,
    'confidence',c.confidence,
    'primaryEvidenceId',c.primary_evidence_id,
    'supersedesClaimId',c.supersedes_claim_id,
    'validFrom',c.valid_from,
    'validUntil',c.valid_until,
    'recordedAt',c.recorded_at,
    'supersededAt',c.superseded_at,
    'metadata',c.metadata
  ) order by c.recorded_at,c.id),'[]'::jsonb)
    into v_claims
  from atlas.claim_records c
  where c.scope_kind='household'
    and c.scope_id=v_household_id
    and (c.subject_domain='household' or c.subject_domain like 'household.%');

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,
    'subject',jsonb_build_object('domain',c.subject_domain,'kind',c.subject_kind,'id',c.subject_id),
    'claimType',c.claim_type,
    'lifecycleState',c.lifecycle_state,
    'authorityKind',c.authority_kind,
    'value',c.value,
    'primaryEvidenceId',c.primary_evidence_id,
    'validFrom',c.valid_from,
    'validUntil',c.valid_until
  ) order by c.recorded_at,c.id),'[]'::jsonb)
    into v_current_claims
  from atlas.claim_records c
  where c.scope_kind='household'
    and c.scope_id=v_household_id
    and (c.subject_domain='household' or c.subject_domain like 'household.%')
    and c.lifecycle_state not in ('superseded','expired');

  return jsonb_build_object(
    'ok',true,
    'scope',jsonb_build_object('kind','household','id',v_household_id),
    'evidenceRecords',v_evidence,
    'claims',v_claims,
    'currentClaims',v_current_claims,
    'truthBoundary',jsonb_build_object(
      'currentPrincipalHouseholdOnly',true,
      'historyPreservedThroughSupersession',true,
      'directTableWriteGranted',false,
      'evidenceDoesNotBecomeTask',true,
      'claimDoesNotBecomeTask',true,
      'carrierAuthority',false,
      'rhythmAuthority',false,
      'consequenceAuthority',false,
      'clockPlacementAuthority',false
    )
  );
end;
$$;

comment on function atlas.current_household_claim_evidence_state_api_v1() is
  'Read membrane for Claim/Evidence in the signed-in active Principal current Household. Direct table access remains governed by existing RLS; no operational or Clock authority is implied.';

revoke all on function atlas.record_current_household_claim_evidence_api_v1(jsonb)
  from public, anon;
revoke all on function atlas.current_household_claim_evidence_state_api_v1()
  from public, anon;

grant execute on function atlas.record_current_household_claim_evidence_api_v1(jsonb)
  to authenticated, service_role;
grant execute on function atlas.current_household_claim_evidence_state_api_v1()
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
    'atlas.record_current_household_claim_evidence_api_v1(p_payload jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Atomically preserve first-party Household Evidence and its explicit Claim lifecycle/authority envelope.',
      'authorizationBoundary','SECURITY DEFINER derives the current active Household from auth.uid() through Principal custody, restricts subjects to Household domain, and grants no task, carrier, consequence, Rhythm, inference, or Clock authority.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.current_household_claim_evidence_state_api_v1()',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Read full/current Claim-Evidence history for the signed-in Principal current active Household.',
      'authorizationBoundary','SECURITY DEFINER derives the Household from auth.uid(); direct authenticated table write remains unavailable and other Household custody is inaccessible.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  )
on conflict (signature) do update set
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
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Household Claim/Evidence membrane registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 3: atlas-personal-laundry-instance-truth-v1
-- ============================================================================

-- Atlas Personal Laundry Instance Truth v1
--
-- Progressive household-specific Laundry facts over the universal
-- Household Claim/Evidence membrane.
--
-- Authority deliberately stops at:
--   Laundry instance root + explicit Household Evidence/Claims.
--
-- This candidate creates no Household Rhythm, task, Person Life Consequence,
-- execution carrier, capacity block, or Clock placement.

create or replace function atlas.record_laundry_instance_fact_internal_v1(
  p_instance_id uuid,
  p_source_action_id text,
  p_fact_key text,
  p_value jsonb,
  p_supersedes_claim_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_source_action_id text := nullif(btrim(p_source_action_id),'');
  v_fact_key text := nullif(btrim(p_fact_key),'');
  v_source_key text;
  v_current_claim atlas.claim_records%rowtype;
  v_metadata jsonb := coalesce(p_metadata,'{}'::jsonb);
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  if p_instance_id is null or v_source_action_id is null or v_fact_key is null then
    raise exception 'instanceId, sourceActionId, and factKey are required.' using errcode='22023';
  end if;

  if p_value is null then
    raise exception 'Laundry fact value is required; use explicit JSON null only inside a structured fact if needed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(v_metadata)<>'object' then
    raise exception 'Laundry fact metadata must be an object.' using errcode='22023';
  end if;

  if not exists (
    select 1
    from atlas.household_kernel_instances i
    where i.id=p_instance_id
      and i.household_id=v_household_id
      and i.kernel_key='household.laundry'
      and i.state='active'
  ) then
    raise exception 'Active Laundry instance not found in the current Principal household.'
      using errcode='42501';
  end if;

  v_source_key := v_source_action_id||':'||v_fact_key;

  select * into v_current_claim
  from atlas.claim_records c
  where c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=p_instance_id::text
    and c.claim_type=v_fact_key
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_current_claim.id is not null
     and v_current_claim.source_key<>v_source_key
     and p_supersedes_claim_id is null then
    raise exception 'Laundry fact % already has accepted truth; durable correction requires explicit supersession.',
      v_fact_key using errcode='23505';
  end if;

  if p_supersedes_claim_id is not null
     and (v_current_claim.id is null or v_current_claim.id<>p_supersedes_claim_id) then
    raise exception 'Laundry supersession must identify the current accepted claim for fact %.',
      v_fact_key using errcode='23505';
  end if;

  return atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey',v_source_key,
    'subject',jsonb_build_object(
      'domain','household.laundry',
      'kind','kernel_instance',
      'id',p_instance_id::text
    ),
    'evidence',jsonb_build_object(
      'kind','principal_calibration_answer',
      'value',p_value,
      'confidence',1,
      'provenance',jsonb_strip_nulls(
        v_metadata
        || jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'factKey',v_fact_key
        )
      )
    ),
    'claim',jsonb_strip_nulls(jsonb_build_object(
      'claimType',v_fact_key,
      'lifecycleState','accepted',
      'value',p_value,
      'confidence',1,
      'supersedesClaimId',p_supersedes_claim_id,
      'metadata',v_metadata || jsonb_build_object('factKey',v_fact_key)
    ))
  ));
end;
$$;

comment on function atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb) is
  'Internal Laundry fact adapter. Fixes custody to the signed-in Principal current Household and active Laundry instance; requires explicit supersession for an already-accepted singleton fact; routes persistence through Household Claim/Evidence only.';

revoke all on function atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb)
  from public, anon, authenticated, service_role;


create or replace function atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_kernel_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_model_key text;
  v_source_action_id text;
  v_location text;
  v_responsibility jsonb;
  v_responsibility_mode text;
  v_need_driver text;
  v_process_variants jsonb;
  v_turnaround jsonb;
  v_supersedes jsonb;
  v_instance atlas.household_kernel_instances%rowtype;
  v_variant jsonb;
  v_variant_key text;
  v_seen_keys text[] := '{}'::text[];
  v_forbidden_key text;
  v_result jsonb;
  v_claims jsonb := '[]'::jsonb;
  v_fact_count integer := 0;
  v_supersedes_claim_id uuid;
  v_common_metadata jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Laundry V2 calibration input must be an object.' using errcode='22023';
  end if;

  v_source_action_id := nullif(btrim(p_input->>'sourceActionId'),'');
  if v_source_action_id is null then
    raise exception 'sourceActionId is required.' using errcode='22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select max(k.version)
  into v_kernel_version
  from atlas.world_kernel_definitions k
  where k.kernel_key='household.laundry'
    and k.active;

  if v_kernel_version is null then
    raise exception 'Active Laundry world kernel required.' using errcode='23514';
  end if;

  -- A source-controlled model is context for questioning, not Household truth.
  -- V2 validates modelKey when supplied but never copies model configuration
  -- into accepted Household facts.
  v_model_key := nullif(btrim(p_input->>'modelKey'),'');
  if v_model_key is not null then
    select * into v_model
    from atlas.world_kernel_models m
    where m.kernel_key='household.laundry'
      and m.kernel_version=v_kernel_version
      and m.model_key=v_model_key
      and m.active;

    if v_model.model_key is null then
      raise exception 'Unknown Laundry model.' using errcode='22023';
    end if;
  end if;

  if p_input ? 'laundryLocation' then
    v_location := nullif(btrim(p_input->>'laundryLocation'),'');
    if v_location='building' then
      -- Current Reality Discovery exposes "building" for the same real-world
      -- answer V2 names shared_machines.
      v_location := 'shared_machines';
    end if;

    if v_location is null
       or v_location not in ('home','shared_machines','laundromat','service','other') then
      raise exception 'Unsupported laundryLocation.' using errcode='22023';
    end if;

    v_fact_count := v_fact_count + 1;
  end if;

  if p_input ? 'responsibility' then
    v_responsibility := p_input->'responsibility';

    if jsonb_typeof(v_responsibility)<>'object' then
      raise exception 'responsibility must be an object.' using errcode='22023';
    end if;

    v_responsibility_mode := nullif(btrim(v_responsibility->>'mode'),'');
    if v_responsibility_mode is null
       or v_responsibility_mode not in (
         'self',
         'shared',
         'other_household_member',
         'outside_household',
         'service',
         'unresolved',
         'other'
       ) then
      raise exception 'Unsupported responsibility.mode.' using errcode='22023';
    end if;

    if (v_responsibility - 'mode') <> '{}'::jsonb then
      raise exception 'Laundry V2 responsibility accepts mode only; identity, scheduling, notes, and carrier details require their own governed authority.'
        using errcode='22023';
    end if;

    v_fact_count := v_fact_count + 1;
  end if;

  if p_input ? 'needDriver' then
    v_need_driver := nullif(btrim(p_input->>'needDriver'),'');

    if v_need_driver is null
       or v_need_driver not in (
         'accumulation_threshold',
         'steady_flow',
         'main_reset',
         'deadline_driven',
         'mixed',
         'other'
       ) then
      raise exception 'Unsupported needDriver.' using errcode='22023';
    end if;

    v_fact_count := v_fact_count + 1;
  end if;

  if p_input ? 'processVariants' then
    v_process_variants := p_input->'processVariants';

    if jsonb_typeof(v_process_variants)<>'array' then
      raise exception 'processVariants must be an array.' using errcode='22023';
    end if;

    v_seen_keys := '{}'::text[];

    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      if jsonb_typeof(v_variant)<>'object' then
        raise exception 'Each process variant must be an object.' using errcode='22023';
      end if;

      v_variant_key := nullif(btrim(v_variant->>'key'),'');
      if v_variant_key is null then
        raise exception 'Each process variant requires key.' using errcode='22023';
      end if;

      if v_variant_key !~ '^[a-z0-9][a-z0-9._-]*$' then
        raise exception 'process variant key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;

      if v_variant_key = any(v_seen_keys) then
        raise exception 'processVariants keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_seen_keys := array_append(v_seen_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule',
        'recurrence',
        'nextDueAt',
        'dueAt',
        'dueDate',
        'floorClass',
        'protectionLevel',
        'principalRequired',
        'blocksCapacity',
        'clockPlacement',
        'todayPlacement',
        'expectedMinutes',
        'personId',
        'memberId',
        'userId'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Process variant may not carry scheduling, Clock, or identity authority field: %',
            v_forbidden_key using errcode='22023';
        end if;
      end loop;

      if v_variant ? 'supersedesClaimId' then
        begin
          perform nullif(v_variant->>'supersedesClaimId','')::uuid;
        exception when invalid_text_representation then
          raise exception 'process variant supersedesClaimId must be a UUID.'
            using errcode='22023';
        end;
      end if;
    end loop;

    v_fact_count := v_fact_count + jsonb_array_length(v_process_variants);
  end if;

  if p_input ? 'turnaroundRelationships' then
    v_turnaround := p_input->'turnaroundRelationships';

    if jsonb_typeof(v_turnaround)<>'array' then
      raise exception 'turnaroundRelationships must be an array.' using errcode='22023';
    end if;

    v_seen_keys := '{}'::text[];

    for v_variant in
      select value from jsonb_array_elements(v_turnaround)
    loop
      if jsonb_typeof(v_variant)<>'object' then
        raise exception 'Each turnaround relationship must be an object.'
          using errcode='22023';
      end if;

      v_variant_key := nullif(btrim(v_variant->>'key'),'');
      if v_variant_key is null then
        raise exception 'Each turnaround relationship requires key.'
          using errcode='22023';
      end if;

      if v_variant_key !~ '^[a-z0-9][a-z0-9._-]*$' then
        raise exception 'turnaround relationship key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;

      if v_variant_key = any(v_seen_keys) then
        raise exception 'turnaroundRelationships keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_seen_keys := array_append(v_seen_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule',
        'recurrence',
        'nextDueAt',
        'dueAt',
        'dueDate',
        'floorClass',
        'protectionLevel',
        'principalRequired',
        'blocksCapacity',
        'clockPlacement',
        'todayPlacement',
        'expectedMinutes',
        'personId',
        'memberId',
        'userId'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Turnaround relationship may not carry scheduling, Clock, or identity authority field: %',
            v_forbidden_key using errcode='22023';
        end if;
      end loop;
    end loop;

    -- Explicit [] is meaningful: "no currently known special turnaround
    -- relationship." Absence of the key remains unknown.
    v_fact_count := v_fact_count + 1;
  end if;

  v_supersedes := coalesce(p_input->'supersedes','{}'::jsonb);
  if jsonb_typeof(v_supersedes)<>'object' then
    raise exception 'supersedes must be an object.' using errcode='22023';
  end if;

  if v_fact_count=0 then
    raise exception 'At least one explicit Laundry fact is required; modelKey alone is not household truth.'
      using errcode='22023';
  end if;

  -- Establish the durable instance root. Existing legacy configuration is
  -- preserved for compatibility, but V2 marks Claim/Evidence as fact authority.
  select * into v_instance
  from atlas.household_kernel_instances i
  where i.household_id=v_household_id
    and i.kernel_key='household.laundry'
  limit 1;

  if v_instance.id is null then
    insert into atlas.household_kernel_instances(
      household_id,
      kernel_key,
      kernel_version,
      state,
      configuration,
      calibrated_at,
      metadata
    ) values (
      v_household_id,
      'household.laundry',
      v_kernel_version,
      'active',
      jsonb_build_object(
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      ),
      now(),
      jsonb_build_object(
        'source','principal_progressive_calibration',
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      )
    )
    returning * into v_instance;
  else
    if v_instance.kernel_version is distinct from v_kernel_version
       or v_instance.state is distinct from 'active'
       or v_instance.configuration->>'factAuthority' is distinct from 'household_claim_evidence_v1'
       or v_instance.configuration->>'calibrationContract' is distinct from 'household_laundry_instance_truth_v1'
       or v_instance.metadata->>'factAuthority' is distinct from 'household_claim_evidence_v1'
       or v_instance.metadata->>'calibrationContract' is distinct from 'household_laundry_instance_truth_v1' then

      update atlas.household_kernel_instances
      set kernel_version=v_kernel_version,
          state='active',
          configuration=configuration || jsonb_build_object(
            'factAuthority','household_claim_evidence_v1',
            'calibrationContract','household_laundry_instance_truth_v1'
          ),
          metadata=metadata || jsonb_build_object(
            'factAuthority','household_claim_evidence_v1',
            'calibrationContract','household_laundry_instance_truth_v1'
          ),
          updated_at=now()
      where id=v_instance.id
      returning * into v_instance;
    end if;
  end if;

  v_common_metadata := jsonb_strip_nulls(jsonb_build_object(
    'kernelVersion',v_kernel_version,
    'selectedModelKey',v_model_key,
    'calibrationContract','household_laundry_instance_truth_v1',
    'modelIsSuggestionContextOnly',true
  ));

  if v_location is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'location','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.location must be a UUID.' using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'location',
      jsonb_build_object('kind',v_location),
      v_supersedes_claim_id,
      v_common_metadata
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_responsibility is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'ordinary_responsibility','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.ordinary_responsibility must be a UUID.'
        using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'ordinary_responsibility',
      jsonb_build_object('mode',v_responsibility_mode),
      v_supersedes_claim_id,
      v_common_metadata || jsonb_build_object('carrierSelectionAuthority',false)
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_need_driver is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'need_generation','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.need_generation must be a UUID.'
        using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'need_generation',
      jsonb_build_object('kind',v_need_driver),
      v_supersedes_claim_id,
      v_common_metadata || jsonb_build_object('recurrenceAuthority',false)
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_process_variants is not null then
    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      v_variant_key := btrim(v_variant->>'key');

      begin
        v_supersedes_claim_id := nullif(v_variant->>'supersedesClaimId','')::uuid;
      exception when invalid_text_representation then
        raise exception 'process variant supersedesClaimId must be a UUID.'
          using errcode='22023';
      end;

      v_result := atlas.record_laundry_instance_fact_internal_v1(
        v_instance.id,
        v_source_action_id,
        'process_variant:'||v_variant_key,
        v_variant - 'supersedesClaimId',
        v_supersedes_claim_id,
        v_common_metadata || jsonb_build_object('schedulingAuthority',false)
      );

      v_claims := v_claims || jsonb_build_array(v_result);
    end loop;
  end if;

  if v_turnaround is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'turnaround_relationships','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.turnaround_relationships must be a UUID.'
        using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'turnaround_relationships',
      v_turnaround,
      v_supersedes_claim_id,
      v_common_metadata || jsonb_build_object('deadlineConsequenceAuthority',false)
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','household_laundry_instance_truth_v1',
    'householdId',v_household_id,
    'sourceActionId',v_source_action_id,
    'selectedModelKey',v_model_key,
    'instance',jsonb_build_object(
      'id',v_instance.id,
      'state',v_instance.state,
      'kernelKey',v_instance.kernel_key,
      'kernelVersion',v_instance.kernel_version,
      'configuration',v_instance.configuration,
      'metadata',v_instance.metadata
    ),
    'factClaims',v_claims,
    'rhythm',null,
    'rhythmMutation','none',
    'truthBoundary',jsonb_build_object(
      'instanceRootIsHouseholdKernelInstance',true,
      'factAuthority','household_claim_evidence_v1',
      'modelIsSuggestionContextNotHouseholdTruth',true,
      'unmentionedFactsRemainUnknown',true,
      'responsibilityDoesNotSelectCarrier',true,
      'needGenerationDoesNotCreateRecurrence',true,
      'turnaroundRelationshipDoesNotCreateDeadline',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateTask',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateCapacity',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb) is
  'Progressively establish explicit household-specific Laundry facts against the durable Laundry kernel instance through Household Claim/Evidence authority. Unmentioned facts remain unknown; model defaults are not promoted; no Rhythm, task, consequence, carrier, capacity, or Clock authority is created.';


create or replace function atlas.personal_laundry_kernel_self_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_base jsonb;
  v_instance_id uuid;
  v_facts jsonb;
  v_accepted_facts jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  v_base := atlas.personal_laundry_kernel_self_api_v1();

  begin
    v_instance_id := nullif(v_base#>>'{instance,id}','')::uuid;
  exception when invalid_text_representation then
    raise exception 'Laundry V1 projection returned invalid instance identity.'
      using errcode='23514';
  end;

  if v_instance_id is null then
    v_facts := '[]'::jsonb;
    v_accepted_facts := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'claimId',c.id,
      'claimType',c.claim_type,
      'lifecycleState',c.lifecycle_state,
      'authorityKind',c.authority_kind,
      'value',c.value,
      'primaryEvidenceId',c.primary_evidence_id,
      'validFrom',c.valid_from,
      'validUntil',c.valid_until,
      'recordedAt',c.recorded_at,
      'metadata',c.metadata
    ) order by c.recorded_at,c.id),'[]'::jsonb)
    into v_facts
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance_id::text
      and c.lifecycle_state not in ('superseded','expired','rejected');

    select coalesce(jsonb_agg(jsonb_build_object(
      'claimId',c.id,
      'claimType',c.claim_type,
      'value',c.value,
      'primaryEvidenceId',c.primary_evidence_id,
      'recordedAt',c.recorded_at,
      'metadata',c.metadata
    ) order by c.recorded_at,c.id),'[]'::jsonb)
    into v_accepted_facts
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance_id::text
      and c.lifecycle_state='accepted';
  end if;

  return v_base || jsonb_build_object(
    'contractVersion','personal_laundry_kernel_self_api_v2',
    'instanceFacts',v_facts,
    'acceptedInstanceFacts',v_accepted_facts,
    'truthBoundary',jsonb_build_object(
      'worldKernelAndHouseholdInstanceRemainDistinct',true,
      'instanceFactsComeFromHouseholdClaimEvidence',true,
      'acceptedFactsRemainLifecycleExplicit',true,
      'legacyConfigurationIsNotV2FactAuthority',true,
      'rhythmIsSeparateDownstreamAuthority',true,
      'readCreatesNoTruth',true,
      'readCreatesNoClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_kernel_self_api_v2() is
  'Read current Household Laundry world-kernel/instance projection plus current source-backed Household Claim/Evidence facts. Any Household Rhythm remains a separate downstream projection, not calibration fact authority.';


revoke all on function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)
  from public, anon;
revoke all on function atlas.personal_laundry_kernel_self_api_v2()
  from public, anon;

grant execute on function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)
  to authenticated, service_role;
grant execute on function atlas.personal_laundry_kernel_self_api_v2()
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
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Progressively establish explicit household-specific Laundry facts on the Laundry kernel instance through Household Claim/Evidence.',
      'authorizationBoundary','SECURITY DEFINER derives current Household from auth.uid(); model defaults remain suggestions; unmentioned facts remain unknown; no Rhythm, task, carrier, consequence, capacity, or Clock authority.',
      'dependsOn','atlas.record_current_household_claim_evidence_api_v1(jsonb)',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.personal_laundry_kernel_self_api_v2()',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Read Laundry world-kernel/instance projection with current Household Claim/Evidence facts while preserving Rhythm as separate authority.',
      'authorizationBoundary','SECURITY DEFINER fixes Household to auth.uid() Principal custody; read creates no truth, task, or Clock placement.',
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
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry V2 instance-truth registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 4: atlas-personal-reality-household-claim-route-v1
-- ============================================================================

-- Personal Reality -> Household Claim Route v1
--
-- Raw spontaneous testimony remains in person custody.
-- A human-confirmed Household interpretation receives new same-subject
-- Household interpretation Evidence and a Household Claim.
-- Cross-scope Claim/Evidence links remain prohibited.

create or replace function atlas.guard_personal_reality_household_claim_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  if new.scope_kind='person'
     and new.source_kind='personal_reality_claim'
     and (new.subject_domain='household' or new.subject_domain like 'household.%') then
    raise exception 'Personal Reality Household claims must use the Household application route, not person Claim custody.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_personal_reality_household_claim_scope_v1() is
  'Fail-closed guard preventing the legacy person-Claim Personal Reality route from storing Household-subject claims in person custody.';

revoke all on function atlas.guard_personal_reality_household_claim_scope_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists personal_reality_household_claim_scope_guard_v1
  on atlas.claim_records;

create trigger personal_reality_household_claim_scope_guard_v1
before insert or update on atlas.claim_records
for each row
execute function atlas.guard_personal_reality_household_claim_scope_v1();


create or replace function atlas.record_current_household_claim_from_capture_evidence_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_raw_evidence_id uuid;
  v_proposal_id uuid;
  v_receipt_id uuid;
  v_supersedes_claim_id uuid;
  v_subject jsonb;
  v_claim jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_claim_type text;
  v_lifecycle text;
  v_authority text;
  v_confidence numeric;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_metadata jsonb;
  v_source_key text;
  v_raw atlas.evidence_records%rowtype;
  v_old atlas.claim_records%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_existing_claim atlas.claim_records%rowtype;
  v_evidence_id uuid;
  v_claim_id uuid;
  v_created boolean := false;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Household capture-claim input must be an object.' using errcode='22023';
  end if;

  begin
    v_raw_evidence_id := nullif(p_input->>'sourceEvidenceId','')::uuid;
    v_proposal_id := nullif(p_input->>'proposalId','')::uuid;
    v_receipt_id := nullif(p_input->>'decisionReceiptId','')::uuid;
    v_supersedes_claim_id := nullif(p_input->>'supersedesClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'sourceEvidenceId, proposalId, decisionReceiptId, and supersedesClaimId must be UUID values when supplied.'
      using errcode='22023';
  end;

  v_subject := p_input->'subject';
  v_claim := p_input->'claim';

  if v_raw_evidence_id is null
     or v_proposal_id is null
     or v_receipt_id is null
     or jsonb_typeof(v_subject)<>'object'
     or jsonb_typeof(v_claim)<>'object' then
    raise exception 'sourceEvidenceId, proposalId, decisionReceiptId, subject, and claim are required.'
      using errcode='22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select * into v_raw
  from atlas.evidence_records e
  where e.id=v_raw_evidence_id
    and e.scope_kind='person'
    and e.scope_id=v_user_id
    and e.source_kind='personal_reality_capture';

  if v_raw.id is null then
    raise exception 'Source Evidence must be the signed-in person Personal Reality capture Evidence.'
      using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.personal_reality_human_decision_receipts r
    where r.id=v_receipt_id
      and r.proposal_id=v_proposal_id
      and r.owner_user_id=v_user_id
      and r.decision='confirm'
      and r.consumed_at is not null
  ) then
    raise exception 'Consumed human confirmation receipt required.'
      using errcode='42501';
  end if;

  v_subject_domain := nullif(btrim(v_subject->>'domain'),'');
  v_subject_kind := nullif(btrim(v_subject->>'kind'),'');
  v_subject_id := nullif(btrim(v_subject->>'id'),'');
  v_claim_type := nullif(btrim(v_claim->>'claimType'),'');
  v_lifecycle := nullif(btrim(v_claim->>'lifecycleState'),'');

  if v_subject_domain is null
     or v_subject_kind is null
     or v_subject_id is null
     or v_claim_type is null
     or v_lifecycle is null
     or not (v_claim ? 'value') then
    raise exception 'Resolved Household subject and complete claim are required.'
      using errcode='22023';
  end if;

  if v_subject_domain<>'household'
     and v_subject_domain not like 'household.%' then
    raise exception 'Household Personal Reality route accepts only household subjects.'
      using errcode='22023';
  end if;

  if v_lifecycle not in ('reported','observed','accepted','rejected','unknown') then
    raise exception 'Unsupported human-confirmed Household claim lifecycle.'
      using errcode='22023';
  end if;

  if v_claim ? 'confidence' then
    v_confidence := (v_claim->>'confidence')::numeric;
    if v_confidence<0 or v_confidence>1 then
      raise exception 'claim confidence must be 0..1.' using errcode='22023';
    end if;
  end if;

  begin
    v_valid_from := nullif(v_claim->>'validFrom','')::timestamptz;
    v_valid_until := nullif(v_claim->>'validUntil','')::timestamptz;
  exception when others then
    raise exception 'Household claim validity timestamps are invalid.'
      using errcode='22023';
  end;

  if v_valid_from is not null
     and v_valid_until is not null
     and v_valid_until<v_valid_from then
    raise exception 'validUntil precedes validFrom.' using errcode='22023';
  end if;

  v_metadata := coalesce(
    case when jsonb_typeof(v_claim->'metadata')='object' then v_claim->'metadata' end,
    '{}'::jsonb
  );

  v_source_key := 'personal_reality_household_proposal:'||v_proposal_id::text;

  if v_supersedes_claim_id is not null then
    select * into v_old
    from atlas.claim_records c
    where c.id=v_supersedes_claim_id
      and c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain=v_subject_domain
      and c.subject_kind=v_subject_kind
      and c.subject_id=v_subject_id;

    if v_old.id is null then
      raise exception 'supersedesClaimId must identify the same-subject Claim in the current Principal Household.'
        using errcode='42501';
    end if;
  end if;

  insert into atlas.evidence_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    evidence_kind,
    source_kind,
    source_key,
    actor_user_id,
    value,
    confidence,
    observed_at,
    effective_from,
    effective_until,
    provenance,
    metadata
  ) values (
    'household',
    v_household_id,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    'human_confirmed_interpretation',
    'personal_reality_household_claim_interpretation',
    v_source_key,
    v_user_id,
    v_claim->'value',
    1,
    v_raw.observed_at,
    v_valid_from,
    v_valid_until,
    jsonb_build_object(
      'sourceEvidenceId',v_raw_evidence_id,
      'sourceEvidenceScope','person',
      'proposalId',v_proposal_id,
      'decisionReceiptId',v_receipt_id,
      'crossScopePromotion',true
    ),
    jsonb_build_object(
      'rawTestimonyNotCopied',true,
      'crossScopeClaimEvidenceLinkCreated',false
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning * into v_evidence;

  if v_evidence.id is null then
    select * into v_evidence
    from atlas.evidence_records e
    where e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.source_kind='personal_reality_household_claim_interpretation'
      and e.source_key=v_source_key;

    if v_evidence.id is null
       or v_evidence.subject_domain is distinct from v_subject_domain
       or v_evidence.subject_kind is distinct from v_subject_kind
       or v_evidence.subject_id is distinct from v_subject_id
       or v_evidence.value is distinct from v_claim->'value'
       or v_evidence.observed_at is distinct from v_raw.observed_at
       or v_evidence.effective_from is distinct from v_valid_from
       or v_evidence.effective_until is distinct from v_valid_until
       or v_evidence.provenance is distinct from jsonb_build_object(
         'sourceEvidenceId',v_raw_evidence_id,
         'sourceEvidenceScope','person',
         'proposalId',v_proposal_id,
         'decisionReceiptId',v_receipt_id,
         'crossScopePromotion',true
       ) then
      raise exception 'Proposal retry does not match Household interpretation Evidence.'
        using errcode='23505';
    end if;
  end if;

  v_evidence_id := v_evidence.id;

  v_authority := case
    when v_supersedes_claim_id is not null then 'household_principal_correction'
    when v_lifecycle='observed' then 'household_principal_observation'
    when v_lifecycle='accepted' then 'household_principal_acceptance'
    when v_lifecycle='rejected' then 'household_principal_rejection'
    when v_lifecycle='reported' then 'household_principal_report'
    else 'household_principal_confirmed_interpretation'
  end;

  insert into atlas.claim_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    claim_type,
    lifecycle_state,
    authority_kind,
    source_kind,
    source_key,
    value,
    confidence,
    primary_evidence_id,
    supersedes_claim_id,
    valid_from,
    valid_until,
    metadata
  ) values (
    'household',
    v_household_id,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    v_claim_type,
    v_lifecycle,
    v_authority,
    'personal_reality_household_claim',
    v_source_key,
    v_claim->'value',
    v_confidence,
    v_evidence_id,
    v_supersedes_claim_id,
    v_valid_from,
    v_valid_until,
    v_metadata || jsonb_build_object(
      'sourceEvidenceId',v_raw_evidence_id,
      'sourceEvidenceScope','person',
      'proposalId',v_proposal_id,
      'decisionReceiptId',v_receipt_id
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning * into v_existing_claim;

  if v_existing_claim.id is null then
    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.source_kind='personal_reality_household_claim'
      and c.source_key=v_source_key;

    if v_existing_claim.id is null
       or v_existing_claim.subject_domain is distinct from v_subject_domain
       or v_existing_claim.subject_kind is distinct from v_subject_kind
       or v_existing_claim.subject_id is distinct from v_subject_id
       or v_existing_claim.claim_type is distinct from v_claim_type
       or v_existing_claim.lifecycle_state is distinct from v_lifecycle
       or v_existing_claim.authority_kind is distinct from v_authority
       or v_existing_claim.value is distinct from v_claim->'value'
       or v_existing_claim.confidence is distinct from v_confidence
       or v_existing_claim.primary_evidence_id is distinct from v_evidence_id
       or v_existing_claim.supersedes_claim_id is distinct from v_supersedes_claim_id
       or v_existing_claim.valid_from is distinct from v_valid_from
       or v_existing_claim.valid_until is distinct from v_valid_until then
      raise exception 'Proposal retry does not match Household Claim.'
        using errcode='23505';
    end if;
  else
    v_created := true;
  end if;

  v_claim_id := v_existing_claim.id;

  insert into atlas.claim_evidence_links(
    claim_id,evidence_id,relation_kind,metadata
  ) values (
    v_claim_id,
    v_evidence_id,
    'supports',
    jsonb_build_object('primary',true,'custodyScope','household')
  )
  on conflict do nothing;

  -- The raw Evidence is person-scoped and therefore is intentionally not
  -- inserted into claim_evidence_links. Provenance above retains the source id.
  if v_created and v_supersedes_claim_id is not null then
    update atlas.claim_records c
    set lifecycle_state='superseded',
        superseded_at=now()
    where c.id=v_supersedes_claim_id
      and c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.lifecycle_state<>'superseded';

    if not found then
      raise exception 'Household Claim being corrected was already superseded.'
        using errcode='23505';
    end if;

    insert into atlas.claim_evidence_links(
      claim_id,evidence_id,relation_kind,metadata
    ) values (
      v_supersedes_claim_id,
      v_evidence_id,
      'corrects',
      jsonb_build_object(
        'correctedByClaimId',v_claim_id,
        'rawSourceEvidenceId',v_raw_evidence_id,
        'rawSourceEvidenceScope','person'
      )
    )
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok',true,
    'created',v_created,
    'scope',jsonb_build_object('kind','household','id',v_household_id),
    'claimId',v_claim_id,
    'interpretationEvidenceId',v_evidence_id,
    'sourceEvidenceId',v_raw_evidence_id,
    'truthBoundary',jsonb_build_object(
      'rawEvidenceRemainsPersonScoped',true,
      'rawTestimonyCopied',false,
      'rawEvidenceReferencedByProvenance',true,
      'crossScopeClaimEvidenceLinkCreated',false,
      'householdInterpretationEvidenceIsPrimary',true,
      'doesNotCreateTask',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateConsequence',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_current_household_claim_from_capture_evidence_v1(jsonb) is
  'Internal promotion writer from signed-in person Personal Reality source Evidence + consumed human confirmation into same-subject current-Household interpretation Evidence and Claim. Raw testimony remains person-scoped and is referenced only through provenance; no cross-scope Claim/Evidence link is created.';

revoke all on function atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)
  from public, anon, authenticated, service_role;


create or replace function atlas.apply_personal_reality_household_claim_effect_self_api_v1(
  p_proposal_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_old_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_body jsonb;
  v_result jsonb;
  v_old_claim atlas.claim_records%rowtype;
  v_supersedes_claim_id uuid;
  v_old_decision_state text;
  v_old_route_state text;
  v_capture_state text;
  v_route_before text;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select * into v_proposal
  from atlas.personal_reality_effect_proposals p
  where p.id=p_proposal_id
    and p.owner_user_id=v_user_id
  for update;

  if v_proposal.id is null then
    raise exception 'Effect proposal not found.' using errcode='P0002';
  end if;

  select * into v_capture
  from atlas.personal_reality_captures c
  where c.id=v_proposal.capture_id
    and c.owner_user_id=v_user_id;

  if v_capture.id is null then
    raise exception 'Personal Reality capture not found.' using errcode='P0002';
  end if;

  if v_proposal.route_state='applied' then
    return jsonb_build_object(
      'ok',true,
      'changed',false,
      'routeState','applied',
      'destinationKind',v_proposal.destination_kind,
      'destinationId',v_proposal.destination_id,
      'destinationState',atlas.personal_reality_destination_state_v1(
        v_proposal.destination_kind,
        v_proposal.destination_id
      )
    );
  end if;

  if v_proposal.effect_kind<>'claim' then
    raise exception 'Household Personal Reality application route accepts claim effects only.'
      using errcode='22023';
  end if;

  if v_proposal.decision_state<>'confirmed'
     or v_proposal.decision_receipt_id is null then
    raise exception 'Human confirmation receipt required before Household application.'
      using errcode='42501';
  end if;

  if v_proposal.readiness_state<>'ready_for_confirmation'
     or v_proposal.route_state not in ('ready','destination_unavailable') then
    raise exception 'Proposal is not ready for Household application.'
      using errcode='22023';
  end if;

  v_body := v_proposal.proposal;
  v_subject_domain := nullif(btrim(v_body#>>'{subject,domain}'),'');
  v_subject_kind := nullif(btrim(v_body#>>'{subject,kind}'),'');
  v_subject_id := nullif(btrim(v_body#>>'{subject,id}'),'');

  if v_subject_domain is null
     or (v_subject_domain<>'household' and v_subject_domain not like 'household.%') then
    raise exception 'Proposal is not a Household-subject Claim.'
      using errcode='22023';
  end if;

  if v_subject_kind is null or v_subject_id is null then
    raise exception 'Resolved Household subject required.'
      using errcode='22023';
  end if;

  if v_proposal.supersedes_proposal_id is not null then
    select * into v_old_proposal
    from atlas.personal_reality_effect_proposals p
    where p.id=v_proposal.supersedes_proposal_id
      and p.owner_user_id=v_user_id
      and p.principal_id=v_proposal.principal_id
    for update;

    if v_old_proposal.id is null
       or v_old_proposal.effect_kind<>'claim'
       or v_old_proposal.decision_state='revoked'
       or v_old_proposal.route_state='superseded' then
      raise exception 'Superseded Household Claim proposal is unavailable or obsolete.'
        using errcode='23505';
    end if;

    v_old_decision_state := v_old_proposal.decision_state;
    v_old_route_state := v_old_proposal.route_state;

    if v_old_proposal.route_state='applied' then
      begin
        select * into v_old_claim
        from atlas.claim_records c
        where c.id=v_old_proposal.destination_id::uuid
          and c.scope_kind='household'
          and c.scope_id=v_household_id;
      exception when invalid_text_representation then
        raise exception 'Prior Household Claim destination identity is invalid.'
          using errcode='23514';
      end;

      if v_old_claim.id is null then
        raise exception 'Prior Household Claim destination missing.'
          using errcode='P0002';
      end if;

      if v_old_claim.subject_domain is distinct from v_subject_domain
         or v_old_claim.subject_kind is distinct from v_subject_kind
         or v_old_claim.subject_id is distinct from v_subject_id then
        raise exception 'Household Personal Reality correction must remain on the same subject.'
          using errcode='23514';
      end if;

      v_supersedes_claim_id := v_old_claim.id;
    end if;
  end if;

  v_result := atlas.record_current_household_claim_from_capture_evidence_v1(
    jsonb_build_object(
      'sourceEvidenceId',v_capture.evidence_id,
      'proposalId',v_proposal.id,
      'decisionReceiptId',v_proposal.decision_receipt_id,
      'subject',v_body->'subject',
      'claim',v_body->'claim',
      'supersedesClaimId',v_supersedes_claim_id
    )
  );

  v_route_before := v_proposal.route_state;

  update atlas.personal_reality_effect_proposals
  set route_state='applied',
      applied_at=coalesce(applied_at,now()),
      destination_kind='claim_record',
      destination_id=v_result->>'claimId',
      updated_at=now()
  where id=v_proposal.id
  returning * into v_proposal;

  insert into atlas.personal_reality_effect_events(
    proposal_id,
    capture_id,
    principal_id,
    actor_user_id,
    authority_receipt_id,
    event_kind,
    state_axis,
    from_state,
    to_state,
    detail
  ) values (
    v_proposal.id,
    v_capture.id,
    v_capture.principal_id,
    v_user_id,
    v_proposal.decision_receipt_id,
    'applied',
    'route',
    v_route_before,
    'applied',
    jsonb_build_object(
      'destinationKind','claim_record',
      'destinationId',v_proposal.destination_id,
      'destinationScope','household',
      'sourceEvidenceId',v_capture.evidence_id
    )
  );

  if v_old_proposal.id is not null then
    update atlas.personal_reality_effect_proposals
    set decision_state='revoked',
        route_state=case
          when route_state='applied' then 'superseded'
          else 'not_ready'
        end,
        revoked_at=now(),
        updated_at=now()
    where id=v_old_proposal.id
    returning * into v_old_proposal;

    insert into atlas.personal_reality_effect_events(
      proposal_id,
      capture_id,
      principal_id,
      actor_user_id,
      authority_receipt_id,
      event_kind,
      state_axis,
      from_state,
      to_state,
      detail
    ) values (
      v_old_proposal.id,
      v_old_proposal.capture_id,
      v_old_proposal.principal_id,
      v_user_id,
      v_proposal.decision_receipt_id,
      'superseded',
      'decision',
      v_old_decision_state,
      'revoked',
      jsonb_build_object(
        'supersededByProposalId',v_proposal.id,
        'oldDestinationReversed',v_supersedes_claim_id is not null
      )
    );

    if v_old_route_state is distinct from v_old_proposal.route_state then
      insert into atlas.personal_reality_effect_events(
        proposal_id,
        capture_id,
        principal_id,
        actor_user_id,
        authority_receipt_id,
        event_kind,
        state_axis,
        from_state,
        to_state,
        detail
      ) values (
        v_old_proposal.id,
        v_old_proposal.capture_id,
        v_old_proposal.principal_id,
        v_user_id,
        v_proposal.decision_receipt_id,
        'superseded',
        'route',
        v_old_route_state,
        v_old_proposal.route_state,
        jsonb_build_object('supersededByProposalId',v_proposal.id)
      );
    end if;

    perform atlas.refresh_personal_reality_capture_state_v1(
      v_old_proposal.capture_id
    );
  end if;

  v_capture_state := atlas.refresh_personal_reality_capture_state_v1(
    v_capture.id
  );

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','personal_reality_household_claim_application_v1',
    'proposalId',v_proposal.id,
    'decisionState',v_proposal.decision_state,
    'routeState',v_proposal.route_state,
    'effectKind',v_proposal.effect_kind,
    'destinationKind',v_proposal.destination_kind,
    'destinationId',v_proposal.destination_id,
    'destinationScope','household',
    'destinationState',atlas.personal_reality_destination_state_v1(
      v_proposal.destination_kind,
      v_proposal.destination_id
    ),
    'sourceEvidenceId',v_capture.evidence_id,
    'interpretationEvidenceId',v_result->>'interpretationEvidenceId',
    'captureState',v_capture_state,
    'truthBoundary',jsonb_build_object(
      'applicationAuthorityComesFromHumanDecisionReceiptNotCaller',true,
      'rawTestimonyRemainsPersonScoped',true,
      'householdInterpretationEvidenceCreated',true,
      'crossScopeClaimEvidenceLinkCreated',false,
      'correctionIsSameSubjectAndTransactional',true,
      'doesNotCreateTask',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateConsequence',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid) is
  'Apply an already-human-confirmed Personal Reality claim proposal whose resolved subject belongs to the current Principal Household. Raw testimony remains person-scoped; same-subject Household interpretation Evidence and Claim are created transactionally.';

revoke all on function atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
  from public, anon;
grant execute on function atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
  to authenticated, service_role;


create or replace function public.apply_personal_reality_household_claim_effect_self_api_v1(
  p_proposal_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.apply_personal_reality_household_claim_effect_self_api_v1(p_proposal_id);
$$;

revoke all on function public.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
  from public, anon;
grant execute on function public.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
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
values (
  'atlas.apply_personal_reality_household_claim_effect_self_api_v1(p_proposal_id uuid)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Apply an already-confirmed Personal Reality claim proposal into current-Household Claim/Evidence custody.',
    'authorizationBoundary','SECURITY DEFINER derives Household from auth.uid(), requires the existing consumed human confirmation receipt, accepts Household subjects only, preserves raw testimony in person custody, and grants no task/Rhythm/consequence/carrier/Clock authority.',
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
    raise exception 'Authenticated RPC registry drifted after Household Personal Reality claim route registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 5: atlas-laundry-household-consequence-v1
-- ============================================================================

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

-- ============================================================================
-- Laundry closed-loop tranche 6: atlas-principal-consequence-clock-characterization-v1
-- ============================================================================

-- Principal Consequence Clock Characterization v1.
--
-- Real consequence truth remains separate from Clock characterization.
-- Characterization remains separate from Clock candidate admission.

create or replace function atlas.person_life_consequence_clock_characterization_completeness_v1(
  p_value jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_blockers jsonb := '[]'::jsonb;
  v_timing jsonb;
  v_has_relevance_start boolean := false;
begin
  if p_value is null or jsonb_typeof(p_value)<>'object' then
    return jsonb_build_object(
      'complete',false,
      'blockers',jsonb_build_array('clock_characterization_required')
    );
  end if;

  if not (p_value ? 'expectedMinutes') then
    v_blockers := v_blockers || '"expected_minutes_required"'::jsonb;
  elsif jsonb_typeof(p_value->'expectedMinutes')<>'number'
     or (p_value->>'expectedMinutes')::numeric<=0
     or trunc((p_value->>'expectedMinutes')::numeric)<>(p_value->>'expectedMinutes')::numeric then
    v_blockers := v_blockers || '"expected_minutes_required"'::jsonb;
  end if;

  if not (p_value ? 'protectionLevel')
     or p_value->>'protectionLevel' not in ('critical','protected','standard','optional') then
    v_blockers := v_blockers || '"protection_level_required"'::jsonb;
  end if;

  if not (p_value ? 'floorClass') then
    v_blockers := v_blockers || '"floor_class_required"'::jsonb;
  elsif jsonb_typeof(p_value->'floorClass')<>'number'
     or (p_value->>'floorClass')::numeric<1
     or (p_value->>'floorClass')::numeric>7
     or trunc((p_value->>'floorClass')::numeric)<>(p_value->>'floorClass')::numeric then
    v_blockers := v_blockers || '"floor_class_required"'::jsonb;
  end if;

  if not (p_value ? 'interruptibility')
     or p_value->>'interruptibility' not in ('interruptible','low_interruptibility','should_not_interrupt') then
    v_blockers := v_blockers || '"interruptibility_required"'::jsonb;
  end if;

  if not (p_value ? 'delegable')
     or jsonb_typeof(p_value->'delegable')<>'boolean' then
    v_blockers := v_blockers || '"delegability_required"'::jsonb;
  end if;

  if not (p_value ? 'ownerRequired')
     or jsonb_typeof(p_value->'ownerRequired')<>'boolean' then
    v_blockers := v_blockers || '"owner_required_characterization_required"'::jsonb;
  end if;

  if nullif(btrim(p_value->>'consequenceOfDelay'),'') is null then
    v_blockers := v_blockers || '"consequence_of_delay_required"'::jsonb;
  end if;

  if nullif(btrim(p_value->>'reasonForFloor'),'') is null then
    v_blockers := v_blockers || '"reason_for_floor_required"'::jsonb;
  end if;

  v_timing := p_value->'timing';
  if jsonb_typeof(v_timing)='object' then
    v_has_relevance_start :=
      nullif(btrim(v_timing->>'windowStart'),'') is not null
      or nullif(btrim(v_timing->>'fixedStart'),'') is not null;
  end if;

  if not v_has_relevance_start then
    v_blockers := v_blockers || '"relevance_start_required"'::jsonb;
  end if;

  return jsonb_build_object(
    'complete',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'truthBoundary',jsonb_build_object(
      'missingRelevanceStartDoesNotMeanOpenNow',true,
      'deadlineAloneDoesNotEstablishCurrentRelevance',true,
      'completenessDoesNotMeanClockAdmission',true
    )
  );
end;
$$;

comment on function atlas.person_life_consequence_clock_characterization_completeness_v1(jsonb) is
  'Pure completeness test for person-life consequence Clock characterization. Missing timing is an admission blocker and never means an open current window.';

revoke all on function atlas.person_life_consequence_clock_characterization_completeness_v1(jsonb)
  from public, anon, authenticated, service_role;


create or replace function atlas.record_person_life_consequence_clock_characterization_self_api_v1(
  p_consequence_instance_id uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_source_action_id text;
  v_value jsonb;
  v_timing jsonb;
  v_key text;
  v_supersedes_claim_id uuid;
  v_current atlas.claim_records%rowtype;
  v_result jsonb;
  v_completeness jsonb;
  v_time_key text;
  v_time_value text;
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_fixed_start timestamptz;
  v_must_begin_by timestamptz;
  v_must_finish_by timestamptz;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_consequence_instance_id is null
     or p_input is null
     or jsonb_typeof(p_input)<>'object' then
    raise exception 'consequenceInstanceId and characterization input object are required.'
      using errcode='22023';
  end if;

  select *
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=v_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open person Life Consequence not found for the signed-in user.'
      using errcode='42501';
  end if;

  v_source_action_id := nullif(btrim(p_input->>'sourceActionId'),'');
  v_value := p_input->'characterization';

  if v_source_action_id is null or jsonb_typeof(v_value)<>'object' then
    raise exception 'sourceActionId and characterization object are required.'
      using errcode='22023';
  end if;

  if v_value='{}'::jsonb then
    raise exception 'characterization must contain at least one explicit field.'
      using errcode='22023';
  end if;

  for v_key in select jsonb_object_keys(v_value)
  loop
    if v_key not in (
      'expectedMinutes',
      'protectionLevel',
      'floorClass',
      'interruptibility',
      'delegable',
      'ownerRequired',
      'timing',
      'consequenceOfDelay',
      'reasonForFloor'
    ) then
      raise exception 'Unsupported Clock characterization field: %',v_key
        using errcode='22023';
    end if;
  end loop;

  if v_value ? 'expectedMinutes' then
    if jsonb_typeof(v_value->'expectedMinutes')<>'number'
       or (v_value->>'expectedMinutes')::numeric<=0
       or trunc((v_value->>'expectedMinutes')::numeric)<>(v_value->>'expectedMinutes')::numeric then
      raise exception 'expectedMinutes must be a positive integer.'
        using errcode='22023';
    end if;
  end if;

  if v_value ? 'protectionLevel'
     and v_value->>'protectionLevel' not in ('critical','protected','standard','optional') then
    raise exception 'Unsupported protectionLevel.' using errcode='22023';
  end if;

  if v_value ? 'floorClass' then
    if jsonb_typeof(v_value->'floorClass')<>'number'
       or (v_value->>'floorClass')::numeric<1
       or (v_value->>'floorClass')::numeric>7
       or trunc((v_value->>'floorClass')::numeric)<>(v_value->>'floorClass')::numeric then
      raise exception 'floorClass must be an integer from 1 through 7.'
        using errcode='22023';
    end if;
  end if;

  if v_value ? 'interruptibility'
     and v_value->>'interruptibility' not in ('interruptible','low_interruptibility','should_not_interrupt') then
    raise exception 'Unsupported interruptibility.' using errcode='22023';
  end if;

  if v_value ? 'delegable' and jsonb_typeof(v_value->'delegable')<>'boolean' then
    raise exception 'delegable must be boolean.' using errcode='22023';
  end if;

  if v_value ? 'ownerRequired' and jsonb_typeof(v_value->'ownerRequired')<>'boolean' then
    raise exception 'ownerRequired must be boolean.' using errcode='22023';
  end if;

  if v_value ? 'consequenceOfDelay'
     and nullif(btrim(v_value->>'consequenceOfDelay'),'') is null then
    raise exception 'consequenceOfDelay must be non-empty when supplied.'
      using errcode='22023';
  end if;

  if v_value ? 'reasonForFloor'
     and nullif(btrim(v_value->>'reasonForFloor'),'') is null then
    raise exception 'reasonForFloor must be non-empty when supplied.'
      using errcode='22023';
  end if;

  if v_value ? 'timing' then
    v_timing := v_value->'timing';
    if jsonb_typeof(v_timing)<>'object' then
      raise exception 'timing must be an object.' using errcode='22023';
    end if;

    for v_time_key in select jsonb_object_keys(v_timing)
    loop
      if v_time_key not in (
        'windowStart',
        'windowEnd',
        'fixedStart',
        'mustBeginBy',
        'mustFinishBy'
      ) then
        raise exception 'Unsupported Clock timing field: %',v_time_key
          using errcode='22023';
      end if;

      v_time_value := nullif(btrim(v_timing->>v_time_key),'');
      if v_time_value is not null
         and not atlas.personal_reality_timestamp_is_explicit_v1(v_time_value) then
        raise exception 'Clock timing field % requires an explicit timestamp offset.',v_time_key
          using errcode='22023';
      end if;
    end loop;

    begin
      v_window_start := nullif(v_timing->>'windowStart','')::timestamptz;
      v_window_end := nullif(v_timing->>'windowEnd','')::timestamptz;
      v_fixed_start := nullif(v_timing->>'fixedStart','')::timestamptz;
      v_must_begin_by := nullif(v_timing->>'mustBeginBy','')::timestamptz;
      v_must_finish_by := nullif(v_timing->>'mustFinishBy','')::timestamptz;
    exception when others then
      raise exception 'Clock timing contains an invalid timestamp.'
        using errcode='22023';
    end;

    if v_window_start is not null
       and v_window_end is not null
       and v_window_end<=v_window_start then
      raise exception 'windowEnd must be after windowStart.'
        using errcode='22023';
    end if;

    if v_must_begin_by is not null
       and v_must_finish_by is not null
       and v_must_finish_by<v_must_begin_by then
      raise exception 'mustFinishBy must not precede mustBeginBy.'
        using errcode='22023';
    end if;

    if v_fixed_start is not null
       and v_window_end is not null
       and v_fixed_start>=v_window_end then
      raise exception 'fixedStart must precede windowEnd when both are supplied.'
        using errcode='22023';
    end if;
  end if;

  begin
    v_supersedes_claim_id := nullif(p_input->>'supersedesClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'supersedesClaimId must be a UUID.'
      using errcode='22023';
  end;

  select *
  into v_current
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=v_user_id
    and c.subject_domain='principal.clock'
    and c.subject_kind='person_life_consequence'
    and c.subject_id=v_instance.id::text
    and c.claim_type='clock_characterization'
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_current.id is not null
     and v_current.source_key<>(v_source_action_id||':clock_characterization')
     and v_supersedes_claim_id is null then
    raise exception 'This consequence already has current accepted Clock characterization; durable correction requires supersedesClaimId.'
      using errcode='23505';
  end if;

  if v_supersedes_claim_id is not null
     and (v_current.id is null or v_current.id<>v_supersedes_claim_id) then
    raise exception 'supersedesClaimId must identify the current accepted Clock characterization for this consequence.'
      using errcode='23505';
  end if;

  v_completeness := atlas.person_life_consequence_clock_characterization_completeness_v1(v_value);

  v_result := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey',v_source_action_id||':clock_characterization',
    'subject',jsonb_build_object(
      'domain','principal.clock',
      'kind','person_life_consequence',
      'id',v_instance.id::text
    ),
    'evidence',jsonb_build_object(
      'kind','principal_clock_characterization_input',
      'value',v_value,
      'confidence',1,
      'provenance',jsonb_build_object(
        'consequenceInstanceId',v_instance.id,
        'definitionId',v_instance.definition_id,
        'sourceActionId',v_source_action_id
      ),
      'metadata',jsonb_build_object(
        'characterizationComplete',coalesce((v_completeness->>'complete')::boolean,false)
      )
    ),
    'claim',jsonb_strip_nulls(jsonb_build_object(
      'claimType','clock_characterization',
      'lifecycleState','accepted',
      'value',v_value,
      'confidence',1,
      'supersedesClaimId',v_supersedes_claim_id,
      'metadata',jsonb_build_object(
        'consequenceInstanceId',v_instance.id,
        'definitionId',v_instance.definition_id,
        'characterizationComplete',coalesce((v_completeness->>'complete')::boolean,false)
      )
    ))
  ));

  return v_result || jsonb_build_object(
    'contractVersion','person_life_consequence_clock_characterization_v1',
    'consequenceInstanceId',v_instance.id,
    'characterization',v_value,
    'completeness',v_completeness,
    'truthBoundary',jsonb_build_object(
      'consequenceTruthRemainsSeparate',true,
      'partialCharacterizationIsPreserved',true,
      'completeCharacterizationDoesNotMeanClockAdmission',true,
      'missingRelevanceStartDoesNotMeanOpenNow',true,
      'deadlineAloneDoesNotEstablishCurrentRelevance',true,
      'doesNotCreateClockCandidate',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb) is
  'Record or explicitly correct source-backed person Clock characterization for an owned open Person Life Consequence. Partial characterization is preserved; no Clock candidate or placement is created.';

revoke all on function atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)
  from public, anon;
grant execute on function atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)
  to authenticated, service_role;


create or replace function atlas.person_life_consequence_clock_admission_state_v1(
  p_owner_user_id uuid,
  p_consequence_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_principal_id uuid;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_completeness jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_principal_carrier_ref text;
begin
  if p_owner_user_id is null or p_consequence_instance_id is null then
    raise exception 'owner user and consequence instance are required.'
      using errcode='22023';
  end if;

  select p.id
  into v_principal_id
  from atlas.principals p
  where p.user_id=p_owner_user_id
    and p.status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select *
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=p_owner_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open Person Life Consequence not found for this owner.'
      using errcode='42501';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=p_owner_user_id
    and c.subject_domain='principal.clock'
    and c.subject_kind='person_life_consequence'
    and c.subject_id=v_instance.id::text
    and c.claim_type='clock_characterization'
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1;

  v_completeness :=
    atlas.person_life_consequence_clock_characterization_completeness_v1(v_claim.value);

  if v_instance.requirement_state<>'established' then
    v_blockers := v_blockers || '"requirement_not_established"'::jsonb;
  end if;

  v_principal_carrier_ref := 'principal:'||v_principal_id::text;

  if v_instance.carrier_state<>'established'
     or v_instance.carrier_ref is distinct from v_principal_carrier_ref then
    v_blockers := v_blockers || '"principal_carrier_required"'::jsonb;
  end if;

  if v_instance.execution_readiness<>'ready' then
    v_blockers := v_blockers || '"execution_readiness_required"'::jsonb;
  end if;

  if v_claim.id is null then
    v_blockers := v_blockers || '"clock_characterization_required"'::jsonb;
  elsif not coalesce((v_completeness->>'complete')::boolean,false) then
    v_blockers := v_blockers || '"clock_characterization_incomplete"'::jsonb;
  end if;

  return jsonb_build_object(
    'contractVersion','person_life_consequence_clock_admission_state_v1',
    'principalId',v_principal_id,
    'consequenceInstanceId',v_instance.id,
    'requirementState',v_instance.requirement_state,
    'carrierRef',v_instance.carrier_ref,
    'carrierState',v_instance.carrier_state,
    'executionReadiness',v_instance.execution_readiness,
    'placementState',v_instance.placement_state,
    'characterizationClaimId',v_claim.id,
    'characterization',v_claim.value,
    'characterizationCompleteness',v_completeness,
    'admitted',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'truthBoundary',jsonb_build_object(
      'admissionIsNotRequirementTruth',true,
      'admissionRequiresPrincipalCarrier',true,
      'admissionRequiresExecutionReadiness',true,
      'admissionRequiresCompleteClockCharacterization',true,
      'missingRelevanceStartNeverMeansOpenNow',true,
      'deadlineAloneDoesNotEstablishCurrentRelevance',true,
      'admissionDoesNotPlaceClock',true
    )
  );
end;
$$;

comment on function atlas.person_life_consequence_clock_admission_state_v1(uuid,uuid) is
  'Internal read of whether an open person Life Consequence has enough independent authority to become a Principal Clock candidate. No candidate or placement is created.';

revoke all on function atlas.person_life_consequence_clock_admission_state_v1(uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.person_life_consequence_clock_admission_self_api_v1(
  p_consequence_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  return atlas.person_life_consequence_clock_admission_state_v1(
    v_user_id,
    p_consequence_instance_id
  );
end;
$;

comment on function atlas.person_life_consequence_clock_admission_self_api_v1(uuid) is
  'Read the signed-in owner admission state for one open Person Life Consequence. Returns blockers instead of manufacturing missing Clock characterization, carrier, or readiness.';

revoke all on function atlas.person_life_consequence_clock_admission_self_api_v1(uuid)
  from public, anon;
grant execute on function atlas.person_life_consequence_clock_admission_self_api_v1(uuid)
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
    'atlas.record_person_life_consequence_clock_characterization_self_api_v1(p_consequence_instance_id uuid, p_input jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Record explicit source-backed Clock characterization for an owned open Person Life Consequence without creating a Clock candidate.',
      'authorizationBoundary','SECURITY DEFINER fixes person custody to auth.uid(); only approved characterization fields are admitted; corrections require explicit supersession; missing timing never defaults to current relevance.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.person_life_consequence_clock_admission_self_api_v1(p_consequence_instance_id uuid)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Return Clock admission blockers for one owned open Person Life Consequence.',
      'authorizationBoundary','Read-only SECURITY DEFINER endpoint. Admission requires established Principal carrier, ready execution, and complete accepted Clock characterization; no candidate/placement is created.',
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
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Principal consequence Clock characterization registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 7: atlas-laundry-consequence-axis-authority-v1
-- ============================================================================

-- Laundry Consequence Axis Authority v1.
--
-- Requirement, carrier, execution readiness, and Clock placement are distinct
-- authorities. This candidate binds Household responsibility/readiness Claims
-- to the carrier/readiness axes and preserves them across later requirement
-- re-evaluation.

create or replace function atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
  p_owner_user_id uuid,
  p_definition_id uuid,
  p_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_principal_id uuid;
  v_household_id uuid;
  v_definition atlas.person_life_definitions%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_mode text;
begin
  if p_owner_user_id is null or p_definition_id is null or p_claim_id is null then
    raise exception 'owner user, definition id, and responsibility Claim id are required.'
      using errcode='22023';
  end if;

  select p.id,h.id
  into v_principal_id,v_household_id
  from atlas.principals p
  join atlas.households h on h.principal_id=p.id
  where p.user_id=p_owner_user_id
    and p.status='active'
    and h.status='active'
  order by
    case when p.active_household_id=h.id then 0 else 1 end,
    h.created_at,
    h.id
  limit 1;

  if v_principal_id is null or v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=p_owner_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Active Laundry consequence definition not found for this owner.'
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
    and c.subject_id=v_definition.subject_id
    and c.claim_type='ordinary_responsibility'
    and c.lifecycle_state='accepted'
    and c.authority_kind in (
      'household_principal_acceptance',
      'household_principal_correction'
    );

  if v_claim.id is null then
    raise exception 'Current accepted same-instance Laundry ordinary_responsibility Claim required.'
      using errcode='42501';
  end if;

  v_mode := nullif(btrim(v_claim.value->>'mode'),'');

  if v_mode not in (
    'self',
    'shared',
    'other_household_member',
    'outside_household',
    'service',
    'unresolved',
    'other'
  ) then
    raise exception 'Laundry responsibility Claim has unsupported mode.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'claimId',v_claim.id,
    'mode',v_mode,
    'carrierRef',case
      when v_mode='self' then 'principal:'||v_principal_id::text
      else null
    end,
    'carrierState',case
      when v_mode='self' then 'established'
      else 'unresolved'
    end,
    'truthBoundary',jsonb_build_object(
      'selfMayResolvePrincipalCarrier',true,
      'sharedDoesNotMeanPrincipal',true,
      'otherModesDoNotInventCarrierIdentity',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(uuid,uuid,uuid) is
  'Internal deterministic carrier resolution from one accepted current-Household Laundry ordinary_responsibility Claim. V1 resolves self to the active Principal and leaves all other modes unresolved.';

revoke all on function atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.personal_laundry_execution_readiness_from_claim_v1(
  p_owner_user_id uuid,
  p_definition_id uuid,
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
  v_definition atlas.person_life_definitions%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_state text;
begin
  if p_owner_user_id is null or p_definition_id is null or p_claim_id is null then
    raise exception 'owner user, definition id, and readiness Claim id are required.'
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
  into v_definition
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=p_owner_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Active Laundry consequence definition not found for this owner.'
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
    and c.subject_id=v_definition.subject_id
    and c.claim_type='execution_readiness'
    and c.lifecycle_state in ('observed','accepted')
    and c.authority_kind in (
      'household_principal_observation',
      'household_principal_acceptance',
      'household_principal_correction'
    );

  if v_claim.id is null then
    raise exception 'Current same-instance Laundry execution_readiness Claim required.'
      using errcode='42501';
  end if;

  v_state := nullif(btrim(v_claim.value->>'state'),'');

  if v_state not in ('ready','blocked','unknown') then
    raise exception 'Laundry execution_readiness Claim has unsupported state.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'claimId',v_claim.id,
    'state',v_state,
    'executionReadiness',case
      when v_state='ready' then 'ready'
      when v_state='blocked' then 'blocked'
      else 'not_evaluated'
    end,
    'truthBoundary',jsonb_build_object(
      'requirementExistenceIsSeparate',true,
      'blockedDoesNotDeleteRequirement',true,
      'unknownDoesNotBecomeReady',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_execution_readiness_from_claim_v1(uuid,uuid,uuid) is
  'Internal deterministic execution-readiness resolution from one current-Household Laundry execution_readiness Claim. ready/blocked/unknown map to ready/blocked/not_evaluated without affecting requirement truth.';

revoke all on function atlas.personal_laundry_execution_readiness_from_claim_v1(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.guard_personal_laundry_consequence_axis_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_definition atlas.person_life_definitions%rowtype;
  v_carrier_authority jsonb;
  v_old_carrier_authority jsonb;
  v_readiness_authority jsonb;
  v_old_readiness_authority jsonb;
  v_claim_id uuid;
  v_resolution jsonb;
  v_expected_carrier_ref text;
  v_expected_carrier_state text;
  v_expected_readiness text;
begin
  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=new.definition_id;

  if v_definition.id is null
     or v_definition.subject_domain<>'household.laundry'
     or v_definition.subject_kind<>'kernel_instance' then
    return new;
  end if;

  v_carrier_authority := new.evidence->'carrierAuthority';
  v_old_carrier_authority := old.evidence->'carrierAuthority';

  if new.carrier_ref is distinct from old.carrier_ref
     or new.carrier_state is distinct from old.carrier_state then

    if jsonb_typeof(v_carrier_authority)='object'
       and nullif(v_carrier_authority->>'claimId','') is not null then
      begin
        v_claim_id := (v_carrier_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Laundry consequence carrier authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      v_expected_carrier_ref := nullif(v_resolution->>'carrierRef','');
      v_expected_carrier_state := v_resolution->>'carrierState';

      if new.carrier_ref is distinct from v_expected_carrier_ref
         or new.carrier_state is distinct from v_expected_carrier_state then
        raise exception 'Laundry consequence carrier fields must equal the source-backed responsibility resolution.'
          using errcode='23514';
      end if;

    elsif jsonb_typeof(v_old_carrier_authority)='object'
          and nullif(v_old_carrier_authority->>'claimId','') is not null then
      -- A requirement refresh has no carrier authority. Revalidate the old
      -- source Claim before preserving the separately established axis.
      begin
        v_claim_id := (v_old_carrier_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Stored Laundry carrier authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      if old.carrier_ref is distinct from nullif(v_resolution->>'carrierRef','')
         or old.carrier_state is distinct from v_resolution->>'carrierState' then
        raise exception 'Stored Laundry carrier projection no longer matches its source authority.'
          using errcode='23514';
      end if;

      new.carrier_ref := old.carrier_ref;
      new.carrier_state := old.carrier_state;
      new.evidence := coalesce(new.evidence,'{}'::jsonb)
        || jsonb_build_object('carrierAuthority',v_old_carrier_authority);

    elsif new.carrier_ref is not null or new.carrier_state<>'unresolved' then
      raise exception 'Laundry consequence carrier cannot be established without authorized responsibility Claim evidence.'
        using errcode='23514';
    end if;

  elsif jsonb_typeof(v_old_carrier_authority)='object'
        and jsonb_typeof(v_carrier_authority)<>'object' then
    begin
      v_claim_id := (v_old_carrier_authority->>'claimId')::uuid;
    exception when invalid_text_representation then
      raise exception 'Stored Laundry carrier authority Claim id is invalid.'
        using errcode='23514';
    end;

    v_resolution :=
      atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
        new.owner_user_id,
        new.definition_id,
        v_claim_id
      );

    if old.carrier_ref is distinct from nullif(v_resolution->>'carrierRef','')
       or old.carrier_state is distinct from v_resolution->>'carrierState' then
      raise exception 'Stored Laundry carrier projection no longer matches its source authority.'
        using errcode='23514';
    end if;

    new.evidence := coalesce(new.evidence,'{}'::jsonb)
      || jsonb_build_object('carrierAuthority',v_old_carrier_authority);
  end if;

  v_readiness_authority := new.evidence->'readinessAuthority';
  v_old_readiness_authority := old.evidence->'readinessAuthority';

  if new.execution_readiness is distinct from old.execution_readiness then

    if jsonb_typeof(v_readiness_authority)='object'
       and nullif(v_readiness_authority->>'claimId','') is not null then
      begin
        v_claim_id := (v_readiness_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Laundry consequence readiness authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_execution_readiness_from_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      v_expected_readiness := v_resolution->>'executionReadiness';

      if new.execution_readiness is distinct from v_expected_readiness then
        raise exception 'Laundry consequence execution readiness must equal the source-backed readiness resolution.'
          using errcode='23514';
      end if;

    elsif jsonb_typeof(v_old_readiness_authority)='object'
          and nullif(v_old_readiness_authority->>'claimId','') is not null then
      -- A requirement refresh has no readiness authority. Revalidate the old
      -- source Claim before preserving the independently established axis.
      begin
        v_claim_id := (v_old_readiness_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Stored Laundry readiness authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_execution_readiness_from_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      if old.execution_readiness is distinct from v_resolution->>'executionReadiness' then
        raise exception 'Stored Laundry readiness projection no longer matches its source authority.'
          using errcode='23514';
      end if;

      new.execution_readiness := old.execution_readiness;
      new.evidence := coalesce(new.evidence,'{}'::jsonb)
        || jsonb_build_object('readinessAuthority',v_old_readiness_authority);

    elsif new.execution_readiness<>'not_evaluated' then
      raise exception 'Laundry consequence execution readiness cannot change without authorized readiness Claim evidence.'
        using errcode='23514';
    end if;

  elsif jsonb_typeof(v_old_readiness_authority)='object'
        and jsonb_typeof(v_readiness_authority)<>'object' then
    begin
      v_claim_id := (v_old_readiness_authority->>'claimId')::uuid;
    exception when invalid_text_representation then
      raise exception 'Stored Laundry readiness authority Claim id is invalid.'
        using errcode='23514';
    end;

    v_resolution :=
      atlas.personal_laundry_execution_readiness_from_claim_v1(
        new.owner_user_id,
        new.definition_id,
        v_claim_id
      );

    if old.execution_readiness is distinct from v_resolution->>'executionReadiness' then
      raise exception 'Stored Laundry readiness projection no longer matches its source authority.'
        using errcode='23514';
    end if;

    new.evidence := coalesce(new.evidence,'{}'::jsonb)
      || jsonb_build_object('readinessAuthority',v_old_readiness_authority);
  end if;

  -- Placement is intentionally outside this authority.
  if new.placement_state is distinct from old.placement_state then
    raise exception 'Laundry consequence placement state is owned by a later Clock authority, not carrier/readiness reconciliation.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_personal_laundry_consequence_axis_authority_v1() is
  'Protect Laundry Person Life consequence carrier/readiness axes from unauthorized mutation and from erasure during later requirement re-evaluation. Placement remains outside this authority.';

revoke all on function atlas.guard_personal_laundry_consequence_axis_authority_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists person_life_laundry_consequence_axis_guard_v1
  on atlas.person_life_consequence_instances;

create trigger person_life_laundry_consequence_axis_guard_v1
before update on atlas.person_life_consequence_instances
for each row
execute function atlas.guard_personal_laundry_consequence_axis_authority_v1();


create or replace function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(
  p_consequence_instance_id uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_definition atlas.person_life_definitions%rowtype;
  v_responsibility_claim_id uuid;
  v_readiness_claim_id uuid;
  v_carrier_resolution jsonb;
  v_readiness_resolution jsonb;
  v_new_carrier_ref text;
  v_new_carrier_state text;
  v_new_readiness text;
  v_new_evidence jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_consequence_instance_id is null
     or p_input is null
     or jsonb_typeof(p_input)<>'object' then
    raise exception 'consequenceInstanceId and reconciliation input object are required.'
      using errcode='22023';
  end if;

  begin
    v_responsibility_claim_id :=
      nullif(p_input->>'responsibilityClaimId','')::uuid;
    v_readiness_claim_id :=
      nullif(p_input->>'readinessClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'responsibilityClaimId and readinessClaimId must be UUIDs when supplied.'
      using errcode='22023';
  end;

  if v_responsibility_claim_id is null and v_readiness_claim_id is null then
    raise exception 'At least one responsibilityClaimId or readinessClaimId is required.'
      using errcode='22023';
  end if;

  if (select count(*) from jsonb_object_keys(p_input)) <>
     (case when v_responsibility_claim_id is null then 0 else 1 end
      + case when v_readiness_claim_id is null then 0 else 1 end) then
    raise exception 'Unsupported Laundry consequence reconciliation field.'
      using errcode='22023';
  end if;

  select i.*
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=v_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open Laundry consequence not found for the signed-in user.'
      using errcode='42501';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=v_instance.definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Open consequence is not governed by an active Laundry consequence definition.'
      using errcode='42501';
  end if;

  v_new_carrier_ref := v_instance.carrier_ref;
  v_new_carrier_state := v_instance.carrier_state;
  v_new_readiness := v_instance.execution_readiness;
  v_new_evidence := coalesce(v_instance.evidence,'{}'::jsonb);

  if v_responsibility_claim_id is not null then
    v_carrier_resolution :=
      atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
        v_user_id,
        v_instance.definition_id,
        v_responsibility_claim_id
      );

    v_new_carrier_ref := nullif(v_carrier_resolution->>'carrierRef','');
    v_new_carrier_state := v_carrier_resolution->>'carrierState';

    v_new_evidence := v_new_evidence || jsonb_build_object(
      'carrierAuthority',
      jsonb_build_object(
        'claimId',v_responsibility_claim_id,
        'mode',v_carrier_resolution->>'mode',
        'carrierRef',v_new_carrier_ref,
        'carrierState',v_new_carrier_state,
        'resolutionContract','personal_laundry_carrier_resolution_from_responsibility_claim_v1'
      )
    );
  end if;

  if v_readiness_claim_id is not null then
    v_readiness_resolution :=
      atlas.personal_laundry_execution_readiness_from_claim_v1(
        v_user_id,
        v_instance.definition_id,
        v_readiness_claim_id
      );

    v_new_readiness := v_readiness_resolution->>'executionReadiness';

    v_new_evidence := v_new_evidence || jsonb_build_object(
      'readinessAuthority',
      jsonb_build_object(
        'claimId',v_readiness_claim_id,
        'state',v_readiness_resolution->>'state',
        'executionReadiness',v_new_readiness,
        'resolutionContract','personal_laundry_execution_readiness_from_claim_v1'
      )
    );
  end if;

  update atlas.person_life_consequence_instances i
  set carrier_ref=v_new_carrier_ref,
      carrier_state=v_new_carrier_state,
      execution_readiness=v_new_readiness,
      evidence=v_new_evidence,
      updated_at=now()
  where i.id=v_instance.id
    and i.owner_user_id=v_user_id
  returning * into v_instance;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_laundry_consequence_axis_reconciliation_v1',
    'consequence',to_jsonb(v_instance),
    'clockAdmission',
      atlas.person_life_consequence_clock_admission_state_v1(
        v_user_id,
        v_instance.id
      ),
    'truthBoundary',jsonb_build_object(
      'requirementAuthorityUnchanged',true,
      'carrierAuthorityComesOnlyFromResponsibilityClaim',true,
      'readinessAuthorityComesOnlyFromReadinessClaim',true,
      'blockedDoesNotDeleteRequirement',true,
      'placementAuthorityUnchanged',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockCandidate',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb) is
  'Reconcile carrier and/or execution-readiness axes of one owned open Laundry Person Life consequence from explicit current-Household Claims. Requirement and placement authorities are unchanged.';

revoke all on function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)
  from public, anon;
grant execute on function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)
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
values (
  'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(p_consequence_instance_id uuid, p_input jsonb)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Reconcile Laundry consequence carrier/readiness from explicit same-instance current-Household Claims while preserving requirement and placement authority.',
    'authorizationBoundary','SECURITY DEFINER fixes ownership to auth.uid(); carrier derives only from accepted ordinary_responsibility Claim and readiness only from observed/accepted execution_readiness Claim; caller cannot submit axis values directly.',
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
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry consequence axis authority registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 8: atlas-person-life-consequence-clock-candidate-v1
-- ============================================================================

-- Person Life Consequence -> Principal Clock Candidate v1.
-- Live V1 candidate/arbitration/API contracts remain untouched.


create or replace view atlas.principal_person_life_consequence_clock_candidates_v1
as
select
  p.id as principal_id,
  d.subject_domain as domain,
  'person_life_consequence'::text as source_type,
  i.id as source_id,
  case
    when i.consequence_kind='laundry_cycle_needed' then 'Laundry'
    when nullif(i.consequence_kind,'') is not null
      then initcap(replace(i.consequence_kind,'_',' '))
    when nullif(i.action_key,'') is not null
      then initcap(replace(replace(i.action_key,':',' '),'_',' '))
    else 'Required action'
  end as title,
  (cc.value->>'floorClass')::smallint as floor_class,
  nullif(cc.value#>>'{timing,windowStart}','')::timestamptz as window_start,
  nullif(cc.value#>>'{timing,windowEnd}','')::timestamptz as window_end,
  nullif(cc.value#>>'{timing,fixedStart}','')::timestamptz as fixed_start,
  nullif(cc.value#>>'{timing,mustBeginBy}','')::timestamptz as must_begin_by,
  nullif(cc.value#>>'{timing,mustFinishBy}','')::timestamptz as must_finish_by,
  (cc.value->>'expectedMinutes')::integer as expected_minutes,
  cc.value->>'protectionLevel' as protection_level,
  cc.value->>'interruptibility' as interruptibility,
  (cc.value->>'delegable')::boolean as delegable,
  (cc.value->>'ownerRequired')::boolean as owner_required,
  cc.value->>'consequenceOfDelay' as consequence,
  cc.value->>'reasonForFloor' as reason_for_floor,
  null::uuid as portfolio_unit_id,
  null::text as horizon,
  jsonb_build_object(
    'clockCandidateContract','person_life_consequence_clock_candidate_v1',
    'consequenceInstanceId',i.id,
    'definitionId',i.definition_id,
    'consequenceStableKey',i.stable_key,
    'consequenceKind',i.consequence_kind,
    'actionKey',i.action_key,
    'requirementState',i.requirement_state,
    'carrierRef',i.carrier_ref,
    'carrierState',i.carrier_state,
    'executionReadiness',i.execution_readiness,
    'sourceEventId',i.last_seen_event_id,
    'clockCharacterizationClaimId',cc.id,
    'clockCharacterizationPrimaryEvidenceId',cc.primary_evidence_id,
    'subject',jsonb_build_object(
      'domain',d.subject_domain,
      'kind',d.subject_kind,
      'id',d.subject_id
    ),
    'truthBoundary',jsonb_build_object(
      'requirementTruthRemainsPersonLifeConsequence',true,
      'carrierAuthorityPrecedesClockAdmission',true,
      'executionReadinessPrecedesClockAdmission',true,
      'characterizationAuthorityPrecedesClockAdmission',true,
      'relevanceStartIsExplicit',true,
      'candidateProjectionCreatesNoPlacement',true
    )
  ) as metadata
from atlas.person_life_consequence_instances i
join atlas.person_life_definitions d
  on d.id=i.definition_id
 and d.owner_user_id=i.owner_user_id
 and d.signal_kind='consequence'
 and d.status='active'
join lateral (
  select p0.id
  from atlas.principals p0
  where p0.user_id=i.owner_user_id
    and p0.status='active'
  limit 1
) p on true
join lateral (
  select c.*
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=i.owner_user_id
    and c.subject_domain='principal.clock'
    and c.subject_kind='person_life_consequence'
    and c.subject_id=i.id::text
    and c.claim_type='clock_characterization'
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1
) cc on true
cross join lateral (
  select atlas.person_life_consequence_clock_characterization_completeness_v1(cc.value) as state
) complete
where i.status='open'
  and i.requirement_state='established'
  and i.carrier_state='established'
  and i.carrier_ref=('principal:'||p.id::text)
  and i.execution_readiness='ready'
  and coalesce((complete.state->>'complete')::boolean,false);

comment on view atlas.principal_person_life_consequence_clock_candidates_v1 is
  'Read-only Principal Clock candidate projection for Person Life consequences that independently satisfy requirement, Principal-carrier, execution-readiness, and complete accepted Clock-characterization admission.';

revoke all on table atlas.principal_person_life_consequence_clock_candidates_v1
  from public, anon, authenticated;
grant select on table atlas.principal_person_life_consequence_clock_candidates_v1
  to service_role;


create or replace view atlas.principal_clock_candidates_v2
as
select
  principal_id,domain,source_type,source_id,title,floor_class,
  window_start,window_end,fixed_start,must_begin_by,must_finish_by,
  expected_minutes,protection_level,interruptibility,delegable,owner_required,
  consequence,reason_for_floor,portfolio_unit_id,horizon,metadata
from atlas.principal_clock_candidates_v1
union all
select
  principal_id,domain,source_type,source_id,title,floor_class,
  window_start,window_end,fixed_start,must_begin_by,must_finish_by,
  expected_minutes,protection_level,interruptibility,delegable,owner_required,
  consequence,reason_for_floor,portfolio_unit_id,horizon,metadata
from atlas.principal_person_life_consequence_clock_candidates_v1;

comment on view atlas.principal_clock_candidates_v2 is
  'V2 Principal Clock candidate inventory: unchanged V1 candidate inventory plus fully admitted Person Life consequence candidates.';

revoke all on table atlas.principal_clock_candidates_v2
  from public, anon, authenticated;
grant select on table atlas.principal_clock_candidates_v2
  to service_role;


CREATE OR REPLACE FUNCTION atlas.principal_clock_arbitration_v2(p_principal_id uuid, p_day date, p_as_of timestamp with time zone DEFAULT now())
 RETURNS TABLE(arbitration_rank bigint, timing_tier smallint, timing_state text, why_now text, right_to_floor_now boolean, latest_start_at timestamp with time zone, next_boundary_at timestamp with time zone, placement_state text, individually_within_daily_plan boolean, capacity_state text, capacity_known boolean, maximum_planned_minutes integer, discretionary_capacity_minutes integer, principal_id uuid, domain text, source_type text, source_id uuid, title text, floor_class smallint, window_start timestamp with time zone, window_end timestamp with time zone, fixed_start timestamp with time zone, must_begin_by timestamp with time zone, must_finish_by timestamp with time zone, expected_minutes integer, protection_level text, interruptibility text, delegable boolean, owner_required boolean, consequence text, reason_for_floor text, portfolio_unit_id uuid, horizon text, metadata jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
with capacity as (
  select atlas.principal_capacity_day_state_v1(p_principal_id, p_day) as state
), base as (
  select
    c.*,
    coalesce(c.must_finish_by, c.window_end) as finish_boundary,
    case
      when c.expected_minutes is not null
       and c.expected_minutes > 0
       and coalesce(c.must_finish_by, c.window_end) is not null
      then coalesce(c.must_finish_by, c.window_end) - make_interval(mins => c.expected_minutes)
      else null
    end as derived_latest_start_at
  from atlas.principal_clock_candidates_v2 c
  where c.principal_id = p_principal_id
), classified as (
  select
    b.*,
    case
      when b.fixed_start is not null
       and b.fixed_start <= p_as_of
       and b.window_end is not null
       and p_as_of < b.window_end
        then 0
      when b.fixed_start is null
       and b.must_finish_by is not null
       and b.must_finish_by <= p_as_of
        then 10
      when b.fixed_start is null
       and b.must_finish_by is null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 11
      when b.fixed_start is not null
       and b.window_end is null
       and b.fixed_start <= p_as_of
        then 12
      when b.fixed_start is null
       and b.must_begin_by is not null
       and b.must_begin_by <= p_as_of
       and (b.finish_boundary is null or p_as_of < b.finish_boundary)
        then 20
      when b.fixed_start is null
       and b.derived_latest_start_at is not null
       and b.derived_latest_start_at <= p_as_of
       and b.finish_boundary is not null
       and p_as_of < b.finish_boundary
        then 21
      when b.fixed_start is null
       and (b.window_start is null or b.window_start <= p_as_of)
       and (b.window_end is null or p_as_of < b.window_end)
        then 30
      when b.fixed_start is not null
       and b.fixed_start > p_as_of
        then 50
      when b.fixed_start is not null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 90
      when b.window_start is not null
       and b.window_start > p_as_of
        then 60
      else 70
    end::smallint as derived_timing_tier,
    case
      when b.fixed_start is not null
       and b.fixed_start <= p_as_of
       and b.window_end is not null
       and p_as_of < b.window_end
        then 'fixed_active'
      when b.fixed_start is null
       and b.must_finish_by is not null
       and b.must_finish_by <= p_as_of
        then 'finish_boundary_breached'
      when b.fixed_start is null
       and b.must_finish_by is null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 'window_elapsed_unresolved'
      when b.fixed_start is not null
       and b.window_end is null
       and b.fixed_start <= p_as_of
        then 'fixed_point_reached'
      when b.fixed_start is null
       and b.must_begin_by is not null
       and b.must_begin_by <= p_as_of
       and (b.finish_boundary is null or p_as_of < b.finish_boundary)
        then 'must_begin_boundary_reached'
      when b.fixed_start is null
       and b.derived_latest_start_at is not null
       and b.derived_latest_start_at <= p_as_of
       and b.finish_boundary is not null
       and p_as_of < b.finish_boundary
        then 'latest_start_reached'
      when b.fixed_start is null
       and (b.window_start is null or b.window_start <= p_as_of)
       and (b.window_end is null or p_as_of < b.window_end)
        then 'relevant_window_open'
      when b.fixed_start is not null
       and b.fixed_start > p_as_of
        then 'fixed_upcoming'
      when b.fixed_start is not null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 'fixed_elapsed'
      when b.window_start is not null
       and b.window_start > p_as_of
        then 'future_window'
      else 'remembered_without_current_timing'
    end as derived_timing_state,
    (
      select min(x.boundary)
      from (values
        (b.fixed_start),
        (b.window_start),
        (b.must_begin_by),
        (b.derived_latest_start_at),
        (b.must_finish_by),
        (b.window_end)
      ) as x(boundary)
      where x.boundary > p_as_of
    ) as derived_next_boundary_at
  from base b
), enriched as (
  select
    c.*,
    case c.derived_timing_state
      when 'fixed_active' then 'A fixed commitment is in progress.'
      when 'finish_boundary_breached' then 'Its finish boundary has passed while the claim remains open.'
      when 'window_elapsed_unresolved' then 'Its relevant window has elapsed while the claim remains unresolved.'
      when 'fixed_point_reached' then 'Its fixed point has been reached while the claim remains open.'
      when 'must_begin_boundary_reached' then 'Its must-begin boundary has been reached.'
      when 'latest_start_reached' then 'Its latest start has been reached after accounting for expected duration.'
      when 'relevant_window_open' then 'Its relevant window is open.'
      when 'fixed_upcoming' then 'A fixed commitment is upcoming.'
      when 'future_window' then 'Its relevant window has not opened yet.'
      when 'fixed_elapsed' then 'The fixed commitment time window has elapsed.'
      else 'The claim is remembered, but no current timing boundary gives it the floor.'
    end as derived_why_now,
    case c.protection_level
      when 'critical' then 0
      when 'protected' then 1
      when 'standard' then 2
      when 'optional' then 3
      else 4
    end as protection_order
  from classified c
), ranked as (
  select
    e.*,
    row_number() over (
      order by
        e.derived_timing_tier,
        e.floor_class,
        e.protection_order,
        e.derived_next_boundary_at nulls last,
        e.title,
        e.source_id
    ) as derived_arbitration_rank
  from enriched e
), cap as (
  select
    state,
    state ->> 'state' as capacity_state,
    coalesce((state ->> 'capacityKnown')::boolean, false) as capacity_known,
    nullif(state ->> 'maximumPlannedMinutes','')::integer as maximum_planned_minutes,
    nullif(state ->> 'discretionaryCapacityMinutes','')::integer as discretionary_capacity_minutes
  from capacity
)
select
  r.derived_arbitration_rank as arbitration_rank,
  r.derived_timing_tier as timing_tier,
  r.derived_timing_state as timing_state,
  r.derived_why_now as why_now,
  (r.derived_timing_tier <= 30) as right_to_floor_now,
  r.derived_latest_start_at as latest_start_at,
  r.derived_next_boundary_at as next_boundary_at,
  case
    when r.fixed_start is not null or r.source_type = 'capacity_block' then 'fixed_or_precommitted'
    when not cap.capacity_known then 'capacity_anchor_required'
    when r.expected_minutes is null then 'duration_required'
    when cap.maximum_planned_minutes is null then 'capacity_anchor_required'
    when r.expected_minutes <= cap.maximum_planned_minutes then 'eligible_for_placement'
    else 'exceeds_daily_planning_capacity'
  end as placement_state,
  case
    when r.fixed_start is not null or r.source_type = 'capacity_block' then null::boolean
    when not cap.capacity_known then false
    when r.expected_minutes is null or cap.maximum_planned_minutes is null then false
    else r.expected_minutes <= cap.maximum_planned_minutes
  end as individually_within_daily_plan,
  cap.capacity_state,
  cap.capacity_known,
  cap.maximum_planned_minutes,
  cap.discretionary_capacity_minutes,
  r.principal_id,
  r.domain,
  r.source_type,
  r.source_id,
  r.title,
  r.floor_class,
  r.window_start,
  r.window_end,
  r.fixed_start,
  r.must_begin_by,
  r.must_finish_by,
  r.expected_minutes,
  r.protection_level,
  r.interruptibility,
  r.delegable,
  r.owner_required,
  r.consequence,
  r.reason_for_floor,
  r.portfolio_unit_id,
  r.horizon,
  r.metadata
from ranked r
cross join cap
order by r.derived_arbitration_rank;
$function$;


comment on function atlas.principal_clock_arbitration_v2(uuid,date,timestamptz) is
  'V2 read-only Principal Clock arbitration. Applies the released V1 arbitration law to principal_clock_candidates_v2, which adds only fully admitted Person Life consequences.';

revoke all on function atlas.principal_clock_arbitration_v2(uuid,date,timestamptz)
  from public, anon, authenticated, service_role;


CREATE OR REPLACE FUNCTION atlas.principal_clock_api_v2(p_day date DEFAULT CURRENT_DATE, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal_id uuid;
  v_capacity jsonb;
  v_candidates jsonb;
  v_floor jsonb;
  v_readiness jsonb;
  v_coverage_state text;
  v_coverage_mode text;
  v_floor_claim_state text;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_day is null then
    raise exception 'A Principal Clock date is required.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'A Principal Clock as-of time is required.' using errcode='22023';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_clock_api_v3',
      'state','principal_required',
      'serviceDate',p_day,
      'asOf',p_as_of,
      'allocationState','read_only_arbitration',
      'coverageState','principal_required',
      'coverageMode','no_principal_context',
      'floor',null,
      'candidates','[]'::jsonb
    );
  end if;

  v_capacity:=atlas.principal_capacity_day_state_v1(v_principal_id,p_day);
  v_readiness:=atlas.principal_reality_readiness_v3(v_principal_id,p_day);
  v_coverage_state:=coalesce(v_readiness->>'state','source_required');
  v_coverage_mode:=case
    when v_coverage_state='ready' then 'governed_field'
    else 'known_reality_slice'
  end;

  select coalesce(jsonb_agg(to_jsonb(a) order by a.arbitration_rank),'[]'::jsonb)
  into v_candidates
  from atlas.principal_clock_arbitration_v2(v_principal_id,p_day,p_as_of) a;

  select to_jsonb(a)
  into v_floor
  from atlas.principal_clock_arbitration_v2(v_principal_id,p_day,p_as_of) a
  where a.right_to_floor_now
    and a.timing_state<>'fixed_elapsed'
  order by a.arbitration_rank
  limit 1;

  v_floor_claim_state:=case
    when v_floor is null and v_coverage_state='ready' then 'no_known_claim_has_floor'
    when v_floor is null then 'no_known_claim_has_floor_but_coverage_incomplete'
    when v_coverage_state='ready' then 'valid_governed_floor'
    else 'valid_floor_within_known_slice'
  end;

  return jsonb_build_object(
    'contractVersion','principal_clock_api_v3',
    'state','ready',
    'arbitrationState','ready',
    'principalId',v_principal_id,
    'serviceDate',p_day,
    'asOf',p_as_of,
    'allocationState','read_only_arbitration',
    'coverageState',v_coverage_state,
    'coverageMode',v_coverage_mode,
    'completeFieldClaim',(v_coverage_state='ready'),
    'floorClaimState',v_floor_claim_state,
    'coverageSummary',v_readiness->'summary',
    'capacity',v_capacity,
    'floor',v_floor,
    'candidates',v_candidates,
    'truthBoundary',jsonb_build_object(
      'floorRanksOnlyKnownLawfulCandidates',true,
      'partialCoverageDoesNotInvalidateKnownCandidate',true,
      'partialCoverageDoesNotProveNoOtherCandidateExists',true,
      'unknownCapacityDoesNotBecomeFreeCapacity',true,
      'sourceGapsRemainOutsideClockCandidateInventory',true,
      'arbitrationReadyDoesNotMeanRealityCoverageComplete',true,
      'personLifeConsequenceCandidatesRequireExplicitAdmission',true,
      'missingCharacterizationNeverDefaultsToClockRelevance',true
    )
  );
end;
$function$;


comment on function atlas.principal_clock_api_v2(date,timestamptz) is
  'Authenticated V2 Principal Clock read. Preserves existing arbitration/capacity/coverage semantics while adding only fully admitted Person Life consequence candidates through the V2 inventory.';

revoke all on function atlas.principal_clock_api_v2(date,timestamptz)
  from public, anon;
grant execute on function atlas.principal_clock_api_v2(date,timestamptz)
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
values (
  'atlas.principal_clock_api_v2(date, timestamp with time zone)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Return V2 read-only Principal Clock arbitration over unchanged V1 candidates plus fully admitted Person Life consequences.',
    'authorizationBoundary','Principal identity remains auth-bound. Person Life consequences enter only after requirement, Principal carrier, execution-readiness, and complete accepted Clock-characterization admission. Endpoint creates no placement.',
    'contract','principal_clock_api_v3',
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
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Principal Clock V2 registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 9: atlas-laundry-actual-consequence-resolution-v1
-- ============================================================================

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
    'atlas.record_personal_laundry_actual_self_api_v1(p_input jsonb)',
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
    'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(p_consequence_instance_id uuid, p_actual_claim_id uuid)',
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

do $$
begin
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry actual resolution registration.';
  end if;
end
$$;

-- ============================================================================
-- Laundry closed-loop tranche 10: atlas-laundry-learning-proposal-v1
-- ============================================================================

-- Laundry Learning Proposal v1.
--
-- Repeated physical actuals may support a proposal. They never silently create
-- an accepted household Rhythm or other durable operating truth.

create or replace function atlas.propose_personal_laundry_weekly_pattern_self_api_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_household_id uuid;
  v_timezone text;
  v_instance atlas.household_kernel_instances%rowtype;
  v_dates date[];
  v_claim_ids uuid[];
  v_evidence_ids uuid[];
  v_dows integer[];
  v_gaps integer[];
  v_support_count integer;
  v_same_weekday boolean;
  v_gaps_stable boolean;
  v_weekday integer;
  v_weekday_name text;
  v_proposal_value jsonb;
  v_analysis_value jsonb;
  v_source_key text;
  v_analysis_evidence_id uuid;
  v_proposal_claim_id uuid;
  v_existing_claim_id uuid;
  v_created boolean := false;
  v_idx integer;
  v_existing_value jsonb;
  v_existing_analysis jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  v_household_id := atlas.principal_current_household_id_v1();

  if v_principal_id is null or v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  v_timezone := atlas.principal_authoritative_timezone_v1(v_principal_id);

  select *
  into v_instance
  from atlas.household_kernel_instances i
  where i.household_id=v_household_id
    and i.kernel_key='household.laundry'
    and i.state='active'
  limit 1;

  if v_instance.id is null then
    raise exception 'Active Laundry instance required before learning patterns.'
      using errcode='42501';
  end if;

  with actuals as (
    select
      c.id as claim_id,
      e.id as evidence_id,
      e.observed_at,
      (e.observed_at at time zone v_timezone)::date as local_date,
      extract(dow from (e.observed_at at time zone v_timezone)::date)::integer as local_dow,
      row_number() over (
        partition by (e.observed_at at time zone v_timezone)::date
        order by e.observed_at,e.id
      ) as within_day_rank
    from atlas.claim_records c
    join atlas.evidence_records e on e.id=c.primary_evidence_id
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type='process_actual'
      and c.lifecycle_state='observed'
      and c.authority_kind='household_principal_observation'
      and c.value->>'transition'='entered_washing'
      and c.value->>'toState'='washing'
      and e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.subject_domain='household.laundry'
      and e.subject_kind='kernel_instance'
      and e.subject_id=v_instance.id::text
      and e.evidence_kind='physical_process_actual'
      and e.provenance->>'actualContract'='personal_laundry_process_actual_v1'
      and e.observed_at is not null
  ), distinct_dates as (
    select claim_id,evidence_id,observed_at,local_date,local_dow
    from actuals
    where within_day_rank=1
    order by local_date desc
    limit 4
  ), ordered as (
    select *
    from distinct_dates
    order by local_date
  )
  select
    array_agg(local_date order by local_date),
    array_agg(claim_id order by local_date),
    array_agg(evidence_id order by local_date),
    array_agg(local_dow order by local_date),
    count(*)::integer
  into
    v_dates,
    v_claim_ids,
    v_evidence_ids,
    v_dows,
    v_support_count
  from ordered;

  if coalesce(v_support_count,0)<4 then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','personal_laundry_weekly_pattern_learning_v1',
      'state','insufficient_evidence',
      'supportCount',coalesce(v_support_count,0),
      'requiredDistinctDates',4,
      'proposalCreated',false,
      'truthBoundary',jsonb_build_object(
        'learningDoesNotGuessFromSparseEvidence',true,
        'doesNotCreateRhythm',true
      )
    );
  end if;

  v_same_weekday :=
    v_dows[1]=v_dows[2]
    and v_dows[2]=v_dows[3]
    and v_dows[3]=v_dows[4];

  v_gaps := array[
    (v_dates[2]-v_dates[1])::integer,
    (v_dates[3]-v_dates[2])::integer,
    (v_dates[4]-v_dates[3])::integer
  ];

  v_gaps_stable :=
    v_gaps[1] between 6 and 8
    and v_gaps[2] between 6 and 8
    and v_gaps[3] between 6 and 8;

  if not v_same_weekday or not v_gaps_stable then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','personal_laundry_weekly_pattern_learning_v1',
      'state','pattern_not_stable',
      'supportCount',v_support_count,
      'localDates',to_jsonb(v_dates),
      'localWeekdays',to_jsonb(v_dows),
      'gapDays',to_jsonb(v_gaps),
      'proposalCreated',false,
      'truthBoundary',jsonb_build_object(
        'nonmatchingActualsRemainActuals',true,
        'learningDoesNotForcePattern',true,
        'doesNotCreateRhythm',true
      )
    );
  end if;

  v_weekday := v_dows[1];
  v_weekday_name := trim(to_char(v_dates[1],'Day'));

  v_proposal_value := jsonb_build_object(
    'patternKind','weekly',
    'proposedLocalWeekday',v_weekday,
    'proposedLocalWeekdayName',v_weekday_name,
    'basisTransition','entered_washing',
    'cadenceToleranceDays',jsonb_build_array(6,8)
  );

  v_analysis_value := jsonb_build_object(
    'analysisContract','personal_laundry_weekly_pattern_learning_v1',
    'timezone',v_timezone,
    'instanceId',v_instance.id,
    'basisTransition','entered_washing',
    'localDates',to_jsonb(v_dates),
    'localWeekdays',to_jsonb(v_dows),
    'gapDays',to_jsonb(v_gaps),
    'actualClaimIds',to_jsonb(v_claim_ids),
    'actualEvidenceIds',to_jsonb(v_evidence_ids),
    'result',v_proposal_value
  );

  -- If the same proposal is already awaiting adjudication, do not create a
  -- duplicate prompt. Attach any newly selected actual Evidence as support.
  select c.id
  into v_existing_claim_id
  from atlas.claim_records c
  where c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=v_instance.id::text
    and c.claim_type='rhythm_pattern_proposal'
    and c.lifecycle_state='proposed'
    and c.authority_kind='derived_pattern_proposal'
    and c.value=v_proposal_value
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_existing_claim_id is not null then
    for v_idx in 1..array_length(v_evidence_ids,1)
    loop
      insert into atlas.claim_evidence_links(
        claim_id,evidence_id,relation_kind,metadata
      ) values (
        v_existing_claim_id,
        v_evidence_ids[v_idx],
        'supports',
        jsonb_build_object(
          'supportRole','physical_actual',
          'actualClaimId',v_claim_ids[v_idx],
          'learningContract','personal_laundry_weekly_pattern_learning_v1'
        )
      )
      on conflict do nothing;
    end loop;

    return jsonb_build_object(
      'ok',true,
      'contractVersion','personal_laundry_weekly_pattern_learning_v1',
      'state','already_proposed',
      'proposalCreated',false,
      'proposalClaimId',v_existing_claim_id,
      'proposal',v_proposal_value,
      'supportActualClaimIds',to_jsonb(v_claim_ids),
      'truthBoundary',jsonb_build_object(
        'additionalEvidenceMayStrengthenProposal',true,
        'proposalValueWasNotSilentlyChanged',true,
        'proposalStillRequiresAdjudication',true,
        'doesNotCreateRhythm',true
      )
    );
  end if;

  v_source_key :=
    'household.laundry:weekly_pattern:'
    ||v_instance.id::text||':'
    ||array_to_string(v_claim_ids,':');

  insert into atlas.evidence_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    evidence_kind,
    source_kind,
    source_key,
    actor_user_id,
    value,
    confidence,
    observed_at,
    learned_at,
    provenance,
    metadata
  ) values (
    'household',
    v_household_id,
    'household.laundry',
    'kernel_instance',
    v_instance.id::text,
    'derived_pattern_analysis',
    'household_learning_engine',
    v_source_key,
    null,
    v_analysis_value,
    null,
    null,
    now(),
    jsonb_build_object(
      'learningContract','personal_laundry_weekly_pattern_learning_v1',
      'derivedFromActualEvidenceIds',to_jsonb(v_evidence_ids),
      'derivedFromActualClaimIds',to_jsonb(v_claim_ids)
    ),
    jsonb_build_object(
      'proposalAuthority',false,
      'acceptedTruthAuthority',false,
      'rhythmAuthority',false
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_analysis_evidence_id;

  if v_analysis_evidence_id is null then
    select e.id,e.value
    into v_analysis_evidence_id,v_existing_analysis
    from atlas.evidence_records e
    where e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.source_kind='household_learning_engine'
      and e.source_key=v_source_key
      and e.subject_domain='household.laundry'
      and e.subject_kind='kernel_instance'
      and e.subject_id=v_instance.id::text
      and e.evidence_kind='derived_pattern_analysis';

    if v_analysis_evidence_id is null
       or v_existing_analysis is distinct from v_analysis_value then
      raise exception 'Laundry learning sourceKey retry does not match existing analysis Evidence.'
        using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    claim_type,
    lifecycle_state,
    authority_kind,
    source_kind,
    source_key,
    value,
    confidence,
    primary_evidence_id,
    metadata
  ) values (
    'household',
    v_household_id,
    'household.laundry',
    'kernel_instance',
    v_instance.id::text,
    'rhythm_pattern_proposal',
    'proposed',
    'derived_pattern_proposal',
    'household_learning_engine',
    v_source_key,
    v_proposal_value,
    null,
    v_analysis_evidence_id,
    jsonb_build_object(
      'learningContract','personal_laundry_weekly_pattern_learning_v1',
      'requiresHumanOrGovernedAdjudication',true,
      'materializesRhythm',false
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_proposal_claim_id;

  if v_proposal_claim_id is not null then
    v_created := true;
  else
    select c.id,c.value
    into v_proposal_claim_id,v_existing_value
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.source_kind='household_learning_engine'
      and c.source_key=v_source_key
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type='rhythm_pattern_proposal'
      and c.lifecycle_state='proposed'
      and c.authority_kind='derived_pattern_proposal';

    if v_proposal_claim_id is null
       or v_existing_value is distinct from v_proposal_value then
      raise exception 'Laundry learning sourceKey retry does not match existing proposed Claim.'
        using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_evidence_links(
    claim_id,evidence_id,relation_kind,metadata
  ) values (
    v_proposal_claim_id,
    v_analysis_evidence_id,
    'supports',
    jsonb_build_object(
      'primary',true,
      'supportRole','derived_analysis',
      'learningContract','personal_laundry_weekly_pattern_learning_v1'
    )
  )
  on conflict do nothing;

  for v_idx in 1..array_length(v_evidence_ids,1)
  loop
    insert into atlas.claim_evidence_links(
      claim_id,evidence_id,relation_kind,metadata
    ) values (
      v_proposal_claim_id,
      v_evidence_ids[v_idx],
      'supports',
      jsonb_build_object(
        'supportRole','physical_actual',
        'actualClaimId',v_claim_ids[v_idx],
        'learningContract','personal_laundry_weekly_pattern_learning_v1'
      )
    )
    on conflict do nothing;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_laundry_weekly_pattern_learning_v1',
    'state','proposed',
    'proposalCreated',v_created,
    'proposalClaimId',v_proposal_claim_id,
    'analysisEvidenceId',v_analysis_evidence_id,
    'proposal',v_proposal_value,
    'supportActualClaimIds',to_jsonb(v_claim_ids),
    'supportActualEvidenceIds',to_jsonb(v_evidence_ids),
    'truthBoundary',jsonb_build_object(
      'actualsRemainSourceTruth',true,
      'patternIsProposalNotAcceptedTruth',true,
      'proposalAuthorityIsDerivedNotPrincipalAuthored',true,
      'proposalRequiresAdjudication',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateTask',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.propose_personal_laundry_weekly_pattern_self_api_v1() is
  'Conservative Laundry learner. Four distinct entered_washing dates on the same Principal-local weekday with 6-8 day adjacent gaps may create a derived Household rhythm-pattern proposal with all supporting actual Evidence linked. Never accepts or materializes a Rhythm.';

revoke all on function atlas.propose_personal_laundry_weekly_pattern_self_api_v1()
  from public, anon;
grant execute on function atlas.propose_personal_laundry_weekly_pattern_self_api_v1()
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
values (
  'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Analyze source-backed Laundry cycle-start actuals and, only under the narrow deterministic V1 rule, create or reinforce a derived weekly-pattern proposal.',
    'authorizationBoundary','SECURITY DEFINER fixes current Household and Laundry instance to auth-bound Principal custody. Fewer than four distinct dates, mixed weekdays, or gaps outside 6-8 days create no proposal. Any output Claim remains proposed with derived authority and never materializes Rhythm.',
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
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry learning proposal registration.';
  end if;
end
$$;

commit;
