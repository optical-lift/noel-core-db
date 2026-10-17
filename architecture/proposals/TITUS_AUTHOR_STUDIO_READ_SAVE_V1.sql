-- REVIEW-ONLY SQL SOURCE. Do NOT execute in production directly.
-- Generate a numbered titus_ migration with the Supabase CLI in the canonical
-- noel-core-db checkout after source review, custody check and isolated tests.
-- No data/identity grants, Marlene account, class release, or permissions are seeded.
--
-- Truth custody: existing titus course/formation tables. The new records below
-- express a missing real authority (program builder delegation) and edit HISTORY.
-- They are not a second curriculum or a copy of draft sections.
create table if not exists titus.program_author_grants (
  program_author_grant_id uuid primary key default gen_random_uuid(),
  program_id uuid not null references titus.programs(program_id) on delete cascade,
  person_entity_id uuid not null references reality.entities(id),
  grant_state text not null check (grant_state in ('active','revoked')),
  grant_basis jsonb not null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  check ((grant_state='active' and revoked_at is null)
      or (grant_state='revoked' and revoked_at is not null))
);
create unique index if not exists program_author_grants_active_unique
on titus.program_author_grants(program_id,person_entity_id)
where grant_state='active' and revoked_at is null;
alter table titus.program_author_grants enable row level security;
revoke all on titus.program_author_grants from public, anon, authenticated;
grant select,insert,update on titus.program_author_grants to service_role;

create table if not exists titus.formation_section_edit_events (
  formation_section_edit_event_id uuid primary key default gen_random_uuid(),
  section_id uuid not null references titus.formation_unit_sections(formation_unit_section_id),
  actor_person_entity_id uuid not null references reality.entities(id),
  old_heading text not null,
  old_body text not null,
  new_heading text not null,
  new_body text not null,
  from_updated_at timestamptz not null,
  to_updated_at timestamptz not null,
  edited_at timestamptz not null default now()
);
create index if not exists formation_section_edit_events_section_time_idx
on titus.formation_section_edit_events(section_id,edited_at desc);
alter table titus.formation_section_edit_events enable row level security;
revoke all on titus.formation_section_edit_events from public, anon, authenticated;
grant select,insert on titus.formation_section_edit_events to service_role;

-- Authorization helper is private to the titus schema, not exposed to Data API.
create or replace function titus.is_program_author_self_v1(p_program_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog
as $$
  select auth.uid() is not null
    and exists (
      select 1 from titus.program_author_grants g
      where g.program_id=p_program_id
        and g.person_entity_id=titus.current_authenticated_person_entity_id_v1()
        and g.grant_state='active' and g.revoked_at is null
    );
$$;
revoke all on function titus.is_program_author_self_v1(uuid)
  from public, anon, authenticated;
grant execute on function titus.is_program_author_self_v1(uuid) to service_role;

create or replace function public.titus_builder_studio_self_api_v1(
  p_program_slug text,
  p_slot_key text
) returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog
as $$
declare
  v_program titus.programs%rowtype;
  v_slot titus.course_slots%rowtype;
  v_unit titus.formation_units%rowtype;
  v_slots jsonb := '[]'::jsonb;
  v_sections jsonb := '[]'::jsonb;
  v_inputs jsonb := '[]'::jsonb;
  v_questions jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or
     titus.current_authenticated_person_entity_id_v1() is null
  then
    return jsonb_build_object('state','unauthorized');
  end if;
  select p.* into v_program
  from titus.programs p where p.program_slug=p_program_slug;
  if v_program.program_id is null or
     not titus.is_program_author_self_v1(v_program.program_id) then
    return jsonb_build_object('state','not_found_or_unauthorized');
  end if;

  select s.* into v_slot
  from titus.course_slots s
  join titus.program_course_placements cp on cp.course_slug=s.course_slug
  join titus.curriculum_versions cv on cv.curriculum_version_id=cp.curriculum_version_id
  where cv.program_id=v_program.program_id and cv.is_current
    and s.slot_key=p_slot_key
  order by cp.sort_order,s.sort_order limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'slotKey', ss.slot_key,
    'number',ss.slot_number,
    'title',ss.slot_title,
    'researchStatus',ss.research_status,
    'slotStatus',ss.slot_status,
    'hasPacket',ss.lesson_slug is not null
  ) order by cp.module_number,ss.slot_number), '[]'::jsonb) into v_slots
  from titus.course_slots ss
  join titus.program_course_placements cp on cp.course_slug=ss.course_slug
  join titus.curriculum_versions cv on cv.curriculum_version_id=cp.curriculum_version_id
  where cv.program_id=v_program.program_id and cv.is_current
    and cp.module_number=1;

  if v_slot.slot_id is null then
    return jsonb_build_object('state','no_slot','slots',v_slots);
  end if;

  if v_slot.lesson_slug is not null then
    select u.* into v_unit from titus.formation_units u
    where u.program_id=v_program.program_id and u.lesson_slug=v_slot.lesson_slug
    order by u.version desc,u.created_at desc limit 1;
  end if;

  if v_unit.formation_unit_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sectionId',s.formation_unit_section_id,
      'sectionKey',s.section_key,'sectionKind',s.section_kind,
      'heading',s.heading,'body',s.body,'status',s.section_status,
      'sortOrder',s.sort_order,'updatedAt',s.updated_at::text
    ) order by s.sort_order,s.section_key),'[]'::jsonb)
    into v_sections
    from titus.formation_unit_sections s
    where s.formation_unit_id=v_unit.formation_unit_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'inputId',i.formation_unit_input_id, 'inputKind',i.input_kind,
      'reviewStatus',i.review_status,'inputRole',i.input_role,
      'relationNote',i.relation_note,
      'historicalTitle',su.unit_title,
      'historicalText',su.content_text,
      'historicalSummary',su.summary,
      'sourceTitle',sr.title,'canonClaim',c.claim_text,
      'canonClaimStatus',c.status
    ) order by i.sort_order,i.formation_unit_input_id),'[]'::jsonb)
    into v_inputs
    from titus.formation_unit_inputs i
    left join titus.teacher_source_units su on su.source_unit_id=i.source_unit_id
    left join titus.teacher_source_refs sr on sr.teacher_source_ref_id=su.teacher_source_ref_id
    left join titus.canon_claims c on c.canon_claim_id=i.canon_claim_id
    where i.formation_unit_id=v_unit.formation_unit_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'questionId',q.formation_question_id,'kind',q.question_kind,
      'question',q.question_text,'status',q.status
    ) order by q.sort_order),'[]'::jsonb)
    into v_questions from titus.formation_questions q
    where q.formation_unit_id=v_unit.formation_unit_id;
  end if;

  return jsonb_build_object(
    'state','ready',
    'programTitle',v_program.title,
    'courseSlug',v_slot.course_slug,
    'session',jsonb_build_object(
      'slotKey',v_slot.slot_key,'title',v_slot.slot_title,
      'slotNumber',v_slot.slot_number,'slotStatus',v_slot.slot_status,
      'researchStatus',v_slot.research_status,
      'researchPrompt',v_slot.noel_deep_dive_prompt
    ),
    'slots',v_slots,
    'unit',case when v_unit.formation_unit_id is null then null else
      jsonb_build_object('formationUnitId',v_unit.formation_unit_id,
      'unitKey',v_unit.unit_key,'title',v_unit.title,
      'governingQuestion',v_unit.governing_question,
      'learnerGoal',v_unit.learner_goal,
      'formationState',v_unit.formation_state,'reviewState',v_unit.review_state)
    end,
    'sections',v_sections,'inputs',v_inputs,'questions',v_questions
  );
end;
$$;
revoke all on function public.titus_builder_studio_self_api_v1(text,text)
  from public, anon, authenticated;
grant execute on function public.titus_builder_studio_self_api_v1(text,text)
  to authenticated,service_role;

create or replace function public.titus_builder_save_section_self_api_v1(
  p_section_id uuid,
  p_expected_updated_at timestamptz,
  p_heading text,
  p_body text
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog
as $$
declare
  v_person uuid;
  v_old titus.formation_unit_sections%rowtype;
  v_new titus.formation_unit_sections%rowtype;
begin
  v_person := titus.current_authenticated_person_entity_id_v1();
  if auth.uid() is null or v_person is null then
    return jsonb_build_object('state','unauthorized');
  end if;
  if p_heading is null or length(btrim(p_heading))=0 or length(p_heading)>180
     or p_body is null or length(btrim(p_body))=0 or length(p_body)>40000
     or p_expected_updated_at is null then
    return jsonb_build_object('state','invalid_input');
  end if;

  -- Exact section and active program-level builder authorization.
  -- FOR UPDATE serializes concurrent saves before the version comparison.
  select s.* into v_old
  from titus.formation_unit_sections s
  join titus.formation_units u on u.formation_unit_id=s.formation_unit_id
  join titus.program_author_grants g on g.program_id=u.program_id
  where s.formation_unit_section_id=p_section_id
    and g.person_entity_id=v_person
    and g.grant_state='active' and g.revoked_at is null
    and s.section_status='draft'
    and u.formation_state='drafted'
  for update of s;

  if v_old.formation_unit_section_id is null then
    return jsonb_build_object('state','not_found_or_unauthorized');
  end if;
  if v_old.updated_at is distinct from p_expected_updated_at then
    return jsonb_build_object('state','conflict','updatedAt',v_old.updated_at::text);
  end if;
  if v_old.heading=p_heading and v_old.body=p_body then
    return jsonb_build_object('state','unchanged','updatedAt',v_old.updated_at::text);
  end if;

  update titus.formation_unit_sections s
  set heading=p_heading,body=p_body,updated_at=clock_timestamp()
  where s.formation_unit_section_id=p_section_id
  returning s.* into v_new;

  insert into titus.formation_section_edit_events(
    section_id,actor_person_entity_id,
    old_heading,old_body,new_heading,new_body,
    from_updated_at,to_updated_at
  ) values (
    p_section_id,v_person,
    v_old.heading,v_old.body,v_new.heading,v_new.body,
    v_old.updated_at,v_new.updated_at
  );

  return jsonb_build_object(
    'state','saved','sectionId',p_section_id,
    'updatedAt',v_new.updated_at::text
  );
end;
$$;
revoke all on function public.titus_builder_save_section_self_api_v1(
  uuid,timestamptz,text,text) from public, anon, authenticated;
grant execute on function public.titus_builder_save_section_self_api_v1(
  uuid,timestamptz,text,text) to authenticated,service_role;

-- In production, perform approved author grant bootstrap separately through
-- governed Atlas/Noel administration after verified Person establishment.
-- This proposal purposely contains NO INSERT into program_author_grants.
-- Do not release this source without negative authorization tests and
-- a canonical timestamped titus_ migration with custody checks.
