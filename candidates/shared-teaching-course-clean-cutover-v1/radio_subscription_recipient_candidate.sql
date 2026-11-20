-- HELD Radio recipient inbox and subscription termination. Scratch only.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('titus.radio_subscription_offer_cancellations_v1') IS NULL
 THEN RAISE EXCEPTION 'held Radio recipient prerequisites missing' USING ERRCODE='42501'; END IF;
END $preflight$;

-- Offers visible only to named recipient; no roster or issuer identity details.
-- An inbox row is not authority: acceptance rechecks and locks actual sources.
CREATE FUNCTION public.titus_radio_subscription_inbox_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $inbox$
DECLARE actor uuid; at_time timestamptz; rows jsonb; total bigint;
BEGIN
 actor:=atlas.current_person_for_private_course_v1();
 IF actor IS NULL THEN RAISE EXCEPTION 'current Person required' USING ERRCODE='42501'; END IF;
 at_time:=clock_timestamp();
 SELECT count(*),coalesce(jsonb_agg(jsonb_build_object('offerId',x.offer_id,
 'stationId',x.station_id,'stationName',x.station_name,'programId',x.program_id,
 'programName',x.program_name,'includedInMembership',x.included) ORDER BY x.offered_at,x.offer_id),'[]'::jsonb)
 INTO total,rows FROM (
 SELECT o.offer_id,o.station_id,s.title AS station_name,o.program_id,p.title AS program_name,
 o.membership_id IS NOT NULL AS included,o.offered_at
 FROM titus.radio_subscription_offers_v1 o
 JOIN ledger.ledgers l ON l.id=o.ledger_id AND l.ledger_state='active' AND l.retired_at IS NULL
 JOIN reality.entities e ON e.id=l.subject_entity_id AND e.identity_state='canonical' AND e.entity_kind IN ('business','organization')
 JOIN titus.radio_stations_v1 s ON s.station_id=o.station_id AND s.ledger_id=o.ledger_id AND s.retired_at IS NULL AND s.established_at<=at_time
 LEFT JOIN titus.radio_programs_v1 p ON p.program_id=o.program_id AND p.station_id=o.station_id
 LEFT JOIN titus.library_memberships_v1 m ON m.membership_id=o.membership_id AND m.ledger_id=o.ledger_id AND m.person_id=actor
 WHERE o.recipient_id=actor AND o.offered_at<=at_time
 AND NOT EXISTS(SELECT 1 FROM titus.radio_subscription_acceptances_v1 a WHERE a.offer_id=o.offer_id)
 AND NOT EXISTS(SELECT 1 FROM titus.radio_subscription_offer_cancellations_v1 c WHERE c.offer_id=o.offer_id)
 AND (o.program_id IS NULL OR (p.program_id IS NOT NULL AND p.retired_at IS NULL AND p.established_at<=at_time))
 AND (o.membership_id IS NULL OR (m.membership_id IS NOT NULL AND m.accepted_at<=at_time AND (m.valid_until IS NULL OR m.valid_until>at_time)
 AND NOT EXISTS(SELECT 1 FROM titus.library_membership_endings_v1 me WHERE me.membership_id=m.membership_id AND me.ended_at<=at_time)))
 AND (SELECT count(*) FROM titus.institution_account_admissions_v1 a WHERE a.ledger_id=o.ledger_id AND a.institution_entity_id=l.subject_entity_id
 AND a.person_entity_id=o.issuer_id AND a.accepted_at<=at_time
 AND NOT EXISTS(SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w WHERE w.admission_id=a.admission_id AND w.ended_at<=at_time))=1
 AND (SELECT count(*) FROM reality.responsibility_relations r WHERE r.carrier_person_entity_id=o.issuer_id
 AND r.responsibility_key='institution_publication_management' AND r.jurisdiction_kind='entity'
 AND r.jurisdiction_entity_id=l.subject_entity_id AND r.jurisdiction_domain IS NULL
 AND r.scope=jsonb_build_object('ledgerId',o.ledger_id::text) AND r.relation_state='active'
 AND r.ended_at IS NULL AND r.began_at<=at_time AND 'offer_subscription'=ANY(r.permitted_operations))=1
 AND EXISTS(SELECT 1 FROM reality.responsibility_relations r WHERE r.id=o.issuer_responsibility_id
 AND r.carrier_person_entity_id=o.issuer_id AND r.responsibility_key='institution_publication_management'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=l.subject_entity_id AND r.jurisdiction_domain IS NULL
 AND r.scope=jsonb_build_object('ledgerId',o.ledger_id::text) AND r.relation_state='active'
 AND r.ended_at IS NULL AND r.began_at<=at_time AND 'offer_subscription'=ANY(r.permitted_operations))
 AND reality.resolve_responsibility_relation_v1(o.issuer_id,'institution_publication_management','offer_subscription','entity',
 l.subject_entity_id,NULL,jsonb_build_object('ledgerId',o.ledger_id::text))=o.issuer_responsibility_id
 ORDER BY o.offered_at,o.offer_id LIMIT 101
 ) x;
 IF total>100 THEN RAISE EXCEPTION 'Radio inbox exceeds response bound' USING ERRCODE='54000'; END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_subscription_inbox_v1','personId',actor,'offers',rows);
END $inbox$;

-- Subscriber can always leave their own subscription, even after publisher
-- standing is lost. No deletion of original or unrelated memberships.
-- Lock order: Ledger, subscription. Publisher termination is separate scope.
CREATE FUNCTION public.titus_radio_end_subscription_self_api_v1(p_subscription_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $end$
DECLARE actor uuid; s titus.radio_subscriptions_v1%ROWTYPE; prior titus.radio_subscription_endings_v1%ROWTYPE;
 receipt text;
BEGIN
 IF p_subscription_id IS NULL OR p_request_id IS NULL THEN RAISE EXCEPTION 'exact termination required' USING ERRCODE='22023'; END IF;
 actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO s FROM titus.radio_subscriptions_v1 WHERE subscription_id=p_subscription_id AND person_id=actor;
 IF s.subscription_id IS NULL THEN RAISE EXCEPTION 'subscription unavailable' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM ledger.ledgers WHERE id=s.ledger_id FOR UPDATE;
 SELECT * INTO s FROM titus.radio_subscriptions_v1 WHERE subscription_id=p_subscription_id AND person_id=actor FOR UPDATE;
 IF s.subscription_id IS NULL OR atlas.current_person_for_private_course_v1() IS DISTINCT FROM actor
 THEN RAISE EXCEPTION 'subscription unavailable' USING ERRCODE='42501'; END IF;
 receipt:='radio-end:'||actor::text||':'||p_request_id::text;
 SELECT * INTO prior FROM titus.radio_subscription_endings_v1 WHERE subscription_id=p_subscription_id;
 IF prior.subscription_id IS NOT NULL THEN
 IF prior.ended_by_person_id IS DISTINCT FROM actor OR prior.source_receipt IS DISTINCT FROM receipt
 THEN RAISE EXCEPTION 'conflicting termination' USING ERRCODE='23505'; END IF;
 ELSE
 INSERT INTO titus.radio_subscription_endings_v1(subscription_id,ended_by_person_id,source_receipt,ended_at)
 VALUES(p_subscription_id,actor,receipt,clock_timestamp());
 END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_subscription_end_v1','subscriptionId',p_subscription_id,'alreadyExists',prior.subscription_id IS NOT NULL);
END $end$;
REVOKE ALL ON FUNCTION public.titus_radio_subscription_inbox_self_api_v1(),public.titus_radio_end_subscription_self_api_v1(uuid,uuid) FROM PUBLIC,anon,authenticated;
DO $acl$
BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
 EXECUTE 'REVOKE ALL ON FUNCTION public.titus_radio_subscription_inbox_self_api_v1(),public.titus_radio_end_subscription_self_api_v1(uuid,uuid) FROM service_role';
 END IF;
END $acl$;
GRANT EXECUTE ON FUNCTION public.titus_radio_subscription_inbox_self_api_v1(),public.titus_radio_end_subscription_self_api_v1(uuid,uuid) TO authenticated;
