-- Atlas State Progression: make canonical Requirement Evaluation the execution-
-- eligibility authority inside the live Worker Day presentation selector chain.
--
-- This is an authority cutover only. Existing presentation states, reasons,
-- ranking, capacity arbitration, and public selector response shapes are
-- preserved. The compatibility readiness packet remains available elsewhere
-- for diagnostics and transition-card projections, but no longer decides
-- presented/held status in legacy_v1, v2, or v3.

do $cutover$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  -- The lowest shared selector stage still supplied readiness to the live
  -- v1 -> v3 -> v2 -> farm_clock_reality_candidates_v1 chain. Read the
  -- canonical evaluation directly and derive the three historical reason
  -- components from its Requirement inputs.
  select pg_get_functiondef(
    'atlas.presented_work_selection_rows_legacy_v1(uuid,uuid,date)'::regprocedure
  ) into v_def;

  v_old := 'cross join lateral (select atlas.task_execution_readiness_v1(t.id) as contract) readiness';
  v_new := 'cross join lateral (select atlas.task_execution_requirement_evaluation_v1(t.id) as contract) readiness';

  if position(v_old in v_def)=0 then
    raise exception 'presented_work_selection_rows_legacy_v1 readiness source pattern not found';
  end if;

  v_def := replace(v_def,v_old,v_new);
  v_def := replace(
    v_def,
    'coalesce((b.readiness->>''ready'')::boolean,false)',
    'coalesce((b.readiness->>''executionReady'')::boolean,false)'
  );
  v_def := replace(
    v_def,
    'coalesce((b.readiness->>''prerequisitesReady'')::boolean,false)',
    'coalesce((select (node->>''satisfied'')::boolean from jsonb_array_elements(coalesce(b.readiness->''requirements'',''[]''::jsonb)) node where node->>''requirementKey''=''prerequisites'' limit 1),false)'
  );
  v_def := replace(
    v_def,
    'coalesce((b.readiness->>''resourcesReady'')::boolean,false)',
    'coalesce((select (node->>''satisfied'')::boolean from jsonb_array_elements(coalesce(b.readiness->''requirements'',''[]''::jsonb)) node where node->>''requirementKey''=''resources'' limit 1),false)'
  );
  v_def := replace(
    v_def,
    'coalesce((b.readiness->>''destinationReady'')::boolean,false)',
    'coalesce((select (node->>''satisfied'')::boolean from jsonb_array_elements(coalesce(b.readiness->''requirements'',''[]''::jsonb)) node where node->>''requirementKey''=''destination'' limit 1),false)'
  );

  execute v_def;

  -- v2 consumes the farm-clock candidate snapshot and performs day/week
  -- capacity arbitration. Its executionReady bit must come from the canonical
  -- evaluation rather than the compatibility projection.
  select pg_get_functiondef(
    'atlas.presented_work_selection_rows_v2(uuid,uuid,date)'::regprocedure
  ) into v_def;

  v_old := '''executionReady'',coalesce((atlas.task_execution_readiness_v1(c.task_id)->>''ready'')::boolean,false)';
  v_new := '''executionReady'',coalesce((atlas.task_execution_requirement_evaluation_v1(c.task_id)->>''executionReady'')::boolean,false)';

  if position(v_old in v_def)=0 then
    raise exception 'presented_work_selection_rows_v2 readiness predicate pattern not found';
  end if;

  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  -- v3 owns the recovery-capacity branch and must use the same authority.
  select pg_get_functiondef(
    'atlas.presented_work_selection_rows_v3(uuid,uuid,date)'::regprocedure
  ) into v_def;

  v_old := '''executionReady'',coalesce((atlas.task_execution_readiness_v1(c.task_id)->>''ready'')::boolean,false),';
  v_new := '''executionReady'',coalesce((atlas.task_execution_requirement_evaluation_v1(c.task_id)->>''executionReady'')::boolean,false),';

  if position(v_old in v_def)=0 then
    raise exception 'presented_work_selection_rows_v3 readiness predicate pattern not found';
  end if;

  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  -- Fail closed if any deciding selector still carries the compatibility
  -- readiness function after this migration.
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'presented_work_selection_rows_legacy_v1',
        'presented_work_selection_rows_v2',
        'presented_work_selection_rows_v3'
      )
      and pg_get_functiondef(p.oid) like '%task_execution_readiness_v1%'
  ) then
    raise exception 'Worker Day presentation selector still contains compatibility readiness authority';
  end if;
end
$cutover$;

comment on function atlas.presented_work_selection_rows_legacy_v1(uuid,uuid,date) is
  'Compatibility-era presentation selector stage. Execution eligibility now derives directly from canonical atlas.task_execution_requirement_evaluation_v1; historical presentation reasons and capacity semantics are preserved.';

comment on function atlas.presented_work_selection_rows_v2(uuid,uuid,date) is
  'Worker Day presentation selector v2. Capacity arbitration consumes execution eligibility directly from canonical atlas.task_execution_requirement_evaluation_v1.';

comment on function atlas.presented_work_selection_rows_v3(uuid,uuid,date) is
  'Worker Day presentation selector v3. Both ordinary and recovery-capacity presentation paths consume canonical State Progression execution evaluation.';
