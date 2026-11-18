-- HELD M1.1: signed, separately source-authorized PRIVATE PILOT offer
-- and the recipient's independent acceptance. Universal/empty-first Titus.
-- Candidate ONLY; use fictional PG17 / approved protected clone.
-- NO production migration, default customers, paid-purchase claim,
-- automatically licensed login, Course, institution, or curriculum.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('reality.responsibility_relations') IS NULL
 OR to_regclass('titus.course_authoring_access_grants') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 THEN RAISE EXCEPTION 'held Titus private-pilot source prerequisites missing'
  USING ERRCODE='42501';
 END IF;
END $preflight$;

-- This operation *does not create issuer standing*. Responsibility for
-- Titus product pilot issue MUST be independently established in Reality.
-- There is currently NO live responsibility with this exact key.
CREATE FUNCTION titus.require_current_pilot_issuer_self_v1()
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $issuer$
DECLARE v_person uuid;v_ids uuid[];
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT array_agg(r.id) INTO v_ids
 FROM reality.responsibility_relations r
 WHERE r.carrier_person_entity_id=v_person
  AND r.responsibility_key='titus_private_pilot_issuance'
  AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
  AND r.relation_state='active'
  AND r.began_at<=clock_timestamp()
  AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
  AND 'issue_pilot_offer'=ANY(r.permitted_operations);
 IF COALESCE(array_length(v_ids,1),0)<>1 THEN
  RAISE EXCEPTION 'one current separately established Titus pilot issuer required'
    USING ERRCODE='42501';
 END IF;
 RETURN v_ids[1];
END $issuer$;
REVOKE ALL ON FUNCTION titus.require_current_pilot_issuer_self_v1()
 FROM PUBLIC,anon,authenticated;

CREATE TABLE titus.course_authoring_pilot_offers (
 offer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 recipient_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 issuer_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 issuer_responsibility_id uuid NOT NULL
  REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 offered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 accept_by timestamptz NOT NULL,
 grant_valid_until timestamptz NOT NULL,
 UNIQUE(issuer_person_entity_id,request_id),
 UNIQUE(recipient_person_entity_id),
 CHECK(recipient_person_entity_id<>issuer_person_entity_id),
 CHECK(accept_by>offered_at),
 CHECK(grant_valid_until>accept_by)
);
CREATE TABLE titus.course_authoring_pilot_responses (
 response_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 offer_id uuid NOT NULL UNIQUE REFERENCES titus.course_authoring_pilot_offers(offer_id)
  ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 recipient_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 decision text NOT NULL CHECK(decision IN ('accept','decline')),
 responded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(recipient_person_entity_id,request_id)
);
ALTER TABLE titus.course_authoring_pilot_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.course_authoring_pilot_responses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.course_authoring_pilot_offers FROM PUBLIC,anon,authenticated;
REVOKE ALL ON titus.course_authoring_pilot_responses FROM PUBLIC,anon,authenticated;

CREATE FUNCTION titus.reject_pilot_original_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Titus pilot offer and response originals are immutable'
  USING ERRCODE='55000';
END $immutable$;
REVOKE ALL ON FUNCTION titus.reject_pilot_original_mutation_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER titus_pilot_offer_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_offers
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();
CREATE TRIGGER titus_pilot_response_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_responses
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();

-- A current independently authorized issuer offers a *pilot*, never a
-- purchase, Course entitlement, or access to another Person's materials.
CREATE FUNCTION public.titus_private_pilot_offer_self_api_v1(
 p_recipient_person uuid,p_request_id uuid,
 p_accept_by timestamptz,p_grant_valid_until timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $offer$
DECLARE v_issuer uuid;v_auth uuid;v_standing uuid;
 v_existing titus.course_authoring_pilot_offers%ROWTYPE;v_id uuid;
BEGIN
 IF p_recipient_person IS NULL OR p_request_id IS NULL
 OR p_accept_by IS NULL OR p_accept_by<=clock_timestamp()
 OR p_grant_valid_until IS NULL OR p_grant_valid_until<=p_accept_by THEN
  RAISE EXCEPTION 'exact bounded Titus pilot offer required'
   USING ERRCODE='22023';
 END IF;
 v_standing:=titus.require_current_pilot_issuer_self_v1();
 v_issuer:=atlas.current_person_for_private_course_v1();
 v_auth:=auth.uid();
 IF p_recipient_person=v_issuer OR NOT EXISTS(
  SELECT 1 FROM reality.entities e WHERE e.id=p_recipient_person
   AND e.entity_kind='person' AND e.identity_state='canonical') THEN
  RAISE EXCEPTION 'distinct canonical recipient required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_existing FROM titus.course_authoring_pilot_offers o
 WHERE o.issuer_person_entity_id=v_issuer AND o.request_id=p_request_id;
 IF v_existing.offer_id IS NOT NULL THEN
  IF v_existing.recipient_person_entity_id IS DISTINCT FROM p_recipient_person
  OR v_existing.accept_by IS DISTINCT FROM p_accept_by
  OR v_existing.grant_valid_until IS DISTINCT FROM p_grant_valid_until
  OR v_existing.issuer_auth_user_id IS DISTINCT FROM v_auth THEN
   RAISE EXCEPTION 'changed pilot offer replay' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','titus_private_pilot_offer_v1',
   'offerId',v_existing.offer_id,'alreadyExists',true,'grantActive',false);
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_access_grants g
    WHERE g.person_entity_id=p_recipient_person) THEN
  RAISE EXCEPTION 'existing Titus grant cannot be replaced by pilot offer'
    USING ERRCODE='23505';
 END IF;
 INSERT INTO titus.course_authoring_pilot_offers(
  recipient_person_entity_id,issuer_person_entity_id,issuer_auth_user_id,
  issuer_responsibility_id,request_id,accept_by,grant_valid_until)
 VALUES(p_recipient_person,v_issuer,v_auth,v_standing,p_request_id,
  p_accept_by,p_grant_valid_until)
 RETURNING offer_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','titus_private_pilot_offer_v1',
  'offerId',v_id,'alreadyExists',false,'grantActive',false);
END $offer$;

-- A known exact recipient may read only this offered pilot's status.
-- No customer roster or other Person's offer can be enumerated.
CREATE FUNCTION public.titus_private_pilot_offer_read_self_api_v1(p_offer_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $read$
DECLARE v_person uuid;v_offer titus.course_authoring_pilot_offers%ROWTYPE;
 v_decision text;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_offer FROM titus.course_authoring_pilot_offers o
 WHERE o.offer_id=p_offer_id AND o.recipient_person_entity_id=v_person;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'own pilot offer required' USING ERRCODE='42501';
 END IF;
 SELECT r.decision INTO v_decision FROM titus.course_authoring_pilot_responses r
 WHERE r.offer_id=v_offer.offer_id;
 RETURN jsonb_build_object('contractVersion','titus_private_pilot_offer_read_v1',
  'offerId',v_offer.offer_id,'purpose','Titus authoring pilot',
  'state',COALESCE(v_decision,CASE
    WHEN v_offer.accept_by<=clock_timestamp() THEN 'expired'
    ELSE 'offered' END),
  'acceptBy',v_offer.accept_by,'grantValidUntil',v_offer.grant_valid_until,
  'grantActive',titus.authoring_grant_current_active_v1(v_person));
END $read$;

-- Only the actual recipient can accept; a separate Reality issuer must
-- still be current. One acceptance inserts the single existing source-owned
-- authoring grant, with its original receipt tied to this exact offer UUID.
CREATE FUNCTION public.titus_private_pilot_respond_self_api_v1(
 p_offer_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $respond$
DECLARE v_person uuid;v_offer titus.course_authoring_pilot_offers%ROWTYPE;
 v_old titus.course_authoring_pilot_responses%ROWTYPE;
BEGIN
 IF p_offer_id IS NULL OR p_request_id IS NULL OR
 p_decision IS NULL OR p_decision NOT IN ('accept','decline') THEN
  RAISE EXCEPTION 'exact recipient pilot decision required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_offer FROM titus.course_authoring_pilot_offers o
 WHERE o.offer_id=p_offer_id AND o.recipient_person_entity_id=v_person
 FOR UPDATE;
 IF v_offer.offer_id IS NULL THEN
  RAISE EXCEPTION 'own pilot offer required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_old FROM titus.course_authoring_pilot_responses r
 WHERE r.offer_id=v_offer.offer_id;
 IF v_old.response_id IS NOT NULL THEN
  IF v_old.recipient_person_entity_id IS DISTINCT FROM v_person OR
     v_old.request_id IS DISTINCT FROM p_request_id OR
     v_old.decision IS DISTINCT FROM p_decision THEN
   RAISE EXCEPTION 'pilot response is terminal' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','titus_private_pilot_response_v1',
   'offerId',v_offer.offer_id,'decision',p_decision,'alreadyExists',true,
   'grantActive',titus.authoring_grant_current_active_v1(v_person));
 END IF;
 IF v_offer.accept_by<=clock_timestamp() THEN
  RAISE EXCEPTION 'current pilot offer required' USING ERRCODE='42501';
 END IF;
 IF p_decision='accept' AND NOT EXISTS(
  SELECT 1 FROM reality.responsibility_relations r
  WHERE r.id=v_offer.issuer_responsibility_id
   AND r.carrier_person_entity_id=v_offer.issuer_person_entity_id
   AND r.responsibility_key='titus_private_pilot_issuance'
   AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
   AND r.relation_state='active'
   AND r.began_at<=clock_timestamp()
   AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
   AND 'issue_pilot_offer'=ANY(r.permitted_operations)
 ) THEN
  RAISE EXCEPTION 'pilot issuer standing no longer current'
   USING ERRCODE='42501';
 END IF;
 IF p_decision='accept' AND EXISTS(SELECT 1
  FROM titus.course_authoring_access_grants g
  WHERE g.person_entity_id=v_person) THEN
  RAISE EXCEPTION 'Person already has a Titus grant original'
   USING ERRCODE='23505';
 END IF;
 INSERT INTO titus.course_authoring_pilot_responses(
  offer_id,request_id,recipient_person_entity_id,decision)
 VALUES(p_offer_id,p_request_id,v_person,p_decision);
 IF p_decision='accept' THEN
  INSERT INTO titus.course_authoring_access_grants(
   person_entity_id,grant_source_auth_user_id,grant_kind,
   grant_source_receipt,state,granted_at,valid_until)
  VALUES(v_person,v_offer.issuer_auth_user_id,'private_pilot',
   'pilot:'||v_offer.offer_id::text,'active',clock_timestamp(),
   v_offer.grant_valid_until);
 END IF;
 RETURN jsonb_build_object('contractVersion','titus_private_pilot_response_v1',
  'offerId',v_offer.offer_id,'decision',p_decision,'alreadyExists',false,
  'grantActive',titus.authoring_grant_current_active_v1(v_person));
END $respond$;

REVOKE ALL ON FUNCTION
 public.titus_private_pilot_offer_self_api_v1(uuid,uuid,timestamptz,timestamptz),
 public.titus_private_pilot_offer_read_self_api_v1(uuid),
 public.titus_private_pilot_respond_self_api_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.titus_private_pilot_offer_self_api_v1(uuid,uuid,timestamptz,timestamptz),
 public.titus_private_pilot_offer_read_self_api_v1(uuid),
 public.titus_private_pilot_respond_self_api_v1(uuid,uuid,text)
 TO authenticated;

-- No real product-issuer responsibility exists today. Nobody is granted it.
-- Recipient-discovery/delivery and purchase/billing are held separately.
