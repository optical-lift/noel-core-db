-- Atlas State Progression: cut live Worker Next Up eligibility over to the
-- canonical task-execution Requirement Evaluation without changing the Next Up
-- response contract. The legacy readiness packet remains only as a blocked-work
-- diagnostic projection in v2. The unused v1 Next Up implementation is retired.

do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef('atlas.worker_next_up_v2(uuid,uuid,date)'::regprocedure)
  into v_def;

  if position('atlas.task_execution_readiness_v1(t.id) as execution_readiness' in v_def)=0 then
    raise exception 'worker_next_up_v2 legacy readiness source pattern not found';
  end if;
  if position('coalesce((t.execution_readiness->>''ready'')::boolean,false)' in v_def)=0 then
    raise exception 'worker_next_up_v2 legacy readiness predicate pattern not found';
  end if;
  if position('''executionReadiness'',b.execution_readiness' in v_def)=0 then
    raise exception 'worker_next_up_v2 diagnostic projection pattern not found';
  end if;

  v_def := replace(
    v_def,
    'atlas.task_execution_readiness_v1(t.id) as execution_readiness',
    'atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation'
  );
  v_def := replace(
    v_def,
    'coalesce((t.execution_readiness->>''ready'')::boolean,false)',
    'coalesce((t.execution_evaluation->>''executionReady'')::boolean,false)'
  );
  v_def := replace(
    v_def,
    '''executionReadiness'',b.execution_readiness',
    '''executionReadiness'',atlas.task_execution_readiness_v1(b.task_id)'
  );

  execute v_def;

  select pg_get_functiondef('atlas.worker_next_up_v3(uuid,uuid,date)'::regprocedure)
  into v_def;

  if position('atlas.task_execution_readiness_v1(t.id) as execution_readiness' in v_def)=0 then
    raise exception 'worker_next_up_v3 legacy readiness source pattern not found';
  end if;
  if position('coalesce((c.execution_readiness->>''ready'')::boolean,false)' in v_def)=0 then
    raise exception 'worker_next_up_v3 legacy readiness predicate pattern not found';
  end if;

  v_def := replace(
    v_def,
    'atlas.task_execution_readiness_v1(t.id) as execution_readiness',
    'atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation'
  );
  v_def := replace(
    v_def,
    'coalesce((c.execution_readiness->>''ready'')::boolean,false)',
    'coalesce((c.execution_evaluation->>''executionReady'')::boolean,false)'
  );

  execute v_def;
end
$migration$;

drop function atlas.worker_next_up_v1(uuid,uuid,date);

comment on function atlas.worker_next_up_v2(uuid,uuid,date) is
  'Worker Next Up v2. Candidate execution eligibility is read directly from canonical atlas.task_execution_requirement_evaluation_v1; legacy task_execution_readiness_v1 is retained only for the existing blocked-work diagnostic JSON shape.';

comment on function atlas.worker_next_up_v3(uuid,uuid,date) is
  'Worker Next Up v3. Normal flow delegates to v2; explicit Sunday override candidate eligibility is read directly from canonical atlas.task_execution_requirement_evaluation_v1.';