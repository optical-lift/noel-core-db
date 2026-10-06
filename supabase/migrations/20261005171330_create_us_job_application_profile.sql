create schema if not exists us;

revoke all on schema us from public;
revoke all on schema us from anon;
revoke all on schema us from authenticated;

create table if not exists us.people (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  full_name text not null,
  preferred_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists us.job_application_profiles (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null unique references us.people(id) on delete cascade,
  primary_email text,
  phone text,
  linkedin_url text,
  linkedin_status text,
  home_state text,
  country_code text not null default 'US',
  education_status text,
  minimum_base_salary_usd integer,
  search_preferences jsonb not null default '{}'::jsonb,
  profile_notes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists us.employment_history (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references us.people(id) on delete cascade,
  employer text not null,
  title text not null,
  location text,
  start_year integer not null,
  start_month integer check (start_month between 1 and 12),
  end_year integer,
  end_month integer check (end_month between 1 and 12),
  is_current boolean not null default false,
  summary text,
  resume_group text,
  date_notes text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(person_id, employer, title, start_year)
);

create table if not exists us.resume_variants (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references us.people(id) on delete cascade,
  slug text not null,
  name text not null,
  target_track text not null,
  positioning text,
  selection_guidance text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(person_id, slug)
);

create table if not exists us.application_answers (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references us.people(id) on delete cascade,
  question_key text not null,
  answer_text text,
  answer_json jsonb,
  confirmation_status text not null default 'confirmed',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(person_id, question_key)
);

alter table us.people enable row level security;
alter table us.job_application_profiles enable row level security;
alter table us.employment_history enable row level security;
alter table us.resume_variants enable row level security;
alter table us.application_answers enable row level security;

comment on schema us is 'Structured and temporal reality for the private Us life system.';
comment on table us.job_application_profiles is 'Canonical reusable applicant data for job-application workflows.';
comment on table us.application_answers is 'Confirmed reusable answers to recurring job-application questions; unknown answers should not be invented.';