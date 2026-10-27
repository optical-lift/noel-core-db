BEGIN;
-- Universal communication-source-owned, per-Person, per-address time-bounded
-- READ disclosure. A Ledger seat is eligibility only, never authority.
-- This candidate MUST NOT be applied directly to the shared production schema.
CREATE TABLE atlas.communication_person_mail_read_decisions_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 communication_endpoint_id uuid NOT NULL REFERENCES atlas.communication_endpoints(id),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
 authorizing_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 target_person_id uuid NOT NULL REFERENCES reality.entities(id),
 decision text NOT NULL CHECK(decision IN ('grant','revoke')),
 start_local_date date,
 timezone_name text,
 earliest_event_at timestamptz,
 source_action_id uuid NOT NULL UNIQUE,
 decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 1000),
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT communication_mail_read_grant_date_v1 CHECK (
    (decision='grant' AND start_local_date IS NOT NULL
      AND timezone_name IS NOT NULL AND earliest_event_at IS NOT NULL)
    OR (decision='revoke' AND start_local_date IS NULL
      AND timezone_name IS NULL AND earliest_event_at IS NULL))
);
CREATE INDEX communication_mail_person_current_v1 ON
 atlas.communication_person_mail_read_decisions_v1
 (communication_endpoint_id,target_person_id,decided_at DESC,id DESC);
ALTER TABLE atlas.communication_person_mail_read_decisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.communication_person_mail_read_decisions_v1 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.communication_mail_read_decision_immutable_v1()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $f$
BEGIN
 RAISE EXCEPTION 'Mailbox access decisions are immutable; append a new decision'
 USING ERRCODE='42501';
END $f$;
REVOKE ALL ON FUNCTION atlas.communication_mail_read_decision_immutable_v1() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER communication_mail_read_immutability_v1 BEFORE UPDATE OR DELETE ON
 atlas.communication_person_mail_read_decisions_v1 FOR EACH ROW
 EXECUTE FUNCTION atlas.communication_mail_read_decision_immutable_v1();

-- The latest decision wins ACROSS all Ledgers for one endpoint+Person. A
-- competing Venue/Flower entry cannot revive a globally revoked grant.
CREATE FUNCTION atlas.communication_person_mail_read_cutoff_v1(
 p_endpoint_id uuid,p_person_id uuid)
 RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
 SELECT CASE WHEN d.decision='grant'
      AND EXISTS (SELECT 1 FROM ledger.seats s
       JOIN atlas.ledger_organization_participations lop ON lop.ledger_id=s.ledger_id
       JOIN atlas.communication_endpoints ep ON ep.id=d.communication_endpoint_id
       WHERE s.ledger_id=d.authorizing_ledger_id
        AND s.person_entity_id=d.target_person_id
        AND s.seat_state='active' AND s.ended_at IS NULL
        AND lop.organization_id=ep.organization_id
        AND lop.status='active' AND lop.ended_at IS NULL
        AND lop.participation_kind IN ('governing','operating'))
      THEN d.earliest_event_at ELSE NULL END
 FROM atlas.communication_person_mail_read_decisions_v1 d
 JOIN reality.entities person ON person.id=d.target_person_id
   AND person.entity_kind='person' AND person.identity_state='canonical'
 WHERE d.communication_endpoint_id=p_endpoint_id AND d.target_person_id=p_person_id
 ORDER BY d.decided_at DESC,d.id DESC LIMIT 1;
$f$;
REVOKE ALL ON FUNCTION atlas.communication_person_mail_read_cutoff_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

-- One governor's decision, rechecked against BOTH the exact Ledger root and
-- the governing institutional root. Person must participate in chosen Ledger.
CREATE FUNCTION atlas.set_person_mail_read_self_v1(
 p_endpoint_id uuid,p_ledger_id uuid,p_target_person_id uuid,
 p_start_date date,p_timezone text,p_enabled boolean,
 p_action_id uuid,p_reason text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_endpoint atlas.communication_endpoints%rowtype;
 v_owner uuid;v_prior atlas.communication_person_mail_read_decisions_v1%rowtype;
 v_new atlas.communication_person_mail_read_decisions_v1%rowtype;
 v_cutoff timestamptz; v_expected_decision text;
BEGIN
 IF auth.uid() IS NULL OR p_endpoint_id IS NULL OR p_ledger_id IS NULL
    OR p_target_person_id IS NULL OR p_action_id IS NULL
    OR p_enabled IS NULL OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 8 AND 1000 THEN
    RAISE EXCEPTION 'A signed exact Person, endpoint, action and reason are required'
      USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_endpoint FROM atlas.communication_endpoints
  WHERE id=p_endpoint_id AND endpoint_state='active'
    AND organization_id IS NOT NULL AND endpoint_kind='email';
 IF v_endpoint.id IS NULL THEN
   RAISE EXCEPTION 'Governed communication endpoint unavailable' USING ERRCODE='42501';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(v_endpoint.organization_id,p_ledger_id);
 IF NOT EXISTS(
   SELECT 1 FROM ledger.seats s JOIN reality.entities e ON e.id=s.person_entity_id
   JOIN atlas.ledger_organization_participations lop ON lop.ledger_id=s.ledger_id
   WHERE s.ledger_id=p_ledger_id AND s.person_entity_id=p_target_person_id
     AND s.seat_state='active' AND s.ended_at IS NULL
     AND e.entity_kind='person' AND e.identity_state='canonical'
     AND lop.organization_id=v_endpoint.organization_id
     AND lop.status='active' AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
 ) THEN RAISE EXCEPTION 'Target must be an active canonical connected Person on this exact Ledger'
   USING ERRCODE='42501'; END IF;
 v_expected_decision:=CASE WHEN p_enabled THEN 'grant' ELSE 'revoke' END;
 IF p_enabled THEN
   IF p_start_date IS NULL OR p_timezone IS NULL OR
     NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone)
   THEN RAISE EXCEPTION 'Valid local calendar start and timezone required'
     USING ERRCODE='22023'; END IF;
   v_cutoff := (p_start_date::timestamp AT TIME ZONE p_timezone);
 ELSE
   IF p_start_date IS NOT NULL OR p_timezone IS NOT NULL THEN
     RAISE EXCEPTION 'Revocation does not accept historical date' USING ERRCODE='22023';
   END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.mail-access:'||p_endpoint_id::text||':'||p_target_person_id::text,0));
 SELECT * INTO v_prior FROM atlas.communication_person_mail_read_decisions_v1
    WHERE source_action_id=p_action_id;
 IF v_prior.id IS NOT NULL THEN
   IF v_prior.communication_endpoint_id IS DISTINCT FROM p_endpoint_id
    OR v_prior.authorizing_ledger_id IS DISTINCT FROM p_ledger_id
    OR v_prior.target_person_id IS DISTINCT FROM p_target_person_id
    OR v_prior.decision IS DISTINCT FROM v_expected_decision
    OR v_prior.earliest_event_at IS DISTINCT FROM v_cutoff
    OR v_prior.reason IS DISTINCT FROM btrim(p_reason) THEN
     RAISE EXCEPTION 'Idempotency key already used for another decision'
       USING ERRCODE='23505'; END IF;
   v_new:=v_prior;
 ELSE
   INSERT INTO atlas.communication_person_mail_read_decisions_v1(
     communication_endpoint_id,organization_id,authorizing_ledger_id,
     target_person_id,decision,start_local_date,timezone_name,
     earliest_event_at,source_action_id,decided_by_person_id,reason)
   VALUES (p_endpoint_id,v_endpoint.organization_id,p_ledger_id,p_target_person_id,
     CASE WHEN p_enabled THEN 'grant' ELSE 'revoke' END,
     CASE WHEN p_enabled THEN p_start_date ELSE NULL END,
     CASE WHEN p_enabled THEN p_timezone ELSE NULL END,
     v_cutoff,p_action_id,v_owner,btrim(p_reason))
   RETURNING * INTO v_new;
 END IF;
 RETURN jsonb_build_object('ok',true,'decisionId',v_new.id,
   'endpointId',p_endpoint_id,'personId',p_target_person_id,
   'actionId',p_action_id,'decision',v_new.decision,
   'startLocalDate',v_new.start_local_date,'timeZone',v_new.timezone_name,
   'earliestEventAt',v_new.earliest_event_at,
   'currentlyEffectiveSince',atlas.communication_person_mail_read_cutoff_v1(
     p_endpoint_id,p_target_person_id));
END $f$;
REVOKE ALL ON FUNCTION atlas.set_person_mail_read_self_v1(
 uuid,uuid,uuid,date,text,boolean,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.set_person_mail_read_self_v1(
 p_endpoint_id uuid,p_ledger_id uuid,p_target_person_id uuid,
 p_start_date date,p_timezone text,p_enabled boolean,
 p_action_id uuid,p_reason text)
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $f$
 SELECT atlas.set_person_mail_read_self_v1(
   p_endpoint_id,p_ledger_id,p_target_person_id,p_start_date,
   p_timezone,p_enabled,p_action_id,p_reason);
$f$;
REVOKE ALL ON FUNCTION public.set_person_mail_read_self_v1(
 uuid,uuid,uuid,date,text,boolean,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_person_mail_read_self_v1(
 uuid,uuid,uuid,date,text,boolean,uuid,text) TO authenticated;

-- Disclose only safe ADDRESS metadata, no cross-organization enumeration.
-- Root owners with legacy endpoint view get their existing mailbox path;
-- native People get only the exact explicitly approved endpoint.
CREATE FUNCTION atlas.person_mail_readable_endpoints_self_v1()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_person uuid;v_items jsonb;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Canonical signed Person required' USING ERRCODE='42501'; END IF;
 v_person:=atlas.current_person_id_v1();
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'endpointId',ep.id,'address',ep.address,'displayName',ep.display_name,
    'earliestEventAt',x.cutoff,'viewOnly',true)
    ORDER BY ep.address),'[]'::jsonb)
 INTO v_items
 FROM atlas.communication_endpoints ep
 CROSS JOIN LATERAL (
   SELECT atlas.communication_person_mail_read_cutoff_v1(ep.id,v_person) AS cutoff
 ) x
 WHERE ep.endpoint_state='active' AND ep.endpoint_kind='email'
   AND ep.organization_id IS NOT NULL AND x.cutoff IS NOT NULL;
 RETURN jsonb_build_object('ok',true,'contractVersion','mail_person_address_read_v1',
    'items',v_items);
END $f$;
REVOKE ALL ON FUNCTION atlas.person_mail_readable_endpoints_self_v1()
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.person_mail_readable_endpoints_self_v1()
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $f$
 SELECT atlas.person_mail_readable_endpoints_self_v1();
$f$;
REVOKE ALL ON FUNCTION public.person_mail_readable_endpoints_self_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.person_mail_readable_endpoints_self_v1()
 TO authenticated;

-- This is a read-projection of ORIGINAL Communication Events, not a second
-- mailbox or ingest writer. No thread-level subject/summary data is read.
-- Paging/filtering happen AFTER per-event date/source proofs and authorization.
CREATE FUNCTION atlas.person_mail_events_self_v1(
 p_endpoint_id uuid,p_limit integer DEFAULT 50,p_before_at timestamptz DEFAULT NULL,
 p_before_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_person uuid;v_cutoff timestamptz;v_items jsonb;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
   OR p_limit NOT BETWEEN 1 AND 100 THEN
   RAISE EXCEPTION 'Signed bounded mail read required' USING ERRCODE='42501'; END IF;
 v_person:=atlas.current_person_id_v1();
 v_cutoff:=atlas.communication_person_mail_read_cutoff_v1(p_endpoint_id,v_person);
 IF v_cutoff IS NULL THEN
   RAISE EXCEPTION 'Mailbox not disclosed to this Person' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'eventId',item.id,
   'conversationId',item.communication_conversation_id,
   'occurredAt',item.occurred_at,
   'speakerAddress',item.speaker_address,
   'direction',item.direction,
   'subject',item.subject,
   'body',item.body,
   'bodyState',item.body_state
   ) ORDER BY item.occurred_at DESC,item.id DESC),'[]'::jsonb)
 INTO v_items
 FROM (
   SELECT e.id,cce.communication_conversation_id,e.occurred_at,
     e.speaker_address,e.direction,e.canonical_event->>'subject' subject,
     e.body,e.body_state
   FROM atlas.communication_conversation_events cce
   JOIN atlas.communication_events e ON e.id=cce.communication_event_id
   JOIN atlas.communication_endpoints ep ON ep.id=cce.communication_endpoint_id
   WHERE ep.id=p_endpoint_id AND ep.endpoint_state='active'
     AND e.organization_id=ep.organization_id
     AND e.occurred_at>=v_cutoff
     AND ((p_before_at IS NULL AND p_before_id IS NULL) OR
       (p_before_at IS NOT NULL AND p_before_id IS NOT NULL
        AND (e.occurred_at,e.id)<(p_before_at,p_before_id)))
     -- Exclude metadata-backed synthesized timestamps: not defensible
     -- date evidence for any retroactive window.
     AND e.canonical_event->>'captureMode'='live_relay'
     AND e.canonical_event->'source'->>'kind'='email'
     AND e.occurred_at IS DISTINCT FROM e.captured_at
   ORDER BY e.occurred_at DESC,e.id DESC LIMIT p_limit
 ) item;
 RETURN jsonb_build_object('ok',true,'contractVersion','mail_person_events_v1',
    'endpointId',p_endpoint_id,'startAt',v_cutoff,'items',v_items,
    'attachmentsDisclosed',false,'historicalThreadMetadataDisclosed',false,
    'readOnly',true);
END $f$;
REVOKE ALL ON FUNCTION atlas.person_mail_events_self_v1(uuid,integer,timestamptz,uuid)
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.person_mail_events_self_v1(
 p_endpoint_id uuid,p_limit integer DEFAULT 50,p_before_at timestamptz DEFAULT NULL,
 p_before_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $f$
 SELECT atlas.person_mail_events_self_v1(p_endpoint_id,p_limit,p_before_at,p_before_id);
$f$;
REVOKE ALL ON FUNCTION public.person_mail_events_self_v1(uuid,integer,timestamptz,uuid)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.person_mail_events_self_v1(uuid,integer,timestamptz,uuid)
 TO authenticated;
-- Root-governor-only picker; no broad People enumeration. Exact native Ledger
-- and active canonical Person participation remain prerequisites.
CREATE FUNCTION atlas.person_mail_governor_choices_self_v1()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_options jsonb:='[]'::jsonb; v_rows jsonb;
 v_rec record;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Canonical signed governor required' USING ERRCODE='42501'; END IF;
 FOR v_rec IN
   SELECT ep.id endpoint_id,ep.address,ep.organization_id,
          lop.ledger_id,nl.name ledger_name
   FROM atlas.communication_endpoints ep
   JOIN atlas.ledger_organization_participations lop
      ON lop.organization_id=ep.organization_id AND lop.status='active'
      AND lop.ended_at IS NULL AND lop.participation_kind IN ('governing','operating')
   JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
       AND nl.ledger_state='active' AND nl.retired_at IS NULL
   WHERE ep.endpoint_kind='email' AND ep.endpoint_state='active'
   ORDER BY ep.address,nl.name
 LOOP
   BEGIN
     PERFORM atlas.company_work_native_ledger_owner_self_v1(v_rec.organization_id,v_rec.ledger_id);
   EXCEPTION WHEN insufficient_privilege THEN CONTINUE;
   END;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'personId',person.id,'personName',person.display_name,
      'startAt',atlas.communication_person_mail_read_cutoff_v1(v_rec.endpoint_id,person.id),
      'startLocalDate',(SELECT d.start_local_date
        FROM atlas.communication_person_mail_read_decisions_v1 d
        WHERE d.communication_endpoint_id=v_rec.endpoint_id AND d.target_person_id=person.id
        ORDER BY d.decided_at DESC,d.id DESC LIMIT 1)
   ) ORDER BY person.display_name),'[]'::jsonb) INTO v_rows
   FROM (SELECT DISTINCT e.id,e.display_name
     FROM ledger.seats s JOIN reality.entities e ON e.id=s.person_entity_id
     WHERE s.ledger_id=v_rec.ledger_id AND s.seat_state='active' AND s.ended_at IS NULL
       AND e.entity_kind='person' AND e.identity_state='canonical') person;
   v_options:=v_options||jsonb_build_array(jsonb_build_object(
      'endpointId',v_rec.endpoint_id,'address',v_rec.address,
      'organizationId',v_rec.organization_id,
      'ledgerId',v_rec.ledger_id,'ledgerName',v_rec.ledger_name,
      'people',v_rows));
 END LOOP;
 RETURN jsonb_build_object('ok',true,'contractVersion','mail_governor_choices_v1',
    'items',v_options);
END $f$;
REVOKE ALL ON FUNCTION atlas.person_mail_governor_choices_self_v1()
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.person_mail_governor_choices_self_v1()
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $f$
 SELECT atlas.person_mail_governor_choices_self_v1();
$f$;
REVOKE ALL ON FUNCTION public.person_mail_governor_choices_self_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.person_mail_governor_choices_self_v1() TO authenticated;
COMMIT;
