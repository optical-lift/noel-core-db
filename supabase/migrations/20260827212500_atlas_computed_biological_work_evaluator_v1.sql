-- Atlas computed biological work evaluator v1
--
-- Governing boundary:
--   * canonical crop / production truth + policy are the authority;
--   * current biological work is computed, not materialized as active requirement state;
--   * tasks and state_consequence_instances are not prerequisites for recognizing work;
--   * execution readiness is reported separately from whether the biological work exists.
--
-- This first slice is intentionally read-only and crop-cycle scoped. It does not
-- backfill data, create tasks, alter Home/Day, or retire existing consequence instances.

create or replace function atlas.current_crop_biological_work_v1(
  p_crop_cycle_id uuid,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_day date := coalesce(p_as_of_date,current_date);
  v_snapshot jsonb;
  v_policy atlas.state_consequence_policies%rowtype;
  v_role text;
  v_item jsonb;
  v_execution jsonb;
  v_operations jsonb := '[]'::jsonb;
  v_truth_acquisition jsonb := '[]'::jsonb;
  v_other jsonb := '[]'::jsonb;
  v_destination jsonb;
  v_harvest_status text;
  v_highest_priority integer := null;
  v_blocks_execution boolean;
begin
  if p_crop_cycle_id is null then
    raise exception 'Crop cycle is required.' using errcode='22023';
  end if;

  select * into v_cycle
  from atlas.crop_cycles
  where id=p_crop_cycle_id;

  if v_cycle.id is null then
    raise exception 'Crop cycle not found.' using errcode='P0002';
  end if;

  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  v_snapshot := atlas.crop_cycle_requirement_snapshot_v1(v_cycle.id,v_day);
  v_destination := atlas.crop_destination_claim_coverage_v1(v_cycle.id);

  select availability.status into v_harvest_status
  from atlas.crop_harvest_availability availability
  where availability.crop_cycle_id=v_cycle.id;

  for v_policy in
    select p.*
    from atlas.state_consequence_policies p
    where p.active
      and p.subject_kind='crop_cycle'
      and (p.farm_id is null or p.farm_id=v_cycle.farm_id)
      and v_snapshot @> p.subject_selector
      and v_snapshot @> p.state_match
    order by p.priority,p.stable_key
  loop
    v_role := coalesce(nullif(v_policy.metadata->>'consequenceRole',''),'other');
    v_highest_priority := case
      when v_highest_priority is null then v_policy.priority
      else least(v_highest_priority,v_policy.priority)
    end;

    v_blocks_execution := lower(coalesce(v_policy.action_spec->>'blocksExecution','false'))='true';
    v_execution := null;

    if v_role='operation_requirement' then
      if v_policy.action_key='transplant' then
        v_execution := jsonb_strip_nulls(jsonb_build_object(
          'executionReady',coalesce((v_snapshot->>'destinationReleaseAllowed')::boolean,false),
          'warrant',case
            when coalesce((v_snapshot->>'destinationReleaseAllowed')::boolean,false) then 'ready'
            else 'missing_truth'
          end,
          'blockerKind',case
            when coalesce((v_snapshot->>'destinationReleaseAllowed')::boolean,false) then null
            when coalesce(v_snapshot->>'destinationCoverageState','missing')='missing' then 'destination_required'
            else 'destination_coverage_required'
          end,
          'destination',v_destination
        ));
      elsif v_policy.action_key='harvest' then
        v_execution := jsonb_strip_nulls(jsonb_build_object(
          'executionReady',coalesce(v_harvest_status,'unknown')='harvestable',
          'warrant',case when coalesce(v_harvest_status,'unknown')='harvestable' then 'ready' else 'missing_truth' end,
          'blockerKind',case when coalesce(v_harvest_status,'unknown')='harvestable' then null else 'harvestability_not_current' end,
          'harvestAvailabilityState',coalesce(v_harvest_status,'unknown')
        ));
      else
        v_execution := jsonb_build_object(
          'executionReady',false,
          'warrant','operation_adapter_not_defined',
          'blockerKind','operation_execution_adapter_required'
        );
      end if;
    end if;

    v_item := jsonb_strip_nulls(jsonb_build_object(
      'policyKey',v_policy.stable_key,
      'role',v_role,
      'consequenceKind',v_policy.consequence_kind,
      'actionKey',v_policy.action_key,
      'audience',v_policy.audience,
      'priority',v_policy.priority,
      'actionSpec',v_policy.action_spec,
      'policyMetadata',v_policy.metadata,
      'blocksExecution',case when v_role='truth_acquisition' then v_blocks_execution else null end,
      'requirementState',case when v_role='operation_requirement' then v_snapshot->>'requirementState' else null end,
      'requirementKnownActiveBy',case when v_role='operation_requirement' then v_snapshot->>'requirementKnownActiveBy' else null end,
      'requirementTimeClass',case when v_role='operation_requirement' then v_snapshot->>'requirementTimeClass' else null end,
      'execution',v_execution
    ));

    if v_role='operation_requirement' then
      v_operations := v_operations || jsonb_build_array(v_item);
    elsif v_role='truth_acquisition' then
      v_truth_acquisition := v_truth_acquisition || jsonb_build_array(v_item);
    else
      v_other := v_other || jsonb_build_array(v_item);
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','current_crop_biological_work_v1',
    'farmId',v_cycle.farm_id,
    'cropCycleId',v_cycle.id,
    'cropCycleKey',v_cycle.crop_cycle_key,
    'cropLabel',v_cycle.crop_label,
    'variety',v_cycle.variety,
    'cycleState',v_cycle.cycle_state,
    'lifecycleStatus',v_cycle.lifecycle_status,
    'asOfDate',v_day,
    'workExists',jsonb_array_length(v_operations)>0,
    'truthAcquisitionNeeded',jsonb_array_length(v_truth_acquisition)>0,
    'highestPriority',v_highest_priority,
    'operationRequirements',v_operations,
    'truthAcquisition',v_truth_acquisition,
    'otherConsequences',v_other,
    'snapshot',v_snapshot,
    'truthBoundary',jsonb_build_object(
      'computedFromCanonicalState',true,
      'stateConsequenceInstanceDependency',false,
      'taskDependency',false,
      'plannedOccurrenceDependency',false,
      'missingExecutionTruthDoesNotEraseWork',true,
      'policyMatchIsRecomputedOnRead',true,
      'noActiveRequirementRowCreated',true
    )
  );
end;
$$;

revoke all on function atlas.current_crop_biological_work_v1(uuid,date) from public, anon;
grant execute on function atlas.current_crop_biological_work_v1(uuid,date) to authenticated, service_role;

comment on function atlas.current_crop_biological_work_v1(uuid,date) is
  'Read-only biological work evaluator. Matches the canonical crop-cycle snapshot directly against active state consequence policies; does not require or create state_consequence_instances or tasks.';

create or replace function atlas.current_biological_work_v1(
  p_farm_id uuid,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_day date := coalesce(p_as_of_date,current_date);
  v_items jsonb := '[]'::jsonb;
  v_active_crop_count integer := 0;
  v_work_item_count integer := 0;
  v_truth_item_count integer := 0;
begin
  if p_farm_id is null then
    raise exception 'Farm is required.' using errcode='22023';
  end if;

  if not exists(select 1 from atlas.farms farm where farm.id=p_farm_id) then
    raise exception 'Farm not found.' using errcode='P0002';
  end if;

  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select count(*)::integer into v_active_crop_count
  from atlas.crop_cycles cycle
  where cycle.farm_id=p_farm_id
    and coalesce(cycle.lifecycle_status,'active')='active';

  with evaluated as (
    select
      cycle.id,
      atlas.current_crop_biological_work_v1(cycle.id,v_day) as work
    from atlas.crop_cycles cycle
    where cycle.farm_id=p_farm_id
      and coalesce(cycle.lifecycle_status,'active')='active'
  ), relevant as (
    select id,work
    from evaluated
    where coalesce((work->>'workExists')::boolean,false)
       or coalesce((work->>'truthAcquisitionNeeded')::boolean,false)
  )
  select
    coalesce(jsonb_agg(work order by coalesce((work->>'highestPriority')::integer,999),coalesce(work->>'cropLabel',''),coalesce(work->>'variety',''),id),'[]'::jsonb),
    count(*) filter (where coalesce((work->>'workExists')::boolean,false))::integer,
    count(*) filter (where coalesce((work->>'truthAcquisitionNeeded')::boolean,false))::integer
  into v_items,v_work_item_count,v_truth_item_count
  from relevant;

  return jsonb_build_object(
    'contractVersion','current_biological_work_v1',
    'farmId',p_farm_id,
    'asOfDate',v_day,
    'activeCropCycleCount',v_active_crop_count,
    'cropCyclesWithBiologicalWork',v_work_item_count,
    'cropCyclesWithTruthAcquisition',v_truth_item_count,
    'items',coalesce(v_items,'[]'::jsonb),
    'coverage',jsonb_build_object(
      'cropCycles',true,
      'productionLots',false,
      'productionSuccessions',false,
      'coverageNote','v1 deliberately proves the computed contract on current crop cycles first. Production lot and future succession adapters are deferred to later bounded slices.'
    ),
    'truthBoundary',jsonb_build_object(
      'computedNotMaterialized',true,
      'stateConsequenceInstancesAreNotAuthority',true,
      'tasksAreNotAuthority',true,
      'emptyItemsMeansNoCurrentPolicyMatchNotNoFarmBiology',true
    )
  );
end;
$$;

revoke all on function atlas.current_biological_work_v1(uuid,date) from public, anon;
grant execute on function atlas.current_biological_work_v1(uuid,date) to authenticated, service_role;

comment on function atlas.current_biological_work_v1(uuid,date) is
  'Farm-wide read-only crop-cycle biological work evaluator. Current work is recomputed from canonical crop state and active policy; no active requirement rows are materialized.';
