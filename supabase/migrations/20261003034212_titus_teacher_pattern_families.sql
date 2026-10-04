create table if not exists titus.teacher_pattern_families (
  teacher_pattern_family_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  family_key text not null,
  family_name text not null,
  family_type text not null check (family_type in ('source_interpretation','formation_transmission','jurisdiction_governance','agency_liberty','cause_fruit_repair','memory_continuity','scale_social_order','other')),
  working_summary text,
  core_question text,
  family_status text not null default 'candidate' check (family_status in ('candidate','recurring','established','disputed','superseded','retired')),
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, family_key)
);

create table if not exists titus.teacher_pattern_family_members (
  teacher_pattern_family_member_id uuid primary key default gen_random_uuid(),
  teacher_pattern_family_id uuid not null references titus.teacher_pattern_families(teacher_pattern_family_id) on delete cascade,
  teacher_pattern_id uuid not null references titus.teacher_patterns(teacher_pattern_id) on delete cascade,
  member_role text not null default 'supporting' check (member_role in ('core','supporting','boundary','failure_expression','repair_expression','cross_scale_expression','historical_expression')),
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  membership_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_pattern_family_id, teacher_pattern_id)
);

comment on table titus.teacher_pattern_families is 'Teacher-native higher-order architecture reconstructed from recurring teacher patterns. Families are not Song concepts and do not replace the evidence-bearing patterns beneath them.';
comment on table titus.teacher_pattern_family_members is 'Many-to-many membership of reconstructed teacher patterns in higher-order teacher pattern families. A pattern may belong to multiple families because the same operation can participate in several architectures.';

create or replace view titus.v_teacher_pattern_family_map_v1 as
select
  f.teacher_pattern_family_id,
  f.teacher_id,
  f.family_key,
  f.family_name,
  f.family_type,
  f.working_summary as family_summary,
  f.core_question,
  f.family_status,
  f.confidence as family_confidence,
  m.member_role,
  m.confidence as membership_confidence,
  m.membership_note,
  p.teacher_pattern_id,
  p.pattern_key,
  p.pattern_name,
  p.pattern_type,
  p.pattern_status,
  p.confidence as pattern_confidence,
  p.working_summary as pattern_summary
from titus.teacher_pattern_families f
join titus.teacher_pattern_family_members m on m.teacher_pattern_family_id=f.teacher_pattern_family_id
join titus.teacher_patterns p on p.teacher_pattern_id=m.teacher_pattern_id;