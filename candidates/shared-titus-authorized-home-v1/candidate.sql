-- SOURCE CANDIDATE ONLY. Do not execute against shared production without
-- shared-lane custody review, production-schema clone, signed session tests,
-- and explicit principal authorization.
-- Current bounded slice: Atlas institutional Teaching LEARNER enrollment only.
-- Private Titus curriculum permissions, teacher/author rights and historical
-- source licenses are NOT inferred by this reader.
--
-- Repo: optical-lift/noel-core-db
-- Cross-domain owner: shared Atlas Person -> Atlas Teaching -> Titus view.
-- Proposed API contract: public.titus_authorized_home_self_api_v1().
--
-- In production clone, function creator must be canonical migration owner.
create or replace function public.titus_authorized_home_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  v_uid uuid := auth.uid();
  v_claims jsonb := auth.jwt();
  v_person uuid;
  v_subjects jsonb := '[]'::jsonb;
begin
  -- A role named authenticated alone is insufficient. Enforce the exact
  -- Titus OAuth client; a general Atlas token cannot read this membrane.
  if v_uid is null or
     coalesce(v_claims->>'client_id','') <>
       'd0b999e7-a2e2-4bb8-91ea-482fcd44b257'
  then
    return jsonb_build_object(
      'contractVersion','titus_authorized_home_self_v1',
      'state','identity_not_ready',
      'subjects','[]'::jsonb
    );
  end if;

  -- Existing Titus resolver verifies session_id against auth.sessions,
  -- current auth.users status, and exactly the canonical Person-binding path.
  v_person := titus.current_authenticated_person_entity_id_v1();
  if v_person is null then
    return jsonb_build_object(
      'contractVersion','titus_authorized_home_self_v1',
      'state','identity_not_ready',
      'subjects','[]'::jsonb
    );
  end if;

  -- Existing lawful enrollment is the ONLY currently supported source of
  -- discovery. An authored-by field, teacher display name, organization role,
  -- source-reference link or Constellation grant is never a course entitlement.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', q.course_id,
        'kind', 'institutional_course',
        'title', q.title,
        'subtitle', q.subtitle,
        'roles', jsonb_build_array('learner')
      ) order by q.title, q.course_id
    ),
    '[]'::jsonb
  )
  into v_subjects
  from (
    select distinct on (c.id)
      c.id as course_id,
      left(regexp_replace(v.title, '[[:cntrl:]]+', ' ', 'g'), 180) as title,
      left(regexp_replace(coalesce(v.summary,''), '[[:cntrl:]]+', ' ', 'g'), 280) as subtitle
    from atlas.teaching_enrollments e
    join atlas.teaching_course_offerings o
      on o.id=e.offering_id and o.ledger_id=e.ledger_id
    join atlas.teaching_courses c
      on c.id=o.course_id and c.ledger_id=o.ledger_id
    join atlas.teaching_course_versions v
      on v.id=o.course_version_id and v.course_id=c.id
    where e.person_id=v_person
      and e.state='active' and e.withdrawn_at is null
      and o.state='open' and o.opened_at is not null
      and c.status='active' and c.retired_at is null
      and v.published_at is not null
      and nullif(btrim(v.title),'') is not null
    order by c.id, v.published_at desc, v.id
  ) as q;

  return jsonb_build_object(
    'contractVersion','titus_authorized_home_self_v1',
    'state','ready',
    'personId',v_person,
    'subjects',v_subjects
  );
end;
$function$;

-- Explicit function ACL: no public/anonymous or general service-role read.
revoke all on function public.titus_authorized_home_self_api_v1()
  from public, anon, service_role;
grant execute on function public.titus_authorized_home_self_api_v1()
  to authenticated;
