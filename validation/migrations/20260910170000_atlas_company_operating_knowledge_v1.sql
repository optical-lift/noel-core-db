-- Canonical postconditions for Atlas Company Operating Knowledge v1.
-- Runs only against the disposable production-schema clone created by the governed validator.

do $$
declare
  v_missing text[];
  v_missing_rls text[];
  v_bad_authenticated_mutation_count integer;
  v_resolver_def text;
begin
  select array_agg(name order by name)
  into v_missing
  from (
    values
      ('atlas.company_operating_knowledge'),
      ('atlas.company_operating_knowledge_evidence'),
      ('atlas.company_operating_knowledge_adjudications')
  ) required(name)
  where to_regclass(name) is null;

  if v_missing is not null then
    raise exception 'Company Operating Knowledge relations missing after migration: %', v_missing;
  end if;

  select array_agg(relname order by relname)
  into v_missing_rls
  from (
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname in (
        'company_operating_knowledge',
        'company_operating_knowledge_evidence',
        'company_operating_knowledge_adjudications'
      )
      and not c.relrowsecurity
  ) q;

  if v_missing_rls is not null then
    raise exception 'Company Operating Knowledge tables missing RLS: %', v_missing_rls;
  end if;

  select count(*)
  into v_bad_authenticated_mutation_count
  from (
    values
      ('atlas.company_operating_knowledge'),
      ('atlas.company_operating_knowledge_evidence'),
      ('atlas.company_operating_knowledge_adjudications')
  ) t(name)
  where has_table_privilege('authenticated', t.name, 'INSERT')
     or has_table_privilege('authenticated', t.name, 'UPDATE')
     or has_table_privilege('authenticated', t.name, 'DELETE');

  if v_bad_authenticated_mutation_count <> 0 then
    raise exception 'Authenticated role retains direct mutation privilege on % Company Operating Knowledge relations.', v_bad_authenticated_mutation_count;
  end if;

  if to_regprocedure('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)') is null then
    raise exception 'Company Operating Knowledge resolver is missing.';
  end if;

  if not has_function_privilege('authenticated', 'atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)', 'EXECUTE') then
    raise exception 'Authenticated organization members cannot execute Company Operating Knowledge resolver.';
  end if;

  if has_function_privilege('anon', 'atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)', 'EXECUTE') then
    raise exception 'Anonymous role can execute Company Operating Knowledge resolver.';
  end if;

  select pg_get_functiondef('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)'::regprocedure)
  into v_resolver_def;

  if position('status = ''established''' in v_resolver_def) = 0 then
    raise exception 'Resolver no longer limits execution context to established knowledge.';
  end if;

  if position('p_context @> k.scope_match' in v_resolver_def) = 0 then
    raise exception 'Resolver lost context-containment scope matching.';
  end if;

  if position('''conflict''' in v_resolver_def) = 0 then
    raise exception 'Resolver no longer exposes equal-rank conflicting rules.';
  end if;

  if position('atlas.is_organization_member' in v_resolver_def) = 0 then
    raise exception 'Resolver lost organization-membership authorization check.';
  end if;

  if (
    select count(*)
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and t.tgname in (
        'company_operating_knowledge_scope_guard',
        'company_operating_knowledge_evidence_scope_guard',
        'company_operating_knowledge_adjudications_scope_guard',
        'company_operating_knowledge_established_semantics_guard',
        'company_operating_knowledge_evidence_append_only',
        'company_operating_knowledge_adjudications_append_only'
      )
      and not t.tgisinternal
  ) <> 6 then
    raise exception 'Company Operating Knowledge custody trigger set is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.company_operating_knowledge'::regclass
      and pg_get_constraintdef(c.oid) ilike '%status%established%'
      and pg_get_constraintdef(c.oid) ilike '%established_at%'
  ) then
    raise exception 'Established Company Operating Knowledge accounting constraint is missing.';
  end if;
end;
$$;