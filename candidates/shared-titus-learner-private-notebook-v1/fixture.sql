-- Fictional structures only. Never migrate or apply to a live project.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA atlas;
CREATE SCHEMA reality;
CREATE SCHEMA titus;
GRANT USAGE ON SCHEMA public TO authenticated;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email_confirmed_at timestamptz,phone_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean DEFAULT false);
CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid REFERENCES auth.users(id),not_after timestamptz);
CREATE TABLE reality.entities(id uuid PRIMARY KEY,entity_kind text,identity_state text);
CREATE TABLE reality.auth_person_bindings(id uuid PRIMARY KEY,auth_user_id uuid,person_entity_id uuid REFERENCES reality.entities(id),binding_state text,retired_at timestamptz);
CREATE TABLE atlas.people(id uuid PRIMARY KEY,status text);
CREATE TABLE atlas.person_auth_credentials(id uuid PRIMARY KEY,person_id uuid REFERENCES atlas.people(id),credential_kind text,auth_user_id uuid,status text,retired_at timestamptz);
CREATE TABLE atlas.teaching_courses(id uuid PRIMARY KEY,ledger_id uuid,capability_activation_id uuid,status text,retired_at timestamptz);
CREATE TABLE atlas.teaching_course_versions(id uuid PRIMARY KEY,course_id uuid REFERENCES atlas.teaching_courses(id),published_at timestamptz);
CREATE TABLE atlas.teaching_course_offerings(id uuid PRIMARY KEY,ledger_id uuid,course_id uuid REFERENCES atlas.teaching_courses(id),course_version_id uuid REFERENCES atlas.teaching_course_versions(id),state text,opened_at timestamptz,closed_at timestamptz,retired_at timestamptz);
CREATE TABLE atlas.teaching_enrollments(id uuid PRIMARY KEY,ledger_id uuid,offering_id uuid REFERENCES atlas.teaching_course_offerings(id),person_id uuid REFERENCES atlas.people(id),state text,withdrawn_at timestamptz);
CREATE TABLE atlas.synthetic_capability(ledger_id uuid,activation_id uuid,state text);
CREATE FUNCTION atlas.teaching_activation_active_v1(l uuid,a uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $f$
 SELECT EXISTS (SELECT 1 FROM atlas.synthetic_capability x WHERE x.ledger_id=l AND x.activation_id=a AND x.state='active');
$f$;
-- Never treat these unsigned request GUCs as GoTrue verification.
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
$f$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE SET search_path=pg_catalog AS $f$
 SELECT nullif(auth.jwt()->>'sub','')::uuid;
$f$;
-- Exact behavior from existing live Titus resolver, using synthetic sessions.
CREATE FUNCTION titus.current_authenticated_person_entity_id_v1() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,auth,reality,titus AS $f$
DECLARE u uuid:=auth.uid();sid uuid;pid uuid;
BEGIN
 IF u IS NULL THEN RETURN NULL; END IF;
 BEGIN sid:=nullif(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN others THEN RETURN NULL;END;
 IF sid IS NULL OR NOT EXISTS(
  SELECT 1 FROM auth.sessions s WHERE s.id=sid AND s.user_id=u AND (s.not_after IS NULL OR s.not_after>now())
 ) OR NOT EXISTS(
  SELECT 1 FROM auth.users x WHERE x.id=u AND x.deleted_at IS NULL AND (x.banned_until IS NULL OR x.banned_until<=now())
 ) THEN RETURN NULL;END IF;
 SELECT b.person_entity_id INTO pid FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
 WHERE b.auth_user_id=u AND b.binding_state='active' AND b.retired_at IS NULL ORDER BY b.bound_at DESC NULLS LAST,b.id LIMIT 1;
 RETURN pid;
END;
$f$;

INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES ('10000000-0000-4000-8000-000000000001',now(),false);
INSERT INTO auth.sessions(id,user_id,not_after) VALUES ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',now()+interval '1 day');
INSERT INTO reality.entities VALUES ('30000000-0000-4000-8000-000000000001','person','canonical');
INSERT INTO reality.auth_person_bindings(id,auth_user_id,person_entity_id,binding_state) VALUES ('40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.people VALUES ('30000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.person_auth_credentials(id,person_id,credential_kind,auth_user_id,status) VALUES ('50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','supabase_auth_user','10000000-0000-4000-8000-000000000001','active');
INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES ('10000000-0000-4000-8000-000000000002',now(),false);
INSERT INTO auth.sessions(id,user_id,not_after) VALUES ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',now()+interval '1 day');
INSERT INTO reality.entities VALUES ('30000000-0000-4000-8000-000000000002','person','canonical');
INSERT INTO reality.auth_person_bindings(id,auth_user_id,person_entity_id,binding_state) VALUES ('40000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','active');
INSERT INTO atlas.people VALUES ('30000000-0000-4000-8000-000000000002','active');
INSERT INTO atlas.person_auth_credentials(id,person_id,credential_kind,auth_user_id,status) VALUES ('50000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','supabase_auth_user','10000000-0000-4000-8000-000000000002','active');
INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES ('10000000-0000-4000-8000-000000000003',now(),false);
INSERT INTO auth.sessions(id,user_id,not_after) VALUES ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003',now()+interval '1 day');
INSERT INTO reality.entities VALUES ('30000000-0000-4000-8000-000000000003','person','canonical');
INSERT INTO reality.auth_person_bindings(id,auth_user_id,person_entity_id,binding_state) VALUES ('40000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000003','active');
INSERT INTO atlas.people VALUES ('30000000-0000-4000-8000-000000000003','active');
INSERT INTO atlas.person_auth_credentials(id,person_id,credential_kind,auth_user_id,status) VALUES ('50000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000003','supabase_auth_user','10000000-0000-4000-8000-000000000003','active');
INSERT INTO atlas.synthetic_capability VALUES ('60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.teaching_courses(id,ledger_id,capability_activation_id,status) VALUES ('80000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.teaching_course_versions VALUES ('90000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001',now());
INSERT INTO atlas.teaching_course_offerings(id,ledger_id,course_id,course_version_id,state,opened_at) VALUES ('aa000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','90000000-0000-4000-8000-000000000001','open',now());
INSERT INTO atlas.teaching_enrollments(id,ledger_id,offering_id,person_id,state) VALUES ('bb000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','aa000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.teaching_enrollments(id,ledger_id,offering_id,person_id,state) VALUES ('bb000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001','aa000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','active');
