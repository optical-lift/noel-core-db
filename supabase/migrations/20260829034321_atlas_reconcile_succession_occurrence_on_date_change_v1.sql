create or replace function atlas.reconcile_production_succession_date_change_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
begin
  if new.state in ('upcoming','in_window','late') then
    perform atlas.ensure_production_succession_sow_occurrence_v1(new.id,null,null);
  elsif new.sow_occurrence_id is not null then
    update atlas.planned_work_occurrences
    set state=case when state='completed' then state else 'cancelled' end,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'cancelledBy','production_succession_date_reconciler',
          'cancelledAt',now(),
          'productionSuccessionId',new.id,
          'reason','succession_no_longer_requires_sowing'
        ),updated_at=now()
    where id=new.sow_occurrence_id and state not in ('completed','cancelled');
  end if;
  return new;
end;
$function$;
revoke all on function atlas.reconcile_production_succession_date_change_v1() from public,anon,authenticated,service_role;
grant execute on function atlas.reconcile_production_succession_date_change_v1() to postgres;

drop trigger if exists trg_reconcile_production_succession_date_change_v1 on atlas.production_successions;
create trigger trg_reconcile_production_succession_date_change_v1
after update of planned_window_start,planned_window_end,late_window_end,skip_after_date on atlas.production_successions
for each row
when (
  old.planned_window_start is distinct from new.planned_window_start
  or old.planned_window_end is distinct from new.planned_window_end
  or old.late_window_end is distinct from new.late_window_end
  or old.skip_after_date is distinct from new.skip_after_date
)
execute function atlas.reconcile_production_succession_date_change_v1();

comment on function atlas.reconcile_production_succession_date_change_v1() is 'Keeps the succession sow planned occurrence synchronized with the production succession plan whenever its governed sow-window dates change.';