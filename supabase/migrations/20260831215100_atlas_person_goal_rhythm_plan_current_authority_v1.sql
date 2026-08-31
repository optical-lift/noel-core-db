-- Atlas Person Goal -> Rhythm current-plan authority v1
--
-- Tightens the initial Goal/Rhythm bridge before release: an accepted plan must
-- be current, accepted corrections are valid person authority, and only one
-- active plan may govern a Goal requirement. Replacing a plan requires explicit
-- Claim supersession; the previous Rhythm is retired and future opportunities
-- are withdrawn without erasing history.

begin;

alter table atlas.person_goal_rhythm_bindings
  add column retired_by_plan_claim_id uuid references atlas.claim_records(id) on delete restrict;

alter table atlas.person_goal_rhythm_bindings
  add constraint person_goal_rhythm_bindings_lifecycle_ck check (
    (status='active' and retired_at is null and retired_by_plan_claim_id is null)
    or
    (status='retired' and retired_at is not null and retired_by_plan_claim_id is not null)
  );

create unique index person_goal_rhythm_bindings_one_active_requirement_idx
  on atlas.person_goal_rhythm_bindings(owner_user_id,goal_definition_id,goal_requirement_key)
  where status='active';

create or replace function atlas.person_goal_rhythm_plan_envelope_v1(
  p_owner_user_id uuid,
  p_plan_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_claim atlas.claim_records%rowtype;
  v_prior_claim atlas.claim_records%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_plan jsonb;
  v_goal_id uuid;
  v_goal_key text;
  v_goal_kind text;
  v_goal_owner uuid;
  v_goal_status text;
  v_goal_packet jsonb;
  v_rhythm jsonb;
  v_opportunity jsonb;
  v_timezone text;
  v_weekday jsonb;
  v_start_time time;
  v_window_minutes integer;
  v_horizon integer;
begin
  select * into v_claim
  from atlas.claim_records c
  where c.id=p_plan_claim_id
    and c.scope_kind='person'
    and c.scope_id=p_owner_user_id;

  if v_claim.id is null then
    raise exception 'Goal Rhythm plan Claim must belong to this person.' using errcode='42501';
  end if;
  if v_claim.claim_type<>'goal_rhythm_plan'
     or v_claim.lifecycle_state<>'accepted'
     or v_claim.authority_kind not in ('person_acceptance','person_correction') then
    raise exception 'Goal Rhythm plan requires a current person-accepted goal_rhythm_plan Claim.' using errcode='23514';
  end if;
  if (v_claim.valid_from is not null and v_claim.valid_from>now())
     or (v_claim.valid_until is not null and v_claim.valid_until<=now()) then
    raise exception 'Goal Rhythm plan Claim is outside its accepted validity window.' using errcode='23514';
  end if;

  select * into v_evidence
  from atlas.evidence_records e
  where e.id=v_claim.primary_evidence_id
    and e.scope_kind='person'
    and e.scope_id=p_owner_user_id;
  if v_evidence.id is null or v_evidence.evidence_kind<>'goal_rhythm_plan_basis' then
    raise exception 'Goal Rhythm plan requires same-person goal_rhythm_plan_basis Evidence.' using errcode='23514';
  end if;

  v_plan := v_claim.value;
  if jsonb_typeof(v_plan)<>'object'
     or v_plan->>'contractVersion'<>'goal_rhythm_plan_v1' then
    raise exception 'goal_rhythm_plan_v1 Claim value is required.' using errcode='22023';
  end if;

  begin
    v_goal_id := nullif(v_plan->>'goalDefinitionId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'goalDefinitionId must be a UUID.' using errcode='22023';
  end;
  v_goal_key := nullif(btrim(coalesce(v_plan->>'goalRequirementKey','')),'');
  if v_goal_id is null or v_goal_key is null then
    raise exception 'goalDefinitionId and goalRequirementKey are required.' using errcode='22023';
  end if;

  if v_claim.authority_kind='person_correction' then
    if v_claim.supersedes_claim_id is null then
      raise exception 'Corrected Goal Rhythm plan must identify the plan Claim it supersedes.' using errcode='23514';
    end if;
    select * into v_prior_claim
    from atlas.claim_records c
    where c.id=v_claim.supersedes_claim_id
      and c.scope_kind='person'
      and c.scope_id=p_owner_user_id
      and c.claim_type='goal_rhythm_plan';
    if v_prior_claim.id is null
       or v_prior_claim.value->>'contractVersion'<>'goal_rhythm_plan_v1'
       or v_prior_claim.value->>'goalDefinitionId' is distinct from v_plan->>'goalDefinitionId'
       or v_prior_claim.value->>'goalRequirementKey' is distinct from v_goal_key then
      raise exception 'A Goal Rhythm plan correction must supersede a plan for the same Goal requirement.' using errcode='23514';
    end if;
  end if;

  select d.owner_user_id,d.signal_kind,d.status,d.engine_packet
  into v_goal_owner,v_goal_kind,v_goal_status,v_goal_packet
  from atlas.person_life_definitions d
  where d.id=v_goal_id;
  if v_goal_owner is null
     or v_goal_owner is distinct from p_owner_user_id
     or v_goal_kind<>'goal'
     or v_goal_status<>'active' then
    raise exception 'Goal Rhythm plan must target this person active Goal definition.' using errcode='23514';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_goal_packet->'requirements','[]'::jsonb)) r
    where coalesce(r->>'requirementKey',r->>'requirement_key')=v_goal_key
  ) then
    raise exception 'goalRequirementKey must identify an explicit requirement of the active Goal.' using errcode='23514';
  end if;

  v_rhythm := v_plan->'rhythm';
  if jsonb_typeof(v_rhythm)<>'object'
     or nullif(btrim(coalesce(v_rhythm->>'sourceKey','')),'') is null
     or jsonb_typeof(v_rhythm->'subject')<>'object'
     or nullif(btrim(coalesce(v_rhythm->'subject'->>'domain','')),'') is null
     or nullif(btrim(coalesce(v_rhythm->'subject'->>'kind','')),'') is null
     or nullif(btrim(coalesce(v_rhythm->'subject'->>'id','')),'') is null
     or jsonb_typeof(v_rhythm->'state')<>'object'
     or jsonb_typeof(v_rhythm->'timing')<>'object'
     or jsonb_typeof(coalesce(v_rhythm->'requirements','[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(v_rhythm->'constraints','[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(v_rhythm->'ambiguities','[]'::jsonb))<>'array' then
    raise exception 'Goal Rhythm plan rhythm requires sourceKey, subject, state, timing, and array requirements/constraints/ambiguities.' using errcode='22023';
  end if;
  if v_rhythm->'state'->>'rhythmModel'<>'lease' then
    raise exception 'Goal Rhythm plan v1 supports only explicit lease Rhythm strategy.' using errcode='22023';
  end if;

  v_opportunity := v_plan->'opportunityPlan';
  if jsonb_typeof(v_opportunity)<>'object'
     or v_opportunity->>'strategy'<>'weekly_local_windows_v1' then
    raise exception 'Goal Rhythm plan v1 requires opportunityPlan.strategy=weekly_local_windows_v1.' using errcode='22023';
  end if;

  v_timezone := nullif(btrim(coalesce(v_opportunity->>'timezone','')),'');
  if v_timezone is null or not exists (select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'opportunityPlan.timezone must be a recognized PostgreSQL timezone.' using errcode='22023';
  end if;
  if jsonb_typeof(v_opportunity->'weekdays')<>'array'
     or jsonb_array_length(v_opportunity->'weekdays')=0 then
    raise exception 'opportunityPlan.weekdays must be a non-empty ISO weekday array.' using errcode='22023';
  end if;
  for v_weekday in select value from jsonb_array_elements(v_opportunity->'weekdays') loop
    if jsonb_typeof(v_weekday)<>'number'
       or (v_weekday#>>'{}')::integer not between 1 and 7 then
      raise exception 'opportunityPlan.weekdays values must be ISO integers 1..7.' using errcode='22023';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(v_opportunity->'weekdays')) <>
     (select count(distinct (value#>>'{}')::integer) from jsonb_array_elements(v_opportunity->'weekdays')) then
    raise exception 'opportunityPlan.weekdays cannot contain duplicates.' using errcode='22023';
  end if;

  if coalesce(v_opportunity->>'localStartTime','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'opportunityPlan.localStartTime must be HH:MM.' using errcode='22023';
  end if;
  v_start_time := (v_opportunity->>'localStartTime')::time;
  begin
    v_window_minutes := (v_opportunity->>'windowMinutes')::integer;
    v_horizon := (v_opportunity->>'materializationHorizonDays')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'windowMinutes and materializationHorizonDays must be integers.' using errcode='22023';
  end;
  if v_window_minutes not between 1 and 1440 then
    raise exception 'opportunityPlan.windowMinutes must be between 1 and 1440.' using errcode='22023';
  end if;
  if v_horizon not between 1 and 42 then
    raise exception 'opportunityPlan.materializationHorizonDays must be between 1 and 42.' using errcode='22023';
  end if;
  if v_opportunity ? 'presentation' and jsonb_typeof(v_opportunity->'presentation')<>'object' then
    raise exception 'opportunityPlan.presentation must be an object when supplied.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'plan',v_plan,
    'planClaimId',v_claim.id,
    'planEvidenceId',v_evidence.id,
    'supersedesPlanClaimId',v_claim.supersedes_claim_id,
    'goalDefinitionId',v_goal_id,
    'goalRequirementKey',v_goal_key,
    'rhythm',v_rhythm,
    'opportunityPlan',v_opportunity
  );
end;
$$;

comment on function atlas.person_goal_rhythm_plan_envelope_v1(uuid,uuid) is
  'Internal resolver for a current person-accepted Goal Rhythm plan. Accepted corrections are valid only when they supersede a plan for the same Goal requirement.';

create or replace function atlas.guard_person_goal_rhythm_binding_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_envelope jsonb;
  v_goal_owner uuid;
  v_goal_kind text;
  v_goal_status text;
  v_rhythm_owner uuid;
  v_rhythm_kind text;
  v_rhythm_status text;
  v_rhythm_signal jsonb;
  v_rhythm_source_domain text;
  v_rhythm_source_kind text;
  v_rhythm_source_id text;
  v_expected_signal jsonb;
begin
  if tg_op='UPDATE' and old.status='active' and new.status='retired' then
    if new.owner_user_id is distinct from old.owner_user_id
       or new.goal_definition_id is distinct from old.goal_definition_id
       or new.goal_requirement_key is distinct from old.goal_requirement_key
       or new.rhythm_definition_id is distinct from old.rhythm_definition_id
       or new.plan_claim_id is distinct from old.plan_claim_id
       or new.plan_evidence_id is distinct from old.plan_evidence_id
       or new.opportunity_plan is distinct from old.opportunity_plan
       or new.created_at is distinct from old.created_at
       or new.retired_at is null
       or new.retired_by_plan_claim_id is null then
      raise exception 'Goal Rhythm binding retirement may not rewrite its historical custody.' using errcode='23514';
    end if;

    v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(new.owner_user_id,new.retired_by_plan_claim_id);
    if nullif(v_envelope->>'supersedesPlanClaimId','')::uuid is distinct from old.plan_claim_id
       or (v_envelope->>'goalDefinitionId')::uuid is distinct from old.goal_definition_id
       or v_envelope->>'goalRequirementKey' is distinct from old.goal_requirement_key then
      raise exception 'Goal Rhythm binding retirement requires a current replacement plan that directly supersedes it.' using errcode='23514';
    end if;
    return new;
  end if;

  if tg_op='UPDATE' and old.status='retired' then
    if new is distinct from old then
      raise exception 'Retired Goal Rhythm bindings are historical and immutable.' using errcode='23514';
    end if;
    return new;
  end if;

  if new.status<>'active' or new.retired_at is not null or new.retired_by_plan_claim_id is not null then
    raise exception 'A Goal Rhythm binding begins active; retirement requires explicit replacement authority.' using errcode='23514';
  end if;

  v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(new.owner_user_id,new.plan_claim_id);

  if (v_envelope->>'planEvidenceId')::uuid is distinct from new.plan_evidence_id
     or (v_envelope->>'goalDefinitionId')::uuid is distinct from new.goal_definition_id
     or v_envelope->>'goalRequirementKey' is distinct from new.goal_requirement_key
     or v_envelope->'opportunityPlan' is distinct from new.opportunity_plan then
    raise exception 'Goal Rhythm binding must exactly reproduce its accepted plan Claim.' using errcode='23514';
  end if;

  select d.owner_user_id,d.signal_kind,d.status
  into v_goal_owner,v_goal_kind,v_goal_status
  from atlas.person_life_definitions d where d.id=new.goal_definition_id;
  select d.owner_user_id,d.signal_kind,d.status,d.life_signal,d.source_domain,d.source_kind,d.source_id
  into v_rhythm_owner,v_rhythm_kind,v_rhythm_status,v_rhythm_signal,v_rhythm_source_domain,v_rhythm_source_kind,v_rhythm_source_id
  from atlas.person_life_definitions d where d.id=new.rhythm_definition_id;

  if v_goal_owner is distinct from new.owner_user_id or v_goal_kind<>'goal' or v_goal_status<>'active'
     or v_rhythm_owner is distinct from new.owner_user_id or v_rhythm_kind<>'rhythm' or v_rhythm_status<>'active' then
    raise exception 'Goal Rhythm binding requires same-owner active Goal and Rhythm definitions.' using errcode='23514';
  end if;
  if v_rhythm_source_domain<>'claim_evidence'
     or v_rhythm_source_kind<>'claim'
     or v_rhythm_source_id is distinct from new.plan_claim_id::text then
    raise exception 'Bound Rhythm must be sourced by the exact accepted goal_rhythm_plan Claim.' using errcode='23514';
  end if;

  v_expected_signal := atlas.build_person_goal_rhythm_signal_v1(new.owner_user_id,new.plan_claim_id);
  if v_rhythm_signal is distinct from v_expected_signal then
    raise exception 'Bound Rhythm Life Signal must be database-compiled from the accepted goal_rhythm_plan Claim.' using errcode='23514';
  end if;
  return new;
end;
$$;

create or replace function atlas.guard_person_rhythm_opportunity_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_envelope jsonb;
  v_plan jsonb;
  v_timezone text;
  v_local_start time;
  v_window_minutes integer;
  v_local_date date;
  v_local_time time;
  v_isodow integer;
  v_base jsonb;
begin
  select * into v_binding from atlas.person_goal_rhythm_bindings b where b.id=new.binding_id;
  if v_binding.id is null
     or v_binding.owner_user_id is distinct from new.owner_user_id
     or v_binding.rhythm_definition_id is distinct from new.rhythm_definition_id
     or v_binding.plan_claim_id is distinct from new.source_plan_claim_id
     or v_binding.plan_evidence_id is distinct from new.source_plan_evidence_id then
    raise exception 'Rhythm opportunity custody must match its Goal Rhythm binding.' using errcode='23514';
  end if;

  if tg_op='UPDATE' and old.projection_state<>'withdrawn' and new.projection_state='withdrawn' then
    if v_binding.status<>'retired'
       or v_binding.retired_by_plan_claim_id is null
       or new.presentation_state<>'withdrawn'
       or new.owner_user_id is distinct from old.owner_user_id
       or new.binding_id is distinct from old.binding_id
       or new.rhythm_definition_id is distinct from old.rhythm_definition_id
       or new.opportunity_key is distinct from old.opportunity_key
       or new.projected_for_local_date is distinct from old.projected_for_local_date
       or new.timezone is distinct from old.timezone
       or new.starts_at is distinct from old.starts_at
       or new.ends_at is distinct from old.ends_at
       or new.base_presentation is distinct from old.base_presentation
       or new.source_plan_claim_id is distinct from old.source_plan_claim_id
       or new.source_plan_evidence_id is distinct from old.source_plan_evidence_id
       or new.created_at is distinct from old.created_at
       or new.presentation_overlay->>'withdrawnByPlanClaimId' is distinct from v_binding.retired_by_plan_claim_id::text then
      raise exception 'Rhythm opportunity withdrawal must preserve history and cite the replacement plan Claim.' using errcode='23514';
    end if;
    return new;
  end if;

  if tg_op='UPDATE' and old.projection_state='withdrawn' and new is distinct from old then
    raise exception 'Withdrawn Rhythm opportunities are historical and may not be resurrected.' using errcode='23514';
  end if;

  if v_binding.status<>'active' then
    raise exception 'Current Rhythm opportunities require an active Goal Rhythm binding.' using errcode='23514';
  end if;

  v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(new.owner_user_id,v_binding.plan_claim_id);
  v_plan := v_envelope->'opportunityPlan';
  v_timezone := v_plan->>'timezone';
  v_local_start := (v_plan->>'localStartTime')::time;
  v_window_minutes := (v_plan->>'windowMinutes')::integer;
  v_base := coalesce(v_plan->'presentation',jsonb_build_object('kind','rhythm_opportunity'));

  if new.timezone is distinct from v_timezone then
    raise exception 'Rhythm opportunity timezone must come from the accepted plan.' using errcode='23514';
  end if;
  v_local_date := (new.starts_at at time zone v_timezone)::date;
  v_local_time := (new.starts_at at time zone v_timezone)::time;
  v_isodow := extract(isodow from v_local_date)::integer;
  if new.projected_for_local_date is distinct from v_local_date
     or v_local_time is distinct from v_local_start
     or not exists (
       select 1 from jsonb_array_elements(v_plan->'weekdays') w
       where (w#>>'{}')::integer=v_isodow
     )
     or new.ends_at is distinct from new.starts_at + make_interval(mins=>v_window_minutes)
     or new.base_presentation is distinct from v_base then
    raise exception 'Rhythm opportunity window/base presentation must exactly follow the accepted weekly plan.' using errcode='23514';
  end if;
  return new;
end;
$$;

create or replace function atlas.activate_person_goal_rhythm_plan_api_v1(p_plan_claim_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_envelope jsonb;
  v_rhythm jsonb;
  v_signal jsonb;
  v_definition_receipt jsonb;
  v_rhythm_definition_id uuid;
  v_binding_id uuid;
  v_existing atlas.person_goal_rhythm_bindings%rowtype;
  v_previous atlas.person_goal_rhythm_bindings%rowtype;
  v_previous_source_key text;
  v_retired_binding_id uuid;
  v_materialization jsonb;
  v_start_date date;
  v_timezone text;
  v_supersedes_claim_id uuid;
  v_updated integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(v_user_id,p_plan_claim_id);
  v_rhythm := v_envelope->'rhythm';
  v_signal := atlas.build_person_goal_rhythm_signal_v1(v_user_id,p_plan_claim_id);
  v_supersedes_claim_id := nullif(v_envelope->>'supersedesPlanClaimId','')::uuid;

  select * into v_previous
  from atlas.person_goal_rhythm_bindings b
  where b.owner_user_id=v_user_id
    and b.goal_definition_id=(v_envelope->>'goalDefinitionId')::uuid
    and b.goal_requirement_key=v_envelope->>'goalRequirementKey'
    and b.status='active'
    and b.plan_claim_id<>p_plan_claim_id
  for update;

  if v_previous.id is not null then
    if v_supersedes_claim_id is distinct from v_previous.plan_claim_id then
      raise exception 'Replacing the active Goal Rhythm plan requires a Claim that directly supersedes it.' using errcode='23514';
    end if;
    select d.source_key into v_previous_source_key
    from atlas.person_life_definitions d
    where d.id=v_previous.rhythm_definition_id;
    if v_previous_source_key is not distinct from v_rhythm->>'sourceKey' then
      raise exception 'A replacement Goal Rhythm plan must use a new rhythm.sourceKey so historical Rhythm identity remains immutable.' using errcode='23514';
    end if;
  end if;

  v_definition_receipt := atlas.create_person_life_definition_api_v1(jsonb_build_object(
    'sourceKey',v_rhythm->>'sourceKey',
    'signal',v_signal,
    'metadata',jsonb_build_object(
      'goalDefinitionId',v_envelope->>'goalDefinitionId',
      'goalRequirementKey',v_envelope->>'goalRequirementKey',
      'planClaimId',p_plan_claim_id,
      'compiledFromGoalRhythmPlan',true
    )
  ));
  v_rhythm_definition_id := (v_definition_receipt->>'definitionId')::uuid;

  if v_previous.id is not null then
    update atlas.person_goal_rhythm_bindings b
    set status='retired',
        retired_at=now(),
        retired_by_plan_claim_id=p_plan_claim_id,
        metadata=b.metadata || jsonb_build_object(
          'retiredByPlanClaimId',p_plan_claim_id,
          'retirementReason','explicit_plan_supersession'
        )
    where b.id=v_previous.id and b.status='active';
    get diagnostics v_updated=row_count;
    if v_updated<>1 then
      raise exception 'Active Goal Rhythm binding changed during replacement.' using errcode='40001';
    end if;
    v_retired_binding_id := v_previous.id;

    update atlas.person_life_definitions d
    set status='retired',
        retired_at=now(),
        metadata=d.metadata || jsonb_build_object(
          'retiredByPlanClaimId',p_plan_claim_id,
          'retirementReason','explicit_plan_supersession'
        )
    where d.id=v_previous.rhythm_definition_id
      and d.owner_user_id=v_user_id
      and d.signal_kind='rhythm'
      and d.status='active';
    get diagnostics v_updated=row_count;
    if v_updated<>1 then
      raise exception 'Prior Rhythm definition could not be retired exactly once.' using errcode='23514';
    end if;

    update atlas.person_rhythm_opportunities o
    set projection_state='withdrawn',
        presentation_state='withdrawn',
        presentation_overlay=o.presentation_overlay || jsonb_build_object(
          'withdrawnByPlanClaimId',p_plan_claim_id,
          'reason','explicit_plan_supersession'
        ),
        metadata=o.metadata || jsonb_build_object(
          'withdrawnByPlanClaimId',p_plan_claim_id
        ),
        updated_at=now()
    where o.binding_id=v_previous.id
      and o.starts_at>=now()
      and o.projection_state<>'withdrawn';
  end if;

  insert into atlas.person_goal_rhythm_bindings(
    owner_user_id,goal_definition_id,goal_requirement_key,rhythm_definition_id,
    plan_claim_id,plan_evidence_id,opportunity_plan,metadata
  ) values (
    v_user_id,(v_envelope->>'goalDefinitionId')::uuid,v_envelope->>'goalRequirementKey',v_rhythm_definition_id,
    p_plan_claim_id,(v_envelope->>'planEvidenceId')::uuid,v_envelope->'opportunityPlan',
    jsonb_build_object('activation','atlas.activate_person_goal_rhythm_plan_api_v1')
  )
  on conflict (plan_claim_id) do nothing
  returning id into v_binding_id;

  if v_binding_id is null then
    select * into v_existing from atlas.person_goal_rhythm_bindings b where b.plan_claim_id=p_plan_claim_id;
    if v_existing.id is null
       or v_existing.status<>'active'
       or v_existing.owner_user_id is distinct from v_user_id
       or v_existing.goal_definition_id is distinct from (v_envelope->>'goalDefinitionId')::uuid
       or v_existing.goal_requirement_key is distinct from v_envelope->>'goalRequirementKey'
       or v_existing.rhythm_definition_id is distinct from v_rhythm_definition_id
       or v_existing.plan_evidence_id is distinct from (v_envelope->>'planEvidenceId')::uuid
       or v_existing.opportunity_plan is distinct from v_envelope->'opportunityPlan' then
      raise exception 'Plan Claim retry does not match existing active Goal Rhythm binding.' using errcode='23505';
    end if;
    v_binding_id := v_existing.id;
  end if;

  v_timezone := v_envelope->'opportunityPlan'->>'timezone';
  v_start_date := (now() at time zone v_timezone)::date;
  v_materialization := atlas.materialize_person_rhythm_opportunities_v1(
    v_user_id,v_binding_id,v_start_date,(v_envelope->'opportunityPlan'->>'materializationHorizonDays')::integer
  );

  return jsonb_build_object(
    'ok',true,
    'planClaimId',p_plan_claim_id,
    'planEvidenceId',v_envelope->>'planEvidenceId',
    'supersedesPlanClaimId',v_supersedes_claim_id,
    'retiredBindingId',v_retired_binding_id,
    'goalDefinitionId',v_envelope->>'goalDefinitionId',
    'goalRequirementKey',v_envelope->>'goalRequirementKey',
    'rhythmDefinitionId',v_rhythm_definition_id,
    'bindingId',v_binding_id,
    'materialization',v_materialization,
    'truthBoundary',jsonb_build_object(
      'goalDoesNotInventCadence',true,
      'acceptedPlanIsCadenceAuthority',true,
      'replacementMustExplicitlySupersedeCurrentPlan',true,
      'historicalRhythmIsRetiredNotRewritten',true,
      'futureOldOpportunitiesAreWithdrawn',true,
      'opportunitiesAreProjectionNotExecution',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

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
      'planClaimId',o.source_plan_claim_id,
      'planEvidenceId',o.source_plan_evidence_id
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
      'opportunityIsNotTask',true,
      'opportunityDoesNotProveExecution',true,
      'clockPriorityNotClaimed',true
    )
  );
end;
$$;

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'purpose','Compile a current person-accepted Goal Rhythm plan Claim into one active bound Rhythm definition and projected weekly opportunities.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); cadence and windows come only from the current accepted Claim/Evidence. Replacing an active plan requires explicit direct Claim supersession; historical Rhythm/opportunities are retired or withdrawn, never rewritten. No Task or Clock placement is created.',
      'directSignedInEndpoint',true
    ),
    reviewed_at=now()
where signature='atlas.activate_person_goal_rhythm_plan_api_v1(uuid)';

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'purpose','Read the signed-in person upcoming Rhythm opportunity projection.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); only opportunities governed by a currently accepted active plan binding are presented; superseded plan history remains stored but hidden from the current projection.',
      'directSignedInEndpoint',true
    ),
    reviewed_at=now()
where signature='atlas.person_rhythm_opportunities_self_api_v1(integer)';

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Goal Rhythm current-plan authority tightening.';
  end if;
end
$$;

commit;