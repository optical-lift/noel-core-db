-- Atlas Generic Care Persistence v1
-- Observation-owned generic Care state plus a compatibility bridge from existing Farm Care observations.

begin;

create table atlas.care_observation_events (
  id uuid primary key default gen_random_uuid(),
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  scope_kind text not null,
  scope_id uuid not null,
  observed_at timestamptz not null default now(),
  condition_state text not null,
  disposition text not null,
  observed_by_user_id uuid references auth.users(id) on delete set null,
  source_kind text not null,
  source_key text,
  note text,
  inferred_from_clock boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint care_observation_events_subject_domain_not_blank check (btrim(subject_domain) <> ''),
  constraint care_observation_events_subject_kind_not_blank check (btrim(subject_kind) <> ''),
  constraint care_observation_events_subject_id_not_blank check (btrim(subject_id) <> ''),
  constraint care_observation_events_scope_kind_not_blank check (btrim(scope_kind) <> ''),
  constraint care_observation_events_condition_not_blank check (btrim(condition_state) <> ''),
  constraint care_observation_events_source_kind_not_blank check (btrim(source_kind) <> ''),
  constraint care_observation_events_disposition_check
    check (disposition in ('hold', 'reassess', 'intervene')),
  constraint care_observation_events_clock_authority_check
    check (inferred_from_clock = false),
  constraint care_observation_events_source_key_key unique (source_key)
);

create index care_observation_events_subject_observed_idx
  on atlas.care_observation_events(subject_domain, subject_kind, subject_id, observed_at desc);
create index care_observation_events_scope_observed_idx
  on atlas.care_observation_events(scope_kind, scope_id, observed_at desc);

alter table atlas.care_observation_events enable row level security;

create policy care_observation_events_scope_read
on atlas.care_observation_events
for select
to authenticated
using (
  (
    scope_kind = 'household'
    and exists (
      select 1
      from atlas.households h
      join atlas.principals p on p.id = h.principal_id
      where h.id = care_observation_events.scope_id
        and h.status = 'active'
        and p.status = 'active'
        and p.user_id = auth.uid()
    )
  )
  or (
    scope_kind = 'farm'
    and atlas.can_read_farm_operations(scope_id)
  )
);

grant select on atlas.care_observation_events to authenticated;
grant select, insert, update, delete on atlas.care_observation_events to service_role;

create table atlas.care_current_state (
  id uuid primary key default gen_random_uuid(),
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  scope_kind text not null,
  scope_id uuid not null,
  condition_state text not null,
  disposition text not null,
  last_observed_at timestamptz not null,
  last_observation_id uuid references atlas.care_observation_events(id) on delete set null,
  care_strategy text,
  trend text,
  next_reassess_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint care_current_state_subject_domain_not_blank check (btrim(subject_domain) <> ''),
  constraint care_current_state_subject_kind_not_blank check (btrim(subject_kind) <> ''),
  constraint care_current_state_subject_id_not_blank check (btrim(subject_id) <> ''),
  constraint care_current_state_scope_kind_not_blank check (btrim(scope_kind) <> ''),
  constraint care_current_state_condition_not_blank check (btrim(condition_state) <> ''),
  constraint care_current_state_disposition_check
    check (disposition in ('hold', 'reassess', 'intervene')),
  constraint care_current_state_subject_key
    unique (subject_domain, subject_kind, subject_id)
);

create index care_current_state_scope_idx
  on atlas.care_current_state(scope_kind, scope_id, disposition, last_observed_at desc);

create trigger care_current_state_set_updated_at
before update on atlas.care_current_state
for each row execute function atlas.set_updated_at();

alter table atlas.care_current_state enable row level security;

create policy care_current_state_scope_read
on atlas.care_current_state
for select
to authenticated
using (
  (
    scope_kind = 'household'
    and exists (
      select 1
      from atlas.households h
      join atlas.principals p on p.id = h.principal_id
      where h.id = care_current_state.scope_id
        and h.status = 'active'
        and p.status = 'active'
        and p.user_id = auth.uid()
    )
  )
  or (
    scope_kind = 'farm'
    and atlas.can_read_farm_operations(scope_id)
  )
);

grant select on atlas.care_current_state to authenticated;
grant select, insert, update, delete on atlas.care_current_state to service_role;

create table atlas.care_result_events (
  id uuid primary key default gen_random_uuid(),
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  scope_kind text not null,
  scope_id uuid not null,
  occurred_at timestamptz not null default now(),
  result_kind text not null,
  condition_before text,
  condition_after text not null,
  minutes integer,
  minutes_known boolean not null default false,
  actor_user_id uuid references auth.users(id) on delete set null,
  source_kind text not null,
  source_key text,
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint care_result_events_subject_domain_not_blank check (btrim(subject_domain) <> ''),
  constraint care_result_events_subject_kind_not_blank check (btrim(subject_kind) <> ''),
  constraint care_result_events_subject_id_not_blank check (btrim(subject_id) <> ''),
  constraint care_result_events_scope_kind_not_blank check (btrim(scope_kind) <> ''),
  constraint care_result_events_condition_after_not_blank check (btrim(condition_after) <> ''),
  constraint care_result_events_source_kind_not_blank check (btrim(source_kind) <> ''),
  constraint care_result_events_result_kind_check check (
    result_kind in (
      'recovered',
      'improved_more_remains',
      'condition_differed',
      'blocked',
      'strategy_should_change',
      'plan_changed_not_relevant'
    )
  ),
  constraint care_result_events_minutes_check check (minutes is null or minutes >= 0),
  constraint care_result_events_minutes_known_check check (minutes_known = false or minutes is not null),
  constraint care_result_events_source_key_key unique (source_key)
);

create index care_result_events_subject_occurred_idx
  on atlas.care_result_events(subject_domain, subject_kind, subject_id, occurred_at desc);
create index care_result_events_scope_occurred_idx
  on atlas.care_result_events(scope_kind, scope_id, occurred_at desc);

alter table atlas.care_result_events enable row level security;

create policy care_result_events_scope_read
on atlas.care_result_events
for select
to authenticated
using (
  (
    scope_kind = 'household'
    and exists (
      select 1
      from atlas.households h
      join atlas.principals p on p.id = h.principal_id
      where h.id = care_result_events.scope_id
        and h.status = 'active'
        and p.status = 'active'
        and p.user_id = auth.uid()
    )
  )
  or (
    scope_kind = 'farm'
    and atlas.can_read_farm_operations(scope_id)
  )
);

grant select on atlas.care_result_events to authenticated;
grant select, insert, update, delete on atlas.care_result_events to service_role;

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
    jsonb_build_object(
      'lastObservationSourceKind', new.source_kind,
      'inferredFromClock', false
    )
  )
  on conflict (subject_domain, subject_kind, subject_id)
  do update set
    scope_kind = excluded.scope_kind,
    scope_id = excluded.scope_id,
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

create trigger care_observation_events_apply_current_state
after insert on atlas.care_observation_events
for each row execute function atlas.care_apply_observation_current_state_v1();

create or replace function atlas.care_condition_disposition_v1(p_condition_state text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case p_condition_state
    when 'holding' then 'hold'
    when 'unknown' then 'reassess'
    when 'needs_attention' then 'intervene'
    when 'losing_shape' then 'intervene'
    when 'recovery_needed' then 'intervene'
    else null
  end;
$$;

revoke all on function atlas.care_condition_disposition_v1(text) from public, anon, authenticated;
grant execute on function atlas.care_condition_disposition_v1(text) to service_role;

create or replace function atlas.care_mirror_farm_observation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_condition text;
  v_disposition text;
begin
  v_condition := case
    when new.recovery_required is true then 'recovery_needed'
    when new.intended_shape_readable is false
      or new.pressure_band in ('heavy', 'severe') then 'losing_shape'
    when new.pressure_band in ('moderate', 'medium') then 'needs_attention'
    else 'holding'
  end;
  v_disposition := case when v_condition = 'holding' then 'hold' else 'intervene' end;

  insert into atlas.care_observation_events (
    subject_domain,
    subject_kind,
    subject_id,
    scope_kind,
    scope_id,
    observed_at,
    condition_state,
    disposition,
    observed_by_user_id,
    source_kind,
    source_key,
    note,
    inferred_from_clock,
    metadata
  )
  values (
    'farm',
    'growing_object',
    new.object_id::text,
    'farm',
    new.farm_id,
    new.observed_at,
    v_condition,
    v_disposition,
    null,
    'legacy_farm_care_observation',
    'legacy_farm_care_observation:' || new.id::text,
    new.note,
    false,
    jsonb_build_object(
      'legacyObservationId', new.id,
      'zoneId', new.zone_id,
      'observedByMembershipId', new.observed_by_membership_id,
      'pressureBand', new.pressure_band,
      'intendedShapeReadable', new.intended_shape_readable,
      'functionProtected', new.function_protected,
      'recoveryRequired', new.recovery_required,
      'estimatedRecoveryMinutes', new.estimated_recovery_minutes
    ) || coalesce(new.metadata, '{}'::jsonb)
  )
  on conflict (source_key) do nothing;

  return new;
end;
$$;

revoke all on function atlas.care_mirror_farm_observation_v1() from public, anon, authenticated;

create trigger care_observations_mirror_generic_v1
after insert on atlas.care_observations
for each row execute function atlas.care_mirror_farm_observation_v1();

insert into atlas.care_observation_events (
  subject_domain,
  subject_kind,
  subject_id,
  scope_kind,
  scope_id,
  observed_at,
  condition_state,
  disposition,
  observed_by_user_id,
  source_kind,
  source_key,
  note,
  inferred_from_clock,
  metadata
)
select
  'farm',
  'growing_object',
  co.object_id::text,
  'farm',
  co.farm_id,
  co.observed_at,
  case
    when co.recovery_required is true then 'recovery_needed'
    when co.intended_shape_readable is false
      or co.pressure_band in ('heavy', 'severe') then 'losing_shape'
    when co.pressure_band in ('moderate', 'medium') then 'needs_attention'
    else 'holding'
  end,
  case
    when co.recovery_required is true
      or co.intended_shape_readable is false
      or co.pressure_band in ('heavy', 'severe', 'moderate', 'medium')
      then 'intervene'
    else 'hold'
  end,
  null,
  'legacy_farm_care_observation',
  'legacy_farm_care_observation:' || co.id::text,
  co.note,
  false,
  jsonb_build_object(
    'legacyObservationId', co.id,
    'zoneId', co.zone_id,
    'observedByMembershipId', co.observed_by_membership_id,
    'pressureBand', co.pressure_band,
    'intendedShapeReadable', co.intended_shape_readable,
    'functionProtected', co.function_protected,
    'recoveryRequired', co.recovery_required,
    'estimatedRecoveryMinutes', co.estimated_recovery_minutes
  ) || coalesce(co.metadata, '{}'::jsonb)
from atlas.care_observations co
order by co.observed_at, co.id
on conflict (source_key) do nothing;

commit;
