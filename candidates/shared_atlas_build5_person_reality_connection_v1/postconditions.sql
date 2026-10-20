-- Build 5 shared Person resolution validation. Source-only candidate;
-- evaluated in a disposable clone after generated migration.
do $verify$
declare v_fn text;
begin
  if to_regclass('atlas.person_reality_connection_resolutions') is null then
    raise exception 'Person/Reality identity resolution table missing';
  end if;
  if not exists (
    select 1 from pg_class c
    where c.oid='atlas.person_reality_connection_resolutions'::regclass
      and c.relrowsecurity
  ) then
    raise exception 'Identity resolution requires RLS';
  end if;
  if has_table_privilege('anon',
      'atlas.person_reality_connection_resolutions','SELECT')
    or has_table_privilege('authenticated',
      'atlas.person_reality_connection_resolutions','SELECT')
    or has_table_privilege('service_role',
      'atlas.person_reality_connection_resolutions','INSERT') then
    raise exception 'Person resolution data is not an API table';
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname='atlas'
      and indexname='person_reality_one_active_alias_v1'
      and indexdef ilike '%where (resolution_state = ''active''%'
  ) then
    raise exception 'One active resolution per organization-local Person not proved';
  end if;
  if has_function_privilege('authenticated',
     'atlas.organization_person_canonical_reality_v1(uuid,uuid)','EXECUTE')
    or has_function_privilege('anon',
     'atlas.organization_person_canonical_reality_v1(uuid,uuid)','EXECUTE') then
    raise exception 'Canonical identity resolver must stay private';
  end if;
  if not has_function_privilege('authenticated',
     'public.company_people_native_ledger_scope_self_api_v2(uuid,uuid,integer,uuid)',
     'EXECUTE')
    or has_function_privilege('anon',
     'public.company_people_native_ledger_scope_self_api_v2(uuid,uuid,integer,uuid)',
     'EXECUTE') then
    raise exception 'Corrected People projection grants invalid';
  end if;
  if not has_function_privilege('authenticated',
     'public.attest_person_reality_connection_owner_self_api_v1(uuid,uuid,uuid,uuid,text)',
     'EXECUTE')
    or has_function_privilege('anon',
     'public.attest_person_reality_connection_owner_self_api_v1(uuid,uuid,uuid,uuid,text)',
     'EXECUTE') then
    raise exception 'Owner attestation transport grants invalid';
  end if;
  select pg_get_functiondef(
    'atlas.attest_person_reality_connection_owner_self_api_v1(uuid,uuid,uuid,uuid,text)'::regprocedure)
    into v_fn;
  if position('company_work_native_ledger_owner_self_v1' in v_fn)=0
    or position('auth.uid()' in v_fn)=0
    or position('person_reality_connection_resolutions' in v_fn)=0
    or position('auth_person_bindings' in v_fn)>0 then
    raise exception 'Identity assertion lacks exact owner guard or modifies Auth';
  end if;
  select pg_get_functiondef(
    'atlas.company_people_native_ledger_scope_self_api_v2(uuid,uuid,integer,uuid)'::regprocedure)
    into v_fn;
  if position('company_people_native_ledger_scope_self_api_v1' in v_fn)=0
    or position('organization_person_canonical_reality_v1' in v_fn)=0
    or position('ledger.seats' in v_fn)=0
    or position('organization_employee_seats' in v_fn)>0 then
    raise exception 'Corrected seat projection does not preserve owner gate/identity';
  end if;
  if exists (
    select 1 from atlas.person_reality_connection_resolutions
  ) then
    raise exception 'Schema-only migration must not ship actual private identity assertions';
  end if;
end
$verify$;
