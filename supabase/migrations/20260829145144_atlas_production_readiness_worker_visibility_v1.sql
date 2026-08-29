create or replace function atlas.prepare_transplant_readiness_day_cue_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_governed_production boolean;
begin
  if new.task_type='transplant_readiness'
     and new.status='open'
     and new.assigned_membership_id is not null then
    v_governed_production := coalesce(new.metadata->>'production_work_key','')='transplant-readiness'
      and coalesce(new.metadata->>'structured_result_required','false')='true'
      and nullif(new.metadata->>'production_lot_id','') is not null
      and nullif(new.metadata->>'production_tray_batch_id','') is not null;

    if v_governed_production then
      new.visibility_scope:='assigned_worker';
      new.metadata:=coalesce(new.metadata,'{}'::jsonb)
        || jsonb_build_object(
          'observation_delivery_mode','task_card',
          'readiness_target','field_transplant',
          'task_style','transplant_readiness'
        );
    else
      new.visibility_scope:='system_internal';
      new.metadata:=coalesce(new.metadata,'{}'::jsonb)
        || jsonb_build_object(
          'observation_delivery_mode','day_cue',
          'readiness_target','field_transplant',
          'task_style','transplant_readiness'
        );
    end if;
  end if;
  return new;
end;
$function$;

update atlas.tasks
set visibility_scope='assigned_worker',
    metadata=coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object(
        'observation_delivery_mode','task_card',
        'readiness_visibility_reconciled_by','atlas_production_readiness_worker_visibility_v1'
      ),
    updated_at=now()
where task_type='transplant_readiness'
  and status in ('open','blocked')
  and assigned_membership_id is not null
  and coalesce(metadata->>'production_work_key','')='transplant-readiness'
  and coalesce(metadata->>'structured_result_required','false')='true'
  and nullif(metadata->>'production_lot_id','') is not null
  and nullif(metadata->>'production_tray_batch_id','') is not null;

comment on function atlas.prepare_transplant_readiness_day_cue_v1() is 'Legacy readiness remains an internal day cue. Governed production readiness with an assigned member and structured biological result remains an assigned worker task card so the worker result membrane can execute.';