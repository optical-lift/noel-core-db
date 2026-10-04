create table if not exists titus.teacher_source_adjudication_targets (
  adjudication_target_id uuid primary key default gen_random_uuid(),
  adjudication_id uuid not null references titus.teacher_source_adjudications(adjudication_id) on delete cascade,
  target_kind text not null check (target_kind in ('canon_claim','truth_ref')),
  canon_claim_id uuid null references titus.canon_claims(canon_claim_id),
  truth_ref_id uuid null references titus.truth_refs(truth_ref_id),
  relation_type text not null check (relation_type in ('supports','partial_alignment','illustrates','requires_guardrail','conflicts','scopes_to','contrast','other')),
  confidence text null check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  relation_note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teacher_source_adjudication_targets_exactly_one_target check (
    (target_kind='canon_claim' and canon_claim_id is not null and truth_ref_id is null)
    or (target_kind='truth_ref' and truth_ref_id is not null and canon_claim_id is null)
  )
);
create unique index if not exists uq_teacher_source_adjudication_targets_claim
  on titus.teacher_source_adjudication_targets(adjudication_id, canon_claim_id, relation_type)
  where target_kind='canon_claim';
create unique index if not exists uq_teacher_source_adjudication_targets_truth
  on titus.teacher_source_adjudication_targets(adjudication_id, truth_ref_id, relation_type)
  where target_kind='truth_ref';
create index if not exists ix_teacher_source_adjudication_targets_claim on titus.teacher_source_adjudication_targets(canon_claim_id) where canon_claim_id is not null;
create index if not exists ix_teacher_source_adjudication_targets_truth on titus.teacher_source_adjudication_targets(truth_ref_id) where truth_ref_id is not null;
alter table titus.teacher_source_adjudication_targets enable row level security;
revoke all on table titus.teacher_source_adjudication_targets from anon, authenticated;