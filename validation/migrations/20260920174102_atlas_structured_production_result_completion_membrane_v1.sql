-- Behavioral postconditions for Structured Production Result Completion Membrane v1.

do $proof$
declare
  v_failed boolean;
  v_result jsonb;
begin
  -- 1. Generic completion cannot close Production-linked structured-result work.
  v_failed:=false;
  begin
    perform atlas.record_task_transition_v1(
      'c1400000-0000-4000-8000-000000000001'::uuid,
      'done',
      'fixture-generic-bypass',
      null,null,null,null,null,
      '{"validation_fixture":true}'::jsonb,
      null
    );
  exception when sqlstate '23514' then
    v_failed:=true;
  end;

  if not v_failed then
    raise exception 'Generic completion accepted structured Production work.';
  end if;

  if (select status from atlas.tasks
      where id='c1400000-0000-4000-8000-000000000001'::uuid)<>'open' then
    raise exception 'Failed Production completion mutated task state.';
  end if;

  -- 2. Historical completion is surfaced, not silently repaired.
  if not exists(
    select 1
    from atlas.production_structured_completion_audit_v1 a
    where a.task_id='c1400000-0000-4000-8000-000000000002'::uuid
      and a.issue_key='structured_production_result_missing'
      and a.production_event_count=0
  ) then
    raise exception 'Historical structured Production completion gap was not audited.';
  end if;

  if exists(
    select 1 from atlas.production_lot_events e
    where e.task_id='c1400000-0000-4000-8000-000000000002'::uuid
  ) then
    raise exception 'Migration invented historical Production result evidence.';
  end if;

  -- 3. A domain adapter may write canonical Production evidence and then use
  -- the trusted internal transition path.
  insert into atlas.production_lot_events(
    farm_id,production_lot_id,task_id,event_type,event_date,
    source,idempotency_key,metadata
  ) values(
    'c1100000-0000-4000-8000-000000000001'::uuid,
    'c1300000-0000-4000-8000-000000000001'::uuid,
    'c1400000-0000-4000-8000-000000000003'::uuid,
    'fixture_structured_result',
    current_date,
    'validation_fixture',
    'structured-result-domain-adapter',
    '{"validation_fixture":true}'::jsonb
  );

  v_result:=atlas.record_task_transition_v1_internal(
    'c1400000-0000-4000-8000-000000000003'::uuid,
    'done',
    'fixture-domain-internal',
    null,
    'Canonical Production evidence was recorded first.',
    null,
    'production',
    'fixture_structured_result',
    '{"validation_fixture":true}'::jsonb,
    null
  );

  if (select status from atlas.tasks
      where id='c1400000-0000-4000-8000-000000000003'::uuid)<>'done' then
    raise exception 'Trusted domain completion path was blocked.';
  end if;

  if exists(
    select 1
    from atlas.production_structured_completion_audit_v1 a
    where a.task_id='c1400000-0000-4000-8000-000000000003'::uuid
  ) then
    raise exception 'Auditor reported a Production task that has canonical event evidence.';
  end if;

  -- 4. Production lineage alone does not force structured result semantics.
  v_result:=atlas.record_task_transition_v1(
    'c1400000-0000-4000-8000-000000000004'::uuid,
    'done',
    'fixture-unstructured-production',
    null,null,null,null,null,
    '{"validation_fixture":true}'::jsonb,
    null
  );

  if (select status from atlas.tasks
      where id='c1400000-0000-4000-8000-000000000004'::uuid)<>'done' then
    raise exception 'Unstructured Production-linked generic completion was incorrectly blocked.';
  end if;

  -- 5. Audit stays internal.
  if has_table_privilege(
       'authenticated',
       'atlas.production_structured_completion_audit_v1',
       'SELECT'
     )
     or has_table_privilege(
       'anon',
       'atlas.production_structured_completion_audit_v1',
       'SELECT'
     ) then
    raise exception 'Production structured completion audit leaked to browser roles.';
  end if;

  if not has_table_privilege(
       'service_role',
       'atlas.production_structured_completion_audit_v1',
       'SELECT'
     ) then
    raise exception 'Production structured completion audit is unavailable to service_role.';
  end if;
end;
$proof$;
