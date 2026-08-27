create schema if not exists reporting;

comment on schema reporting is
  'Private newsroom reporting memory: source-custodied evidence, claims, events, money, actions, quotes and continuing story topics.';

revoke all on schema reporting from public, anon, authenticated;

alter default privileges in schema reporting revoke all on tables from public, anon, authenticated;
alter default privileges in schema reporting revoke all on sequences from public, anon, authenticated;
alter default privileges in schema reporting revoke execute on functions from public, anon, authenticated;

create table reporting.sources (
  id uuid primary key default gen_random_uuid(),
  source_family_key text not null,
  source_version_key text not null unique,
  source_kind text not null check (btrim(source_kind) <> ''),
  authority_class text not null check (
    authority_class in (
      'official_final', 'official_proposed', 'official_supporting',
      'first_party_statement', 'reporter_interview', 'reporter_observation',
      'secondary_reporting', 'private_note', 'unknown'
    )
  ),
  visibility_class text not null default 'public' check (
    visibility_class in ('public', 'newsroom_private', 'restricted')
  ),
  title text,
  publisher text,
  source_date date,
  published_at timestamptz,
  retrieved_at timestamptz not null default now(),
  canonical_url text,
  external_locator jsonb not null default '{}'::jsonb,
  content_sha256 text check (
    content_sha256 is null or content_sha256 ~ '^[0-9a-fA-F]{64}$'
  ),
  content_type text,
  parent_source_id uuid references reporting.sources(id) on delete restrict,
  derivation_kind text,
  supersedes_source_id uuid references reporting.sources(id) on delete restrict,
  source_status text not null default 'active' check (
    source_status in ('active', 'superseded', 'unavailable', 'retracted')
  ),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(source_family_key) <> ''),
  check (btrim(source_version_key) <> ''),
  check ((parent_source_id is null and derivation_kind is null) or (parent_source_id is not null and nullif(btrim(derivation_kind), '') is not null)),
  check (supersedes_source_id is null or supersedes_source_id <> id)
);

create unique index uq_reporting_sources_family_hash on reporting.sources(source_family_key, content_sha256) where content_sha256 is not null;
create unique index uq_reporting_sources_one_active_version on reporting.sources(source_family_key) where source_status = 'active';
create index ix_reporting_sources_kind_date on reporting.sources(source_kind, source_date desc);
create index ix_reporting_sources_parent on reporting.sources(parent_source_id) where parent_source_id is not null;

create table reporting.source_passages (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references reporting.sources(id) on delete restrict,
  stable_key text not null unique,
  passage_kind text not null check (btrim(passage_kind) <> ''),
  ordinal integer not null check (ordinal >= 0),
  page_number integer check (page_number is null or page_number >= 1),
  start_offset integer check (start_offset is null or start_offset >= 0),
  end_offset integer check (end_offset is null or end_offset >= 0),
  speaker_label_raw text,
  text text not null,
  text_origin text not null check (text_origin in ('official_text','embedded_pdf','ocr','machine_transcript','human_transcript','published_text','reporter_note','other')),
  is_verbatim boolean not null default false,
  machine_derived boolean not null default false,
  confidence numeric(6,5) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  text_sha256 text check (text_sha256 is null or text_sha256 ~ '^[0-9a-fA-F]{64}$'),
  locator jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (id, source_id),
  check ((start_offset is null and end_offset is null) or (start_offset is not null and end_offset is not null and end_offset > start_offset)),
  check (text_origin not in ('ocr', 'machine_transcript') or machine_derived)
);

create index ix_reporting_source_passages_source_ordinal on reporting.source_passages(source_id, ordinal);
create index ix_reporting_source_passages_page on reporting.source_passages(source_id, page_number) where page_number is not null;
create index ix_reporting_source_passages_search on reporting.source_passages using gin (to_tsvector('english', coalesce(text, '')));

create table reporting.objects (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  object_type text not null check (object_type in ('person','organization','government_body','project','property','place','contract','grant_program','publication','other')),
  canonical_name text not null check (btrim(canonical_name) <> ''),
  description text,
  local_intel_entity_id uuid references local_intel.entities(id) on delete set null,
  local_intel_binding_state text not null default 'unlinked' check (local_intel_binding_state in ('unlinked', 'candidate', 'verified', 'rejected')),
  local_intel_binding_confidence numeric(6,5) check (local_intel_binding_confidence is null or (local_intel_binding_confidence >= 0 and local_intel_binding_confidence <= 1)),
  verification_state text not null default 'candidate' check (verification_state in ('candidate', 'source_backed', 'verified', 'disputed', 'retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((local_intel_entity_id is null and local_intel_binding_state in ('unlinked', 'rejected')) or (local_intel_entity_id is not null and local_intel_binding_state in ('candidate', 'verified')))
);

create unique index uq_reporting_objects_local_intel_binding on reporting.objects(local_intel_entity_id) where local_intel_entity_id is not null;
create index ix_reporting_objects_type_name on reporting.objects(object_type, canonical_name);
create index ix_reporting_objects_search on reporting.objects using gin (to_tsvector('english', coalesce(canonical_name, '') || ' ' || coalesce(description, '')));

create table reporting.object_aliases (
  id uuid primary key default gen_random_uuid(),
  object_id uuid not null references reporting.objects(id) on delete cascade,
  alias text not null check (btrim(alias) <> ''),
  alias_kind text not null default 'name' check (btrim(alias_kind) <> ''),
  source_id uuid references reporting.sources(id) on delete restrict,
  verification_state text not null default 'candidate' check (verification_state in ('candidate', 'source_backed', 'verified', 'rejected')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index uq_reporting_object_aliases_normalized on reporting.object_aliases(object_id, lower(alias));
create index ix_reporting_object_aliases_lookup on reporting.object_aliases(lower(alias));

create table reporting.events (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  event_kind text not null check (event_kind in ('meeting','interview','press_conference','hearing','incident','tour','deadline','publication','other')),
  title text not null check (btrim(title) <> ''),
  starts_at timestamptz,
  ends_at timestamptz,
  government_body_object_id uuid references reporting.objects(id) on delete set null,
  location_object_id uuid references reporting.objects(id) on delete set null,
  event_status text not null default 'unknown' check (event_status in ('scheduled', 'occurred', 'cancelled', 'unknown')),
  external_locator jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create index ix_reporting_events_kind_start on reporting.events(event_kind, starts_at desc);
create index ix_reporting_events_body_start on reporting.events(government_body_object_id, starts_at desc) where government_body_object_id is not null;

create table reporting.event_sources (
  event_id uuid not null references reporting.events(id) on delete cascade,
  source_id uuid not null references reporting.sources(id) on delete restrict,
  source_role text not null check (btrim(source_role) <> ''),
  created_at timestamptz not null default now(),
  primary key (event_id, source_id, source_role)
);
create index ix_reporting_event_sources_source on reporting.event_sources(source_id);

create table reporting.topics (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  title text not null check (btrim(title) <> ''),
  description text,
  workflow_state text not null default 'watching' check (workflow_state in ('watching','upcoming','occurred','follow_up','packet_ready','published','continuing','archived')),
  priority smallint not null default 50 check (priority between 0 and 100),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (closed_at is null or closed_at >= opened_at)
);

create index ix_reporting_topics_workflow on reporting.topics(workflow_state, priority desc, opened_at desc);
create index ix_reporting_topics_search on reporting.topics using gin (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, '')));

create table reporting.topic_objects (
  topic_id uuid not null references reporting.topics(id) on delete cascade,
  object_id uuid not null references reporting.objects(id) on delete cascade,
  relation_role text not null default 'related' check (btrim(relation_role) <> ''),
  created_at timestamptz not null default now(),
  primary key (topic_id, object_id, relation_role)
);
create index ix_reporting_topic_objects_object on reporting.topic_objects(object_id);

create table reporting.topic_sources (
  topic_id uuid not null references reporting.topics(id) on delete cascade,
  source_id uuid not null references reporting.sources(id) on delete restrict,
  relation_role text not null default 'related' check (btrim(relation_role) <> ''),
  created_at timestamptz not null default now(),
  primary key (topic_id, source_id, relation_role)
);
create index ix_reporting_topic_sources_source on reporting.topic_sources(source_id);

create table reporting.topic_events (
  topic_id uuid not null references reporting.topics(id) on delete cascade,
  event_id uuid not null references reporting.events(id) on delete cascade,
  relation_role text not null default 'related' check (btrim(relation_role) <> ''),
  created_at timestamptz not null default now(),
  primary key (topic_id, event_id, relation_role)
);
create index ix_reporting_topic_events_event on reporting.topic_events(event_id);

create table reporting.claims (
  id uuid primary key default gen_random_uuid(),
  subject_object_id uuid references reporting.objects(id) on delete restrict,
  subject_event_id uuid references reporting.events(id) on delete restrict,
  subject_topic_id uuid references reporting.topics(id) on delete restrict,
  claim_kind text not null check (btrim(claim_kind) <> ''),
  predicate text not null check (btrim(predicate) <> ''),
  phase text not null default 'unknown' check (phase in ('unknown','proposed','requested','estimated','approved','adopted','actual','reported','observed')),
  claim_state text not null default 'candidate' check (claim_state in ('candidate','source_backed','verified','disputed','superseded','rejected')),
  conflict_state text not null default 'none' check (conflict_state in ('none','unresolved','resolved')),
  value_text text,
  value_numeric numeric,
  value_date date,
  value_timestamp timestamptz,
  value_boolean boolean,
  value_json jsonb,
  object_value_id uuid references reporting.objects(id) on delete restrict,
  asserted_by_object_id uuid references reporting.objects(id) on delete set null,
  asserted_at timestamptz,
  valid_from timestamptz,
  valid_to timestamptz,
  supersedes_claim_id uuid references reporting.claims(id) on delete restrict,
  machine_derived boolean not null default false,
  verification_method text,
  verified_at timestamptz,
  resolution_note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(subject_object_id, subject_event_id, subject_topic_id) = 1),
  check (num_nonnulls(value_text, value_numeric, value_date, value_timestamp, value_boolean, value_json, object_value_id) = 1),
  check (valid_to is null or valid_from is null or valid_to >= valid_from),
  check (supersedes_claim_id is null or supersedes_claim_id <> id),
  check (claim_state <> 'verified' or (verified_at is not null and nullif(btrim(verification_method), '') is not null)),
  check (conflict_state <> 'resolved' or nullif(btrim(resolution_note), '') is not null)
);

create index ix_reporting_claims_subject_object on reporting.claims(subject_object_id, predicate, phase) where subject_object_id is not null;
create index ix_reporting_claims_subject_event on reporting.claims(subject_event_id, predicate, phase) where subject_event_id is not null;
create index ix_reporting_claims_subject_topic on reporting.claims(subject_topic_id, predicate, phase) where subject_topic_id is not null;
create index ix_reporting_claims_state_phase on reporting.claims(claim_state, phase, created_at desc);
create index ix_reporting_claims_object_value on reporting.claims(object_value_id) where object_value_id is not null;
create index ix_reporting_claims_search on reporting.claims using gin (to_tsvector('english', coalesce(predicate, '') || ' ' || coalesce(value_text, '')));

create table reporting.claim_evidence (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references reporting.claims(id) on delete cascade,
  source_id uuid not null references reporting.sources(id) on delete restrict,
  source_passage_id uuid,
  evidence_role text not null default 'supports' check (evidence_role in ('supports','contradicts','reports','attributes','derives','supersedes')),
  evidence_strength numeric(6,5) check (evidence_strength is null or (evidence_strength >= 0 and evidence_strength <= 1)),
  evidence_note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (source_passage_id, source_id) references reporting.source_passages(id, source_id) on delete restrict
);

create index ix_reporting_claim_evidence_claim on reporting.claim_evidence(claim_id);
create index ix_reporting_claim_evidence_source on reporting.claim_evidence(source_id);
create index ix_reporting_claim_evidence_passage on reporting.claim_evidence(source_passage_id) where source_passage_id is not null;

create table reporting.topic_claims (
  topic_id uuid not null references reporting.topics(id) on delete cascade,
  claim_id uuid not null references reporting.claims(id) on delete cascade,
  relation_role text not null default 'related' check (btrim(relation_role) <> ''),
  created_at timestamptz not null default now(),
  primary key (topic_id, claim_id, relation_role)
);
create index ix_reporting_topic_claims_claim on reporting.topic_claims(claim_id);

create table reporting.money_facts (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null unique references reporting.claims(id) on delete cascade,
  amount numeric(18,2) not null,
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  money_role text not null check (money_role in ('request','proposed_budget','estimated_expense','estimated_revenue','award','estimate','bid','contract_award','appropriation','encumbrance','reimbursement','actual_expense','actual_revenue','profit_loss','fee','other')),
  category_text text,
  normalized_category text,
  payer_object_id uuid references reporting.objects(id) on delete set null,
  payee_object_id uuid references reporting.objects(id) on delete set null,
  related_event_id uuid references reporting.events(id) on delete set null,
  related_object_id uuid references reporting.objects(id) on delete set null,
  period_start date,
  period_end date,
  is_total boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end is null or period_start is null or period_end >= period_start)
);

create index ix_reporting_money_role_category on reporting.money_facts(money_role, normalized_category);
create index ix_reporting_money_event on reporting.money_facts(related_event_id, money_role) where related_event_id is not null;
create index ix_reporting_money_object on reporting.money_facts(related_object_id, money_role) where related_object_id is not null;

create table reporting.actions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references reporting.events(id) on delete restrict,
  subject_object_id uuid references reporting.objects(id) on delete set null,
  action_type text not null check (btrim(action_type) <> ''),
  disposition text not null default 'other' check (disposition in ('approved','denied','tabled','withdrawn','awarded','rejected','accepted','authorized','amended','discussed','no_action','other')),
  finality_state text not null default 'unknown' check (finality_state in ('proposed', 'final', 'procedural', 'unknown')),
  action_text text not null check (btrim(action_text) <> ''),
  occurred_at timestamptz,
  source_passage_id uuid references reporting.source_passages(id) on delete restrict,
  claim_id uuid references reporting.claims(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_passage_id is not null or claim_id is not null)
);
create index ix_reporting_actions_event on reporting.actions(event_id, occurred_at);
create index ix_reporting_actions_subject on reporting.actions(subject_object_id) where subject_object_id is not null;

create table reporting.action_votes (
  id uuid primary key default gen_random_uuid(),
  action_id uuid not null references reporting.actions(id) on delete cascade,
  voter_object_id uuid not null references reporting.objects(id) on delete restrict,
  vote_choice text not null check (vote_choice in ('yes','no','abstain','absent','recused','present','not_recorded','other')),
  source_passage_id uuid references reporting.source_passages(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (action_id, voter_object_id)
);
create index ix_reporting_action_votes_voter on reporting.action_votes(voter_object_id);

create table reporting.quotes (
  id uuid primary key default gen_random_uuid(),
  source_passage_id uuid not null references reporting.source_passages(id) on delete restrict,
  event_id uuid references reporting.events(id) on delete set null,
  speaker_object_id uuid references reporting.objects(id) on delete set null,
  speaker_label_raw text,
  quote_text text not null check (btrim(quote_text) <> ''),
  start_offset integer check (start_offset is null or start_offset >= 0),
  end_offset integer check (end_offset is null or end_offset >= 0),
  verification_state text not null default 'unverified' check (verification_state in ('unverified','machine_transcript','source_text','minutes_direct_quote','audio_verified','human_verified')),
  quote_state text not null default 'candidate' check (quote_state in ('candidate','verified','rejected')),
  machine_derived boolean not null default false,
  confidence numeric(6,5) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (speaker_object_id is not null or nullif(btrim(speaker_label_raw), '') is not null),
  check ((start_offset is null and end_offset is null) or (start_offset is not null and end_offset is not null and end_offset > start_offset)),
  check (quote_state <> 'verified' or verified_at is not null)
);
create index ix_reporting_quotes_event on reporting.quotes(event_id) where event_id is not null;
create index ix_reporting_quotes_speaker on reporting.quotes(speaker_object_id) where speaker_object_id is not null;
create index ix_reporting_quotes_passage on reporting.quotes(source_passage_id);

create or replace function reporting.set_updated_at_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_reporting_sources_updated_at before update on reporting.sources for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_objects_updated_at before update on reporting.objects for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_events_updated_at before update on reporting.events for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_topics_updated_at before update on reporting.topics for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_claims_updated_at before update on reporting.claims for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_money_facts_updated_at before update on reporting.money_facts for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_actions_updated_at before update on reporting.actions for each row execute function reporting.set_updated_at_v1();
create trigger trg_reporting_quotes_updated_at before update on reporting.quotes for each row execute function reporting.set_updated_at_v1();

create or replace function reporting.enforce_claim_evidence_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
declare
  v_claim_ids uuid[];
  v_claim_id uuid;
begin
  if tg_table_name = 'claims' then
    if tg_op = 'DELETE' then v_claim_ids := array[old.id]; else v_claim_ids := array[new.id]; end if;
  else
    if tg_op = 'INSERT' then v_claim_ids := array[new.claim_id];
    elsif tg_op = 'DELETE' then v_claim_ids := array[old.claim_id];
    else v_claim_ids := array[new.claim_id, old.claim_id];
    end if;
  end if;

  foreach v_claim_id in array v_claim_ids loop
    if v_claim_id is null then continue; end if;
    if exists (
      select 1 from reporting.claims c
      where c.id = v_claim_id
        and c.claim_state in ('source_backed', 'verified', 'disputed', 'superseded')
        and not exists (select 1 from reporting.claim_evidence e where e.claim_id = c.id)
    ) then
      raise exception 'Reporting claim % in state % requires at least one source evidence row',
        v_claim_id,
        (select c.claim_state from reporting.claims c where c.id = v_claim_id);
    end if;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create constraint trigger trg_reporting_claims_require_evidence
after insert or update on reporting.claims
deferrable initially deferred
for each row execute function reporting.enforce_claim_evidence_v1();

create constraint trigger trg_reporting_claim_evidence_preserves_claim
after insert or update or delete on reporting.claim_evidence
deferrable initially deferred
for each row execute function reporting.enforce_claim_evidence_v1();

create view reporting.v_current_sources_v1 with (security_invoker = true) as
select * from reporting.sources where source_status = 'active';

create view reporting.v_reportable_claims_v1 with (security_invoker = true) as
select c.*, (select count(*)::integer from reporting.claim_evidence e where e.claim_id = c.id) as evidence_count
from reporting.claims c
where c.claim_state in ('source_backed', 'verified', 'disputed');

create view reporting.v_reporting_core_health_v1 with (security_invoker = true) as
select
  (select count(*)::bigint from reporting.sources) as source_count,
  (select count(*)::bigint from reporting.source_passages) as passage_count,
  (select count(*)::bigint from reporting.objects) as object_count,
  (select count(*)::bigint from reporting.events) as event_count,
  (select count(*)::bigint from reporting.topics) as topic_count,
  (select count(*)::bigint from reporting.claims) as claim_count,
  (select count(*)::bigint from reporting.claims c where c.claim_state in ('source_backed','verified','disputed','superseded') and not exists (select 1 from reporting.claim_evidence e where e.claim_id = c.id)) as orphan_reportable_claims,
  (select count(*)::bigint from reporting.money_facts) as money_fact_count,
  (select count(*)::bigint from reporting.actions) as action_count,
  (select count(*)::bigint from reporting.quotes) as quote_count;

alter table reporting.sources enable row level security;
alter table reporting.source_passages enable row level security;
alter table reporting.objects enable row level security;
alter table reporting.object_aliases enable row level security;
alter table reporting.events enable row level security;
alter table reporting.event_sources enable row level security;
alter table reporting.topics enable row level security;
alter table reporting.topic_objects enable row level security;
alter table reporting.topic_sources enable row level security;
alter table reporting.topic_events enable row level security;
alter table reporting.claims enable row level security;
alter table reporting.claim_evidence enable row level security;
alter table reporting.topic_claims enable row level security;
alter table reporting.money_facts enable row level security;
alter table reporting.actions enable row level security;
alter table reporting.action_votes enable row level security;
alter table reporting.quotes enable row level security;

revoke all on all tables in schema reporting from public, anon, authenticated;
revoke all on all sequences in schema reporting from public, anon, authenticated;
revoke execute on all functions in schema reporting from public, anon, authenticated;

comment on table reporting.sources is 'Versioned source registry. Agenda proposals, final minutes, interviews, prior reporting and private notes retain distinct authority and visibility.';
comment on table reporting.source_passages is 'Precisely located text surfaces used by evidence and quotes; OCR and machine transcripts remain explicitly machine-derived.';
comment on table reporting.objects is 'Reporting-specific named objects with optional, explicitly adjudicated bindings to local_intel entity identity.';
comment on table reporting.claims is 'Source-custodied newsroom claims separating phase, verification state and conflict state.';
comment on table reporting.claim_evidence is 'Evidence membrane linking claims to exact source records and, when available, exact source passages.';
comment on table reporting.money_facts is 'Typed monetary facts attached one-to-one to claims so requests, budgets, awards and actuals cannot collapse into one amount.';
comment on table reporting.actions is 'Meeting/interview/public-event actions with explicit disposition and finality.';
comment on table reporting.quotes is 'Quote candidates and verified quotes tied to precise source passages and speaker identity or raw speaker label.';
comment on table reporting.topics is 'Continuing story/issue state that connects sources, events, objects and claims across reporting cycles.';