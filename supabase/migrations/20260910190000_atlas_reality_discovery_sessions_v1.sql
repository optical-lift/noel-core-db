begin;

-- Reality Discovery session orchestration.
-- Session state governs whether an adaptive questioning encounter is open/paused/quiet.
-- It is not a universal onboarding-completion flag and says nothing about world completeness.

create table if not exists atlas.reality_discovery_sessions (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  session_kind text not null check (session_kind in ('first_day','manual','micro')),
  state text not null check (state in ('active','paused','quiet','closed')),
  started_at timestamptz not null default now(),
  last_opened_at timestamptz not null default now(),
  paused_at timestamptz,
  quiet_at timestamptz,
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists reality_discovery_first_day_session_uidx
  on atlas.reality_discovery_sessions(principal_id,session_kind)
  where session_kind='first_day';

create index if not exists reality_discovery_sessions_owner_state_idx
  on atlas.reality_discovery_sessions(owner_user_id,state,updated_at desc);

create table if not exists atlas.reality_discovery_session_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references atlas.reality_discovery_sessions(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  event_kind text not null check (event_kind in ('started','resumed','paused','quiet','closed')),
  source_action_id text not null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(owner_user_id,source_action_id)
);

create index if not exists reality_discovery_session_events_session_idx
  on atlas.reality_discovery_session_events(session_id,occurred_at,id);

alter table atlas.reality_discovery_sessions enable row level security;
alter table atlas.reality_discovery_session_events enable row level security;
revoke all on atlas.reality_discovery_sessions from public,anon,authenticated;
revoke all on atlas.reality_discovery_session_events from public,anon,authenticated;

create or replace function atlas.begin_reality_discovery_self_api_v1(
  p_session_kind text default 'first_day',
  p_source_action_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_kind text;
  v_action text;
  v_session atlas.reality_discovery_sessions%rowtype;
  v_event_kind text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select id into v_principal_id from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_kind:=coalesce(nullif(trim(p_session_kind),''),'first_day');
  if v_kind not in ('first_day','manual','micro') then raise exception 'Unsupported discovery session kind.' using errcode='22023'; end if;
  v_action:=coalesce(nullif(trim(p_source_action_id),''),gen_random_uuid()::text);

  if v_kind='first_day' then
    select * into v_session
    from atlas.reality_discovery_sessions
    where principal_id=v_principal_id and session_kind='first_day'
    for update;

    if v_session.id is null then
      insert into atlas.reality_discovery_sessions(principal_id,owner_user_id,session_kind,state,metadata)
      values(v_principal_id,v_user_id,'first_day','active',jsonb_build_object('universalCompletionFlag',false))
      returning * into v_session;
      v_event_kind:='started';
    else
      if v_session.state in ('paused','quiet') then
        update atlas.reality_discovery_sessions
        set state='active',last_opened_at=now(),paused_at=null,quiet_at=null,updated_at=now()
        where id=v_session.id returning * into v_session;
        v_event_kind:='resumed';
      elsif v_session.state='closed' then
        return jsonb_build_object(
          'ok',true,'contractVersion','reality_discovery_session_v1',
          'session',jsonb_build_object('id',v_session.id,'sessionKind',v_session.session_kind,'state',v_session.state),
          'next',null,'message','First-day discovery is closed. Start a manual discovery session to keep mapping.'
        );
      else
        update atlas.reality_discovery_sessions set last_opened_at=now(),updated_at=now()
        where id=v_session.id returning * into v_session;
        v_event_kind:=null;
      end if;
    end if;
  else
    insert into atlas.reality_discovery_sessions(principal_id,owner_user_id,session_kind,state,metadata)
    values(v_principal_id,v_user_id,v_kind,'active','{}'::jsonb)
    returning * into v_session;
    v_event_kind:='started';
  end if;

  if v_event_kind is not null then
    insert into atlas.reality_discovery_session_events(session_id,principal_id,owner_user_id,event_kind,source_action_id,metadata)
    values(v_session.id,v_principal_id,v_user_id,v_event_kind,v_action,jsonb_build_object('sessionKind',v_kind))
    on conflict(owner_user_id,source_action_id) do nothing;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_session_v1',
    'session',jsonb_build_object(
      'id',v_session.id,'sessionKind',v_session.session_kind,'state',v_session.state,
      'startedAt',v_session.started_at,'lastOpenedAt',v_session.last_opened_at
    ),
    'next',atlas.reality_discovery_next_question_self_api_v1(),
    'truthBoundary',jsonb_build_object(
      'sessionStateIsEncounterState',true,
      'sessionStateDoesNotMeasureLifeCompleteness',true,
      'pauseDoesNotAnswerQuestions',true
    )
  );
end;
$function$;

create or replace function atlas.pause_reality_discovery_self_api_v1(
  p_session_id uuid,
  p_source_action_id text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_session atlas.reality_discovery_sessions%rowtype;
  v_existing uuid;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_session_id is null or nullif(trim(p_source_action_id),'') is null then
    raise exception 'sessionId and sourceActionId required.' using errcode='22023';
  end if;

  select id into v_existing from atlas.reality_discovery_session_events
  where owner_user_id=v_user_id and source_action_id=p_source_action_id;
  if v_existing is not null then
    select * into v_session from atlas.reality_discovery_sessions where id=p_session_id and owner_user_id=v_user_id;
    return jsonb_build_object('ok',true,'idempotentReplay',true,'session',jsonb_build_object('id',v_session.id,'state',v_session.state));
  end if;

  select * into v_session from atlas.reality_discovery_sessions
  where id=p_session_id and owner_user_id=v_user_id for update;
  if v_session.id is null then raise exception 'Discovery session not found.' using errcode='22023'; end if;

  update atlas.reality_discovery_sessions
  set state='paused',paused_at=now(),updated_at=now()
  where id=v_session.id returning * into v_session;

  insert into atlas.reality_discovery_session_events(session_id,principal_id,owner_user_id,event_kind,source_action_id)
  values(v_session.id,v_session.principal_id,v_user_id,'paused',p_source_action_id);

  return jsonb_build_object(
    'ok',true,'contractVersion','reality_discovery_session_v1','idempotentReplay',false,
    'session',jsonb_build_object('id',v_session.id,'sessionKind',v_session.session_kind,'state',v_session.state,'pausedAt',v_session.paused_at)
  );
end;
$function$;

create or replace function atlas.reality_discovery_first_day_status_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_session atlas.reality_discovery_sessions%rowtype;
  v_answer_count integer:=0;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select id into v_principal_id from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_session from atlas.reality_discovery_sessions
  where principal_id=v_principal_id and session_kind='first_day';
  select count(*)::integer into v_answer_count from atlas.reality_discovery_answer_events where principal_id=v_principal_id;

  return jsonb_build_object(
    'ok',true,'contractVersion','reality_discovery_first_day_status_self_api_v1',
    'hasStarted',v_session.id is not null,
    'session',case when v_session.id is null then null else jsonb_build_object(
      'id',v_session.id,'state',v_session.state,'startedAt',v_session.started_at,
      'lastOpenedAt',v_session.last_opened_at,'pausedAt',v_session.paused_at,'quietAt',v_session.quiet_at,'closedAt',v_session.closed_at
    ) end,
    'answerCount',v_answer_count,
    'shouldAutoOpen',v_session.id is null,
    'truthBoundary',jsonb_build_object(
      'shouldAutoOpenIsEncounterRouting',true,
      'pausedIsNotComplete',true,
      'answerCountIsNotCompletionScore',true
    )
  );
end;
$function$;

revoke all on function atlas.begin_reality_discovery_self_api_v1(text,text) from public,anon;
revoke all on function atlas.pause_reality_discovery_self_api_v1(uuid,text) from public,anon;
revoke all on function atlas.reality_discovery_first_day_status_self_api_v1() from public,anon;
grant execute on function atlas.begin_reality_discovery_self_api_v1(text,text) to authenticated,service_role;
grant execute on function atlas.pause_reality_discovery_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function atlas.reality_discovery_first_day_status_self_api_v1() to authenticated,service_role;

create or replace function public.begin_reality_discovery_self_api_v1(p_session_kind text default 'first_day',p_source_action_id text default null)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.begin_reality_discovery_self_api_v1(p_session_kind,p_source_action_id); $function$;
create or replace function public.pause_reality_discovery_self_api_v1(p_session_id uuid,p_source_action_id text)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.pause_reality_discovery_self_api_v1(p_session_id,p_source_action_id); $function$;
create or replace function public.reality_discovery_first_day_status_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.reality_discovery_first_day_status_self_api_v1(); $function$;

revoke all on function public.begin_reality_discovery_self_api_v1(text,text) from public,anon;
revoke all on function public.pause_reality_discovery_self_api_v1(uuid,text) from public,anon;
revoke all on function public.reality_discovery_first_day_status_self_api_v1() from public,anon;
grant execute on function public.begin_reality_discovery_self_api_v1(text,text) to authenticated,service_role;
grant execute on function public.pause_reality_discovery_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function public.reality_discovery_first_day_status_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
('atlas.begin_reality_discovery_self_api_v1(p_session_kind text, p_source_action_id text)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Start/resume an adaptive Reality Discovery encounter without creating an onboarding-completion gate.'),now()),
('atlas.pause_reality_discovery_self_api_v1(p_session_id uuid, p_source_action_id text)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Persist the Principal choice to stop Reality Discovery for now without answering remaining questions.'),now()),
('atlas.reality_discovery_first_day_status_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Route the first-day Reality Discovery encounter from durable session state; answer count is not a completion score.'),now())
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();

commit;
