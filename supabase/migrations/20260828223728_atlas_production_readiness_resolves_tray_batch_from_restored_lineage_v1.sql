do $$
declare v_oid oid; v_def text; v_next text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='record_production_readiness_v1'
    and pg_get_function_identity_arguments(p.oid)='p_task_id uuid, p_action text, p_surviving_seedlings numeric, p_tray_count numeric, p_observed_date date, p_next_check_date date, p_note text, p_idempotency_key text';
  if v_oid is null then raise exception 'record_production_readiness_v1 was not found'; end if;
  v_def:=pg_get_functiondef(v_oid);
  v_next:=replace(v_def,
    'where id=v_task.generated_from_id and production_lot_id=v_lot.id',
    'where id=coalesce(v_task.generated_from_id,(select nullif(plt.metadata->>''tray_batch_id'','''')::uuid from atlas.production_lot_tasks plt where plt.task_id=p_task_id and plt.link_role=''transplant_readiness'' order by plt.created_at desc limit 1)) and production_lot_id=v_lot.id');
  if v_next=v_def then raise exception 'Could not install readiness tray-batch lineage fallback'; end if;
  execute v_next;
end $$;
revoke all on function atlas.record_production_readiness_v1(uuid,text,numeric,numeric,date,date,text,text) from public;