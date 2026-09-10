begin;

-- A cancelled/skipped queue item is intentionally not executable work. It must
-- not break provenance from the last completed executable predecessor to the
-- next queued item.
do $repair$
declare
  v_oid oid;
  v_def text;
  v_old text:=$needle$and previous.position<v_next_item.position
        order by previous.position desc$needle$;
  v_new text:=$needle$and previous.position<v_next_item.position
          and previous.state<>'skipped'
        order by previous.position desc$needle$;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='release_next_task_in_queue_v1'
    and pg_get_function_identity_arguments(p.oid)='p_farm_id uuid, p_queue_key text, p_completed_date date';

  if v_oid is null then
    raise exception 'release_next_task_in_queue_v1 signature not found.';
  end if;

  v_def:=pg_get_functiondef(v_oid);
  if position(v_old in v_def)=0 then
    raise exception 'Expected completion-gated predecessor clause was not found; refusing semantic patch.';
  end if;

  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$repair$;

commit;
