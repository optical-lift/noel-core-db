
\set ON_ERROR_STOP on
create schema auth;
create schema atlas;
create role anon;
create role authenticated;
create table auth.users(id uuid primary key);
create table atlas.principals(id uuid primary key,user_id uuid unique,status text,active_household_id uuid);
create function auth.uid() returns uuid language sql stable as $fn$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$fn$;
create function atlas.personal_atlas_access_status_self_api_v1() returns jsonb
  language sql stable as $fn$
  select jsonb_build_object('eligible',auth.uid() is not null,'accessState','active')
$fn$;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002');
insert into atlas.principals(id,user_id,status) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','active'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','active');

-- Small, non-production schema reproduces referenced Index inputs.
create table atlas.reality_discovery_orientation_events(
 id uuid primary key default gen_random_uuid(),
 principal_id uuid,owner_user_id uuid,orientation_version integer,
 world_domains jsonb,occurred_at timestamptz default now()
);
create table atlas.reality_discovery_questions(
 question_key text primary key,metadata jsonb,prompt text,options jsonb
);
create table atlas.reality_discovery_answer_events(
 id uuid primary key default gen_random_uuid(),
 principal_id uuid,owner_user_id uuid,question_key text,answer_value jsonb,
 occurred_at timestamptz default now()
);
create table atlas.notebook_spread_instances(
 id uuid primary key default gen_random_uuid(),principal_id uuid,
 section_key text,opened_at timestamptz default now(),
 spread_key text,title text,scope_kind text,scope_id uuid,
 subject_domain text,subject_kind text,subject_id uuid,
 spread_state text,thread_key text,recipe_key text,purpose_key text,horizon_key text
);
-- Only the Section-root test needs this orientation reader; full production
-- Discovery logic is deliberately NOT simulated.
create function atlas.reality_discovery_orientation_profile_self_api_v1()
 returns jsonb language sql stable as $fn$
 select jsonb_build_object('worldDomains',
  coalesce((select e.world_domains from atlas.reality_discovery_orientation_events e
            where e.owner_user_id=auth.uid()
            order by e.occurred_at desc,e.id desc limit 1),'[]'::jsonb))
$fn$;
