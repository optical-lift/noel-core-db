-- HELD station and addressed subscription command candidate, scratch only.
-- Reuses U1 native Ledger, current Person and exact Reality responsibility.
-- No issuer grant, billing, source promotion or seeded station/subscriber.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('titus.radio_stations_v1') IS NULL
 OR to_regprocedure('titus.require_current_account_context_self_v1(text,uuid)') IS NULL
 THEN RAISE EXCEPTION 'held Radio command prerequisites missing' USING ERRCODE='42501'; END IF;
END $preflight$;
CREATE FUNCTION titus.require_radio_operator_self_v1(p_ledger_id uuid,p_operation text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog AS $publisher$
DECLARE v_context jsonb; v_person uuid; v_institution uuid;
 v_admissions uuid[]; v_responsibilities uuid[]; v_resolved uuid;
BEGIN
 IF p_ledger_id IS NULL OR p_operation IS NULL OR p_operation NOT IN ('establish_station','establish_program','offer_subscription') THEN
  RAISE EXCEPTION 'exact institutional publishing scope required' USING ERRCODE='42501';
 END IF;
 -- Same native Ledger and current Person context as U1. No supplied actor.
 v_context:=titus.require_current_account_context_self_v1('institution',p_ledger_id);
 v_person:=(v_context->>'personId')::uuid;
 v_institution:=(v_context->>'institutionId')::uuid;
 -- Lock Ledger first, then admission (withdrawal locks admission), then
 -- operation-specific responsibility. Final integrated concurrency proof
 -- must include all grant/rights/withdrawal writers, not just this probe.
 PERFORM 1 FROM ledger.ledgers l
 WHERE l.id=p_ledger_id AND l.subject_entity_id=v_institution
 AND l.ledger_state='active' AND l.retired_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active publication Ledger required' USING ERRCODE='42501'; END IF;
 SELECT array_agg(x.admission_id) INTO v_admissions FROM (
  SELECT a.admission_id FROM titus.institution_account_admissions_v1 a
  WHERE a.person_entity_id=v_person AND a.ledger_id=p_ledger_id
  AND a.institution_entity_id=v_institution AND a.accepted_at<=clock_timestamp()
  AND NOT EXISTS (SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
    WHERE w.admission_id=a.admission_id AND w.ended_at<=clock_timestamp())
  FOR UPDATE
 ) x;
 IF cardinality(v_admissions) IS DISTINCT FROM 1
 OR titus.require_current_account_context_self_v1('institution',p_ledger_id) IS DISTINCT FROM v_context
 THEN RAISE EXCEPTION 'institutional admission changed' USING ERRCODE='42501'; END IF;
 -- Proposed neutral responsibility key; source issuance is not implemented.
 SELECT array_agg(x.id) INTO v_responsibilities FROM (
  SELECT r.id FROM reality.responsibility_relations r
  WHERE r.carrier_person_entity_id=v_person
   AND r.responsibility_key='institution_publication_management'
   AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=v_institution
   AND r.jurisdiction_domain IS NULL
   AND r.scope=jsonb_build_object('ledgerId',p_ledger_id::text)
   AND r.relation_state='active' AND r.ended_at IS NULL
   AND r.began_at<=clock_timestamp() AND p_operation=ANY(r.permitted_operations)
  FOR SHARE
 ) x;
 IF cardinality(v_responsibilities) IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'exact current publishing responsibility required' USING ERRCODE='42501';
 END IF;
 v_resolved:=reality.resolve_responsibility_relation_v1(
  v_person,'institution_publication_management',p_operation,'entity',v_institution,
  NULL,jsonb_build_object('ledgerId',p_ledger_id::text));
 IF v_resolved IS DISTINCT FROM v_responsibilities[1] THEN
  RAISE EXCEPTION 'canonical publishing responsibility mismatch' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('contractVersion','radio_operator_standing_v1',
  'personId',v_person,'institutionId',v_institution,'ledgerId',p_ledger_id,
  'admissionId',v_admissions[1],'responsibilityId',v_resolved,
  'publicationApproved',false);
END $publisher$;

REVOKE ALL ON FUNCTION titus.require_radio_operator_self_v1(uuid,text) FROM PUBLIC,anon,authenticated;
CREATE TABLE titus.radio_establishment_receipts_v1 (
 actor_id uuid NOT NULL REFERENCES reality.entities(id),
 request_id uuid NOT NULL,
 responsibility_id uuid NOT NULL REFERENCES reality.responsibility_relations(id),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 station_id uuid NOT NULL REFERENCES titus.radio_stations_v1(station_id),
 program_id uuid REFERENCES titus.radio_programs_v1(program_id),
 title text NOT NULL,
 PRIMARY KEY(actor_id,request_id)
);
CREATE TABLE titus.radio_subscription_offers_v1 (
 offer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 issuer_id uuid NOT NULL REFERENCES reality.entities(id),
 issuer_responsibility_id uuid NOT NULL REFERENCES reality.responsibility_relations(id),
 recipient_id uuid NOT NULL REFERENCES reality.entities(id),
 ledger_id uuid NOT NULL,
 station_id uuid NOT NULL,
 program_id uuid,
 membership_id uuid,
 request_id uuid NOT NULL,
 offered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(issuer_id,request_id),
 FOREIGN KEY(station_id,ledger_id) REFERENCES titus.radio_stations_v1(station_id,ledger_id),
 FOREIGN KEY(program_id,station_id) REFERENCES titus.radio_programs_v1(program_id,station_id),
 FOREIGN KEY(membership_id,ledger_id,recipient_id) REFERENCES titus.library_memberships_v1(membership_id,ledger_id,person_id)
);
CREATE TABLE titus.radio_subscription_acceptances_v1 (
 offer_id uuid PRIMARY KEY REFERENCES titus.radio_subscription_offers_v1(offer_id),
 recipient_id uuid NOT NULL REFERENCES reality.entities(id),
 request_id uuid NOT NULL,
 subscription_id uuid NOT NULL UNIQUE REFERENCES titus.radio_subscriptions_v1(subscription_id),
 UNIQUE(recipient_id,request_id)
);
DO $private$
DECLARE n text;
BEGIN
 FOREACH n IN ARRAY ARRAY['radio_establishment_receipts_v1','radio_subscription_offers_v1','radio_subscription_acceptances_v1'] LOOP
 EXECUTE format('ALTER TABLE titus.%I ENABLE ROW LEVEL SECURITY',n);
 EXECUTE format('REVOKE ALL ON TABLE titus.%I FROM PUBLIC,anon,authenticated',n);
 EXECUTE format('CREATE TRIGGER immutable_original BEFORE UPDATE OR DELETE ON titus.%I FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1()',n);
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
 EXECUTE format('REVOKE ALL ON TABLE titus.%I FROM service_role',n);
 END IF;
 END LOOP;
END $private$;

CREATE FUNCTION public.titus_radio_establish_self_api_v1(p_ledger_id uuid,p_station_id uuid,p_title text,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $establish$
DECLARE a jsonb; actor uuid; authority uuid; prior titus.radio_establishment_receipts_v1%ROWTYPE;
 station uuid; program uuid;
BEGIN
 IF p_request_id IS NULL OR p_title IS NULL OR p_title<>btrim(p_title)
 OR length(p_title) NOT BETWEEN 1 AND 200 OR p_title~'[[:cntrl:]]'
 THEN RAISE EXCEPTION 'exact establishment intent required' USING ERRCODE='22023'; END IF;
 a:=titus.require_radio_operator_self_v1(p_ledger_id,CASE WHEN p_station_id IS NULL THEN 'establish_station' ELSE 'establish_program' END);
 actor:=(a->>'personId')::uuid; authority:=(a->>'responsibilityId')::uuid;
 IF p_station_id IS NOT NULL THEN
  PERFORM 1 FROM titus.radio_stations_v1 WHERE station_id=p_station_id AND ledger_id=p_ledger_id AND retired_at IS NULL FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'station unavailable' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT * INTO prior FROM titus.radio_establishment_receipts_v1 WHERE actor_id=actor AND request_id=p_request_id;
 IF prior.request_id IS NOT NULL THEN
  IF prior.ledger_id IS DISTINCT FROM p_ledger_id OR prior.responsibility_id IS DISTINCT FROM authority
  OR prior.title IS DISTINCT FROM p_title OR (p_station_id IS NULL AND prior.program_id IS NOT NULL)
  OR (p_station_id IS NOT NULL AND (prior.program_id IS NULL OR prior.station_id IS DISTINCT FROM p_station_id))
  THEN RAISE EXCEPTION 'conflicting establishment request' USING ERRCODE='23505'; END IF;
  station:=prior.station_id; program:=prior.program_id;
  PERFORM 1 FROM titus.radio_stations_v1 WHERE station_id=station AND ledger_id=p_ledger_id AND retired_at IS NULL FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'station unavailable' USING ERRCODE='42501'; END IF;
  IF program IS NOT NULL THEN
   PERFORM 1 FROM titus.radio_programs_v1 WHERE program_id=program AND station_id=station AND retired_at IS NULL FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'program unavailable' USING ERRCODE='42501'; END IF;
  END IF;
 ELSE
  IF p_station_id IS NULL THEN
   INSERT INTO titus.radio_stations_v1(ledger_id,title) VALUES(p_ledger_id,p_title) RETURNING station_id INTO station;
  ELSE
   station:=p_station_id;
   INSERT INTO titus.radio_programs_v1(station_id,title) VALUES(station,p_title) RETURNING program_id INTO program;
  END IF;
  INSERT INTO titus.radio_establishment_receipts_v1 VALUES(actor,p_request_id,authority,p_ledger_id,station,program,p_title);
 END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_establishment_v1','stationId',station,'programId',program,
  'alreadyExists',prior.request_id IS NOT NULL);
END $establish$;

CREATE FUNCTION public.titus_radio_offer_subscription_self_api_v1(p_ledger_id uuid,p_station_id uuid,p_program_id uuid,p_recipient_id uuid,p_membership_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $offer$
DECLARE a jsonb; actor uuid; authority uuid; prior titus.radio_subscription_offers_v1%ROWTYPE; result uuid;
BEGIN
 IF p_request_id IS NULL OR p_station_id IS NULL OR p_recipient_id IS NULL THEN
 RAISE EXCEPTION 'exact subscription offer required' USING ERRCODE='22023'; END IF;
 a:=titus.require_radio_operator_self_v1(p_ledger_id,'offer_subscription');
 actor:=(a->>'personId')::uuid; authority:=(a->>'responsibilityId')::uuid;
 PERFORM 1 FROM titus.radio_stations_v1 WHERE station_id=p_station_id AND ledger_id=p_ledger_id AND retired_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'station unavailable' USING ERRCODE='42501'; END IF;
 IF p_program_id IS NOT NULL THEN
 PERFORM 1 FROM titus.radio_programs_v1 WHERE program_id=p_program_id AND station_id=p_station_id AND retired_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'program unavailable' USING ERRCODE='42501'; END IF; END IF;
 IF NOT EXISTS(SELECT 1 FROM reality.entities WHERE id=p_recipient_id AND entity_kind='person' AND identity_state='canonical')
 THEN RAISE EXCEPTION 'canonical recipient required' USING ERRCODE='42501'; END IF;
 IF p_membership_id IS NOT NULL THEN
 PERFORM 1 FROM titus.library_memberships_v1 m WHERE m.membership_id=p_membership_id
 AND m.ledger_id=p_ledger_id AND m.person_id=p_recipient_id AND m.accepted_at<=clock_timestamp()
 AND (m.valid_until IS NULL OR m.valid_until>clock_timestamp())
 AND NOT EXISTS(SELECT 1 FROM titus.library_membership_endings_v1 e WHERE e.membership_id=m.membership_id AND e.ended_at<=clock_timestamp()) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'membership unavailable' USING ERRCODE='42501'; END IF; END IF;
 SELECT * INTO prior FROM titus.radio_subscription_offers_v1 WHERE issuer_id=actor AND request_id=p_request_id;
 IF prior.offer_id IS NOT NULL THEN
 IF prior.issuer_responsibility_id IS DISTINCT FROM authority OR prior.ledger_id IS DISTINCT FROM p_ledger_id
 OR prior.station_id IS DISTINCT FROM p_station_id OR prior.program_id IS DISTINCT FROM p_program_id
 OR prior.recipient_id IS DISTINCT FROM p_recipient_id OR prior.membership_id IS DISTINCT FROM p_membership_id
 THEN RAISE EXCEPTION 'conflicting subscription offer' USING ERRCODE='23505'; END IF;
 result:=prior.offer_id;
 ELSE
 INSERT INTO titus.radio_subscription_offers_v1(issuer_id,issuer_responsibility_id,recipient_id,ledger_id,station_id,program_id,membership_id,request_id)
 VALUES(actor,authority,p_recipient_id,p_ledger_id,p_station_id,p_program_id,p_membership_id,p_request_id) RETURNING offer_id INTO result;
 END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_subscription_offer_v1','offerId',result,'alreadyExists',prior.offer_id IS NOT NULL);
END $offer$;

-- Acceptance is deliberately not implemented in this increment. It needs
-- current named-recipient consent, current original issuer admission and exact
-- operation authority, fresh membership/source validation and cancellation.
-- Offer alone NEVER enters the subscription collection.
REVOKE ALL ON FUNCTION public.titus_radio_establish_self_api_v1(uuid,uuid,text,uuid),
 public.titus_radio_offer_subscription_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
DO $acl$
BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
 EXECUTE 'REVOKE ALL ON FUNCTION titus.require_radio_operator_self_v1(uuid,text), public.titus_radio_establish_self_api_v1(uuid,uuid,text,uuid), public.titus_radio_offer_subscription_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid) FROM service_role';
 END IF;
END $acl$;
GRANT EXECUTE ON FUNCTION public.titus_radio_establish_self_api_v1(uuid,uuid,text,uuid),
 public.titus_radio_offer_subscription_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid) TO authenticated;
