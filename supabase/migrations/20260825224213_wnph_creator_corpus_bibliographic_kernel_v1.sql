-- Write Now Publishing House creator/corpus + bibliographic identity kernel v1.
--
-- Scope is intentionally bounded to empirical identity/bibliographic custody proven
-- by the Alice Ross Colver packet. Recovery, rights, source-circle/transmission,
-- production, and application API surfaces remain outside this migration.

create table wnph.evidence_sources (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  source_type text not null check (btrim(source_type) <> ''),
  title text,
  repository_name text,
  url text,
  external_identifier text,
  retrieved_at timestamptz,
  rights_note text,
  provenance_note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

create table wnph.creator_authorities (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  preferred_label text not null check (btrim(preferred_label) <> ''),
  creator_type text not null default 'person' check (btrim(creator_type) <> ''),
  birth_year integer,
  death_year integer,
  status text not null default 'established' check (btrim(status) <> ''),
  identity_confidence text,
  notes text,
  created_at timestamptz not null default now(),
  check (birth_year is null or death_year is null or birth_year <= death_year)
);

create table wnph.creator_corpora (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  primary_creator_id uuid not null references wnph.creator_authorities(id),
  label text not null check (btrim(label) <> ''),
  coverage_state text not null default 'partial' check (btrim(coverage_state) <> ''),
  completeness_state text not null default 'partial' check (btrim(completeness_state) <> ''),
  notes text,
  created_at timestamptz not null default now()
);

create table wnph.historical_works (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  work_type text,
  language_code text,
  status text not null default 'established' check (btrim(status) <> ''),
  identity_confidence text,
  notes text,
  created_at timestamptz not null default now()
);

create table wnph.work_creator_credits (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references wnph.historical_works(id),
  creator_id uuid not null references wnph.creator_authorities(id),
  role text not null default 'author' check (btrim(role) <> ''),
  credit_status text not null default 'established' check (btrim(credit_status) <> ''),
  notes text,
  created_at timestamptz not null default now(),
  unique (work_id, creator_id, role)
);

create table wnph.corpus_memberships (
  id uuid primary key default gen_random_uuid(),
  corpus_id uuid not null references wnph.creator_corpora(id),
  work_id uuid not null references wnph.historical_works(id),
  membership_type text not null default 'member' check (btrim(membership_type) <> ''),
  status text not null default 'established' check (btrim(status) <> ''),
  notes text,
  created_at timestamptz not null default now(),
  unique (corpus_id, work_id, membership_type)
);

create table wnph.series (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  publisher_context text,
  status text not null default 'established' check (btrim(status) <> ''),
  notes text,
  created_at timestamptz not null default now()
);

create table wnph.expressions (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  work_id uuid not null references wnph.historical_works(id),
  expression_type text not null check (btrim(expression_type) <> ''),
  language_code text,
  status text not null default 'established' check (btrim(status) <> ''),
  identity_confidence text,
  summary text,
  created_at timestamptz not null default now()
);

create table wnph.manifestations (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  publisher_name text,
  publication_place text,
  publication_statement text,
  extent_statement text,
  format_statement text,
  status text not null default 'established' check (btrim(status) <> ''),
  notes text,
  created_at timestamptz not null default now()
);

create table wnph.expression_manifestations (
  id uuid primary key default gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  manifestation_id uuid not null references wnph.manifestations(id),
  relationship_type text not null default 'embodied_in' check (btrim(relationship_type) <> ''),
  status text not null default 'established' check (btrim(status) <> ''),
  confidence text,
  notes text,
  created_at timestamptz not null default now(),
  unique (expression_id, manifestation_id, relationship_type)
);

create table wnph.items (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  manifestation_id uuid not null references wnph.manifestations(id),
  holding_institution text,
  call_number text,
  external_identifier text,
  status text not null default 'surviving_item_confirmed' check (btrim(status) <> ''),
  copy_note text,
  provenance_note text,
  created_at timestamptz not null default now()
);

create table wnph.surrogates (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  item_id uuid not null references wnph.items(id),
  source_id uuid references wnph.evidence_sources(id),
  surrogate_type text not null check (btrim(surrogate_type) <> ''),
  image_count integer check (image_count is null or image_count >= 0),
  formats text[] not null default '{}'::text[],
  checksum text,
  status text not null default 'available' check (btrim(status) <> ''),
  quality_note text,
  created_at timestamptz not null default now()
);

create table wnph.appellations (
  id uuid primary key default gen_random_uuid(),
  value text not null check (btrim(value) <> ''),
  kind text not null check (btrim(kind) <> ''),
  language_code text,
  script_code text,
  normalized_value text,
  created_at timestamptz not null default now()
);

create table wnph.appellation_attestations (
  id uuid primary key default gen_random_uuid(),
  appellation_id uuid not null references wnph.appellations(id),
  source_id uuid not null references wnph.evidence_sources(id),
  observed_value text not null check (btrim(observed_value) <> ''),
  observed_context text,
  source_locator text,
  notes text,
  created_at timestamptz not null default now()
);

create table wnph.appellation_bindings (
  id uuid primary key default gen_random_uuid(),
  appellation_id uuid not null references wnph.appellations(id),
  relationship_type text not null check (btrim(relationship_type) <> ''),
  creator_id uuid references wnph.creator_authorities(id),
  corpus_id uuid references wnph.creator_corpora(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  series_id uuid references wnph.series(id),
  status text not null default 'established' check (btrim(status) <> ''),
  confidence text,
  notes text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(creator_id, corpus_id, work_id, expression_id, manifestation_id, series_id) = 1)
);

create table wnph.work_identity_adjudications (
  id uuid primary key default gen_random_uuid(),
  left_attestation_id uuid not null references wnph.appellation_attestations(id),
  right_attestation_id uuid references wnph.appellation_attestations(id),
  result_work_id uuid references wnph.historical_works(id),
  result text not null check (result in (
    'SAME_WORK',
    'DIFFERENT_WORKS',
    'SERIALIZATION_RELATIONSHIP',
    'ADAPTATION_RELATIONSHIP',
    'TRANSLATION_RELATIONSHIP',
    'WORKING_TITLE_RELATIONSHIP',
    'POSSIBLY_UNPUBLISHED',
    'UNRESOLVED',
    'OTHER'
  )),
  rationale text not null check (btrim(rationale) <> ''),
  confidence text,
  supersedes_adjudication_id uuid references wnph.work_identity_adjudications(id),
  recorded_by text,
  created_at timestamptz not null default now(),
  check (right_attestation_id is null or right_attestation_id <> left_attestation_id),
  check (supersedes_adjudication_id is null or supersedes_adjudication_id <> id)
);

create table wnph.expression_adjudications (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references wnph.historical_works(id),
  left_expression_id uuid references wnph.expressions(id),
  left_manifestation_id uuid references wnph.manifestations(id),
  right_expression_id uuid references wnph.expressions(id),
  right_manifestation_id uuid references wnph.manifestations(id),
  result text not null check (result in (
    'SAME_EXPRESSION',
    'DIFFERENT_EXPRESSION',
    'TRANSLATION_RELATIONSHIP',
    'ADAPTATION_RELATIONSHIP',
    'UNRESOLVED',
    'OTHER'
  )),
  rationale text not null check (btrim(rationale) <> ''),
  confidence text,
  supersedes_adjudication_id uuid references wnph.expression_adjudications(id),
  recorded_by text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(left_expression_id, left_manifestation_id) = 1),
  check (num_nonnulls(right_expression_id, right_manifestation_id) = 1),
  check (supersedes_adjudication_id is null or supersedes_adjudication_id <> id)
);

create table wnph.series_memberships (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references wnph.series(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  membership_type text not null default 'member' check (btrim(membership_type) <> ''),
  sequence_label text,
  valid_from_year integer,
  valid_to_year integer,
  status text not null default 'established' check (btrim(status) <> ''),
  notes text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(work_id, expression_id, manifestation_id) = 1),
  check (valid_from_year is null or valid_to_year is null or valid_from_year <= valid_to_year)
);

create table wnph.date_claims (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references wnph.evidence_sources(id),
  date_kind text not null check (btrim(date_kind) <> ''),
  observed_text text,
  year_start integer,
  year_end integer,
  precision text,
  status text not null default 'attested' check (btrim(status) <> ''),
  creator_id uuid references wnph.creator_authorities(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  series_membership_id uuid references wnph.series_memberships(id),
  notes text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(creator_id, work_id, expression_id, manifestation_id, item_id, series_membership_id) = 1),
  check (year_start is not null or observed_text is not null),
  check (year_start is null or year_end is null or year_start <= year_end)
);

create table wnph.identifiers (
  id uuid primary key default gen_random_uuid(),
  scheme text not null check (btrim(scheme) <> ''),
  value text not null check (btrim(value) <> ''),
  source_id uuid references wnph.evidence_sources(id),
  creator_id uuid references wnph.creator_authorities(id),
  corpus_id uuid references wnph.creator_corpora(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  series_id uuid references wnph.series(id),
  status text not null default 'attested' check (btrim(status) <> ''),
  notes text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(creator_id, corpus_id, work_id, expression_id, manifestation_id, item_id, surrogate_id, series_id) = 1)
);

create table wnph.coverage_ledger (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid references wnph.creator_authorities(id),
  corpus_id uuid references wnph.creator_corpora(id),
  work_id uuid references wnph.historical_works(id),
  source_family text not null check (btrim(source_family) <> ''),
  query_or_scope text,
  searched_at timestamptz not null default now(),
  coverage_state text not null check (btrim(coverage_state) <> ''),
  result_summary text,
  source_id uuid references wnph.evidence_sources(id),
  notes text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(creator_id, corpus_id, work_id) <= 1)
);

create table wnph.evidence_links (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references wnph.evidence_sources(id),
  support_role text not null default 'supports' check (support_role in ('supports', 'contradicts', 'context', 'unknown')),
  creator_id uuid references wnph.creator_authorities(id),
  corpus_id uuid references wnph.creator_corpora(id),
  work_creator_credit_id uuid references wnph.work_creator_credits(id),
  appellation_attestation_id uuid references wnph.appellation_attestations(id),
  work_identity_adjudication_id uuid references wnph.work_identity_adjudications(id),
  corpus_membership_id uuid references wnph.corpus_memberships(id),
  series_membership_id uuid references wnph.series_memberships(id),
  expression_id uuid references wnph.expressions(id),
  expression_adjudication_id uuid references wnph.expression_adjudications(id),
  expression_manifestation_id uuid references wnph.expression_manifestations(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  date_claim_id uuid references wnph.date_claims(id),
  identifier_id uuid references wnph.identifiers(id),
  confidence text,
  note text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(
    creator_id,
    corpus_id,
    work_creator_credit_id,
    appellation_attestation_id,
    work_identity_adjudication_id,
    corpus_membership_id,
    series_membership_id,
    expression_id,
    expression_adjudication_id,
    expression_manifestation_id,
    manifestation_id,
    item_id,
    surrogate_id,
    date_claim_id,
    identifier_id
  ) = 1)
);

create index creator_corpora_primary_creator_idx on wnph.creator_corpora(primary_creator_id);
create index work_creator_credits_work_idx on wnph.work_creator_credits(work_id);
create index work_creator_credits_creator_idx on wnph.work_creator_credits(creator_id);
create index corpus_memberships_corpus_idx on wnph.corpus_memberships(corpus_id);
create index corpus_memberships_work_idx on wnph.corpus_memberships(work_id);
create index expressions_work_idx on wnph.expressions(work_id);
create index expression_manifestations_expression_idx on wnph.expression_manifestations(expression_id);
create index expression_manifestations_manifestation_idx on wnph.expression_manifestations(manifestation_id);
create index items_manifestation_idx on wnph.items(manifestation_id);
create index surrogates_item_idx on wnph.surrogates(item_id);
create index surrogates_source_idx on wnph.surrogates(source_id);
create index appellation_attestations_appellation_idx on wnph.appellation_attestations(appellation_id);
create index appellation_attestations_source_idx on wnph.appellation_attestations(source_id);
create index appellation_bindings_appellation_idx on wnph.appellation_bindings(appellation_id);
create index appellation_bindings_creator_idx on wnph.appellation_bindings(creator_id) where creator_id is not null;
create index appellation_bindings_corpus_idx on wnph.appellation_bindings(corpus_id) where corpus_id is not null;
create index appellation_bindings_work_idx on wnph.appellation_bindings(work_id) where work_id is not null;
create index appellation_bindings_expression_idx on wnph.appellation_bindings(expression_id) where expression_id is not null;
create index appellation_bindings_manifestation_idx on wnph.appellation_bindings(manifestation_id) where manifestation_id is not null;
create index appellation_bindings_series_idx on wnph.appellation_bindings(series_id) where series_id is not null;
create index work_identity_adjudications_left_idx on wnph.work_identity_adjudications(left_attestation_id);
create index work_identity_adjudications_right_idx on wnph.work_identity_adjudications(right_attestation_id) where right_attestation_id is not null;
create index work_identity_adjudications_result_work_idx on wnph.work_identity_adjudications(result_work_id) where result_work_id is not null;
create index work_identity_adjudications_supersedes_idx on wnph.work_identity_adjudications(supersedes_adjudication_id) where supersedes_adjudication_id is not null;
create index expression_adjudications_work_idx on wnph.expression_adjudications(work_id);
create index expression_adjudications_left_expression_idx on wnph.expression_adjudications(left_expression_id) where left_expression_id is not null;
create index expression_adjudications_left_manifestation_idx on wnph.expression_adjudications(left_manifestation_id) where left_manifestation_id is not null;
create index expression_adjudications_right_expression_idx on wnph.expression_adjudications(right_expression_id) where right_expression_id is not null;
create index expression_adjudications_right_manifestation_idx on wnph.expression_adjudications(right_manifestation_id) where right_manifestation_id is not null;
create index expression_adjudications_supersedes_idx on wnph.expression_adjudications(supersedes_adjudication_id) where supersedes_adjudication_id is not null;
create index series_memberships_series_idx on wnph.series_memberships(series_id);
create index series_memberships_work_idx on wnph.series_memberships(work_id) where work_id is not null;
create index series_memberships_expression_idx on wnph.series_memberships(expression_id) where expression_id is not null;
create index series_memberships_manifestation_idx on wnph.series_memberships(manifestation_id) where manifestation_id is not null;
create index date_claims_source_idx on wnph.date_claims(source_id);
create index date_claims_creator_idx on wnph.date_claims(creator_id) where creator_id is not null;
create index date_claims_work_idx on wnph.date_claims(work_id) where work_id is not null;
create index date_claims_expression_idx on wnph.date_claims(expression_id) where expression_id is not null;
create index date_claims_manifestation_idx on wnph.date_claims(manifestation_id) where manifestation_id is not null;
create index date_claims_item_idx on wnph.date_claims(item_id) where item_id is not null;
create index date_claims_series_membership_idx on wnph.date_claims(series_membership_id) where series_membership_id is not null;
create index identifiers_source_idx on wnph.identifiers(source_id) where source_id is not null;
create index identifiers_creator_idx on wnph.identifiers(creator_id) where creator_id is not null;
create index identifiers_corpus_idx on wnph.identifiers(corpus_id) where corpus_id is not null;
create index identifiers_work_idx on wnph.identifiers(work_id) where work_id is not null;
create index identifiers_expression_idx on wnph.identifiers(expression_id) where expression_id is not null;
create index identifiers_manifestation_idx on wnph.identifiers(manifestation_id) where manifestation_id is not null;
create index identifiers_item_idx on wnph.identifiers(item_id) where item_id is not null;
create index identifiers_surrogate_idx on wnph.identifiers(surrogate_id) where surrogate_id is not null;
create index identifiers_series_idx on wnph.identifiers(series_id) where series_id is not null;
create index coverage_ledger_creator_idx on wnph.coverage_ledger(creator_id) where creator_id is not null;
create index coverage_ledger_corpus_idx on wnph.coverage_ledger(corpus_id) where corpus_id is not null;
create index coverage_ledger_work_idx on wnph.coverage_ledger(work_id) where work_id is not null;
create index coverage_ledger_source_idx on wnph.coverage_ledger(source_id) where source_id is not null;
create index evidence_links_source_idx on wnph.evidence_links(source_id);
create index evidence_links_creator_idx on wnph.evidence_links(creator_id) where creator_id is not null;
create index evidence_links_corpus_idx on wnph.evidence_links(corpus_id) where corpus_id is not null;
create index evidence_links_work_credit_idx on wnph.evidence_links(work_creator_credit_id) where work_creator_credit_id is not null;
create index evidence_links_appellation_attestation_idx on wnph.evidence_links(appellation_attestation_id) where appellation_attestation_id is not null;
create index evidence_links_work_adjudication_idx on wnph.evidence_links(work_identity_adjudication_id) where work_identity_adjudication_id is not null;
create index evidence_links_corpus_membership_idx on wnph.evidence_links(corpus_membership_id) where corpus_membership_id is not null;
create index evidence_links_series_membership_idx on wnph.evidence_links(series_membership_id) where series_membership_id is not null;
create index evidence_links_expression_idx on wnph.evidence_links(expression_id) where expression_id is not null;
create index evidence_links_expression_adjudication_idx on wnph.evidence_links(expression_adjudication_id) where expression_adjudication_id is not null;
create index evidence_links_expression_manifestation_idx on wnph.evidence_links(expression_manifestation_id) where expression_manifestation_id is not null;
create index evidence_links_manifestation_idx on wnph.evidence_links(manifestation_id) where manifestation_id is not null;
create index evidence_links_item_idx on wnph.evidence_links(item_id) where item_id is not null;
create index evidence_links_surrogate_idx on wnph.evidence_links(surrogate_id) where surrogate_id is not null;
create index evidence_links_date_claim_idx on wnph.evidence_links(date_claim_id) where date_claim_id is not null;
create index evidence_links_identifier_idx on wnph.evidence_links(identifier_id) where identifier_id is not null;

create function wnph.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'WNPH append-only custody: %.% rows may not be updated or deleted', TG_TABLE_SCHEMA, TG_TABLE_NAME;
end
$$;

revoke all on function wnph.reject_append_only_mutation() from public, anon, authenticated, service_role;

create trigger appellation_attestations_append_only
before update or delete on wnph.appellation_attestations
for each row execute function wnph.reject_append_only_mutation();

create trigger work_identity_adjudications_append_only
before update or delete on wnph.work_identity_adjudications
for each row execute function wnph.reject_append_only_mutation();

create trigger expression_adjudications_append_only
before update or delete on wnph.expression_adjudications
for each row execute function wnph.reject_append_only_mutation();

create trigger date_claims_append_only
before update or delete on wnph.date_claims
for each row execute function wnph.reject_append_only_mutation();

create trigger coverage_ledger_append_only
before update or delete on wnph.coverage_ledger
for each row execute function wnph.reject_append_only_mutation();

do $$
declare
  relation_name text;
begin
  for relation_name in
    select tablename
    from pg_tables
    where schemaname = 'wnph'
  loop
    execute format('alter table wnph.%I enable row level security', relation_name);
  end loop;
end
$$;

revoke all on all tables in schema wnph from public, anon, authenticated, service_role;
revoke all on all sequences in schema wnph from public, anon, authenticated, service_role;
revoke all on all functions in schema wnph from public, anon, authenticated, service_role;

comment on table wnph.appellations is
  'Observed or canonical name/title/designation strings. Identity is established separately through evidence-bearing bindings and adjudications.';
comment on table wnph.expressions is
  'Distinct content realizations of Historical Works. A publication state does not create an Expression without evidence-backed adjudication.';
comment on table wnph.manifestations is
  'Publication/production embodiments. Manifestations and Expressions are related many-to-many through expression_manifestations.';
comment on table wnph.items is
  'Individually identifiable surviving exemplars of Manifestations.';
comment on table wnph.surrogates is
  'Digital/photographic captures of Items; never the Item itself.';
comment on table wnph.date_claims is
  'Source-specific date assertions. Conflicting dates coexist until adjudicated; there is no single unqualified publication-date scalar on Historical Work.';
comment on table wnph.coverage_ledger is
  'Append-only record of where a creator/corpus/work was searched and what that search established or failed to establish.';

do $$
declare
  role_name text;
  required_relation text;
  expected_relations text[] := array[
    'creator_authorities',
    'historical_works',
    'expressions',
    'manifestations',
    'expression_manifestations',
    'items',
    'surrogates',
    'appellations',
    'appellation_attestations',
    'work_identity_adjudications',
    'expression_adjudications',
    'date_claims',
    'evidence_sources',
    'evidence_links'
  ];
begin
  foreach required_relation in array expected_relations loop
    if to_regclass('wnph.' || required_relation) is null then
      raise exception 'WNPH kernel invariant failed: missing wnph.%', required_relation;
    end if;
  end loop;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'wnph_api'
      and c.relkind in ('r', 'p', 'v', 'm', 'f')
  ) then
    raise exception 'WNPH API invariant failed: bounded kernel must not create an application relation';
  end if;

  foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
    if has_schema_privilege(role_name, 'wnph', 'USAGE')
       or has_schema_privilege(role_name, 'wnph', 'CREATE') then
      raise exception 'WNPH membrane violation: role % gained direct schema access', role_name;
    end if;

    if has_schema_privilege(role_name, 'wnph_api', 'USAGE')
       or has_schema_privilege(role_name, 'wnph_api', 'CREATE') then
      raise exception 'WNPH API membrane violation: role % gained access without an explicit API migration', role_name;
    end if;
  end loop;
end
$$;
