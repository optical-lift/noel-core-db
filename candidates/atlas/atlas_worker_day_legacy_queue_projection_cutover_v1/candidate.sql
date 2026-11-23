-- HELD SOURCE ONLY: Atlas SRC-RETIRE-01 worker-day future projection queue reader cutoff.
-- Existing function, exact signature/owner/ACL/search_path; NO new Work/Task/queue engine.
-- Pin live source: pg_get_functiondef MD5 2f9ed909367aa93f224d0d7e8eb56398
-- Do not apply to production without signed current-schema clone, canonical version generation,
-- independent proof and separate exact owner release authorization.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE TEMP TABLE atlas_worker_day_queue_projection_before ON COMMIT DROP AS
SELECT p.oid,p.proowner,p.proacl,p.prosecdef,p.proconfig,
       md5(pg_get_functiondef(p.oid)) source_md5
FROM pg_proc p
WHERE p.oid=to_regprocedure('atlas.worker_day_selection_overlay_live_v1(uuid,uuid,date,jsonb)');

DO $atlas_projection_source_guard$
BEGIN
  IF (SELECT count(*) FROM atlas_worker_day_queue_projection_before)<>1 OR
     (SELECT source_md5 FROM atlas_worker_day_queue_projection_before)
       IS DISTINCT FROM '2f9ed909367aa93f224d0d7e8eb56398'
  THEN RAISE EXCEPTION 'Worker Day queue projection original source drift'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM atlas_worker_day_queue_projection_before b
    WHERE b.proowner='postgres'::regrole AND b.prosecdef
      AND b.proacl::text='{postgres=X/postgres,service_role=X/postgres}'
  ) THEN RAISE EXCEPTION 'Worker Day projection original owner / EXECUTE custody drift'; END IF;
  IF to_regclass('atlas.task_release_queue_items') IS NULL OR
     to_regclass('atlas.work_items') IS NULL OR
     to_regclass('atlas.work_allocations') IS NULL OR
     to_regclass('atlas.work_execution_plans') IS NULL
  THEN RAISE EXCEPTION 'Original historical/canonical sources missing'; END IF;
  PERFORM set_config('atlas.projection_pre_queue_count',
      (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
  PERFORM set_config('atlas.projection_pre_queue_hash',
      (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
       FROM atlas.task_release_queue_items q),true);
  PERFORM set_config('atlas.projection_pre_work',(SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.projection_pre_tasks',(SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.projection_pre_occurrences',(SELECT count(*)::text FROM atlas.planned_work_occurrences),true);
  PERFORM set_config('atlas.projection_pre_requirements',(SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.projection_pre_queue_source_count',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname IN ('atlas','public') AND p.prokind IN ('f','p')
       AND strpos(lower(pg_get_functiondef(p.oid)),'task_release_queue_items')>0),true);
END $atlas_projection_source_guard$;

CREATE OR REPLACE FUNCTION atlas.worker_day_selection_overlay_live_v1(p_farm_id uuid, p_membership_id uuid, p_day date, p_plan jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_plan jsonb:=coalesce(p_plan,'{}'::jsonb);
  v_real jsonb:='[]'::jsonb;
  v_next jsonb:='[]'::jsonb;
  v_reality jsonb:='{}'::jsonb;
  v_selection jsonb:='[]'::jsonb;
  v_automatic jsonb:='[]'::jsonb;
  v_committed integer:=0;
  v_automatic_minutes integer:=0;
  v_target integer:=0;
  v_capacity jsonb;
  v_item jsonb;
  v_timezone text:='America/Chicago';
  v_today date;
begin
  if coalesce((v_plan->>'availableWorkerDay')::boolean,true)=false then
    return jsonb_set(v_plan,'{nextUp}','[]'::jsonb,true);
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago') into v_timezone
  from atlas.farms f where f.id=p_farm_id;
  v_today:=(now() at time zone coalesce(v_timezone,'America/Chicago'))::date;

  -- One Reality snapshot for explanation metadata.
  select coalesce(jsonb_object_agg(c.task_id::text,jsonb_build_object(
      'warrantClass',c.reality_warrant_class,
      'warrantOrder',c.reality_warrant_order,
      'subjectState',c.subject_state,
      'fittingOperation',c.fitting_operation,
      'operationWindow',c.operation_window,
      'jurisdiction',c.jurisdiction,
      'truthBoundary',c.truth_boundary
    )),'{}'::jsonb) into v_reality
  from atlas.farm_clock_reality_candidates_v1(p_farm_id,p_membership_id,p_day) c;

  -- One selector snapshot owns both Today and Next Up. Do not rebuild the same
  -- weekly/reality arbitration separately for each projection lane.
  select coalesce(jsonb_agg(jsonb_build_object(
    'taskId',s.task_id,
    'presentationState',s.presentation_state,
    'presentationReason',s.presentation_reason,
    'laneOrder',s.lane_order,
    'selectionRank',s.selection_rank,
    'workLane',s.work_lane,
    'commitmentKind',s.commitment_kind,
    'effortUnits',s.effort_units,
    'budgetUnits',s.budget_units,
    'notificationPlanned',s.notification_planned,
    'overload',s.overload
  ) order by s.selection_rank,s.task_id),'[]'::jsonb)
  into v_selection
  from atlas.presented_work_selection_rows_v1(p_farm_id,p_membership_id,p_day) s;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id','task:'||t.id::text,'kind','real','sourceKind','task','sourceId',t.id,'taskId',t.id,
      'title',t.title,'status',t.status,'expectedActiveMinutes',capacity.expected_active_minutes,
      'physicalLoad',capacity.physical_load,
      'dayWindow',coalesce(placement.day_window,atlas.worker_task_day_window_v1(t.action_key,t.task_type,t.metadata)),
      'workOrderNumber',coalesce(placement.sort_order,atlas.worker_task_order_v1(t.action_key,t.task_type,t.metadata)),
      'location',coalesce(nullif(t.metadata->>'display_location',''),nullif(t.metadata->>'collection_zone',''),nullif(t.metadata->>'collection_label','')),
      'automatic',false,'requiresOwnerApproval',false,'presentationReason',s.item->>'presentationReason',
      'farmClockReality',coalesce(v_reality->t.id::text,'{}'::jsonb)||jsonb_build_object('clockDecision',jsonb_build_object('state',s.item->>'presentationState','reason',s.item->>'presentationReason')),
      'workLane',s.item->>'workLane','commitmentKind',s.item->>'commitmentKind',
      'protectedFarmMinimum',coalesce((protection.contract->>'protectedFarmMinimum')::boolean,false),
      'consequenceTier',case when coalesce(consequence.contract->>'effectiveTier','') ~ '^[1-6]$' then (consequence.contract->>'effectiveTier')::integer else null end,
      'capacityDeferrable',coalesce((deferral.contract->>'capacityDeferrable')::boolean,false),
      'placementSource',placement.placement_source,'placementReason',placement.placement_reason
    ) order by
      case coalesce(placement.day_window,atlas.worker_task_day_window_v1(t.action_key,t.task_type,t.metadata)) when 'morning' then 0 when 'afternoon' then 1 else 2 end,
      case when coalesce((protection.contract->>'protectedFarmMinimum')::boolean,false) then 0 else 1 end,
      case when coalesce(consequence.contract->>'effectiveTier','') ~ '^[1-6]$' then (consequence.contract->>'effectiveTier')::integer else 99 end,
      coalesce(placement.sort_order,atlas.worker_task_order_v1(t.action_key,t.task_type,t.metadata)),
      coalesce(nullif(s.item->>'selectionRank','')::bigint,9223372036854775807),t.title,t.id),'[]'::jsonb),
    coalesce(sum(capacity.expected_active_minutes),0)::integer
  into v_real,v_committed
  from jsonb_array_elements(v_selection) s(item)
  join atlas.tasks t on t.id=(s.item->>'taskId')::uuid
  cross join lateral atlas.task_capacity_plan_v1(t,p_day) capacity
  cross join lateral (select atlas.task_worker_day_deferral_v1(t.id,p_day) as contract) deferral
  cross join lateral (select atlas.task_protected_farm_minimum_v1(t.id,p_day) as contract) protection
  cross join lateral (select atlas.task_effective_delay_consequence_v1(t.id,p_day) as contract) consequence
  left join atlas.worker_day_task_placements placement
    on placement.farm_id=p_farm_id and placement.membership_id=p_membership_id
   and placement.task_id=t.id and placement.service_date=p_day and placement.state='placed'
  where s.item->>'presentationState'='presented';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id','task:'||t.id::text,'kind','next_up','sourceKind','task','sourceId',t.id,'taskId',t.id,
    'title',t.title,'status',t.status,'expectedActiveMinutes',capacity.expected_active_minutes,
    'physicalLoad',capacity.physical_load,
    'dayWindow',atlas.worker_task_day_window_v1(t.action_key,t.task_type,t.metadata),
    'workOrderNumber',atlas.worker_task_order_v1(t.action_key,t.task_type,t.metadata),
    'location',coalesce(nullif(t.metadata->>'display_location',''),nullif(t.metadata->>'collection_zone',''),nullif(t.metadata->>'collection_label','')),
    'nextUpReason',s.item->>'presentationReason',
    'farmClockReality',coalesce(v_reality->t.id::text,'{}'::jsonb)||jsonb_build_object('clockDecision',jsonb_build_object('state',s.item->>'presentationState','reason',s.item->>'presentationReason')),
    'deferredByCapacity',(s.item->>'presentationReason') in ('next_up_capacity','next_up_heavy_capacity'),
    'executableNow',(s.item->>'presentationReason') in ('next_up_capacity','next_up_heavy_capacity'),
    'workLane',s.item->>'workLane','commitmentKind',s.item->>'commitmentKind',
    'executionReadiness',readiness.contract,
    'protectedFarmMinimum',coalesce((protection.contract->>'protectedFarmMinimum')::boolean,false),
    'consequenceTier',case when coalesce(consequence.contract->>'effectiveTier','') ~ '^[1-6]$' then (consequence.contract->>'effectiveTier')::integer else null end,
    'capacityDeferrable',coalesce((deferral.contract->>'capacityDeferrable')::boolean,false)
  ) order by
    coalesce(nullif(s.item->>'laneOrder','')::integer,2147483647),
    coalesce(nullif(s.item->>'selectionRank','')::bigint,9223372036854775807),t.title,t.id),'[]'::jsonb)
  into v_next
  from jsonb_array_elements(v_selection) s(item)
  join atlas.tasks t on t.id=(s.item->>'taskId')::uuid
  cross join lateral atlas.task_capacity_plan_v1(t,p_day) capacity
  cross join lateral (select atlas.task_worker_day_deferral_v1(t.id,p_day) as contract) deferral
  cross join lateral (select atlas.task_execution_readiness_v1(t.id) as contract) readiness
  cross join lateral (select atlas.task_protected_farm_minimum_v1(t.id,p_day) as contract) protection
  cross join lateral (select atlas.task_effective_delay_consequence_v1(t.id,p_day) as contract) consequence
  where s.item->>'presentationState' in ('held','attention')
    and (t.due_date is null or t.due_date<=p_day)
    and s.item->>'presentationReason' in (
      'next_up_capacity','next_up_heavy_capacity','waiting_on_prerequisite','waiting_on_resource',
      'waiting_on_destination','temporal_not_ready','outside_lawful_window','awaiting_favored_sky_window',
      'work_estimate_required','consequence_resolution_required','blocked'
    );

  if p_day<=v_today then
    v_automatic:='[]'::jsonb;
  else
    for v_item in select value from jsonb_array_elements(coalesce(v_plan->'automaticWork','[]'::jsonb)) loop
      -- The old historical release queue is no longer a source of future executable Work.
      -- Keep all nonqueue automatic items and the existing day/actor/capacity gates.
      if v_item->>'sourceKind'='queue' then
        continue;
      end if;
      v_automatic:=v_automatic||jsonb_build_array(v_item);
    end loop;
  end if;

  select coalesce(sum(coalesce(nullif(a->>'expectedActiveMinutes','')::integer,0)),0)::integer
  into v_automatic_minutes
  from jsonb_array_elements(v_automatic) a;

  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,p_day);
  v_target:=case when v_capacity->>'capacityClass'='recovery'
    then coalesce((v_capacity->>'recoveryCapacityMinutes')::integer,0)
    else coalesce((v_capacity->>'plannedCapacityMinutes')::integer,0) end;

  v_plan:=jsonb_set(v_plan,'{realWork}',v_real,true);
  v_plan:=jsonb_set(v_plan,'{nextUp}',v_next,true);
  v_plan:=jsonb_set(v_plan,'{automaticWork}',v_automatic,true);
  v_plan:=jsonb_set(v_plan,'{automaticPaidMinutes}',to_jsonb(v_automatic_minutes),true);
  v_plan:=jsonb_set(v_plan,'{committedPaidMinutes}',to_jsonb(v_committed),true);
  v_plan:=jsonb_set(v_plan,'{paidTargetMinutes}',to_jsonb(v_target),true);
  v_plan:=jsonb_set(v_plan,'{remainingPaidMinutes}',to_jsonb(greatest(v_target-v_committed-v_automatic_minutes,0)),true);
  v_plan:=jsonb_set(v_plan,'{selectionContractVersion}',to_jsonb('worker_day_selection_v3_single_snapshot'::text),true);
  return v_plan;
end;
$function$;

DO $atlas_projection_no_loss$
DECLARE v_oid oid:=to_regprocedure('atlas.worker_day_selection_overlay_live_v1(uuid,uuid,date,jsonb)');
        v_body text;
BEGIN
  IF v_oid IS NULL THEN RAISE EXCEPTION 'Worker Day projection signature lost'; END IF;
  v_body:=pg_get_functiondef(v_oid);
  IF position('task_release_queue_items' in lower(v_body))>0
     OR position('v_queue_task' in lower(v_body))>0
     OR position('sourceKind' in v_body)=0
     OR position('continue;' in v_body)=0
     OR position('worker_week_day_capacity_v1' in v_body)=0
  THEN RAISE EXCEPTION 'Worker Day projection old queue dependency or current Work gate mismatch'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_proc p JOIN atlas_worker_day_queue_projection_before b ON b.oid=p.oid
    WHERE p.oid=v_oid AND p.proowner=b.proowner AND p.proacl IS NOT DISTINCT FROM b.proacl
      AND p.prosecdef=b.prosecdef AND p.proconfig IS NOT DISTINCT FROM b.proconfig
  ) THEN RAISE EXCEPTION 'Worker Day projection owner/ACL/SECURITY/search_path changed'; END IF;
  IF (SELECT count(*)::text FROM atlas.task_release_queue_items)
       IS DISTINCT FROM current_setting('atlas.projection_pre_queue_count')
     OR (SELECT md5(coalesce(string_agg(md5(to_jsonb(q)::text),',' ORDER BY q.id::text),''))
         FROM atlas.task_release_queue_items q)
       IS DISTINCT FROM current_setting('atlas.projection_pre_queue_hash')
     OR (SELECT count(*)::text FROM atlas.work_items)
       IS DISTINCT FROM current_setting('atlas.projection_pre_work')
     OR (SELECT count(*)::text FROM atlas.tasks)
       IS DISTINCT FROM current_setting('atlas.projection_pre_tasks')
     OR (SELECT count(*)::text FROM atlas.planned_work_occurrences)
       IS DISTINCT FROM current_setting('atlas.projection_pre_occurrences')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
       IS DISTINCT FROM current_setting('atlas.projection_pre_requirements')
  THEN RAISE EXCEPTION 'Worker Day projection changed historical or canonical rows'; END IF;
  IF (SELECT count(*)::integer FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname IN ('atlas','public') AND p.prokind IN ('f','p')
       AND strpos(lower(pg_get_functiondef(p.oid)),'task_release_queue_items')>0)
     <> current_setting('atlas.projection_pre_queue_source_count')::integer-1
  THEN RAISE EXCEPTION 'Worker Day projection unexpected queue-source reference delta'; END IF;
END $atlas_projection_no_loss$;
COMMIT;
