-- Atlas person-owned life feedback loop v1
--
-- Closes the first human vertical-slice orchestration seam without creating a
-- second scheduler. A canonical person observation can satisfy one current
-- Rhythm opportunity and immediately re-evaluate its linked Goal. Separately,
-- an already-authorized person Consequence can apply its exact presentation-only
-- overlay to the next current Rhythm opportunity. The accepted plan remains the
-- scheduling authority; the Goal is not rewritten; no Task or Clock placement is
-- created.

begin;

alter table atlas.person_rhythm_opportunities
  add column if not exists satisfied_by_evidence_id uuid references atlas.evidence_records(id) on delete restrict,
  add column if not exists satisfied_by_claim_id uuid references atlas.claim_records(id) on delete restrict,
  add column if not exists satisfaction_event_id uuid references atlas.person_life_state_events(id) on delete restrict,
  add column if not exists satisfied_at timestamptz,
  add column if not exists presentation_consequence_instance_id uuid references atlas.person_life_consequence_instances(id) on delete restrict,
  add column if not exists presentation_consequence_event_id uuid references atlas.person_life_state_events(id) on delete restrict,
  add column if not exists presentation_applied_at timestamptz;

create index if not exists person_rhythm_opportunities_satisfied_evidence_idx
  on atlas.person_rhythm_opportunities(satisfied_by_evidence_id);
create index if not exists person_rhythm_opportunities_satisfied_claim_idx
  on atlas.person_rhythm_opportunities(satisfied_by_claim_id);
create index if not exists person_rhythm_opportunities_satisfaction_event_idx
  on atlas.person_rhythm_opportunities(satisfaction_event_id);
create index if not exists person_rhythm_opportunities_presentation_consequence_instance_idx
  on atlas.person_rhythm_opportunities(presentation_consequence_instance_id);
create index if not exists person_rhythm_opportunities_presentation_consequence_event_idx
  on atlas.person_rhythm_opportunities(presentation_consequence_event_id);

create unique index if not exists person_rhythm_opportunities_one_occurrence_per_rhythm_evidence_idx
  on atlas.person_rhythm_opportunities(rhythm_definition_id,satisfied_by_evidence_id)
  where satisfied_by_evidence_id is not null;

create unique index if not exists person_rhythm_opportunities_one_presentation_application_per_consequence_event_idx
  on atlas.person_rhythm_opportunities(presentation_consequence_instance_id,presentation_consequence_event_id)
  where presentation_consequence_instance_id is not null
    and presentation_consequence_event_id is not null;

comment on column atlas.person_rhythm_opportunities.satisfied_by_evidence_id is
  'Canonical person Evidence that satisfied this projected Rhythm opportunity. Evidence remains Claim/Evidence-owned.';
comment on column atlas.person_rhythm_opportunities.satisfaction_event_id is
  'Person-life rhythm_satisfaction event proving how the canonical Evidence changed Rhythm state.';
comment on column atlas.person_rhythm_opportunities.presentation_consequence_instance_id is
  'Authorized person Consequence instance whose exact presentation-only actionSpec adapted this opportunity.';
comment on column atlas.person_rhythm_opportunities.presentation_consequence_event_id is
  'Exact consequence_evaluation event cycle that authorized the stored presentation overlay.';

create or replace function atlas.guard_person_rhythm_opportunity_feedback_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_evidence atlas.evidence_records%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_state_event atlas.person_life_state_events%rowtype;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_target jsonb;
  v_target_goal_id uuid;
begin
  if new.projection_state='satisfied' then
    if new.satisfied_by_evidence_id is null
       or new.satisfied_by_claim_id is null
       or new.satisfaction_event_id is null
       or new.satisfied_at is null then
      raise exception 'Satisfied person Rhythm opportunity requires canonical Evidence, Claim, state event, and satisfiedAt.'
        using errcode='23514';
    end if;

    select * into v_evidence
    from atlas.evidence_records e
    where e.id=new.satisfied_by_evidence_id
      and e.scope_kind='person'
      and e.scope_id=new.owner_user_id;
    if v_evidence.id is null then
      raise exception 'Rhythm satisfaction Evidence must belong to the opportunity owner.'
        using errcode='23514';
    end if;

    select * into v_claim
    from atlas.claim_records c
    where c.id=new.satisfied_by_claim_id
      and c.scope_kind='person'
      and c.scope_id=new.owner_user_id
      and c.primary_evidence_id=new.satisfied_by_evidence_id;
    if v_claim.id is null then
      raise exception 'Rhythm satisfaction Claim must be the same-person Claim backed by the satisfaction Evidence.'
        using errcode='23514';
    end if;

    select * into v_state_event
    from atlas.person_life_state_events e
    where e.id=new.satisfaction_event_id
      and e.owner_user_id=new.owner_user_id
      and e.definition_id=new.rhythm_definition_id
      and e.event_kind='rhythm_satisfaction';
    if v_state_event.id is null
       or v_state_event.occurred_at is distinct from new.satisfied_at
       or v_state_event.evidence->'source'->>'canonicalEvidenceId' is distinct from new.satisfied_by_evidence_id::text
       or v_state_event.evidence->'source'->>'canonicalClaimId' is distinct from new.satisfied_by_claim_id::text
       or v_state_event.evidence->'source'->>'opportunityId' is distinct from new.id::text then
      raise exception 'Rhythm opportunity satisfaction must exactly reproduce its person-life state event provenance.'
        using errcode='23514';
    end if;
  elsif new.satisfied_by_evidence_id is not null
     or new.satisfied_by_claim_id is not null
     or new.satisfaction_event_id is not null
     or new.satisfied_at is not null then
    raise exception 'Only a satisfied person Rhythm opportunity may carry satisfaction provenance.'
      using errcode='23514';
  end if;

  if new.presentation_state='base' then
    if new.presentation_overlay is distinct from '{}'::jsonb
       or new.presentation_consequence_instance_id is not null
       or new.presentation_consequence_event_id is not null
       or new.presentation_applied_at is not null then
      raise exception 'Base person Rhythm presentation cannot carry a consequence overlay or provenance.'
        using errcode='23514';
    end if;
  elsif new.presentation_state='adapted' then
    if jsonb_typeof(new.presentation_overlay)<>'object'
       or new.presentation_overlay='{}'::jsonb
       or new.presentation_consequence_instance_id is null
       or new.presentation_consequence_event_id is null
       or new.presentation_applied_at is null then
      raise exception 'Adapted person Rhythm presentation requires a non-empty overlay and consequence provenance.'
        using errcode='23514';
    end if;

    select * into v_instance
    from atlas.person_life_consequence_instances i
    where i.id=new.presentation_consequence_instance_id
      and i.owner_user_id=new.owner_user_id;
    if v_instance.id is null then
      raise exception 'Presentation Consequence instance must belong to the opportunity owner.'
        using errcode='23514';
    end if;

    select * into v_state_event
    from atlas.person_life_state_events e
    where e.id=new.presentation_consequence_event_id
      and e.owner_user_id=new.owner_user_id
      and e.definition_id=v_instance.definition_id
      and e.event_kind='consequence_evaluation';
    if v_state_event.id is null
       or not exists (
         select 1
         from jsonb_array_elements(coalesce(v_state_event.evaluation->'openConsequences','[]'::jsonb)) c(value)
         where c.value->>'stableKey'=v_instance.stable_key
       ) then
      raise exception 'Presentation overlay must cite a consequence_evaluation event that established this exact Consequence.'
        using errcode='23514';
    end if;

    if v_instance.action_spec->>'effectKind'<>'rhythm_opportunity_presentation_overlay'
       or jsonb_typeof(v_instance.action_spec->'presentationOverlay')<>'object'
       or v_instance.action_spec->'presentationOverlay' is distinct from new.presentation_overlay then
      raise exception 'Presentation overlay must exactly reproduce the authorized Consequence actionSpec.'
        using errcode='23514';
    end if;

    v_target := v_instance.action_spec->'target';
    if jsonb_typeof(v_target)<>'object'
       or v_target->>'kind'<>'goal_requirement_next_opportunity'
       or coalesce(v_target->>'goalDefinitionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or nullif(btrim(coalesce(v_target->>'goalRequirementKey','')),'') is null then
      raise exception 'Presentation Consequence requires an explicit goal_requirement_next_opportunity target.'
        using errcode='23514';
    end if;
    v_target_goal_id := (v_target->>'goalDefinitionId')::uuid;

    select * into v_binding
    from atlas.person_goal_rhythm_bindings b
    where b.id=new.binding_id
      and b.owner_user_id=new.owner_user_id;
    if v_binding.id is null
       or v_binding.goal_definition_id is distinct from v_target_goal_id
       or v_binding.goal_requirement_key is distinct from v_target->>'goalRequirementKey' then
      raise exception 'Presentation Consequence target must exactly match the opportunity Goal requirement binding.'
        using errcode='23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function atlas.guard_person_rhythm_opportunity_feedback_v1() is
  'Database custody guard for canonical occurrence satisfaction and authorized presentation-only Consequence overlays on person Rhythm opportunities.';

revoke all on function atlas.guard_person_rhythm_opportunity_feedback_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_rhythm_opportunity_feedback_v1() to service_role;

drop trigger if exists guard_person_rhythm_opportunity_feedback_v1
  on atlas.person_rhythm_opportunities;
create trigger guard_person_rhythm_opportunity_feedback_v1
before insert or update on atlas.person_rhythm_opportunities
for each row execute function atlas.guard_person_rhythm_opportunity_feedback_v1();

create or replace function atlas.record_person_rhythm_occurrence_api_v1(
  p_opportunity_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_opportunity atlas.person_rhythm_opportunities%rowtype;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_source_key text;
  v_storage_key text;
  v_observed_at timestamptz;
  v_metadata jsonb;
  v_value jsonb;
  v_goal_packet jsonb;
  v_requirement jsonb;
  v_selector jsonb;
  v_subject jsonb;
  v_claim_type text;
  v_evidence_kind text;
  v_existing_evidence_id uuid;
  v_capture jsonb;
  v_evidence_id uuid;
  v_claim_id uuid;
  v_satisfaction jsonb;
  v_satisfaction_event_id uuid;
  v_goal_evaluation jsonb;
  v_updated integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_opportunity_id is null then
    raise exception 'opportunityId is required.' using errcode='22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  select o.* into v_opportunity
  from atlas.person_rhythm_opportunities o
  join atlas.person_goal_rhythm_bindings b on b.id=o.binding_id
  join atlas.claim_records c on c.id=b.plan_claim_id
  where o.id=p_opportunity_id
    and o.owner_user_id=v_user_id
    and b.owner_user_id=v_user_id
    and b.status='active'
    and c.scope_kind='person'
    and c.scope_id=v_user_id
    and c.claim_type='goal_rhythm_plan'
    and c.lifecycle_state='accepted'
    and c.authority_kind in ('person_acceptance','person_correction')
    and (c.valid_from is null or c.valid_from<=now())
    and (c.valid_until is null or c.valid_until>now())
    and o.projection_state<>'withdrawn'
  for update of o;

  if v_opportunity.id is null then
    raise exception 'Current person Rhythm opportunity not found for this user.'
      using errcode='42501';
  end if;

  select * into v_binding
  from atlas.person_goal_rhythm_bindings b
  where b.id=v_opportunity.binding_id
    and b.owner_user_id=v_user_id
    and b.status='active';
  if v_binding.id is null then
    raise exception 'Active Goal Rhythm binding not found for this opportunity.'
      using errcode='23514';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key='' then
    raise exception 'sourceKey is required for idempotent Rhythm occurrence capture.'
      using errcode='22023';
  end if;
  if not (p_payload ? 'value') then
    raise exception 'value is required, including explicit JSON null when that is the observation.'
      using errcode='22023';
  end if;
  v_value := p_payload->'value';
  v_metadata := coalesce(p_payload->'metadata','{}'::jsonb);
  if jsonb_typeof(v_metadata)<>'object' then
    raise exception 'metadata must be an object.' using errcode='22023';
  end if;
  v_evidence_kind := coalesce(nullif(btrim(p_payload->>'evidenceKind'),''),'rhythm_occurrence_observation');
  v_storage_key := 'person_rhythm_occurrence:' || v_user_id::text || ':' || v_source_key;

  if nullif(p_payload->>'observedAt','') is not null then
    begin
      v_observed_at := (p_payload->>'observedAt')::timestamptz;
    exception when invalid_datetime_format or datetime_field_overflow then
      raise exception 'observedAt must be a timestamp with timezone.' using errcode='22023';
    end;
  else
    select e.observed_at into v_observed_at
    from atlas.evidence_records e
    where e.scope_kind='person'
      and e.scope_id=v_user_id
      and e.source_kind='person_capture'
      and e.source_key=v_storage_key;
    v_observed_at := coalesce(v_observed_at,now());
  end if;

  if v_observed_at>now()+interval '5 minutes' then
    raise exception 'A person Rhythm occurrence cannot be recorded as future execution.'
      using errcode='22023';
  end if;
  if v_observed_at<v_opportunity.starts_at or v_observed_at>v_opportunity.ends_at then
    raise exception 'observedAt must fall inside the selected accepted Rhythm opportunity window.'
      using errcode='22023';
  end if;

  if v_opportunity.projection_state not in ('projected','satisfied') then
    raise exception 'Only a current projected Rhythm opportunity can be satisfied by new Evidence.'
      using errcode='22023';
  end if;

  select d.engine_packet into v_goal_packet
  from atlas.person_life_definitions d
  where d.id=v_binding.goal_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='goal'
    and d.status='active';
  if v_goal_packet is null then
    raise exception 'Active linked Goal definition not found.'
      using errcode='23514';
  end if;

  select r.value into v_requirement
  from jsonb_array_elements(coalesce(v_goal_packet->'requirements','[]'::jsonb)) r(value)
  where coalesce(r.value->>'requirementKey',r.value->>'requirement_key')=v_binding.goal_requirement_key
  limit 1;
  if v_requirement is null
     or coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind')<>'claim_threshold' then
    raise exception 'Rhythm occurrence v1 requires the linked Goal requirement to be an evidence-backed claim_threshold.'
      using errcode='23514';
  end if;

  v_selector := v_requirement->'evidenceSelector';
  v_subject := v_selector->'subject';
  v_claim_type := nullif(btrim(coalesce(v_selector->>'claimType','')),'');
  if jsonb_typeof(v_selector)<>'object'
     or jsonb_typeof(v_subject)<>'object'
     or nullif(btrim(coalesce(v_subject->>'domain','')),'') is null
     or nullif(btrim(coalesce(v_subject->>'kind','')),'') is null
     or nullif(btrim(coalesce(v_subject->>'id','')),'') is null
     or v_claim_type is null
     or jsonb_typeof(v_selector->'lifecycleStates')<>'array'
     or jsonb_typeof(v_selector->'authorityKinds')<>'array' then
    raise exception 'Linked Goal requirement has an invalid Evidence selector.'
      using errcode='23514';
  end if;
  if not exists (
       select 1 from jsonb_array_elements_text(v_selector->'lifecycleStates') x(value)
       where x.value='observed'
     )
     or not exists (
       select 1 from jsonb_array_elements_text(v_selector->'authorityKinds') x(value)
       where x.value='person_reported_observation'
     ) then
    raise exception 'Linked Goal requirement does not authorize first-party observed occurrence Evidence.'
      using errcode='23514';
  end if;

  select e.id into v_existing_evidence_id
  from atlas.evidence_records e
  where e.scope_kind='person'
    and e.scope_id=v_user_id
    and e.source_kind='person_capture'
    and e.source_key=v_storage_key;

  if v_opportunity.projection_state='satisfied'
     and v_existing_evidence_id is distinct from v_opportunity.satisfied_by_evidence_id then
    raise exception 'This Rhythm opportunity is already satisfied by different canonical Evidence.'
      using errcode='23505';
  end if;

  v_capture := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey',v_storage_key,
    'subject',v_subject,
    'evidence',jsonb_build_object(
      'kind',v_evidence_kind,
      'value',v_value,
      'observedAt',v_observed_at,
      'provenance',jsonb_build_object(
        'adapter','atlas.record_person_rhythm_occurrence_api_v1',
        'opportunityId',v_opportunity.id,
        'bindingId',v_binding.id,
        'rhythmDefinitionId',v_binding.rhythm_definition_id,
        'goalDefinitionId',v_binding.goal_definition_id,
        'goalRequirementKey',v_binding.goal_requirement_key,
        'planClaimId',v_binding.plan_claim_id,
        'canonicalOwner','claim_evidence'
      ),
      'metadata',v_metadata || jsonb_build_object('captureSurface','person_rhythm_occurrence')
    ),
    'claim',jsonb_build_object(
      'claimType',v_claim_type,
      'lifecycleState','observed',
      'value',v_value,
      'validFrom',v_observed_at,
      'metadata',v_metadata || jsonb_build_object(
        'captureSurface','person_rhythm_occurrence',
        'opportunityId',v_opportunity.id
      )
    )
  ));
  v_evidence_id := (v_capture->>'evidenceId')::uuid;
  v_claim_id := (v_capture->>'claimId')::uuid;

  if v_opportunity.projection_state='satisfied' then
    if v_evidence_id is distinct from v_opportunity.satisfied_by_evidence_id
       or v_claim_id is distinct from v_opportunity.satisfied_by_claim_id then
      raise exception 'sourceKey replay does not match the Evidence that satisfied this Rhythm opportunity.'
        using errcode='23505';
    end if;
    v_goal_evaluation := atlas.evaluate_person_goal_from_claim_evidence_api_v1(
      v_binding.goal_definition_id,
      'person_rhythm_goal_evaluation:' || v_evidence_id::text
    );
    return jsonb_build_object(
      'ok',true,
      'replayed',true,
      'opportunityId',v_opportunity.id,
      'bindingId',v_binding.id,
      'rhythmDefinitionId',v_binding.rhythm_definition_id,
      'goalDefinitionId',v_binding.goal_definition_id,
      'goalRequirementKey',v_binding.goal_requirement_key,
      'evidenceId',v_evidence_id,
      'claimId',v_claim_id,
      'rhythmEventId',v_opportunity.satisfaction_event_id,
      'goalEvaluation',v_goal_evaluation,
      'truthBoundary',jsonb_build_object(
        'occurrenceOwnedByClaimEvidence',true,
        'sameEvidenceFeedsRhythmAndGoal',true,
        'goalDefinitionIsNotRewritten',true,
        'doesNotCreateTask',true,
        'doesNotCreateClockPlacement',true
      )
    );
  end if;

  v_satisfaction := atlas.record_person_life_state_api_v1(
    v_binding.rhythm_definition_id,
    jsonb_build_object(
      'sourceKey','person_rhythm_satisfaction:' || v_evidence_id::text,
      'eventKind','rhythm_satisfaction',
      'satisfiedAt',v_observed_at,
      'asOf',v_observed_at,
      'evidence',jsonb_build_object(
        'canonicalEvidenceId',v_evidence_id,
        'canonicalClaimId',v_claim_id,
        'opportunityId',v_opportunity.id,
        'bindingId',v_binding.id,
        'goalDefinitionId',v_binding.goal_definition_id,
        'goalRequirementKey',v_binding.goal_requirement_key,
        'planClaimId',v_binding.plan_claim_id
      )
    )
  );
  v_satisfaction_event_id := (v_satisfaction->>'eventId')::uuid;

  update atlas.person_rhythm_opportunities o
  set projection_state='satisfied',
      satisfied_by_evidence_id=v_evidence_id,
      satisfied_by_claim_id=v_claim_id,
      satisfaction_event_id=v_satisfaction_event_id,
      satisfied_at=v_observed_at,
      metadata=o.metadata || jsonb_build_object(
        'satisfactionAdapter','atlas.record_person_rhythm_occurrence_api_v1'
      ),
      updated_at=now()
  where o.id=v_opportunity.id
    and o.owner_user_id=v_user_id
    and o.projection_state='projected';
  get diagnostics v_updated=row_count;
  if v_updated<>1 then
    raise exception 'Rhythm opportunity changed while recording its Evidence.'
      using errcode='40001';
  end if;

  v_goal_evaluation := atlas.evaluate_person_goal_from_claim_evidence_api_v1(
    v_binding.goal_definition_id,
    'person_rhythm_goal_evaluation:' || v_evidence_id::text
  );

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'opportunityId',v_opportunity.id,
    'bindingId',v_binding.id,
    'rhythmDefinitionId',v_binding.rhythm_definition_id,
    'goalDefinitionId',v_binding.goal_definition_id,
    'goalRequirementKey',v_binding.goal_requirement_key,
    'evidenceId',v_evidence_id,
    'claimId',v_claim_id,
    'rhythmEventId',v_satisfaction_event_id,
    'rhythmEvaluation',v_satisfaction->'evaluation',
    'goalEvaluation',v_goal_evaluation,
    'truthBoundary',jsonb_build_object(
      'occurrenceOwnedByClaimEvidence',true,
      'sameEvidenceFeedsRhythmAndGoal',true,
      'opportunitySatisfactionIsEvidenceBacked',true,
      'goalDefinitionIsNotRewritten',true,
      'opportunityIsNotTask',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_person_rhythm_occurrence_api_v1(uuid,jsonb) is
  'Record first-party canonical Evidence for one current person Rhythm opportunity, satisfy that opportunity, and re-evaluate the linked Goal from the same Claim/Evidence graph.';

revoke all on function atlas.record_person_rhythm_occurrence_api_v1(uuid,jsonb) from public, anon;
grant execute on function atlas.record_person_rhythm_occurrence_api_v1(uuid,jsonb) to authenticated, service_role;

create or replace function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(
  p_consequence_instance_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_action_spec jsonb;
  v_target jsonb;
  v_overlay jsonb;
  v_goal_definition_id uuid;
  v_goal_requirement_key text;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_opportunity atlas.person_rhythm_opportunities%rowtype;
  v_existing atlas.person_rhythm_opportunities%rowtype;
  v_event_id uuid;
  v_event atlas.person_life_state_events%rowtype;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_consequence_instance_id is null then
    raise exception 'consequenceInstanceId is required.' using errcode='22023';
  end if;

  select * into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=v_user_id
    and i.status='open';
  if v_instance.id is null then
    raise exception 'Open person Consequence instance not found for this user.'
      using errcode='42501';
  end if;

  v_event_id := v_instance.last_seen_event_id;
  select * into v_event
  from atlas.person_life_state_events e
  where e.id=v_event_id
    and e.owner_user_id=v_user_id
    and e.definition_id=v_instance.definition_id
    and e.event_kind='consequence_evaluation';
  if v_event.id is null
     or not exists (
       select 1
       from jsonb_array_elements(coalesce(v_event.evaluation->'openConsequences','[]'::jsonb)) c(value)
       where c.value->>'stableKey'=v_instance.stable_key
     ) then
    raise exception 'Consequence instance lacks a current evidence-backed consequence_evaluation event.'
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.person_rhythm_opportunities o
  where o.owner_user_id=v_user_id
    and o.presentation_consequence_instance_id=v_instance.id
    and o.presentation_consequence_event_id=v_event_id
  order by o.presentation_applied_at desc nulls last,o.id
  limit 1;
  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,
      'replayed',true,
      'consequenceInstanceId',v_instance.id,
      'consequenceEventId',v_event_id,
      'opportunityId',v_existing.id,
      'bindingId',v_existing.binding_id,
      'rhythmDefinitionId',v_existing.rhythm_definition_id,
      'basePresentation',v_existing.base_presentation,
      'presentationOverlay',v_existing.presentation_overlay,
      'effectivePresentation',v_existing.base_presentation || v_existing.presentation_overlay,
      'truthBoundary',jsonb_build_object(
        'overlayComesOnlyFromAcceptedConsequencePolicy',true,
        'basePlanPresentationIsPreserved',true,
        'goalDefinitionIsNotRewritten',true,
        'doesNotCreateTask',true,
        'doesNotCreateClockPlacement',true
      )
    );
  end if;

  v_action_spec := v_instance.action_spec;
  v_target := v_action_spec->'target';
  v_overlay := v_action_spec->'presentationOverlay';

  if v_action_spec->>'effectKind'<>'rhythm_opportunity_presentation_overlay'
     or jsonb_typeof(v_target)<>'object'
     or v_target->>'kind'<>'goal_requirement_next_opportunity'
     or jsonb_typeof(v_overlay)<>'object'
     or v_overlay='{}'::jsonb then
    raise exception 'Consequence actionSpec is not an authorized non-empty Rhythm presentation overlay.'
      using errcode='23514';
  end if;
  if coalesce(v_target->>'goalDefinitionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Consequence presentation target goalDefinitionId must be a UUID.'
      using errcode='23514';
  end if;
  v_goal_definition_id := (v_target->>'goalDefinitionId')::uuid;
  v_goal_requirement_key := nullif(btrim(coalesce(v_target->>'goalRequirementKey','')),'');
  if v_goal_requirement_key is null then
    raise exception 'Consequence presentation target goalRequirementKey is required.'
      using errcode='23514';
  end if;

  select b.* into v_binding
  from atlas.person_goal_rhythm_bindings b
  join atlas.person_life_definitions g on g.id=b.goal_definition_id
  join atlas.person_life_definitions r on r.id=b.rhythm_definition_id
  join atlas.claim_records c on c.id=b.plan_claim_id
  where b.owner_user_id=v_user_id
    and b.goal_definition_id=v_goal_definition_id
    and b.goal_requirement_key=v_goal_requirement_key
    and b.status='active'
    and g.owner_user_id=v_user_id and g.signal_kind='goal' and g.status='active'
    and r.owner_user_id=v_user_id and r.signal_kind='rhythm' and r.status='active'
    and c.scope_kind='person' and c.scope_id=v_user_id
    and c.claim_type='goal_rhythm_plan'
    and c.lifecycle_state='accepted'
    and c.authority_kind in ('person_acceptance','person_correction')
    and (c.valid_from is null or c.valid_from<=now())
    and (c.valid_until is null or c.valid_until>now())
  limit 1;
  if v_binding.id is null then
    raise exception 'Consequence presentation target has no current accepted Goal Rhythm binding.'
      using errcode='23514';
  end if;

  perform atlas.materialize_person_rhythm_opportunities_v1(
    v_user_id,
    v_binding.id,
    null,
    null
  );

  update atlas.person_rhythm_opportunities o
  set projection_state='elapsed',updated_at=now()
  where o.owner_user_id=v_user_id
    and o.binding_id=v_binding.id
    and o.projection_state='projected'
    and o.ends_at<=now();

  select o.* into v_opportunity
  from atlas.person_rhythm_opportunities o
  where o.owner_user_id=v_user_id
    and o.binding_id=v_binding.id
    and o.projection_state='projected'
    and o.ends_at>now()
  order by o.starts_at,o.id
  limit 1
  for update;

  if v_opportunity.id is null then
    raise exception 'No current/future projected Rhythm opportunity exists inside the accepted plan horizon.'
      using errcode='22023';
  end if;
  if v_opportunity.presentation_state<>'base'
     or v_opportunity.presentation_overlay is distinct from '{}'::jsonb then
    raise exception 'The next Rhythm opportunity already has a presentation effect; v1 does not silently compose competing Consequences.'
      using errcode='23505';
  end if;

  update atlas.person_rhythm_opportunities o
  set presentation_state='adapted',
      presentation_overlay=v_overlay,
      presentation_consequence_instance_id=v_instance.id,
      presentation_consequence_event_id=v_event_id,
      presentation_applied_at=now(),
      metadata=o.metadata || jsonb_build_object(
        'presentationAdapter','atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1',
        'consequenceStableKey',v_instance.stable_key
      ),
      updated_at=now()
  where o.id=v_opportunity.id
    and o.owner_user_id=v_user_id
    and o.presentation_state='base'
    and o.presentation_overlay='{}'::jsonb
  returning * into v_opportunity;

  if v_opportunity.id is null then
    raise exception 'Next Rhythm opportunity changed while applying its authorized presentation overlay.'
      using errcode='40001';
  end if;

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'consequenceInstanceId',v_instance.id,
    'consequenceEventId',v_event_id,
    'opportunityId',v_opportunity.id,
    'bindingId',v_binding.id,
    'rhythmDefinitionId',v_binding.rhythm_definition_id,
    'goalDefinitionId',v_binding.goal_definition_id,
    'goalRequirementKey',v_binding.goal_requirement_key,
    'basePresentation',v_opportunity.base_presentation,
    'presentationOverlay',v_opportunity.presentation_overlay,
    'effectivePresentation',v_opportunity.base_presentation || v_opportunity.presentation_overlay,
    'truthBoundary',jsonb_build_object(
      'overlayComesOnlyFromAcceptedConsequencePolicy',true,
      'consequenceObservationAndRuleRemainSeparate',true,
      'basePlanPresentationIsPreserved',true,
      'goalDefinitionIsNotRewritten',true,
      'opportunityRemainsNotTask',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true,
      'doesNotInferDiagnosisOrTrainingRule',true
    )
  );
end;
$$;

comment on function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid) is
  'Apply one exact presentation-only effect from the current evidence-backed person Consequence evaluation to the next opportunity of the explicitly targeted current Goal requirement.';

revoke all on function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid) from public, anon;
grant execute on function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid) to authenticated, service_role;

create or replace function atlas.person_rhythm_opportunities_self_api_v1(
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_limit integer;
  v_rows jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_limit := greatest(1,least(coalesce(p_limit,100),500));

  select coalesce(jsonb_agg(x.row_data order by x.starts_at,x.id),'[]'::jsonb)
  into v_rows
  from (
    select o.starts_at,o.id,jsonb_build_object(
      'opportunityId',o.id,
      'bindingId',o.binding_id,
      'rhythmDefinitionId',o.rhythm_definition_id,
      'localDate',o.projected_for_local_date,
      'timezone',o.timezone,
      'startsAt',o.starts_at,
      'endsAt',o.ends_at,
      'projectionState',o.projection_state,
      'presentationState',o.presentation_state,
      'basePresentation',o.base_presentation,
      'presentationOverlay',o.presentation_overlay,
      'effectivePresentation',o.base_presentation || o.presentation_overlay,
      'planClaimId',o.source_plan_claim_id,
      'planEvidenceId',o.source_plan_evidence_id,
      'satisfaction',case when o.satisfied_by_evidence_id is null then null else jsonb_build_object(
        'evidenceId',o.satisfied_by_evidence_id,
        'claimId',o.satisfied_by_claim_id,
        'eventId',o.satisfaction_event_id,
        'satisfiedAt',o.satisfied_at
      ) end,
      'presentationProvenance',case when o.presentation_consequence_instance_id is null then null else jsonb_build_object(
        'consequenceInstanceId',o.presentation_consequence_instance_id,
        'consequenceEventId',o.presentation_consequence_event_id,
        'appliedAt',o.presentation_applied_at
      ) end
    ) as row_data
    from atlas.person_rhythm_opportunities o
    join atlas.person_goal_rhythm_bindings b on b.id=o.binding_id
    join atlas.claim_records c on c.id=b.plan_claim_id
    where o.owner_user_id=v_user_id
      and b.owner_user_id=v_user_id
      and b.status='active'
      and c.scope_kind='person'
      and c.scope_id=v_user_id
      and c.claim_type='goal_rhythm_plan'
      and c.lifecycle_state='accepted'
      and c.authority_kind in ('person_acceptance','person_correction')
      and (c.valid_from is null or c.valid_from<=now())
      and (c.valid_until is null or c.valid_until>now())
      and o.projection_state<>'withdrawn'
      and o.ends_at>=now()-interval '1 day'
    order by o.starts_at,o.id
    limit v_limit
  ) x;

  return jsonb_build_object(
    'ok',true,
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'opportunities',v_rows,
    'truthBoundary',jsonb_build_object(
      'readOnlyProjection',true,
      'onlyCurrentAcceptedPlanIsVisible',true,
      'supersededPlanHistoryIsPreservedButNotPresented',true,
      'satisfactionProvenanceIsCanonicalClaimEvidence',true,
      'presentationOverlayIsAuthorizedEffectNotBasePlanRewrite',true,
      'opportunityIsNotTask',true,
      'opportunityDoesNotProveExecutionUnlessSatisfiedEvidenceExists',true,
      'clockPriorityNotClaimed',true
    )
  );
end;
$$;

comment on function atlas.person_rhythm_opportunities_self_api_v1(integer) is
  'Read the signed-in person current Rhythm opportunities with canonical satisfaction provenance and exact authorized presentation overlays composed as effectivePresentation.';

revoke all on function atlas.person_rhythm_opportunities_self_api_v1(integer) from public, anon;
grant execute on function atlas.person_rhythm_opportunities_self_api_v1(integer) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
(
  'atlas.record_person_rhythm_occurrence_api_v1(uuid,jsonb)',
  'app_endpoint','verified','active',
  true,true,true,
  0,0,
  jsonb_build_object(
    'purpose','Capture canonical first-party occurrence Evidence for one current person Rhythm opportunity, satisfy it, and re-evaluate the linked Goal from the same Claim/Evidence graph.',
    'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); the current accepted Goal Rhythm binding supplies the Goal requirement and evidence selector. observedAt must be inside the selected accepted window. The endpoint does not create a Task or Clock placement.',
    'directSignedInEndpoint',true
  ),
  false
),
(
  'atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,true,
  0,0,
  jsonb_build_object(
    'purpose','Apply an exact presentation-only action from one evidence-backed open person Consequence to the next opportunity of its explicitly targeted current Goal requirement.',
    'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); the target and presentationOverlay must come verbatim from the accepted Consequence policy actionSpec. The base plan, Goal, Tasks, and Principal Clock are not rewritten.',
    'directSignedInEndpoint',true
  ),
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
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'purpose','Read the signed-in person current Rhythm opportunity projection, including canonical occurrence satisfaction provenance and exact authorized presentation overlays.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); only opportunities governed by a currently accepted active plan binding are presented. Effective presentation is basePresentation plus a separately proven presentationOverlay; no Task or Clock priority is created.',
      'directSignedInEndpoint',true
    ),
    reviewed_at=now()
where signature='atlas.person_rhythm_opportunities_self_api_v1(integer)';

commit;
