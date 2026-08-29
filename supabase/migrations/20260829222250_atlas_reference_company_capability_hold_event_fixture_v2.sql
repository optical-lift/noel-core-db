do $block$
declare
  v_definition text;
  v_old text := '''Reference one-off event'',''reference_event'',v_today-1';
  v_new text := '''Reference one-off event'',''ticketed_seasonal_evening'',v_today-1';
begin
  select pg_get_functiondef(p.oid) into v_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='run_reference_company_capability_hold_and_event_lifetime_v1'
  order by p.oid desc
  limit 1;

  if v_definition is null then raise exception 'Reference runner definition not found.'; end if;
  if position(v_old in v_definition)=0 then raise exception 'Reference runner event fixture pattern not found.'; end if;
  execute replace(v_definition,v_old,v_new);
end;
$block$;