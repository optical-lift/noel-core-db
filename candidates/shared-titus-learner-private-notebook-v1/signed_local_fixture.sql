-- Synthetic but source-shaped Atlas Teaching fixture for genuine LOCAL GoTrue Auth.
-- Derived from live Noel column/FK catalog and exact functions (read-only audit).
-- No production dump, records, Auth users, or migration is loaded.
CREATE SCHEMA IF NOT EXISTS atlas;
CREATE SCHEMA IF NOT EXISTS reality;
CREATE SCHEMA IF NOT EXISTS titus;
CREATE TABLE reality.entities(
 id uuid PRIMARY KEY,stable_key text NOT NULL UNIQUE,display_name text NOT NULL,
 entity_kind text NOT NULL,identity_state text NOT NULL DEFAULT 'canonical',
 CHECK(btrim(stable_key)<>''),CHECK(btrim(display_name)<>''),
 CHECK(identity_state IN('canonical','disputed','retired'))
);
CREATE TABLE reality.auth_person_bindings(
 id uuid PRIMARY KEY,auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 binding_state text NOT NULL DEFAULT 'active',bound_at timestamptz NOT NULL DEFAULT now(),
 retired_at timestamptz,
 CHECK(binding_state IN('active','retired'))
);
CREATE TABLE atlas.people(
 id uuid PRIMARY KEY,stable_key text UNIQUE,display_name text,
 status text NOT NULL DEFAULT 'active',CHECK(status IN ('active','retired'))
);
CREATE TABLE atlas.person_auth_credentials(
 id uuid PRIMARY KEY,person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 credential_kind text NOT NULL DEFAULT 'supabase_auth_user',
 auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
 status text NOT NULL DEFAULT 'active',bound_at timestamptz NOT NULL DEFAULT now(),
 provenance jsonb NOT NULL DEFAULT '{}'::jsonb,retired_at timestamptz,
 CHECK(credential_kind='supabase_auth_user'),
 CHECK(status IN('active','retired')),
 CHECK((status='active' AND retired_at IS NULL) OR (status='retired' AND retired_at IS NOT NULL))
);
CREATE TABLE atlas.principals(
 id uuid PRIMARY KEY,user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
 person_id uuid REFERENCES atlas.people(id) ON DELETE RESTRICT,
 stable_key text NOT NULL UNIQUE,name text NOT NULL,status text NOT NULL DEFAULT 'active',
 CHECK(status IN('active','inactive'))
);
CREATE TABLE atlas.ledgers(
 id uuid PRIMARY KEY,stable_key text NOT NULL UNIQUE,name text NOT NULL,
 ledger_kind text NOT NULL DEFAULT 'governed_reality',
 status text NOT NULL DEFAULT 'active',metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 CHECK(status IN('active','retired')),CHECK(btrim(name)<>'')
);
CREATE TABLE atlas.principal_ledger_authorities(
 id uuid PRIMARY KEY,principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
 authority_kind text NOT NULL CHECK(authority_kind='root_governing'),
 status text NOT NULL DEFAULT 'active',basis text NOT NULL,
 ended_at timestamptz,metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 CHECK((status='active' AND ended_at IS NULL) OR (status='ended' AND ended_at IS NOT NULL))
);
CREATE TABLE atlas.capability_definitions(
 capability_key text NOT NULL,capability_version integer NOT NULL,
 status text NOT NULL DEFAULT 'active',eligible_subject_kinds text[] NOT NULL,
 PRIMARY KEY(capability_key,capability_version)
);
CREATE TABLE atlas.capability_activations(
 id uuid PRIMARY KEY,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
 capability_key text NOT NULL,capability_version integer NOT NULL,
 subject_ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
 subject_kind text NOT NULL,subject_id uuid,subject_key text,subject_path text,
 state text NOT NULL DEFAULT 'draft',retired_at timestamptz,
 created_by_person_id uuid NOT NULL REFERENCES atlas.people(id),
 created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 FOREIGN KEY(capability_key,capability_version)
   REFERENCES atlas.capability_definitions(capability_key,capability_version),
 CHECK(state IN('draft','active','paused','retired')),
 CHECK((state<>'retired' AND retired_at IS NULL) OR (state='retired' AND retired_at IS NOT NULL))
);
CREATE TABLE atlas.teaching_courses(
 id uuid PRIMARY KEY,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
 capability_activation_id uuid NOT NULL REFERENCES atlas.capability_activations(id),
 course_key text NOT NULL,name text NOT NULL,
 status text NOT NULL DEFAULT 'active',retired_at timestamptz,
 created_by_person_id uuid NOT NULL REFERENCES atlas.people(id),
 created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 UNIQUE(ledger_id,id),CHECK(btrim(course_key)<>''),CHECK(btrim(name)<>''),
 CHECK((status='active' AND retired_at IS NULL) OR (status='retired' AND retired_at IS NOT NULL))
);
CREATE TABLE atlas.teaching_course_versions(
 id uuid PRIMARY KEY,course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id),
 version_no integer NOT NULL CHECK(version_no>0),title text NOT NULL CHECK(btrim(title)<>''),
 published_by_person_id uuid NOT NULL REFERENCES atlas.people(id),
 published_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 published_at timestamptz,UNIQUE(course_id,id),UNIQUE(course_id,version_no)
);
CREATE TABLE atlas.teaching_course_offerings(
 id uuid PRIMARY KEY,ledger_id uuid NOT NULL,
 course_id uuid NOT NULL,course_version_id uuid NOT NULL,
 state text NOT NULL DEFAULT 'draft',opened_at timestamptz,
 closed_at timestamptz,retired_at timestamptz,
 delivery_mode text NOT NULL CHECK(delivery_mode IN('self_paced','cohort','scheduled','live_hybrid')),
 created_by_person_id uuid NOT NULL REFERENCES atlas.people(id),
 created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 FOREIGN KEY(ledger_id,course_id) REFERENCES atlas.teaching_courses(ledger_id,id),
 FOREIGN KEY(course_id,course_version_id) REFERENCES atlas.teaching_course_versions(course_id,id),
 UNIQUE(ledger_id,id),
 CHECK ((state='draft' AND opened_at IS NULL AND closed_at IS NULL AND retired_at IS NULL)
 OR (state='open' AND opened_at IS NOT NULL AND closed_at IS NULL AND retired_at IS NULL)
 OR (state='closed' AND opened_at IS NOT NULL AND closed_at IS NOT NULL AND retired_at IS NULL)
 OR (state='retired' AND retired_at IS NOT NULL))
);
CREATE TABLE atlas.teaching_enrollments(
 id uuid PRIMARY KEY,ledger_id uuid NOT NULL,
 offering_id uuid NOT NULL,person_id uuid NOT NULL REFERENCES atlas.people(id),
 state text NOT NULL DEFAULT 'active',withdrawn_at timestamptz,
 enrolled_by_person_id uuid NOT NULL REFERENCES atlas.people(id),
 enrolled_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 FOREIGN KEY(ledger_id,offering_id) REFERENCES atlas.teaching_course_offerings(ledger_id,id),
 CHECK ((state='active' AND withdrawn_at IS NULL)
    OR (state='withdrawn' AND withdrawn_at IS NOT NULL))
);

-- Exact live Noel capability function bodies, retrieved read-only from the current catalog.
CREATE OR REPLACE FUNCTION atlas.capability_subject_valid_v1(p_capability_key text, p_capability_version integer, p_subject_ledger_id uuid, p_subject_kind text, p_subject_id uuid, p_subject_key text, p_subject_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_key text:=btrim(coalesce(p_capability_key,'')); v_kind text:=btrim(coalesce(p_subject_kind,''));
begin
  if not exists(
    select 1 from atlas.capability_definitions d
    where d.capability_key=v_key and d.capability_version=p_capability_version
      and d.status='active' and v_kind=any(d.eligible_subject_kinds)
  ) then return false; end if;

  if v_key='teaching' and p_capability_version=1 then
    if v_kind='ledger' then
      return p_subject_ledger_id is not null
        and p_subject_id=p_subject_ledger_id
        and p_subject_key is null
        and p_subject_path is null
        and exists(select 1 from atlas.ledgers l where l.id=p_subject_ledger_id and l.status='active');
    end if;

    if v_kind='organization_ledger_entry' then
      return p_subject_ledger_id is not null
        and p_subject_id is not null
        and p_subject_key is null
        and p_subject_path is null
        and exists(
          select 1
          from atlas.organization_ledger_entries e
          join atlas.ledgers l on l.id=e.ledger_id and l.status='active'
          where e.id=p_subject_id and e.ledger_id=p_subject_ledger_id
        );
    end if;
  end if;

  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.capability_subject_governed_v1(p_ledger_id uuid, p_capability_key text, p_capability_version integer, p_subject_ledger_id uuid, p_subject_kind text, p_subject_id uuid, p_subject_key text, p_subject_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_key text:=btrim(coalesce(p_capability_key,''));
begin
  if not atlas.capability_subject_valid_v1(
    v_key,p_capability_version,p_subject_ledger_id,p_subject_kind,p_subject_id,p_subject_key,p_subject_path
  ) then return false; end if;

  -- Teaching v1 acts only on truth governed by the same Ledger.
  -- Cross-Ledger source reality must be represented through the Ledger correlation contract first.
  if v_key='teaching' and p_capability_version=1 then
    return p_ledger_id is not null and p_subject_ledger_id=p_ledger_id;
  end if;

  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION atlas.capability_active_for_subject_v1(p_ledger_id uuid, p_capability_key text, p_capability_version integer, p_subject_ledger_id uuid, p_subject_kind text, p_subject_id uuid, p_subject_key text, p_subject_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
  select exists(
    select 1 from atlas.capability_activations a
    join atlas.capability_definitions d on d.capability_key=a.capability_key and d.capability_version=a.capability_version
    join atlas.ledgers gl on gl.id=a.ledger_id and gl.status='active'
    join atlas.ledgers sl on sl.id=a.subject_ledger_id and sl.status='active'
    where a.ledger_id=p_ledger_id and a.capability_key=btrim(coalesce(p_capability_key,'')) and a.capability_version=p_capability_version
      and a.subject_ledger_id=p_subject_ledger_id and a.subject_kind=btrim(coalesce(p_subject_kind,''))
      and a.subject_id is not distinct from p_subject_id and a.subject_key is not distinct from p_subject_key
      and a.subject_path is not distinct from p_subject_path and a.state='active' and d.status='active'
  );
$function$;

CREATE OR REPLACE FUNCTION atlas.teaching_activation_active_v1(p_ledger_id uuid, p_capability_activation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
  select exists(
    select 1
    from atlas.capability_activations a
    join atlas.capability_definitions d
      on d.capability_key=a.capability_key and d.capability_version=a.capability_version
    where a.id=p_capability_activation_id
      and a.ledger_id=p_ledger_id
      and a.capability_key='teaching'
      and a.capability_version=1
      and a.state='active'
      and d.status='active'
      and atlas.capability_subject_governed_v1(
        a.ledger_id,a.capability_key,a.capability_version,a.subject_ledger_id,
        a.subject_kind,a.subject_id,a.subject_key,a.subject_path
      )
      and atlas.capability_active_for_subject_v1(
        a.ledger_id,a.capability_key,a.capability_version,a.subject_ledger_id,
        a.subject_kind,a.subject_id,a.subject_key,a.subject_path
      )
  );
$function$;

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
