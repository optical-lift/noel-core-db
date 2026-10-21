-- Disposable clone structural/authorization proof for Person-native date placement.
do $check$
declare v_entry text;v_args text;v_atlas oid;v_public oid;
begin
 if (select is_nullable from information_schema.columns
 where table_schema='atlas' and table_name='ledger_person_dispatches'
 and column_name='proposed_work_on')<>'YES' then
  raise exception 'Optional proposed date missing';end if;
 if not exists(select 1 from pg_constraint
 where conrelid='atlas.ledger_person_dispatches'::regclass
 and conname='ledger_person_dispatches_notice_no_work_date_v1') then
  raise exception 'Informational notice must not become dated Work';end if;
 for v_entry,v_args in select * from (values
 ('connected_ledger_send_dated_self_api_v1','uuid,uuid,text,text,text,date'),
 ('connected_ledger_respond_dated_self_api_v1','uuid,text,date'),
 ('connected_ledger_inbox_dated_self_api_v1','integer'),
 ('connected_person_place_work_self_api_v1','uuid,date,text')) x(name,args)
 loop
  v_atlas:=to_regprocedure('atlas.'||v_entry||'('||v_args||')');
  v_public:=to_regprocedure('public.'||v_entry||'('||v_args||')');
  if v_atlas is null or v_public is null then
    raise exception 'Canonical and browser public RPC must both exist: %',v_entry;end if;
  if has_function_privilege('anon',v_public,'EXECUTE')
   or has_function_privilege('anon',v_atlas,'EXECUTE')
   or not has_function_privilege('authenticated',v_public,'EXECUTE')
   or not has_function_privilege('authenticated',v_atlas,'EXECUTE') then
    raise exception 'Person-only function privileges missing: %',v_entry;end if;
  if exists (select 1 from pg_proc where oid=v_public and prosecdef) then
    raise exception 'Public forwarding must not elevate privileges: %',v_entry;end if;
 end loop;
 if position('assignee_canonical_person_id=v_person' in pg_get_functiondef(
  'atlas.connected_person_place_work_self_api_v1(uuid,date,text)'::regprocedure))=0
 or position('person_has_native_ledger_connection_v1' in pg_get_functiondef(
  'atlas.connected_person_place_work_self_api_v1(uuid,date,text)'::regprocedure))=0
 then raise exception 'Self placement not constrained to current accountable connected Person';end if;
 if position('connected_person_place_work_self_api_v1' in pg_get_functiondef(
  'atlas.connected_ledger_respond_dated_self_api_v1(uuid,text,date)'::regprocedure))=0
 then raise exception 'Accept does not commit Work and Day atomically';end if;
 if position('proposedWorkOn' in pg_get_functiondef(
  'atlas.connected_ledger_inbox_dated_self_api_v1(integer)'::regprocedure))=0
 then raise exception 'Original sender proposal not visible before receiver uptake';end if;
end$check$;