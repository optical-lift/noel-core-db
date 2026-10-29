-- HELD / owner decision #2392. This is an immutable review of historical
-- source, never another Work engine, accepted Actual or legacy authorization.
CREATE TABLE atlas.historical_self_adoption_review_events_v1(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 ledger_id uuid NOT NULL,
 work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 allocation_id uuid NOT NULL REFERENCES atlas.work_allocations(id) ON DELETE RESTRICT,
 event_kind text NOT NULL CHECK(event_kind IN ('person_confirmed','worker_pending','governor_reviewed')),
 action_id uuid NOT NULL,
 actor_person_id uuid NOT NULL REFERENCES reality.entities(id),
 linked_person_id uuid REFERENCES reality.entities(id),
 parent_event_id uuid REFERENCES atlas.historical_self_adoption_review_events_v1(id),
 evidence_event_id uuid REFERENCES atlas.historical_self_adoption_review_events_v1(id),
 outcome text CHECK(outcome IN ('historically_performed','obsolete_cancelled','still_unresolved')),
 evidence_text text CHECK(evidence_text IS NULL OR length(evidence_text)<=2000),
 snapshot jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(snapshot)='object'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(ledger_id,action_id),
 CHECK (
  (event_kind='person_confirmed' AND linked_person_id IS NOT NULL AND parent_event_id IS NULL AND outcome IS NULL)
  OR (event_kind='worker_pending' AND parent_event_id IS NOT NULL AND linked_person_id=actor_person_id
     AND nullif(btrim(evidence_text),'') IS NOT NULL AND outcome IS NULL)
  OR (event_kind='governor_reviewed' AND parent_event_id IS NOT NULL AND outcome IS NOT NULL AND linked_person_id IS NULL)
 )
);
CREATE UNIQUE INDEX historical_self_adoption_one_person_link_v1
 ON atlas.historical_self_adoption_review_events_v1(organization_id,ledger_id,allocation_id)
 WHERE event_kind='person_confirmed';
CREATE UNIQUE INDEX historical_self_adoption_one_review_v1
 ON atlas.historical_self_adoption_review_events_v1(parent_event_id)
 WHERE event_kind='governor_reviewed';
CREATE INDEX historical_self_adoption_work_read_v1
 ON atlas.historical_self_adoption_review_events_v1(ledger_id,work_item_id,recorded_at,id);
ALTER TABLE atlas.historical_self_adoption_review_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.historical_self_adoption_review_events_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.historical_self_adoption_review_events_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION atlas.reject_historical_review_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $imm$ BEGIN RAISE EXCEPTION 'Historical review is immutable' USING ERRCODE='42501'; END; $imm$;
CREATE TRIGGER reject_historical_review_mutation_v1 BEFORE UPDATE OR DELETE
 ON atlas.historical_self_adoption_review_events_v1 FOR EACH ROW
 EXECUTE FUNCTION atlas.reject_historical_review_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_historical_review_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- Exact native governor confirms a historical Person link without assigning
-- current Work, granting visibility, changing a result, or creating a new Work.
CREATE OR REPLACE FUNCTION atlas.governor_link_historical_self_adoption_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_allocation_id uuid,
 p_related_person_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $link$
DECLARE a uuid; e atlas.historical_self_adoption_review_events_v1%ROWTYPE;
BEGIN
 a:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF p_action_id IS NULL OR p_related_person_id IS NULL OR p_work_item_id IS NULL OR p_allocation_id IS NULL
 THEN RAISE EXCEPTION 'Exact historical identity and action required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('history-link:'||p_allocation_id::text,0));
 SELECT * INTO e FROM atlas.historical_self_adoption_review_events_v1
  WHERE ledger_id=p_ledger_id AND action_id=p_action_id;
 IF e.id IS NOT NULL THEN
  IF e.event_kind<>'person_confirmed' OR e.actor_person_id IS DISTINCT FROM a
    OR e.work_item_id IS DISTINCT FROM p_work_item_id
    OR e.allocation_id IS DISTINCT FROM p_allocation_id
    OR e.linked_person_id IS DISTINCT FROM p_related_person_id
  THEN RAISE EXCEPTION 'Conflicting historical link replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'linkId',e.id,'historicalOnly',true,'replay',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_items w
    JOIN atlas.work_allocations x ON x.work_item_id=w.id
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND x.id=p_allocation_id AND x.organization_id=p_organization_id
      AND x.establishment_basis_kind='self_adoption')
 OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
      AND r.work_item_id=p_work_item_id AND r.attribution_state='active')
 OR NOT EXISTS(SELECT 1 FROM reality.entities p WHERE p.id=p_related_person_id
    AND p.entity_kind='person' AND p.identity_state='canonical')
 THEN RAISE EXCEPTION 'Exact governed historical Work/Person source required' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 h
   WHERE h.ledger_id=p_ledger_id AND h.allocation_id=p_allocation_id
      AND h.event_kind='person_confirmed')
 THEN RAISE EXCEPTION 'Conflicting historical Person; correction requires adjudication'
 USING ERRCODE='23505'; END IF;
 INSERT INTO atlas.historical_self_adoption_review_events_v1(
   organization_id,ledger_id,work_item_id,allocation_id,event_kind,action_id,
   actor_person_id,linked_person_id,snapshot)
 VALUES (p_organization_id,p_ledger_id,p_work_item_id,p_allocation_id,'person_confirmed',
   p_action_id,a,p_related_person_id,
   jsonb_build_object('nativeGovernorConfirmed',true,'legacyAuthorityGranted',false,
     'newWorkCreated',false,'currentAssignmentCreated',false))
 RETURNING * INTO e;
 RETURN jsonb_build_object('ok',true,'linkId',e.id,'historicalOnly',true,
   'newWorkCreated',false,'newAuthorityGranted',false,'replay',false);
END; $link$;

-- Worker report is pending evidence, NOT Done, and requires currently signed,
-- connected canonical Person and source-enforced original Work disclosure.
CREATE OR REPLACE FUNCTION atlas.report_historical_self_adoption_pending_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_evidence_text text,p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $pending$
DECLARE a uuid:=atlas.current_person_id_v1();
 l atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 e atlas.historical_self_adoption_review_events_v1%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR a IS NULL
   OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Signed current native Person required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
 IF p_link_id IS NULL OR p_action_id IS NULL
    OR nullif(btrim(coalesce(p_evidence_text,'')),'') IS NULL OR length(p_evidence_text)>2000
 THEN RAISE EXCEPTION 'Actual historical report and action required' USING ERRCODE='22023'; END IF;
 SELECT * INTO l FROM atlas.historical_self_adoption_review_events_v1
 WHERE id=p_link_id AND organization_id=p_organization_id AND ledger_id=p_ledger_id
   AND event_kind='person_confirmed' AND linked_person_id=a;
 IF l.id IS NULL
   OR NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,a)
   OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
       WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
         AND r.work_item_id=l.work_item_id AND r.attribution_state='active')
   OR NOT atlas.person_original_work_identity_disclosed_self_v1(
     p_organization_id,p_ledger_id,l.work_item_id,a)
 THEN RAISE EXCEPTION 'Historical source not disclosed to current Person' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('historical-evidence:'||p_action_id::text,0));
 SELECT * INTO e FROM atlas.historical_self_adoption_review_events_v1
 WHERE ledger_id=p_ledger_id AND action_id=p_action_id;
 IF e.id IS NOT NULL THEN
  IF e.event_kind<>'worker_pending' OR e.parent_event_id IS DISTINCT FROM l.id
     OR e.actor_person_id IS DISTINCT FROM a OR e.evidence_text IS DISTINCT FROM btrim(p_evidence_text)
  THEN RAISE EXCEPTION 'Conflicting historical evidence replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'evidenceId',e.id,'state','pending','acceptedDone',false,'replay',true);
 END IF;
 INSERT INTO atlas.historical_self_adoption_review_events_v1(
 organization_id,ledger_id,work_item_id,allocation_id,event_kind,action_id,
 actor_person_id,linked_person_id,parent_event_id,evidence_text,snapshot)
 VALUES(p_organization_id,p_ledger_id,l.work_item_id,l.allocation_id,'worker_pending',
 p_action_id,a,a,l.id,btrim(p_evidence_text),
 jsonb_build_object('newResultCreated',false,'acceptedDone',false,'originalWorkUnchanged',true))
 RETURNING * INTO e;
 RETURN jsonb_build_object('ok',true,'evidenceId',e.id,'state','pending','acceptedDone',false,'replay',false);
END; $pending$;

-- Owner historical decision is audit evidence and deliberately cannot alter
-- the original Work state. The eventual lifecycle closure must be a
-- separately admitted native transition, not hidden inside a review event.
CREATE OR REPLACE FUNCTION atlas.governor_review_historical_self_adoption_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_outcome text,
 p_evidence_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $review$
DECLARE a uuid; l atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 e atlas.historical_self_adoption_review_events_v1%ROWTYPE;
BEGIN
 a:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF p_action_id IS NULL OR p_link_id IS NULL
 OR p_outcome IS NULL OR p_outcome NOT IN
 ('historically_performed','obsolete_cancelled','still_unresolved')
 THEN RAISE EXCEPTION 'Exact review outcome and action required' USING ERRCODE='22023'; END IF;
 SELECT * INTO l FROM atlas.historical_self_adoption_review_events_v1
 WHERE id=p_link_id AND organization_id=p_organization_id AND ledger_id=p_ledger_id
 AND event_kind='person_confirmed';
 IF l.id IS NULL OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
   WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.work_item_id=l.work_item_id AND r.attribution_state='active')
 THEN RAISE EXCEPTION 'Exact governed historical source required' USING ERRCODE='42501'; END IF;
 IF p_evidence_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 p
   WHERE p.id=p_evidence_id AND p.parent_event_id=l.id
   AND p.event_kind='worker_pending' AND p.ledger_id=p_ledger_id)
 THEN RAISE EXCEPTION 'Wrong historical evidence reference' USING ERRCODE='42501'; END IF;
 IF p_outcome='historically_performed' AND p_evidence_id IS NULL
 AND NOT EXISTS(SELECT 1 FROM atlas.work_execution_results r
   JOIN atlas.work_result_acceptances c ON c.execution_result_id=r.id
   WHERE r.work_item_id=l.work_item_id AND r.responsible_allocation_id=l.allocation_id
   AND c.decision='accepted' AND c.work_item_id=r.work_item_id)
 THEN RAISE EXCEPTION 'Historical performance requires actual evidence' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('historical-review:'||l.id::text,0));
 SELECT * INTO e FROM atlas.historical_self_adoption_review_events_v1
 WHERE ledger_id=p_ledger_id AND action_id=p_action_id;
 IF e.id IS NOT NULL THEN
  IF e.event_kind<>'governor_reviewed' OR e.parent_event_id IS DISTINCT FROM l.id
  OR e.actor_person_id IS DISTINCT FROM a OR e.outcome IS DISTINCT FROM p_outcome
  OR e.evidence_event_id IS DISTINCT FROM p_evidence_id
  THEN RAISE EXCEPTION 'Conflicting historical review replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'reviewId',e.id,'outcome',e.outcome,'workStateChanged',false,'replay',true);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 r
    WHERE r.parent_event_id=l.id AND r.event_kind='governor_reviewed')
 THEN RAISE EXCEPTION 'Historical decision already reviewed; correction requires adjudication'
 USING ERRCODE='23505'; END IF;
 INSERT INTO atlas.historical_self_adoption_review_events_v1(
 organization_id,ledger_id,work_item_id,allocation_id,event_kind,action_id,
 actor_person_id,parent_event_id,evidence_event_id,outcome,snapshot)
 VALUES(p_organization_id,p_ledger_id,l.work_item_id,l.allocation_id,'governor_reviewed',
 p_action_id,a,l.id,p_evidence_id,p_outcome,
 jsonb_build_object('originalWorkUnchanged',true,'noAcceptedActualFabricated',true))
 RETURNING * INTO e;
 RETURN jsonb_build_object('ok',true,'reviewId',e.id,'outcome',p_outcome,
 'historicalOnly',true,'workStateChanged',false,'replay',false);
END; $review$;

REVOKE ALL ON FUNCTION atlas.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION atlas.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)
 FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION atlas.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)
 TO authenticated;
