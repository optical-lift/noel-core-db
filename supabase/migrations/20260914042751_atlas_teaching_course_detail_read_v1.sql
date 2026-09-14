-- Atlas Teaching Course Detail Read v1.
-- Adds the missing root-authorized read seam needed to resume Teaching setup safely
-- across reloads without exposing the academic tables directly to browser clients.

begin;

create or replace function atlas.teaching_course_admin_self_api_v1(p_course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_course atlas.teaching_courses%rowtype;
  v_activation atlas.capability_activations%rowtype;
  v_person uuid;
  v_principal uuid;
  v_authority uuid;
  v_versions jsonb;
  v_offerings jsonb;
begin
  if p_course_id is null then
    raise exception 'Course required.' using errcode='22023';
  end if;

  select * into v_course
  from atlas.teaching_courses
  where id=p_course_id;

  if v_course.id is null then
    raise exception 'Course not found.' using errcode='P0002';
  end if;

  -- Reuse the existing Gate B authority contract. Reading the Teaching-side
  -- projection does not manufacture a Professor role or Organization membership.
  select c.person_id,c.principal_id,c.principal_ledger_authority_id
    into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_course.ledger_id) c;

  select * into v_activation
  from atlas.capability_activations
  where id=v_course.capability_activation_id;

  if v_activation.id is null
     or v_activation.ledger_id<>v_course.ledger_id
     or v_activation.capability_key<>'teaching'
     or v_activation.capability_version<>1 then
    raise exception 'Course Teaching custody is malformed.' using errcode='23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'courseVersionId',v.id,
        'versionNo',v.version_no,
        'title',v.title,
        'summary',v.summary,
        'learningOutcomes',to_jsonb(v.learning_outcomes),
        'publishedAt',v.published_at
      ) order by v.version_no,v.id
    ),
    '[]'::jsonb
  ) into v_versions
  from atlas.teaching_course_versions v
  where v.course_id=v_course.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'offeringId',o.id,
        'courseVersionId',o.course_version_id,
        'offeringState',o.state,
        'deliveryMode',o.delivery_mode,
        'startsAt',o.starts_at,
        'endsAt',o.ends_at,
        'openedAt',o.opened_at,
        'closedAt',o.closed_at,
        'retiredAt',o.retired_at,
        'createdAt',o.created_at
      ) order by o.created_at,o.id
    ),
    '[]'::jsonb
  ) into v_offerings
  from atlas.teaching_course_offerings o
  where o.course_id=v_course.id and o.ledger_id=v_course.ledger_id;

  return jsonb_build_object(
    'contractVersion','teaching_course_admin_self_v1',
    'state','ready',
    'courseId',v_course.id,
    'ledgerId',v_course.ledger_id,
    'courseKey',v_course.course_key,
    'name',v_course.name,
    'courseState',v_course.status,
    'capabilityActivationId',v_course.capability_activation_id,
    'activationState',v_activation.state,
    'sourceSubjectLedgerId',v_activation.subject_ledger_id,
    'sourceSubjectKind',v_activation.subject_kind,
    'sourceSubjectId',v_activation.subject_id,
    'sourceSubjectKey',v_activation.subject_key,
    'sourceSubjectPath',v_activation.subject_path,
    'versions',v_versions,
    'offerings',v_offerings
  );
end;
$function$;

revoke all on function atlas.teaching_course_admin_self_api_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.teaching_course_admin_self_api_v1(uuid) to authenticated;

commit;
