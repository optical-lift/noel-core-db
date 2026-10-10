create table if not exists us.job_opportunities (
 id uuid primary key default gen_random_uuid(),
 person_id uuid not null references us.people(id) on delete cascade,
 company text not null,
 role_title text not null,
 requisition_id text,
 track text not null check (track in ('freedom','startup','other')),
 posting_url text,
 salary_min_usd integer,
 salary_max_usd integer,
 location_type text,
 listing_status text not null default 'candidate' check (listing_status in ('candidate','open','expired','closed','uncertain')),
 application_status text not null default 'not_submitted' check (application_status in ('not_submitted','in_progress','submitted','withdrawn','rejected','interview','offer')),
 status_reason text,
 status_evidence text,
 last_checked_at timestamptz,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint job_opportunity_requisition_unique unique (person_id,company,requisition_id)
);
alter table us.job_opportunities enable row level security;
revoke all on us.job_opportunities from anon,authenticated;
comment on table us.job_opportunities is 'Private Us job-search pipeline: listing availability is distinct from application submission status.';