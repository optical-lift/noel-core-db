-- WNPH Alice source-transmission empirical reconciliation v1
-- Preserve directly evidenced authorship while explicitly refusing to fabricate a Source Circle.

with alice as (
  select id as creator_id
  from wnph.creator_authorities
  where canonical_key = 'alice-ross-colver'
), dewy as (
  select id as work_id
  from wnph.historical_works
  where canonical_key = 'wish-fairy-and-dewy-dear'
), dewy_source as (
  select id as source_id
  from wnph.evidence_sources
  where canonical_key = 'loc:item:22008427'
), dewy_claim as (
  insert into wnph.authorship_claims (
    work_id, creator_id, role, claim_basis, confidence, notes
  )
  select
    dewy.work_id,
    alice.creator_id,
    'author',
    'library_authority',
    'high',
    'Library of Congress bibliographic record names Alice Ross Colver for The Wish Fairy and Dewy Dear.'
  from alice cross join dewy
  returning id
)
insert into wnph.evidence_links (
  source_id, support_role, authorship_claim_id, confidence, note
)
select
  dewy_source.source_id,
  'supports',
  dewy_claim.id,
  'high',
  'Direct Library of Congress bibliographic attribution.'
from dewy_source cross join dewy_claim;

with alice as (
  select id as creator_id
  from wnph.creator_authorities
  where canonical_key = 'alice-ross-colver'
), jeanne as (
  select id as work_id
  from wnph.historical_works
  where canonical_key = 'jeannes-house-party'
), jeanne_source as (
  select id as source_id
  from wnph.evidence_sources
  where canonical_key = 'loc:item:23017721'
), jeanne_claim as (
  insert into wnph.authorship_claims (
    work_id, creator_id, role, claim_basis, confidence, notes
  )
  select
    jeanne.work_id,
    alice.creator_id,
    'author',
    'library_authority',
    'high',
    'Library of Congress bibliographic record names Alice Ross Colver for Jeanne''s House Party.'
  from alice cross join jeanne
  returning id
)
insert into wnph.evidence_links (
  source_id, support_role, authorship_claim_id, confidence, note
)
select
  jeanne_source.source_id,
  'supports',
  jeanne_claim.id,
  'high',
  'Direct Library of Congress bibliographic attribution.'
from jeanne_source cross join jeanne_claim;

insert into wnph.coverage_ledger (
  corpus_id,
  source_family,
  query_or_scope,
  coverage_state,
  result_summary,
  notes
)
select
  cc.id,
  'source_transmission_review',
  'Bounded Alice Ross Colver source-transmission review: LOC 22008427; LOC 23017721; Indiana University Dodd, Mead finding aid; Henry Altemus publisher bibliographies; 1949 Catalog of Copyright Entries; Goodreads Babs series.',
  'bounded_review_complete',
  'Direct bibliographic authorship is evidenced for the two LOC-held works. The current bounded source set does not establish a Source Circle or transmission relationship; no membership or transmission claim was created.',
  'This is a scoped negative finding, not a universal conclusion. Future evidence may establish a Source Circle and should be added append-only without rewriting the present review.'
from wnph.creator_corpora cc
where cc.canonical_key = 'alice-ross-colver-corpus';

do $$
declare
  alice_id uuid;
  alice_corpus_id uuid;
  claim_count integer;
  evidence_count integer;
  public_credit_count integer;
  coverage_count integer;
begin
  select id into alice_id
  from wnph.creator_authorities
  where canonical_key = 'alice-ross-colver';

  select id into alice_corpus_id
  from wnph.creator_corpora
  where canonical_key = 'alice-ross-colver-corpus';

  if alice_id is null or alice_corpus_id is null then
    raise exception 'Alice source-transmission reconciliation failed: canonical creator/corpus missing';
  end if;

  select count(*) into claim_count
  from wnph.authorship_claims
  where creator_id = alice_id;

  if claim_count <> 2 then
    raise exception 'Alice source-transmission reconciliation failed: expected 2 authorship claims, found %', claim_count;
  end if;

  select count(*) into evidence_count
  from wnph.evidence_links el
  join wnph.authorship_claims ac on ac.id = el.authorship_claim_id
  join wnph.evidence_sources es on es.id = el.source_id
  where ac.creator_id = alice_id
    and es.canonical_key in ('loc:item:22008427', 'loc:item:23017721')
    and el.support_role = 'supports';

  if evidence_count <> 2 then
    raise exception 'Alice source-transmission reconciliation failed: expected 2 LOC evidence links, found %', evidence_count;
  end if;

  if exists (select 1 from wnph.source_circles)
     or exists (select 1 from wnph.source_circle_memberships)
     or exists (select 1 from wnph.transmission_claims)
     or exists (select 1 from wnph.transmission_claim_continuities) then
    raise exception 'Alice source-transmission reconciliation failed: bounded evidence does not warrant a Source Circle or transmission claim';
  end if;

  select count(*) into public_credit_count
  from wnph.work_creator_credits
  where creator_id = alice_id;

  if public_credit_count <> 29 then
    raise exception 'WNPH public-attribution firewall failed: expected 29 Alice public credits, found %', public_credit_count;
  end if;

  select count(*) into coverage_count
  from wnph.coverage_ledger
  where corpus_id = alice_corpus_id
    and source_family = 'source_transmission_review'
    and coverage_state = 'bounded_review_complete';

  if coverage_count <> 1 then
    raise exception 'Alice source-transmission reconciliation failed: expected one bounded coverage record, found %', coverage_count;
  end if;
end
$$;