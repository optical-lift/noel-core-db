-- Contract validation: Identity Resolution -> Reality Entity authority cutover v1.
--
-- Read-only assertions. This file does not create resolver cases or mutate
-- production data.

do $block$
declare
  v_reality_fk_count integer;
  v_local_fk_count integer;
  v_missing bigint;
  v_def text;
begin
  select count(*)::integer into v_reality_fk_count
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where con.contype='f'
    and con.confrelid='reality.entities'::regclass
    and (
      (n.nspname='atlas' and c.relname in (
        'ledger_source_party_resolutions',
        'ledger_source_party_resolution_cases',
        'ledger_source_party_resolution_candidates'
      ))
      or
      (n.nspname='local_intel' and c.relname in (
        'entity_private_identifier_bindings',
        'entity_private_identifier_binding_conflicts'
      ))
    );

  if v_reality_fk_count<>5 then
    raise exception
      'Expected five resolver Reality entity foreign keys, found %.',
      v_reality_fk_count;
  end if;

  select count(*)::integer into v_local_fk_count
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where con.contype='f'
    and con.confrelid='local_intel.entities'::regclass
    and (
      (n.nspname='atlas' and c.relname in (
        'ledger_source_party_resolutions',
        'ledger_source_party_resolution_cases',
        'ledger_source_party_resolution_candidates'
      ))
      or
      (n.nspname='local_intel' and c.relname in (
        'entity_private_identifier_bindings',
        'entity_private_identifier_binding_conflicts'
      ))
    );

  if v_local_fk_count<>0 then
    raise exception
      'Resolver canonical seam still contains % foreign keys to local_intel.entities.',
      v_local_fk_count;
  end if;

  select count(*) into v_missing
  from (
    select canonical_entity_id as entity_id
    from atlas.ledger_source_party_resolutions

    union all

    select selected_entity_id
    from atlas.ledger_source_party_resolution_cases
    where selected_entity_id is not null

    union all

    select canonical_entity_id
    from atlas.ledger_source_party_resolution_candidates

    union all

    select canonical_entity_id
    from local_intel.entity_private_identifier_bindings

    union all

    select asserted_entity_id
    from local_intel.entity_private_identifier_binding_conflicts
  ) x
  left join reality.entities r on r.id=x.entity_id
  where r.id is null;

  if v_missing<>0 then
    raise exception
      'Resolver canonical seam contains % entity references outside Reality.',
      v_missing;
  end if;

  select pg_get_functiondef(
    'atlas.resolve_ledger_source_party_record_service_v1(uuid,uuid,uuid,text,numeric,text,jsonb,uuid,jsonb)'::regprocedure
  ) into v_def;

  if position('from reality.entities' in lower(v_def))=0
     or position('local_intel.entities' in lower(v_def))<>0 then
    raise exception
      'Low-level resolution write service is not governed by Reality entity authority.';
  end if;

  select pg_get_functiondef(
    'atlas.refresh_private_identifier_bindings_for_source_record_v2(uuid,uuid)'::regprocedure
  ) into v_def;

  if position('from reality.entities' in lower(v_def))=0
     or position('local_intel.entities' in lower(v_def))<>0 then
    raise exception
      'V2 private binding projection is not governed by Reality entity authority.';
  end if;

  select pg_get_functiondef(
    'atlas.evaluate_ledger_source_party_resolution_service_v2(uuid,uuid,date,text,text)'::regprocedure
  ) into v_def;

  if position('join reality.entities' in lower(v_def))=0
     or position('local_intel.entities' in lower(v_def))<>0 then
    raise exception
      'V2 evaluator does not gate Shared Intelligence evidence through Reality.';
  end if;

  select pg_get_functiondef(
    'atlas.commit_ledger_source_party_resolution_case_service_v2(uuid,uuid,uuid,text,uuid,jsonb)'::regprocedure
  ) into v_def;

  if position('from reality.entities' in lower(v_def))=0
     or position('local_intel.entities' in lower(v_def))<>0 then
    raise exception
      'V2 commit service is not governed by Reality entity authority.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.upsert_ledger_source_party_identity_signal_service_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'Legacy V1 signal writer still grants service_role execution.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.evaluate_ledger_source_party_resolution_service_v1(uuid,uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Legacy V1 evaluator still grants service_role execution.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.commit_ledger_source_party_resolution_case_service_v1(uuid,uuid,uuid,text,uuid,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Legacy V1 commit service still grants service_role execution.';
  end if;

  if not has_function_privilege(
    'service_role',
    'atlas.resolve_ledger_source_party_record_service_v1(uuid,uuid,uuid,text,numeric,text,jsonb,uuid,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'V2-compatible low-level resolution service lost service_role execution.';
  end if;

  if not has_function_privilege(
    'service_role',
    'atlas.evaluate_ledger_source_party_resolution_service_v2(uuid,uuid,date,text,text)',
    'EXECUTE'
  ) then
    raise exception 'V2 evaluator is not executable by service_role.';
  end if;

  if not has_function_privilege(
    'service_role',
    'atlas.commit_ledger_source_party_resolution_case_service_v2(uuid,uuid,uuid,text,uuid,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'V2 commit service is not executable by service_role.';
  end if;
end
$block$;

select
  'identity_resolution_reality_entity_cutover_v1' as contract,
  'pass' as result,
  5 as canonical_reality_foreign_keys,
  0 as legacy_v1_mutation_entry_points_with_service_role_authority;
