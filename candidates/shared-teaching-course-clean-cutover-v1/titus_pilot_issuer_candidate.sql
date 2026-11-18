-- HELD M1.1 owner correction 6D/7C/5B: one transferable private-pilot code.
-- NOT a generated migration; disposable PG17 candidate and owner review only.
-- Single-claim behavior is a bounded test policy, NOT a final business choice
-- about multi-seat code capacity, code expiry, paid plans, or free trials.
-- No real owner/delegated Titus issuer standing is established by this file.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('reality.responsibility_relations') IS NULL
 OR to_regclass('titus.course_authoring_access_grants') IS NULL
 OR to_regclass('titus.course_authoring_access_status_events') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 THEN RAISE EXCEPTION 'held Titus pilot source prerequisites missing'
  USING ERRCODE='42501';
 END IF;
END $preflight$;

-- Role source is Reality's actual active domain responsibility; a signed
-- Titus user, Course author, institution teacher or product purchaser does
-- NOT automatically become a platform issuer. The private helper itself is
-- not callable via PostgREST.
CREATE FUNCTION titus.require_current_pilot_issuer_self_v1(
 p_operation text
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $issuer$
DECLARE v_person uuid;v_ids uuid[];
BEGIN
 IF p_operation NOT IN
  ('issue_pilot_code','revoke_pilot_code','end_pilot_access') THEN
  RAISE EXCEPTION 'exact Titus platform issuance operation required'
   USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT array_agg(r.id) INTO v_ids
 FROM reality.responsibility_relations r
 WHERE r.carrier_person_entity_id=v_person
  AND r.responsibility_key='titus_private_pilot_issuance'
  AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
  AND r.relation_state='active'
  AND r.began_at<=clock_timestamp()
  AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
  AND p_operation=ANY(r.permitted_operations);
 IF COALESCE(array_length(v_ids,1),0)<>1 THEN
  RAISE EXCEPTION 'one current authorized Titus platform issuer required'
   USING ERRCODE='42501';
 END IF;
 RETURN v_ids[1];
END $issuer$;
REVOKE ALL ON FUNCTION titus.require_current_pilot_issuer_self_v1(text)
 FROM PUBLIC,anon,authenticated;

-- A code is not addressed to a particular Person when created.
-- Store ONLY SHA-256 of a uniformly random 244-bit token. The original token
-- is returned ONCE to the signed issuer in that initial RPC; never stored.
CREATE TABLE titus.course_authoring_pilot_codes(
 code_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_hash text NOT NULL UNIQUE CHECK(
   code_hash ~ '^[0-9a-f]{64}$'),
 issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 issuer_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 issuer_responsibility_id uuid NOT NULL
  REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(issuer_person_entity_id,request_id)
);
CREATE TABLE titus.course_authoring_pilot_code_claims(
 claim_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_id uuid NOT NULL UNIQUE REFERENCES
   titus.course_authoring_pilot_codes(code_id) ON DELETE RESTRICT,
 claimed_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 claimed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(claimed_by_person_entity_id,request_id)
);
CREATE TABLE titus.course_authoring_pilot_code_cancellations(
 cancellation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_id uuid NOT NULL UNIQUE REFERENCES
  titus.course_authoring_pilot_codes(code_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 cancelled_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 issuer_responsibility_id uuid NOT NULL REFERENCES
  reality.responsibility_relations(id) ON DELETE RESTRICT,
 cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(cancelled_by_person_entity_id,request_id)
);
ALTER TABLE titus.course_authoring_pilot_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.course_authoring_pilot_code_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.course_authoring_pilot_code_cancellations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.course_authoring_pilot_codes,
 titus.course_authoring_pilot_code_claims,
 titus.course_authoring_pilot_code_cancellations
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION titus.reject_pilot_original_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Titus pilot code, claim or cancellation cannot be rewritten'
  USING ERRCODE='55000';
END $immutable$;
REVOKE ALL ON FUNCTION titus.reject_pilot_original_mutation_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER titus_pilot_code_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_codes
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();
CREATE TRIGGER titus_pilot_claim_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_code_claims
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();
CREATE TRIGGER titus_pilot_cancel_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_code_cancellations
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();

-- A signed, source-authorized platform issuer creates a bearer code. No
-- recipient Person exists or is chosen here. No license is created yet.
CREATE FUNCTION public.titus_private_pilot_code_issue_self_api_v1(
 p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $issue$
DECLARE v_person uuid;v_auth uuid;v_authority uuid;
 v_old titus.course_authoring_pilot_codes%ROWTYPE;
 v_code text;v_hash text;v_id uuid;
BEGIN
 IF p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact pilot code issuance request required'
   USING ERRCODE='22023';
 END IF;
 v_authority:=titus.require_current_pilot_issuer_self_v1('issue_pilot_code');
 v_person:=atlas.current_person_for_private_course_v1();
 v_auth:=auth.uid();
 SELECT * INTO v_old FROM titus.course_authoring_pilot_codes c
 WHERE c.issuer_person_entity_id=v_person AND c.request_id=p_request_id;
 IF v_old.code_id IS NOT NULL THEN
  IF v_old.issuer_auth_user_id IS DISTINCT FROM v_auth
    OR v_old.issuer_responsibility_id IS DISTINCT FROM v_authority THEN
   RAISE EXCEPTION 'pilot issuance retry had changed authority'
    USING ERRCODE='23505'; END IF;
  -- Never reveal a bearer secret again on replay.
  RETURN jsonb_build_object('contractVersion','titus_pilot_code_issue_v1',
   'codeId',v_old.code_id,'alreadyExists',true,'secretAvailable',false);
 END IF;
 v_code:='TITUS-'||
  upper(replace(gen_random_uuid()::text,'-','')||
        replace(gen_random_uuid()::text,'-',''));
 v_hash:=encode(sha256(convert_to(v_code,'UTF8')),'hex');
 INSERT INTO titus.course_authoring_pilot_codes(
  code_hash,issuer_person_entity_id,issuer_auth_user_id,
  issuer_responsibility_id,request_id)
 VALUES(v_hash,v_person,v_auth,v_authority,p_request_id)
 RETURNING code_id INTO v_id;
 -- One-time secret: transmit only through the actual signed response,
 -- never write it into table, event log, URL, analytics or debug output.
 RETURN jsonb_build_object('contractVersion','titus_pilot_code_issue_v1',
  'codeId',v_id,'code',v_code,
  'alreadyExists',false,'secretAvailable',true,
  'grantActive',false,'claimCapacity',1);
END $issue$;

-- A transferable bearer may be passed before claim. Its *actual* first
-- claimant must be a current independently signed canonical Reality Person.
-- Lock exact code row to serialize competing simultaneous claims/cancels;
-- a consumed or cancelled bearer can never mint a second license.
CREATE FUNCTION public.titus_private_pilot_code_claim_self_api_v1(
 p_code text,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $claim$
DECLARE v_person uuid;v_code titus.course_authoring_pilot_codes%ROWTYPE;
 v_old titus.course_authoring_pilot_code_claims%ROWTYPE;v_hash text;
BEGIN
 IF p_request_id IS NULL OR p_code IS NULL OR
 p_code !~ '^TITUS-[A-F0-9]{64}$' THEN
  RAISE EXCEPTION 'valid Titus pilot code required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 v_hash:=encode(sha256(convert_to(p_code,'UTF8')),'hex');
 SELECT * INTO v_code FROM titus.course_authoring_pilot_codes c
 WHERE c.code_hash=v_hash FOR UPDATE;
 IF v_code.code_id IS NULL THEN
  RAISE EXCEPTION 'unavailable pilot code' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.course_authoring_pilot_code_claims x
 WHERE x.code_id=v_code.code_id;
 IF v_old.claim_id IS NOT NULL THEN
  IF v_old.claimed_by_person_entity_id IS DISTINCT FROM v_person
  OR v_old.request_id IS DISTINCT FROM p_request_id THEN
   RAISE EXCEPTION 'pilot code already claimed'
    USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_pilot_code_claim_v1',
   'codeId',v_code.code_id,'alreadyExists',true,
   'grantActive',titus.authoring_grant_current_active_v1(v_person));
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_pilot_code_cancellations x
   WHERE x.code_id=v_code.code_id) OR v_person=v_code.issuer_person_entity_id THEN
  RAISE EXCEPTION 'unavailable pilot code' USING ERRCODE='42501'; END IF;
 -- Issuer may have delegated/ceased authority since creating code.
 IF NOT EXISTS(
  SELECT 1 FROM reality.responsibility_relations r
  WHERE r.id=v_code.issuer_responsibility_id
   AND r.carrier_person_entity_id=v_code.issuer_person_entity_id
   AND r.responsibility_key='titus_private_pilot_issuance'
   AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
   AND r.relation_state='active'
   AND r.began_at<=clock_timestamp()
   AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
   AND 'issue_pilot_code'=ANY(r.permitted_operations)
   AND EXISTS(
    SELECT 1 FROM reality.auth_person_bindings b
    JOIN reality.entities issuer ON issuer.id=b.person_entity_id
    WHERE b.auth_user_id=v_code.issuer_auth_user_id
     AND b.person_entity_id=v_code.issuer_person_entity_id
     AND b.binding_state='active' AND b.retired_at IS NULL
     AND issuer.entity_kind='person' AND issuer.identity_state='canonical')
 ) THEN
  RAISE EXCEPTION 'pilot code issuer is no longer authorized'
   USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_access_grants g
   WHERE g.person_entity_id=v_person) THEN
  RAISE EXCEPTION 'Person already has Titus product grant'
   USING ERRCODE='23505'; END IF;
 INSERT INTO titus.course_authoring_pilot_code_claims(
  code_id,claimed_by_person_entity_id,request_id)
 VALUES(v_code.code_id,v_person,p_request_id);
 INSERT INTO titus.course_authoring_access_grants(
  person_entity_id,grant_source_auth_user_id,grant_kind,
  grant_source_receipt,state,granted_at,valid_until)
 VALUES(v_person,v_code.issuer_auth_user_id,'private_pilot',
  'pilotcode:'||v_code.code_id::text,'active',clock_timestamp(),NULL);
 RETURN jsonb_build_object('contractVersion','titus_pilot_code_claim_v1',
  'codeId',v_code.code_id,'alreadyExists',false,
  'grantActive',titus.authoring_grant_current_active_v1(v_person));
END $claim$;

-- A distinct currently authorized platform admin may cancel an unclaimed
-- code. This is an append-only event, not a mutable expiration field.
CREATE FUNCTION public.titus_private_pilot_code_cancel_self_api_v1(
 p_code_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $cancel$
DECLARE v_actor uuid;v_authority uuid;
 v_code titus.course_authoring_pilot_codes%ROWTYPE;
 v_old titus.course_authoring_pilot_code_cancellations%ROWTYPE;
BEGIN
 IF p_code_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact code cancellation required' USING ERRCODE='22023'; END IF;
 v_authority:=titus.require_current_pilot_issuer_self_v1('revoke_pilot_code');
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_code FROM titus.course_authoring_pilot_codes c
 WHERE c.code_id=p_code_id FOR UPDATE;
 IF v_code.code_id IS NULL THEN
  RAISE EXCEPTION 'known pilot code required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.course_authoring_pilot_code_cancellations x
 WHERE x.code_id=p_code_id;
 IF v_old.cancellation_id IS NOT NULL THEN
  IF v_old.cancelled_by_person_entity_id IS DISTINCT FROM v_actor
  OR v_old.request_id IS DISTINCT FROM p_request_id THEN
   RAISE EXCEPTION 'changed code cancellation replay'
    USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_pilot_code_cancel_v1',
   'codeId',p_code_id,'alreadyExists',true);
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_pilot_code_claims x
   WHERE x.code_id=p_code_id) THEN
  RAISE EXCEPTION 'claimed pilot code cannot be cancelled'
   USING ERRCODE='23514'; END IF;
 INSERT INTO titus.course_authoring_pilot_code_cancellations(
  code_id,request_id,cancelled_by_person_entity_id,issuer_responsibility_id)
 VALUES(p_code_id,p_request_id,v_actor,v_authority);
 RETURN jsonb_build_object('contractVersion','titus_pilot_code_cancel_v1',
  'codeId',p_code_id,'alreadyExists',false);
END $cancel$;

-- No automatic expiration on an accepted pilot. Ending it is a deliberate
-- source-audited, independently authorized Titus administrator operation.
CREATE FUNCTION public.titus_private_pilot_access_end_self_api_v1(
 p_grantee_person uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $end_pilot$
DECLARE v_actor uuid;v_authority uuid;
 v_grant titus.course_authoring_access_grants%ROWTYPE;
 v_old titus.course_authoring_access_status_events%ROWTYPE;
BEGIN
 IF p_grantee_person IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact administrator pilot end decision required'
   USING ERRCODE='22023'; END IF;
 v_authority:=titus.require_current_pilot_issuer_self_v1('end_pilot_access');
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_grant FROM titus.course_authoring_access_grants g
 WHERE g.person_entity_id=p_grantee_person FOR UPDATE;
 IF v_grant.person_entity_id IS NULL
 OR v_grant.grant_kind IS DISTINCT FROM 'private_pilot'
 OR v_grant.grant_source_receipt NOT LIKE 'pilotcode:%'
 THEN RAISE EXCEPTION 'original claimed pilot grant required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.course_authoring_access_status_events e
 WHERE e.person_entity_id=p_grantee_person AND e.request_id=p_request_id;
 IF v_old.event_seq IS NOT NULL THEN
  IF v_old.next_state IS DISTINCT FROM 'revoked' OR
    v_old.recorded_by_auth_user_id IS DISTINCT FROM auth.uid() THEN
   RAISE EXCEPTION 'changed pilot end replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_pilot_access_end_v1',
   'ended',true,'alreadyExists',true);
 END IF;
 INSERT INTO titus.course_authoring_access_status_events(
  person_entity_id,request_id,next_state,source_evidence_receipt,
  recorded_by_auth_user_id)
 VALUES(p_grantee_person,p_request_id,'revoked',
  'pilotend:'||p_request_id::text,auth.uid());
 RETURN jsonb_build_object('contractVersion','titus_pilot_access_end_v1',
  'ended',true,'alreadyExists',false);
END $end_pilot$;

REVOKE ALL ON FUNCTION
 public.titus_private_pilot_code_issue_self_api_v1(uuid),
 public.titus_private_pilot_code_claim_self_api_v1(text,uuid),
 public.titus_private_pilot_code_cancel_self_api_v1(uuid,uuid),
 public.titus_private_pilot_access_end_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.titus_private_pilot_code_issue_self_api_v1(uuid),
 public.titus_private_pilot_code_claim_self_api_v1(text,uuid),
 public.titus_private_pilot_code_cancel_self_api_v1(uuid,uuid),
 public.titus_private_pilot_access_end_self_api_v1(uuid,uuid)
 TO authenticated;
-- Paid purchase, free trial, actual license issuer, organizational license,
-- post-license read/export, rate-limit/claim capacity, browser delivery,
-- protected GoTrue signed proof and production release are all STILL HELD.
