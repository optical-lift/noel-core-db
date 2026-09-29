-- Postcondition: canonical Execution Authority history is append-only.

do $block$
declare
  v_guard regprocedure:=to_regprocedure('atlas.enforce_execution_authority_chain_v1()');
  v_def text;
begin
  if v_guard is null then
    raise exception 'Execution Authority history guard is missing';
  end if;

  select pg_get_functiondef(v_guard) into v_def;
  if v_def not like '%tg_op=''UPDATE''%' then
    raise exception 'Execution Authority history guard does not reject mutation';
  end if;
  if v_def not like '%record a new authority event%' then
    raise exception 'Execution Authority history guard does not declare append-event repair semantics';
  end if;
end
$block$;
