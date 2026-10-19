-- Run on a disposable production-schema clone AFTER candidate.sql.
-- No production data is written by this file.
do $post$
declare
  v_count integer;
  v_source text;
  v_doc jsonb := jsonb_build_object(
    'purpose','Maintain institutional operations',
    'outcomes','[]'::jsonb,
    'requirements','[]'::jsonb,
    'responsibilityNotes','[]'::jsonb,
    'reporting','{}'::jsonb,
    'operatingConditions','{}'::jsonb,
    'requestedAccess',jsonb_build_object(
      'view','[]'::jsonb,'record','[]'::jsonb,
      'manage','[]'::jsonb,'approve','[]'::jsonb,
      'excluded',jsonb_build_array('financial','payroll','owner_controls')));
begin
  if to_regclass('atlas.position_definition_kernels') is null
    or to_regclass('atlas.organization_position_ledger_definitions') is null
    or to_regclass('atlas.organization_position_definition_revisions') is null then
    raise exception 'Durable position tables missing';
  end if;
  if not atlas.position_definition_document_valid_v1(v_doc)
    or atlas.position_definition_document_valid_v1(v_doc || '{"roguePermission":true}'::jsonb)
    or atlas.position_definition_document_valid_v1(v_doc - 'purpose')
    or atlas.position_definition_document_valid_v1(v_doc || '{"requestedAccess":{"view":"all"}}'::jsonb) then
    raise exception 'Position document validation failed open or rejects a valid document';
  end if;
  select count(*) into v_count from atlas.position_definition_kernels;
  if v_count < 5 then
    raise exception 'Reusable position kernel seed incomplete';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='atlas.organization_position_definition_revisions'::regclass
      and tgname='organization_position_revisions_immutable_v1'
      and not tgisinternal
  ) then raise exception 'Append-only definition history trigger missing'; end if;
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname in ('position_definition_kernels',
        'organization_position_ledger_definitions',
        'organization_position_definition_revisions')
      and not c.relrowsecurity
  ) then raise exception 'Position definition RLS must be enabled'; end if;
  if has_table_privilege('authenticated','atlas.position_definition_kernels','SELECT')
    or has_table_privilege('authenticated','atlas.organization_position_ledger_definitions','SELECT')
    or has_table_privilege('authenticated','atlas.organization_position_definition_revisions','SELECT')
    or has_table_privilege('authenticated','atlas.organization_position_definition_revisions','INSERT')
    or has_table_privilege('anon','atlas.organization_position_ledger_definitions','SELECT') then
    raise exception 'Direct role table privileges widened';
  end if;
  if has_function_privilege('anon','public.position_definition_kernels_self_api_v1()','EXECUTE')
    or has_function_privilege('anon','public.position_definition_owner_self_api_v1(uuid,uuid,uuid)','EXECUTE')
    or has_function_privilege('anon','public.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz)','EXECUTE')
    or not has_function_privilege('authenticated','public.position_definition_owner_self_api_v1(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Authenticated-only RPC grants incorrect';
  end if;
  select pg_get_functiondef(
    'atlas.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz)'::regprocedure)
    into v_source;
  if position('company_work_native_ledger_owner_self_v1' in v_source)=0
    or position('p_expected_revision' in v_source)=0
    or position('organization_position_appointments' in v_source)=0
    or position('standingAssignmentChanged' in v_source)=0 then
    raise exception 'Owner, concurrency, appointment-history or no-grant boundary missing';
  end if;
  if exists (
    select 1 from atlas.organization_position_ledger_definitions d
    join atlas.organization_positions p on p.id=d.position_id
    join atlas.ledgers l on l.id=d.ledger_id
    where d.organization_id<>p.organization_id
      or d.organization_id is distinct from l.organization_id
  ) then
    raise exception 'Found cross-organization position Ledger definition';
  end if;
end
$post$;
