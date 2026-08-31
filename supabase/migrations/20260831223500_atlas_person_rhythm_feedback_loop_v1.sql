-- Atlas Person Rhythm feedback loop v1
--
-- Closes the person-owned 5K/body-observation orchestration seam without
-- creating a second scheduler. Canonical observed Claim/Evidence can satisfy
-- one projected Rhythm opportunity and immediately re-evaluate its linked Goal.
-- Separately, an already-authorized open Consequence may adapt the next
-- projected opportunity only when the accepted policy actionSpec explicitly
-- names the target Goal requirement and exact presentation overlay.
--
-- Truth boundaries:
--   * occurrence Evidence is not manufactured from the schedule;
--   * satisfying an opportunity is not a Task completion or Clock claim;
--   * Goal evaluation still resolves only from current canonical Claim/Evidence;
--   * body observation and consequence policy remain separate authorities;
--   * a Consequence cannot infer its own target or presentation change;
--   * adaptation preserves the accepted plan as base presentation.

begin;

alter table atlas.person_rhythm_opportunities
  add column satisfied_by_claim_id uuid references atlas.claim_records(id) on delete restrict,
  add column satisfied_by_evidence_id uuid references atlas.evidence_records(id) on delete restrict,
  add column satisfied_by_event_id uuid references atlas.person_life_state_events(id) on delete restrict,
  add column satisfied_at timestamptz;

alter table atlas.person_rhythm_opportunities
  add constraint person_rhythm_opportunities_satisfaction_custody_ck check (
    (projection_state='satisfied'
      and satisfied_by_claim_id is not null
      and satisfied_by_evidence_id is not null
      and satisfied_by_event_id is not null
      and satisfied_at is not null)
    or
    (projection_state<>'satisfied'
      and satisfied_by_claim_id is null
      and satisfied_by_evidence_id is null
      and satisfied_by_event_id is null
      and satisfied_at is null)
  );

create index person_rhythm_opportunities_satisfied_claim_idx
  on atlas.person_rhythm_opportunities(satisfied_by_claim_id)
  where satisfied_by_claim_id is not null;
create index person_rhythm_opportunities_satisfied_evidence_idx
  on atlas.person_rhythm_opportunities(satisfied_by_evidence_id)
  where satisfied_by_evidence_id is not null;
create index person_rhythm_opportunities_satisfied_event_idx
  on atlas.person_rhythm_opportunities(satisfied_by_event_id)
  where satisfied_by_event_id is not null;

create table atlas.person_rhythm_opportunity_adaptations (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  opportunity_id uuid not null references atlas.person_rhythm_opportunities(id) on delete cascade,
  consequence_instance_id uuid not null references atlas.person_life_consequence_instances(id) on delete restrict,
  consequence_event_id uuid not null references atlas.person_life_state_events(id) on delete restrict,
  source_key text not null check (btrim(source_key)<>''),
  action_key text,
  presentation_state text not null check (presentation_state in ('adapted','held')),
  presentation_overlay jsonb not null check (jsonb_typeof(presentation_overlay)='object'),
  applied_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (owner_user_id,source_key),
  unique (opportunity_id),
  unique (consequence_instance_id)
);

comment on table atlas.person_rhythm_opportunity_adaptations is
  'Append-only provenance for one authorized Consequence presentation adjustment applied to the next projected person Rhythm opportunity. v1 refuses silent multi-policy composition; conflicting adaptations require explicit future adjudication.';

create index person_rhythm_opportunity_adaptations_owner_time_idx
  on atlas.person_rhythm_opportunity_adaptations(owner_user_id,applied_at,id);
create index person_rhythm_opportunity_adaptations_consequence_event_idx
  on atlas.person_rhythm_opportunity_adaptations(consequence_event_id);

create or replace function atlas.guard_person_rhythm_opportunity_feedback_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_claim atlas.claim_records%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_event atlas.person_life_state_events%rowtype;
  v_adaptation atlas.person_rhythm_opportunity_adaptations%rowtype;
begin
  if new.projection_state='satisfied' then
    select * into v_claim
    from atlas.claim_records c
    where c.id=new.satisfied_by_claim_id
      and c.scope_kind='person'
      and c.scope_id=new.owner_user_id
      and c.lifecycle_state='observed'
      and c.authority_kind in ('person_reported_observation','person_correction');
    if v_claim.id is null
       or v_claim.primary_evidence_id is distinct from new.satisfied_by_evidence_id then
      raise exception 'Satisfied Rhythm opportunity requires a current same-person observed Claim backed by the recorded Evidence.' using errcode='23514';
    end if;

    select * into v_evidence
    from atlas.evidence_records e
    where e.id=new.satisfied_by_evidence_id
      and e.scope_kind='person'
      and e.scope_id=new.owner_user_id
      and e.subject_domain=v_claim.subject_domain
      and e.subject_kind=v_claim.subject_kind
      and e.subject_id=v_claim.subject_id;
    if v_evidence.id is null
       or v_evidence.observed_at is null
       or v_evidence.observed_at is distinct from new.satisfied_at then
      raise exception 'Satisfied Rhythm opportunity requires the exact canonical observed Evidence timestamp.' using errcode='23514';
    end if;

    select * into v_event
    from atlas.person_life_state_events e
    where e.id=new.satisfied_by_event_id
      and e.owner_user_id=new.owner_user_id
      and e.definition_id=new.rhythm_definition_id
      and e.event_kind='rhythm_satisfaction';
    if v_event.id is null
       or v_event.occurred_at is distinct from new.satisfied_at
       or v_event.evidence->'source'->>'evidenceId' is distinct from new.satisfied_by_evidence_id::text
       or v_event.evidence->'source'->>'claimId' is distinct from new.satisfied_by_claim_id::text
       or v_event.evidence->'source'->>'opportunityId' is distinct from new.id::text then
      raise exception 'Satisfied Rhythm opportunity must point to its exact canonical rhythm_satisfaction event.' using errcode='23514';
    end if;
  elsif new.satisfied_by_claim_id is not null
     or new.satisfied_by_evidence_id is not null
     or new.satisfied_by_event_id is not null
     or new.satisfied_at is not null then
    raise exception 'Only a satisfied Rhythm opportunity may carry satisfaction provenance.' using errcode='23514';
  end if;

  if new.presentation_state in ('adapted','held') then
    select * into v_adaptation
    from atlas.person_rhythm_opportunity_adaptations a
    where a.opportunity_id=new.id and a.owner_user_id=new.owner_user_id;
    if v_adaptation.id is null
       or v_adaptation.presentation_state is distinct from new.presentation_state
       or v_adaptation.presentation_overlay is distinct from new.presentation_overlay then
      raise exception 'Adapted/Held Rhythm presentation must exactly match its authorized adaptation provenance row.' using errcode='23514';
    end if;
  elsif new.presentation_state='base' and new.presentation_overlay<>'{}'::jsonb then
    raise exception 'Base Rhythm presentation cannot carry an adaptation overlay.' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_person_rhythm_opportunity_feedback_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_rhythm_opportunity_feedback_v1() to service_role;

create trigger person_rhythm_opportunities_feedback_guard_v1
before insert or update on atlas.person_rhythm_opportunities
for each row execute function atlas.guard_person_rhythm_opportunity_feedback_v1();

create or replace function atlas.guard_person_rhythm_opportunity_adaptation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_opportunity atlas.person_rhythm_opportunities%rowtype;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_event atlas.person_life_state_events%rowtype;
  v_action jsonb;
  v_target jsonb;
begin
  if tg_op='UPDATE' and new is distinct from old then
    raise exception 'Rhythm opportunity adaptation provenance is append-only.' using errcode='23514';
  end if;

  select * into v_opportunity
  from atlas.person_rhythm_opportunities o
  where o.id=new.opportunity_id and o.owner_user_id=new.owner_user_id;
  if v_opportunity.id is null or v_opportunity.projection_state<>'projected' then
    raise exception 'Rhythm adaptation requires this person projected opportunity.' using errcode='23514';
  end if;

  select * into v_binding
  from atlas.person_goal_rhythm_bindings b
  where b.id=v_opportunity.binding_id
    and b.owner_user_id=new.owner_user_id
    and b.status='active';
  if v_binding.id is null then
    raise exception 'Rhythm adaptation requires a current active Goal Rhythm binding.' using errcode='23514';
  end if;

  -- Revalidate the accepted plan rather than trusting the projection row alone.
  perform atlas.person_goal_rhythm_plan_envelope_v1(new.owner_user_id,v_binding.plan_claim_id);

  select * into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=new.consequence_instance_id
    and i.owner_user_id=new.owner_user_id
    and i.status='open';
  if v_instance.id is null then
    raise exception 'Rhythm adaptation requires this person open authorized Consequence instance.' using errcode='23514';
  end if;
  if v_instance.opened_by_event_id is distinct from new.consequence_event_id then
    raise exception 'Rhythm adaptation consequence event must be the event that opened the Consequence.' using errcode='23514';
  end if;

  select * into v_event
  from atlas.person_life_state_events e
  where e.id=new.consequence_event_id
    and e.owner_user_id=new.owner_user_id
    and e.event_kind='consequence_evaluation'
    and e.definition_id=v_instance.definition_id;
  if v_event.id is null then
    raise exception 'Rhythm adaptation requires canonical person Consequence evaluation provenance.' using errcode='23514';
  end if;

  v_action := v_instance.action_spec;
  v_target := v_action->'target';
  if jsonb_typeof(v_action)<>'object'
     or v_action->>'contractVersion'<>'rhythm_presentation_adjustment_v1'
     or v_action->>'applyTo'<>'next_projected_opportunity'
     or jsonb_typeof(v_target)<>'object'
     or v_target->>'goalDefinitionId' is distinct from v_binding.goal_definition_id::text
     or v_target->>'goalRequirementKey' is distinct from v_binding.goal_requirement_key
     or v_action->>'presentationState' not in ('adapted','held')
     or jsonb_typeof(v_action->'presentationOverlay')<>'object' then
    raise exception 'Consequence policy must explicitly authorize this Goal requirement next-opportunity presentation adjustment.' using errcode='23514';
  end if;

  if new.action_key is distinct from v_instance.action_key
     or new.presentation_state is distinct from v_action->>'presentationState'
     or new.presentation_overlay is distinct from v_action->'presentationOverlay' then
    raise exception 'Rhythm adaptation must exactly reproduce the authorized Consequence actionSpec.' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_person_rhythm_opportunity_adaptation_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_rhythm_opportunity_adaptation_v1() to service_role;

create trigger person_rhythm_opportunity_adaptations_guard_v1
before insert or update on atlas.person_rhythm_opportunity_adaptations
for each row execute function atlas.guard_person_rhythm_opportunity_adaptation_v1();

alter table atlas.person_rhythm_opportunity_adaptations enable row level security;
create policy person_rhythm_opportunity_adaptations_self_read
on atlas.person_rhythm_opportunity_adaptations for select to authenticated
using (owner_user_id=(select auth.uid()));

grant select on atlas.person_rhythm_opportunity_adaptations to authenticated;
grant select,insert,update,delete on atlas.person_rhythm_opportunity_adaptations to service_role;

create or replace function atlas.record_person_rhythm_occurrence_from_evidence_api_v1(
  p_opportunity_id uuid,
  p_evidence_id uuid,
  p_source_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_event_source_key text;
  v_goal_source_key text;
  v_opportunity atlas.person_rhythm_opportunities%rowtype;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_rhythm_subject jsonb;
  v_evidence atlas.evidence_records%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_satisfaction jsonb;
  v_goal_evaluation jsonb;
  v_event_id uuid;
  v_updated integer;
  v_replayed boolean := false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_opportunity_id is null or p_evidence_id is null then
    raise exception 'opportunityId and evidenceId are required.' using errcode='22023';
  end if;
  v_source_key:=btrim(coalesce(p_source_key,''));
  if v_source_key='' then raise exception 'sourceKey is required.' using errcode='22023'; end if;
  v_event_source_key:='person_rhythm_occurrence:'||v_source_key;
  v_goal_source_key:='person_goal_after_rhythm:'||v_source_key;

  select * into v_opportunity
  from atlas.person_rhythm_opportunities o
  where o.id=p_opportunity_id and o.owner_user_id=v_user_id
  for update;
  if v_opportunity.id is null then
    raise exception 'Person Rhythm opportunity not found.' using errcode='42501';
  end if;

  select * into v_binding
  from atlas.person_goal_rhythm_bindings b
  where b.id=v_opportunity.binding_id
    and b.owner_user_id=v_user_id
    and b.status='active';
  if v_binding.id is null then
    raise exception 'Rhythm occurrence requires a current active Goal Rhythm binding.' using errcode='23514';
  end if;
  perform atlas.person_goal_rhythm_plan_envelope_v1(v_user_id,v_binding.plan_claim_id);

  select d.life_signal->'subject' into v_rhythm_subject
  from atlas.person_life_definitions d
  where d.id=v_opportunity.rhythm_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='rhythm'
    and d.status='active';
  if jsonb_typeof(v_rhythm_subject)<>'object' then
    raise exception 'Current Rhythm definition subject is unavailable.' using errcode='23514';
  end if;

  select * into v_evidence
  from atlas.evidence_records e
  where e.id=p_evidence_id
    and e.scope_kind='person'
    and e.scope_id=v_user_id
    and e.subject_domain=v_rhythm_subject->>'domain'
    and e.subject_kind=v_rhythm_subject->>'kind'
    and e.subject_id=v_rhythm_subject->>'id';
  if v_evidence.id is null or v_evidence.observed_at is null then
    raise exception 'Rhythm occurrence requires same-person canonical observed Evidence for the Rhythm subject.' using errcode='23514';
  end if;
  if v_evidence.observed_at<v_opportunity.starts_at or v_evidence.observed_at>v_opportunity.ends_at then
    raise exception 'Observed Evidence timestamp must fall inside the selected Rhythm opportunity window.' using errcode='23514';
  end if;

  select * into v_claim
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=v_user_id
    and c.primary_evidence_id=v_evidence.id
    and c.subject_domain=v_evidence.subject_domain
    and c.subject_kind=v_evidence.subject_kind
    and c.subject_id=v_evidence.subject_id
    and c.lifecycle_state='observed'
    and c.authority_kind in ('person_reported_observation','person_correction')
  order by c.recorded_at desc,c.id desc
  limit 1;
  if v_claim.id is null then
    raise exception 'Rhythm occurrence Evidence must back a current observed person Claim.' using errcode='23514';
  end if;

  if v_opportunity.projection_state='satisfied' then
    if v_opportunity.satisfied_by_claim_id is distinct from v_claim.id
       or v_opportunity.satisfied_by_evidence_id is distinct from v_evidence.id
       or v_opportunity.satisfied_at is distinct from v_evidence.observed_at then
      raise exception 'Rhythm opportunity is already satisfied by different canonical Evidence.' using errcode='23505';
    end if;
    v_event_id:=v_opportunity.satisfied_by_event_id;
    v_replayed:=true;
  elsif v_opportunity.projection_state<>'projected' then
    raise exception 'Only a projected Rhythm opportunity can be satisfied.' using errcode='23514';
  else
    v_satisfaction:=atlas.record_person_life_state_api_v1(
      v_opportunity.rhythm_definition_id,
      jsonb_build_object(
        'sourceKey',v_event_source_key,
        'eventKind','rhythm_satisfaction',
        'satisfiedAt',v_evidence.observed_at,
        'asOf',greatest(v_evidence.observed_at,now()),
        'evidence',jsonb_build_object(
          'basis','canonical_observed_claim_evidence',
          'opportunityId',v_opportunity.id,
          'claimId',v_claim.id,
          'evidenceId',v_evidence.id,
          'claimType',v_claim.claim_type
        )
      )
    );
    v_event_id:=(v_satisfaction->>'eventId')::uuid;

    update atlas.person_rhythm_opportunities o
    set projection_state='satisfied',
        satisfied_by_claim_id=v_claim.id,
        satisfied_by_evidence_id=v_evidence.id,
        satisfied_by_event_id=v_event_id,
        satisfied_at=v_evidence.observed_at,
        metadata=o.metadata || jsonb_build_object(
          'satisfactionBasis','canonical_observed_claim_evidence',
          'satisfiedByClaimId',v_claim.id,
          'satisfiedByEvidenceId',v_evidence.id,
          'satisfiedByEventId',v_event_id
        ),
        updated_at=now()
    where o.id=v_opportunity.id and o.projection_state='projected';
    get diagnostics v_updated=row_count;
    if v_updated<>1 then raise exception 'Rhythm opportunity changed during satisfaction.' using errcode='40001'; end if;
  end if;

  v_goal_evaluation:=atlas.evaluate_person_goal_from_claim_evidence_api_v1(
    v_binding.goal_definition_id,
    v_goal_source_key
  );

  return jsonb_build_object(
    'ok',true,
    'replayed',v_replayed,
    'opportunityId',v_opportunity.id,
    'bindingId',v_binding.id,
    'rhythmDefinitionId',v_opportunity.rhythm_definition_id,
    'goalDefinitionId',v_binding.goal_definition_id,
    'goalRequirementKey',v_binding.goal_requirement_key,
    'claimId',v_claim.id,
    'evidenceId',v_evidence.id,
    'rhythmSatisfactionEventId',v_event_id,
    'satisfiedAt',v_evidence.observed_at,
    'goalEvaluation',v_goal_evaluation,
    'truthBoundary',jsonb_build_object(
      'occurrenceComesFromCanonicalObservedClaimEvidence',true,
      'evidenceMustMatchRhythmSubject',true,
      'evidenceMustFallInsideSelectedOpportunity',true,
      'opportunityDoesNotManufactureOccurrence',true,
      'goalReevaluationUsesCurrentClaimEvidence',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true,
      'doesNotCreateConsequence',true
    )
  );
end;
$$;

revoke all on function atlas.record_person_rhythm_occurrence_from_evidence_api_v1(uuid,uuid,text) from public, anon;
grant execute on function atlas.record_person_rhythm_occurrence_from_evidence_api_v1(uuid,uuid,text) to authenticated, service_role;

create or replace function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(
  p_consequence_instance_id uuid,
  p_source_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_action jsonb;
  v_target jsonb;
  v_goal_id uuid;
  v_goal_key text;
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_opportunity atlas.person_rhythm_opportunities%rowtype;
  v_existing atlas.person_rhythm_opportunity_adaptations%rowtype;
  v_adaptation_id uuid;
  v_replayed boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_consequence_instance_id is null then raise exception 'consequenceInstanceId is required.' using errcode='22023'; end if;
  v_source_key:=btrim(coalesce(p_source_key,''));
  if v_source_key='' then raise exception 'sourceKey is required.' using errcode='22023'; end if;

  select * into v_existing
  from atlas.person_rhythm_opportunity_adaptations a
  where a.owner_user_id=v_user_id and a.source_key=v_source_key;
  if v_existing.id is not null then
    if v_existing.consequence_instance_id is distinct from p_consequence_instance_id then
      raise exception 'sourceKey retry does not match existing Rhythm adaptation.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'replayed',true,'adaptationId',v_existing.id,
      'opportunityId',v_existing.opportunity_id,'consequenceInstanceId',v_existing.consequence_instance_id,
      'consequenceEventId',v_existing.consequence_event_id,
      'presentationState',v_existing.presentation_state,'presentationOverlay',v_existing.presentation_overlay
    );
  end if;

  select * into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=v_user_id
    and i.status='open'
  for update;
  if v_instance.id is null then
    raise exception 'Open person Consequence instance not found.' using errcode='42501';
  end if;

  v_action:=v_instance.action_spec;
  v_target:=v_action->'target';
  if jsonb_typeof(v_action)<>'object'
     or v_action->>'contractVersion'<>'rhythm_presentation_adjustment_v1'
     or v_action->>'applyTo'<>'next_projected_opportunity'
     or jsonb_typeof(v_target)<>'object'
     or coalesce(v_target->>'goalDefinitionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or nullif(btrim(coalesce(v_target->>'goalRequirementKey','')),'') is null
     or v_action->>'presentationState' not in ('adapted','held')
     or jsonb_typeof(v_action->'presentationOverlay')<>'object' then
    raise exception 'Consequence actionSpec does not explicitly authorize a next Rhythm presentation adjustment.' using errcode='23514';
  end if;
  v_goal_id:=(v_target->>'goalDefinitionId')::uuid;
  v_goal_key:=v_target->>'goalRequirementKey';

  select * into v_binding
  from atlas.person_goal_rhythm_bindings b
  where b.owner_user_id=v_user_id
    and b.goal_definition_id=v_goal_id
    and b.goal_requirement_key=v_goal_key
    and b.status='active'
  for update;
  if v_binding.id is null then
    raise exception 'Consequence target does not resolve to this person current Goal Rhythm binding.' using errcode='23514';
  end if;
  perform atlas.person_goal_rhythm_plan_envelope_v1(v_user_id,v_binding.plan_claim_id);

  select * into v_opportunity
  from atlas.person_rhythm_opportunities o
  where o.owner_user_id=v_user_id
    and o.binding_id=v_binding.id
    and o.projection_state='projected'
    and o.starts_at>=v_instance.opened_at
  order by o.starts_at,o.id
  limit 1
  for update;
  if v_opportunity.id is null then
    raise exception 'No projected Rhythm opportunity exists after this Consequence observation.' using errcode='22023';
  end if;

  if exists (
    select 1 from atlas.person_rhythm_opportunity_adaptations a
    where a.opportunity_id=v_opportunity.id
  ) then
    raise exception 'The next projected Rhythm opportunity already has an authorized adaptation; v1 will not silently compose competing policies.' using errcode='23514';
  end if;
  if exists (
    select 1 from atlas.person_rhythm_opportunity_adaptations a
    where a.consequence_instance_id=v_instance.id
  ) then
    raise exception 'This Consequence instance has already been applied to a Rhythm opportunity.' using errcode='23505';
  end if;

  insert into atlas.person_rhythm_opportunity_adaptations(
    owner_user_id,opportunity_id,consequence_instance_id,consequence_event_id,
    source_key,action_key,presentation_state,presentation_overlay,metadata
  ) values (
    v_user_id,v_opportunity.id,v_instance.id,v_instance.opened_by_event_id,
    v_source_key,v_instance.action_key,v_action->>'presentationState',v_action->'presentationOverlay',
    jsonb_build_object(
      'adapter','atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1',
      'policyClaimId',v_instance.evidence->>'policyClaimId',
      'observationEvidenceId',v_instance.evidence->>'evidenceId',
      'basePlanClaimId',v_binding.plan_claim_id
    )
  ) returning id into v_adaptation_id;

  update atlas.person_rhythm_opportunities o
  set presentation_state=v_action->>'presentationState',
      presentation_overlay=v_action->'presentationOverlay',
      metadata=o.metadata || jsonb_build_object(
        'adaptationId',v_adaptation_id,
        'adaptedByConsequenceInstanceId',v_instance.id,
        'adaptedByConsequenceEventId',v_instance.opened_by_event_id,
        'adaptationAuthority','accepted_consequence_policy'
      ),
      updated_at=now()
  where o.id=v_opportunity.id;

  return jsonb_build_object(
    'ok',true,
    'replayed',v_replayed,
    'adaptationId',v_adaptation_id,
    'opportunityId',v_opportunity.id,
    'bindingId',v_binding.id,
    'goalDefinitionId',v_binding.goal_definition_id,
    'goalRequirementKey',v_binding.goal_requirement_key,
    'consequenceInstanceId',v_instance.id,
    'consequenceEventId',v_instance.opened_by_event_id,
    'presentationState',v_action->>'presentationState',
    'basePresentation',v_opportunity.base_presentation,
    'presentationOverlay',v_action->'presentationOverlay',
    'effectivePresentation',v_opportunity.base_presentation || (v_action->'presentationOverlay'),
    'truthBoundary',jsonb_build_object(
      'consequenceMustAlreadyBeAuthorizedByAcceptedPolicy',true,
      'targetGoalRequirementComesFromPolicyActionSpec',true,
      'nextOpportunitySelectionIsTemporalNotDiagnostic',true,
      'baseAcceptedPlanIsPreserved',true,
      'conflictingAdaptationsAreRejectedNotMerged',true,
      'goalDefinitionIsNotRewritten',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

revoke all on function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid,text) from public, anon;
grant execute on function atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid,text) to authenticated, service_role;

create or replace function atlas.person_rhythm_opportunities_self_api_v1(p_limit integer default 100)
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
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_limit:=greatest(1,least(coalesce(p_limit,100),500));

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
      'effectivePresentation',case
        when o.presentation_state in ('adapted','held') then o.base_presentation || o.presentation_overlay
        else o.base_presentation
      end,
      'planClaimId',o.source_plan_claim_id,
      'planEvidenceId',o.source_plan_evidence_id,
      'feedback',jsonb_strip_nulls(jsonb_build_object(
        'satisfiedByClaimId',o.satisfied_by_claim_id,
        'satisfiedByEvidenceId',o.satisfied_by_evidence_id,
        'satisfiedByEventId',o.satisfied_by_event_id,
        'satisfiedAt',o.satisfied_at,
        'adaptationId',a.id,
        'adaptedByConsequenceInstanceId',a.consequence_instance_id,
        'adaptedByConsequenceEventId',a.consequence_event_id,
        'adaptationActionKey',a.action_key
      ))
    ) as row_data
    from atlas.person_rhythm_opportunities o
    join atlas.person_goal_rhythm_bindings b on b.id=o.binding_id
    join atlas.claim_records c on c.id=b.plan_claim_id
    left join atlas.person_rhythm_opportunity_adaptations a on a.opportunity_id=o.id
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
      'satisfactionCarriesCanonicalEvidenceProvenance',true,
      'adaptationCarriesAuthorizedConsequenceProvenance',true,
      'basePlanPresentationIsPreserved',true,
      'opportunityIsNotTask',true,
      'clockPriorityNotClaimed',true
    )
  );
end;
$$;

revoke all on function atlas.person_rhythm_opportunities_self_api_v1(integer) from public, anon;
grant execute on function atlas.person_rhythm_opportunities_self_api_v1(integer) to authenticated, service_role;

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'purpose','Record canonical observed Claim/Evidence as satisfaction of one selected person Rhythm opportunity and immediately re-evaluate its linked Goal.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); Evidence must belong to the person, match the active Rhythm subject, back a current observed Claim, and occur inside the selected accepted-plan opportunity. No Task, Consequence, or Clock placement is created.',
      'directSignedInEndpoint',true
    ),
    reviewed_at=now()
where signature='atlas.record_person_rhythm_occurrence_from_evidence_api_v1(uuid, uuid, text)';

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'purpose','Apply one already-authorized open person Consequence to the next projected Rhythm opportunity for the exact Goal requirement named by its policy actionSpec.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); target, presentation state, and overlay must come verbatim from the persisted authorized Consequence actionSpec. Base plan remains unchanged; v1 rejects competing adaptation composition; no Task or Clock placement is created.',
      'directSignedInEndpoint',true
    ),
    reviewed_at=now()
where signature='atlas.apply_person_consequence_to_next_rhythm_opportunity_api_v1(uuid, text)';

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'purpose','Read the signed-in person current Rhythm opportunities with canonical satisfaction and authorized adaptation provenance.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); only opportunities governed by a currently accepted active plan binding are presented. Base accepted-plan presentation remains visible beside any authorized overlay.',
      'directSignedInEndpoint',true
    ),
    reviewed_at=now()
where signature='atlas.person_rhythm_opportunities_self_api_v1(integer)';

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after person Rhythm feedback loop installation.';
  end if;
end
$$;

commit;
