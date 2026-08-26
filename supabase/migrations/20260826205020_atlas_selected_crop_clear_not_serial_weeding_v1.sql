do $$
declare
  v_farm_id uuid;
  v_occurrence_id uuid;
  v_task_id uuid;
begin
  select f.id into v_farm_id
  from atlas.farms f
  where f.stable_key='elm_farm';

  if v_farm_id is null then
    raise exception 'Elm Farm not found.';
  end if;

  select o.id into v_occurrence_id
  from atlas.planned_work_occurrences o
  where o.farm_id=v_farm_id
    and coalesce(o.task_payload->>'task_type','')='crop_clear'
    and coalesce(o.task_payload->'metadata'->>'crop_profile_stable_key','')='muncher_cucumber'
    and lower(o.title) like '%muncher cucumber%'
  order by o.created_at desc
  limit 1;

  if v_occurrence_id is null then
    raise exception 'Muncher cucumber clear occurrence not found.';
  end if;

  select t.id into v_task_id
  from atlas.tasks t
  where t.farm_id=v_farm_id
    and t.planned_occurrence_id=v_occurrence_id
    and t.task_type='crop_clear'
  order by t.created_at desc
  limit 1;

  if v_task_id is null then
    raise exception 'Muncher cucumber clear task not found.';
  end if;

  update atlas.task_release_queue_items qi
  set state='skipped',
      task_id=null,
      updated_at=now(),
      metadata=coalesce(qi.metadata,'{}'::jsonb)||jsonb_build_object(
        'skipped_reason','Card family is bed-work presentation; selected-crop Clear is not ordinary serial weeding.',
        'classification_repaired_at',now(),
        'classification_repair','selected_crop_clear_not_serial_weeding_v1'
      )
  where qi.farm_id=v_farm_id
    and qi.queue_key='anna_weeding_rotation'
    and qi.planned_occurrence_id=v_occurrence_id
    and qi.state in ('active','queued');

  update atlas.tasks t
  set status='open',
      action_key='clear',
      completed_at=null,
      blocker_text=null,
      due_date=(now() at time zone 'America/Chicago')::date,
      updated_at=now(),
      metadata=(coalesce(t.metadata,'{}'::jsonb)
        - 'release_queue_key'
        - 'release_queue_position'
        - 'release_queue_policy'
        - 'weed_serial_gate'
        - 'serial_weeding_retracted'
        - 'serial_weeding_retracted_at'
        - 'serial_weeding_queue_key'
        - 'archived_reason')
        || jsonb_build_object(
          'canonical_card_family','weed',
          'bed_work_action','clear',
          'serial_queue_bypass',true,
          'classification_repair','selected_crop_clear_not_serial_weeding_v1',
          'classification_repaired_at',now()
        )
  where t.id=v_task_id;

  update atlas.planned_work_occurrences o
  set state='released',
      planned_due_date=(now() at time zone 'America/Chicago')::date,
      not_before_date=(now() at time zone 'America/Chicago')::date,
      gate_satisfied_at=coalesce(o.gate_satisfied_at,now()),
      released_at=coalesce(o.released_at,now()),
      released_task_id=v_task_id,
      updated_at=now(),
      task_payload=jsonb_set(
        jsonb_set(
          coalesce(o.task_payload,'{}'::jsonb),
          '{action_key}',to_jsonb('clear'::text),true
        ),
        '{metadata}',
        (coalesce(o.task_payload->'metadata','{}'::jsonb)-'serial_queue_state')
          || jsonb_build_object(
            'canonical_card_family','weed',
            'bed_work_action','clear',
            'serial_queue_bypass',true
          ),
        true
      ),
      metadata=(coalesce(o.metadata,'{}'::jsonb)
        - 'serialWeedingQueued'
        - 'serialWeedingQueuedAt'
        - 'serialWeedingQueueKey'
        - 'calendar_commitment_kind'
        - 'queue_original_planned_due_date')
        || jsonb_build_object(
          'classificationRepair','selected_crop_clear_not_serial_weeding_v1',
          'classificationRepairedAt',now(),
          'releasedLane','bed_work_clear'
        )
  where o.id=v_occurrence_id;

  perform atlas.sync_task_release_queue_summary_v1(v_farm_id,'anna_weeding_rotation');
end $$;