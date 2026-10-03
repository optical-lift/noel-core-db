alter type transcript_core.asset_provenance_class
  add value if not exists 'authored_performance_take';
alter type transcript_core.asset_provenance_class
  add value if not exists 'authored_performance_master';

create table if not exists transcript_core.manuscript_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  title text not null,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.manuscript_revisions (
  id uuid primary key default extensions.gen_random_uuid(),
  manuscript_document_id uuid not null references transcript_core.manuscript_documents(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  source_asset_id uuid references transcript_core.assets(id),
  content_hash text not null,
  source_format text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (manuscript_document_id, ordinal)
);

create table if not exists transcript_core.narration_units (
  id uuid primary key default extensions.gen_random_uuid(),
  manuscript_revision_id uuid not null references transcript_core.manuscript_revisions(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  unit_kind text not null check (unit_kind in ('paragraph','paragraph_group','sentence','custom')),
  chapter_key text,
  chapter_title text,
  pov_key text,
  pov_display_name text,
  text text not null,
  source_anchor jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (manuscript_revision_id, sequence)
);

create table if not exists transcript_core.productions (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  title text not null,
  production_kind text not null check (production_kind in ('audiobook','readers_theatre','voiceover','audio_drama','narrated_curriculum','training','other')),
  status text not null default 'planning' check (status in ('planning','in_production','proofing','mastering','delivered','archived')),
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.production_sources (
  production_id uuid primary key references transcript_core.productions(id) on delete cascade,
  script_revision_id uuid references transcript_core.script_revisions(id),
  manuscript_revision_id uuid references transcript_core.manuscript_revisions(id),
  created_at timestamptz not null default now(),
  check (((script_revision_id is not null)::integer + (manuscript_revision_id is not null)::integer) = 1)
);

create table if not exists transcript_core.recording_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  performer_kind text not null check (performer_kind in ('human_person','voice_profile','label')),
  performer_ref text not null,
  performer_display_name text not null,
  started_at timestamptz,
  ended_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  check (ended_at is null or started_at is null or ended_at >= started_at)
);

create table if not exists transcript_core.performance_takes (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  recording_session_id uuid references transcript_core.recording_sessions(id) on delete set null,
  performance_cue_id uuid references transcript_core.performance_cues(id) on delete cascade,
  narration_unit_id uuid references transcript_core.narration_units(id) on delete cascade,
  participant_key text,
  origin text not null check (origin in ('human_recording','generated_voice')),
  performer_kind text not null check (performer_kind in ('human_person','voice_profile','label')),
  performer_ref text not null,
  performer_display_name text not null,
  audio_asset_id uuid not null references transcript_core.assets(id),
  audio_start_ms bigint not null default 0 check (audio_start_ms >= 0),
  audio_end_ms bigint check (audio_end_ms is null or audio_end_ms >= audio_start_ms),
  take_number integer not null check (take_number > 0),
  status text not null default 'available' check (status in ('available','rejected','superseded')),
  created_at timestamptz not null default now(),
  check (((performance_cue_id is not null)::integer + (narration_unit_id is not null)::integer) = 1)
);

create table if not exists transcript_core.take_selections (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  performance_cue_id uuid references transcript_core.performance_cues(id) on delete cascade,
  narration_unit_id uuid references transcript_core.narration_units(id) on delete cascade,
  participant_key text not null default '',
  selected_take_id uuid not null references transcript_core.performance_takes(id),
  selected_by uuid references auth.users(id),
  selected_at timestamptz not null default now(),
  check (((performance_cue_id is not null)::integer + (narration_unit_id is not null)::integer) = 1)
);

create unique index if not exists take_selections_cue_uidx
  on transcript_core.take_selections(production_id, performance_cue_id, participant_key)
  where performance_cue_id is not null;
create unique index if not exists take_selections_narration_uidx
  on transcript_core.take_selections(production_id, narration_unit_id, participant_key)
  where narration_unit_id is not null;

create table if not exists transcript_core.proofing_passes (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  pass_kind text not null check (pass_kind in ('text_match','performance','technical','final')),
  performed_by text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (production_id, ordinal),
  check (completed_at is null or completed_at >= started_at)
);

create table if not exists transcript_core.proofing_issues (
  id uuid primary key default extensions.gen_random_uuid(),
  proofing_pass_id uuid not null references transcript_core.proofing_passes(id) on delete cascade,
  performance_cue_id uuid references transcript_core.performance_cues(id) on delete cascade,
  narration_unit_id uuid references transcript_core.narration_units(id) on delete cascade,
  participant_key text,
  performance_take_id uuid references transcript_core.performance_takes(id) on delete set null,
  issue_kind text not null check (issue_kind in ('misread','omission','insertion','pronunciation','noise','performance','timing','other')),
  status text not null default 'open' check (status in ('open','accepted','pickup_required','resolved')),
  expected_text text,
  observed_text text,
  note text,
  source_anchor jsonb,
  audio_start_ms bigint check (audio_start_ms is null or audio_start_ms >= 0),
  audio_end_ms bigint,
  created_at timestamptz not null default now(),
  check (((performance_cue_id is not null)::integer + (narration_unit_id is not null)::integer) = 1),
  check (audio_end_ms is null or audio_start_ms is null or audio_end_ms >= audio_start_ms)
);

create table if not exists transcript_core.pickup_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  proofing_issue_id uuid references transcript_core.proofing_issues(id) on delete set null,
  performance_cue_id uuid references transcript_core.performance_cues(id) on delete cascade,
  narration_unit_id uuid references transcript_core.narration_units(id) on delete cascade,
  participant_key text,
  instruction text,
  status text not null default 'requested' check (status in ('requested','recorded','approved','cancelled')),
  replacement_take_id uuid references transcript_core.performance_takes(id) on delete set null,
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  check (((performance_cue_id is not null)::integer + (narration_unit_id is not null)::integer) = 1),
  check (approved_at is null or approved_at >= requested_at)
);

create table if not exists transcript_core.text_audio_alignments (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  performance_take_id uuid not null references transcript_core.performance_takes(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  granularity text not null check (granularity in ('unit','sentence','word','custom')),
  source_anchor jsonb not null,
  audio_start_ms bigint not null check (audio_start_ms >= 0),
  audio_end_ms bigint not null check (audio_end_ms >= audio_start_ms),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_by_kind text not null check (created_by_kind in ('machine','human')),
  created_at timestamptz not null default now(),
  unique (performance_take_id, sequence)
);

create table if not exists transcript_core.production_masters (
  id uuid primary key default extensions.gen_random_uuid(),
  production_id uuid not null references transcript_core.productions(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  audio_asset_id uuid not null references transcript_core.assets(id),
  timeline_manifest jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (production_id, ordinal)
);

create table if not exists transcript_core.delivery_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  profile_key text not null,
  display_name text not null,
  rule_version text not null,
  configuration jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (workspace_id, profile_key, rule_version)
);

create table if not exists transcript_core.delivery_packages (
  id uuid primary key default extensions.gen_random_uuid(),
  production_master_id uuid not null references transcript_core.production_masters(id) on delete cascade,
  delivery_profile_id uuid not null references transcript_core.delivery_profiles(id),
  status text not null default 'pending' check (status in ('pending','valid','invalid','exported')),
  validation_report jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists narration_units_revision_idx
  on transcript_core.narration_units(manuscript_revision_id, sequence);
create index if not exists productions_workspace_idx
  on transcript_core.productions(workspace_id, created_at desc);
create index if not exists performance_takes_production_idx
  on transcript_core.performance_takes(production_id, created_at);
create index if not exists proofing_issues_pass_status_idx
  on transcript_core.proofing_issues(proofing_pass_id, status);
create index if not exists pickup_requests_production_status_idx
  on transcript_core.pickup_requests(production_id, status);
create index if not exists text_audio_alignments_take_idx
  on transcript_core.text_audio_alignments(performance_take_id, sequence);

alter table transcript_core.manuscript_documents enable row level security;
alter table transcript_core.manuscript_revisions enable row level security;
alter table transcript_core.narration_units enable row level security;
alter table transcript_core.productions enable row level security;
alter table transcript_core.production_sources enable row level security;
alter table transcript_core.recording_sessions enable row level security;
alter table transcript_core.performance_takes enable row level security;
alter table transcript_core.take_selections enable row level security;
alter table transcript_core.proofing_passes enable row level security;
alter table transcript_core.proofing_issues enable row level security;
alter table transcript_core.pickup_requests enable row level security;
alter table transcript_core.text_audio_alignments enable row level security;
alter table transcript_core.production_masters enable row level security;
alter table transcript_core.delivery_profiles enable row level security;
alter table transcript_core.delivery_packages enable row level security;