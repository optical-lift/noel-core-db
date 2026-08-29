do $do$
declare
  v_def text;
  v_marker text := E'  if v_existing.id is not null then\n    v_existing_visibility:=nullif(v_existing.task_payload->>''visibility_scope'','''');\n';
  v_insert text := E'  if v_existing.id is not null and v_existing.state=''completed'' then\n    return jsonb_strip_nulls(jsonb_build_object(\n      ''contractVersion'',''author_production_work_occurrence_v1'',\n      ''occurrenceId'',v_existing.id,\n      ''taskId'',v_existing.released_task_id,\n      ''state'',v_existing.state,\n      ''workKey'',p_work_key,\n      ''dueDate'',v_existing.planned_due_date,\n      ''notBeforeDate'',v_existing.not_before_date,\n      ''authority'',''production_reconciler'',\n      ''historicalImmutable'',true,\n      ''deduplicated'',true\n    ));\n  end if;\n\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='author_production_work_occurrence_v1';
  if v_def is null then raise exception 'Production work authoring membrane is missing'; end if;
  if position(E'v_existing.state=''completed'' then\n    return jsonb_strip_nulls' in v_def)>0 then return; end if;
  if position(v_marker in v_def)=0 then raise exception 'Expected completed-history insertion marker not found'; end if;
  execute replace(v_def,v_marker,v_insert||v_marker);
end
$do$;