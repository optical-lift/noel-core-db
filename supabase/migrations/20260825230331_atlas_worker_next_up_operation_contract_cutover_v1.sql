-- Atlas Operation Contract: move live Worker Next Up execution eligibility behind
-- the company-neutral task Operation Contract without changing ranking, capacity,
-- diagnostics, Sunday override behavior, or the returned Next Up JSON contract.

do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef('atlas.worker_next_up_v2(uuid,uuid,date)'::regprocedure)
  into v_def;

  if position('atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation' in v_def)=0 then
    raise exception 'worker_next_up_v2 canonical evaluation source pattern not found';
  end if;
  if position('coalesce((t.execution_evaluation->>''executionReady'')::boolean,false)' in v_def)=0 then
    raise exception 'worker_next_up_v2 canonical evaluation predicate pattern not found';
  end if;

  v_def := replace(
    v_def,
    'atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation',
    'atlas.task_operation_contract_v1(t.id,p_membership_id,v_day) as operation_contract'
  );
  v_def := replace(
    v_def,
    'coalesce((t.execution_evaluation->>''executionReady'')::boolean,false)',
    '(coalesce(t.operation_contract->>''executionDisposition'','''')=''warranted'')'
  );

  execute v_def;

  select pg_get_functiondef('atlas.worker_next_up_v3(uuid,uuid,date)'::regprocedure)
  into v_def;

  if position('atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation' in v_def)=0 then
    raise exception 'worker_next_up_v3 canonical evaluation source pattern not found';
  end if;
  if position('coalesce((c.execution_evaluation->>''executionReady'')::boolean,false)' in v_def)=0 then
    raise exception 'worker_next_up_v3 canonical evaluation predicate pattern not found';
  end if;

  v_def := replace(
    v_def,
    'atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation',
    'atlas.task_operation_contract_v1(t.id,p_membership_id,v_day) as operation_contract'
  );
  v_def := replace(
    v_def,
    'coalesce((c.execution_evaluation->>''executionReady'')::boolean,false)',
    '(coalesce(c.operation_contract->>''executionDisposition'','''')=''warranted'')'
  );

  execute v_def;
end
$migration$;

do $assert$
declare
  v_v2 text;
  v_v3 text;
begin
  select pg_get_functiondef('atlas.worker_next_up_v2(uuid,uuid,date)'::regprocedure) into v_v2;
  select pg_get_functiondef('atlas.worker_next_up_v3(uuid,uuid,date)'::regprocedure) into v_v3;

  if position('atlas.task_operation_contract_v1(t.id,p_membership_id,v_day) as operation_contract' in v_v2)=0
     or position('atlas.task_operation_contract_v1(t.id,p_membership_id,v_day) as operation_contract' in v_v3)=0 then
    raise exception 'Worker Next Up Operation Contract dependency was not installed';
  end if;

  if position('atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation' in v_v2)>0
     or position('atlas.task_execution_requirement_evaluation_v1(t.id) as execution_evaluation' in v_v3)>0 then
    raise exception 'Worker Next Up still has a direct Requirement Evaluation dependency';
  end if;
end
$assert$;

comment on function atlas.worker_next_up_v2(uuid,uuid,date) is
  'Worker Next Up v2. Candidate execution eligibility is projected through atlas.task_operation_contract_v1; ranking, capacity, consequence ordering, and the existing blocked-work diagnostic packet remain unchanged.';

comment on function atlas.worker_next_up_v3(uuid,uuid,date) is
  'Worker Next Up v3. Normal flow delegates to v2; explicit Sunday override candidate eligibility is projected through atlas.task_operation_contract_v1.';
