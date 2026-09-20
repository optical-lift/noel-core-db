-- Planned Work Occurrence execution-carrier terminality reconciliation v1.
-- Historical exact-pair repair only. Current runtime terminalization already exists.

begin;

create or replace view atlas.planned_occurrence_execution_carrier_terminality_audit_v1 as
select
  pwo.id as occurrence_id,
  pwo.farm_id,
  pwo.occurrence_key,
  pwo.title as occurrence_title,
  pwo.state as occurrence_state,
  pwo.released_task_id,
  t.status as task_status,
  t.completed_at as task_completed_at,
  t.planned_occurrence_id as task_planned_occurrence_id,
  case
    when pwo.state='released'
      and t.status='done'
      and t.planned_occurrence_id=pwo.id
      then 'released_occurrence_done_task_exact_pair'
    when pwo.state='released'
      and t.status='archived'
      and t.planned_occurrence_id=pwo.id
      then 'released_occurrence_archived_task_requires_classification'
    when pwo.state='released'
      and t.status='skipped'
      and t.planned_occurrence_id=pwo.id
      then 'released_occurrence_skipped_task_requires_classification'
    else 'execution_carrier_terminality_contradiction'
  end as issue_key,
  case
    when pwo.state='released'
      and t.status='done'
      and t.planned_occurrence_id=pwo.id
      then 'Deterministically reconcilable as occurrence completed. This repairs execution-carrier terminality only and does not establish domain result acceptance.'
    when pwo.state='released'
      and t.status in ('archived','skipped')
      and t.planned_occurrence_id=pwo.id
      then 'Do not infer occurrence cancellation/completion from historical administrative task terminality without separately classified semantics.'
    else 'Inspect exact occurrence/task custody before repair.'
  end as recovery_boundary
from atlas.planned_work_occurrences pwo
join atlas.tasks t
  on t.id=pwo.released_task_id
where pwo.state='released'
  and t.status in ('done','archived','skipped');

revoke all on atlas.planned_occurrence_execution_carrier_terminality_audit_v1
from public,anon,authenticated;
grant select on atlas.planned_occurrence_execution_carrier_terminality_audit_v1
to service_role;

comment on view atlas.planned_occurrence_execution_carrier_terminality_audit_v1 is
'Internal audit of released occurrence / terminal task contradictions. Exact released+done custody pairs are deterministically reconcilable as completed execution carriers. Archived/skipped historical cases remain classification work and are not automatically repaired.';

with exact_done_pairs as (
  select
    pwo.id as occurrence_id,
    t.id as task_id,
    t.completed_at
  from atlas.planned_work_occurrences pwo
  join atlas.tasks t
    on t.id=pwo.released_task_id
   and t.planned_occurrence_id=pwo.id
  where pwo.state='released'
    and t.status='done'
)
update atlas.planned_work_occurrences pwo
set
  state='completed',
  updated_at=now(),
  metadata=coalesce(pwo.metadata,'{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object(
      'historicalTerminalityReconciledBy',
        'planned_occurrence_execution_carrier_terminality_reconciliation_v1',
      'historicalTerminalTaskId',pairs.task_id,
      'historicalTerminalTaskStatus','done',
      'historicalTaskCompletedAt',pairs.completed_at,
      'historicalTerminalityReconciledAt',now(),
      'domainResultAcceptanceInferred',false
    ))
from exact_done_pairs pairs
where pwo.id=pairs.occurrence_id;

do $verification$
begin
  if exists(
    select 1
    from atlas.planned_work_occurrences pwo
    join atlas.tasks t
      on t.id=pwo.released_task_id
     and t.planned_occurrence_id=pwo.id
    where pwo.state='released'
      and t.status='done'
  ) then
    raise exception 'Exact released occurrence / done task contradictions remain after reconciliation.'
      using errcode='55000';
  end if;

  if has_table_privilege(
       'authenticated',
       'atlas.planned_occurrence_execution_carrier_terminality_audit_v1',
       'SELECT'
     )
     or has_table_privilege(
       'anon',
       'atlas.planned_occurrence_execution_carrier_terminality_audit_v1',
       'SELECT'
     ) then
    raise exception 'Occurrence terminality audit leaked to browser roles.';
  end if;

  if not has_table_privilege(
       'service_role',
       'atlas.planned_occurrence_execution_carrier_terminality_audit_v1',
       'SELECT'
     ) then
    raise exception 'Occurrence terminality audit unavailable to service_role.';
  end if;

  if pg_get_functiondef(
       'atlas.release_after_task_terminal_v1()'::regprocedure
     ) not ilike '%planned_work_occurrences%'
     or pg_get_functiondef(
       'atlas.release_after_task_terminal_v1()'::regprocedure
     ) not ilike '%new.planned_occurrence_id%'
  then
    raise exception 'Current runtime occurrence terminalization contract is absent.';
  end if;
end;
$verification$;

commit;
