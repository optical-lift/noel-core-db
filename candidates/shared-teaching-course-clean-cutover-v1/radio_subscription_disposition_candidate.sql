-- HELD addressed subscription disposition. No billing, real issuer or seed.
-- Same native Ledger and canonical signed Person as the other Radio commands.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('titus.radio_subscription_offers_v1') IS NULL
 THEN RAISE EXCEPTION 'held Radio acceptance prerequisites missing' USING ERRCODE='42501'; END IF;
END $preflight$;
CREATE TABLE titus.radio_subscription_offer_cancellations_v1 (
 offer_id uuid PRIMARY KEY REFERENCES titus.radio_subscription_offers_v1(offer_id),
 issuer_id uuid NOT NULL REFERENCES reality.entities(id),
 request_id uuid NOT NULL,
 cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(issuer_id,request_id)
);
ALTER TABLE titus.radio_subscription_offer_cancellations_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.radio_subscription_offer_cancellations_v1 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER immutable_original BEFORE UPDATE OR DELETE ON titus.radio_subscription_offer_cancellations_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();

CREATE FUNCTION public.titus_radio_accept_subscription_self_api_v1(p_offer_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $accept$
DECLARE actor uuid; o titus.radio_subscription_offers_v1%ROWTYPE;
 prior titus.radio_subscription_acceptances_v1%ROWTYPE;
 institution uuid; admissions uuid[]; authorities uuid[]; result uuid; at_time timestamptz;
BEGIN
 IF p_offer_id IS NULL OR p_request_id IS NULL THEN
 RAISE EXCEPTION 'exact acceptance required' USING ERRCODE='22023'; END IF;
 actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO o FROM titus.radio_subscription_offers_v1 WHERE offer_id=p_offer_id AND recipient_id=actor;
 IF o.offer_id IS NULL THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 -- All disposition commands lock Ledger first. Never impersonate issuer.
 SELECT l.subject_entity_id INTO institution FROM ledger.ledgers l JOIN reality.entities e ON e.id=l.subject_entity_id
 WHERE l.id=o.ledger_id AND l.ledger_state='active' AND l.retired_at IS NULL
 AND e.identity_state='canonical' AND e.entity_kind IN ('business','organization') FOR UPDATE OF l;
 IF institution IS NULL THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 SELECT array_agg(x.admission_id) INTO admissions FROM (
  SELECT a.admission_id FROM titus.institution_account_admissions_v1 a
  WHERE a.ledger_id=o.ledger_id AND a.institution_entity_id=institution AND a.person_entity_id=o.issuer_id
  AND a.accepted_at<=clock_timestamp() AND NOT EXISTS (
   SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w WHERE w.admission_id=a.admission_id AND w.ended_at<=clock_timestamp())
  FOR UPDATE
 ) x;
 IF cardinality(admissions) IS DISTINCT FROM 1 OR EXISTS(
 SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w WHERE w.admission_id=admissions[1] AND w.ended_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 SELECT array_agg(x.id) INTO authorities FROM (
 SELECT r.id FROM reality.responsibility_relations r
 WHERE r.carrier_person_entity_id=o.issuer_id AND r.responsibility_key='institution_publication_management'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=institution AND r.jurisdiction_domain IS NULL
 AND r.scope=jsonb_build_object('ledgerId',o.ledger_id::text)
 AND r.relation_state='active' AND r.ended_at IS NULL AND r.began_at<=clock_timestamp()
 AND 'offer_subscription'=ANY(r.permitted_operations) FOR SHARE
 ) x;
 IF cardinality(authorities) IS DISTINCT FROM 1 OR authorities[1] IS DISTINCT FROM o.issuer_responsibility_id
 OR reality.resolve_responsibility_relation_v1(o.issuer_id,'institution_publication_management','offer_subscription','entity',
 institution,NULL,jsonb_build_object('ledgerId',o.ledger_id::text)) IS DISTINCT FROM o.issuer_responsibility_id
 THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM titus.radio_subscription_offers_v1 WHERE offer_id=p_offer_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM titus.radio_subscription_offer_cancellations_v1 WHERE offer_id=p_offer_id)
 THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 at_time:=clock_timestamp();
 PERFORM 1 FROM titus.radio_stations_v1 WHERE station_id=o.station_id AND ledger_id=o.ledger_id AND retired_at IS NULL AND established_at<=at_time FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 IF o.program_id IS NOT NULL THEN
 PERFORM 1 FROM titus.radio_programs_v1 WHERE program_id=o.program_id AND station_id=o.station_id AND retired_at IS NULL AND established_at<=at_time FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF; END IF;
 IF o.membership_id IS NOT NULL THEN
 PERFORM 1 FROM titus.library_memberships_v1 m WHERE m.membership_id=o.membership_id AND m.person_id=actor AND m.ledger_id=o.ledger_id
 AND m.accepted_at<=at_time AND (m.valid_until IS NULL OR m.valid_until>at_time) FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM titus.library_membership_endings_v1 e WHERE e.membership_id=o.membership_id AND e.ended_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF; END IF;
 SELECT * INTO prior FROM titus.radio_subscription_acceptances_v1 WHERE offer_id=p_offer_id;
 IF prior.offer_id IS NOT NULL THEN
 IF prior.recipient_id IS DISTINCT FROM actor OR prior.request_id IS DISTINCT FROM p_request_id
 THEN RAISE EXCEPTION 'conflicting acceptance' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM titus.radio_subscription_endings_v1 WHERE subscription_id=prior.subscription_id AND ended_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'subscription ended' USING ERRCODE='42501'; END IF;
 result:=prior.subscription_id;
 ELSE
 -- Recheck signed recipient before creating the original.
 IF atlas.current_person_for_private_course_v1() IS DISTINCT FROM actor THEN
 RAISE EXCEPTION 'recipient changed' USING ERRCODE='42501'; END IF;
 INSERT INTO titus.radio_subscriptions_v1(station_id,ledger_id,program_id,person_id,membership_id,issuer_person_id,source_receipt,accepted_at)
 VALUES(o.station_id,o.ledger_id,o.program_id,actor,o.membership_id,o.issuer_id,'radio-offer:'||o.offer_id::text,clock_timestamp())
 RETURNING subscription_id INTO result;
 INSERT INTO titus.radio_subscription_acceptances_v1 VALUES(o.offer_id,actor,p_request_id,result);
 END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_subscription_accept_v1','subscriptionId',result,'alreadyExists',prior.offer_id IS NOT NULL);
END $accept$;

CREATE FUNCTION public.titus_radio_cancel_subscription_offer_self_api_v1(p_offer_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $cancel$
DECLARE actor uuid; o titus.radio_subscription_offers_v1%ROWTYPE; standing jsonb;
 prior titus.radio_subscription_offer_cancellations_v1%ROWTYPE;
BEGIN
 IF p_offer_id IS NULL OR p_request_id IS NULL THEN RAISE EXCEPTION 'exact cancellation required' USING ERRCODE='22023'; END IF;
 actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO o FROM titus.radio_subscription_offers_v1 WHERE offer_id=p_offer_id AND issuer_id=actor;
 IF o.offer_id IS NULL THEN RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 standing:=titus.require_radio_operator_self_v1(o.ledger_id,'offer_subscription');
 IF (standing->>'responsibilityId')::uuid IS DISTINCT FROM o.issuer_responsibility_id THEN
 RAISE EXCEPTION 'offer unavailable' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM titus.radio_subscription_offers_v1 WHERE offer_id=p_offer_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM titus.radio_subscription_acceptances_v1 WHERE offer_id=p_offer_id)
 THEN RAISE EXCEPTION 'accepted offer requires subscription termination' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM titus.radio_subscription_offer_cancellations_v1 WHERE offer_id=p_offer_id;
 IF prior.offer_id IS NOT NULL THEN
 IF prior.issuer_id IS DISTINCT FROM actor OR prior.request_id IS DISTINCT FROM p_request_id
 THEN RAISE EXCEPTION 'conflicting cancellation' USING ERRCODE='23505'; END IF;
 ELSE INSERT INTO titus.radio_subscription_offer_cancellations_v1(offer_id,issuer_id,request_id) VALUES(p_offer_id,actor,p_request_id);
 END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_subscription_cancel_v1','offerId',p_offer_id,'alreadyExists',prior.offer_id IS NOT NULL);
END $cancel$;
REVOKE ALL ON FUNCTION public.titus_radio_accept_subscription_self_api_v1(uuid,uuid),
 public.titus_radio_cancel_subscription_offer_self_api_v1(uuid,uuid) FROM PUBLIC,anon,authenticated;
DO $acl$
BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
 EXECUTE 'REVOKE ALL ON titus.radio_subscription_offer_cancellations_v1 FROM service_role';
 EXECUTE 'REVOKE ALL ON FUNCTION public.titus_radio_accept_subscription_self_api_v1(uuid,uuid), public.titus_radio_cancel_subscription_offer_self_api_v1(uuid,uuid) FROM service_role';
 END IF;
END $acl$;
GRANT EXECUTE ON FUNCTION public.titus_radio_accept_subscription_self_api_v1(uuid,uuid),
 public.titus_radio_cancel_subscription_offer_self_api_v1(uuid,uuid) TO authenticated;
