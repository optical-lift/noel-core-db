-- Atlas Weekly Harvest -> Owner review handoff v1
--
-- Purpose:
--   Weekly Harvest flower custody must stop at Owner review. A flower observation
--   may never expose Flower Preparation by itself. Only the completed Weekly
--   Harvest card may create one Owner review and one hidden preparation occurrence.
--
-- Deliberate boundary:
--   This migration does not unlock record_flower_preparation_directive_v1 and does
--   not release the hidden worker occurrence. Owner direction remains the only
--   future release authority.

-- Existing Bell/notification functions already recognize owner_decision, but the
-- journal event CHECK predates that event kind. Align the table contract to the
-- already-deployed Bell contract so a governed Owner handoff can be recorded.
alter table atlas.journal_event_index
  drop constraint journal_event_index_event_kind_check;

alter table atlas.journal_event_index
  add constraint journal_event_index_event_kind_check
  check (event_kind = any (array[
    'task_result'::text,
    'field_log'::text,
    'field_action'::text,
    'observation'::text,
    'maintenance_result'::text,
    'state_change'::text,
    'crop_cycle_change'::text,
    'production_change'::text,
    'trail_evidence'::text,
    'unlock'::text,
    'rhythm_warning'::text,
    'rhythm_due'::text,
    'rhythm_failure'::text,
    'rhythm_recovery'::text,
    'migration'::text,
    'owner_action'::text,
    'owner_decision'::text,
    'system_event'::text
  ]));

-- Preserve the legacy automatic preparation behavior for non-Weekly flower
-- harvest sources, but explicitly suppress it for the governed Weekly Harvest.
create or replace function atlas.queue_flower_preparation_after_harvest_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_task_series_key text;
begin
  select t.task_series_key
  into v_task_series_key
  from atlas.tasks t
  where t.id = new.task_id;

  if v_task_series_key = 'anna_harvest_thursday_weekly' then
    return new;
  end if;

  perform atlas.ensure_flower_preparation_task_v1(
    new.batch_id,
    new.id,
    new.recorded_by_membership_id,
    new.observed_date
  );

  return new;
end;
$function$;

comment on function atlas.queue_flower_preparation_after_harvest_v1() is
  'Queues legacy Flower Preparation for non-Weekly flower harvest observations. Weekly Harvest observations stop at custody until the whole Harvest card completes and Owner review is created.';

create or replace function atlas.ensure_weekly_harvest_owner_review_handoff_v1(
  p_harvest_task_id uuid,
  p_transition_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_transition atlas.task_transitions%rowtype;
  v_batch atlas.flower_harvest_batches%rowtype;
  v_worker atlas.farm_memberships%rowtype;
  v_owner atlas.farm_memberships%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_review atlas.tasks%rowtype;
  v_relation jsonb := '{}'::jsonb;
  v_occurrence_id uuid;
  v_event_id uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_field_observation_count integer := 0;
  v_external_line_count integer := 0;
begin
  select *
  into v_task
  from atlas.tasks
  where id = p_harvest_task_id
  for update;

  if v_task.id is null then
    raise exception 'Weekly Harvest task was not found.' using errcode = 'P0002';
  end if;

  if v_task.task_type <> 'harvest'
     or v_task.task_series_key <> 'anna_harvest_thursday_weekly' then
    return jsonb_build_object(
      'action', 'not_weekly_harvest',
      'harvestTaskId', v_task.id
    );
  end if;

  if v_task.status <> 'done' then
    return jsonb_build_object(
      'action', 'harvest_not_done',
      'harvestTaskId', v_task.id,
      'status', v_task.status
    );
  end if;

  if p_transition_id is not null then
    select *
    into v_transition
    from atlas.task_transitions tt
    where tt.id = p_transition_id
      and tt.task_id = v_task.id;

    if v_transition.id is null
       or v_transition.transition <> 'done'
       or v_transition.next_status <> 'done' then
      raise exception 'Weekly Harvest handoff requires its canonical done transition.' using errcode = '22023';
    end if;
  end if;

  select *
  into v_batch
  from atlas.flower_harvest_batches b
  where b.farm_id = v_task.farm_id
    and b.batch_key = 'weekly-harvest:' || v_task.id::text
  order by b.created_at
  limit 1
  for update;

  if v_batch.id is null then
    return jsonb_build_object(
      'action', 'no_flower_custody',
      'harvestTaskId', v_task.id
    );
  end if;

  select count(*)::integer
  into v_field_observation_count
  from atlas.flower_harvest_bucket_observations h
  where h.batch_id = v_batch.id;

  select count(*)::integer
  into v_external_line_count
  from atlas.flower_external_intakes i
  join atlas.flower_external_intake_lines l on l.intake_id = i.id
  where i.harvest_batch_id = v_batch.id;

  if v_field_observation_count = 0 and v_external_line_count = 0 then
    return jsonb_build_object(
      'action', 'empty_flower_custody',
      'harvestTaskId', v_task.id,
      'harvestBatchId', v_batch.id
    );
  end if;

  select *
  into v_worker
  from atlas.farm_memberships m
  where m.id = v_task.assigned_membership_id
    and m.farm_id = v_task.farm_id
    and m.active;

  if v_worker.id is null then
    select *
    into v_worker
    from atlas.farm_memberships m
    where m.id = v_batch.recorded_by_membership_id
      and m.farm_id = v_task.farm_id
      and m.active;
  end if;

  if v_worker.id is null then
    raise exception 'Completed Weekly Harvest has no active worker to receive the later preparation continuation.' using errcode = '22023';
  end if;

  select *
  into v_owner
  from atlas.farm_memberships m
  where m.farm_id = v_task.farm_id
    and m.active
    and m.role in ('owner', 'manager')
  order by case when m.role = 'owner' then 0 else 1 end, m.created_at
  limit 1;

  if v_owner.id is null then
    raise exception 'Completed Weekly Harvest has no active Owner or manager for harvest direction.' using errcode = '22023';
  end if;

  -- If an old path already created/released Flower Preparation, do not quietly
  -- create a second governed path. This is an invariant breach and should block
  -- the completion transaction rather than hide the exposure.
  if exists (
    select 1
    from atlas.tasks t
    where t.farm_id = v_task.farm_id
      and t.task_type = 'flower_preparation'
      and t.metadata->>'flower_harvest_batch_id' = v_batch.id::text
      and t.status in ('open', 'blocked')
  ) then
    raise exception 'Weekly Harvest Flower Preparation was already exposed before Owner review.' using errcode = '55000';
  end if;

  select *
  into v_occurrence
  from atlas.planned_work_occurrences o
  where o.farm_id = v_task.farm_id
    and o.source_kind = 'flower_harvest_batch'
    and o.source_id = v_batch.id
    and coalesce(o.task_payload->>'task_type', '') = 'flower_preparation'
  order by o.created_at
  limit 1
  for update;

  if v_occurrence.id is not null
     and (v_occurrence.released_task_id is not null
          or v_occurrence.gate_satisfied_at is not null
          or v_occurrence.state not in ('planned', 'failed')) then
    raise exception 'Weekly Harvest Flower Preparation occurrence was already exposed or satisfied before Owner review.' using errcode = '55000';
  end if;

  if v_occurrence.id is null then
    select jsonb_build_object(
      'task_crop_cycles',
      coalesce(
        jsonb_agg(
          distinct jsonb_build_object(
            'crop_cycle_id', h.crop_cycle_id,
            'role', 'preserves',
            'confidence', 'confirmed',
            'source', 'weekly_harvest_owner_review_handoff_v1'
          )
        ) filter (where h.crop_cycle_id is not null),
        '[]'::jsonb
      )
    )
    into v_relation
    from atlas.flower_harvest_bucket_observations h
    where h.batch_id = v_batch.id;

    v_occurrence_id := atlas.plan_work_occurrence_v1(
      p_farm_id => v_task.farm_id,
      p_definition_key => 'flower-preparation:' || v_batch.id::text,
      p_policy_key => 'flower-preparation:' || v_batch.id::text || ':owner-directed',
      p_occurrence_key => 'flower-preparation-owner-directed:' || v_batch.id::text,
      p_title => 'Condition + Bunch',
      p_task_type => 'flower_preparation',
      p_due_date => v_today,
      p_source_kind => 'flower_harvest_batch',
      p_source_id => v_batch.id,
      p_gate_type => 'event',
      p_horizon_days => 0,
      p_maximum_active_instances => 1,
      p_task_payload => jsonb_build_object(
        'organization_id', v_task.organization_id,
        'farm_id', v_task.farm_id,
        'title', 'Condition + Bunch',
        'task_type', 'flower_preparation',
        'status', 'open',
        'priority', 'high',
        'generated_from', 'flower_harvest_batch',
        'generated_from_id', v_batch.id,
        'note', 'Condition + bundle for pre-sales',
        'action_key', 'prepare',
        'work_class', 'postharvest',
        'task_series_key', 'flower-preparation:' || v_batch.id::text,
        'engine_instance_key', 'flower-preparation-owner-directed:' || v_batch.id::text,
        'visibility_scope', 'assigned_worker',
        'assigned_membership_id', v_worker.id,
        'assigned_user_id', v_worker.user_id,
        'origin_kind', 'generated',
        'metadata', jsonb_build_object(
          'task_style', 'flower_preparation',
          'structured_result_required', true,
          'flower_harvest_batch_id', v_batch.id,
          'source_harvest_task_id', v_task.id,
          'requires_owner_preparation_directive', true,
          'display_action', 'Condition + bunch',
          'display_subject', 'Pre-sale flowers',
          'display_detail', 'Orders + final tally',
          'collection_zone', 'Post-harvest',
          'time_claims_physical_condition', false
        )
      ),
      p_relation_payload => coalesce(v_relation, '{}'::jsonb),
      p_gate_config => jsonb_build_object(
        'engine', 'task_dependency_clock_v1',
        'requiresOwnerDirective', true,
        'requiresHarvestCompletion', true,
        'timeClaimsPhysicalCondition', false
      ),
      p_not_before_date => v_today,
      p_metadata => jsonb_build_object(
        'flowerHarvestBatchId', v_batch.id,
        'sourceHarvestTaskId', v_task.id,
        'ownerDirectiveRequired', true,
        'hiddenUntilOwnerDirective', true
      )
    );

    select *
    into v_occurrence
    from atlas.planned_work_occurrences o
    where o.id = v_occurrence_id
    for update;
  else
    v_occurrence_id := v_occurrence.id;
  end if;

  if v_occurrence.released_task_id is not null
     or v_occurrence.gate_satisfied_at is not null
     or v_occurrence.state not in ('planned', 'failed') then
    raise exception 'Owner-directed preparation occurrence is not hidden.' using errcode = '55000';
  end if;

  select *
  into v_review
  from atlas.tasks t
  where t.farm_id = v_task.farm_id
    and t.metadata->>'task_style' = 'flower_preparation_directive_review'
    and t.metadata->>'flower_harvest_batch_id' = v_batch.id::text
  order by t.created_at
  limit 1
  for update;

  if v_review.id is null then
    insert into atlas.tasks(
      organization_id,
      farm_id,
      title,
      task_type,
      status,
      priority,
      due_date,
      generated_from,
      generated_from_id,
      note,
      metadata,
      action_key,
      work_class,
      task_series_key,
      engine_instance_key,
      visibility_scope,
      assigned_membership_id,
      assigned_user_id,
      origin_kind
    ) values (
      v_task.organization_id,
      v_task.farm_id,
      'Direct Harvest',
      'owner_decision',
      'open',
      'high',
      v_today,
      'flower_harvest_batch',
      v_batch.id,
      'Harvest complete. Set the pre-sale pack-out.',
      jsonb_build_object(
        'task_key', 'flower_preparation_directive_review_' || v_batch.id::text,
        'task_style', 'flower_preparation_directive_review',
        'flower_preparation_directive_review_version', 1,
        'structured_result_required', true,
        'owner_task', true,
        'anna_task', false,
        'assigned_to', 'Owner',
        'flower_harvest_batch_id', v_batch.id,
        'flower_preparation_occurrence_id', v_occurrence.id,
        'source_harvest_task_id', v_task.id,
        'field_harvest_observation_count', v_field_observation_count,
        'external_intake_line_count', v_external_line_count,
        'display_action', 'Direct',
        'display_subject', 'Harvest',
        'display_detail', 'Pre-sale plan',
        'collection_zone', 'Owner',
        'time_claims_physical_condition', false
      ),
      'decide',
      'owner_decision',
      'flower-preparation-directive-review:' || v_batch.id::text,
      'flower-preparation-directive-review:' || v_batch.id::text,
      'owner',
      v_owner.id,
      v_owner.user_id,
      'generated'
    )
    returning * into v_review;
  end if;

  if v_review.status not in ('open', 'blocked') then
    raise exception 'Harvest direction task already exists but is not open.' using errcode = '55000';
  end if;

  if v_review.metadata->>'flower_preparation_occurrence_id' is distinct from v_occurrence.id::text then
    raise exception 'Harvest direction task points to a different preparation occurrence.' using errcode = '55000';
  end if;

  update atlas.flower_harvest_batches
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'ownerReviewRequired', true,
        'ownerReviewTaskId', v_review.id,
        'ownerDirectedPreparationOccurrenceId', v_occurrence.id,
        'weeklyHarvestHandoffVersion', 1
      ),
      updated_at = now()
  where id = v_batch.id;

  v_event_id := atlas.upsert_journal_event_v1(
    p_organization_id => v_task.organization_id,
    p_farm_id => v_task.farm_id,
    p_event_key => 'flower-preparation-directive-review:' || v_batch.id::text,
    p_event_kind => 'owner_decision',
    p_source_kind => 'flower_harvest_batch',
    p_source_id => v_batch.id,
    p_source_event => 'harvest_completed',
    p_occurred_at => coalesce(v_transition.created_at, now()),
    p_journal_date => v_today,
    p_title => 'Direct Harvest',
    p_detail => 'Harvest is complete. Set the pre-sale pack-out.',
    p_visibility_scope => 'owner',
    p_importance => 'attention',
    p_actor_user_id => v_transition.actor_user_id,
    p_assigned_user_id => v_owner.user_id,
    p_task_id => v_review.id,
    p_payload => jsonb_build_object(
      'contractVersion', 'weekly_harvest_owner_review_handoff_v1',
      'harvestTaskId', v_task.id,
      'harvestBatchId', v_batch.id,
      'ownerReviewTaskId', v_review.id,
      'preparationOccurrenceId', v_occurrence.id,
      'fieldHarvestObservationCount', v_field_observation_count,
      'externalIntakeLineCount', v_external_line_count,
      'workerPreparationReleased', false
    ),
    p_provenance => jsonb_build_object(
      'source', 'weekly_harvest_completion',
      'sourceTransitionId', v_transition.id,
      'truthBoundary', 'owner_direction_required_before_worker_preparation'
    )
  );

  return jsonb_build_object(
    'action', 'owner_review_ready',
    'harvestTaskId', v_task.id,
    'harvestBatchId', v_batch.id,
    'ownerReviewTaskId', v_review.id,
    'preparationOccurrenceId', v_occurrence.id,
    'preparationTaskId', v_occurrence.released_task_id,
    'journalEventId', v_event_id,
    'fieldHarvestObservationCount', v_field_observation_count,
    'externalIntakeLineCount', v_external_line_count,
    'workerPreparationReleased', false
  );
end;
$function$;

revoke all on function atlas.ensure_weekly_harvest_owner_review_handoff_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function atlas.ensure_weekly_harvest_owner_review_handoff_v1(uuid, uuid) to service_role;

comment on function atlas.ensure_weekly_harvest_owner_review_handoff_v1(uuid, uuid) is
  'Creates one Owner Direct Harvest task plus one unsatisfied/hidden Flower Preparation occurrence after a completed Weekly Harvest with flower custody. It never signals or releases the worker occurrence.';

create or replace function atlas.queue_weekly_harvest_owner_review_after_completion_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_series_key text;
begin
  if new.transition <> 'done' or new.next_status <> 'done' then
    return new;
  end if;

  select t.task_series_key
  into v_series_key
  from atlas.tasks t
  where t.id = new.task_id;

  if v_series_key = 'anna_harvest_thursday_weekly' then
    perform atlas.ensure_weekly_harvest_owner_review_handoff_v1(new.task_id, new.id);
  end if;

  return new;
end;
$function$;

revoke all on function atlas.queue_weekly_harvest_owner_review_after_completion_v1() from public;

drop trigger if exists weekly_harvest_owner_review_after_completion_v1 on atlas.task_transitions;
create trigger weekly_harvest_owner_review_after_completion_v1
after insert on atlas.task_transitions
for each row
execute function atlas.queue_weekly_harvest_owner_review_after_completion_v1();
