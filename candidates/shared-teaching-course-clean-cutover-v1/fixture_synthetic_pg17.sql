-- Network-isolated PG17 test only: fictional identities and manuscripts.
-- Not a protected production-shaped clone. No live customer data or credentials.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA reality;
CREATE SCHEMA atlas;
CREATE SCHEMA titus;
CREATE SCHEMA ledger;
GRANT USAGE ON SCHEMA auth,public TO authenticated;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE auth.sessions(
 id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id),
 not_after timestamptz
);
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $jwt$
 SELECT coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)
$jwt$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT (NULLIF(current_setting('request.jwt.claims',true),'')::jsonb ->> 'sub')::uuid
$$;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
CREATE TABLE reality.entities(
 id uuid PRIMARY KEY,
 entity_kind text NOT NULL CHECK(entity_kind in ('person','business')),
 identity_state text NOT NULL DEFAULT 'canonical',
 stable_key text NOT NULL
);
CREATE TABLE reality.auth_person_bindings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 binding_state text NOT NULL,
 retired_at timestamptz
);
-- Fictional Atlas Reality authorization stub: models CURRENT session
-- dependency only; this is not genuine signed GoTrue/PostgREST proof.
CREATE FUNCTION atlas.reality_access_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog
AS $reality_context$
DECLARE v_auth uuid:=auth.uid(); v_session uuid; v_person uuid;
BEGIN
 BEGIN
  v_session:=nullif(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN v_session:=NULL;
 END;
 IF v_auth IS NULL OR v_session IS NULL
  OR NOT EXISTS (SELECT 1 FROM auth.sessions s
   WHERE s.id=v_session AND s.user_id=v_auth
   AND (s.not_after IS NULL OR s.not_after>clock_timestamp())) THEN
  RETURN jsonb_build_object('contractVersion','reality_access_self_v1',
   'authenticated',false,'state','session_invalid');
 END IF;
 SELECT b.person_entity_id INTO v_person FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
  AND e.entity_kind='person' AND e.identity_state='canonical'
 WHERE b.auth_user_id=v_auth AND b.binding_state='active'
 AND b.retired_at IS NULL ORDER BY b.id LIMIT 1;
 IF v_person IS NULL THEN
  RETURN jsonb_build_object('contractVersion','reality_access_self_v1',
   'authenticated',true,'state','person_binding_required');
 END IF;
 RETURN jsonb_build_object('contractVersion','reality_access_self_v1',
  'authenticated',true,'state','ready',
  'person',jsonb_build_object('id',v_person));
END
$reality_context$;
CREATE TABLE ledger.ledgers(
 id uuid PRIMARY KEY,
 subject_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 ledger_state text NOT NULL,
 retired_at timestamptz
);
CREATE TABLE atlas.ledgers(id uuid PRIMARY KEY);
CREATE TABLE atlas.capability_activations(id uuid PRIMARY KEY);
CREATE TABLE atlas.people(id uuid PRIMARY KEY);
CREATE TABLE atlas.principals(id uuid PRIMARY KEY);
CREATE TABLE atlas.teaching_courses(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 capability_activation_id uuid NOT NULL REFERENCES atlas.capability_activations(id) ON DELETE RESTRICT,
 course_key text NOT NULL CHECK (btrim(course_key)<>''),
 name text NOT NULL CHECK (btrim(name)<>''),
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
 created_by_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 retired_at timestamptz,
 UNIQUE(ledger_id,id),
 CHECK ((status='active' AND retired_at IS NULL) OR
        (status='retired' AND retired_at IS NOT NULL))
);
CREATE UNIQUE INDEX teaching_courses_ledger_key_uq ON atlas.teaching_courses (ledger_id,lower(course_key));
CREATE FUNCTION atlas.guard_teaching_course_activation_v1()
RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE FUNCTION atlas.guard_teaching_course_identity_update_v1()
RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE FUNCTION atlas.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END $$;
CREATE TRIGGER teaching_courses_activation_guard_v1
 BEFORE INSERT OR UPDATE ON atlas.teaching_courses
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_teaching_course_activation_v1();
CREATE TRIGGER teaching_courses_identity_immutable_v1
 BEFORE UPDATE ON atlas.teaching_courses
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_teaching_course_identity_update_v1();
CREATE TRIGGER teaching_courses_set_updated_at
 BEFORE UPDATE ON atlas.teaching_courses
 FOR EACH ROW EXECUTE FUNCTION atlas.set_updated_at();
CREATE TABLE titus.customer_course_drafts_v1(
 course_id uuid PRIMARY KEY,workspace_id uuid NOT NULL,
 created_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 create_request_id uuid NOT NULL,
 title text NOT NULL,state text NOT NULL DEFAULT 'draft',
 created_at timestamptz NOT NULL
);
CREATE TABLE titus.customer_course_material_revisions_v1(
 revision_id uuid PRIMARY KEY,
 course_id uuid NOT NULL REFERENCES titus.customer_course_drafts_v1(course_id),
 edit_request_id uuid NOT NULL,based_on_revision integer NOT NULL,
 revision_number integer NOT NULL,body_text text NOT NULL,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 recorded_at timestamptz NOT NULL
);
CREATE TABLE titus.customer_course_units_v1(
 unit_id uuid PRIMARY KEY,
 course_id uuid NOT NULL REFERENCES titus.customer_course_drafts_v1(course_id),
 create_request_id uuid NOT NULL,kind text NOT NULL,title text NOT NULL,
 display_position integer NOT NULL,
 created_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL
);
CREATE TABLE titus.customer_course_unit_revisions_v1(
 revision_id uuid PRIMARY KEY,
 unit_id uuid NOT NULL REFERENCES titus.customer_course_units_v1(unit_id),
 edit_request_id uuid NOT NULL,based_on_revision integer NOT NULL,
 revision_number integer NOT NULL,body_text text NOT NULL,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 recorded_at timestamptz NOT NULL
);
CREATE TABLE titus.customer_workspace_entitlements_v1(
 owner_auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),
 grant_kind text NOT NULL,
 grant_source_receipt text NOT NULL,
 state text NOT NULL,
 granted_at timestamptz NOT NULL,
 valid_until timestamptz
);
INSERT INTO auth.users(id) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
INSERT INTO auth.sessions(id,user_id,not_after) VALUES
 ('5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',NULL),
 ('5ccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',NULL);
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','person','fictional-author'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','person','fictional-outsider'),
 ('44444444-4444-4444-8444-444444444444','business','fictional-institution');
INSERT INTO ledger.ledgers(id,subject_entity_id,ledger_state,retired_at)
 VALUES('77777777-7777-4777-8777-777777777777',
 '44444444-4444-4444-8444-444444444444','active',NULL);
INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','active'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd','active');
INSERT INTO titus.customer_workspace_entitlements_v1 VALUES(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'private_pilot','fictional-pilot-grant-receipt','active',
 '2026-11-06 15:00+00',NULL);
INSERT INTO titus.customer_course_drafts_v1(
 course_id,workspace_id,created_by_auth_user_id,create_request_id,
 title,state,created_at) VALUES
 ('11111111-1111-4111-8111-111111111111',
  'f1111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'e1111111-1111-4111-8111-111111111111',
  'Fictional law study','draft','2026-11-06 15:13:20+00');
INSERT INTO titus.customer_course_material_revisions_v1 VALUES
 ('21111111-1111-4111-8111-111111111111',
  '11111111-1111-4111-8111-111111111111',
  'e2111111-1111-4111-8111-111111111111',
  0,1,E'Teaching source\n\nObservation: \u05d0\n',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-11-06 15:13:30+00');
INSERT INTO titus.customer_course_units_v1 VALUES
 ('31111111-1111-4111-8111-111111111111',
  '11111111-1111-4111-8111-111111111111',
  'e3111111-1111-4111-8111-111111111111',
  'lesson','Class 1',1,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-11-06 16:00+00'),
 ('32222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'e3222222-2222-4222-8222-222222222222',
  'assignment','Homework draft 1',2,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-11-06 16:20+00');
INSERT INTO titus.customer_course_unit_revisions_v1 VALUES
 ('41111111-1111-4111-8111-111111111111',
  '31111111-1111-4111-8111-111111111111',
  'e4111111-1111-4111-8111-111111111111',
  0,1,E'Before\r\nAfter',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-11-06 16:04+00'),
 ('42222222-2222-4222-8222-222222222222',
  '31111111-1111-4111-8111-111111111111',
  'e4222222-2222-4222-8222-222222222222',
  1,2,'Revised class law statement.',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-11-06 17:15+00'),
 ('43333333-3333-4333-8333-333333333333',
  '32222222-2222-4222-8222-222222222222',
  'e4333333-3333-4333-8333-333333333333',
  0,1,'Research question, not issued Work.',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-11-06 17:18+00');
