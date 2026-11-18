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
CREATE FUNCTION atlas.current_person_for_private_course_v1()
 RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
 SET search_path TO pg_catalog AS $current$
DECLARE v_auth uuid;v_session uuid;v_person uuid;v_count bigint;
BEGIN
 v_auth:=auth.uid();
 BEGIN v_session:=NULLIF(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN v_session:=NULL; END;
 IF v_auth IS NULL OR v_session IS NULL
 OR NOT EXISTS (SELECT 1 FROM auth.sessions s
  WHERE s.id=v_session AND s.user_id=v_auth
  AND (s.not_after IS NULL OR s.not_after>clock_timestamp()))
 THEN RAISE EXCEPTION 'current signed session required'
 USING ERRCODE='42501'; END IF;
 SELECT count(*),min(b.person_entity_id::text)::uuid INTO v_count,v_person
 FROM reality.auth_person_bindings b JOIN reality.entities e
 ON e.id=b.person_entity_id
 WHERE b.auth_user_id=v_auth AND b.binding_state='active'
 AND b.retired_at IS NULL AND e.entity_kind='person'
 AND e.identity_state='canonical';
 IF v_count<>1 THEN RAISE EXCEPTION 'unique signed canonical Person required'
 USING ERRCODE='42501'; END IF;
 RETURN v_person;
END $current$;
REVOKE ALL ON FUNCTION atlas.current_person_for_private_course_v1()
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
-- INDEPENDENT ROOT, only in this isolated fiction, not a real university
-- owner. Manager authority must be appointed by the shared governed command.
INSERT INTO reality.responsibility_relations(
id,carrier_person_entity_id,responsibility_key,jurisdiction_kind,
jurisdiction_entity_id,relation_state,permitted_operations,began_at,scope)
VALUES('99999999-9999-4999-8999-999999999999',
 '11111111-1111-4111-8111-111111111111',
 'titus_institution_account_root_governance','entity',
 '44444444-4444-4444-8444-444444444444','active',
 ARRAY['appoint_manager','transfer_manager','revoke_manager']::text[],
 now()-interval '1 hour',
 '{"ledgerId":"77777777-7777-4777-8777-777777777777"}');
