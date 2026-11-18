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

-- Test existing guard function bodies, with fictional capability dependencies.
ALTER TABLE atlas.capability_activations ADD COLUMN ledger_id uuid,
 ADD COLUMN capability_key text, ADD COLUMN capability_version integer,
 ADD COLUMN subject_ledger_id uuid, ADD COLUMN subject_kind text,
 ADD COLUMN subject_id uuid, ADD COLUMN subject_key text,ADD COLUMN subject_path text,
 ADD COLUMN state text;
CREATE FUNCTION atlas.capability_subject_governed_v1(uuid,text,integer,uuid,text,uuid,text,text)
 RETURNS boolean LANGUAGE sql AS $$ SELECT $1=$4 AND $5='ledger' AND $1=$6 $$;
CREATE FUNCTION atlas.teaching_activation_active_v1(uuid,uuid)
 RETURNS boolean LANGUAGE sql AS $$ SELECT EXISTS(
 SELECT 1 FROM atlas.capability_activations a
 WHERE a.id=$2 AND a.ledger_id=$1 AND a.state='active') $$;
create or replace function atlas.guard_teaching_course_activation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_activation atlas.capability_activations%rowtype;
begin
  select * into v_activation from atlas.capability_activations where id=new.capability_activation_id;
  if v_activation.id is null
     or v_activation.ledger_id<>new.ledger_id
     or v_activation.capability_key<>'teaching'
     or v_activation.capability_version<>1
     or not atlas.capability_subject_governed_v1(
       v_activation.ledger_id,v_activation.capability_key,v_activation.capability_version,v_activation.subject_ledger_id,
       v_activation.subject_kind,v_activation.subject_id,v_activation.subject_key,v_activation.subject_path
     ) then
    raise exception 'Course must bind to a valid Teaching v1 activation governed by the same Ledger.' using errcode='23514';
  end if;
  if tg_op='INSERT' and not atlas.teaching_activation_active_v1(new.ledger_id,new.capability_activation_id) then
    raise exception 'Active Teaching v1 capability required to create Course.' using errcode='23514';
  end if;
  return new;
end;
$function$;
create or replace function atlas.guard_teaching_course_identity_update_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin
  if old.ledger_id is distinct from new.ledger_id
     or old.capability_activation_id is distinct from new.capability_activation_id
     or old.course_key is distinct from new.course_key
     or old.created_by_person_id is distinct from new.created_by_person_id
     or old.created_by_principal_id is distinct from new.created_by_principal_id
     or old.created_at is distinct from new.created_at then
    raise exception 'Teaching Course identity/custody fields are immutable.' using errcode='55000';
  end if;
  if old.status='retired' and new.status<>'retired' then
    raise exception 'Retired Teaching Course is terminal.' using errcode='55000';
  end if;
  return new;
end;
$function$;
INSERT INTO atlas.ledgers(id) VALUES('77777777-7777-4777-8777-777777777777');
INSERT INTO atlas.capability_activations(id,ledger_id,capability_key,capability_version,
 subject_ledger_id,subject_kind,subject_id,state)
 VALUES('81111111-1111-4111-8111-111111111111','77777777-7777-4777-8777-777777777777',
 'teaching',1,'77777777-7777-4777-8777-777777777777','ledger',
 '77777777-7777-4777-8777-777777777777','active');
INSERT INTO atlas.people(id) VALUES('82222222-2222-4222-8222-222222222222');
INSERT INTO atlas.principals(id) VALUES('83333333-3333-4333-8333-333333333333');
INSERT INTO atlas.teaching_courses(id,ledger_id,capability_activation_id,course_key,name,
 created_by_person_id,created_by_principal_id)
 VALUES('84444444-4444-4444-8444-444444444444','77777777-7777-4777-8777-777777777777',
 '81111111-1111-4111-8111-111111111111','institution-course','Fictional institution course',
 '82222222-2222-4222-8222-222222222222','83333333-3333-4333-8333-333333333333');

CREATE TABLE reality.responsibility_relations(
 id uuid PRIMARY KEY,carrier_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 responsibility_key text NOT NULL,jurisdiction_kind text NOT NULL,jurisdiction_domain text,
 relation_state text NOT NULL,permitted_operations text[] NOT NULL,
 began_at timestamptz NOT NULL,ended_at timestamptz);

BEGIN;
CREATE TEMP TABLE original_rows AS SELECT
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM atlas.teaching_courses c) AS institutional,
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.course_id) FROM titus.customer_course_drafts_v1 c) AS drafts,
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.revision_id) FROM titus.customer_course_material_revisions_v1 c) AS manuscripts,
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.unit_id) FROM titus.customer_course_units_v1 c) AS units,
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.revision_id) FROM titus.customer_course_unit_revisions_v1 c) AS revisions,
 (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.owner_auth_user_id) FROM titus.customer_workspace_entitlements_v1 c) AS entitlements;
SET LOCAL app.shared_course_clone='approved';
\ir personal_authoring_candidate.sql

DO $check$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR EXISTS(SELECT 1 FROM atlas.teaching_course_units)
 OR EXISTS(SELECT 1 FROM titus.course_authoring_access_grants)
 THEN RAISE EXCEPTION 'installation must neither alter nor seed Courses or grants'; END IF;
 IF has_table_privilege('authenticated','atlas.teaching_courses','SELECT')
 OR has_table_privilege('authenticated','atlas.teaching_course_unit_revisions','INSERT')
 OR has_function_privilege('anon','public.shared_teaching_course_create_self_api_v1(uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'unexpected direct access'; END IF;
 -- A legacy-shaped Course still requires an active teaching activation.
 UPDATE atlas.capability_activations SET state='inactive';
 BEGIN
 INSERT INTO atlas.teaching_courses(ledger_id,capability_activation_id,course_key,name,
 created_by_person_id,created_by_principal_id)
 VALUES('77777777-7777-4777-8777-777777777777',
 '81111111-1111-4111-8111-111111111111','illegal','Illegal',
 '82222222-2222-4222-8222-222222222222','83333333-3333-4333-8333-333333333333');
 RAISE EXCEPTION 'inactive old activation allowed';
 EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE atlas.capability_activations SET state='active';
 BEGIN
 UPDATE atlas.teaching_courses SET created_by_person_entity_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  create_request_id=gen_random_uuid(),created_by_auth_user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  ledger_id=NULL,capability_activation_id=NULL,created_by_person_id=NULL,created_by_principal_id=NULL
  WHERE id='84444444-4444-4444-8444-444444444444';
 RAISE EXCEPTION 'old origin rewritten';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END $check$;

-- Fixture authority only. No seeded product entitlement.
INSERT INTO reality.responsibility_relations VALUES(
 '89999999-9999-4999-8999-999999999999','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 'titus_private_pilot_issuance','domain','titus','active',
 ARRAY['issue_pilot_code','revoke_pilot_code','end_pilot_access'],now(),NULL);
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $issue$
DECLARE r jsonb;
BEGIN
 r:=public.titus_private_pilot_code_issue_self_api_v1(gen_random_uuid());
 IF r->>'grantActive'<>'false' THEN RAISE EXCEPTION 'issuer auto-granted'; END IF;
 PERFORM set_config('app.fictional_code',r->>'code',true);
END $issue$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $author$
DECLARE r jsonb; cid uuid; uid uuid; req uuid:=gen_random_uuid(); saved text:='A fictional original observation.';
BEGIN
 IF public.titus_authoring_access_self_api_v1()->>'canUseTitus'<>'false'
 OR public.shared_teaching_course_catalog_self_api_v1()->'courses'<>'[]'::jsonb
 THEN RAISE EXCEPTION 'nonempty first use'; END IF;
 BEGIN
 PERFORM public.shared_teaching_course_create_self_api_v1(req,'Uninvited');
 RAISE EXCEPTION 'uninvited direct writer allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 r:=public.titus_private_pilot_code_claim_self_api_v1(current_setting('app.fictional_code'),gen_random_uuid());
 IF r->>'grantActive'<>'true' THEN RAISE EXCEPTION 'claim failed'; END IF;
 r:=public.shared_teaching_course_create_self_api_v1(req,'Personal study');
 cid:=(r->>'courseId')::uuid;
 IF public.shared_teaching_course_create_self_api_v1(req,'Personal study')->>'courseId'<>cid::text
 OR public.shared_teaching_course_outline_read_self_api_v1(cid)->'units'<>'[]'::jsonb
 THEN RAISE EXCEPTION 'original identity not retained or outline is not empty'; END IF;
 r:=public.shared_teaching_course_material_save_self_api_v1(cid,gen_random_uuid(),0,'Original manuscript');
 IF r->'material'->>'text'<>'Original manuscript' THEN RAISE EXCEPTION 'manuscript save failed'; END IF;
 r:=public.shared_teaching_course_unit_create_self_api_v1(cid,gen_random_uuid(),'lesson','Opening');
 uid:=(r->'units'->0->>'unitId')::uuid;
 r:=public.shared_teaching_course_unit_save_self_api_v1(uid,gen_random_uuid(),0,saved);
 IF r->'material'->>'text'<>saved OR r->'material'->>'revisionNumber'<>'1'
 OR public.shared_teaching_course_unit_read_self_api_v1(uid)->'material'->>'text'<>saved
 OR public.shared_teaching_course_catalog_self_api_v1()->'courses'->0->>'courseId'<>cid::text
 THEN RAISE EXCEPTION 'save and reopen failed'; END IF;
 PERFORM set_config('app.fictional_course',cid::text,true);
 PERFORM set_config('app.fictional_unit',uid::text,true);
END $author$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $other$
BEGIN
 IF public.shared_teaching_course_catalog_self_api_v1()->'courses'<>'[]'::jsonb
 THEN RAISE EXCEPTION 'another Person disclosed'; END IF;
 BEGIN
 PERFORM public.shared_teaching_course_unit_read_self_api_v1(current_setting('app.fictional_unit')::uuid);
 RAISE EXCEPTION 'cross Person unit disclosed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.titus_private_pilot_access_end_self_api_v1(
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',gen_random_uuid());
END $other$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $ended$
BEGIN
 IF public.titus_authoring_access_self_api_v1()->>'canUseTitus'<>'false'
 OR public.shared_teaching_course_unit_read_self_api_v1(current_setting('app.fictional_unit')::uuid)->'material'->>'text'<>'A fictional original observation.'
 THEN RAISE EXCEPTION 'license ending erased original'; END IF;
 BEGIN
 PERFORM public.shared_teaching_course_unit_save_self_api_v1(
 current_setting('app.fictional_unit')::uuid,gen_random_uuid(),1,'Unauthorized update');
 RAISE EXCEPTION 'ended pilot still writes';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $ended$;
RESET ROLE;

DO $preserve$
DECLARE o original_rows%ROWTYPE;
BEGIN
 SELECT * INTO o FROM original_rows;
 IF o.institutional IS DISTINCT FROM (
 SELECT jsonb_agg(to_jsonb(c)-'created_by_person_entity_id'-'create_request_id'-'created_by_auth_user_id' ORDER BY c.id)
 FROM atlas.teaching_courses c WHERE c.created_by_person_entity_id IS NULL)
 OR o.drafts IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.course_id) FROM titus.customer_course_drafts_v1 c)
 OR o.manuscripts IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.revision_id) FROM titus.customer_course_material_revisions_v1 c)
 OR o.units IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.unit_id) FROM titus.customer_course_units_v1 c)
 OR o.revisions IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.revision_id) FROM titus.customer_course_unit_revisions_v1 c)
 OR o.entitlements IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.owner_auth_user_id) FROM titus.customer_workspace_entitlements_v1 c)
 THEN RAISE EXCEPTION 'existing fictional originals changed'; END IF;
END $preserve$;
ROLLBACK;
\echo PASS personal authoring with preserved fictional institution and historical Titus rows
