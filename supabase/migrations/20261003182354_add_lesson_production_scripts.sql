create table if not exists titus.lesson_scripts (
  lesson_script_id uuid primary key default gen_random_uuid(),
  lesson_slug text not null references titus.lesson_packets(lesson_slug) on delete cascade,
  script_version integer not null default 1 check (script_version > 0),
  script_title text not null,
  script_status text not null default 'draft' check (script_status in ('draft','review','approved','recorded','retired')),
  target_minutes integer not null default 90 check (target_minutes > 0),
  voice_basis text,
  governing_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_slug, script_version)
);

create table if not exists titus.lesson_script_segments (
  lesson_script_segment_id uuid primary key default gen_random_uuid(),
  lesson_script_id uuid not null references titus.lesson_scripts(lesson_script_id) on delete cascade,
  segment_code text not null,
  heading text not null,
  start_minute integer not null check (start_minute >= 0),
  end_minute integer not null check (end_minute > start_minute),
  teaching_purpose text,
  spoken_copy text not null,
  production_notes jsonb not null default '{}'::jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_script_id, segment_code)
);

create table if not exists titus.lesson_script_segment_claims (
  lesson_script_segment_id uuid not null references titus.lesson_script_segments(lesson_script_segment_id) on delete cascade,
  canon_claim_id uuid not null references titus.canon_claims(canon_claim_id) on delete restrict,
  role text not null default 'governing' check (role in ('governing','supporting','guardrail','contrast')),
  primary key (lesson_script_segment_id, canon_claim_id, role)
);

alter table titus.lesson_scripts enable row level security;
alter table titus.lesson_script_segments enable row level security;
alter table titus.lesson_script_segment_claims enable row level security;
revoke all on titus.lesson_scripts from anon, authenticated;
revoke all on titus.lesson_script_segments from anon, authenticated;
revoke all on titus.lesson_script_segment_claims from anon, authenticated;

create index if not exists idx_lesson_script_segments_script_order on titus.lesson_script_segments(lesson_script_id, sort_order);
create index if not exists idx_lesson_script_segment_claims_claim on titus.lesson_script_segment_claims(canon_claim_id);