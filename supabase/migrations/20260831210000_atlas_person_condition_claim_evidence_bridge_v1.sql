-- Atlas Person Condition Claim / Evidence Bridge v1
--
-- Repairs ownership for first-party person condition observations. Human reports
-- become canonical Claim / Evidence first. Generic Care remains a derived state
-- projection for condition-oriented consumers; it no longer owns the person
-- observation itself.
--
-- The public person-condition RPC signature stays stable so existing callers do
-- not need a parallel health-specific write path.

begin;

-- Production was verified to contain no person-owned Care observations before
-- this repair. If that changes before release, stop rather than silently recast
-- newly-created source truth as derived state.
do $$
begin
  if exists (
    select 1
    from atlas.care_observation_events o
    where o.scope_kind = 'person'
  ) then
    raise exception 'Person Care observations appeared before the Claim/Evidence ownership repair; adjudicate them explicitly before release.';
  end if;
end
$$;

alter table atlas.care_observation_events
  add column if not exists source_evidence_id uuid references atlas.evidence_records(id) on delete restrict,
  add column if not exists source_claim_id uuid references atlas.claim_records(id) on delete restrict;

comment on column atlas.care_observation_events.source_evidence_id is
  'Canonical Evidence source for a derived Care observation when one exists. Person-owned condition observations require this provenance after the Claim/Evidence cutover.';
comment on column atlas.care_observation_events.source_claim_id is
  'Canonical Claim source for a derived Care observation when one exists. Person-owned condition observations require this provenance after the Claim/Evidence cutover.';

create index if not exists care_observation_events_source_evidence_idx
  on atlas.care_observation_events(source_evidence_id)
  where source_evidence_id is not null;
create index if not exists care_observation_events_source_claim_idx
  on atlas.care_observation_events(source_claim_id)
  where source_claim_id is not null;

create or replace function atlas.guard_person_care_derivation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_e_scope_kind text;
  v_e_scope_id uuid;
  v_e_subject_domain text;
  v_e_subject_kind text;
  v_e_subject_id text;
  v_e_kind text;
  v_e_actor uuid;
  v_e_observed_at timestamptz;
  v_e_value jsonb;
  v_c_scope_kind text;
  v_c_scope_id uuid;
  v_c_subject_domain text;
  v_c_subject_kind text;
  v_c_subject_id text;
  v_c_type text;
  v_c_state text;
  v_c_authority text;
  v_c_primary_evidence_id uuid;
  v_c_value jsonb;
begin
  if new.scope_kind <> 'person' then
    return new;
  end if;

  if new.source_kind <> 'person_claim_evidence_condition' then
    raise exception 'Person Care observations must be derived from canonical Claim/Evidence.' using errcode='23514';
  end if;
  if new.source_evidence_id is null or new.source_claim_id is null then
    raise exception 'Person Care derivation requires source evidence and claim ids.' using errcode='23514';
  end if;

  select
    e.scope_kind,e.scope_id,e.subject_domain,e.subject_kind,e.subject_id,
    e.evidence_kind,e.actor_user_id,e.observed_at,e.value
  into
    v_e_scope_kind,v_e_scope_id,v_e_subject_domain,v_e_subject_kind,v_e_subject_id,
    v_e_kind,v_e_actor,v_e_observed_at,v_e_value
  from atlas.evidence_records e
  where e.id = new.source_evidence_id;

  select
    c.scope_kind,c.scope_id,c.subject_domain,c.subject_kind,c.subject_id,
    c.claim_type,c.lifecycle_state,c.authority_kind,c.primary_evidence_id,c.value
  into
    v_c_scope_kind,v_c_scope_id,v_c_subject_domain,v_c_subject_kind,v_c_subject_id,
    v_c_type,v_c_state,v_c_authority,v_c_primary_evidence_id,v_c_value
  from atlas.claim_records c
  where c.id = new.source_claim_id;

  if v_e_scope_kind is null or v_c_scope_kind is null
     or v_e_scope_kind is distinct from 'person'
     or v_c_scope_kind is distinct from 'person'
     or v_e_scope_id is distinct from new.scope_id
     or v_c_scope_id is distinct from new.scope_id
     or v_e_actor is distinct from new.scope_id
     or new.observed_by_user_id is distinct from new.scope_id then
    raise exception 'Person Care derivation custody must match its canonical Claim/Evidence owner.' using errcode='23514';
  end if;

  if v_e_subject_domain is distinct from new.subject_domain
     or v_e_subject_kind is distinct from new.subject_kind
     or v_e_subject_id is distinct from new.subject_id
     or v_c_subject_domain is distinct from new.subject_domain
     or v_c_subject_kind is distinct from new.subject_kind
     or v_c_subject_id is distinct from new.subject_id then
    raise exception 'Person Care derivation subject must match its canonical Claim/Evidence subject.' using errcode='23514';
  end if;

  if v_e_kind is distinct from 'condition_observation'
     or v_c_type is distinct from 'condition_observation'
     or v_c_state not in ('observed','superseded')
     or v_c_authority is distinct from 'person_reported_observation'
     or v_c_primary_evidence_id is distinct from new.source_evidence_id then
    raise exception 'Person Care derivation requires a first-party observed condition Claim backed by the supplied Evidence.' using errcode='23514';
  end if;

  if v_e_value->>'conditionState' is distinct from new.condition_state
     or v_c_value->>'conditionState' is distinct from new.condition_state
     or v_e_value->>'disposition' is distinct from new.disposition
     or v_c_value->>'disposition' is distinct from new.disposition
     or v_e_observed_at is distinct from new.observed_at
     or new.inferred_from_clock is distinct from false then
    raise exception 'Derived Care state must reproduce the canonical observed condition without changing it.' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_person_care_derivation_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_care_derivation_v1() to service_role;

drop trigger if exists person_care_derivation_guard_v1 on atlas.care_observation_events;
create trigger person_care_derivation_guard_v1
before insert or update on atlas.care_observation_events
for each row execute function atlas.guard_person_care_derivation_v1();

-- Preserve the existing Care current-state adapter, but make the canonical
-- Claim/Evidence provenance visible in the derived projection.
create or replace function atlas.care_apply_observation_current_state_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  insert into atlas.care_current_state (
    subject_domain,
    subject_kind,
    subject_id,
    scope_kind,
    scope_id,
    condition_state,
    disposition,
    last_observed_at,
    last_observation_id,
    metadata
  )
  values (
    new.subject_domain,
    new.subject_kind,
    new.subject_id,
    new.scope_kind,
    new.scope_id,
    new.condition_state,
    new.disposition,
    new.observed_at,
    new.id,
    jsonb_strip_nulls(jsonb_build_object(
      'lastObservationSourceKind', new.source_kind,
      'sourceEvidenceId', new.source_evidence_id,
      'sourceClaimId', new.source_claim_id,
      'derivedFromCanonicalEvidence', case when new.scope_kind='person' then true else null end,
      'inferredFromClock', false
    ))
  )
  on conflict (scope_kind, scope_id, subject_domain, subject_kind, subject_id)
  do update set
    condition_state = excluded.condition_state,
    disposition = excluded.disposition,
    last_observed_at = excluded.last_observed_at,
    last_observation_id = excluded.last_observation_id,
    metadata = coalesce(atlas.care_current_state.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = now()
  where excluded.last_observed_at >= atlas.care_current_state.last_observed_at;

  return new;
end;
$$;

revoke all on function atlas.care_apply_observation_current_state_v1() from public, anon, authenticated;
grant execute on function atlas.care_apply_observation_current_state_v1() to service_role;

create or replace function atlas.record_person_condition_observation_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_condition_state text;
  v_disposition text;
  v_source_key text;
  v_storage_key text;
  v_derived_key text;
  v_observed_at timestamptz;
  v_note text;
  v_metadata jsonb;
  v_value jsonb;
  v_capture jsonb;
  v_evidence_id uuid;
  v_claim_id uuid;
  v_observation_id uuid;
  v_care_metadata jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  v_subject_domain := btrim(coalesce(p_payload->>'subjectDomain',''));
  v_subject_kind := btrim(coalesce(p_payload->>'subjectKind',''));
  v_subject_id := btrim(coalesce(p_payload->>'subjectId',''));
  v_condition_state := btrim(coalesce(p_payload->>'conditionState',''));

  if v_subject_domain='' then raise exception 'subjectDomain is required.' using errcode='22023'; end if;
  if v_subject_kind='' then raise exception 'subjectKind is required.' using errcode='22023'; end if;
  if v_subject_id='' then raise exception 'subjectId is required.' using errcode='22023'; end if;
  if v_condition_state='' then raise exception 'conditionState is required.' using errcode='22023'; end if;

  v_disposition := nullif(btrim(coalesce(p_payload->>'disposition','')),'');
  if v_disposition is null then
    v_disposition := atlas.care_condition_disposition_v1(v_condition_state);
  end if;
  if v_disposition is null then
    v_disposition := 'observe';
  end if;
  if v_disposition not in ('observe','hold','reassess','intervene') then
    raise exception 'Unsupported disposition.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key='' then
    raise exception 'sourceKey is required for idempotent condition observations.' using errcode='22023';
  end if;

  v_note := nullif(p_payload->>'note','');
  v_metadata := coalesce(p_payload->'metadata','{}'::jsonb);
  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be an object.' using errcode='22023';
  end if;

  -- Keep the historical namespace so an existing client idempotency key has one
  -- stable identity across the endpoint cutover.
  v_storage_key := 'person_condition_observation:' || v_user_id::text || ':' || v_source_key;

  if nullif(p_payload->>'observedAt','') is not null then
    v_observed_at := (p_payload->>'observedAt')::timestamptz;
  else
    -- If this is an idempotent retry after the cutover, reuse the canonical
    -- Evidence timestamp rather than manufacturing a new now().
    select e.observed_at into v_observed_at
    from atlas.evidence_records e
    where e.scope_kind='person'
      and e.scope_id=v_user_id
      and e.source_kind='person_capture'
      and e.source_key=v_storage_key;
    v_observed_at := coalesce(v_observed_at,now());
  end if;

  v_value := jsonb_strip_nulls(jsonb_build_object(
    'conditionState',v_condition_state,
    'disposition',v_disposition,
    'note',v_note
  ));

  v_capture := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey',v_storage_key,
    'subject',jsonb_build_object(
      'domain',v_subject_domain,
      'kind',v_subject_kind,
      'id',v_subject_id
    ),
    'evidence',jsonb_build_object(
      'kind','condition_observation',
      'value',v_value,
      'observedAt',v_observed_at,
      'provenance',jsonb_build_object(
        'adapter','atlas.record_person_condition_observation_api_v1',
        'sourceKind','person_condition_observation',
        'clientSourceKey',v_source_key,
        'canonicalOwner','claim_evidence'
      ),
      'metadata',v_metadata || jsonb_build_object('captureSurface','person_condition_observation')
    ),
    'claim',jsonb_build_object(
      'claimType','condition_observation',
      'lifecycleState','observed',
      'value',v_value,
      'validFrom',v_observed_at,
      'metadata',v_metadata || jsonb_build_object('captureSurface','person_condition_observation')
    )
  ));

  v_evidence_id := (v_capture->>'evidenceId')::uuid;
  v_claim_id := (v_capture->>'claimId')::uuid;
  if v_evidence_id is null or v_claim_id is null then
    raise exception 'Canonical condition Claim/Evidence capture did not return source ids.' using errcode='23514';
  end if;

  v_derived_key := 'person_claim_evidence_condition:' || v_evidence_id::text;
  v_care_metadata := v_metadata || jsonb_build_object(
    'canonicalEvidenceId',v_evidence_id,
    'canonicalClaimId',v_claim_id,
    'canonicalSourceKey',v_storage_key,
    'derivedProjection',true
  );

  insert into atlas.care_observation_events (
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,observed_at,
    condition_state,disposition,observed_by_user_id,source_kind,source_key,note,
    inferred_from_clock,metadata,source_evidence_id,source_claim_id
  ) values (
    v_subject_domain,v_subject_kind,v_subject_id,'person',v_user_id,v_observed_at,
    v_condition_state,v_disposition,v_user_id,'person_claim_evidence_condition',v_derived_key,v_note,
    false,v_care_metadata,v_evidence_id,v_claim_id
  )
  on conflict (source_key) do nothing
  returning id into v_observation_id;

  if v_observation_id is null then
    select o.id into v_observation_id
    from atlas.care_observation_events o
    where o.source_key=v_derived_key
      and o.scope_kind='person'
      and o.scope_id=v_user_id
      and o.subject_domain=v_subject_domain
      and o.subject_kind=v_subject_kind
      and o.subject_id=v_subject_id
      and o.observed_at=v_observed_at
      and o.condition_state=v_condition_state
      and o.disposition=v_disposition
      and o.observed_by_user_id=v_user_id
      and o.source_kind='person_claim_evidence_condition'
      and o.note is not distinct from v_note
      and o.inferred_from_clock=false
      and o.metadata=v_care_metadata
      and o.source_evidence_id=v_evidence_id
      and o.source_claim_id=v_claim_id;

    if v_observation_id is null then
      raise exception 'Canonical condition capture exists but its derived Care projection does not match.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,
    'scopeKind','person',
    'scopeId',v_user_id,
    'subjectDomain',v_subject_domain,
    'subjectKind',v_subject_kind,
    'subjectId',v_subject_id,
    'observationId',v_observation_id,
    'evidenceId',v_evidence_id,
    'claimId',v_claim_id,
    'conditionState',v_condition_state,
    'disposition',v_disposition,
    'canonicalTruth','claim_evidence',
    'careDerived',true,
    'inferredFromClock',false,
    'truthBoundary',jsonb_build_object(
      'humanObservationOwnedByClaimEvidence',true,
      'careIsDerivedProjection',true,
      'appearsInPersonLifeTimelineWithoutCareAdapter',true,
      'doesNotDiagnose',true,
      'doesNotInventCausation',true,
      'doesNotCreateConsequence',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_person_condition_observation_api_v1(jsonb) is
  'First-party condition observation adapter. The human report is canonically captured as person Claim/Evidence, then Generic Care receives a provenance-linked derived projection. It does not diagnose, infer causation, create consequences, schedule work, infer from Clock, or grant practitioner access.';

-- Same authenticated RPC signature; custody registration must remain intact.
do $$
begin
  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1()
    where signature='atlas.record_person_condition_observation_api_v1(jsonb)'
  ) then
    raise exception 'Person-condition authenticated RPC custody drifted after Claim/Evidence ownership cutover.';
  end if;
end
$$;

commit;
