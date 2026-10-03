-- Titus v2: generic university/program + teacher-source + Song-scoping workbench
-- Additive migration. Existing Titus course/lesson machinery remains intact.

alter table titus.course_slots
  add column if not exists delivery_mode text,
  add column if not exists duration_minutes integer;

create table titus.teachers (
  teacher_id uuid primary key default gen_random_uuid(),
  teacher_key text not null unique,
  display_name text not null,
  status text not null default 'active' check (status in ('candidate','active','inactive','retired')),
  bio_note text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table titus.programs (
  program_id uuid primary key default gen_random_uuid(),
  program_slug text not null unique,
  title text not null,
  subtitle text,
  public_description text,
  intended_learner text,
  program_kind text not null default 'pathway',
  program_status text not null default 'draft' check (program_status in ('draft','beta','published','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table titus.program_teachers (
  program_id uuid not null references titus.programs(program_id) on delete cascade,
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  teacher_role text not null default 'primary_teacher' check (teacher_role in ('primary_teacher','contributing_teacher','source_teacher','guest')),
  status text not null default 'active' check (status in ('active','inactive','retired')),
  notes text,
  created_at timestamptz not null default now(),
  primary key (program_id, teacher_id, teacher_role)
);

create table titus.course_teachers (
  course_slug text not null references titus.courses(course_slug) on delete cascade,
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  teacher_role text not null default 'primary_teacher' check (teacher_role in ('primary_teacher','contributing_teacher','source_teacher','guest')),
  status text not null default 'active' check (status in ('active','inactive','retired')),
  notes text,
  created_at timestamptz not null default now(),
  primary key (course_slug, teacher_id, teacher_role)
);

create table titus.curriculum_versions (
  curriculum_version_id uuid primary key default gen_random_uuid(),
  program_id uuid not null references titus.programs(program_id) on delete cascade,
  version_no integer not null,
  version_label text not null,
  version_status text not null default 'draft' check (version_status in ('draft','frozen','published','superseded')),
  is_current boolean not null default false,
  based_on_version_id uuid references titus.curriculum_versions(curriculum_version_id) on delete set null,
  change_summary text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (program_id, version_no)
);

create unique index titus_curriculum_versions_one_current
  on titus.curriculum_versions(program_id)
  where is_current;

create table titus.program_course_placements (
  placement_id uuid primary key default gen_random_uuid(),
  curriculum_version_id uuid not null references titus.curriculum_versions(curriculum_version_id) on delete cascade,
  course_slug text not null references titus.courses(course_slug) on delete cascade,
  module_number integer,
  display_title text,
  course_role text not null default 'required' check (course_role in ('required','elective','support','capstone')),
  placement_status text not null default 'planned' check (placement_status in ('planned','active','published','retired')),
  sort_order integer not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (curriculum_version_id, course_slug),
  unique (curriculum_version_id, module_number)
);

create table titus.curriculum_slot_placements (
  slot_placement_id uuid primary key default gen_random_uuid(),
  curriculum_version_id uuid not null references titus.curriculum_versions(curriculum_version_id) on delete cascade,
  course_slug text not null,
  slot_key text not null,
  session_number integer,
  week_number integer,
  meeting_number integer,
  display_title text,
  placement_status text not null default 'planned' check (placement_status in ('planned','active','published','retired')),
  sort_order integer not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_slug, slot_key) references titus.course_slots(course_slug, slot_key) on delete cascade,
  unique (curriculum_version_id, course_slug, slot_key),
  unique (curriculum_version_id, course_slug, session_number)
);

create table titus.slot_canon_briefs (
  canon_brief_id uuid primary key default gen_random_uuid(),
  curriculum_version_id uuid not null references titus.curriculum_versions(curriculum_version_id) on delete cascade,
  course_slug text not null,
  slot_key text not null,
  brief_title text,
  canonical_center text,
  student_capability text,
  must_teach text[] not null default '{}',
  must_distinguish text[] not null default '{}',
  must_not_collapse text[] not null default '{}',
  known_limits text[] not null default '{}',
  brief_status text not null default 'draft' check (brief_status in ('draft','review','approved','superseded','retired')),
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_slug, slot_key) references titus.course_slots(course_slug, slot_key) on delete cascade,
  unique (curriculum_version_id, course_slug, slot_key)
);

create table titus.slot_song_scopes (
  slot_song_scope_id uuid primary key default gen_random_uuid(),
  canon_brief_id uuid not null references titus.slot_canon_briefs(canon_brief_id) on delete cascade,
  scope_source_schema text not null default 'draft',
  scope_source_table text not null,
  scope_target_key text not null,
  scope_label_snapshot text,
  scope_role text not null check (scope_role in ('primary','supporting','guardrail','prerequisite','contrast','excluded')),
  scope_note text,
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (canon_brief_id, scope_source_schema, scope_source_table, scope_target_key, scope_role)
);

create table titus.teacher_source_refs (
  teacher_source_ref_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  source_system text not null,
  source_external_ref text not null,
  title text not null,
  source_kind text not null default 'other' check (source_kind in ('book','ebook','article','outline','course','lesson','webinar','audio','video','transcript','slidebook','handout','chart','workshop','other')),
  source_date date,
  source_status text not null default 'available' check (source_status in ('known','available','partial','missing','retired')),
  original_filename text,
  metadata jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, source_system, source_external_ref)
);

create table titus.teacher_source_units (
  source_unit_id uuid primary key default gen_random_uuid(),
  teacher_source_ref_id uuid not null references titus.teacher_source_refs(teacher_source_ref_id) on delete cascade,
  unit_key text not null,
  unit_kind text not null check (unit_kind in ('claim','definition','distinction','framework','story','example','analogy','chart','exercise','question','application','scripture_interpretation','historical_assertion','teaching_sequence','memorable_phrase','other')),
  unit_title text,
  summary text not null,
  content_text text,
  source_locator jsonb not null default '{}'::jsonb,
  extraction_status text not null default 'candidate' check (extraction_status in ('candidate','reviewed','confirmed','retired')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_source_ref_id, unit_key)
);

create table titus.teacher_source_song_scopes (
  teacher_source_song_scope_id uuid primary key default gen_random_uuid(),
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  scope_source_schema text not null default 'draft',
  scope_source_table text not null,
  scope_target_key text not null,
  scope_label_snapshot text,
  scope_relation text not null check (scope_relation in ('direct','near_direct','umbrella','partial','metaphor','teaching_frame','teaching_question','false_friend','conflict','contrast','other')),
  scope_note text,
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_unit_id, scope_source_schema, scope_source_table, scope_target_key, scope_relation)
);

create table titus.teacher_source_adjudications (
  adjudication_id uuid primary key default gen_random_uuid(),
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  teacher_source_song_scope_id uuid references titus.teacher_source_song_scopes(teacher_source_song_scope_id) on delete set null,
  curriculum_version_id uuid references titus.curriculum_versions(curriculum_version_id) on delete set null,
  disposition text not null check (disposition in ('use_as_is','edit','extract','recontextualize','example_only','term_only','retire','replace','hold')),
  approval_status text not null default 'pending' check (approval_status in ('pending','reviewed','approved','rejected','deferred','superseded')),
  rationale text not null,
  required_revision text,
  guardrail text,
  replacement_note text,
  supersedes_adjudication_id uuid references titus.teacher_source_adjudications(adjudication_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table titus.teacher_terms (
  teacher_term_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete cascade,
  term text not null,
  normalized_term text not null,
  teacher_meaning text,
  preferred_student_term boolean not null default false,
  term_status text not null default 'candidate' check (term_status in ('candidate','attested','preferred','restricted','avoid','retired')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, normalized_term)
);

create table titus.teacher_term_attestations (
  attestation_id uuid primary key default gen_random_uuid(),
  teacher_term_id uuid not null references titus.teacher_terms(teacher_term_id) on delete cascade,
  teacher_source_ref_id uuid not null references titus.teacher_source_refs(teacher_source_ref_id) on delete cascade,
  source_unit_id uuid references titus.teacher_source_units(source_unit_id) on delete set null,
  source_locator jsonb not null default '{}'::jsonb,
  attestation_note text,
  created_at timestamptz not null default now()
);

create table titus.teacher_term_song_scopes (
  teacher_term_song_scope_id uuid primary key default gen_random_uuid(),
  teacher_term_id uuid not null references titus.teacher_terms(teacher_term_id) on delete cascade,
  scope_source_schema text not null default 'draft',
  scope_source_table text not null,
  scope_target_key text not null,
  scope_label_snapshot text,
  scope_relation text not null check (scope_relation in ('direct','near_direct','umbrella','partial','metaphor','teaching_frame','teaching_question','false_friend','conflict','new_language_needed','other')),
  student_use_status text not null default 'allowed' check (student_use_status in ('preferred','allowed','restricted','avoid','replace')),
  guardrail text,
  rationale text,
  confidence text check (confidence is null or confidence in ('low','medium','high')),
  review_status text not null default 'candidate' check (review_status in ('candidate','reviewed','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_term_id, scope_source_schema, scope_source_table, scope_target_key, scope_relation)
);

create table titus.slot_teacher_source_candidates (
  slot_teacher_source_candidate_id uuid primary key default gen_random_uuid(),
  curriculum_version_id uuid not null references titus.curriculum_versions(curriculum_version_id) on delete cascade,
  course_slug text not null,
  slot_key text not null,
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  adjudication_id uuid references titus.teacher_source_adjudications(adjudication_id) on delete set null,
  recovery_role text not null default 'other' check (recovery_role in ('core_explanation','example','story','definition','visual','exercise','case_study','contrast','historical_context','terminology','other')),
  recovery_status text not null default 'candidate' check (recovery_status in ('candidate','reviewing','approved','rejected','deferred')),
  recovery_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_slug, slot_key) references titus.course_slots(course_slug, slot_key) on delete cascade,
  unique (curriculum_version_id, course_slug, slot_key, source_unit_id, recovery_role)
);

create table titus.lesson_teacher_source_links (
  lesson_teacher_source_link_id uuid primary key default gen_random_uuid(),
  lesson_slug text not null references titus.lesson_packets(lesson_slug) on delete cascade,
  source_unit_id uuid not null references titus.teacher_source_units(source_unit_id) on delete cascade,
  adjudication_id uuid references titus.teacher_source_adjudications(adjudication_id) on delete set null,
  lesson_role text not null default 'other' check (lesson_role in ('core_explanation','example','story','definition','visual','exercise','case_study','contrast','historical_context','terminology','other')),
  adaptation_note text,
  status text not null default 'candidate' check (status in ('candidate','approved','rejected','retired')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_slug, source_unit_id, lesson_role)
);

create table titus.curriculum_findings (
  finding_id uuid primary key default gen_random_uuid(),
  program_id uuid references titus.programs(program_id) on delete cascade,
  curriculum_version_id uuid references titus.curriculum_versions(curriculum_version_id) on delete set null,
  target_type text not null,
  target_key text not null,
  finding_kind text not null check (finding_kind in ('terminology','placement','correction','gap','reuse','scope','evidence','source_request','question','production','other')),
  finding_text text not null,
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','accepted','rejected','deferred','resolved','superseded')),
  resolution text,
  source_provenance jsonb not null default '{}'::jsonb,
  supersedes_finding_id uuid references titus.curriculum_findings(finding_id) on delete set null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table titus.curriculum_decisions (
  decision_id uuid primary key default gen_random_uuid(),
  decision_key text not null unique,
  program_id uuid references titus.programs(program_id) on delete cascade,
  curriculum_version_id uuid references titus.curriculum_versions(curriculum_version_id) on delete set null,
  target_type text not null,
  target_key text not null,
  decision_type text not null,
  decision_text text not null,
  rationale text not null,
  status text not null default 'accepted' check (status in ('proposed','accepted','superseded','reversed')),
  supersedes_decision_id uuid references titus.curriculum_decisions(decision_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table titus.workspace_state (
  program_id uuid primary key references titus.programs(program_id) on delete cascade,
  active_curriculum_version_id uuid references titus.curriculum_versions(curriculum_version_id) on delete set null,
  active_course_slug text references titus.courses(course_slug) on delete set null,
  active_slot_key text,
  active_phase text not null default 'canon_scope' check (active_phase in ('syllabus_baseline','canon_scope','teacher_recovery','adjudication','gap_analysis','authoring','review','recording','qa','published')),
  next_action text,
  context_note text,
  updated_at timestamptz not null default now(),
  foreign key (active_course_slug, active_slot_key) references titus.course_slots(course_slug, slot_key) on delete set null
);

create index titus_slot_song_scopes_target_idx on titus.slot_song_scopes(scope_source_schema, scope_source_table, scope_target_key);
create index titus_teacher_source_units_kind_idx on titus.teacher_source_units(unit_kind, extraction_status);
create index titus_teacher_source_song_scopes_target_idx on titus.teacher_source_song_scopes(scope_source_schema, scope_source_table, scope_target_key);
create index titus_teacher_term_song_scopes_target_idx on titus.teacher_term_song_scopes(scope_source_schema, scope_source_table, scope_target_key);
create index titus_curriculum_findings_open_idx on titus.curriculum_findings(program_id, status, priority);
create index titus_slot_source_candidates_idx on titus.slot_teacher_source_candidates(curriculum_version_id, course_slug, slot_key, recovery_status);

-- Seed Dr. Marlene McMillan as the first teacher and the existing nine-module pathway as a draft program.
insert into titus.teachers (teacher_key, display_name, status, bio_note)
values ('marlene_mcmillan', 'Dr. Marlene McMillan', 'active', 'Founding teacher whose prior corpus is being scoped through Song for Titus-approved teaching.')
on conflict (teacher_key) do update set display_name = excluded.display_name, status = excluded.status, updated_at = now();

insert into titus.programs (program_slug, title, subtitle, public_description, intended_learner, program_kind, program_status)
values (
  'mcmillan-university',
  'Dr. Marlene McMillan University',
  'Canon-first Titus teaching pathway',
  'Working nine-module pathway built from canon/Song first, then supplied with approved and corrected teaching assets from Dr. McMillan''s prior corpus.',
  'Students progressing as a cohort through the full nine-module pathway.',
  'cohort_pathway',
  'draft'
)
on conflict (program_slug) do update set title=excluded.title, subtitle=excluded.subtitle, public_description=excluded.public_description, intended_learner=excluded.intended_learner, updated_at=now();

insert into titus.program_teachers (program_id, teacher_id, teacher_role, status)
select p.program_id, t.teacher_id, 'primary_teacher', 'active'
from titus.programs p cross join titus.teachers t
where p.program_slug='mcmillan-university' and t.teacher_key='marlene_mcmillan'
on conflict do nothing;

insert into titus.courses (course_slug, title, subtitle, public_description, intended_reader, course_status, sort_order)
values
 ('learning-to-think-truthfully','Learning to Think Truthfully',null,null,null,'draft',1),
 ('liberty-what-it-is-and-how-it-works','Liberty: What It Is and How It Works',null,null,null,'draft',2),
 ('kingdom-and-order-of-reality','The Kingdom and the Order of Reality',null,null,null,'draft',3),
 ('self-government-character-and-success','Self-Government, Character and Success',null,null,null,'draft',4),
 ('economics-prosperity-poverty-and-stewardship','Economics, Prosperity, Poverty and Stewardship',null,null,null,'draft',5),
 ('education-language-and-cultural-formation','Education, Language and Cultural Formation',null,null,null,'draft',6),
 ('government-law-authority-and-citizenship','Government, Law, Authority and Citizenship',null,null,null,'draft',7),
 ('relationship-prayer-forgiveness-and-repair','Relationship, Prayer, Forgiveness and Repair',null,null,null,'draft',8),
 ('integrated-kingdom-leadership','Integrated Kingdom Leadership',null,null,null,'draft',9)
on conflict (course_slug) do update set title=excluded.title, sort_order=excluded.sort_order, updated_at=now();

insert into titus.course_teachers (course_slug, teacher_id, teacher_role, status)
select c.course_slug, t.teacher_id, 'primary_teacher', 'active'
from titus.courses c
join titus.teachers t on t.teacher_key='marlene_mcmillan'
where c.course_slug in (
 'learning-to-think-truthfully','liberty-what-it-is-and-how-it-works','kingdom-and-order-of-reality',
 'self-government-character-and-success','economics-prosperity-poverty-and-stewardship','education-language-and-cultural-formation',
 'government-law-authority-and-citizenship','relationship-prayer-forgiveness-and-repair','integrated-kingdom-leadership'
)
on conflict do nothing;

insert into titus.curriculum_versions (program_id, version_no, version_label, version_status, is_current, change_summary)
select program_id, 0, 'Founding syllabus baseline', 'frozen', false, 'Original nine-module / Module 1 syllabus retained as the pre-reconstruction baseline.'
from titus.programs where program_slug='mcmillan-university'
on conflict (program_id, version_no) do update set version_label=excluded.version_label, version_status=excluded.version_status, change_summary=excluded.change_summary, updated_at=now();

insert into titus.curriculum_versions (program_id, version_no, version_label, version_status, is_current, based_on_version_id, change_summary)
select p.program_id, 1, 'Canon-first working reconstruction', 'draft', true, v0.curriculum_version_id,
       'Working copy of the founding syllabus. Song/canon scope is established first; teacher material is then recovered, adjudicated, and attached.'
from titus.programs p
join titus.curriculum_versions v0 on v0.program_id=p.program_id and v0.version_no=0
where p.program_slug='mcmillan-university'
on conflict (program_id, version_no) do update set version_label=excluded.version_label, version_status=excluded.version_status, based_on_version_id=excluded.based_on_version_id, change_summary=excluded.change_summary, updated_at=now();

update titus.curriculum_versions cv
set is_current = (cv.version_no = 1), updated_at=now()
where cv.program_id = (select program_id from titus.programs where program_slug='mcmillan-university');

insert into titus.program_course_placements (curriculum_version_id, course_slug, module_number, display_title, course_role, placement_status, sort_order)
select cv.curriculum_version_id, x.course_slug, x.module_number, x.display_title, 'required', 'planned', x.module_number
from titus.curriculum_versions cv
join titus.programs p on p.program_id=cv.program_id and p.program_slug='mcmillan-university'
cross join (values
 (1,'learning-to-think-truthfully','Learning to Think Truthfully'),
 (2,'liberty-what-it-is-and-how-it-works','Liberty: What It Is and How It Works'),
 (3,'kingdom-and-order-of-reality','The Kingdom and the Order of Reality'),
 (4,'self-government-character-and-success','Self-Government, Character and Success'),
 (5,'economics-prosperity-poverty-and-stewardship','Economics, Prosperity, Poverty and Stewardship'),
 (6,'education-language-and-cultural-formation','Education, Language and Cultural Formation'),
 (7,'government-law-authority-and-citizenship','Government, Law, Authority and Citizenship'),
 (8,'relationship-prayer-forgiveness-and-repair','Relationship, Prayer, Forgiveness and Repair'),
 (9,'integrated-kingdom-leadership','Integrated Kingdom Leadership')
) as x(module_number, course_slug, display_title)
where cv.version_no in (0,1)
on conflict (curriculum_version_id, course_slug) do update set module_number=excluded.module_number, display_title=excluded.display_title, sort_order=excluded.sort_order, updated_at=now();

insert into titus.course_slots (course_slug, slot_key, slot_number, slot_title, slot_role, research_status, slot_status, why_this_slot_exists, sort_order, delivery_mode, duration_minutes)
values
 ('learning-to-think-truthfully','m01-s01',1,'Truth, Reality & Responsibility to Think','lesson','needs_noel_deep_dive','planned','Founding syllabus session 1; canon-first center to be rebuilt in Titus.',1,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s02',2,'Words as Materials of Thought','lesson','needs_noel_deep_dive','planned','Founding syllabus session 2; canon-first center to be rebuilt in Titus.',2,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s03',3,'Premises, Inferences & Conclusions','lesson','needs_noel_deep_dive','planned','Founding syllabus session 3; canon-first center to be rebuilt in Titus.',3,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s04',4,'Fact, Opinion, Perception & Condition','lesson','needs_noel_deep_dive','planned','Founding syllabus session 4; canon-first center to be rebuilt in Titus.',4,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s05',5,'Cause to Effect Without Oversimplification','lesson','needs_noel_deep_dive','planned','Founding syllabus session 5; canon-first center to be rebuilt in Titus.',5,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s06',6,'LIVE Q&A #1 Definition & Premise Clinic','supporting_node','needs_noel_deep_dive','planned','Required live clinic from the founding syllabus.',6,'live',90),
 ('learning-to-think-truthfully','m01-s07',7,'Worldview, Frame & Interpretive Lens','lesson','needs_noel_deep_dive','planned','Founding syllabus session 7; canon-first center to be rebuilt in Titus.',7,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s08',8,'Source Is Not the Same as Carrier','lesson','needs_noel_deep_dive','planned','Founding syllabus session 8; direct bridge into Song source/carrier distinctions.',8,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s09',9,'Reading a Claim Before Refuting It','lesson','needs_noel_deep_dive','planned','Founding syllabus session 9; canon-first center to be rebuilt in Titus.',9,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s10',10,'Relativism, Absolutes & Competing Kinds of Claims','lesson','needs_noel_deep_dive','planned','Founding syllabus session 10; claim kinds and bounded truth require Song scoping.',10,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s11',11,'Language, Redefinition & Cultural Formation','lesson','needs_noel_deep_dive','planned','Founding syllabus session 11; semantic distinctions require Song scoping.',11,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s12',12,'LIVE Q&A #2 Argument & Application Clinic','supporting_node','needs_noel_deep_dive','planned','Required live clinic from the founding syllabus.',12,'live',90),
 ('learning-to-think-truthfully','m01-s13',13,'Repeatable Method for New Problems','lesson','needs_noel_deep_dive','planned','Founding syllabus session 13; candidate location for the Song discovery method.',13,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s14',14,'Capstone Case Workshop','capstone','needs_noel_deep_dive','planned','Founding syllabus capstone workshop.',14,'prerecorded',90),
 ('learning-to-think-truthfully','m01-s15',15,'LIVE Q&A #3 Oral Defense, Correction & Bridge to Module 2','capstone','needs_noel_deep_dive','planned','Required live oral defense and bridge from the founding syllabus.',15,'live',90)
on conflict (course_slug, slot_key) do update set slot_number=excluded.slot_number, slot_title=excluded.slot_title, slot_role=excluded.slot_role, why_this_slot_exists=excluded.why_this_slot_exists, sort_order=excluded.sort_order, delivery_mode=excluded.delivery_mode, duration_minutes=excluded.duration_minutes, updated_at=now();

insert into titus.curriculum_slot_placements (curriculum_version_id, course_slug, slot_key, session_number, week_number, meeting_number, display_title, placement_status, sort_order)
select cv.curriculum_version_id, 'learning-to-think-truthfully', s.slot_key, s.slot_number,
       ((s.slot_number - 1) / 3) + 1,
       ((s.slot_number - 1) % 3) + 1,
       s.slot_title, 'planned', s.slot_number
from titus.curriculum_versions cv
join titus.programs p on p.program_id=cv.program_id and p.program_slug='mcmillan-university'
join titus.course_slots s on s.course_slug='learning-to-think-truthfully'
where cv.version_no in (0,1)
on conflict (curriculum_version_id, course_slug, slot_key) do update set session_number=excluded.session_number, week_number=excluded.week_number, meeting_number=excluded.meeting_number, display_title=excluded.display_title, sort_order=excluded.sort_order, updated_at=now();

insert into titus.workspace_state (program_id, active_curriculum_version_id, active_course_slug, active_slot_key, active_phase, next_action, context_note)
select p.program_id, cv.curriculum_version_id, 'learning-to-think-truthfully', 'm01-s01', 'canon_scope',
       'Build the canon brief for Session 1, then recover Dr. McMillan material against that scope.',
       'Titus is the approved-teaching layer. Song/canon scopes the lesson first; teacher corpus is recovered second.'
from titus.programs p
join titus.curriculum_versions cv on cv.program_id=p.program_id and cv.version_no=1
where p.program_slug='mcmillan-university'
on conflict (program_id) do update set active_curriculum_version_id=excluded.active_curriculum_version_id, active_course_slug=excluded.active_course_slug, active_slot_key=excluded.active_slot_key, active_phase=excluded.active_phase, next_action=excluded.next_action, context_note=excluded.context_note, updated_at=now();

create or replace view titus.v_program_curriculum_map_v2 as
select
  p.program_slug,
  p.title as program_title,
  cv.curriculum_version_id,
  cv.version_no,
  cv.version_label,
  cv.version_status,
  cv.is_current,
  pcp.module_number,
  pcp.course_slug,
  coalesce(pcp.display_title, c.title) as course_title,
  csp.session_number,
  csp.week_number,
  csp.meeting_number,
  csp.slot_key,
  coalesce(csp.display_title, cs.slot_title) as session_title,
  cs.slot_role,
  cs.delivery_mode,
  cs.duration_minutes,
  cs.research_status,
  cs.slot_status
from titus.programs p
join titus.curriculum_versions cv on cv.program_id=p.program_id
join titus.program_course_placements pcp on pcp.curriculum_version_id=cv.curriculum_version_id
join titus.courses c on c.course_slug=pcp.course_slug
left join titus.curriculum_slot_placements csp on csp.curriculum_version_id=cv.curriculum_version_id and csp.course_slug=pcp.course_slug
left join titus.course_slots cs on cs.course_slug=csp.course_slug and cs.slot_key=csp.slot_key;

create or replace view titus.v_teacher_song_vocabulary_v2 as
select
  t.teacher_key,
  t.display_name,
  tt.teacher_term_id,
  tt.term,
  tt.normalized_term,
  tt.teacher_meaning,
  tt.preferred_student_term,
  tt.term_status,
  ts.scope_source_schema,
  ts.scope_source_table,
  ts.scope_target_key,
  ts.scope_label_snapshot,
  ts.scope_relation,
  ts.student_use_status,
  ts.guardrail,
  ts.rationale,
  ts.confidence,
  ts.review_status
from titus.teacher_terms tt
join titus.teachers t on t.teacher_id=tt.teacher_id
left join titus.teacher_term_song_scopes ts on ts.teacher_term_id=tt.teacher_term_id;

create or replace view titus.v_slot_workbench_v2 as
select
  p.program_slug,
  cv.version_no,
  pcp.module_number,
  csp.course_slug,
  csp.session_number,
  csp.week_number,
  csp.slot_key,
  coalesce(csp.display_title, cs.slot_title) as session_title,
  cs.delivery_mode,
  cb.canon_brief_id,
  cb.brief_status,
  cb.canonical_center,
  cb.student_capability,
  (select count(*) from titus.slot_song_scopes sss where sss.canon_brief_id=cb.canon_brief_id) as song_scope_count,
  (select count(*) from titus.slot_teacher_source_candidates stsc where stsc.curriculum_version_id=cv.curriculum_version_id and stsc.course_slug=csp.course_slug and stsc.slot_key=csp.slot_key) as teacher_source_candidate_count,
  (select count(*) from titus.slot_teacher_source_candidates stsc where stsc.curriculum_version_id=cv.curriculum_version_id and stsc.course_slug=csp.course_slug and stsc.slot_key=csp.slot_key and stsc.recovery_status='approved') as approved_teacher_source_count,
  (select count(*) from titus.curriculum_findings f where f.curriculum_version_id=cv.curriculum_version_id and f.target_type='slot' and f.target_key=(csp.course_slug || ':' || csp.slot_key) and f.status in ('open','deferred')) as open_finding_count
from titus.programs p
join titus.curriculum_versions cv on cv.program_id=p.program_id and cv.is_current
join titus.program_course_placements pcp on pcp.curriculum_version_id=cv.curriculum_version_id
join titus.curriculum_slot_placements csp on csp.curriculum_version_id=cv.curriculum_version_id and csp.course_slug=pcp.course_slug
join titus.course_slots cs on cs.course_slug=csp.course_slug and cs.slot_key=csp.slot_key
left join titus.slot_canon_briefs cb on cb.curriculum_version_id=cv.curriculum_version_id and cb.course_slug=csp.course_slug and cb.slot_key=csp.slot_key;

create or replace view titus.v_curriculum_workspace_v2 as
select
  p.program_slug,
  p.title as program_title,
  t.teacher_key as primary_teacher_key,
  t.display_name as primary_teacher,
  cv.version_no as active_version_no,
  cv.version_label as active_version_label,
  ws.active_course_slug,
  ws.active_slot_key,
  cs.slot_title as active_slot_title,
  ws.active_phase,
  ws.next_action,
  ws.context_note,
  (select count(*) from titus.curriculum_findings f where f.program_id=p.program_id and f.status in ('open','deferred')) as open_finding_count,
  (select count(*) from titus.curriculum_decisions d where d.program_id=p.program_id and d.status='accepted') as accepted_decision_count,
  ws.updated_at
from titus.workspace_state ws
join titus.programs p on p.program_id=ws.program_id
left join titus.curriculum_versions cv on cv.curriculum_version_id=ws.active_curriculum_version_id
left join titus.course_slots cs on cs.course_slug=ws.active_course_slug and cs.slot_key=ws.active_slot_key
left join titus.program_teachers pt on pt.program_id=p.program_id and pt.teacher_role='primary_teacher' and pt.status='active'
left join titus.teachers t on t.teacher_id=pt.teacher_id;
