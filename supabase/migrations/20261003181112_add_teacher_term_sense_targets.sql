create table if not exists titus.teacher_term_sense_targets (
  teacher_term_sense_target_id uuid primary key default gen_random_uuid(),
  teacher_term_sense_id uuid not null references titus.teacher_term_senses(teacher_term_sense_id) on delete cascade,
  target_kind text not null check (target_kind in ('canon_claim','truth_ref')),
  canon_claim_id uuid references titus.canon_claims(canon_claim_id) on delete cascade,
  truth_ref_id uuid references titus.truth_refs(truth_ref_id) on delete cascade,
  relation_type text not null check (relation_type in ('direct','partial_alignment','teacher_expression_of','requires_guardrail','bounded_by','supports','contrast','conflict','not_equivalent','coordinate_not_function','other')),
  student_use_status text not null default 'allowed' check (student_use_status in ('preferred','allowed','restricted','avoid','replace')),
  guardrail text,
  rationale text,
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teacher_term_sense_targets_exactly_one_target check (
    (target_kind='canon_claim' and canon_claim_id is not null and truth_ref_id is null)
    or
    (target_kind='truth_ref' and truth_ref_id is not null and canon_claim_id is null)
  )
);

create unique index if not exists teacher_term_sense_targets_claim_uq
  on titus.teacher_term_sense_targets(teacher_term_sense_id, canon_claim_id, relation_type)
  where canon_claim_id is not null;

create unique index if not exists teacher_term_sense_targets_truth_uq
  on titus.teacher_term_sense_targets(teacher_term_sense_id, truth_ref_id, relation_type)
  where truth_ref_id is not null;

create index if not exists teacher_term_sense_targets_sense_idx
  on titus.teacher_term_sense_targets(teacher_term_sense_id);
create index if not exists teacher_term_sense_targets_claim_idx
  on titus.teacher_term_sense_targets(canon_claim_id) where canon_claim_id is not null;
create index if not exists teacher_term_sense_targets_truth_idx
  on titus.teacher_term_sense_targets(truth_ref_id) where truth_ref_id is not null;

alter table titus.teacher_term_sense_targets enable row level security;
revoke all on titus.teacher_term_sense_targets from anon, authenticated;

create or replace view titus.v_teacher_term_sense_targets_live
with (security_invoker=true)
as
select
  t.teacher_term_id,
  t.term,
  t.normalized_term,
  t.preferred_student_term,
  t.term_status,
  s.teacher_term_sense_id,
  s.sense_key,
  s.sense_label,
  s.working_definition,
  s.sense_status,
  x.teacher_term_sense_target_id,
  x.target_kind,
  x.relation_type,
  x.student_use_status,
  x.guardrail,
  x.rationale,
  x.confidence,
  x.review_status,
  c.canon_claim_id,
  c.claim_key,
  c.claim_text,
  tr.truth_ref_id,
  tr.ref_kind,
  tr.function_key,
  tr.song_object_id,
  tr.label_snapshot as truth_label
from titus.teacher_terms t
join titus.teacher_term_senses s on s.teacher_term_id=t.teacher_term_id
join titus.teacher_term_sense_targets x on x.teacher_term_sense_id=s.teacher_term_sense_id
left join titus.canon_claims c on c.canon_claim_id=x.canon_claim_id
left join titus.truth_refs tr on tr.truth_ref_id=x.truth_ref_id;

revoke all on titus.v_teacher_term_sense_targets_live from anon, authenticated;