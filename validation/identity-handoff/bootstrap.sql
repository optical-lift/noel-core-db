-- Disposable PostgreSQL 17 contract fixture.
-- Only create the minimal surrounding Atlas/Reality/Titus types necessary
-- to compile and execute the candidate handoff migration. No live Supabase data.
create schema auth;
create schema reality;
create schema titus;
create schema extensions;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
grant usage on schema public,auth,reality,titus to anon, authenticated, service_role;
create extension pgcrypto with schema extensions;

create table auth.users (
  id uuid primary key,
  deleted_at timestamptz,
  banned_until timestamptz
);
create table auth.sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  not_after timestamptz
);
create table reality.entities (
  id uuid primary key,
  entity_kind text not null,
  identity_state text not null
);
create table reality.auth_person_bindings (
  auth_user_id uuid not null references auth.users(id),
  person_entity_id uuid not null references reality.entities(id),
  binding_state text not null,
  retired_at timestamptz
);
create table titus.teachers (
  teacher_id uuid primary key,
  teacher_key text not null,
  status text not null
);
create table titus.teacher_person_bindings (
  teacher_id uuid not null references titus.teachers(teacher_id),
  person_entity_id uuid not null references reality.entities(id),
  binding_state text not null,
  retired_at timestamptz
);
create table titus.formation_units (
  formation_unit_id uuid primary key,
  teacher_id uuid not null references titus.teachers(teacher_id),
  formation_state text not null,
  review_state text not null
);

-- Minimal Supabase auth compatibility surface used by the new candidate.
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.role',true),'') $$;
create function auth.jwt() returns jsonb
language sql stable
as $$ select nullif(current_setting('request.jwt.claims',true),'')::jsonb $$;

-- This stub mirrors the relevant pre-existing real resolver boundary; the
-- candidate migration does NOT recreate or replace the real resolver.
create function titus.current_authenticated_person_entity_id_v1()
returns uuid language plpgsql stable security definer
set search_path=pg_catalog,auth,reality,titus
as $$
declare
  v_person uuid;
  v_session uuid;
begin
  if auth.uid() is null then return null; end if;
  begin
    v_session := nullif(auth.jwt()->>'session_id','')::uuid;
  exception when others then
    return null;
  end;
  if v_session is null then return null; end if;
  select b.person_entity_id into v_person
  from reality.auth_person_bindings b
  join reality.entities e on e.id=b.person_entity_id
  join auth.sessions s on s.user_id=b.auth_user_id
    and s.id=v_session and (s.not_after is null or s.not_after>now())
  join auth.users u on u.id=s.user_id
    and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())
  where b.auth_user_id=auth.uid()
    and b.binding_state='active' and b.retired_at is null
    and e.entity_kind='person' and e.identity_state='canonical'
  limit 1;
  return v_person;
end;
$$;
revoke all on function titus.current_authenticated_person_entity_id_v1() from public,anon,authenticated,service_role;

insert into auth.users(id) values('00000000-0000-4000-8000-000000000011');
insert into auth.sessions(id,user_id) values
('00000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000011');
insert into reality.entities(id,entity_kind,identity_state) values
('00000000-0000-4000-8000-000000000013','person','canonical');
insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state)
values('00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000013','active');
insert into titus.teachers(teacher_id,teacher_key,status)
values('00000000-0000-4000-8000-000000000014','marlene_mcmillan','active');
insert into titus.formation_units(formation_unit_id,teacher_id,formation_state,review_state)
values('00000000-0000-4000-8000-000000000015','00000000-0000-4000-8000-000000000014','drafted','current');
