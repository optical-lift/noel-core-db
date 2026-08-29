alter table atlas.production_successions
  add column if not exists sow_occurrence_id uuid references atlas.planned_work_occurrences(id) on delete set null;

create index if not exists production_successions_sow_occurrence_idx
  on atlas.production_successions(sow_occurrence_id)
  where sow_occurrence_id is not null;

create or replace function atlas.sync_production_succession_task_pointer_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if new.planned_occurrence_id is not null then
    update atlas.production_successions
    set sow_task_id=new.id,updated_at=now()
    where sow_occurrence_id=new.planned_occurrence_id
      and state in ('upcoming','in_window','late');
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_sync_production_succession_task_pointer_v1 on atlas.tasks;
create trigger trg_sync_production_succession_task_pointer_v1
after insert on atlas.tasks
for each row execute function atlas.sync_production_succession_task_pointer_v1();

create or replace function atlas.cancel_production_succession_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if old.sow_occurrence_id is not null and (tg_op='DELETE' or (tg_op='UPDATE' and new.state='skipped' and old.state is distinct from 'skipped')) then
    update atlas.planned_work_occurrences
    set state=case when state='completed' then state else 'cancelled' end,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'cancelledBy','production_succession_state',
          'cancelledAt',now(),
          'productionSuccessionId',old.id,
          'reason',case when tg_op='DELETE' then 'succession_removed' else 'succession_skipped' end
        ),updated_at=now()
    where id=old.sow_occurrence_id and state not in ('completed','cancelled');
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$function$;

drop trigger if exists trg_cancel_production_succession_occurrence_v1 on atlas.production_successions;
create trigger trg_cancel_production_succession_occurrence_v1
before update of state or delete on atlas.production_successions
for each row execute function atlas.cancel_production_succession_occurrence_v1();

comment on column atlas.production_successions.sow_occurrence_id is
'Canonical planned-work occurrence for this succession sowing commitment. sow_task_id is populated only when the occurrence materializes.';