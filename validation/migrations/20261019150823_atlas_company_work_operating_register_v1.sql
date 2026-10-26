-- Disposable schema-clone postconditions; no production fixture mutation.
do $post$
declare
  v_doc jsonb := jsonb_build_object(
    'requiredOutcome','Animals have water and feed',
    'instructions','Confirm both sources safely',
    'prerequisites','[]'::jsonb,
    'resources','[]'::jsonb,
    'reporting','{}'::jsonb,
    'escalation','{}'::jsonb);
  v_source text;
begin
  if to_regclass('atlas.company_work_operating_register_entries') is null
    or to_regclass('atlas.company_work_operating_register_revisions') is null then
    raise exception 'Operating register source tables missing';
  end if;
  if not atlas.operating_requirement_document_valid_v1(v_doc)
    or atlas.operating_requirement_document_valid_v1(v_doc - 'requiredOutcome')
    or atlas.operating_requirement_document_valid_v1(
      v_doc||'{"extraAuthority":true}'::jsonb) then
    raise exception 'Operating document validator failed open or rejected a valid value';
  end if;
  if has_table_privilege('authenticated',
       'atlas.company_work_operating_register_entries','SELECT')
    or has_table_privilege('authenticated',
       'atlas.company_work_operating_register_revisions','INSERT')
    or has_table_privilege('anon',
       'atlas.company_work_operating_register_entries','SELECT') then
    raise exception 'Unsafe direct register table privileges';
  end if;
  if exists (
    select 1 from pg_class c where c.oid in (
      'atlas.company_work_operating_register_entries'::regclass,
      'atlas.company_work_operating_register_revisions'::regclass)
      and not c.relrowsecurity
  ) then raise exception 'Register RLS disabled'; end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='atlas.company_work_operating_register_revisions'::regclass
      and tgname='operating_register_revision_immutable_v1' and not tgisinternal
  ) then raise exception 'Append-only register revisions not guarded'; end if;
  if has_function_privilege('anon',
       'public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)','EXECUTE')
    or has_function_privilege('anon',
       'public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)','EXECUTE')
    or not has_function_privilege('authenticated',
       'public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)','EXECUTE') then
    raise exception 'Register RPC role grants incorrect'; end if;
  select pg_get_functiondef(
    'atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure)
    into v_source;
  if position('company_work_native_ledger_owner_self_v1' in v_source)=0
    or position('insert into atlas.work_requirements' in lower(v_source))=0
    or position('insert into atlas.work_items' in lower(v_source))>0
    or position('instancesGenerated' in v_source)=0 then
    raise exception 'Exact owner/canonical requirement/no instance generation contract missing';
  end if;
  if exists (
    select 1 from atlas.company_work_operating_register_entries e
    join atlas.work_requirements w on w.id=e.requirement_id
    join atlas.ledgers l on l.id=e.ledger_id
    where e.organization_id<>w.organization_id
      or e.organization_id is distinct from l.organization_id
  ) then raise exception 'Cross-organization register entry found'; end if;
end
$post$;
