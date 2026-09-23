-- Automatic recurrence realization state v1
-- Keep recurrence expectation and canonical occurrence reality distinct and
-- automatically surface disagreement as realization_state='conflict'.

create or replace function atlas.guard_recurrence_instance_realization_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_status text;
  v_start_at timestamptz;
  v_end_at timestamptz;
begin
  if new.occurrence_binding_id is null then
    new.realization_state='unmaterialized';
    return new;
  end if;

  select o.status,o.start_at,o.end_at
  into v_status,v_start_at,v_end_at
  from atlas.organization_occurrence_bindings b
  join local_intel.occurrences o on o.id=b.occurrence_id
  where b.id=new.occurrence_binding_id
    and b.organization_id=new.organization_id
    and b.binding_state='active';

  if v_status is null then
    raise exception 'Attached recurrence occurrence binding is outside organization or inactive.'
      using errcode='42501';
  end if;

  new.realization_state:=case
    when v_status='cancelled' then 'cancelled'
    when v_start_at is distinct from new.expected_start_at then 'conflict'
    when v_end_at is distinct from new.expected_end_at then 'conflict'
    else 'materialized'
  end;

  return new;
end
$function$;

drop trigger if exists recurrence_instance_realization_guard_v1
  on atlas.organization_recurrence_instances;

create trigger recurrence_instance_realization_guard_v1
before insert or update of expected_start_at,expected_end_at,occurrence_binding_id,organization_id
on atlas.organization_recurrence_instances
for each row
execute function atlas.guard_recurrence_instance_realization_v1();

comment on trigger recurrence_instance_realization_guard_v1
  on atlas.organization_recurrence_instances is
  'Automatically classifies attached canonical occurrence as materialized, cancelled, or conflict without rewriting canonical truth or recurrence expectation.';
