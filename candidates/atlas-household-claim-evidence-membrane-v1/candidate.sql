begin;

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

commit;
