
create table if not exists draft.history_accounts (
  account_id bigint generated always as identity primary key,
  account_key text not null unique,
  account_title text not null,
  source_tradition text not null,
  source_language text,
  narrative_kind text not null default 'narrative',
  version_group text,
  witness_locator text not null,
  source_uri text,
  witness_basis text not null,
  chronology_note text,
  source_trace_id bigint references draft.research_traces(trace_id) on delete set null,
  status text not null default 'source_indexed' check (status in ('source_indexed','needs_source_review','superseded')),
  source_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint history_accounts_key_format check (account_key ~ '^[a-z0-9_]+$')
);
create table if not exists draft.history_scenes (
  scene_id bigint generated always as identity primary key,
  scene_key text not null unique,
  account_id bigint not null references draft.history_accounts(account_id) on delete restrict,
  scene_order integer,
  scene_title text not null,
  source_locator text not null,
  source_uri text,
  original_surface text,
  surface_basis text not null default 'not_transcribed' check (surface_basis in ('not_transcribed','edited_original','edition_transliteration','quoted_translation')),
  source_observation text not null,
  actor_label text,
  supplier_label text,
  recipient_label text,
  before_state text,
  scene_operation text not null,
  after_state text,
  material_carrier text,
  jurisdiction text,
  source_trace_id bigint references draft.research_traces(trace_id) on delete set null,
  evidence_note text,
  witness_uncertainty text,
  status text not null default 'source_paraphrase_pending_collation' check (status in ('source_paraphrase_pending_collation','edited_text_checked','physical_witness_checked','needs_revision')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint history_scenes_key_format check (scene_key ~ '^[a-z0-9_]+$'),
  constraint history_scenes_surface_source check (surface_basis = 'not_transcribed' or original_surface is not null)
);
create table if not exists draft.history_scene_functions (
  scene_id bigint not null references draft.history_scenes(scene_id) on delete cascade,
  function_key text not null references draft.function_registry(function_key) on delete restrict,
  relation_type text not null check (relation_type in ('same_operation_candidate','inverted_operation_candidate','related_operation','failure_mode','contrast_control')),
  rationale text not null,
  status text not null default 'candidate' check (status in ('candidate','pressure_testing','reviewed','rejected','superseded')),
  created_at timestamptz not null default now(),
  primary key (scene_id,function_key,relation_type)
);
create table if not exists draft.history_storylines (
  storyline_id bigint generated always as identity primary key,
  storyline_key text not null unique,
  storyline_title text not null,
  current_hypothesis text not null,
  canon_governing_refs text[] not null default '{}'::text[],
  research_trail_id bigint not null references draft.research_trails(trail_id) on delete restrict,
  version_number integer not null default 1,
  epistemic_status text not null default 'exploratory' check (epistemic_status in ('exploratory','candidate_parallel','targeted_investigation','reviewed_historical_statement','retired')),
  unresolved_question text,
  next_discriminator text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint history_storylines_key_format check (storyline_key ~ '^[a-z0-9_]+$')
);
create table if not exists draft.history_storyline_scenes (
  storyline_id bigint not null references draft.history_storylines(storyline_id) on delete cascade,
  scene_id bigint not null references draft.history_scenes(scene_id) on delete restrict,
  proposed_role text not null,
  relation_type text not null check (relation_type in ('same_operation_candidate','inverted_operation_candidate','stage_candidate','complementary_witness','contrary_witness','alternate_distribution')),
  interpretation_note text not null,
  status text not null default 'candidate' check (status in ('candidate','pressure_testing','reviewed','rejected','superseded')),
  created_at timestamptz not null default now(),
  primary key(storyline_id,scene_id,proposed_role)
);
create table if not exists draft.history_parallel_sets (
  parallel_set_id bigint generated always as identity primary key,
  parallel_key text not null unique,
  storyline_id bigint not null references draft.history_storylines(storyline_id) on delete cascade,
  parallel_title text not null,
  shared_function_hypothesis text not null,
  compound_requirement text not null,
  competing_reading text,
  next_discriminator text,
  status text not null default 'candidate' check (status in ('candidate','pressure_testing','reviewed','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint history_parallel_sets_key_format check (parallel_key ~ '^[a-z0-9_]+$')
);
create table if not exists draft.history_parallel_evidence (
  parallel_set_id bigint not null references draft.history_parallel_sets(parallel_set_id) on delete cascade,
  scene_id bigint not null references draft.history_scenes(scene_id) on delete restrict,
  evidence_role text not null check (evidence_role in ('essential_anchor','supporting_anchor','inverted_anchor','contrary_anchor')),
  contribution text not null,
  created_at timestamptz not null default now(),
  primary key (parallel_set_id,scene_id,evidence_role)
);
create table if not exists draft.history_scene_canon_links (
  canon_link_id bigint generated always as identity primary key,
  scene_id bigint not null references draft.history_scenes(scene_id) on delete cascade,
  canon_ref text not null,
  canon_witness text not null default 'Noel staged Hebrew text',
  canon_original_marks text,
  function_key text references draft.function_registry(function_key) on delete restrict,
  relation_type text not null check (relation_type in ('same_operation_candidate','inverted_operation_candidate','related_operation','contrary_control')),
  rationale text not null,
  status text not null default 'candidate' check (status in ('candidate','pressure_testing','reviewed','rejected','superseded')),
  created_at timestamptz not null default now()
);
create index if not exists history_scenes_account_order_idx on draft.history_scenes (account_id,scene_order);
create index if not exists history_scenes_search_idx on draft.history_scenes using gin (
  to_tsvector('simple',coalesce(scene_title,'')||' '||coalesce(source_observation,'')||' '||coalesce(scene_operation,'')||' '||coalesce(original_surface,''))
);
create index if not exists history_scene_functions_function_idx on draft.history_scene_functions (function_key,relation_type,scene_id);
create index if not exists history_storyline_scenes_scene_idx on draft.history_storyline_scenes (scene_id,storyline_id);
create index if not exists history_parallel_sets_storyline_idx on draft.history_parallel_sets (storyline_id);
create index if not exists history_parallel_evidence_scene_idx on draft.history_parallel_evidence (scene_id,parallel_set_id);
create index if not exists history_canon_ref_idx on draft.history_scene_canon_links (canon_ref,scene_id);
create index if not exists history_storylines_canon_gin on draft.history_storylines using gin (canon_governing_refs);
alter table draft.history_accounts enable row level security;
alter table draft.history_scenes enable row level security;
alter table draft.history_scene_functions enable row level security;
alter table draft.history_storylines enable row level security;
alter table draft.history_storyline_scenes enable row level security;
alter table draft.history_parallel_sets enable row level security;
alter table draft.history_parallel_evidence enable row level security;
alter table draft.history_scene_canon_links enable row level security;
revoke all on table draft.history_accounts,draft.history_scenes,draft.history_scene_functions,draft.history_storylines,draft.history_storyline_scenes,draft.history_parallel_sets,draft.history_parallel_evidence,draft.history_scene_canon_links from public, anon, authenticated;
grant select,insert,update,delete on table draft.history_accounts,draft.history_scenes,draft.history_scene_functions,draft.history_storylines,draft.history_storyline_scenes,draft.history_parallel_sets,draft.history_parallel_evidence,draft.history_scene_canon_links to service_role;
grant usage,select on all sequences in schema draft to service_role;
comment on table draft.history_accounts is 'History Index story/poem/myth/law witnesses; preserve independent source traditions and versions';
comment on table draft.history_scenes is 'Source-coordinate scenes: observed narrative and material distinct from canonical interpretation';
comment on table draft.history_parallel_sets is 'Compound parallel hypothesis spanning more than one independently sourced scene, not automatic lexical/identity equivalence';
