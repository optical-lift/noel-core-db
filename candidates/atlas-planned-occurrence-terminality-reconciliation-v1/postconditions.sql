-- Behavioral postconditions for planned occurrence execution-carrier terminality reconciliation v1.

do $proof$
declare
  v_result jsonb;
begin
  -- 1. Historical exact released+done pair is reconciled.
  if not exists(
    select 1
    from atlas.planned_work_occurrences pwo
    where pwo.id='d1400000-0000-4000-8000-000000000001'::uuid
      and pwo.state='completed'
      and pwo.metadata->>'historicalTerminalityReconciledBy'
        ='planned_occurrence_execution_carrier_terminality_reconciliation_v1'
      and pwo.metadata->>'historicalTerminalTaskId'
        ='d1500000-0000-4000-8000-000000000001'
      and coalesce((pwo.metadata->>'domainResultAcceptanceInferred')::boolean,true)=false
  ) then
    raise exception 'Historical exact released+done pair was not reconciled with bounded provenance.';
  end if;

  -- 2. Historical archived carrier remains unresolved/visible, not guessed.
  if (select state
      from atlas.planned_work_occurrences
      where id='d1400000-0000-4000-8000-000000000002'::uuid)<>'released' then
    raise exception 'Archived historical carrier was auto-reconciled without classified semantics.';
  end if;

  if not exists(
    select 1
    from atlas.planned_occurrence_execution_carrier_terminality_audit_v1 a
    where a.occurrence_id='d1400000-0000-4000-8000-000000000002'::uuid
      and a.issue_key='released_occurrence_archived_task_requires_classification'
  ) then
    raise exception 'Archived historical carrier is not visible in terminality audit.';
  end if;

  -- 3. Fresh runtime pair remains live until task actually completes.
  if (select state
      from atlas.planned_work_occurrences
      where id='d1400000-0000-4000-8000-000000000003'::uuid)<>'released' then
    raise exception 'Open execution carrier was terminalized by historical reconciliation.';
  end if;

  -- 4. Current runtime trigger terminalizes occurrence through normal task completion.
  v_result:=atlas.record_task_transition_v1(
    'd1500000-0000-4000-8000-000000000003'::uuid,
    'done',
    'fixture-current-runtime-terminal',
    null,null,null,null,null,
    '{"validation_fixture":true}'::jsonb,
    null
  );

  if (select status
      from atlas.tasks
      where id='d1500000-0000-4000-8000-000000000003'::uuid)<>'done' then
    raise exception 'Normal task transition did not complete fresh task.';
  end if;

  if not exists(
    select 1
    from atlas.planned_work_occurrences pwo
    where pwo.id='d1400000-0000-4000-8000-000000000003'::uuid
      and pwo.state='completed'
      and pwo.metadata->>'terminal_task_id'
        ='d1500000-0000-4000-8000-000000000003'
  ) then
    raise exception 'Current runtime terminality trigger did not close exact occurrence.';
  end if;

  -- 5. No exact released+done pair remains.
  if exists(
    select 1
    from atlas.planned_work_occurrences pwo
    join atlas.tasks t
      on t.id=pwo.released_task_id
     and t.planned_occurrence_id=pwo.id
    where pwo.state='released'
      and t.status='done'
  ) then
    raise exception 'Released+done exact-pair contradiction remains.';
  end if;

  -- 6. Audit remains internal.
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
end;
$proof$;
