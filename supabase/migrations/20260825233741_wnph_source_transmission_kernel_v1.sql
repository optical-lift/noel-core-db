-- WNPH Source Transmission Kernel v1
-- Private, evidence-bearing transmission/authorship graph.
-- Public bibliographic attribution remains a separate authority.

create table wnph.source_circles (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null check (btrim(canonical_key) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  circle_type text not null check (
    circle_type = any (array[
      'transmission_tradition','functional_office','literary_lineage',
      'editorial_house','scribal_tradition','ritual_tradition',
      'priestly_stream','philosophical_school','oral_tradition',
      'translation_tradition','craft_tradition','thematic_source',
      'house_name','shared_byline','pseudonymous_collective','unknown','other'
    ]::text[])
  ),
  status text not null default 'research_only' check (
    status = any (array[
      'documented','strongly_supported','proposed','disputed','research_only'
    ]::text[])
  ),
  notes text,
  supersedes_source_circle_id uuid references wnph.source_circles(id),
  created_at timestamptz not null default now(),
  constraint source_circles_supersedes_not_self_check
    check (supersedes_source_circle_id is null or supersedes_source_circle_id <> id)
);

comment on table wnph.source_circles is
'Research identity for a recurring information/transmission stream. A Source Circle is not automatically a person and never rewrites bibliographic creator identity.';

-- Source-circle designations reuse the existing appellation/attestation mechanism.
alter table wnph.appellation_bindings
  add column source_circle_id uuid references wnph.source_circles(id);

alter table wnph.appellation_bindings
  drop constraint appellation_bindings_check;

alter table wnph.appellation_bindings
  add constraint appellation_bindings_check
  check (
    num_nonnulls(
      creator_id, corpus_id, work_id, expression_id,
      manifestation_id, series_id, source_circle_id
    ) = 1
  );

create table wnph.source_circle_memberships (
  id uuid primary key default gen_random_uuid(),
  source_circle_id uuid not null references wnph.source_circles(id),
  creator_id uuid references wnph.creator_authorities(id),
  corpus_id uuid references wnph.creator_corpora(id),
  series_id uuid references wnph.series(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  relationship_type text not null check (
    relationship_type = any (array[
      'direct_documentary_association','alias_association','pseudonym_claim',
      'house_name_association','shared_byline_association','transmission_lineage',
      'editorial_association','functional_alignment','inherited_tradition',
      'attributed_membership','unknown','other'
    ]::text[])
  ),
  evidence_status text not null check (
    evidence_status = any (array[
      'documented','strongly_supported','inferred','disputed','research_only'
    ]::text[])
  ),
  mechanism_status text not null default 'unknown' check (
    mechanism_status = any (array['known','partially_known','unknown']::text[])
  ),
  valid_from_year integer,
  valid_to_year integer,
  confidence text,
  notes text,
  supersedes_membership_id uuid references wnph.source_circle_memberships(id),
  created_at timestamptz not null default now(),
  constraint source_circle_memberships_one_subject_check
    check (num_nonnulls(creator_id, corpus_id, series_id, work_id, expression_id, manifestation_id, item_id) = 1),
  constraint source_circle_memberships_year_range_check
    check (valid_from_year is null or valid_to_year is null or valid_from_year <= valid_to_year),
  constraint source_circle_memberships_supersedes_not_self_check
    check (supersedes_membership_id is null or supersedes_membership_id <> id)
);

comment on table wnph.source_circle_memberships is
'Scoped many-to-many association between a Source Circle and exactly one canonical subject. Membership is a relationship, not an identity rewrite; documented association may coexist with unknown mechanism.';

create table wnph.authorship_claims (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references wnph.historical_works(id),
  creator_id uuid not null references wnph.creator_authorities(id),
  role text not null check (
    role = any (array[
      'author','illustrator','compiler','editor','translator','adapter',
      'attributed_author','anonymous','collective','unknown','other'
    ]::text[])
  ),
  claim_basis text not null check (
    claim_basis = any (array[
      'title_page','copyright_record','publisher_archive','manuscript',
      'correspondence','library_authority','later_bibliography',
      'traditional_attribution','other'
    ]::text[])
  ),
  confidence text,
  notes text,
  supersedes_claim_id uuid references wnph.authorship_claims(id),
  created_at timestamptz not null default now(),
  constraint authorship_claims_supersedes_not_self_check
    check (supersedes_claim_id is null or supersedes_claim_id <> id)
);

comment on table wnph.authorship_claims is
'Evidence-bearing historical authorship/contributor claims. They are deliberately separate from public work_creator_credits and have no automatic mutation path into public attribution.';

create table wnph.transmission_claims (
  id uuid primary key default gen_random_uuid(),
  source_circle_id uuid not null references wnph.source_circles(id),
  creator_id uuid references wnph.creator_authorities(id),
  corpus_id uuid references wnph.creator_corpora(id),
  series_id uuid references wnph.series(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  claim_text text not null check (btrim(claim_text) <> ''),
  epistemic_status text not null check (
    epistemic_status = any (array['evidence','inference','interpretation']::text[])
  ),
  confidence text,
  notes text,
  supersedes_claim_id uuid references wnph.transmission_claims(id),
  created_at timestamptz not null default now(),
  constraint transmission_claims_one_subject_check
    check (num_nonnulls(creator_id, corpus_id, series_id, work_id, expression_id, manifestation_id, item_id) = 1),
  constraint transmission_claims_supersedes_not_self_check
    check (supersedes_claim_id is null or supersedes_claim_id <> id)
);

comment on table wnph.transmission_claims is
'Scoped research assertions about information transmission. Epistemic status remains evidence, inference, or interpretation and may never silently become an authorship fact.';

create table wnph.transmission_claim_continuities (
  id uuid primary key default gen_random_uuid(),
  transmission_claim_id uuid not null references wnph.transmission_claims(id),
  continuity_kind text not null check (
    continuity_kind = any (array[
      'function','terminology','structure','ritual_operation','teaching_pattern',
      'narrative_pattern','material_process','editorial_pattern',
      'attribution_history','direct_documentary_link','other'
    ]::text[])
  ),
  observation_text text not null check (btrim(observation_text) <> ''),
  notes text,
  supersedes_continuity_id uuid references wnph.transmission_claim_continuities(id),
  created_at timestamptz not null default now(),
  constraint transmission_claim_continuities_supersedes_not_self_check
    check (supersedes_continuity_id is null or supersedes_continuity_id <> id)
);

comment on table wnph.transmission_claim_continuities is
'Relational custody for observed continuities supporting transmission claims; repeatable observations are not hidden in arrays, notes, or JSON.';

-- Extend reusable evidence custody to the new graph.
alter table wnph.evidence_links
  add column source_circle_id uuid references wnph.source_circles(id),
  add column source_circle_membership_id uuid references wnph.source_circle_memberships(id),
  add column authorship_claim_id uuid references wnph.authorship_claims(id),
  add column transmission_claim_id uuid references wnph.transmission_claims(id),
  add column transmission_claim_continuity_id uuid references wnph.transmission_claim_continuities(id);

alter table wnph.evidence_links
  drop constraint evidence_links_one_target_check;

alter table wnph.evidence_links
  add constraint evidence_links_one_target_check
  check (
    num_nonnulls(
      creator_id, corpus_id, work_creator_credit_id, appellation_attestation_id,
      work_identity_adjudication_id, corpus_membership_id, series_membership_id,
      expression_id, expression_adjudication_id, expression_manifestation_id,
      work_manifestation_id, manifestation_id, item_id, surrogate_id,
      date_claim_id, date_adjudication_id, identifier_id,
      source_circle_id, source_circle_membership_id, authorship_claim_id,
      transmission_claim_id, transmission_claim_continuity_id
    ) = 1
  );

-- Cover every new graph edge and supersession path.
create index source_circles_canonical_key_idx on wnph.source_circles(canonical_key);
create index source_circles_supersedes_idx on wnph.source_circles(supersedes_source_circle_id);

create index appellation_bindings_source_circle_idx on wnph.appellation_bindings(source_circle_id);

create index source_circle_memberships_source_circle_idx on wnph.source_circle_memberships(source_circle_id);
create index source_circle_memberships_creator_idx on wnph.source_circle_memberships(creator_id);
create index source_circle_memberships_corpus_idx on wnph.source_circle_memberships(corpus_id);
create index source_circle_memberships_series_idx on wnph.source_circle_memberships(series_id);
create index source_circle_memberships_work_idx on wnph.source_circle_memberships(work_id);
create index source_circle_memberships_expression_idx on wnph.source_circle_memberships(expression_id);
create index source_circle_memberships_manifestation_idx on wnph.source_circle_memberships(manifestation_id);
create index source_circle_memberships_item_idx on wnph.source_circle_memberships(item_id);
create index source_circle_memberships_supersedes_idx on wnph.source_circle_memberships(supersedes_membership_id);

create index authorship_claims_work_idx on wnph.authorship_claims(work_id);
create index authorship_claims_creator_idx on wnph.authorship_claims(creator_id);
create index authorship_claims_supersedes_idx on wnph.authorship_claims(supersedes_claim_id);

create index transmission_claims_source_circle_idx on wnph.transmission_claims(source_circle_id);
create index transmission_claims_creator_idx on wnph.transmission_claims(creator_id);
create index transmission_claims_corpus_idx on wnph.transmission_claims(corpus_id);
create index transmission_claims_series_idx on wnph.transmission_claims(series_id);
create index transmission_claims_work_idx on wnph.transmission_claims(work_id);
create index transmission_claims_expression_idx on wnph.transmission_claims(expression_id);
create index transmission_claims_manifestation_idx on wnph.transmission_claims(manifestation_id);
create index transmission_claims_item_idx on wnph.transmission_claims(item_id);
create index transmission_claims_supersedes_idx on wnph.transmission_claims(supersedes_claim_id);

create index transmission_claim_continuities_claim_idx on wnph.transmission_claim_continuities(transmission_claim_id);
create index transmission_claim_continuities_supersedes_idx on wnph.transmission_claim_continuities(supersedes_continuity_id);

create index evidence_links_source_circle_idx on wnph.evidence_links(source_circle_id);
create index evidence_links_source_circle_membership_idx on wnph.evidence_links(source_circle_membership_id);
create index evidence_links_authorship_claim_idx on wnph.evidence_links(authorship_claim_id);
create index evidence_links_transmission_claim_idx on wnph.evidence_links(transmission_claim_id);
create index evidence_links_transmission_claim_continuity_idx on wnph.evidence_links(transmission_claim_continuity_id);

-- Historical transmission research is append-only.
create trigger source_circles_append_only
before update or delete on wnph.source_circles
for each row execute function wnph.reject_append_only_mutation();

create trigger source_circle_memberships_append_only
before update or delete on wnph.source_circle_memberships
for each row execute function wnph.reject_append_only_mutation();

create trigger authorship_claims_append_only
before update or delete on wnph.authorship_claims
for each row execute function wnph.reject_append_only_mutation();

create trigger transmission_claims_append_only
before update or delete on wnph.transmission_claims
for each row execute function wnph.reject_append_only_mutation();

create trigger transmission_claim_continuities_append_only
before update or delete on wnph.transmission_claim_continuities
for each row execute function wnph.reject_append_only_mutation();

-- Private canonical custody: RLS enabled, no policies, no application grants.
alter table wnph.source_circles enable row level security;
alter table wnph.source_circle_memberships enable row level security;
alter table wnph.authorship_claims enable row level security;
alter table wnph.transmission_claims enable row level security;
alter table wnph.transmission_claim_continuities enable row level security;

revoke all on table
  wnph.source_circles,
  wnph.source_circle_memberships,
  wnph.authorship_claims,
  wnph.transmission_claims,
  wnph.transmission_claim_continuities
from public, anon, authenticated, service_role;

-- Fail closed on the privacy boundary and on accidental cross-authority behavior.
do $$
declare
  missing_rls integer;
  unexpected_trigger integer;
begin
  select count(*) into missing_rls
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='wnph'
    and c.relname::text = any(array[
      'source_circles','source_circle_memberships','authorship_claims',
      'transmission_claims','transmission_claim_continuities'
    ]::text[])
    and c.relkind='r'
    and not c.relrowsecurity;

  if missing_rls <> 0 then
    raise exception 'WNPH Source Transmission invariant failed: % new tables lack RLS', missing_rls;
  end if;

  select count(*) into unexpected_trigger
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='wnph'
    and c.relname::text = any(array[
      'source_circles','source_circle_memberships','authorship_claims',
      'transmission_claims','transmission_claim_continuities'
    ]::text[])
    and not t.tgisinternal
    and t.tgname::text not in (
      'source_circles_append_only',
      'source_circle_memberships_append_only',
      'authorship_claims_append_only',
      'transmission_claims_append_only',
      'transmission_claim_continuities_append_only'
    );

  if unexpected_trigger <> 0 then
    raise exception 'WNPH public-attribution firewall failed: unexpected trigger on Source Transmission graph';
  end if;
end
$$;