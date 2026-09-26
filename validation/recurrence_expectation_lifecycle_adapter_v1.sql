-- Recurrence Expectation Lifecycle Adapter v1 acceptance
-- Permanent executable proof for the live adapter contract.
-- The only write is a rollback-only temporary move exception.

begin;

DO $assert_baseline$
declare
  v_organization_id constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid;
  v_context_id constant uuid := 'f546bc48-b915-42a5-8c64-72b58b038142'::uuid;
  v_rule_ids uuid[];
  v_recurrence jsonb;
  v_composer jsonb;
  v_instance_count_before integer;
  v_instance_count_after integer;
  v_occurrence_count integer;
  v_marker_count integer;
  v_expectation_count integer;
  v_bad_pressure_count integer;
  v_actual_dates date[];
  v_actual_titles text[];
begin
  select array_agg(r.id order by r.stable_key)
  into v_rule_ids
  from atlas.organization_purpose_context_memberships m
  join atlas.organization_recurrence_rules r
    on r.id=m.recurrence_rule_id
   and r.organization_id=m.organization_id
  where m.organization_id=v_organization_id
    and m.context_id=v_context_id
    and m.membership_state='active'
    and m.member_kind='recurrence_rule'
    and r.stable_key in (
      'thursdays_community_mornings',
      'thursdays_seasonal_evenings'
    );

  if coalesce(cardinality(v_rule_ids),0)<>2 then
    raise exception 'Acceptance fixture expected two active Elm recurrence rules; got %.',coalesce(cardinality(v_rule_ids),0);
  end if;

  select count(*)::integer
  into v_instance_count_before
  from atlas.organization_recurrence_instances i
  where i.organization_id=v_organization_id
    and i.recurrence_rule_id=any(v_rule_ids)
    and i.local_date between date '2026-12-01' and date '2026-12-31';

  if v_instance_count_before<>0 then
    raise exception 'December acceptance requires zero persisted recurrence instances before read derivation; got %.',v_instance_count_before;
  end if;

  v_recurrence:=atlas.recurrence_expectation_temporal_adapter_v1(
    v_organization_id,
    v_rule_ids,
    date '2026-12-01',
    date '2026-12-31',
    5000
  );

  if coalesce((v_recurrence#>>'{coverage,partial}')::boolean,true) then
    raise exception 'December recurrence coverage must be complete: %',v_recurrence->'coverage';
  end if;

  if coalesce((v_recurrence#>>'{coverage,derivedWithoutPersistedInstanceCount}')::integer,-1)<>4 then
    raise exception 'December derivation must report four expectations without persisted instances: %',v_recurrence->'coverage';
  end if;

  select count(*)::integer,
         array_agg((c#>>'{coordinate,dateKey}')::date order by (c#>>'{coordinate,dateKey}')::date),
         array_agg(c#>>'{display,title}' order by (c#>>'{coordinate,dateKey}')::date),
         count(*) filter (
           where coalesce((c#>>'{temporalPressure,active}')::boolean,false) is not true
              or c#>>'{temporalPressure,class}'<>'expectation'
         )::integer
  into v_expectation_count,v_actual_dates,v_actual_titles,v_bad_pressure_count
  from jsonb_array_elements(v_recurrence->'expectationContributions') as x(c);

  if v_expectation_count<>4 then
    raise exception 'December acceptance expected four standalone expectations; got %.',v_expectation_count;
  end if;

  if v_actual_dates<>array[
    date '2026-12-03',
    date '2026-12-10',
    date '2026-12-17',
    date '2026-12-24'
  ] then
    raise exception 'Unexpected December expectation dates: %.',v_actual_dates;
  end if;

  if v_actual_titles<>array[
    'Thursdays at Elm — Community Mornings',
    'Thursdays at Elm — Seasonal Evenings',
    'Thursdays at Elm — Community Mornings',
    'Thursdays at Elm — Seasonal Evenings'
  ]::text[] then
    raise exception 'Unexpected December expectation titles: %.',v_actual_titles;
  end if;

  if v_bad_pressure_count<>0 then
    raise exception 'All four unrealized December expectations must carry active expectation pressure; bad rows=%',v_bad_pressure_count;
  end if;

  select count(*)::integer
  into v_instance_count_after
  from atlas.organization_recurrence_instances i
  where i.organization_id=v_organization_id
    and i.recurrence_rule_id=any(v_rule_ids)
    and i.local_date between date '2026-12-01' and date '2026-12-31';

  if v_instance_count_after<>v_instance_count_before then
    raise exception 'Read derivation mutated recurrence instances: before %, after %.',v_instance_count_before,v_instance_count_after;
  end if;

  v_composer:=atlas.organization_context_temporal_composer_service_v2(
    v_organization_id,
    v_context_id,
    date '2026-10-01',
    date '2026-11-30',
    'America/Chicago',
    5000
  );

  if coalesce((v_composer#>>'{coverage,partial}')::boolean,true) then
    raise exception 'October-November composer coverage must be complete: %',v_composer->'coverage';
  end if;

  select
    count(*) filter (where c#>>'{sourceRef,kind}'='occurrence')::integer,
    count(*) filter (where c#>>'{sourceRef,kind}'='temporal_marker')::integer
  into v_occurrence_count,v_marker_count
  from jsonb_array_elements(v_composer->'contributions') as x(c);

  if v_occurrence_count<>25 then
    raise exception 'October-November acceptance expected 25 canonical Occurrence contributions; got %.',v_occurrence_count;
  end if;

  if v_marker_count<>2 then
    raise exception 'October-November acceptance expected two canonical Temporal Marker contributions; got %.',v_marker_count;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_composer->'contributions') as x(c)
    where c#>>'{sourceRef,kind}'='recurrence_instance'
  ) then
    raise exception 'Composer must not manufacture recurrence-instance event identities.';
  end if;
end
$assert_baseline$;

DO $assert_move_fixture_clear$
declare
  v_organization_id constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid;
  v_rule_id uuid;
begin
  select r.id
  into v_rule_id
  from atlas.organization_recurrence_rules r
  where r.organization_id=v_organization_id
    and r.stable_key='thursdays_community_mornings';

  if v_rule_id is null then
    raise exception 'Community Morning recurrence rule fixture is missing.';
  end if;

  if exists (
    select 1
    from atlas.organization_recurrence_exceptions e
    where e.organization_id=v_organization_id
      and e.recurrence_rule_id=v_rule_id
      and e.source_local_date=date '2026-12-03'
  ) then
    raise exception 'Move acceptance fixture requires December 3 to have no persisted exception.';
  end if;
end
$assert_move_fixture_clear$;

insert into atlas.organization_recurrence_exceptions (
  organization_id,
  recurrence_rule_id,
  source_local_date,
  exception_action,
  replacement_date,
  reason,
  payload,
  exception_state
)
select
  'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
  r.id,
  date '2026-12-03',
  'move',
  date '2026-12-04',
  'recurrence_expectation_lifecycle_adapter_v1 acceptance rollback fixture',
  jsonb_build_object('acceptanceFixture','recurrence_expectation_lifecycle_adapter_v1'),
  'active'
from atlas.organization_recurrence_rules r
where r.organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
  and r.stable_key='thursdays_community_mornings';

DO $assert_move$
declare
  v_organization_id constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid;
  v_rule_id uuid;
  v_result jsonb;
  v_moved jsonb;
  v_expected_key text;
begin
  select r.id
  into v_rule_id
  from atlas.organization_recurrence_rules r
  where r.organization_id=v_organization_id
    and r.stable_key='thursdays_community_mornings';

  v_expected_key:='recurrence_expectation:'||v_rule_id::text||':2026-12-03';

  v_result:=atlas.recurrence_expectation_temporal_adapter_v1(
    v_organization_id,
    array[v_rule_id],
    date '2026-12-01',
    date '2026-12-10',
    5000
  );

  select c
  into v_moved
  from jsonb_array_elements(v_result->'expectationContributions') as x(c)
  where c->>'projectionKey'=v_expected_key;

  if v_moved is null then
    raise exception 'Moved expectation was not returned under its source-anchored projection key %.',v_expected_key;
  end if;

  if v_moved#>>'{sourceSnapshot,lineage,sourceLocalDate}'<>'2026-12-03' then
    raise exception 'Move must preserve December 3 source lineage: %',v_moved#>'{sourceSnapshot,lineage}';
  end if;

  if v_moved#>>'{coordinate,dateKey}'<>'2026-12-04' then
    raise exception 'Move must shift effective coordinate to December 4: %',v_moved->'coordinate';
  end if;

  if v_moved#>>'{sourceSnapshot,lineage,exception,action}'<>'move' then
    raise exception 'Move lifecycle must retain the source exception action: %',v_moved#>'{sourceSnapshot,lineage,exception}';
  end if;

  if v_moved#>>'{sourceSnapshot,scheduleState}'<>'moved' then
    raise exception 'Moved expectation must report scheduleState=moved: %',v_moved#>'{sourceSnapshot,scheduleState}';
  end if;

  if coalesce((v_moved#>>'{temporalPressure,active}')::boolean,false) is not true
     or v_moved#>>'{temporalPressure,class}'<>'expectation'
     or (v_moved#>>'{temporalPressure,startsAt}')::date<>date '2026-12-04' then
    raise exception 'Temporal pressure must follow the moved effective coordinate: %',v_moved->'temporalPressure';
  end if;
end
$assert_move$;

rollback;

DO $assert_cleanup$
begin
  if exists (
    select 1
    from atlas.organization_recurrence_exceptions e
    where e.organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and e.source_local_date=date '2026-12-03'
      and e.payload->>'acceptanceFixture'='recurrence_expectation_lifecycle_adapter_v1'
  ) then
    raise exception 'Rollback-only move acceptance fixture persisted unexpectedly.';
  end if;
end
$assert_cleanup$;
