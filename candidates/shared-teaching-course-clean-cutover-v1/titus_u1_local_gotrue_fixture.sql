-- TITUS U1 SIGNED LOCAL TEST FIXTURE ONLY.
-- Genuine GoTrue + PostgREST local stack, fictional institutions and People.
-- No schema dump, production credentials, customer records or release.
-- This fixture deliberately does NOT create Auth users or sessions:
-- the signed test driver obtains those from actual local GoTrue.
DO $local_only$
BEGIN
 IF current_setting('app.titus_u1_local_signed_fixture',true) IS DISTINCT FROM 'approved'
 OR current_database()<>'postgres'
 OR to_regclass('auth.sessions') IS NULL
 OR to_regclass('auth.users') IS NULL
 THEN RAISE EXCEPTION 'U1 signed fixture requires approved disposable local Supabase'
 USING ERRCODE='42501'; END IF;
END $local_only$;
CREATE SCHEMA reality;
CREATE SCHEMA ledger;
CREATE SCHEMA atlas;
CREATE SCHEMA titus;
CREATE SCHEMA compatibility;
CREATE TABLE compatibility.legacy_bindings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 legacy_schema text NOT NULL, legacy_table text NOT NULL,
 legacy_key text NOT NULL, disposition text NOT NULL,
 new_schema text NOT NULL,new_table text NOT NULL,
 new_id uuid NOT NULL,created_at timestamptz DEFAULT clock_timestamp()
);

CREATE TABLE reality.entities (
 id uuid PRIMARY KEY,
 entity_kind text NOT NULL CHECK(entity_kind IN ('person','business','organization')),
 identity_state text NOT NULL DEFAULT 'canonical',
 stable_key text NOT NULL UNIQUE
);
CREATE TABLE reality.auth_person_bindings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 binding_state text NOT NULL CHECK(binding_state IN ('active','retired')),
 bound_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 retired_at timestamptz
);
CREATE UNIQUE INDEX titus_u1_local_one_active_auth
 ON reality.auth_person_bindings(auth_user_id) WHERE binding_state='active' AND retired_at IS NULL;
CREATE UNIQUE INDEX titus_u1_local_one_active_person
 ON reality.auth_person_bindings(person_entity_id) WHERE binding_state='active' AND retired_at IS NULL;
CREATE TABLE ledger.ledgers (
 id uuid PRIMARY KEY,
 subject_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ledger_state text NOT NULL CHECK(ledger_state IN ('active','retired')),
 retired_at timestamptz
);
CREATE TABLE reality.responsibility_relations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 carrier_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 responsibility_key text NOT NULL,
 jurisdiction_kind text NOT NULL,
 jurisdiction_entity_id uuid REFERENCES reality.entities(id),
 jurisdiction_domain text,
 relation_state text NOT NULL CHECK(relation_state IN ('active','ended')),
 permitted_operations text[] NOT NULL,
 began_at timestamptz NOT NULL,
 ended_at timestamptz,
 scope jsonb NOT NULL DEFAULT '{}'::jsonb,
 title text NOT NULL DEFAULT 'Fictional responsibility',
 establishment_kind text NOT NULL DEFAULT 'fictional_fixture',
 source_person_entity_id uuid REFERENCES reality.entities(id),
 establishment_basis jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE FUNCTION reality.resolve_responsibility_relation_v1(
 p_person_entity_id uuid,p_responsibility_key text,p_operation_key text,
 p_jurisdiction_kind text,p_jurisdiction_entity_id uuid,
 p_jurisdiction_domain text,p_required_scope jsonb
) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO '' AS $shared$
 SELECT rr.id FROM reality.responsibility_relations rr
 JOIN reality.entities person ON person.id=rr.carrier_person_entity_id
 AND person.entity_kind='person' AND person.identity_state='canonical'
 LEFT JOIN reality.entities subject ON subject.id=rr.jurisdiction_entity_id
 WHERE rr.carrier_person_entity_id=p_person_entity_id
 AND rr.responsibility_key=p_responsibility_key
 AND rr.relation_state='active' AND rr.began_at<=now()
 AND rr.ended_at IS NULL
 AND p_operation_key=ANY(rr.permitted_operations)
 AND rr.jurisdiction_kind=p_jurisdiction_kind
 AND ((p_jurisdiction_kind='entity'
   AND rr.jurisdiction_entity_id=p_jurisdiction_entity_id
   AND subject.identity_state='canonical')
  OR (p_jurisdiction_kind='domain' AND rr.jurisdiction_domain=p_jurisdiction_domain))
 AND rr.scope @> COALESCE(p_required_scope,'{}'::jsonb)
 ORDER BY rr.began_at DESC,rr.id LIMIT 1
$shared$;
-- Only fixture-specific Auth resolver implementation. This is NOT a source
-- replacement for Noel's existing Atlas/Reality resolver in production.
-- The scratch copies the current canonical Atlas Person reader, but
-- intentionally does NOT supply Titus's extra signed-session adapter.
-- The latter is loaded from its exact held source below.
CREATE FUNCTION atlas.current_person_id_v1()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog AS $canonical_person$
 SELECT b.person_entity_id
 FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
  AND e.entity_kind='person' AND e.identity_state='canonical'
 WHERE b.auth_user_id=auth.uid()
  AND b.binding_state='active' AND b.retired_at IS NULL
 ORDER BY b.bound_at DESC,b.id LIMIT 1
$canonical_person$;
REVOKE ALL ON FUNCTION atlas.current_person_id_v1()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION reality.resolve_responsibility_relation_v1(
 uuid,text,text,text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
INSERT INTO reality.entities(id,entity_kind,stable_key) VALUES
('11111111-1111-4111-8111-111111111111','person','u1-test-manager'),
('22222222-2222-4222-8222-222222222222','person','u1-test-recipient'),
('33333333-3333-4333-8333-333333333333','person','u1-test-outsider'),
('44444444-4444-4444-8444-444444444444','business','u1-test-institution');
INSERT INTO ledger.ledgers(id,subject_entity_id,ledger_state) VALUES
('77777777-7777-4777-8777-777777777777',
 '44444444-4444-4444-8444-444444444444','active'),
('88888888-8888-4888-8888-888888888888',
 '44444444-4444-4444-8444-444444444444','active');
-- The following miniature Atlas objects model the already-live *independent*
-- Principal-root/active governing Ledger + Seat contract on disposable local
-- GoTrue. This is not production schema; full clone parity stays HELD.
CREATE TABLE atlas.organizations(
 id uuid PRIMARY KEY,status text NOT NULL
);
CREATE TABLE atlas.ledgers(
 id uuid PRIMARY KEY,status text NOT NULL
);
CREATE TABLE atlas.ledger_organization_participations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL,
 organization_id uuid NOT NULL,
 participation_kind text NOT NULL,
 is_compatibility_primary boolean NOT NULL,
 status text NOT NULL,
 ended_at timestamptz
);
CREATE TABLE atlas.principals(
 id uuid PRIMARY KEY,person_id uuid NOT NULL REFERENCES reality.entities(id),
 status text NOT NULL
);
CREATE TABLE atlas.principal_ledger_authorities(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 ledger_id uuid NOT NULL,
 authority_kind text NOT NULL,
 status text NOT NULL,
 ended_at timestamptz
);
CREATE TABLE ledger.seats(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 seat_state text NOT NULL,
 ended_at timestamptz
);
INSERT INTO atlas.organizations(id,status)
VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','active'),
       ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','active');
-- A second Atlas-only governing-primary pair deliberately has NO native
-- ledger. A compatibility mapping cannot establish its missing native source.

INSERT INTO compatibility.legacy_bindings(
 legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id)
VALUES('atlas','organizations','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'maps_to','reality','entities','44444444-4444-4444-8444-444444444444');

INSERT INTO atlas.ledgers(id,status)
VALUES('77777777-7777-4777-8777-777777777777','active'),
('88888888-8888-4888-8888-888888888888','active'),
('66666666-6666-4666-8666-666666666666','active');
INSERT INTO atlas.ledger_organization_participations(
 ledger_id,organization_id,participation_kind,is_compatibility_primary,status)
VALUES('77777777-7777-4777-8777-777777777777',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','governing',true,'active'),
('66666666-6666-4666-8666-666666666666',
'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','governing',true,'active'),
('88888888-8888-4888-8888-888888888888',
'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','operating',false,'active');
INSERT INTO atlas.principals(id,person_id,status)
VALUES('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
'11111111-1111-4111-8111-111111111111','active');
INSERT INTO atlas.principal_ledger_authorities(principal_id,ledger_id,authority_kind,status)
VALUES('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
'77777777-7777-4777-8777-777777777777','root_governing','active');
INSERT INTO ledger.seats(ledger_id,person_entity_id,seat_state)
VALUES('77777777-7777-4777-8777-777777777777',
'11111111-1111-4111-8111-111111111111','active'),
('88888888-8888-4888-8888-888888888888',
'11111111-1111-4111-8111-111111111111','active');

-- Scratch adapter approximates the ACTUAL existing Atlas native+primary
-- governing-Principal two-Ledger check; it is still a FICTIONAL TEST DOUBLE,
-- NOT a production-schema restore or a copy of private source SQL.
-- It intentionally distinguishes a native operating Ledger (8888) from the
-- separately governed primary Ledger (7777), both for the same Organization.
CREATE FUNCTION atlas.company_work_native_ledger_owner_self_v1(
 p_organization_id uuid,p_ledger_id uuid
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $scratch_atlas$
DECLARE
 v_person uuid;v_principal uuid;v_principals bigint;
 v_primary uuid;v_primary_count bigint;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT count(*),min(p.id::text)::uuid INTO v_principals,v_principal
 FROM atlas.principals p
 WHERE p.person_id=v_person AND p.status='active';
 IF v_principals<>1 THEN
 RAISE EXCEPTION 'one signed active Principal required'
 USING ERRCODE='42501'; END IF;

 IF NOT EXISTS(SELECT 1 FROM atlas.ledger_organization_participations lop
  JOIN atlas.ledgers al ON al.id=lop.ledger_id AND al.status='active'
  JOIN ledger.ledgers nl ON nl.id=al.id
   AND nl.ledger_state='active' AND nl.retired_at IS NULL
  WHERE lop.ledger_id=p_ledger_id AND lop.organization_id=p_organization_id
   AND lop.status='active' AND lop.ended_at IS NULL
   AND lop.participation_kind IN ('governing','operating'))
 THEN RAISE EXCEPTION 'current native Ledger participation required'
 USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM ledger.seats seat
  WHERE seat.ledger_id=p_ledger_id AND seat.person_entity_id=v_person
  AND seat.seat_state='active' AND seat.ended_at IS NULL)
 THEN RAISE EXCEPTION 'current native Ledger Seat required'
 USING ERRCODE='42501'; END IF;

 SELECT count(*),min(lop.ledger_id::text)::uuid
 INTO v_primary_count,v_primary
 FROM atlas.ledger_organization_participations lop
 JOIN atlas.ledgers al ON al.id=lop.ledger_id AND al.status='active'
 WHERE lop.organization_id=p_organization_id AND lop.status='active'
 AND lop.ended_at IS NULL AND lop.participation_kind='governing'
 AND lop.is_compatibility_primary;
 IF v_primary_count<>1 THEN
 RAISE EXCEPTION 'unique current organizational primary Ledger required'
 USING ERRCODE='42501'; END IF;

 IF NOT EXISTS(SELECT 1 FROM atlas.principal_ledger_authorities a
 JOIN atlas.ledgers al ON al.id=a.ledger_id AND al.status='active'
 WHERE a.principal_id=v_principal AND a.ledger_id=p_ledger_id
 AND a.authority_kind='root_governing' AND a.status='active'
 AND a.ended_at IS NULL)
 OR NOT EXISTS(SELECT 1 FROM atlas.principal_ledger_authorities a
 JOIN atlas.ledgers al ON al.id=a.ledger_id AND al.status='active'
 WHERE a.principal_id=v_principal AND a.ledger_id=v_primary
 AND a.authority_kind='root_governing' AND a.status='active'
 AND a.ended_at IS NULL)
 THEN RAISE EXCEPTION 'same Principal needs both native and primary root authority'
 USING ERRCODE='42501'; END IF;
 RETURN v_person;
END $scratch_atlas$;
REVOKE ALL ON FUNCTION atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

-- Disposable signed-HTTP transport ONLY. Not part of any U1 candidate,
-- production app API, release migration or canonical institutional role.
-- Its only purpose is testing the modeled Atlas authority in signed REST.
CREATE FUNCTION public.titus_u1_fixture_native_owner_probe_v1(
 p_ledger_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $native_probe$
DECLARE v_person uuid;v_source uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 v_source:=atlas.company_work_native_ledger_owner_self_v1(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,p_ledger_id);
 IF v_source IS DISTINCT FROM v_person THEN
 RAISE EXCEPTION 'Atlas root and Titus signed Person disagree'
 USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','titus_u1_fixture_native_owner_v1',
  'authorized',true);
END $native_probe$;
REVOKE ALL ON FUNCTION public.titus_u1_fixture_native_owner_probe_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_u1_fixture_native_owner_probe_v1(uuid)
 TO authenticated;
