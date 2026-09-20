-- Behavioral postconditions for planned occurrence execution-carrier terminality reconciliation v1.

do $proof$
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

  -- 4. Current runtime contract remains structurally present.
  if pg_get_functiondef(
       'atlas.release_after_task_terminal_v1()'::regprocedure
     ) not ilike '%new.planned_occurrence_id%'
     or pg_get_functiondef(
       'atlas.release_after_task_terminal_v1()'::regprocedure
     ) not ilike '%state=case when new.status=''done'' then ''completed''%'
  then
    raise exception 'Current runtime occurrence terminalization contract is absent.';
  end if;

  -- 5. No exact released+done pair remains after historical reconciliation.
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
