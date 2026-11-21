-- HELD: signed observation without task admission. Worker observation is
-- physical evidence, not authority to schedule or create original Work.
-- Only the current accepted connected Person for a governor's explicit
-- standing_source_observed policy may report this physical source.
CREATE OR REPLACE FUNCTION atlas.record_standing_care_observation_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid,p_rhythm_state_id uuid,
 p_condition text,p_note text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $observe$
DECLARE
 v_actor uuid;
 v_state atlas.rhythm_state%ROWTYPE;
 v_policy atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_current atlas.care_current_state%ROWTYPE;
 v_event atlas.care_observation_events%ROWTYPE;
 v_condition text:=nullif(btrim(coalesce(p_condition,'')),'');
 v_note text:=nullif(btrim(coalesce(p_note,'')),'');
 v_key text;
BEGIN
 v_actor:=atlas.current_person_id_v1();
 IF auth.uid() IS NULL OR v_actor IS NULL OR p_organization_id IS NULL
 OR p_ledger_id IS NULL OR p_rhythm_state_id IS NULL OR p_action_id IS NULL
 OR v_condition IS NULL OR v_note IS NULL OR length(v_note) NOT BETWEEN 10 AND 1500
 THEN RAISE EXCEPTION 'Exact signed physical evidence required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.standing-physical-observation:'||p_organization_id||':'||p_rhythm_state_id,0));
 SELECT * INTO v_policy FROM atlas.continuing_work_source_governance_events_v1 g
 WHERE g.organization_id=p_organization_id AND g.ledger_id=p_ledger_id
 AND g.source_kind='rhythm_state' AND g.source_id=p_rhythm_state_id
 ORDER BY g.recorded_at DESC,g.id DESC LIMIT 1;
 IF v_policy.id IS NULL OR v_policy.authorization_method<>'standing_source_observed'
 OR v_policy.worker_visibility<>'eligible_disclosed' THEN
   RAISE EXCEPTION 'Worker observation not governed by active standing authority'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes a
 WHERE a.id=v_policy.worker_scope_id AND a.organization_id=p_organization_id
 AND a.ledger_id=p_ledger_id;
 IF v_scope.id IS NULL OR v_scope.worker_person_id IS DISTINCT FROM v_actor
 OR v_scope.scope_state<>'active' OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.coverage_mode<>'ledger_all_work'
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_actor
 OR v_scope.accepted_at IS NULL
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
     p_organization_id,p_ledger_id,v_actor)
 THEN RAISE EXCEPTION 'Accepted responsible Person required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
 AND s.subject_kind='growing_object' AND s.state<>'paused' FOR SHARE;
 IF v_state.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.rhythm_bindings b JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
   WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
     AND b.organization_id=p_organization_id AND b.farm_id=v_state.farm_id
     AND b.active AND r.status='active'
 ) THEN RAISE EXCEPTION 'Observed source no longer active' USING ERRCODE='23514'; END IF;
 IF NOT atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'identity')
 OR NOT atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'condition')
 THEN RAISE EXCEPTION 'Physical Subject not disclosed to this Person' USING ERRCODE='42501';
 END IF;
 IF (v_state.rhythm_key='weed_stewardship' AND
     v_condition NOT IN ('clear','needs_inspection','row_readable','medium_pressure','heavy'))
 OR (v_state.rhythm_key='mowing' AND
     v_condition NOT IN ('resting','acceptable','needs_inspection','ready_for_mowing','overgrown','too_wet'))
 OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
 THEN RAISE EXCEPTION 'Unqualified physical source condition' USING ERRCODE='22023'; END IF;
 IF v_state.rhythm_key='weed_stewardship' AND NOT EXISTS(
   SELECT 1 FROM atlas.weed_cards c WHERE c.farm_id=v_state.farm_id AND c.object_id=v_state.subject_id
 ) THEN RAISE EXCEPTION 'Physical weed source missing' USING ERRCODE='23514'; END IF;
 IF v_state.rhythm_key='mowing' AND NOT EXISTS(
   SELECT 1 FROM atlas.mowing_area_state m WHERE m.farm_id=v_state.farm_id
     AND m.organization_id=p_organization_id AND m.object_id=v_state.subject_id
     AND m.status<>'closed'
 ) THEN RAISE EXCEPTION 'Physical mowing source missing' USING ERRCODE='23514'; END IF;
 v_key:='standing-care-observation:'||p_organization_id||':'||p_rhythm_state_id||':'||p_action_id;
 SELECT * INTO v_event FROM atlas.care_observation_events e
 WHERE e.source_kind='standing_care_person_observation' AND e.source_key=v_key;
 IF v_event.id IS NOT NULL THEN
    IF v_event.condition_state IS DISTINCT FROM v_condition
    OR v_event.note IS DISTINCT FROM v_note
    OR v_event.observed_by_user_id IS DISTINCT FROM auth.uid()
    OR v_event.subject_id IS DISTINCT FROM v_state.subject_id::text
    THEN RAISE EXCEPTION 'Signed physical source action replay changed meaning'
      USING ERRCODE='23505'; END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'sourceObservationId',v_event.id,'noWorkCreated',true,'notOnToday',true);
 END IF;
 SELECT * INTO v_current FROM atlas.care_current_state c
 WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
 AND c.subject_domain='farm' AND c.subject_kind='growing_object'
 AND c.subject_id=v_state.subject_id::text FOR UPDATE;
 INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
 ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    clock_timestamp(),v_condition,'reassess',auth.uid(),
    'standing_care_person_observation',v_key,v_note,false,
    jsonb_build_object('rhythmStateId',v_state.id,'ledgerId',p_ledger_id,
      'workerPersonId',v_actor,'governanceEventId',v_policy.id,
      'noAutomaticWorkCreated',true)
 ) RETURNING * INTO v_event;
 IF NOT EXISTS(SELECT 1 FROM atlas.care_current_state c
   WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
     AND c.subject_domain='farm' AND c.subject_kind='growing_object'
     AND c.subject_id=v_state.subject_id::text
     AND c.last_observation_id=v_event.id
     AND c.condition_state=v_condition
 ) THEN RAISE EXCEPTION 'Signed physical evidence failed source projection' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('ok',true,'idempotent',false,
   'sourceObservationId',v_event.id,'conditionRecorded',true,
   'noWorkCreated',true,'notOnToday',true,'notAnAssignment',true);
END;
$observe$;
REVOKE ALL ON FUNCTION atlas.record_standing_care_observation_self_api_v1(
 uuid,uuid,uuid,text,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.record_standing_care_observation_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_condition text,p_note text,p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.record_standing_care_observation_self_api_v1(
   p_organization_id,p_ledger_id,p_rhythm_state_id,p_condition,p_note,p_action_id);
$public$;
REVOKE ALL ON FUNCTION public.record_standing_care_observation_self_api_v1(
 uuid,uuid,uuid,text,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_standing_care_observation_self_api_v1(
 uuid,uuid,uuid,text,text,uuid
) TO authenticated;
SELECT pg_catalog.pg_notify('pgrst','reload schema');
