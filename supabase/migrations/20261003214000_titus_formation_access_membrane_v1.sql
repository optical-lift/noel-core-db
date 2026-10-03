-- Titus Formation Access Membrane v1
--
-- Governing identity chain:
--   authenticated session
--   → reality.auth_person_bindings
--   → canonical reality Person
--   → titus.teacher_person_bindings
--   → Titus Teacher profile
--   → bounded self-access to that Teacher's learner-ready Formation Units
--
-- This migration does not fabricate a Dr. Marlene Person or auth binding.
-- It remains fail-closed until those real identity relations are established.

create table if not exists titus.teacher_person_bindings (
  teacher_person_binding_id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references titus.teachers(teacher_id) on delete restrict,
  person_entity_id uuid not null references reality.entities(id) on delete restrict,
  binding_state text not null default 'active' check (binding_state = any (array['active'::text, 'retired'::text])),
  binding_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(binding_basis) = 'object'),
  bound_at timestamptz not null default now(),
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teacher_person_bindings_retirement_time_check check (
    (binding_state = 'active' and retired_at is null)
    or (binding_state = 'retired' and retired_at is not null and retired_at >= bound_at)
  )
);

create unique index if not exists teacher_person_bindings_one_active_teacher_uq
  on titus.teacher_person_bindings (teacher_id)
  where binding_state = 'active';

create index if not exists teacher_person_bindings_active_person_idx
  on titus.teacher_person_bindings (person_entity_id, teacher_id)
  where binding_state = 'active';

create or replace function titus.guard_teacher_person_binding_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, titus, reality
as $$
declare
  v_kind text;
  v_identity_state text;
begin
  select e.entity_kind, e.identity_state
  into v_kind, v_identity_state
  from reality.entities e
  where e.id = new.person_entity_id;

  if not found then
    raise exception 'teacher_person_binding requires an existing canonical Reality Person';
  end if;

  if v_kind <> 'person' or v_identity_state <> 'canonical' then
    raise exception 'teacher_person_binding requires entity_kind=person and identity_state=canonical';
  end if;

  return new;
end;
$$;

revoke all on function titus.guard_teacher_person_binding_v1() from public, anon, authenticated, service_role;

create trigger teacher_person_bindings_guard
before insert or update of person_entity_id, binding_state, retired_at
on titus.teacher_person_bindings
for each row execute function titus.guard_teacher_person_binding_v1();

create trigger teacher_person_bindings_set_updated_at
before update on titus.teacher_person_bindings
for each row execute function titus.set_formation_updated_at();

comment on table titus.teacher_person_bindings is
  'Domain-specific identity relation binding one Titus Teacher profile to the canonical Reality Person that profile represents. Auth identity remains owned by reality.auth_person_bindings.';

alter table titus.teacher_person_bindings enable row level security;
revoke all on table titus.teacher_person_bindings from public, anon, authenticated;
grant select, insert, update, delete on table titus.teacher_person_bindings to service_role;

-- Internal current-person resolver. It validates the actual auth session and
-- shared Reality auth-person binding. It is deliberately not granted to clients.
create or replace function titus.current_authenticated_person_entity_id_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, reality, titus
as $$
declare
  v_uid uuid := auth.uid();
  v_claims jsonb := auth.jwt();
  v_session_id uuid;
  v_person_id uuid;
begin
  if v_uid is null then
    return null;
  end if;

  begin
    v_session_id := nullif(v_claims->>'session_id', '')::uuid;
  exception when others then
    return null;
  end;

  if v_session_id is null or not exists (
    select 1
    from auth.sessions s
    where s.id = v_session_id
      and s.user_id = v_uid
      and (s.not_after is null or s.not_after > now())
  ) then
    return null;
  end if;

  if not exists (
    select 1
    from auth.users u
    where u.id = v_uid
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= now())
  ) then
    return null;
  end if;

  select b.person_entity_id
  into v_person_id
  from reality.auth_person_bindings b
  join reality.entities e
    on e.id = b.person_entity_id
   and e.entity_kind = 'person'
   and e.identity_state = 'canonical'
  where b.auth_user_id = v_uid
    and b.binding_state = 'active'
    and b.retired_at is null
  order by b.bound_at desc, b.id
  limit 1;

  return v_person_id;
end;
$$;

revoke all on function titus.current_authenticated_person_entity_id_v1() from public, anon, authenticated, service_role;

-- Resolve the authenticated person's Titus Teacher profile(s) without exposing
-- raw canonical tables or treating auth identity as Teacher identity.
create or replace function public.titus_formation_access_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, reality, titus
as $$
declare
  v_uid uuid := auth.uid();
  v_person_id uuid;
  v_person_name text;
  v_teachers jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    return jsonb_build_object(
      'contractVersion', 'titus_formation_access_self_v1',
      'authenticated', false,
      'state', 'anonymous',
      'teachers', '[]'::jsonb
    );
  end if;

  v_person_id := titus.current_authenticated_person_entity_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion', 'titus_formation_access_self_v1',
      'authenticated', false,
      'state', 'identity_not_ready',
      'teachers', '[]'::jsonb
    );
  end if;

  select e.display_name
  into v_person_name
  from reality.entities e
  where e.id = v_person_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'teacherId', t.teacher_id,
        'teacherKey', t.teacher_key,
        'displayName', t.display_name,
        'teacherStatus', t.status,
        'bindingId', b.teacher_person_binding_id,
        'boundAt', b.bound_at
      )
      order by t.display_name, t.teacher_id
    ),
    '[]'::jsonb
  )
  into v_teachers
  from titus.teacher_person_bindings b
  join titus.teachers t
    on t.teacher_id = b.teacher_id
   and t.status = 'active'
  where b.person_entity_id = v_person_id
    and b.binding_state = 'active'
    and b.retired_at is null;

  if jsonb_array_length(v_teachers) = 0 then
    return jsonb_build_object(
      'contractVersion', 'titus_formation_access_self_v1',
      'authenticated', true,
      'state', 'teacher_binding_required',
      'person', jsonb_build_object(
        'id', v_person_id,
        'displayName', v_person_name
      ),
      'teachers', v_teachers,
      'truthBoundary', jsonb_build_object(
        'authUserIsNotPerson', true,
        'personIsNotTeacherProfile', true,
        'serviceRoleIsNotViewerAuthority', true
      )
    );
  end if;

  return jsonb_build_object(
    'contractVersion', 'titus_formation_access_self_v1',
    'authenticated', true,
    'state', 'ready',
    'person', jsonb_build_object(
      'id', v_person_id,
      'displayName', v_person_name
    ),
    'teachers', v_teachers,
    'truthBoundary', jsonb_build_object(
      'authUserIsNotPerson', true,
      'personIsNotTeacherProfile', true,
      'selfBindingDoesNotGrantBuilderAuthority', true,
      'serviceRoleIsNotViewerAuthority', true
    )
  );
end;
$$;

revoke all on function public.titus_formation_access_self_api_v1() from public, anon, authenticated, service_role;
grant execute on function public.titus_formation_access_self_api_v1() to authenticated, service_role;

-- Learner-facing projection for one Formation Unit. Draft/review-only formation
-- content fails closed until the unit and sections are learner-ready.
create or replace function public.titus_formation_unit_self_api_v1(
  p_formation_unit_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, auth, reality, titus
as $$
declare
  v_person_id uuid;
  v_unit titus.formation_units%rowtype;
  v_teacher_name text;
  v_lesson_title text;
  v_sections jsonb := '[]'::jsonb;
  v_sources jsonb := '[]'::jsonb;
  v_canon_claims jsonb := '[]'::jsonb;
  v_canon_structures jsonb := '[]'::jsonb;
  v_song_refs jsonb := '[]'::jsonb;
  v_questions jsonb := '[]'::jsonb;
  v_responses jsonb := '[]'::jsonb;
  v_transfer_cases jsonb := '[]'::jsonb;
  v_articulation jsonb;
begin
  v_person_id := titus.current_authenticated_person_entity_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion', 'titus_formation_unit_self_v1',
      'state', 'unauthorized'
    );
  end if;

  select fu.*
  into v_unit
  from titus.formation_units fu
  join titus.teacher_person_bindings b
    on b.teacher_id = fu.teacher_id
   and b.person_entity_id = v_person_id
   and b.binding_state = 'active'
   and b.retired_at is null
  where fu.formation_unit_id = p_formation_unit_id;

  if v_unit.formation_unit_id is null then
    return jsonb_build_object(
      'contractVersion', 'titus_formation_unit_self_v1',
      'state', 'not_found_or_unauthorized'
    );
  end if;

  if v_unit.review_state <> 'current'
     or v_unit.formation_state not in (
       'learner_ready',
       'encountered',
       'teachback_pending',
       'teachback_received',
       'teachback_reviewed',
       'transfer_pending',
       'transfer_reviewed',
       'integrated'
     ) then
    return jsonb_build_object(
      'contractVersion', 'titus_formation_unit_self_v1',
      'state', 'unit_not_ready',
      'formationUnitId', v_unit.formation_unit_id,
      'formationState', v_unit.formation_state,
      'reviewState', v_unit.review_state
    );
  end if;

  select t.display_name, lp.title
  into v_teacher_name, v_lesson_title
  from titus.teachers t
  join titus.lesson_packets lp on lp.lesson_slug = v_unit.lesson_slug
  where t.teacher_id = v_unit.teacher_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'sectionId', s.formation_unit_section_id,
        'sectionKey', s.section_key,
        'sectionKind', s.section_kind,
        'heading', s.heading,
        'body', s.body,
        'status', s.section_status,
        'sortOrder', s.sort_order
      ) order by s.sort_order, s.section_key
    ),
    '[]'::jsonb
  )
  into v_sections
  from titus.formation_unit_sections s
  where s.formation_unit_id = v_unit.formation_unit_id
    and s.section_status in ('reviewed', 'approved');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'sourceUnitId', su.source_unit_id,
        'unitKey', su.unit_key,
        'unitKind', su.unit_kind,
        'unitTitle', su.unit_title,
        'summary', su.summary,
        'contentText', su.content_text,
        'source', jsonb_build_object(
          'sourceRefId', sr.teacher_source_ref_id,
          'title', sr.title,
          'sourceSystem', sr.source_system,
          'sourceKind', sr.source_kind,
          'sourceDate', sr.source_date,
          'sourceStatus', sr.source_status
        ),
        'relationNote', i.relation_note,
        'materiality', i.materiality
      ) order by i.sort_order, su.unit_key
    ),
    '[]'::jsonb
  )
  into v_sources
  from titus.formation_unit_inputs i
  join titus.teacher_source_units su on su.source_unit_id = i.source_unit_id
  join titus.teacher_source_refs sr on sr.teacher_source_ref_id = su.teacher_source_ref_id
  where i.formation_unit_id = v_unit.formation_unit_id
    and i.input_kind = 'source_unit'
    and i.review_status in ('reviewed', 'approved');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'canonClaimId', c.canon_claim_id,
        'claimKey', c.claim_key,
        'claimText', c.claim_text,
        'claimKind', c.claim_kind,
        'status', c.status,
        'confidence', c.confidence,
        'inputRole', i.input_role,
        'materiality', i.materiality,
        'relationNote', i.relation_note
      ) order by i.sort_order, c.claim_key
    ),
    '[]'::jsonb
  )
  into v_canon_claims
  from titus.formation_unit_inputs i
  join titus.canon_claims c on c.canon_claim_id = i.canon_claim_id
  where i.formation_unit_id = v_unit.formation_unit_id
    and i.input_kind = 'canon_claim'
    and i.review_status in ('reviewed', 'approved')
    and c.status in ('reviewed', 'approved');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'canonStructureId', cs.canon_structure_id,
        'structureKey', cs.structure_key,
        'structureName', cs.structure_name,
        'structureType', cs.structure_type,
        'summary', cs.structure_summary,
        'status', cs.status,
        'confidence', cs.confidence,
        'inputRole', i.input_role,
        'materiality', i.materiality,
        'relationNote', i.relation_note
      ) order by i.sort_order, cs.structure_key
    ),
    '[]'::jsonb
  )
  into v_canon_structures
  from titus.formation_unit_inputs i
  join titus.canon_structures cs on cs.canon_structure_id = i.canon_structure_id
  where i.formation_unit_id = v_unit.formation_unit_id
    and i.input_kind = 'canon_structure'
    and i.review_status in ('reviewed', 'approved')
    and cs.status in ('reviewed', 'approved');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'truthRefId', tr.truth_ref_id,
        'refKind', tr.ref_kind,
        'functionKey', tr.function_key,
        'songObjectId', tr.song_object_id,
        'label', tr.label_snapshot,
        'inputRole', i.input_role,
        'materiality', i.materiality,
        'relationNote', i.relation_note
      ) order by i.sort_order, tr.ref_kind, tr.label_snapshot
    ),
    '[]'::jsonb
  )
  into v_song_refs
  from titus.formation_unit_inputs i
  join titus.truth_refs tr on tr.truth_ref_id = i.truth_ref_id
  where i.formation_unit_id = v_unit.formation_unit_id
    and i.input_kind = 'truth_ref'
    and i.review_status in ('reviewed', 'approved');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'questionId', q.formation_question_id,
        'kind', q.question_kind,
        'question', q.question_text,
        'status', q.status,
        'resolution', q.resolution,
        'sortOrder', q.sort_order
      ) order by q.sort_order, q.formation_question_id
    ),
    '[]'::jsonb
  )
  into v_questions
  from titus.formation_questions q
  where q.formation_unit_id = v_unit.formation_unit_id
    and q.status <> 'retired';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'responseId', r.formation_response_id,
        'questionId', r.formation_question_id,
        'kind', r.response_kind,
        'sourceKind', r.source_kind,
        'sourceRef', r.source_ref,
        'rawText', r.raw_text,
        'status', r.response_status,
        'createdAt', r.created_at
      ) order by r.created_at, r.formation_response_id
    ),
    '[]'::jsonb
  )
  into v_responses
  from titus.formation_responses r
  where r.formation_unit_id = v_unit.formation_unit_id
    and r.teacher_id = v_unit.teacher_id
    and r.response_status <> 'retired';

  if v_unit.formation_state in ('teachback_reviewed', 'transfer_pending', 'transfer_reviewed', 'integrated') then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'transferCaseId', tc.formation_transfer_case_id,
          'caseKey', tc.case_key,
          'version', tc.version,
          'title', tc.title,
          'prompt', tc.prompt_text,
          'expectedDistinctions', tc.expected_distinctions,
          'status', tc.case_status,
          'attempts', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'attemptId', ta.formation_transfer_attempt_id,
                'responseText', ta.response_text,
                'assessmentStatus', ta.assessment_status,
                'assessmentNote', ta.assessment_note,
                'submittedAt', ta.submitted_at,
                'assessedAt', ta.assessed_at
              ) order by ta.submitted_at, ta.formation_transfer_attempt_id
            )
            from titus.formation_transfer_attempts ta
            where ta.formation_transfer_case_id = tc.formation_transfer_case_id
              and ta.teacher_id = v_unit.teacher_id
          ), '[]'::jsonb)
        ) order by tc.case_key, tc.version
      ),
      '[]'::jsonb
    )
    into v_transfer_cases
    from titus.formation_transfer_cases tc
    where tc.formation_unit_id = v_unit.formation_unit_id
      and tc.case_status = 'learner_ready';
  end if;

  select jsonb_build_object(
    'articulationId', a.formation_articulation_id,
    'version', a.articulation_version,
    'text', a.articulation_text,
    'status', a.articulation_status,
    'createdAt', a.created_at,
    'updatedAt', a.updated_at
  )
  into v_articulation
  from titus.formation_articulations a
  where a.formation_unit_id = v_unit.formation_unit_id
    and a.teacher_id = v_unit.teacher_id
    and a.articulation_status = 'current'
  order by a.articulation_version desc
  limit 1;

  return jsonb_build_object(
    'contractVersion', 'titus_formation_unit_self_v1',
    'state', 'ready',
    'formationUnit', jsonb_build_object(
      'formationUnitId', v_unit.formation_unit_id,
      'lessonSlug', v_unit.lesson_slug,
      'lessonTitle', v_lesson_title,
      'teacherName', v_teacher_name,
      'unitKey', v_unit.unit_key,
      'version', v_unit.version,
      'title', v_unit.title,
      'governingQuestion', v_unit.governing_question,
      'learnerGoal', v_unit.learner_goal,
      'formationState', v_unit.formation_state,
      'reviewState', v_unit.review_state,
      'confidence', v_unit.confidence
    ),
    'historicalSources', v_sources,
    'canonClaims', v_canon_claims,
    'canonStructures', v_canon_structures,
    'songFunctionRefs', v_song_refs,
    'sections', v_sections,
    'questions', v_questions,
    'myResponses', v_responses,
    'transferCases', v_transfer_cases,
    'currentArticulation', v_articulation,
    'truthBoundary', jsonb_build_object(
      'historicalClaimIsNotCanonClaim', true,
      'songMappingIsNotCanonProof', true,
      'teachBackIsNotTransferProof', true,
      'maturedArticulationDoesNotRewriteHistory', true
    )
  );
end;
$$;

revoke all on function public.titus_formation_unit_self_api_v1(uuid) from public, anon, authenticated, service_role;
grant execute on function public.titus_formation_unit_self_api_v1(uuid) to authenticated, service_role;

-- Learner-authored response command. The authenticated caller never supplies
-- teacher_id; identity is resolved through the canonical Person↔Teacher relation.
create or replace function public.titus_submit_formation_response_self_api_v1(
  p_formation_unit_id uuid,
  p_response_kind text,
  p_raw_text text,
  p_formation_question_id uuid default null,
  p_source_kind text default 'typed_text',
  p_source_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, reality, titus
as $$
declare
  v_person_id uuid;
  v_unit titus.formation_units%rowtype;
  v_response_id uuid;
begin
  v_person_id := titus.current_authenticated_person_entity_id_v1();

  if v_person_id is null then
    return jsonb_build_object('contractVersion','titus_submit_formation_response_self_v1','state','unauthorized');
  end if;

  if p_response_kind not in ('teachback','integration_response','disagreement','new_example','research_note','other') then
    return jsonb_build_object('contractVersion','titus_submit_formation_response_self_v1','state','invalid_response_kind');
  end if;

  if p_source_kind not in ('typed_text','audio_transcript','uploaded_transcript','other') then
    return jsonb_build_object('contractVersion','titus_submit_formation_response_self_v1','state','invalid_source_kind');
  end if;

  if p_raw_text is null or btrim(p_raw_text) = '' then
    return jsonb_build_object('contractVersion','titus_submit_formation_response_self_v1','state','response_required');
  end if;

  select fu.*
  into v_unit
  from titus.formation_units fu
  join titus.teacher_person_bindings b
    on b.teacher_id = fu.teacher_id
   and b.person_entity_id = v_person_id
   and b.binding_state = 'active'
   and b.retired_at is null
  where fu.formation_unit_id = p_formation_unit_id;

  if v_unit.formation_unit_id is null then
    return jsonb_build_object('contractVersion','titus_submit_formation_response_self_v1','state','not_found_or_unauthorized');
  end if;

  if v_unit.review_state <> 'current'
     or v_unit.formation_state not in (
       'learner_ready','encountered','teachback_pending','teachback_received',
       'teachback_reviewed','transfer_pending','transfer_reviewed','integrated'
     ) then
    return jsonb_build_object(
      'contractVersion','titus_submit_formation_response_self_v1',
      'state','unit_not_ready',
      'formationState',v_unit.formation_state,
      'reviewState',v_unit.review_state
    );
  end if;

  if p_formation_question_id is not null and not exists (
    select 1
    from titus.formation_questions q
    where q.formation_question_id = p_formation_question_id
      and q.formation_unit_id = v_unit.formation_unit_id
      and q.status <> 'retired'
  ) then
    return jsonb_build_object('contractVersion','titus_submit_formation_response_self_v1','state','question_not_available');
  end if;

  insert into titus.formation_responses (
    formation_unit_id,
    teacher_id,
    formation_question_id,
    response_kind,
    source_kind,
    source_ref,
    raw_text,
    response_status
  ) values (
    v_unit.formation_unit_id,
    v_unit.teacher_id,
    p_formation_question_id,
    p_response_kind,
    p_source_kind,
    p_source_ref,
    p_raw_text,
    'submitted'
  )
  returning formation_response_id into v_response_id;

  if p_response_kind = 'teachback'
     and v_unit.formation_state in ('learner_ready','encountered','teachback_pending') then
    update titus.formation_units
    set formation_state = 'teachback_received'
    where formation_unit_id = v_unit.formation_unit_id;
  end if;

  return jsonb_build_object(
    'contractVersion','titus_submit_formation_response_self_v1',
    'state','submitted',
    'formationResponseId',v_response_id,
    'formationUnitId',v_unit.formation_unit_id,
    'responseKind',p_response_kind
  );
end;
$$;

revoke all on function public.titus_submit_formation_response_self_api_v1(uuid,text,text,uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function public.titus_submit_formation_response_self_api_v1(uuid,text,text,uuid,text,text) to authenticated, service_role;

-- Learner transfer-attempt command. Assessment authority remains separate.
create or replace function public.titus_submit_formation_transfer_attempt_self_api_v1(
  p_formation_transfer_case_id uuid,
  p_response_text text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, reality, titus
as $$
declare
  v_person_id uuid;
  v_unit titus.formation_units%rowtype;
  v_case titus.formation_transfer_cases%rowtype;
  v_attempt_id uuid;
begin
  v_person_id := titus.current_authenticated_person_entity_id_v1();

  if v_person_id is null then
    return jsonb_build_object('contractVersion','titus_submit_formation_transfer_attempt_self_v1','state','unauthorized');
  end if;

  if p_response_text is null or btrim(p_response_text) = '' then
    return jsonb_build_object('contractVersion','titus_submit_formation_transfer_attempt_self_v1','state','response_required');
  end if;

  select tc.*
  into v_case
  from titus.formation_transfer_cases tc
  where tc.formation_transfer_case_id = p_formation_transfer_case_id;

  if v_case.formation_transfer_case_id is null then
    return jsonb_build_object('contractVersion','titus_submit_formation_transfer_attempt_self_v1','state','not_found_or_unauthorized');
  end if;

  select fu.*
  into v_unit
  from titus.formation_units fu
  join titus.teacher_person_bindings b
    on b.teacher_id = fu.teacher_id
   and b.person_entity_id = v_person_id
   and b.binding_state = 'active'
   and b.retired_at is null
  where fu.formation_unit_id = v_case.formation_unit_id;

  if v_unit.formation_unit_id is null then
    return jsonb_build_object('contractVersion','titus_submit_formation_transfer_attempt_self_v1','state','not_found_or_unauthorized');
  end if;

  if v_unit.review_state <> 'current'
     or v_case.case_status <> 'learner_ready'
     or v_unit.formation_state not in ('teachback_reviewed','transfer_pending','transfer_reviewed') then
    return jsonb_build_object(
      'contractVersion','titus_submit_formation_transfer_attempt_self_v1',
      'state','transfer_not_ready',
      'formationState',v_unit.formation_state,
      'reviewState',v_unit.review_state,
      'caseStatus',v_case.case_status
    );
  end if;

  insert into titus.formation_transfer_attempts (
    formation_transfer_case_id,
    teacher_id,
    response_text,
    assessment_status
  ) values (
    v_case.formation_transfer_case_id,
    v_unit.teacher_id,
    p_response_text,
    'pending'
  )
  returning formation_transfer_attempt_id into v_attempt_id;

  if v_unit.formation_state = 'teachback_reviewed' then
    update titus.formation_units
    set formation_state = 'transfer_pending'
    where formation_unit_id = v_unit.formation_unit_id;
  end if;

  return jsonb_build_object(
    'contractVersion','titus_submit_formation_transfer_attempt_self_v1',
    'state','submitted',
    'formationTransferAttemptId',v_attempt_id,
    'formationTransferCaseId',v_case.formation_transfer_case_id,
    'assessmentStatus','pending'
  );
end;
$$;

revoke all on function public.titus_submit_formation_transfer_attempt_self_api_v1(uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.titus_submit_formation_transfer_attempt_self_api_v1(uuid,text) to authenticated, service_role;

-- Guard direct role exposure.
do $$
begin
  if has_table_privilege('anon', 'titus.teacher_person_bindings', 'SELECT')
     or has_table_privilege('authenticated', 'titus.teacher_person_bindings', 'SELECT')
     or has_table_privilege('anon', 'titus.teacher_person_bindings', 'INSERT')
     or has_table_privilege('authenticated', 'titus.teacher_person_bindings', 'INSERT')
     or has_table_privilege('anon', 'titus.teacher_person_bindings', 'UPDATE')
     or has_table_privilege('authenticated', 'titus.teacher_person_bindings', 'UPDATE')
     or has_table_privilege('anon', 'titus.teacher_person_bindings', 'DELETE')
     or has_table_privilege('authenticated', 'titus.teacher_person_bindings', 'DELETE') then
    raise exception 'Titus formation access membrane violation: direct client privilege exists on teacher_person_bindings';
  end if;
end
$$;
