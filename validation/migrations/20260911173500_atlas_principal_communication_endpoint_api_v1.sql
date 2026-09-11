-- Validation for 20260911173500 Principal communication endpoint API.
-- Intended for disposable/clone validation after this migration is applied on top
-- of the released 20260911172800 provider-independent communication foundation.

begin;

-- The Principal endpoint read API introduced here must be browser-executable.
do $validation$
begin
  if not has_function_privilege('authenticated','atlas.principal_communication_endpoints_self_api_v1()','EXECUTE') then
    raise exception 'Principal endpoint read API is not executable by authenticated.';
  end if;
end;
$validation$;

-- The Principal endpoint/source binding API introduced here must be browser-executable.
do $validation$
begin
  if not has_function_privilege('authenticated','atlas.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb)','EXECUTE') then
    raise exception 'Principal endpoint source-binding API is not executable by authenticated.';
  end if;
end;
$validation$;

-- Append-only actionability correction lineage must exist and the old one-current
-- accepted unique index must be absent.
do $validation$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='communication_actionability_assessments'
      and column_name='supersedes_assessment_id'
      and data_type='uuid'
  ) then
    raise exception 'Actionability supersedes_assessment_id lineage column missing.';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='communication_actionability_one_current_accepted_uq'
      and c.relkind='i'
  ) then
    raise exception 'Legacy one-current accepted actionability index still exists.';
  end if;
end;
$validation$;

rollback;
