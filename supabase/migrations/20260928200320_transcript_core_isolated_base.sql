create extension if not exists pgmq;

create schema if not exists transcript_core;
comment on schema transcript_core is 'Transcript Core bounded context. No domain dependency on Noel/Atlas schemas.';

revoke all on schema transcript_core from public, anon, authenticated;

do $$ begin
  create type transcript_core.asset_provenance_class as enum (
    'observed_original','observed_derivative','script_source','generated_take','generated_render'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type transcript_core.processing_job_status as enum (
    'queued','processing','partially_processed','ready','failed_retryable','failed_terminal'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type transcript_core.transcript_revision_kind as enum ('machine','human');
exception when duplicate_object then null; end $$;

create table if not exists transcript_core.workspaces (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.workspace_memberships (
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','editor','viewer')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists transcript_core.assets (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  provenance_class transcript_core.asset_provenance_class not null,
  storage_bucket text not null,
  storage_path text not null,
  content_hash text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size >= 0),
  created_at timestamptz not null default now(),
  unique (workspace_id, storage_bucket, storage_path)
);

create table if not exists transcript_core.processing_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  job_type text not null check (job_type in ('transcribe_recording','parse_performance_script','render_voice_take','mix_performance','verify_performance')),
  status transcript_core.processing_job_status not null default 'queued',
  source_asset_id uuid references transcript_core.assets(id),
  attempt integer not null default 0 check (attempt >= 0),
  provider text,
  provider_model text,
  queue_name text,
  queue_message_id bigint,
  claimed_at timestamptz,
  heartbeat_at timestamptz,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create table if not exists transcript_core.recordings (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  source_asset_id uuid not null unique references transcript_core.assets(id),
  title text not null,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.transcripts (
  id uuid primary key default extensions.gen_random_uuid(),
  recording_id uuid not null unique references transcript_core.recordings(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.transcript_revisions (
  id uuid primary key default extensions.gen_random_uuid(),
  transcript_id uuid not null references transcript_core.transcripts(id) on delete cascade,
  ordinal integer not null check (ordinal > 0),
  revision_kind transcript_core.transcript_revision_kind not null,
  source_job_id uuid unique references transcript_core.processing_jobs(id),
  provider text,
  provider_model text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (transcript_id, ordinal)
);

alter table transcript_core.transcripts
  add column if not exists current_revision_id uuid references transcript_core.transcript_revisions(id);

create table if not exists transcript_core.transcript_segments (
  id uuid primary key default extensions.gen_random_uuid(),
  transcript_id uuid not null references transcript_core.transcripts(id) on delete cascade,
  sequence integer not null,
  anchor_start_ms bigint not null check (anchor_start_ms >= 0),
  anchor_end_ms bigint not null check (anchor_end_ms >= anchor_start_ms),
  created_at timestamptz not null default now(),
  unique (transcript_id, sequence)
);

create table if not exists transcript_core.transcript_segment_versions (
  transcript_revision_id uuid not null references transcript_core.transcript_revisions(id) on delete cascade,
  transcript_segment_id uuid not null references transcript_core.transcript_segments(id) on delete cascade,
  start_ms bigint not null check (start_ms >= 0),
  end_ms bigint not null check (end_ms >= start_ms),
  text text not null,
  provider_speaker text,
  primary key (transcript_revision_id, transcript_segment_id)
);

create table if not exists transcript_core.script_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  title text not null,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.script_revisions (
  id uuid primary key default extensions.gen_random_uuid(),
  script_document_id uuid not null references transcript_core.script_documents(id) on delete cascade,
  source_asset_id uuid not null unique references transcript_core.assets(id),
  content_hash text not null,
  parser_adapter text,
  parser_version text,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.performance_scripts (
  id uuid primary key default extensions.gen_random_uuid(),
  script_revision_id uuid not null references transcript_core.script_revisions(id) on delete cascade,
  source_job_id uuid unique references transcript_core.processing_jobs(id),
  parser_adapter text not null,
  parser_version text not null,
  created_at timestamptz not null default now()
);

create table if not exists transcript_core.cast_roles (
  id uuid primary key default extensions.gen_random_uuid(),
  performance_script_id uuid not null references transcript_core.performance_scripts(id) on delete cascade,
  role_key text not null,
  display_name text not null,
  unique (performance_script_id, role_key)
);

create table if not exists transcript_core.performance_cues (
  id uuid primary key default extensions.gen_random_uuid(),
  performance_script_id uuid not null references transcript_core.performance_scripts(id) on delete cascade,
  sequence integer not null,
  speakers text[] not null,
  dialogue text not null,
  instructions_before text[] not null default '{}',
  synchronization_mode text not null check (synchronization_mode in ('sequential','unison')),
  source_paragraph integer not null,
  source_style text not null,
  unique (performance_script_id, sequence)
);

create table if not exists transcript_core.performance_parse_events (
  id uuid primary key default extensions.gen_random_uuid(),
  performance_script_id uuid not null references transcript_core.performance_scripts(id) on delete cascade,
  sequence integer not null,
  event_kind text not null check (event_kind in ('speaker','instruction','dialogue')),
  payload jsonb not null,
  source_paragraph integer not null,
  source_style text not null,
  unique (performance_script_id, sequence)
);

create table if not exists transcript_core.source_ingests (
  id uuid primary key,
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  source_kind text not null check (source_kind in ('recording','script')),
  asset_id uuid references transcript_core.assets(id),
  recording_id uuid references transcript_core.recordings(id),
  script_document_id uuid references transcript_core.script_documents(id),
  script_revision_id uuid references transcript_core.script_revisions(id),
  processing_job_id uuid references transcript_core.processing_jobs(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists tc_jobs_workspace_status_idx on transcript_core.processing_jobs(workspace_id, status, created_at);
create index if not exists tc_assets_workspace_idx on transcript_core.assets(workspace_id, created_at);
create index if not exists tc_segments_transcript_idx on transcript_core.transcript_segments(transcript_id, sequence);
create index if not exists tc_cues_script_idx on transcript_core.performance_cues(performance_script_id, sequence);

alter table transcript_core.workspaces enable row level security;
alter table transcript_core.workspace_memberships enable row level security;
alter table transcript_core.assets enable row level security;
alter table transcript_core.processing_jobs enable row level security;
alter table transcript_core.recordings enable row level security;
alter table transcript_core.transcripts enable row level security;
alter table transcript_core.transcript_revisions enable row level security;
alter table transcript_core.transcript_segments enable row level security;
alter table transcript_core.transcript_segment_versions enable row level security;
alter table transcript_core.script_documents enable row level security;
alter table transcript_core.script_revisions enable row level security;
alter table transcript_core.performance_scripts enable row level security;
alter table transcript_core.cast_roles enable row level security;
alter table transcript_core.performance_cues enable row level security;
alter table transcript_core.performance_parse_events enable row level security;
alter table transcript_core.source_ingests enable row level security;

insert into storage.buckets (id, name, public)
values
  ('transcript-core-observed-originals','transcript-core-observed-originals',false),
  ('transcript-core-observed-derivatives','transcript-core-observed-derivatives',false),
  ('transcript-core-script-sources','transcript-core-script-sources',false),
  ('transcript-core-generated-takes','transcript-core-generated-takes',false),
  ('transcript-core-generated-renders','transcript-core-generated-renders',false)
on conflict (id) do update set public = false;

do $$
declare q text;
begin
  foreach q in array array[
    'transcript_core_transcription_jobs',
    'transcript_core_performance_parse_jobs',
    'transcript_core_voice_render_jobs',
    'transcript_core_performance_mix_jobs',
    'transcript_core_performance_verify_jobs'
  ]
  loop
    if not exists (select 1 from pgmq.list_queues() where queue_name = q) then
      perform pgmq.create(q);
    end if;
  end loop;
end $$;