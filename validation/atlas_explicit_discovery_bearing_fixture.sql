\set ON_ERROR_STOP on
create schema auth;
create schema atlas;
create role authenticated;
create role anon;
create function auth.uid() returns uuid language sql stable as $fn$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$fn$;
create table atlas.principals(id uuid primary key,user_id uuid unique,status text);
create table atlas.reality_discovery_sessions(
 id uuid primary key,principal_id uuid,owner_user_id uuid,session_kind text,state text,
 metadata jsonb default '{}'::jsonb,
 last_opened_at timestamptz default now(),started_at timestamptz default now(),
 updated_at timestamptz default now());
create table atlas.reality_discovery_questions(
 question_key text primary key,metadata jsonb,prompt text);
create table atlas.reality_discovery_encounter_admission(
 question_key text primary key,first_day_disposition text,admission_class text,reason_text text);
create table atlas.reality_discovery_answer_events(
 principal_id uuid,owner_user_id uuid,question_key text,answer_value jsonb);
insert into atlas.principals values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','active'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','active');
insert into atlas.reality_discovery_sessions(id,principal_id,owner_user_id,session_kind,state)
values
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','first_day','active'),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','first_day','active');
insert into atlas.reality_discovery_questions(question_key,metadata,prompt) values
('business.one','{"orientationWorldDomains":["business"],"encounterCluster":"work","encounterClusterLabel":"Work"}','Which business?'),
('business.two','{"orientationWorldDomains":["business"],"encounterCluster":"work","encounterClusterLabel":"Work"}','How many?'),
('job.one','{"orientationWorldDomains":["job"],"encounterCluster":"job","encounterClusterLabel":"Job"}','What kind of job?'),
('property.one','{"orientationWorldDomains":["property"],"encounterCluster":"property"}','What property?');
insert into atlas.reality_discovery_encounter_admission values
('business.one','admit','first_day','Worth asking'),
('business.two','admit','first_day','Worth asking'),
('job.one','defer','manual','Requires explicit attention'),
('property.one','defer','manual','Requires explicit attention');
create function atlas.reality_discovery_orientation_profile_self_api_v1()
 returns jsonb language sql stable as $fn$
 select '{"captured":true,"worldDomains":["business"]}'::jsonb
$fn$;
create function atlas.reality_discovery_ranked_questions_self_api_v1()
 returns jsonb language sql stable as $fn$
 select jsonb_build_object(
  'context',jsonb_build_object('principalId',(select id from atlas.principals
     where user_id=auth.uid() and status='active' limit 1),
   'orientation',jsonb_build_object('captured',true),
   'signals',jsonb_build_object('household.people_shape','adult')),
  'items',coalesce((select jsonb_agg(jsonb_build_object(
    'questionKey',q.question_key,'prompt',q.prompt,
    'answerKind','single_choice',
    'options',jsonb_build_array(jsonb_build_object('key','yes','label','Yes')))
    order by case q.question_key when 'business.one' then 1 when 'job.one' then 2
      when 'business.two' then 3 else 4 end)
   from atlas.reality_discovery_questions q
   where not exists(select 1 from atlas.reality_discovery_answer_events a
     where a.owner_user_id=auth.uid() and a.question_key=q.question_key)
   ),'[]'::jsonb))
$fn$;
create function atlas.reality_discovery_apply_option_eligibility_v1(p_question jsonb,p_context jsonb)
 returns jsonb language sql stable as $fn$ select p_question $fn$;
create function atlas.reality_discovery_question_set_self_api_v1(p_limit integer default 4)
 returns jsonb language sql stable as $fn$
 select atlas.reality_discovery_question_set_for_encounter_self_api_v1(
  coalesce((select session_kind from atlas.reality_discovery_sessions
   where owner_user_id=auth.uid() and state='active' order by last_opened_at desc limit 1),
   'first_day'),p_limit)
$fn$;
grant usage on schema atlas to authenticated;
grant select on atlas.principals,atlas.reality_discovery_sessions,atlas.reality_discovery_questions,
 atlas.reality_discovery_encounter_admission,atlas.reality_discovery_answer_events to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function atlas.reality_discovery_question_set_self_api_v1(integer) to authenticated;
