create or replace function atlas.guard_smart_contact_saved_search_run_child_write_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_run_id uuid:=coalesce(new.run_id,old.run_id);
  v_state text;
begin
  select run_state into v_state
  from atlas.smart_contact_saved_search_runs
  where id=v_run_id;

  if v_state is null then
    if tg_op='DELETE' then
      return old;
    end if;
    raise exception 'Saved-search run not found.' using errcode='P0002';
  end if;

  if v_state<>'running' then
    raise exception 'Saved-search run contents are immutable after run completion.'
      using errcode='55000';
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$function$;
