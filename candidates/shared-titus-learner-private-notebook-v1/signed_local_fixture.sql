-- Disposable Supabase Auth+REST fixture: only synthetic academic source, never live.
-- Real local auth.users, auth.sessions, auth.uid and auth.jwt are NOT overridden.
CREATE SCHEMA IF NOT EXISTS atlas;
CREATE SCHEMA IF NOT EXISTS reality;
CREATE SCHEMA IF NOT EXISTS titus;

CREATE TABLE reality.entities(
 id uuid PRIMARY KEY,entity_kind text,identity_state text
);
CREATE TABLE reality.auth_person_bindings(
 id uuid PRIMARY KEY,auth_user_id uuid,person_entity_id uuid REFERENCES reality.entities(id),
 binding_state text,bound_at timestamptz DEFAULT now(),retired_at timestamptz
);
CREATE TABLE atlas.people(id uuid PRIMARY KEY,status text);
CREATE TABLE atlas.person_auth_credentials(
 id uuid PRIMARY KEY,person_id uuid REFERENCES atlas.people(id),credential_kind text,
 auth_user_id uuid,status text,retired_at timestamptz
);
CREATE TABLE atlas.teaching_courses(
 id uuid PRIMARY KEY,ledger_id uuid,capability_activation_id uuid,status text,retired_at timestamptz
);
CREATE TABLE atlas.teaching_course_versions(
 id uuid PRIMARY KEY,course_id uuid REFERENCES atlas.teaching_courses(id),published_at timestamptz
);
CREATE TABLE atlas.teaching_course_offerings(
 id uuid PRIMARY KEY,ledger_id uuid,course_id uuid REFERENCES atlas.teaching_courses(id),
 course_version_id uuid REFERENCES atlas.teaching_course_versions(id),
 state text,opened_at timestamptz,closed_at timestamptz,retired_at timestamptz
);
CREATE TABLE atlas.teaching_enrollments(
 id uuid PRIMARY KEY,ledger_id uuid,
 offering_id uuid REFERENCES atlas.teaching_course_offerings(id),
 person_id uuid REFERENCES atlas.people(id),state text,withdrawn_at timestamptz
);
CREATE TABLE atlas.synthetic_capability(ledger_id uuid,activation_id uuid,state text);
CREATE FUNCTION atlas.teaching_activation_active_v1(l uuid,a uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $f$
 SELECT EXISTS (SELECT 1 FROM atlas.synthetic_capability x
 WHERE x.ledger_id=l AND x.activation_id=a AND x.state='active');
$f$;

-- Exact *structural* copy of live Titus resolver read via pg_get_functiondef,
-- not a mock Auth user or a function accepting arbitrary Person input.
CREATE OR REPLACE FUNCTION titus.current_authenticated_person_entity_id_v1()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'auth', 'reality', 'titus'
AS $function$
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
$function$;
