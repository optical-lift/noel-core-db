-- Titus Formation Kernel v1
-- First proving slice: Session 11 / “He who defines controls.”
--
-- Governing boundaries:
--   * reuse existing teacher-source / teacher-pattern / canon / Song truth objects
--   * add only missing person-specific formation nouns
--   * generated documents remain projections, not canonical storage
--   * new formation tables are private by default
--   * this migration does not mass-remediate inherited Titus RLS/security

create or replace function titus.set_formation_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function titus.set_formation_updated_at() from public, anon, authenticated, service_role;

create table if not exists titus.formation_units (
  formation_unit_id uuid primary key default gen_random_uuid(),
  program_id uuid not null references titus.programs(program_id),
  teacher_id uuid not null references titus.teachers(teacher_id),
  lesson_slug text not null references titus.lesson_packets(lesson_slug),
  unit_key text not null,
  version integer not null default 1 check (version > 0),
  title text not null,
  governing_question text not null,
  learner_goal text not null,
  formation_state text not null check (formation_state = any (array[
    'candidate'::text,
    'researching'::text,
    'adjudication_ready'::text,
    'drafted'::text,
    'reviewed'::text,
    'learner_ready'::text,
    'encountered'::text,
    'teachback_pending'::text,
    'teachback_received'::text,
    'teachback_reviewed'::text,
    'transfer_pending'::text,
    'transfer_reviewed'::text,
    'integrated'::text,
    'superseded'::text,
    'retired'::text
  ])),
  review_state text not null default 'current' check (review_state = any (array[
    'current'::text,
    'potentially_stale'::text,
    'needs_review'::text,
    'blocked'::text
  ])),
  confidence text check (confidence is null or confidence = any (array['low'::text, 'medium'::text, 'high'::text])),
  supersedes_formation_unit_id uuid references titus.formation_units(formation_unit_id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_slug, unit_key, version)
);

create trigger formation_units_set_updated_at
before update on titus.formation_units
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_units is
  'Bounded learner-facing worldview-to-canon reconstruction units. Canon truth and historical worldview remain owned by their upstream Titus/Noel objects.';

create table if not exists titus.formation_unit_inputs (
  formation_unit_input_id uuid primary key default gen_random_uuid(),
  formation_unit_id uuid not null references titus.formation_units(formation_unit_id) on delete cascade,
  input_kind text not null check (input_kind = any (array[
    'source_unit'::text,
    'source_adjudication'::text,
    'source_adjudication_target'::text,
    'teacher_pattern'::text,
    'teacher_pattern_claim_link'::text,
    'teacher_term_sense'::text,
    'teacher_term_sense_target'::text,
    'canon_claim'::text,
    'canon_structure'::text,
    'truth_ref'::text
  ])),
  source_unit_id uuid references titus.teacher_source_units(source_unit_id),
  source_adjudication_id uuid references titus.teacher_source_adjudications(adjudication_id),
  source_adjudication_target_id uuid references titus.teacher_source_adjudication_targets(adjudication_target_id),
  teacher_pattern_id uuid references titus.teacher_patterns(teacher_pattern_id),
  teacher_pattern_claim_link_id uuid references titus.teacher_pattern_claim_links(teacher_pattern_claim_link_id),
  teacher_term_sense_id uuid references titus.teacher_term_senses(teacher_term_sense_id),
  teacher_term_sense_target_id uuid references titus.teacher_term_sense_targets(teacher_term_sense_target_id),
  canon_claim_id uuid references titus.canon_claims(canon_claim_id),
  canon_structure_id uuid references titus.canon_structures(canon_structure_id),
  truth_ref_id uuid references titus.truth_refs(truth_ref_id),
  input_role text not null check (input_role = any (array[
    'historical_evidence'::text,
    'source_adjudication'::text,
    'functional_bridge'::text,
    'canon_control'::text,
    'canon_guardrail'::text,
    'song_scope'::text,
    'contrast'::text,
    'supporting'::text,
    'other'::text
  ])),
  materiality text not null default 'supporting' check (materiality = any (array['core'::text, 'supporting'::text, 'context'::text])),
  review_status text not null default 'candidate' check (review_status = any (array[
    'candidate'::text,
    'reviewed'::text,
    'approved'::text,
    'rejected'::text,
    'superseded'::text
  ])),
  relation_note text,
  reviewed_at timestamptz,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint formation_unit_inputs_exactly_one_target check (
    num_nonnulls(
      source_unit_id,
      source_adjudication_id,
      source_adjudication_target_id,
      teacher_pattern_id,
      teacher_pattern_claim_link_id,
      teacher_term_sense_id,
      teacher_term_sense_target_id,
      canon_claim_id,
      canon_structure_id,
      truth_ref_id
    ) = 1
    and (
      (input_kind = 'source_unit' and source_unit_id is not null) or
      (input_kind = 'source_adjudication' and source_adjudication_id is not null) or
      (input_kind = 'source_adjudication_target' and source_adjudication_target_id is not null) or
      (input_kind = 'teacher_pattern' and teacher_pattern_id is not null) or
      (input_kind = 'teacher_pattern_claim_link' and teacher_pattern_claim_link_id is not null) or
      (input_kind = 'teacher_term_sense' and teacher_term_sense_id is not null) or
      (input_kind = 'teacher_term_sense_target' and teacher_term_sense_target_id is not null) or
      (input_kind = 'canon_claim' and canon_claim_id is not null) or
      (input_kind = 'canon_structure' and canon_structure_id is not null) or
      (input_kind = 'truth_ref' and truth_ref_id is not null)
    )
  )
);

create index if not exists formation_unit_inputs_unit_sort_idx
  on titus.formation_unit_inputs (formation_unit_id, sort_order, input_kind);

create unique index if not exists formation_unit_inputs_source_unit_uq
  on titus.formation_unit_inputs (formation_unit_id, source_unit_id)
  where source_unit_id is not null;
create unique index if not exists formation_unit_inputs_source_adjudication_uq
  on titus.formation_unit_inputs (formation_unit_id, source_adjudication_id)
  where source_adjudication_id is not null;
create unique index if not exists formation_unit_inputs_source_adjudication_target_uq
  on titus.formation_unit_inputs (formation_unit_id, source_adjudication_target_id)
  where source_adjudication_target_id is not null;
create unique index if not exists formation_unit_inputs_teacher_pattern_uq
  on titus.formation_unit_inputs (formation_unit_id, teacher_pattern_id)
  where teacher_pattern_id is not null;
create unique index if not exists formation_unit_inputs_teacher_pattern_claim_link_uq
  on titus.formation_unit_inputs (formation_unit_id, teacher_pattern_claim_link_id)
  where teacher_pattern_claim_link_id is not null;
create unique index if not exists formation_unit_inputs_teacher_term_sense_uq
  on titus.formation_unit_inputs (formation_unit_id, teacher_term_sense_id)
  where teacher_term_sense_id is not null;
create unique index if not exists formation_unit_inputs_teacher_term_sense_target_uq
  on titus.formation_unit_inputs (formation_unit_id, teacher_term_sense_target_id)
  where teacher_term_sense_target_id is not null;
create unique index if not exists formation_unit_inputs_canon_claim_uq
  on titus.formation_unit_inputs (formation_unit_id, canon_claim_id)
  where canon_claim_id is not null;
create unique index if not exists formation_unit_inputs_canon_structure_uq
  on titus.formation_unit_inputs (formation_unit_id, canon_structure_id)
  where canon_structure_id is not null;
create unique index if not exists formation_unit_inputs_truth_ref_uq
  on titus.formation_unit_inputs (formation_unit_id, truth_ref_id)
  where truth_ref_id is not null;

create trigger formation_unit_inputs_set_updated_at
before update on titus.formation_unit_inputs
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_unit_inputs is
  'Typed dependencies from a Formation Unit to existing source, adjudication, teacher-pattern, canon, and Song/function objects. Inputs reference upstream truth rather than copying it.';

create table if not exists titus.formation_unit_sections (
  formation_unit_section_id uuid primary key default gen_random_uuid(),
  formation_unit_id uuid not null references titus.formation_units(formation_unit_id) on delete cascade,
  section_key text not null,
  section_kind text not null check (section_kind = any (array[
    'recognition'::text,
    'functional_decomposition'::text,
    'canon_reconstruction'::text,
    'song_placement'::text,
    'adjudication'::text,
    'expansion'::text,
    'rebuild'::text,
    'summary'::text,
    'other'::text
  ])),
  heading text not null,
  body text not null,
  section_status text not null default 'draft' check (section_status = any (array[
    'candidate'::text,
    'draft'::text,
    'reviewed'::text,
    'approved'::text,
    'superseded'::text,
    'retired'::text
  ])),
  sort_order integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (formation_unit_id, section_key)
);

create trigger formation_unit_sections_set_updated_at
before update on titus.formation_unit_sections
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_unit_sections is
  'Learner-facing connective teaching within a Formation Unit. Sections explain governed inputs but do not become the source of canon truth.';

create table if not exists titus.formation_questions (
  formation_question_id uuid primary key default gen_random_uuid(),
  formation_unit_id uuid not null references titus.formation_units(formation_unit_id) on delete cascade,
  origin_input_id uuid references titus.formation_unit_inputs(formation_unit_input_id) on delete set null,
  question_kind text not null check (question_kind = any (array[
    'research'::text,
    'integration'::text,
    'challenge'::text,
    'reflection'::text,
    'other'::text
  ])),
  question_text text not null,
  status text not null default 'open' check (status = any (array[
    'open'::text,
    'researching'::text,
    'resolved'::text,
    'deferred'::text,
    'retired'::text
  ])),
  resolution text,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists formation_questions_unit_status_idx
  on titus.formation_questions (formation_unit_id, status, sort_order);

create trigger formation_questions_set_updated_at
before update on titus.formation_questions
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_questions is
  'Durable research, integration, challenge, and reflection questions attached to Formation Units. Open questions are first-class formation state.';

create table if not exists titus.formation_responses (
  formation_response_id uuid primary key default gen_random_uuid(),
  formation_unit_id uuid not null references titus.formation_units(formation_unit_id) on delete cascade,
  teacher_id uuid not null references titus.teachers(teacher_id),
  formation_question_id uuid references titus.formation_questions(formation_question_id) on delete set null,
  response_kind text not null check (response_kind = any (array[
    'teachback'::text,
    'integration_response'::text,
    'disagreement'::text,
    'new_example'::text,
    'research_note'::text,
    'other'::text
  ])),
  source_kind text not null default 'typed_text' check (source_kind = any (array[
    'typed_text'::text,
    'audio_transcript'::text,
    'uploaded_transcript'::text,
    'other'::text
  ])),
  source_ref text,
  raw_text text not null,
  response_status text not null default 'submitted' check (response_status = any (array[
    'submitted'::text,
    'reviewed'::text,
    'superseded'::text,
    'retired'::text
  ])),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists formation_responses_unit_kind_idx
  on titus.formation_responses (formation_unit_id, response_kind, created_at);

create trigger formation_responses_set_updated_at
before update on titus.formation_responses
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_responses is
  'Raw learner-authored responses/teach-back artifacts. Analyst or model interpretation must not overwrite the raw response.';

create table if not exists titus.formation_transfer_cases (
  formation_transfer_case_id uuid primary key default gen_random_uuid(),
  formation_unit_id uuid not null references titus.formation_units(formation_unit_id) on delete cascade,
  case_key text not null,
  version integer not null default 1 check (version > 0),
  title text not null,
  prompt_text text not null,
  expected_distinctions text[] not null default '{}',
  case_status text not null default 'draft' check (case_status = any (array[
    'draft'::text,
    'reviewed'::text,
    'learner_ready'::text,
    'retired'::text
  ])),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (formation_unit_id, case_key, version)
);

create trigger formation_transfer_cases_set_updated_at
before update on titus.formation_transfer_cases
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_transfer_cases is
  'Novel cases used to test whether a learner can transfer the Formation Unit architecture beyond rehearsed examples.';

create table if not exists titus.formation_transfer_attempts (
  formation_transfer_attempt_id uuid primary key default gen_random_uuid(),
  formation_transfer_case_id uuid not null references titus.formation_transfer_cases(formation_transfer_case_id) on delete cascade,
  teacher_id uuid not null references titus.teachers(teacher_id),
  response_text text not null,
  assessment_status text not null default 'pending' check (assessment_status = any (array[
    'pending'::text,
    'reviewed'::text,
    'pass'::text,
    'needs_revision'::text,
    'insufficient_warrant'::text,
    'superseded'::text
  ])),
  assessment_note text,
  submitted_at timestamptz not null default now(),
  assessed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists formation_transfer_attempts_case_idx
  on titus.formation_transfer_attempts (formation_transfer_case_id, submitted_at);

create trigger formation_transfer_attempts_set_updated_at
before update on titus.formation_transfer_attempts
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_transfer_attempts is
  'Learner attempts and reviewed assessment for novel transfer cases. Restatement ability and transfer ability remain distinct.';

create table if not exists titus.formation_articulations (
  formation_articulation_id uuid primary key default gen_random_uuid(),
  formation_unit_id uuid not null references titus.formation_units(formation_unit_id) on delete cascade,
  teacher_id uuid not null references titus.teachers(teacher_id),
  articulation_version integer not null check (articulation_version > 0),
  articulation_text text not null,
  articulation_status text not null default 'candidate' check (articulation_status = any (array[
    'candidate'::text,
    'reviewed'::text,
    'current'::text,
    'superseded'::text,
    'retired'::text
  ])),
  based_on_response_id uuid references titus.formation_responses(formation_response_id) on delete set null,
  based_on_transfer_attempt_id uuid references titus.formation_transfer_attempts(formation_transfer_attempt_id) on delete set null,
  supersedes_articulation_id uuid references titus.formation_articulations(formation_articulation_id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (formation_unit_id, teacher_id, articulation_version)
);

create unique index if not exists formation_articulations_one_current_uq
  on titus.formation_articulations (formation_unit_id, teacher_id)
  where articulation_status = 'current';

create trigger formation_articulations_set_updated_at
before update on titus.formation_articulations
for each row execute function titus.set_formation_updated_at();

comment on table titus.formation_articulations is
  'Versioned matured learner articulations after formation. They never overwrite historical worldview claims or raw learner responses.';

-- New formation custody is private by default.
alter table titus.formation_units enable row level security;
alter table titus.formation_unit_inputs enable row level security;
alter table titus.formation_unit_sections enable row level security;
alter table titus.formation_questions enable row level security;
alter table titus.formation_responses enable row level security;
alter table titus.formation_transfer_cases enable row level security;
alter table titus.formation_transfer_attempts enable row level security;
alter table titus.formation_articulations enable row level security;

revoke all on table titus.formation_units from public, anon, authenticated;
revoke all on table titus.formation_unit_inputs from public, anon, authenticated;
revoke all on table titus.formation_unit_sections from public, anon, authenticated;
revoke all on table titus.formation_questions from public, anon, authenticated;
revoke all on table titus.formation_responses from public, anon, authenticated;
revoke all on table titus.formation_transfer_cases from public, anon, authenticated;
revoke all on table titus.formation_transfer_attempts from public, anon, authenticated;
revoke all on table titus.formation_articulations from public, anon, authenticated;

grant select, insert, update, delete on table titus.formation_units to service_role;
grant select, insert, update, delete on table titus.formation_unit_inputs to service_role;
grant select, insert, update, delete on table titus.formation_unit_sections to service_role;
grant select, insert, update, delete on table titus.formation_questions to service_role;
grant select, insert, update, delete on table titus.formation_responses to service_role;
grant select, insert, update, delete on table titus.formation_transfer_cases to service_role;
grant select, insert, update, delete on table titus.formation_transfer_attempts to service_role;
grant select, insert, update, delete on table titus.formation_articulations to service_role;

-- Precise canon/Song targets for the two historical definition-control source units.
-- Existing approved source adjudications remain the adjudication authority; this
-- backfill makes their actual dependencies inspectable.
insert into titus.teacher_source_adjudication_targets (
  adjudication_target_id,
  adjudication_id,
  target_kind,
  canon_claim_id,
  relation_type,
  confidence,
  review_status,
  relation_note
)
select
  gen_random_uuid(),
  a.adjudication_id,
  'canon_claim',
  c.canon_claim_id,
  x.relation_type,
  'high',
  'reviewed',
  x.relation_note
from titus.teacher_source_units u
join titus.teacher_source_adjudications a on a.source_unit_id = u.source_unit_id
cross join (values
  ('speech_coordinates_bodies_through_intelligibility', 'partial_alignment', 'The source claim notices real coordination power in accepted language, but coordination is not sovereign control.'),
  ('formation_is_mediated_not_deterministic', 'requires_guardrail', 'The control thesis must be expanded into the mediated chain of hearing, testing, reception/resistance, memory, practice, coordination, and fruit.'),
  ('testing_carriers_is_not_rejecting_source', 'requires_guardrail', 'Hearers remain responsible to test human carriers; a definition does not mechanically determine reception.'),
  ('semantic_change_not_automatically_custody_transfer', 'requires_guardrail', 'A changed definition can participate in reframing but does not by itself prove a handoff of interpretive custody.')
) as x(claim_key, relation_type, relation_note)
join titus.canon_claims c on c.claim_key = x.claim_key
where u.unit_key in ('definition_control_claim_2018', 'definition_control_claim_2023')
  and a.approval_status = 'approved'
  and not exists (
    select 1
    from titus.teacher_source_adjudication_targets existing
    where existing.adjudication_id = a.adjudication_id
      and existing.target_kind = 'canon_claim'
      and existing.canon_claim_id = c.canon_claim_id
      and existing.relation_type = x.relation_type
  );

insert into titus.teacher_source_adjudication_targets (
  adjudication_target_id,
  adjudication_id,
  target_kind,
  truth_ref_id,
  relation_type,
  confidence,
  review_status,
  relation_note
)
select
  gen_random_uuid(),
  a.adjudication_id,
  'truth_ref',
  tr.truth_ref_id,
  x.relation_type,
  'high',
  'reviewed',
  x.relation_note
from titus.teacher_source_units u
join titus.teacher_source_adjudications a on a.source_unit_id = u.source_unit_id
cross join (values
  ('function', 'source_recognition', null::bigint, 'scopes_to', 'Definitions and carriers remain downstream of Source; accepted language does not become Source by social success.'),
  ('song_object', null::text, 8::bigint, 'partial_alignment', 'Voice / Speech / Call supplies a real language-operation lane but does not make all speech sovereign.'),
  ('song_object', null::text, 17::bigint, 'contrast', 'Name/classification is real but naming is not equivalent to owning or controlling the referent/person.'),
  ('song_object', null::text, 47::bigint, 'requires_guardrail', 'Custody Transfer is relevant only where governing interpretive custody actually changes; semantic change alone is insufficient.')
) as x(ref_kind, function_key, song_object_id, relation_type, relation_note)
join titus.truth_refs tr
  on tr.ref_kind = x.ref_kind
 and tr.function_key is not distinct from x.function_key
 and tr.song_object_id is not distinct from x.song_object_id
where u.unit_key in ('definition_control_claim_2018', 'definition_control_claim_2023')
  and a.approval_status = 'approved'
  and not exists (
    select 1
    from titus.teacher_source_adjudication_targets existing
    where existing.adjudication_id = a.adjudication_id
      and existing.target_kind = 'truth_ref'
      and existing.truth_ref_id = tr.truth_ref_id
      and existing.relation_type = x.relation_type
  );

-- Bring the 2018 historical formulation into Session 11 beside the already-linked 2023 formulation.
insert into titus.lesson_teacher_source_links (
  lesson_teacher_source_link_id,
  lesson_slug,
  source_unit_id,
  adjudication_id,
  lesson_role,
  adaptation_note,
  status,
  sort_order
)
select
  gen_random_uuid(),
  'm01-s11-language-redefinition-cultural-formation',
  u.source_unit_id,
  a.adjudication_id,
  'contrast',
  'Show the early “power to define is the power to control” formulation as historical evidence, then distinguish framing/coordination from sovereign control.',
  'approved',
  24
from titus.teacher_source_units u
join titus.teacher_source_adjudications a on a.source_unit_id = u.source_unit_id
where u.unit_key = 'definition_control_claim_2018'
  and a.approval_status = 'approved'
  and not exists (
    select 1
    from titus.lesson_teacher_source_links existing
    where existing.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
      and existing.source_unit_id = u.source_unit_id
      and existing.lesson_role = 'contrast'
  );

-- First Formation Unit. Durable IDs are resolved by stable keys.
insert into titus.formation_units (
  program_id,
  teacher_id,
  lesson_slug,
  unit_key,
  version,
  title,
  governing_question,
  learner_goal,
  formation_state,
  review_state,
  confidence,
  notes
)
select
  p.program_id,
  t.teacher_id,
  'm01-s11-language-redefinition-cultural-formation',
  'definition_control_reconstruction',
  1,
  'Definitions Can Steer Without Sovereign Control',
  'What does the canon actually establish about the power of definitions to shape persons, groups, and culture?',
  'Distinguish classification, framing, intelligibility, coordination, reception, institutional reinforcement, jurisdiction, custody, and sovereign control; preserve the real force of definitions without attributing to them authority the canon does not give them.',
  'drafted',
  'current',
  'high',
  'First end-to-end Worldview-to-Canon Formation Unit. Historical Marlene language is preserved upstream; this unit teaches the larger canon architecture rather than merely replacing a slogan.'
from titus.programs p
join titus.program_teachers pt on pt.program_id = p.program_id and pt.status = 'active'
join titus.teachers t on t.teacher_id = pt.teacher_id and t.teacher_key = 'marlene_mcmillan'
where p.program_slug = 'mcmillan-university'
  and not exists (
    select 1
    from titus.formation_units existing
    where existing.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
      and existing.unit_key = 'definition_control_reconstruction'
      and existing.version = 1
  );

-- Historical source inputs.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, source_unit_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'source_unit',
  u.source_unit_id,
  'historical_evidence',
  'core',
  'reviewed',
  case u.unit_key
    when 'definition_control_claim_2018' then 'Early strong formulation: power to define as power to control.'
    when 'definition_control_claim_2023' then 'Recurring later formulation: he who defines controls people/outcome/result/future.'
  end,
  now(),
  case u.unit_key when 'definition_control_claim_2018' then 10 else 20 end
from titus.formation_units fu
join titus.teacher_source_units u on u.unit_key in ('definition_control_claim_2018', 'definition_control_claim_2023')
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Source-specific adjudication inputs.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, source_adjudication_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'source_adjudication',
  a.adjudication_id,
  'source_adjudication',
  'core',
  'reviewed',
  'Approved source-specific correction preserving framing/coordination insight while rejecting sovereign-control overclaim.',
  now(),
  case u.unit_key when 'definition_control_claim_2018' then 30 else 40 end
from titus.formation_units fu
join titus.teacher_source_units u on u.unit_key in ('definition_control_claim_2018', 'definition_control_claim_2023')
join titus.teacher_source_adjudications a on a.source_unit_id = u.source_unit_id and a.approval_status = 'approved'
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Exact source-adjudication target dependencies.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, source_adjudication_target_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'source_adjudication_target',
  at.adjudication_target_id,
  case when at.target_kind = 'truth_ref' then 'song_scope' else 'canon_guardrail' end,
  case when at.relation_type in ('requires_guardrail', 'conflicts') then 'core' else 'supporting' end,
  'reviewed',
  at.relation_note,
  now(),
  50 + row_number() over (order by u.unit_key, at.target_kind, at.relation_type, at.adjudication_target_id)
from titus.formation_units fu
join titus.teacher_source_units u on u.unit_key in ('definition_control_claim_2018', 'definition_control_claim_2023')
join titus.teacher_source_adjudications a on a.source_unit_id = u.source_unit_id and a.approval_status = 'approved'
join titus.teacher_source_adjudication_targets at on at.adjudication_id = a.adjudication_id and at.review_status in ('reviewed','approved')
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Teacher-native functional pattern inputs.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, teacher_pattern_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'teacher_pattern',
  tp.teacher_pattern_id,
  'functional_bridge',
  case when tp.pattern_key in ('premise_language_conclusion_chain','semantic_redefinition_culture_transition') then 'core' else 'supporting' end,
  'reviewed',
  case tp.pattern_key
    when 'premise_language_conclusion_chain' then 'Teacher-native architecture already separates language as a mediated input rather than an autonomous deterministic cause.'
    when 'semantic_redefinition_culture_transition' then 'Teacher-native cultural-redefinition pattern already contains the corrected reception/repetition/institutionalization/embodiment chain.'
    when 'source_governed_interpretive_frame' then 'Keeps definitions and premises under Source rather than making the definer the final source.'
    when 'relational_pressure_custody_shift' then 'Supplies the relational-pressure lane while preserving the need to prove actual custody transfer.'
    when 'label_function_noncollapse' then 'Supplies Marlene’s durable habit of testing operation rather than trusting a label.'
  end,
  now(),
  case tp.pattern_key
    when 'premise_language_conclusion_chain' then 100
    when 'semantic_redefinition_culture_transition' then 110
    when 'source_governed_interpretive_frame' then 120
    when 'relational_pressure_custody_shift' then 130
    when 'label_function_noncollapse' then 140
  end
from titus.formation_units fu
join titus.teacher_patterns tp on tp.pattern_key in (
  'premise_language_conclusion_chain',
  'semantic_redefinition_culture_transition',
  'source_governed_interpretive_frame',
  'relational_pressure_custody_shift',
  'label_function_noncollapse'
)
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Exact reviewed teacher-pattern ↔ canon relation dependencies for the two central patterns.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, teacher_pattern_claim_link_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'teacher_pattern_claim_link',
  pcl.teacher_pattern_claim_link_id,
  'functional_bridge',
  'core',
  'reviewed',
  pcl.relation_note,
  now(),
  150 + row_number() over (order by tp.pattern_key, c.claim_key)
from titus.formation_units fu
join titus.teacher_patterns tp on tp.pattern_key in ('premise_language_conclusion_chain','semantic_redefinition_culture_transition')
join titus.teacher_pattern_claim_links pcl on pcl.teacher_pattern_id = tp.teacher_pattern_id and pcl.review_status in ('reviewed','approved')
join titus.canon_claims c on c.canon_claim_id = pcl.canon_claim_id
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
  and c.claim_key in (
    'formation_is_mediated_not_deterministic',
    'speech_is_formative_and_diagnostic',
    'speech_coordinates_bodies_through_intelligibility',
    'semantic_change_not_automatically_custody_transfer'
  )
on conflict do nothing;

-- Independent canon controls.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, canon_claim_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'canon_claim',
  c.canon_claim_id,
  case
    when c.claim_key in ('formation_is_mediated_not_deterministic','speech_coordinates_bodies_through_intelligibility') then 'canon_control'
    else 'canon_guardrail'
  end,
  case
    when c.claim_key in ('formation_is_mediated_not_deterministic','speech_coordinates_bodies_through_intelligibility') then 'core'
    else 'supporting'
  end,
  'reviewed',
  case c.claim_key
    when 'formation_is_mediated_not_deterministic' then 'Primary causal boundary: lexical change participates in a mediated chain and does not mechanically determine persons/culture.'
    when 'speech_coordinates_bodies_through_intelligibility' then 'Positive mechanism preserved from Marlene: shared intelligibility can coordinate collective action.'
    when 'testing_carriers_is_not_rejecting_source' then 'Hearers remain active examiners; reception is not mechanical.'
    when 'semantic_change_not_automatically_custody_transfer' then 'A changed definition is not yet proof of governing custody transfer.'
    when 'human_naming_is_delegated_classification' then 'Naming/classification can be real without creating, owning, or sovereignly controlling the referent.'
  end,
  now(),
  case c.claim_key
    when 'formation_is_mediated_not_deterministic' then 200
    when 'speech_coordinates_bodies_through_intelligibility' then 210
    when 'testing_carriers_is_not_rejecting_source' then 220
    when 'semantic_change_not_automatically_custody_transfer' then 230
    when 'human_naming_is_delegated_classification' then 240
  end
from titus.formation_units fu
join titus.canon_claims c on c.claim_key in (
  'formation_is_mediated_not_deterministic',
  'speech_coordinates_bodies_through_intelligibility',
  'testing_carriers_is_not_rejecting_source',
  'semantic_change_not_automatically_custody_transfer',
  'human_naming_is_delegated_classification'
)
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Primary canon structures.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, canon_structure_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'canon_structure',
  cs.canon_structure_id,
  case cs.structure_key when 'speech_under_source_architecture' then 'canon_control' else 'contrast' end,
  case cs.structure_key when 'speech_under_source_architecture' then 'core' else 'supporting' end,
  'reviewed',
  case cs.structure_key
    when 'speech_under_source_architecture' then 'Primary end-to-end architecture from Source/authorization through carrier, intelligibility, testing, reception, practice/coordination, and fruit.'
    when 'babel_pentecost_contrast' then 'Canonical control showing shared language/coordination does not equal righteous unity or sovereign control.'
  end,
  now(),
  case cs.structure_key when 'speech_under_source_architecture' then 250 else 260 end
from titus.formation_units fu
join titus.canon_structures cs on cs.structure_key in ('speech_under_source_architecture','babel_pentecost_contrast')
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Explicit Song/function handles used by this unit.
insert into titus.formation_unit_inputs (
  formation_unit_id, input_kind, truth_ref_id, input_role, materiality, review_status, relation_note, reviewed_at, sort_order
)
select
  fu.formation_unit_id,
  'truth_ref',
  tr.truth_ref_id,
  'song_scope',
  case
    when tr.function_key = 'source_recognition' or tr.song_object_id = 8 then 'core'
    else 'supporting'
  end,
  'reviewed',
  case
    when tr.function_key = 'source_recognition' then 'Primary Source guardrail: the definer/carrier does not become Source.'
    when tr.song_object_id = 8 then 'Voice / Speech / Call: real formative and coordinating speech operations, bounded by Source and operation type.'
    when tr.song_object_id = 17 then 'Name: classification/identification without sovereign creation or ownership.'
    when tr.song_object_id = 47 then 'Custody Transfer / Reclassification: conditional lane only when governing custody actually moves.'
  end,
  now(),
  case
    when tr.function_key = 'source_recognition' then 270
    when tr.song_object_id = 8 then 280
    when tr.song_object_id = 17 then 290
    when tr.song_object_id = 47 then 300
  end
from titus.formation_units fu
join titus.truth_refs tr on
     (tr.ref_kind = 'function' and tr.function_key = 'source_recognition')
  or (tr.ref_kind = 'song_object' and tr.song_object_id in (8,17,47))
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict do nothing;

-- Initial learner-facing connective sections. These remain draft until reviewed as formation material.
insert into titus.formation_unit_sections (
  formation_unit_id, section_key, section_kind, heading, body, section_status, sort_order
)
select fu.formation_unit_id, x.section_key, x.section_kind, x.heading, x.body, 'draft', x.sort_order
from titus.formation_units fu
cross join (values
  ('what_you_already_see', 'recognition', 'What you already see',
   'Across 2018 and 2023 you repeatedly named a real pressure: accepted definitions can shape what a body notices, how it classifies a question, what conclusions seem available, and how people coordinate. That observation is worth keeping. The canon does not require us to weaken the importance of language; it requires us to separate the operations that your older word “control” was carrying together.', 10),
  ('under_the_word_control', 'functional_decomposition', 'What is underneath the word “control”?',
   'The older formulation compresses several different operations: classification, framing, intelligibility, attention steering, inference steering, group coordination, repetition, institutional reinforcement, jurisdictional enforcement, reception or resistance, and possible custody shift. These operations can travel together, but they are not interchangeable. None of them by itself establishes sovereign control of the hearer, the outcome, reality, or the future.', 20),
  ('canon_reconstruction', 'canon_reconstruction', 'What the canon actually makes visible',
   'The canon gives speech real force while preserving the hearer, Source, relation, jurisdiction, and operation. Shared intelligibility can coordinate a body. Hearers can test human carriers. Naming can classify without creating or owning the referent. Speech can be formative and also diagnostic of a prior heart/source condition. The full formation path is mediated: Source and claim → carrier and speech operation → intelligibility → hearing/recognition → testing → reception or resistance → memory/repetition → practice/coordination → fruit/public state.', 30),
  ('song_placement', 'song_placement', 'Where Song gives you better handles',
   'Source Recognition keeps the definer from becoming Source. Voice / Speech / Call identifies real speech operations without turning all speech into one power. Name preserves classification and identification while refusing the leap from naming to sovereign ownership. Custody Transfer / Reclassification becomes relevant only when governing interpretive authority or belonging actually changes hands; a semantic change by itself does not prove that transfer.', 40),
  ('adjudication', 'adjudication', 'What survives and what changes',
   'The observation survives: accepted definitions can create substantial framing and coordination influence. The old formulation overgeneralizes that influence into control. The stronger model asks which operation occurred, who supplied the definition, whether the carrier was authorized, whether the definition was intelligible, whether hearers tested/received/resisted it, what institutions reinforced it, whether any real jurisdiction or custody changed, and what fruit followed.', 50),
  ('canon_expansion', 'expansion', 'What the older model could not yet distinguish',
   'The canon expands the language model in both directions. Upstream, it asks Source, authorization, carrier, operation, and jurisdiction before it asks outcome. Downstream, it refuses to jump from exposure to embodiment: hearing, testing, reception, memory, practice, coordination, and fruit are separate thresholds. This means a changed definition may matter enormously without being magical, deterministic, or self-authenticating.', 60),
  ('rebuild', 'rebuild', 'Rebuild the idea in your own words',
   'Do not begin by replacing one slogan with another. Start by naming the real operations you were trying to protect. Which part is classification? Which part is framing? Which part is coordination? What requires institutional authority? What requires reception? What would count as actual custody transfer? Then state what definitions can genuinely do without giving them Source-level or sovereign power.', 70),
  ('working_summary', 'summary', 'Working mature formulation',
   'Definitions can steer. When accepted and reinforced, they can organize categories, direct attention, shape available inferences, and coordinate bodies toward action. Their effect is mediated through carriers, intelligibility, testing, reception or resistance, repetition, institutions, jurisdiction, practice, and fruit. A definition does not create reality, erase hearer agency, prove Source, or establish custody merely by being spoken or socially accepted.', 80)
) as x(section_key, section_kind, heading, body, sort_order)
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
on conflict (formation_unit_id, section_key) do nothing;

-- Questions intended to ferment integration rather than reward wording substitution.
insert into titus.formation_questions (
  formation_unit_id, question_kind, question_text, status, sort_order
)
select fu.formation_unit_id, x.question_kind, x.question_text, 'open', x.sort_order
from titus.formation_units fu
cross join (values
  ('integration', 'When you used the word “control,” which distinct operations were you actually seeing in real life?', 10),
  ('challenge', 'What evidence would be required to move from “the definition changed” to “governing interpretive custody changed”?', 20),
  ('integration', 'How does restoring the hearer’s capacity to test, resist, reinterpret, or fail to embody a definition change your older causal model?', 30),
  ('reflection', 'Which examples from your earlier language teaching are better described as framing, coordination, institutional enforcement, or custody rather than one undifferentiated “control”?', 40),
  ('challenge', 'What does the Babel/Pentecost contrast force you to separate between shared intelligibility, coordinated action, Source unity, and righteousness?', 50),
  ('research', 'Where, if anywhere, does the canon show a semantic or naming change that is accompanied by an actual transfer of governing custody? What additional evidence marks the handoff?', 60)
) as x(question_kind, question_text, sort_order)
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
  and not exists (
    select 1 from titus.formation_questions q
    where q.formation_unit_id = fu.formation_unit_id
      and q.question_text = x.question_text
  );

-- A deliberately novel transfer case. It remains draft until the formation unit is reviewed/learner-ready.
insert into titus.formation_transfer_cases (
  formation_unit_id,
  case_key,
  version,
  title,
  prompt_text,
  expected_distinctions,
  case_status
)
select
  fu.formation_unit_id,
  'institutional_definition_change',
  1,
  'A changed term before changed practice',
  'An institution replaces a familiar term with a new definition. For eighteen months its formal policy and enforcement remain unchanged. Then training language, incentives, credentialing requirements, and enforcement begin to shift. Analyze the sequence without assuming motive. Identify what the semantic change establishes by itself, what later coordination/enforcement changes establish, what evidence would be needed to claim a custody transfer, where hearer agency remains active, and what fruit can and cannot prove.',
  array[
    'semantic change is not automatically custody transfer',
    'classification/framing differs from jurisdictional enforcement',
    'shared intelligibility can coordinate without sovereign control',
    'hearers remain capable of testing/reception/resistance',
    'institutional reinforcement is a distinct causal lane',
    'fruit is evidence but does not uniquely prove hidden Source or motive'
  ],
  'draft'
from titus.formation_units fu
where fu.lesson_slug = 'm01-s11-language-redefinition-cultural-formation'
  and fu.unit_key = 'definition_control_reconstruction'
  and fu.version = 1
  and not exists (
    select 1 from titus.formation_transfer_cases tc
    where tc.formation_unit_id = fu.formation_unit_id
      and tc.case_key = 'institutional_definition_change'
      and tc.version = 1
  );

-- Input health view. Staleness follows the exact typed dependency, not the whole session.
create or replace view titus.v_formation_unit_input_health
with (security_invoker = true)
as
select
  fui.formation_unit_input_id,
  fui.formation_unit_id,
  fui.input_kind,
  fui.input_role,
  fui.materiality,
  fui.review_status,
  fui.relation_note,
  fui.reviewed_at,
  fui.sort_order,
  case fui.input_kind
    when 'source_unit' then su.updated_at
    when 'source_adjudication' then sa.updated_at
    when 'source_adjudication_target' then sat.updated_at
    when 'teacher_pattern' then tp.updated_at
    when 'teacher_pattern_claim_link' then tpcl.updated_at
    when 'teacher_term_sense' then tts.updated_at
    when 'teacher_term_sense_target' then ttst.updated_at
    when 'canon_claim' then cc.updated_at
    when 'canon_structure' then cs.updated_at
    when 'truth_ref' then tr.updated_at
  end as upstream_updated_at,
  case
    when fui.reviewed_at is null then true
    else coalesce(
      case fui.input_kind
        when 'source_unit' then su.updated_at
        when 'source_adjudication' then sa.updated_at
        when 'source_adjudication_target' then sat.updated_at
        when 'teacher_pattern' then tp.updated_at
        when 'teacher_pattern_claim_link' then tpcl.updated_at
        when 'teacher_term_sense' then tts.updated_at
        when 'teacher_term_sense_target' then ttst.updated_at
        when 'canon_claim' then cc.updated_at
        when 'canon_structure' then cs.updated_at
        when 'truth_ref' then tr.updated_at
      end > fui.reviewed_at,
      false
    )
  end as potentially_stale
from titus.formation_unit_inputs fui
left join titus.teacher_source_units su on su.source_unit_id = fui.source_unit_id
left join titus.teacher_source_adjudications sa on sa.adjudication_id = fui.source_adjudication_id
left join titus.teacher_source_adjudication_targets sat on sat.adjudication_target_id = fui.source_adjudication_target_id
left join titus.teacher_patterns tp on tp.teacher_pattern_id = fui.teacher_pattern_id
left join titus.teacher_pattern_claim_links tpcl on tpcl.teacher_pattern_claim_link_id = fui.teacher_pattern_claim_link_id
left join titus.teacher_term_senses tts on tts.teacher_term_sense_id = fui.teacher_term_sense_id
left join titus.teacher_term_sense_targets ttst on ttst.teacher_term_sense_target_id = fui.teacher_term_sense_target_id
left join titus.canon_claims cc on cc.canon_claim_id = fui.canon_claim_id
left join titus.canon_structures cs on cs.canon_structure_id = fui.canon_structure_id
left join titus.truth_refs tr on tr.truth_ref_id = fui.truth_ref_id;

create or replace view titus.v_formation_unit_workspace_v1
with (security_invoker = true)
as
select
  fu.formation_unit_id,
  fu.program_id,
  fu.teacher_id,
  t.teacher_key,
  t.display_name as teacher_name,
  fu.lesson_slug,
  lp.title as lesson_title,
  fu.unit_key,
  fu.version,
  fu.title,
  fu.governing_question,
  fu.learner_goal,
  fu.formation_state,
  fu.review_state,
  fu.confidence,
  fu.notes,
  fu.created_at,
  fu.updated_at,
  (select count(*) from titus.formation_unit_inputs i where i.formation_unit_id = fu.formation_unit_id) as input_count,
  (select count(*) from titus.v_formation_unit_input_health h where h.formation_unit_id = fu.formation_unit_id and h.potentially_stale) as potentially_stale_input_count,
  (select count(*) from titus.formation_unit_sections s where s.formation_unit_id = fu.formation_unit_id and s.section_status not in ('superseded','retired')) as section_count,
  (select count(*) from titus.formation_questions q where q.formation_unit_id = fu.formation_unit_id and q.status in ('open','researching')) as open_question_count,
  (select count(*) from titus.formation_responses r where r.formation_unit_id = fu.formation_unit_id and r.response_kind = 'teachback' and r.response_status <> 'retired') as teachback_count,
  (select count(*) from titus.formation_transfer_attempts a join titus.formation_transfer_cases c on c.formation_transfer_case_id = a.formation_transfer_case_id where c.formation_unit_id = fu.formation_unit_id and a.assessment_status = 'pass') as passed_transfer_count,
  (select a.articulation_text from titus.formation_articulations a where a.formation_unit_id = fu.formation_unit_id and a.articulation_status = 'current' order by a.articulation_version desc limit 1) as current_articulation
from titus.formation_units fu
join titus.teachers t on t.teacher_id = fu.teacher_id
join titus.lesson_packets lp on lp.lesson_slug = fu.lesson_slug;

revoke all on table titus.v_formation_unit_input_health from public, anon, authenticated;
revoke all on table titus.v_formation_unit_workspace_v1 from public, anon, authenticated;
grant select on table titus.v_formation_unit_input_health to service_role;
grant select on table titus.v_formation_unit_workspace_v1 to service_role;

comment on view titus.v_formation_unit_input_health is
  'Service-side review projection showing whether an exact Formation Unit dependency changed after its last review.';
comment on view titus.v_formation_unit_workspace_v1 is
  'Service-side Formation Workspace summary projection. Private until a viewer-aware application membrane is deliberately released.';

-- Guard the new private tables against accidental direct role exposure.
do $$
declare
  rel text;
  role_name text;
begin
  foreach rel in array array[
    'formation_units',
    'formation_unit_inputs',
    'formation_unit_sections',
    'formation_questions',
    'formation_responses',
    'formation_transfer_cases',
    'formation_transfer_attempts',
    'formation_articulations'
  ] loop
    foreach role_name in array array['anon', 'authenticated'] loop
      if has_table_privilege(role_name, format('titus.%I', rel), 'SELECT')
         or has_table_privilege(role_name, format('titus.%I', rel), 'INSERT')
         or has_table_privilege(role_name, format('titus.%I', rel), 'UPDATE')
         or has_table_privilege(role_name, format('titus.%I', rel), 'DELETE') then
        raise exception 'Titus formation membrane violation: role % has direct privilege on titus.%', role_name, rel;
      end if;
    end loop;
  end loop;
end
$$;
