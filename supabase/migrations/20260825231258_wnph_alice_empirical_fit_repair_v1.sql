-- WNPH Alice empirical fit repair v1.
--
-- Repairs only the four general structural gaps exposed by the first real corpus:
-- 1. a Manifestation may be known to belong to a Work while Expression identity is unresolved;
-- 2. evidence-bearing relationships require append-only supersession rather than silent rewrite;
-- 3. ordinary Work establishment requires an explicit adjudication event;
-- 4. conflicting date claims require a governed multi-claim adjudication object.
--
-- Recovery Work, rights, transmission/source-circle architecture, production assets,
-- and wnph_api remain outside this migration.

create table wnph.work_manifestations (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references wnph.historical_works(id),
  manifestation_id uuid not null references wnph.manifestations(id),
  relationship_type text not null default 'manifestation_of' check (btrim(relationship_type) <> ''),
  status text not null default 'established' check (btrim(status) <> ''),
  confidence text,
  supersedes_relationship_id uuid references wnph.work_manifestations(id),
  notes text,
  created_at timestamptz not null default now(),
  check (supersedes_relationship_id is null or supersedes_relationship_id <> id)
);

create table wnph.date_adjudications (
  id uuid primary key default gen_random_uuid(),
  result text not null check (result in (
    'CONFIRMED',
    'DISTINGUISHED_DATE_ROLES',
    'UNRESOLVED',
    'REJECTED',
    'OTHER'
  )),
  creator_id uuid references wnph.creator_authorities(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  series_membership_id uuid references wnph.series_memberships(id),
  canonical_year_start integer,
  canonical_year_end integer,
  conclusion_text text,
  rationale text not null check (btrim(rationale) <> ''),
  confidence text,
  supersedes_adjudication_id uuid references wnph.date_adjudications(id),
  recorded_by text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(creator_id, work_id, expression_id, manifestation_id, item_id, series_membership_id) = 1),
  check (canonical_year_start is null or canonical_year_end is null or canonical_year_start <= canonical_year_end),
  check (supersedes_adjudication_id is null or supersedes_adjudication_id <> id)
);

create table wnph.date_adjudication_claims (
  id uuid primary key default gen_random_uuid(),
  adjudication_id uuid not null references wnph.date_adjudications(id),
  date_claim_id uuid not null references wnph.date_claims(id),
  claim_role text not null default 'considered' check (btrim(claim_role) <> ''),
  notes text,
  created_at timestamptz not null default now(),
  unique (adjudication_id, date_claim_id)
);

alter table wnph.evidence_sources
  add column supersedes_source_id uuid references wnph.evidence_sources(id),
  add constraint evidence_sources_supersedes_not_self_check
    check (supersedes_source_id is null or supersedes_source_id <> id);

alter table wnph.work_creator_credits
  drop constraint work_creator_credits_work_id_creator_id_role_key,
  add column supersedes_credit_id uuid references wnph.work_creator_credits(id),
  add constraint work_creator_credits_supersedes_not_self_check
    check (supersedes_credit_id is null or supersedes_credit_id <> id);

alter table wnph.corpus_memberships
  drop constraint corpus_memberships_corpus_id_work_id_membership_type_key,
  add column supersedes_membership_id uuid references wnph.corpus_memberships(id),
  add constraint corpus_memberships_supersedes_not_self_check
    check (supersedes_membership_id is null or supersedes_membership_id <> id);

alter table wnph.expression_manifestations
  drop constraint expression_manifestations_expression_id_manifestation_id_re_key,
  add column supersedes_relationship_id uuid references wnph.expression_manifestations(id),
  add constraint expression_manifestations_supersedes_not_self_check
    check (supersedes_relationship_id is null or supersedes_relationship_id <> id);

alter table wnph.appellation_bindings
  add column supersedes_binding_id uuid references wnph.appellation_bindings(id),
  add constraint appellation_bindings_supersedes_not_self_check
    check (supersedes_binding_id is null or supersedes_binding_id <> id);

alter table wnph.series_memberships
  add column supersedes_membership_id uuid references wnph.series_memberships(id),
  add constraint series_memberships_supersedes_not_self_check
    check (supersedes_membership_id is null or supersedes_membership_id <> id);

alter table wnph.evidence_links
  add column work_manifestation_id uuid references wnph.work_manifestations(id),
  add column date_adjudication_id uuid references wnph.date_adjudications(id),
  add column supersedes_evidence_link_id uuid references wnph.evidence_links(id),
  add constraint evidence_links_supersedes_not_self_check
    check (supersedes_evidence_link_id is null or supersedes_evidence_link_id <> id);

alter table wnph.evidence_links
  drop constraint evidence_links_check;

alter table wnph.evidence_links
  add constraint evidence_links_one_target_check
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
    work_manifestation_id,
    manifestation_id,
    item_id,
    surrogate_id,
    date_claim_id,
    date_adjudication_id,
    identifier_id
  ) = 1);

alter table wnph.work_identity_adjudications
  drop constraint work_identity_adjudications_result_check;

alter table wnph.work_identity_adjudications
  add constraint work_identity_adjudications_result_check
  check (result in (
    'ESTABLISHES_WORK',
    'SAME_WORK',
    'DIFFERENT_WORKS',
    'SERIALIZATION_RELATIONSHIP',
    'ADAPTATION_RELATIONSHIP',
    'TRANSLATION_RELATIONSHIP',
    'WORKING_TITLE_RELATIONSHIP',
    'POSSIBLY_UNPUBLISHED',
    'UNRESOLVED',
    'OTHER'
  ));

alter table wnph.work_identity_adjudications
  add constraint work_identity_adjudications_establishment_shape_check
  check (
    result <> 'ESTABLISHES_WORK'
    or (right_attestation_id is null and result_work_id is not null)
  );

create index work_manifestations_work_idx on wnph.work_manifestations(work_id);
create index work_manifestations_manifestation_idx on wnph.work_manifestations(manifestation_id);
create index work_manifestations_supersedes_idx on wnph.work_manifestations(supersedes_relationship_id) where supersedes_relationship_id is not null;

create index date_adjudications_creator_idx on wnph.date_adjudications(creator_id) where creator_id is not null;
create index date_adjudications_work_idx on wnph.date_adjudications(work_id) where work_id is not null;
create index date_adjudications_expression_idx on wnph.date_adjudications(expression_id) where expression_id is not null;
create index date_adjudications_manifestation_idx on wnph.date_adjudications(manifestation_id) where manifestation_id is not null;
create index date_adjudications_item_idx on wnph.date_adjudications(item_id) where item_id is not null;
create index date_adjudications_series_membership_idx on wnph.date_adjudications(series_membership_id) where series_membership_id is not null;
create index date_adjudications_supersedes_idx on wnph.date_adjudications(supersedes_adjudication_id) where supersedes_adjudication_id is not null;
create index date_adjudication_claims_adjudication_idx on wnph.date_adjudication_claims(adjudication_id);
create index date_adjudication_claims_claim_idx on wnph.date_adjudication_claims(date_claim_id);

create index evidence_sources_supersedes_idx on wnph.evidence_sources(supersedes_source_id) where supersedes_source_id is not null;
create index work_creator_credits_supersedes_idx on wnph.work_creator_credits(supersedes_credit_id) where supersedes_credit_id is not null;
create index corpus_memberships_supersedes_idx on wnph.corpus_memberships(supersedes_membership_id) where supersedes_membership_id is not null;
create index expression_manifestations_supersedes_idx on wnph.expression_manifestations(supersedes_relationship_id) where supersedes_relationship_id is not null;
create index appellation_bindings_supersedes_idx on wnph.appellation_bindings(supersedes_binding_id) where supersedes_binding_id is not null;
create index series_memberships_supersedes_idx on wnph.series_memberships(supersedes_membership_id) where supersedes_membership_id is not null;
create index evidence_links_work_manifestation_idx on wnph.evidence_links(work_manifestation_id) where work_manifestation_id is not null;
create index evidence_links_date_adjudication_idx on wnph.evidence_links(date_adjudication_id) where date_adjudication_id is not null;
create index evidence_links_supersedes_idx on wnph.evidence_links(supersedes_evidence_link_id) where supersedes_evidence_link_id is not null;

create trigger evidence_sources_append_only
before update or delete on wnph.evidence_sources
for each row execute function wnph.reject_append_only_mutation();

create trigger work_creator_credits_append_only
before update or delete on wnph.work_creator_credits
for each row execute function wnph.reject_append_only_mutation();

create trigger corpus_memberships_append_only
before update or delete on wnph.corpus_memberships
for each row execute function wnph.reject_append_only_mutation();

create trigger expression_manifestations_append_only
before update or delete on wnph.expression_manifestations
for each row execute function wnph.reject_append_only_mutation();

create trigger appellation_bindings_append_only
before update or delete on wnph.appellation_bindings
for each row execute function wnph.reject_append_only_mutation();

create trigger series_memberships_append_only
before update or delete on wnph.series_memberships
for each row execute function wnph.reject_append_only_mutation();

create trigger evidence_links_append_only
before update or delete on wnph.evidence_links
for each row execute function wnph.reject_append_only_mutation();

create trigger work_manifestations_append_only
before update or delete on wnph.work_manifestations
for each row execute function wnph.reject_append_only_mutation();

create trigger date_adjudications_append_only
before update or delete on wnph.date_adjudications
for each row execute function wnph.reject_append_only_mutation();

create trigger date_adjudication_claims_append_only
before update or delete on wnph.date_adjudication_claims
for each row execute function wnph.reject_append_only_mutation();

alter table wnph.work_manifestations enable row level security;
alter table wnph.date_adjudications enable row level security;
alter table wnph.date_adjudication_claims enable row level security;

revoke all on wnph.work_manifestations from public, anon, authenticated, service_role;
revoke all on wnph.date_adjudications from public, anon, authenticated, service_role;
revoke all on wnph.date_adjudication_claims from public, anon, authenticated, service_role;
revoke all on all sequences in schema wnph from public, anon, authenticated, service_role;

comment on table wnph.work_manifestations is
  'Evidence-bearing Work-to-Manifestation relationship used when Work identity is known but Expression identity may remain unresolved.';
comment on column wnph.work_manifestations.supersedes_relationship_id is
  'Append-only correction chain. A new relationship row may supersede an earlier row; the earlier row is never rewritten.';
comment on table wnph.date_adjudications is
  'Append-only adjudication over one or more source-specific date claims. Original date claims remain immutable.';
comment on table wnph.date_adjudication_claims is
  'Membership of source-specific date claims in a governed date adjudication.';
comment on column wnph.work_identity_adjudications.result is
  'Includes ESTABLISHES_WORK so ordinary title-to-Work establishment is an explicit historical decision rather than an implicit mutable binding.';

do $$
declare
  role_name text;
begin
  if to_regclass('wnph.work_manifestations') is null
     or to_regclass('wnph.date_adjudications') is null
     or to_regclass('wnph.date_adjudication_claims') is null then
    raise exception 'WNPH Alice fit repair invariant failed: required repair relation missing';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'wnph_api'
      and c.relkind in ('r', 'p', 'v', 'm', 'f')
  ) then
    raise exception 'WNPH API invariant failed: empirical fit repair must not create application relations';
  end if;

  foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
    if has_schema_privilege(role_name, 'wnph', 'USAGE')
       or has_schema_privilege(role_name, 'wnph', 'CREATE')
       or has_schema_privilege(role_name, 'wnph_api', 'USAGE')
       or has_schema_privilege(role_name, 'wnph_api', 'CREATE') then
      raise exception 'WNPH membrane violation during Alice fit repair for role %', role_name;
    end if;
  end loop;
end
$$;