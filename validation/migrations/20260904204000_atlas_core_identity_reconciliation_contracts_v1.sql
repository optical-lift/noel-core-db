-- Canonical postconditions for Atlas Core evidence-first identity reconciliation v1.
-- Runs only against the disposable production-schema clone created by the governed validator.

do $$
declare
  v_missing text[];
  v_bad_fk_count integer;
  v_bad_mutation_count integer;
  v_missing_rls text[];
  v_function_def text;
begin
  select array_agg(name order by name)
  into v_missing
  from (
    values
      ('atlas.identity_subjects'),
      ('atlas.identity_source_records'),
      ('atlas.identity_claims'),
      ('atlas.identity_source_subject_assertions'),
      ('atlas.identity_subject_pair_assertions'),
      ('atlas.identity_reconciliation_reviews'),
      ('atlas.identity_reconciliation_adjudications'),
      ('atlas.identity_subject_projections'),
      ('atlas.v_identity_parties_v1')
  ) as required(name)
  where to_regclass(name) is null;

  if v_missing is not null then
    raise exception 'Identity reconciliation relations missing after migration: %', v_missing;
  end if;

  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema='atlas'
      and c.table_name='identity_subjects'
      and c.column_name in ('display_name','name','email','phone','address','party_kind','subject_kind','external_id')
  ) then
    raise exception 'identity_subjects contains privileged descriptive identity columns; subject must remain thin.';
  end if;

  select count(*)
  into v_bad_fk_count
  from pg_constraint c
  join pg_class src on src.oid=c.conrelid
  join pg_namespace src_ns on src_ns.oid=src.relnamespace
  join pg_class dst on dst.oid=c.confrelid
  join pg_namespace dst_ns on dst_ns.oid=dst.relnamespace
  where c.contype='f'
    and src_ns.nspname='atlas'
    and src.relname in (
      'identity_subjects','identity_source_records','identity_claims',
      'identity_source_subject_assertions','identity_subject_pair_assertions',
      'identity_reconciliation_reviews','identity_reconciliation_adjudications',
      'identity_subject_projections'
    )
    and dst_ns.nspname='local_intel';

  if v_bad_fk_count <> 0 then
    raise exception 'Atlas Core identity reconciliation still has % local_intel foreign-key dependencies.', v_bad_fk_count;
  end if;

  select array_agg(relname order by relname)
  into v_missing_rls
  from (
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname in (
        'identity_subjects','identity_source_records','identity_claims',
        'identity_source_subject_assertions','identity_subject_pair_assertions',
        'identity_reconciliation_reviews','identity_reconciliation_adjudications',
        'identity_subject_projections'
      )
      and not c.relrowsecurity
  ) q;

  if v_missing_rls is not null then
    raise exception 'Identity reconciliation tables missing RLS: %', v_missing_rls;
  end if;

  select count(*)
  into v_bad_mutation_count
  from (
    values
      ('atlas.identity_subjects'),
      ('atlas.identity_source_records'),
      ('atlas.identity_claims'),
      ('atlas.identity_source_subject_assertions'),
      ('atlas.identity_subject_pair_assertions'),
      ('atlas.identity_reconciliation_reviews'),
      ('atlas.identity_reconciliation_adjudications'),
      ('atlas.identity_subject_projections')
  ) as t(name)
  where has_table_privilege('authenticated', t.name, 'INSERT')
     or has_table_privilege('authenticated', t.name, 'UPDATE')
     or has_table_privilege('authenticated', t.name, 'DELETE');

  if v_bad_mutation_count <> 0 then
    raise exception 'Authenticated role retains direct mutation privilege on % identity relations.', v_bad_mutation_count;
  end if;

  if to_regprocedure('atlas.identity_party_projection_v1(uuid)') is null then
    raise exception 'Identity Party projection RPC is missing.';
  end if;
  if to_regprocedure('atlas.identity_subject_provenance_v1(uuid)') is null then
    raise exception 'Identity provenance RPC is missing.';
  end if;
  if to_regprocedure('atlas.identity_review_queue_v1(uuid)') is null then
    raise exception 'Identity review queue RPC is missing.';
  end if;
  if to_regprocedure('atlas.identity_adjudicate_review_v1(uuid,text,text)') is null then
    raise exception 'Identity adjudication RPC is missing.';
  end if;

  select pg_get_functiondef('atlas.identity_adjudicate_review_v1(uuid,text,text)'::regprocedure)
  into v_function_def;

  if position('not_enough_evidence' in v_function_def)=0
     or position('defer_unresolved' in v_function_def)=0
     or position('v_resolves_review := false' in v_function_def)=0 then
    raise exception 'Identity adjudication lost the true unresolved review outcome.';
  end if;

  if position('local_intel' in lower(v_function_def))<>0 then
    raise exception 'Core identity adjudication still depends on local_intel.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='identity_subjects'
      and t.tgname='identity_subjects_no_delete'
      and not t.tgisinternal
  ) then
    raise exception 'Identity subjects can be physically deleted; retirement/correction guard missing.';
  end if;

  if (
    select count(*)
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and t.tgname in (
        'identity_source_records_append_only',
        'identity_claims_append_only',
        'identity_source_subject_assertions_append_only',
        'identity_subject_pair_assertions_append_only',
        'identity_reconciliation_adjudications_append_only'
      )
      and not t.tgisinternal
  ) <> 5 then
    raise exception 'Append-only identity evidence/adjudication trigger set is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.identity_source_subject_assertions'::regclass
      and pg_get_constraintdef(c.oid) ilike '%non_match%'
  ) then
    raise exception 'Explicit source-record non-match identity evidence is not structurally supported.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.identity_subject_pair_assertions'::regclass
      and pg_get_constraintdef(c.oid) ilike '%distinct%'
  ) then
    raise exception 'Explicit subject-distinct identity evidence is not structurally supported.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry r
    where r.signature='atlas.identity_review_queue_v1(uuid)'
      and r.authenticated_execute_expected=true
      and r.anonymous_execute_expected=false
      and coalesce((r.evidence->>'threeWayReview')::boolean,false)=true
      and coalesce((r.evidence->>'dependsOnLocalIntel')::boolean,true)=false
  ) then
    raise exception 'Identity review queue governance registration is missing three-way/Core-owned semantics.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry r
    where replace(r.signature,' ','')='atlas.identity_adjudicate_review_v1(uuid,text,text)'
      and r.authenticated_execute_expected=true
      and r.anonymous_execute_expected=false
      and coalesce((r.evidence->>'notEnoughEvidenceRemainsOpen')::boolean,false)=true
      and coalesce((r.evidence->>'canonicalPartyRowCreated')::boolean,true)=false
      and coalesce((r.evidence->>'dependsOnLocalIntel')::boolean,true)=false
  ) then
    raise exception 'Identity adjudication governance registration does not preserve evidence-first unresolved semantics.';
  end if;
end;
$$;
