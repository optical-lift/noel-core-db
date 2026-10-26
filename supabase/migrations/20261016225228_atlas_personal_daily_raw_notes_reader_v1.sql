-- Native Personal Daily Log read side, using EXISTING captured testimony source.
-- No parallel daily-notes table, no task inference, no schedule mutation.
begin;

create or replace function atlas.personal_daily_raw_notes_self_api_v1(p_date date)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog','atlas','personal','auth'
as $fn$
declare
  v_person uuid;
  v_atlas uuid;
  v_total bigint;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Personal Atlas required.' using errcode='42501';
  end if;
  if p_date is null then
    raise exception 'Daily notebook date required.' using errcode='22023';
  end if;
  v_person:=atlas.current_person_id_v1();
  if v_person is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;
  select a.id into v_atlas
  from personal.atlases a
  where a.person_entity_id=v_person and a.atlas_state='active' and a.native
  order by a.id limit 1;
  if v_atlas is null then
    raise exception 'Active native Personal Atlas required.' using errcode='42501';
  end if;
  select count(*) into v_total from atlas.personal_reality_captures c
  where c.owner_user_id=auth.uid()
    and c.source_surface='personal_notebook_daily_log'
    and c.capture_context->>'notebookDate'=p_date::text
    and c.capture_context->>'entryKind'='note';
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',r.id,
      'text',r.testimony,
      'capturedAt',r.captured_at,
      'captureState',r.capture_state,
      'evidenceId',r.evidence_id,
      'sourceKind','first_party_testimony',
      'subjectUnresolved',true,
      'dateMeaning','notebook_page_context_not_observed_at'
    ) order by r.captured_at,r.id
  ),'[]'::jsonb) into v_items
  from (
    select c.id,c.testimony,c.captured_at,c.capture_state,c.evidence_id
    from atlas.personal_reality_captures c
    where c.owner_user_id=auth.uid()
      and c.source_surface='personal_notebook_daily_log'
      and c.capture_context->>'notebookDate'=p_date::text
      and c.capture_context->>'entryKind'='note'
    order by c.captured_at desc,c.id desc
    limit 120
  ) r;
  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_daily_raw_notes_self_v1',
    'date',p_date::text,
    'personEntityId',v_person,
    'items',v_items,
    'total',v_total,
    'truncated',(v_total>jsonb_array_length(v_items)),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'onlyOriginalOwnerTestimony',true,
      'captureDoesNotCreateTask',true,
      'diaryDateIsNavigationNotWitnessedOccurrence',true,
      'doesNotScheduleOrAdmitClockWork',true,
      'noAutomaticCollectionRelationship',true
    )
  );
end;
$fn$;

create or replace function public.personal_daily_raw_notes_self_api_v1(p_date date)
returns jsonb
language sql stable security definer
set search_path to 'pg_catalog','atlas','personal','auth'
as $fn$
  select atlas.personal_daily_raw_notes_self_api_v1(p_date);
$fn$;

revoke all on function atlas.personal_daily_raw_notes_self_api_v1(date) from public,anon,authenticated;
revoke all on function public.personal_daily_raw_notes_self_api_v1(date) from public,anon,authenticated;
grant execute on function public.personal_daily_raw_notes_self_api_v1(date) to authenticated;

commit;
