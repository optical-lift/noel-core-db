create table if not exists titus.teacher_categories (
  category_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  category_key text not null,
  category_name text not null,
  description text,
  status text not null default 'candidate' check (status in ('candidate','active','merged','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, category_key)
);

create table if not exists titus.teacher_topics (
  topic_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  topic_key text not null,
  topic_name text not null,
  description text,
  status text not null default 'candidate' check (status in ('candidate','active','merged','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, topic_key)
);

create table if not exists titus.teacher_topic_category_links (
  topic_category_link_id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references titus.teacher_topics(topic_id) on delete cascade,
  category_id uuid not null references titus.teacher_categories(category_id) on delete cascade,
  relation_type text not null default 'primary' check (relation_type in ('primary','supporting','cross_domain')),
  notes text,
  created_at timestamptz not null default now(),
  unique (topic_id, category_id, relation_type)
);

create table if not exists titus.teacher_source_unit_category_links (
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  category_id uuid not null references titus.teacher_categories(category_id) on delete cascade,
  relevance text not null default 'primary' check (relevance in ('primary','supporting','contrast')),
  notes text,
  created_at timestamptz not null default now(),
  primary key (source_unit_id, category_id)
);

create table if not exists titus.teacher_source_unit_topic_links (
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  topic_id uuid not null references titus.teacher_topics(topic_id) on delete cascade,
  relevance text not null default 'primary' check (relevance in ('primary','supporting','contrast')),
  notes text,
  created_at timestamptz not null default now(),
  primary key (source_unit_id, topic_id)
);

create table if not exists titus.teacher_term_senses (
  teacher_term_sense_id uuid primary key default gen_random_uuid(),
  teacher_term_id uuid not null references titus.teacher_terms(teacher_term_id) on delete cascade,
  sense_key text not null,
  sense_label text not null,
  working_definition text,
  sense_status text not null default 'candidate' check (sense_status in ('candidate','attested','preferred','restricted','superseded','retired')),
  earliest_attested_date date,
  latest_attested_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_term_id, sense_key)
);

create table if not exists titus.teacher_term_definitions (
  teacher_term_definition_id uuid primary key default gen_random_uuid(),
  teacher_term_id uuid not null references titus.teacher_terms(teacher_term_id) on delete cascade,
  teacher_term_sense_id uuid references titus.teacher_term_senses(teacher_term_sense_id) on delete set null,
  teacher_source_ref_id uuid references titus.teacher_source_refs(teacher_source_ref_id) on delete set null,
  source_unit_id uuid references titus.teacher_source_units(source_unit_id) on delete set null,
  definition_kind text not null default 'explicit' check (definition_kind in ('explicit','characterization','contrastive','implicit','reconstructed')),
  definition_text text not null,
  source_locator jsonb not null default '{}'::jsonb,
  status text not null default 'candidate' check (status in ('candidate','reviewed','confirmed','superseded','retired')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (teacher_source_ref_id is not null or source_unit_id is not null)
);

create table if not exists titus.teacher_concepts (
  teacher_concept_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  concept_key text not null,
  concept_name text not null,
  concept_kind text not null default 'concept' check (concept_kind in ('concept','distinction','framework','diagnostic_question','causal_model','teaching_method','metaphor','principle_label','other')),
  native_label text,
  working_description text,
  concept_status text not null default 'candidate' check (concept_status in ('candidate','recurring','established','disputed','merged','retired')),
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  chronology_note text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, concept_key)
);

create table if not exists titus.teacher_concept_evidence (
  teacher_concept_evidence_id uuid primary key default gen_random_uuid(),
  teacher_concept_id uuid not null references titus.teacher_concepts(teacher_concept_id) on delete cascade,
  teacher_source_ref_id uuid references titus.teacher_source_refs(teacher_source_ref_id) on delete set null,
  source_unit_id uuid references titus.teacher_source_units(source_unit_id) on delete set null,
  evidence_role text not null default 'supporting' check (evidence_role in ('defining','supporting','development','contrast','counterexample')),
  observed_expression text,
  source_locator jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  check (teacher_source_ref_id is not null or source_unit_id is not null)
);

create table if not exists titus.teacher_source_function_codings (
  function_coding_id uuid primary key default gen_random_uuid(),
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  observed_condition text,
  before_state text,
  operation text,
  after_state text,
  source_claim text,
  carrier text,
  target text,
  jurisdiction text,
  timing_phase text,
  custody_handoff text,
  authorization_basis text,
  intended_or_claimed_fruit text,
  failure_mode text,
  scale text,
  coding_status text not null default 'candidate' check (coding_status in ('candidate','reviewed','confirmed','superseded','retired')),
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  coding_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists titus.teacher_patterns (
  teacher_pattern_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  pattern_key text not null,
  pattern_name text not null,
  pattern_type text not null default 'relation' check (pattern_type in ('relation','sequence','state_transition','causal_chain','custody_chain','jurisdiction_pattern','source_pattern','formation_pattern','failure_repair_pattern','cross_domain_homology','other')),
  working_summary text not null,
  before_state text,
  operation text,
  after_state text,
  source_relation text,
  jurisdiction text,
  timing_phase text,
  custody_handoff text,
  fruit text,
  failure_mode text,
  scale text,
  pattern_status text not null default 'candidate' check (pattern_status in ('candidate','recurring','established','disputed','superseded','retired')),
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  chronology_note text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, pattern_key)
);

create table if not exists titus.teacher_pattern_members (
  teacher_pattern_member_id uuid primary key default gen_random_uuid(),
  teacher_pattern_id uuid not null references titus.teacher_patterns(teacher_pattern_id) on delete cascade,
  teacher_concept_id uuid references titus.teacher_concepts(teacher_concept_id) on delete cascade,
  teacher_term_id uuid references titus.teacher_terms(teacher_term_id) on delete cascade,
  member_role text not null default 'participates' check (member_role in ('source','input','condition','carrier','operation','target','boundary','timing','custody','output','fruit','failure','contrast','participates')),
  notes text,
  created_at timestamptz not null default now(),
  check ((teacher_concept_id is not null)::int + (teacher_term_id is not null)::int = 1)
);

create table if not exists titus.teacher_pattern_evidence (
  teacher_pattern_evidence_id uuid primary key default gen_random_uuid(),
  teacher_pattern_id uuid not null references titus.teacher_patterns(teacher_pattern_id) on delete cascade,
  teacher_source_ref_id uuid references titus.teacher_source_refs(teacher_source_ref_id) on delete set null,
  source_unit_id uuid references titus.teacher_source_units(source_unit_id) on delete set null,
  evidence_role text not null default 'supporting' check (evidence_role in ('defining','supporting','cross_domain_repeat','development','pressure','counterexample')),
  observed_expression text,
  source_locator jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  check (teacher_source_ref_id is not null or source_unit_id is not null)
);

create table if not exists titus.teacher_pattern_song_links (
  teacher_pattern_song_link_id uuid primary key default gen_random_uuid(),
  teacher_pattern_id uuid not null references titus.teacher_patterns(teacher_pattern_id) on delete cascade,
  song_object_id bigint references draft.song_objects(song_object_id) on update cascade on delete restrict,
  function_key text references draft.function_registry(function_key) on update cascade on delete restrict,
  relation_type text not null check (relation_type in ('direct_alignment','partial_alignment','umbrella_over','subset_of','combines_with','missing_condition','directionally_correct','conflict','false_collapse','contrast','other')),
  relation_note text,
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  song_label_snapshot text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((song_object_id is not null)::int + (function_key is not null)::int = 1)
);

create or replace view titus.v_teacher_pattern_song_live as
select
  p.teacher_pattern_id,
  p.teacher_id,
  p.pattern_key,
  p.pattern_name,
  p.pattern_status,
  p.working_summary,
  l.teacher_pattern_song_link_id,
  case when l.song_object_id is not null then 'song_object' else 'function' end as target_kind,
  l.song_object_id,
  l.function_key,
  coalesce(so.object_name, fr.function_name) as live_target_name,
  coalesce(so.object_status, fr.status) as live_target_status,
  case when l.song_object_id is not null then so.one_sentence_claim else fr.working_definition end as live_target_definition,
  case when l.song_object_id is not null then so.provisional_function_lane else fr.operation end as live_operation_or_lane,
  case when l.song_object_id is not null then so.updated_at else fr.updated_at end as live_target_updated_at,
  l.relation_type,
  l.relation_note,
  l.confidence,
  l.review_status,
  l.song_label_snapshot,
  l.created_at as linked_at,
  l.updated_at as link_updated_at
from titus.teacher_patterns p
join titus.teacher_pattern_song_links l on l.teacher_pattern_id = p.teacher_pattern_id
left join draft.song_objects so on so.song_object_id = l.song_object_id
left join draft.function_registry fr on fr.function_key = l.function_key;

comment on table titus.teacher_source_function_codings is 'Song-aware conversion layer: describe a teacher source unit in functional anatomy without requiring the teacher to have used Song vocabulary.';
comment on table titus.teacher_patterns is 'Teacher-native recurring patterns reconstructed from corpus evidence. Patterns are not approved teaching until separately adjudicated.';
comment on table titus.teacher_pattern_song_links is 'Live links from reconstructed teacher patterns to current Song objects or Function registry entries. Snapshots are audit-only; current meaning resolves through foreign keys.';
comment on view titus.v_teacher_pattern_song_live is 'Always resolves teacher-pattern links against the current live Song object or Function definition.';