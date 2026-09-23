-- Recurrence realization conflict detection v1
-- A rule/exception may change expected schedule without changing canonical
-- occurrence truth. Preserve both and surface the disagreement explicitly.

alter table atlas.organization_recurrence_instances
  drop constraint if exists organization_recurrence_instances_realization_state_v1;

alter table atlas.organization_recurrence_instances
  add constraint organization_recurrence_instances_realization_state_v1
  check (realization_state in ('unmaterialized','materialized','cancelled','conflict'));

create or replace function atlas.reconcile_recurrence_instance_realization_v1(
  p_organization_id uuid,
  p_recurrence_rule_id uuid,
  p_start_date date,
  p_end_date date
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_count integer;
begin
  update atlas.organization_recurrence_instances i
  set realization_state=case
        when i.occurrence_binding_id is null then 'unmaterialized'
        when o.status='cancelled' then 'cancelled'
        when o.start_at is distinct from i.expected_start_at then 'conflict'
        when o.end_at is distinct from i.expected_end_at then 'conflict'
        else 'materialized'
      end,
      updated_at=now()
  from atlas.organization_occurrence_bindings b
  join local_intel.occurrences o on o.id=b.occurrence_id
  where i.organization_id=p_organization_id
    and i.recurrence_rule_id=p_recurrence_rule_id
    and i.source_local_date between p_start_date and p_end_date
    and i.occurrence_binding_id=b.id
    and b.organization_id=i.organization_id;

  get diagnostics v_count=row_count;
  return v_count;
end
$function$;

revoke all on function atlas.reconcile_recurrence_instance_realization_v1(uuid,uuid,date,date)
  from public,anon,authenticated;
grant execute on function atlas.reconcile_recurrence_instance_realization_v1(uuid,uuid,date,date)
  to service_role;

comment on function atlas.reconcile_recurrence_instance_realization_v1(uuid,uuid,date,date) is
  'Compares Organization recurrence expectation to attached canonical occurrence reality. Marks conflict rather than rewriting either side when dates/times disagree.';
