-- Titus Build 1G-B: synthetic session-table fixture ONLY, disposable PG17.
-- No actual GoTrue, no cryptographically verified JWT, no real identities.
-- The GUC below models claims AFTER an external PostgREST signature check;
-- direct set_config is unsafe as auth and MUST NEVER become a migration.
-- All three resolver bodies below are modeled from read-only live pg_get_functiondef
-- inspected 2026-11-04; this fixture is not a production source copy.
CREATE TABLE auth.users (
  id uuid PRIMARY KEY,
  deleted_at timestamptz,
  email_confirmed_at timestamptz,
  is_anonymous boolean NOT NULL DEFAULT false,
  banned_until timestamptz
);
CREATE TABLE auth.sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  not_after timestamptz
);
CREATE TABLE reality.auth_person_bindings (
  id uuid PRIMARY KEY,
  auth_user_id uuid NOT NULL REFERENCES auth.users(id),
  person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
  binding_state text NOT NULL,
  retired_at timestamptz,
  bound_at timestamptz NOT NULL
);

-- TEST transport: request.jwt.claims is input from the scratch test only.
-- A real Supabase/GoTrue deployment must validate JWT signatures *before*
-- constructing these claims; this fixture deliberately does NOT do that.
CREATE FUNCTION auth.jwt()
RETURNS jsonb LANGUAGE sql STABLE
SET search_path=pg_catalog AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)
$$;
CREATE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
SET search_path=pg_catalog,auth AS $$
  SELECT nullif(auth.jwt()->>'sub','')::uuid
$$;

INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES
 ('00000000-0000-4000-8000-000000000501',now(),false), -- governor
 ('00000000-0000-4000-8000-000000000502',now(),false), -- teacher
 ('00000000-0000-4000-8000-000000000503',now(),false), -- learner
 ('00000000-0000-4000-8000-000000000504',now(),false), -- outsider
 ('00000000-0000-4000-8000-000000000505',now(),false); -- retired Person
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
 ('00000000-0000-4000-8000-000000000751','00000000-0000-4000-8000-000000000501',now()+interval '1 day'),
 ('00000000-0000-4000-8000-000000000752','00000000-0000-4000-8000-000000000502',now()+interval '1 day'),
 ('00000000-0000-4000-8000-000000000753','00000000-0000-4000-8000-000000000503',now()+interval '1 day'),
 ('00000000-0000-4000-8000-000000000754','00000000-0000-4000-8000-000000000504',now()+interval '1 day'),
 ('00000000-0000-4000-8000-000000000755','00000000-0000-4000-8000-000000000505',now()+interval '1 day');
INSERT INTO reality.auth_person_bindings(
 id,auth_user_id,person_entity_id,binding_state,bound_at) VALUES
 ('00000000-0000-4000-8000-000000000801','00000000-0000-4000-8000-000000000501','00000000-0000-4000-8000-000000000204','active',now()),
 ('00000000-0000-4000-8000-000000000802','00000000-0000-4000-8000-000000000502','00000000-0000-4000-8000-000000000202','active',now()),
 ('00000000-0000-4000-8000-000000000803','00000000-0000-4000-8000-000000000503','00000000-0000-4000-8000-000000000201','active',now()),
 ('00000000-0000-4000-8000-000000000804','00000000-0000-4000-8000-000000000504','00000000-0000-4000-8000-000000000203','active',now()),
 ('00000000-0000-4000-8000-000000000805','00000000-0000-4000-8000-000000000505','00000000-0000-4000-8000-000000000205','active',now());

-- Replace only old GUC stubs in this disposable cluster with the
-- current production *source-shaped* functions. A signed JWT is NOT simulated.
CREATE OR REPLACE FUNCTION atlas.existing_person_claim_signed_actor_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $live_shape$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT EXISTS (
   SELECT 1 FROM auth.users u
   JOIN auth.sessions s ON s.user_id=u.id
   WHERE u.id=v_user AND u.deleted_at IS NULL
     AND u.email_confirmed_at IS NOT NULL
     AND NOT coalesce(u.is_anonymous,false)
     AND (u.banned_until IS NULL OR u.banned_until<=now())
     AND s.id::text=auth.jwt()->>'session_id'
     AND (s.not_after IS NULL OR s.not_after>now())
 ) THEN
   RAISE EXCEPTION 'Fresh verified Auth session required'
     USING errcode='42501';
 END IF;
 RETURN v_user;
END;
$live_shape$;

CREATE OR REPLACE FUNCTION titus.current_authenticated_person_entity_id_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'auth', 'reality', 'titus'
AS $live_shape$
DECLARE
  v_uid uuid := auth.uid();
  v_claims jsonb := auth.jwt();
  v_session_id uuid;
  v_person_id uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  BEGIN
    v_session_id := NULLIF(v_claims->>'session_id', '')::uuid;
  EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  IF v_session_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s
    WHERE s.id = v_session_id AND s.user_id = v_uid
      AND (s.not_after IS NULL OR s.not_after > now())
  ) THEN RETURN NULL; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = v_uid AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until <= now())
  ) THEN RETURN NULL; END IF;
  SELECT b.person_entity_id INTO v_person_id
  FROM reality.auth_person_bindings b
  JOIN reality.entities e ON e.id = b.person_entity_id
   AND e.entity_kind = 'person' AND e.identity_state = 'canonical'
  WHERE b.auth_user_id = v_uid AND b.binding_state = 'active'
    AND b.retired_at IS NULL
  ORDER BY b.bound_at DESC, b.id LIMIT 1;
  RETURN v_person_id;
END;
$live_shape$;

CREATE FUNCTION atlas.current_person_id_v1()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'auth', 'reality'
AS $live_shape$
  SELECT b.person_entity_id
  FROM reality.auth_person_bindings b
  JOIN reality.entities e
    ON e.id=b.person_entity_id
   AND e.entity_kind='person' AND e.identity_state='canonical'
  WHERE b.auth_user_id=auth.uid()
    AND b.binding_state='active'
    AND b.retired_at IS NULL
  ORDER BY b.bound_at DESC,b.id
  LIMIT 1;
$live_shape$;

CREATE OR REPLACE FUNCTION atlas.current_principal_id_v1()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $live_shape$
  SELECT p.id
  FROM atlas.principals p
  WHERE p.person_id = atlas.current_person_id_v1()
    AND p.status = 'active'
  LIMIT 1;
$live_shape$;

-- Fixture must retain privacy even though the schema is private by default.
REVOKE ALL ON TABLE auth.users,auth.sessions,reality.auth_person_bindings FROM PUBLIC;
REVOKE ALL ON FUNCTION auth.uid(),auth.jwt() FROM PUBLIC;
REVOKE ALL ON FUNCTION atlas.existing_person_claim_signed_actor_v1(),
 titus.current_authenticated_person_entity_id_v1(),
 atlas.current_person_id_v1(),atlas.current_principal_id_v1() FROM PUBLIC;
