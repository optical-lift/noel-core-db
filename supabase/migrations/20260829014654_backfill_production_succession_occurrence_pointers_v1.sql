update atlas.production_successions ps
set sow_occurrence_id=t.planned_occurrence_id,
    metadata=coalesce(ps.metadata,'{}'::jsonb)||jsonb_build_object(
      'sow_occurrence_id',t.planned_occurrence_id,
      'sow_occurrence_backfilled_at',now(),
      'sow_occurrence_backfill_source','existing_sow_task'
    ),
    updated_at=now()
from atlas.tasks t
where ps.sow_task_id=t.id
  and ps.sow_occurrence_id is null
  and t.planned_occurrence_id is not null;

comment on trigger trg_sync_production_succession_task_pointer_v1 on atlas.tasks is
'When a planned succession sowing occurrence materializes, backfill the concrete task pointer onto production_successions.sow_task_id.';