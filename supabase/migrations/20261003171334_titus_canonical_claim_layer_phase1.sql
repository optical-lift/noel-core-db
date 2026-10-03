create table titus.truth_refs (
  truth_ref_id uuid primary key default gen_random_uuid(),
  ref_kind text not null check (ref_kind in ('song_object','function')),
  song_object_id bigint null references draft.song_objects(song_object_id),
  function_key text null references draft.function_registry(function_key),
  label_snapshot text null,
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint truth_refs_exactly_one_target check (
    (ref_kind = 'song_object' and song_object_id is not null and function_key is null)
    or
    (ref_kind = 'function' and function_key is not null and song_object_id is null)
  )
);

create unique index truth_refs_song_object_uq
  on titus.truth_refs(song_object_id)
  where song_object_id is not null;

create unique index truth_refs_function_uq
  on titus.truth_refs(function_key)
  where function_key is not null;

comment on table titus.truth_refs is 'Stable Titus pointers into live Noel/Song truth objects. Stores identifiers and audit snapshots only; present meaning resolves live from draft.song_objects or draft.function_registry.';
comment on column titus.truth_refs.label_snapshot is 'Audit-only label captured when the reference is created or deliberately refreshed. Never authoritative for current Noel/Song meaning.';

create table titus.canon_claims (
  canon_claim_id uuid primary key default gen_random_uuid(),
  program_id uuid null references titus.programs(program_id),
  claim_key text not null unique,
  claim_text text not null,
  claim_kind text not null check (claim_kind in (
    'positive_rule','distinction','operation_rule','source_rule','jurisdiction_rule',
    'causal_rule','diagnostic_rule','guardrail','negative_rule','other'
  )),
  status text not null default 'candidate' check (status in ('candidate','reviewed','approved','superseded','retired')),
  confidence text null check (confidence is null or confidence in ('low','medium','high')),
  originating_finding_id uuid null references titus.curriculum_findings(finding_id),
  supersedes_claim_id uuid null references titus.canon_claims(canon_claim_id),
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index canon_claims_program_idx on titus.canon_claims(program_id);
create index canon_claims_originating_finding_idx on titus.canon_claims(originating_finding_id);
create index canon_claims_supersedes_idx on titus.canon_claims(supersedes_claim_id);

comment on table titus.canon_claims is 'Reusable corrected teaching claims established from canon/Noel research. Claims are Titus teaching objects, not copied Noel research state.';

create table titus.canon_claim_truth_links (
  canon_claim_truth_link_id uuid primary key default gen_random_uuid(),
  canon_claim_id uuid not null references titus.canon_claims(canon_claim_id) on delete cascade,
  truth_ref_id uuid not null references titus.truth_refs(truth_ref_id),
  relation_type text not null check (relation_type in (
    'primary','supporting','guardrail','contrast','prerequisite','partial_alignment','other'
  )),
  relation_note text null,
  confidence text null check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (canon_claim_id, truth_ref_id, relation_type)
);

create index canon_claim_truth_links_claim_idx on titus.canon_claim_truth_links(canon_claim_id);
create index canon_claim_truth_links_truth_idx on titus.canon_claim_truth_links(truth_ref_id);

comment on table titus.canon_claim_truth_links is 'Many-to-many bridge from corrected Titus canon claims to live Noel/Song truth references.';

create table titus.canon_claim_evidence (
  canon_claim_evidence_id uuid primary key default gen_random_uuid(),
  canon_claim_id uuid not null references titus.canon_claims(canon_claim_id) on delete cascade,
  book text not null,
  chapter integer not null check (chapter > 0),
  start_verse integer not null check (start_verse > 0),
  end_verse integer not null check (end_verse >= start_verse),
  evidence_role text not null check (evidence_role in (
    'primary_anchor','supporting','boundary','contrast','counterexample','failure_case','original_language','other'
  )),
  evidence_note text null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (canon_claim_id, book, chapter, start_verse, end_verse, evidence_role)
);

create index canon_claim_evidence_claim_idx on titus.canon_claim_evidence(canon_claim_id, sort_order);
create index canon_claim_evidence_passage_idx on titus.canon_claim_evidence(book, chapter, start_verse, end_verse);

comment on table titus.canon_claim_evidence is 'Passage-level warrant for a specific corrected canon claim. Stores coordinates and the evidentiary role, not a duplicate biblical corpus.';

create table titus.canon_brief_items (
  canon_brief_item_id uuid primary key default gen_random_uuid(),
  canon_brief_id uuid not null references titus.slot_canon_briefs(canon_brief_id) on delete cascade,
  item_type text not null check (item_type in ('must_teach','must_distinguish','must_not_collapse','known_limit')),
  canon_claim_id uuid null references titus.canon_claims(canon_claim_id),
  item_text_snapshot text not null,
  sort_order integer not null default 0,
  status text not null default 'active' check (status in ('active','superseded','retired')),
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (canon_brief_id, item_type, sort_order)
);

create index canon_brief_items_brief_idx on titus.canon_brief_items(canon_brief_id, item_type, sort_order);
create index canon_brief_items_claim_idx on titus.canon_brief_items(canon_claim_id) where canon_claim_id is not null;

comment on table titus.canon_brief_items is 'Normalized projection of canon brief teaching requirements. Existing slot_canon_briefs arrays remain for compatibility while these rows become addressable and linkable.';

create table titus.teacher_pattern_claim_links (
  teacher_pattern_claim_link_id uuid primary key default gen_random_uuid(),
  teacher_pattern_id uuid not null references titus.teacher_patterns(teacher_pattern_id) on delete cascade,
  canon_claim_id uuid not null references titus.canon_claims(canon_claim_id) on delete cascade,
  relation_type text not null check (relation_type in (
    'supports','partial_alignment','broader_than','narrower_than','requires_guardrail',
    'conflicts','counterexample','teacher_expression_of','other'
  )),
  relation_note text null,
  confidence text null check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_pattern_id, canon_claim_id, relation_type)
);

create index teacher_pattern_claim_links_pattern_idx on titus.teacher_pattern_claim_links(teacher_pattern_id);
create index teacher_pattern_claim_links_claim_idx on titus.teacher_pattern_claim_links(canon_claim_id);

comment on table titus.teacher_pattern_claim_links is 'Formal bridge from teacher-native recurring architecture to corrected reusable canon claims. This is distinct from Song-object alignment.';

create table titus.lesson_claim_links (
  lesson_claim_link_id uuid primary key default gen_random_uuid(),
  lesson_slug text not null references titus.lesson_packets(lesson_slug) on delete cascade,
  canon_claim_id uuid not null references titus.canon_claims(canon_claim_id),
  lesson_role text not null check (lesson_role in (
    'foundation','core_explanation','distinction','guardrail','case_control','diagnostic','application','other'
  )),
  teaching_phrase text null,
  sort_order integer not null default 0,
  status text not null default 'candidate' check (status in ('candidate','approved','rejected','retired')),
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_slug, canon_claim_id, lesson_role)
);

create index lesson_claim_links_lesson_idx on titus.lesson_claim_links(lesson_slug, sort_order);
create index lesson_claim_links_claim_idx on titus.lesson_claim_links(canon_claim_id);

comment on table titus.lesson_claim_links is 'Curriculum projection: lessons consume reusable canon claims rather than owning the claims themselves.';

create or replace view titus.v_truth_refs_live as
select
  tr.truth_ref_id,
  tr.ref_kind,
  tr.song_object_id,
  tr.function_key,
  tr.label_snapshot,
  case when tr.ref_kind = 'song_object' then so.object_name else fr.function_name end as live_label,
  case when tr.ref_kind = 'song_object' then so.provisional_function_lane else fr.working_definition end as live_definition,
  case when tr.ref_kind = 'song_object' then so.one_sentence_claim else fr.operation end as live_operation_or_claim,
  case when tr.ref_kind = 'song_object' then so.object_status else fr.status end as live_status,
  tr.notes,
  tr.created_at,
  tr.updated_at
from titus.truth_refs tr
left join draft.song_objects so on tr.song_object_id = so.song_object_id
left join draft.function_registry fr on tr.function_key = fr.function_key;

create or replace view titus.v_canon_claims_live as
select
  c.canon_claim_id,
  c.program_id,
  c.claim_key,
  c.claim_text,
  c.claim_kind,
  c.status,
  c.confidence,
  c.originating_finding_id,
  c.supersedes_claim_id,
  c.notes,
  c.created_at,
  c.updated_at,
  (select count(*) from titus.canon_claim_evidence e where e.canon_claim_id = c.canon_claim_id) as evidence_count,
  (select count(*) from titus.canon_claim_truth_links l where l.canon_claim_id = c.canon_claim_id and l.review_status in ('reviewed','approved')) as reviewed_truth_ref_count,
  (select count(*) from titus.teacher_pattern_claim_links p where p.canon_claim_id = c.canon_claim_id and p.review_status in ('reviewed','approved')) as reviewed_teacher_pattern_count,
  (select count(*) from titus.lesson_claim_links ll where ll.canon_claim_id = c.canon_claim_id and ll.status = 'approved') as approved_lesson_count
from titus.canon_claims c;

create or replace view titus.v_lesson_claim_map as
select
  ll.lesson_slug,
  lp.title as lesson_title,
  ll.lesson_role,
  ll.sort_order,
  ll.status as lesson_link_status,
  ll.teaching_phrase,
  c.canon_claim_id,
  c.claim_key,
  c.claim_text,
  c.claim_kind,
  c.status as claim_status,
  c.confidence as claim_confidence
from titus.lesson_claim_links ll
join titus.lesson_packets lp on lp.lesson_slug = ll.lesson_slug
join titus.canon_claims c on c.canon_claim_id = ll.canon_claim_id;

alter table titus.truth_refs enable row level security;
alter table titus.canon_claims enable row level security;
alter table titus.canon_claim_truth_links enable row level security;
alter table titus.canon_claim_evidence enable row level security;
alter table titus.canon_brief_items enable row level security;
alter table titus.teacher_pattern_claim_links enable row level security;
alter table titus.lesson_claim_links enable row level security;

revoke all on titus.truth_refs, titus.canon_claims, titus.canon_claim_truth_links,
  titus.canon_claim_evidence, titus.canon_brief_items, titus.teacher_pattern_claim_links,
  titus.lesson_claim_links from anon, authenticated;

grant select, insert, update, delete on titus.truth_refs, titus.canon_claims,
  titus.canon_claim_truth_links, titus.canon_claim_evidence, titus.canon_brief_items,
  titus.teacher_pattern_claim_links, titus.lesson_claim_links to service_role;

grant select on titus.v_truth_refs_live, titus.v_canon_claims_live, titus.v_lesson_claim_map to service_role;