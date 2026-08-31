-- Atlas Person Goal -> Rhythm Plan + Opportunities v1
--
-- Connects a person-owned Goal requirement to an explicit person-accepted
-- Rhythm plan without inventing a training / practice cadence from the Goal.
-- The accepted Claim is the planning authority. Atlas compiles that Claim into
-- a Rhythm definition and projects exact weekly windows as person-owned
-- opportunities. Opportunities are not Tasks and are not Clock placements.

begin;

create table atlas.person_goal_rhythm_bindings (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  goal_definition_id uuid not null references atlas.person_life_definitions(id) on delete cascade,
  goal_requirement_key text not null check (btrim(goal_requirement_key) <> ''),
  rhythm_definition_id uuid not null references atlas.person_life_definitions(id) on delete cascade,
  plan_claim_id uuid not null references atlas.claim_records(id) on delete restrict,
  plan_evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  opportunity_plan jsonb not null,
  status text not null default 'active' check (status in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  unique (plan_claim_id),
  unique (rhythm_definition_id)
);

comment on table atlas.person_goal_rhythm_bindings is
  'Person-owned bridge from one explicit Goal requirement to one Rhythm definition under a current accepted goal_rhythm_plan Claim. The Goal remains unchanged; the plan is separate authority.';

create index person_goal_rhythm_bindings_owner_goal_idx
  on atlas.person_goal_rhythm_bindings(owner_user_id, goal_definition_id, status, created_at, id);

create table atlas.person_rhythm_opportunities (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  binding_id uuid not null references atlas.person_goal_rhythm_bindings(id) on delete cascade,
  rhythm_definition_id uuid not null references atlas.person_life_definitions(id) on delete cascade,
  opportunity_key text not null check (btrim(opportunity_key) <> ''),
  projected_for_local_date date not null,
  timezone text not null check (btrim(timezone) <> ''),
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  projection_state text not null default 'projected' check (projection_state in ('projected','satisfied','elapsed','withdrawn')),
  presentation_state text not null default 'base' check (presentation_state in ('base','adapted','held','withdrawn')),
  base_presentation jsonb not null default '{}'::jsonb,
  presentation_overlay jsonb not null default '{}'::jsonb,
  source_plan_claim_id uuid not null references atlas.claim_records(id) on delete restrict,
  source_plan_evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (binding_id, starts_at),
  unique (owner_user_id, opportunity_key)
);

comment on table atlas.person_rhythm_opportunities is
  'Projected person-owned windows earned by an accepted Rhythm plan. These rows are schedule opportunities only: they do not create a Task, claim execution, or grant right-to-floor in the Principal Clock.';

create index person_rhythm_opportunities_owner_time_idx
  on atlas.person_rhythm_opportunities(owner_user_id, starts_at, projection_state, id);
create index person_rhythm_opportunities_binding_time_idx
  on atlas.person_rhythm_opportunities(binding_id, starts_at, id);

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
     or v_claim.authority_kind<>'person_acceptance' then
    raise exception 'Goal Rhythm plan requires a current person-accepted goal_rhythm_plan Claim.' using errcode='23514';
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
    'goalDefinitionId',v_goal_id,
    'goalRequirementKey',v_goal_key,
    'rhythm',v_rhythm,
    'opportunityPlan',v_opportunity
  );
end;
$$;

comment on function atlas.person_goal_rhythm_plan_envelope_v1(uuid,uuid) is
  'Internal validator/resolver for an accepted person goal_rhythm_plan Claim and its exact Goal requirement / Rhythm / opportunity authority.';

revoke all on function atlas.person_goal_rhythm_plan_envelope_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function atlas.person_goal_rhythm_plan_envelope_v1(uuid,uuid) to service_role;

create or replace function atlas.build_person_goal_rhythm_signal_v1(
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
  v_envelope jsonb;
  v_rhythm jsonb;
  v_goal_id uuid;
  v_goal_key text;
begin
  v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(p_owner_user_id,p_plan_claim_id);
  v_rhythm := v_envelope->'rhythm';
  v_goal_id := (v_envelope->>'goalDefinitionId')::uuid;
  v_goal_key := v_envelope->>'goalRequirementKey';

  return jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',p_owner_user_id),
    'subject',v_rhythm->'subject',
    'signalKind','rhythm',
    'state',v_rhythm->'state',
    'timing',v_rhythm->'timing',
    'requirements',coalesce(v_rhythm->'requirements','[]'::jsonb),
    'constraints',coalesce(v_rhythm->'constraints','[]'::jsonb),
    'ambiguities',coalesce(v_rhythm->'ambiguities','[]'::jsonb),
    'relations',jsonb_build_array(jsonb_build_object(
      'relationKind','supports_goal_requirement',
      'target',jsonb_build_object(
        'domain','person_life',
        'kind','goal_requirement',
        'id',v_goal_id::text || ':' || v_goal_key
      ),
      'relationBasis','accepted_goal_rhythm_plan',
      'relationStatus','authorized'
    )),
    'source',jsonb_build_object('domain','claim_evidence','kind','claim','id',p_plan_claim_id),
    'epistemic',jsonb_build_object('factClass','person_accepted_plan')
  );
end;
$$;

revoke all on function atlas.build_person_goal_rhythm_signal_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function atlas.build_person_goal_rhythm_signal_v1(uuid,uuid) to service_role;

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

revoke all on function atlas.guard_person_goal_rhythm_binding_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_goal_rhythm_binding_v1() to service_role;

create trigger person_goal_rhythm_bindings_guard_v1
before insert or update on atlas.person_goal_rhythm_bindings
for each row execute function atlas.guard_person_goal_rhythm_binding_v1();

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
  if v_binding.id is null or v_binding.status<>'active'
     or v_binding.owner_user_id is distinct from new.owner_user_id
     or v_binding.rhythm_definition_id is distinct from new.rhythm_definition_id
     or v_binding.plan_claim_id is distinct from new.source_plan_claim_id
     or v_binding.plan_evidence_id is distinct from new.source_plan_evidence_id then
    raise exception 'Rhythm opportunity custody must match its active Goal Rhythm binding.' using errcode='23514';
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

revoke all on function atlas.guard_person_rhythm_opportunity_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_rhythm_opportunity_v1() to service_role;

create trigger person_rhythm_opportunities_guard_v1
before insert or update on atlas.person_rhythm_opportunities
for each row execute function atlas.guard_person_rhythm_opportunity_v1();

alter table atlas.person_goal_rhythm_bindings enable row level security;
alter table atlas.person_rhythm_opportunities enable row level security;

create policy person_goal_rhythm_bindings_self_read
on atlas.person_goal_rhythm_bindings for select to authenticated
using (owner_user_id=auth.uid());
create policy person_rhythm_opportunities_self_read
on atlas.person_rhythm_opportunities for select to authenticated
using (owner_user_id=auth.uid());

grant select on atlas.person_goal_rhythm_bindings to authenticated;
grant select on atlas.person_rhythm_opportunities to authenticated;
grant select,insert,update,delete on atlas.person_goal_rhythm_bindings to service_role;
grant select,insert,update,delete on atlas.person_rhythm_opportunities to service_role;

create or replace function atlas.materialize_person_rhythm_opportunities_v1(
  p_owner_user_id uuid,
  p_binding_id uuid,
  p_start_date date,
  p_horizon_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_binding atlas.person_goal_rhythm_bindings%rowtype;
  v_envelope jsonb;
  v_plan jsonb;
  v_timezone text;
  v_start_time time;
  v_window_minutes integer;
  v_authorized_horizon integer;
  v_date date;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_base jsonb;
  v_key text;
  v_seen integer := 0;
  v_created integer := 0;
  v_id uuid;
begin
  select * into v_binding
  from atlas.person_goal_rhythm_bindings b
  where b.id=p_binding_id and b.owner_user_id=p_owner_user_id and b.status='active';
  if v_binding.id is null then
    raise exception 'Active Goal Rhythm binding not found for this person.' using errcode='42501';
  end if;

  v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(p_owner_user_id,v_binding.plan_claim_id);
  v_plan := v_envelope->'opportunityPlan';
  v_timezone := v_plan->>'timezone';
  v_start_time := (v_plan->>'localStartTime')::time;
  v_window_minutes := (v_plan->>'windowMinutes')::integer;
  v_authorized_horizon := (v_plan->>'materializationHorizonDays')::integer;
  v_base := coalesce(v_plan->'presentation',jsonb_build_object('kind','rhythm_opportunity'));

  if p_start_date is null then
    p_start_date := (now() at time zone v_timezone)::date;
  end if;
  if p_horizon_days is null then p_horizon_days := v_authorized_horizon; end if;
  if p_horizon_days<1 or p_horizon_days>v_authorized_horizon then
    raise exception 'Requested horizon must be within the accepted plan materializationHorizonDays.' using errcode='22023';
  end if;

  for v_date in
    select d::date from generate_series(p_start_date,p_start_date + (p_horizon_days-1),interval '1 day') d
  loop
    if not exists (
      select 1 from jsonb_array_elements(v_plan->'weekdays') w
      where (w#>>'{}')::integer=extract(isodow from v_date)::integer
    ) then continue; end if;

    v_starts_at := (v_date + v_start_time) at time zone v_timezone;
    v_ends_at := v_starts_at + make_interval(mins=>v_window_minutes);
    v_key := p_binding_id::text || ':' || to_char(v_date,'YYYY-MM-DD') || ':' || to_char(v_start_time,'HH24:MI');
    v_seen := v_seen + 1;
    v_id := null;

    insert into atlas.person_rhythm_opportunities(
      owner_user_id,binding_id,rhythm_definition_id,opportunity_key,
      projected_for_local_date,timezone,starts_at,ends_at,
      projection_state,presentation_state,base_presentation,presentation_overlay,
      source_plan_claim_id,source_plan_evidence_id,metadata
    ) values (
      p_owner_user_id,v_binding.id,v_binding.rhythm_definition_id,v_key,
      v_date,v_timezone,v_starts_at,v_ends_at,
      'projected','base',v_base,'{}'::jsonb,
      v_binding.plan_claim_id,v_binding.plan_evidence_id,
      jsonb_build_object('materializer','atlas.materialize_person_rhythm_opportunities_v1')
    )
    on conflict (binding_id,starts_at) do update set
      ends_at=excluded.ends_at,
      timezone=excluded.timezone,
      projected_for_local_date=excluded.projected_for_local_date,
      base_presentation=excluded.base_presentation,
      source_plan_claim_id=excluded.source_plan_claim_id,
      source_plan_evidence_id=excluded.source_plan_evidence_id,
      metadata=atlas.person_rhythm_opportunities.metadata || excluded.metadata,
      updated_at=now()
    returning id into v_id;

    if v_id is not null and exists (
      select 1 from atlas.person_rhythm_opportunities o where o.id=v_id and o.created_at=o.updated_at
    ) then v_created := v_created + 1; end if;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'bindingId',v_binding.id,
    'rhythmDefinitionId',v_binding.rhythm_definition_id,
    'startDate',p_start_date,
    'horizonDays',p_horizon_days,
    'projectedWindowCount',v_seen,
    'createdOrRefreshedCount',v_seen,
    'truthBoundary',jsonb_build_object(
      'windowsComeFromAcceptedPlan',true,
      'opportunityIsNotTask',true,
      'opportunityDoesNotProveExecution',true,
      'opportunityDoesNotClaimClockPriority',true,
      'goalDefinitionIsNotRewritten',true
    )
  );
end;
$$;

revoke all on function atlas.materialize_person_rhythm_opportunities_v1(uuid,uuid,date,integer) from public, anon, authenticated;
grant execute on function atlas.materialize_person_rhythm_opportunities_v1(uuid,uuid,date,integer) to service_role;

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
  v_materialization jsonb;
  v_start_date date;
  v_timezone text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_envelope := atlas.person_goal_rhythm_plan_envelope_v1(v_user_id,p_plan_claim_id);
  v_rhythm := v_envelope->'rhythm';
  v_signal := atlas.build_person_goal_rhythm_signal_v1(v_user_id,p_plan_claim_id);

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
       or v_existing.owner_user_id is distinct from v_user_id
       or v_existing.goal_definition_id is distinct from (v_envelope->>'goalDefinitionId')::uuid
       or v_existing.goal_requirement_key is distinct from v_envelope->>'goalRequirementKey'
       or v_existing.rhythm_definition_id is distinct from v_rhythm_definition_id
       or v_existing.plan_evidence_id is distinct from (v_envelope->>'planEvidenceId')::uuid
       or v_existing.opportunity_plan is distinct from v_envelope->'opportunityPlan' then
      raise exception 'Plan Claim retry does not match existing Goal Rhythm binding.' using errcode='23505';
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
    'goalDefinitionId',v_envelope->>'goalDefinitionId',
    'goalRequirementKey',v_envelope->>'goalRequirementKey',
    'rhythmDefinitionId',v_rhythm_definition_id,
    'bindingId',v_binding_id,
    'materialization',v_materialization,
    'truthBoundary',jsonb_build_object(
      'goalDoesNotInventCadence',true,
      'acceptedPlanIsCadenceAuthority',true,
      'rhythmCompiledFromAcceptedClaim',true,
      'opportunitiesAreProjectionNotExecution',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.activate_person_goal_rhythm_plan_api_v1(uuid) is
  'Compile one current accepted goal_rhythm_plan Claim into a person Rhythm binding and its authorized weekly opportunities. The Goal is not rewritten and no Task or Clock placement is created.';

revoke all on function atlas.activate_person_goal_rhythm_plan_api_v1(uuid) from public, anon;
grant execute on function atlas.activate_person_goal_rhythm_plan_api_v1(uuid) to authenticated, service_role;

create or replace function atlas.refresh_person_rhythm_opportunities_api_v1(
  p_binding_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_start_date date;
  v_horizon integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;
  begin
    v_start_date := nullif(p_payload->>'startDate','')::date;
    v_horizon := nullif(p_payload->>'horizonDays','')::integer;
  exception when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'startDate/horizonDays are invalid.' using errcode='22023';
  end;
  return atlas.materialize_person_rhythm_opportunities_v1(v_user_id,p_binding_id,v_start_date,v_horizon);
end;
$$;

revoke all on function atlas.refresh_person_rhythm_opportunities_api_v1(uuid,jsonb) from public, anon;
grant execute on function atlas.refresh_person_rhythm_opportunities_api_v1(uuid,jsonb) to authenticated, service_role;

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
    where o.owner_user_id=v_user_id
      and o.ends_at >= now() - interval '1 day'
    order by o.starts_at,o.id
    limit v_limit
  ) x;

  return jsonb_build_object(
    'ok',true,
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'opportunities',v_rows,
    'truthBoundary',jsonb_build_object(
      'readOnlyProjection',true,
      'opportunityIsNotTask',true,
      'opportunityDoesNotProveExecution',true,
      'clockPriorityNotClaimed',true
    )
  );
end;
$$;

revoke all on function atlas.person_rhythm_opportunities_self_api_v1(integer) from public, anon;
grant execute on function atlas.person_rhythm_opportunities_self_api_v1(integer) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values
  (
    'atlas.activate_person_goal_rhythm_plan_api_v1(uuid)',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Compile a person-accepted Goal Rhythm plan Claim into a bound Rhythm definition and projected weekly opportunities.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); the Goal requirement, Rhythm signal, cadence, and windows are read from the current accepted goal_rhythm_plan Claim/Evidence. No Task or Clock placement is created.',
      'directSignedInEndpoint',true
    ),now(),false
  ),
  (
    'atlas.refresh_person_rhythm_opportunities_api_v1(uuid,jsonb)',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Refresh projected person Rhythm opportunities from the already accepted weekly plan.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); caller can choose projection range only within the plan authorized horizon and cannot change cadence/window semantics.',
      'directSignedInEndpoint',true
    ),now(),false
  ),
  (
    'atlas.person_rhythm_opportunities_self_api_v1(integer)',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Read the signed-in person upcoming Rhythm opportunity projection.',
      'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); read only.',
      'directSignedInEndpoint',true
    ),now(),false
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
    raise exception 'Authenticated RPC registry drifted after Goal Rhythm plan opportunity activation.';
  end if;
end
$$;

commit;