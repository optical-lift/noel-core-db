-- Candidate only. Owned by noel-core-db; no production release here.
-- Person's source-preserving period reader. Neither the query nor the packet owns history.
begin;

create or replace function atlas.person_period_source_history_self_api_v1(
  p_start_date date, p_end_date date,
  p_timezone text default 'UTC',
  p_limit integer default 100,
  p_after_day date default null,
  p_after_recorded_at timestamptz default null,
  p_after_kind text default null,
  p_after_source_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path to ''
as $body$
declare
  v_user uuid := auth.uid();
  v_principal uuid;
  v_records jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_last jsonb;
begin
  if v_user is null then
    raise exception 'Signed-in Person required.' using errcode='42501';
  end if;
  if p_start_date is null or p_end_date is null
    or p_end_date<p_start_date or p_end_date-p_start_date>366 then
    raise exception 'A bounded inclusive history period is required.' using errcode='22023';
  end if;
  if p_limit is null or p_limit<1 or p_limit>200 then
    raise exception 'History limit must be 1 through 200.' using errcode='22023';
  end if;
  if p_timezone is null or not exists(
    select 1 from pg_catalog.pg_timezone_names where name=p_timezone
  ) then
    raise exception 'A named IANA timezone is required.' using errcode='22023';
  end if;
  if (p_after_day is null and (
     p_after_recorded_at is not null or p_after_kind is not null or p_after_source_id is not null))
     or (p_after_day is not null and (
     p_after_recorded_at is null or p_after_kind is null or p_after_source_id is null)) then
    raise exception 'History cursor must be complete.' using errcode='22023';
  end if;
  v_principal := atlas.require_active_task_principal_v1();
  with source_rows as (
    -- A page date is an authored notebook coordinate, never observation onset.
    select c.capture_context->>'notebookDate' as entry_day,
      c.captured_at as recorded_at,
      'personal_raw_observation'::text as source_kind,
      c.id as source_id,
      jsonb_strip_nulls(jsonb_build_object(
        'entryKind','first_party_observation',
        'source',jsonb_build_object('kind','personal_reality_capture',
          'id',c.id,'evidenceId',c.evidence_id),
        'text',c.testimony,
        'entryDay',c.capture_context->>'notebookDate',
        'recordedAt',c.captured_at,
        'occurredAt',e.observed_at,
        'occurredTimeBasis',e.provenance->>'sourceTimeBasis',
        'timeStanding',case when e.observed_at is null
          then 'page_context_only' else 'explicit_source_assertion' end,
        'evidenceStanding','first_party_testimony',
        'sourceState',c.capture_state,
        'subjectStanding','unresolved',
        'subjectLinks','[]'::jsonb
      )) as envelope
    from atlas.personal_reality_captures c
    join atlas.evidence_records e on e.id=c.evidence_id
      and e.scope_kind='person' and e.scope_id=v_user
    where c.owner_user_id=v_user and c.principal_id=v_principal
      and c.source_surface='personal_notebook_daily_log'
      and c.metadata->>'notebookEntryKind'='raw_note'
      and (c.capture_context->>'notebookDate') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      and c.capture_context->>'notebookDate'
        between p_start_date::text and p_end_date::text
    union all
    -- Task completion is a task-state receipt, not a verified physical outcome.
    select to_char(t.completed_at at time zone p_timezone,'YYYY-MM-DD') as entry_day,
      t.completed_at as recorded_at,
      'personal_task_state'::text as source_kind,
      t.id as source_id,
      jsonb_build_object(
        'entryKind','personal_task_marked_complete',
        'source',jsonb_build_object('kind','personal_task','id',t.id),
        'text',t.sentence,
        'entryDay',(t.completed_at at time zone p_timezone)::date,
        'recordedAt',t.completed_at,
        'occurredAt',null,
        'timeStanding','completion_recorded_at',
        'evidenceStanding','task_status_only',
        'sourceState',t.status,
        'subjectStanding','task_identity_only',
        'subjectLinks',jsonb_build_array(jsonb_build_object(
          'domain','personal_work','kind','task','id',t.id,
          'relation','state_of'))
      )
    from atlas.task_entries t
    where t.owner_user_id=v_user and t.principal_id=v_principal
      and t.status='done' and t.completed_at is not null
      and (t.completed_at at time zone p_timezone)::date
        between p_start_date and p_end_date
  ), after_cursor as (
    select *
    from source_rows s
    where p_after_day is null
      or (s.entry_day,s.recorded_at,s.source_kind,s.source_id)
       < (p_after_day::text,p_after_recorded_at,p_after_kind,p_after_source_id)
  ), bounded as (
    select * from after_cursor
    order by entry_day desc,recorded_at desc,source_kind desc,source_id desc
    limit p_limit+1
  ), numbered as (
    select b.*,row_number() over(
      order by b.entry_day desc,b.recorded_at desc,b.source_kind desc,b.source_id desc
    ) as rn from bounded b
  )
  select coalesce(jsonb_agg(
      n.envelope order by n.entry_day desc,n.recorded_at desc,n.source_kind desc,n.source_id desc
    ) filter(where n.rn<=p_limit),'[]'::jsonb),
    count(*)::integer,
    (jsonb_agg(jsonb_build_object(
      'day',n.entry_day,'recordedAt',n.recorded_at,
      'kind',n.source_kind,'sourceId',n.source_id
    ) order by n.entry_day desc,n.recorded_at desc,n.source_kind desc,n.source_id desc)
    filter(where n.rn=p_limit))->0
  into v_records,v_count,v_last
  from numbered n;
  return jsonb_build_object(
    'ok',true,'contractVersion','person_period_source_history_v1',
    'startDate',p_start_date,'endDate',p_end_date,
    'timezone',p_timezone,'items',v_records,
    'hasMore',v_count>p_limit,
    'nextCursor',case when v_count>p_limit then v_last else null end,
    'sourceCoverage',jsonb_build_object(
      'personalRawObservations','bounded',
      'personalTaskCompletionState','bounded',
      'institutionalWork','not_connected',
      'communications','not_connected',
      'externalProviders','not_connected',
      'crossDomainSubjectLinks','not_connected'
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,'oneSourceIdentityPerEntry',true,
      'noCopyOfSourceTruth',true,'privatePersonScopeOnly',true,
      'pageDateIsNotObservedAt',true,
      'taskCompletionIsNotPhysicalOutcomeProof',true,
      'noInferredSubjectLinks',true,'notACompleteActivityRecord',true
    )
  );
end
$body$;

create or replace function public.person_period_source_history_self_api_v1(
  p_start_date date, p_end_date date,
  p_timezone text default 'UTC', p_limit integer default 100,
  p_after_day date default null,
  p_after_recorded_at timestamptz default null,
  p_after_kind text default null,
  p_after_source_id uuid default null
) returns jsonb language sql stable security definer
set search_path to 'pg_catalog'
as $body$
  select atlas.person_period_source_history_self_api_v1(
    p_start_date,p_end_date,p_timezone,p_limit,
    p_after_day,p_after_recorded_at,p_after_kind,p_after_source_id);
$body$;

revoke all on function atlas.person_period_source_history_self_api_v1(
 date,date,text,integer,date,timestamptz,text,uuid)
 from public,anon,authenticated;
revoke all on function public.person_period_source_history_self_api_v1(
 date,date,text,integer,date,timestamptz,text,uuid)
 from public,anon;
grant execute on function public.person_period_source_history_self_api_v1(
 date,date,text,integer,date,timestamptz,text,uuid)
 to authenticated;
comment on function public.person_period_source_history_self_api_v1(
 date,date,text,integer,date,timestamptz,text,uuid)
 is 'Authenticated Person-only bounded evidence/Task-state history, no report or cross-Ledger sharing authority.';
commit;