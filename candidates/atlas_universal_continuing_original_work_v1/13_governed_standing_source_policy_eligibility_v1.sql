-- HELD DRAFT. Universal source-governed standing Work authority, version 1.
-- No new Work or Today/Clock row is created by this file. Do not deploy.
-- The only eligible source adapter presently admitted is an exact governed
-- organization Rhythm state. Future domains must add their own source gate.
-- Three distinct decisions are preserved: condition/timing, governor-selected
-- admission authority, and owner/worker source disclosure. None implies another.

CREATE TABLE atlas.continuing_work_source_governance_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 ledger_id uuid NOT NULL,
 source_kind text NOT NULL CHECK (source_kind='rhythm_state'),
 source_id uuid NOT NULL,
 worker_scope_id uuid NOT NULL,
 action_id uuid NOT NULL,
 authorization_method text NOT NULL CHECK (
   authorization_method IN ('owner_each_cycle','standing_source_observed','hold')),
 governor_visibility text NOT NULL CHECK (
   governor_visibility IN ('full_eligibility','exceptions_only')),
 worker_visibility text NOT NULL CHECK (
   worker_visibility IN ('assigned_work_only','eligible_disclosed')),
 eligibility_window text NOT NULL CHECK (eligibility_window IN ('warning','due')),
 observation_max_age_seconds integer NOT NULL CHECK (
   observation_max_age_seconds BETWEEN 3600 AND 604800),
 decided_by_person_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 reason text NOT NULL CHECK (length(reason) BETWEEN 10 AND 1500),
 decision_contract text NOT NULL DEFAULT 'continuing_source_governance_v1'
   CHECK (decision_contract='continuing_source_governance_v1'),
 UNIQUE (organization_id,ledger_id,source_kind,source_id,action_id)
);
ALTER TABLE atlas.continuing_work_source_governance_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.continuing_work_source_governance_events_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- Immutable custody: changing a newer decision means appending a NEW event.
CREATE OR REPLACE FUNCTION atlas.block_continuing_source_governance_mutation_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $block$
BEGIN
 RAISE EXCEPTION 'Standing authority history is append-only'
 USING ERRCODE='42501';
END;
$block$;
REVOKE ALL ON FUNCTION atlas.block_continuing_source_governance_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER continuing_work_source_governance_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.continuing_work_source_governance_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_continuing_source_governance_mutation_v1();

-- Owner chooses the method at setup or replaces it only through another
-- immutable signed owner decision. No user_metadata/legacy employee seats.
CREATE OR REPLACE FUNCTION atlas.owner_decide_continuing_source_governance_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_rhythm_state_id uuid,
 p_scope_id uuid, p_authorization_method text,
 p_governor_visibility text, p_worker_visibility text,
 p_eligibility_window text, p_observation_max_age_seconds integer,
 p_reason text, p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $decide$
DECLARE
 v_owner uuid;
 v_state atlas.rhythm_state%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_current atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_event atlas.continuing_work_source_governance_events_v1%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL
 OR p_organization_id IS NULL OR p_ledger_id IS NULL
 OR p_rhythm_state_id IS NULL OR p_scope_id IS NULL OR p_action_id IS NULL
 OR p_authorization_method IS NULL OR p_authorization_method
    NOT IN ('owner_each_cycle','standing_source_observed','hold')
 OR p_governor_visibility NOT IN ('full_eligibility','exceptions_only')
 OR p_worker_visibility NOT IN ('assigned_work_only','eligible_disclosed')
 OR p_eligibility_window NOT IN ('warning','due')
 OR p_observation_max_age_seconds NOT BETWEEN 3600 AND 604800
 OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 10 AND 1500
 THEN RAISE EXCEPTION 'Complete bounded governing decision required' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_owner IS DISTINCT FROM atlas.current_person_id_v1() THEN
   RAISE EXCEPTION 'Only the native Ledger governor may decide source authority'
   USING ERRCODE='42501';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.continuing-source-policy:'||p_organization_id||':'||p_ledger_id||':'||p_rhythm_state_id,0));
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
   AND s.subject_kind='growing_object' FOR SHARE;
 IF v_state.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.rhythm_bindings b JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
   WHERE b.id=v_state.rhythm_binding_id AND b.organization_id=p_organization_id
   AND b.farm_id=v_state.farm_id AND b.active
   AND r.id=v_state.rhythm_rule_id AND r.status='active'
 ) THEN
   RAISE EXCEPTION 'Only an established active native Rhythm may be governed'
   USING ERRCODE='23514';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=p_scope_id AND s.organization_id=p_organization_id
   AND s.ledger_id=p_ledger_id FOR SHARE;
 IF v_scope.id IS NULL OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
 OR v_scope.scope_state<>'active' OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR v_scope.coverage_mode<>'ledger_all_work'
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
       p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN
   RAISE EXCEPTION 'Accepted, bounded connected-Person Ledger scope required'
   USING ERRCODE='42501';
 END IF;
 -- A standing authority never substitutes for the Subject disclosure decision.
 -- At configuration, do not demand disclosure (it may be granted later);
 -- eligibility and actual Work admission separately require both exact grants.
 SELECT * INTO v_event FROM atlas.continuing_work_source_governance_events_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
 AND e.source_kind='rhythm_state' AND e.source_id=p_rhythm_state_id
 AND e.action_id=p_action_id;
 IF v_event.id IS NOT NULL THEN
   IF v_event.worker_scope_id IS DISTINCT FROM p_scope_id
   OR v_event.authorization_method IS DISTINCT FROM p_authorization_method
   OR v_event.governor_visibility IS DISTINCT FROM p_governor_visibility
   OR v_event.worker_visibility IS DISTINCT FROM p_worker_visibility
   OR v_event.eligibility_window IS DISTINCT FROM p_eligibility_window
   OR v_event.observation_max_age_seconds IS DISTINCT FROM p_observation_max_age_seconds
   OR v_event.reason IS DISTINCT FROM btrim(p_reason) THEN
      RAISE EXCEPTION 'Governing action retry cannot alter authority' USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'policyEventId',v_event.id,
     'idempotent',true,'authorizationMethod',v_event.authorization_method);
 END IF;
 SELECT * INTO v_current FROM atlas.continuing_work_source_governance_events_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
 AND e.source_kind='rhythm_state' AND e.source_id=p_rhythm_state_id
 ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1;
 IF v_current.id IS NOT NULL AND v_current.worker_scope_id<>p_scope_id
   AND p_authorization_method<>'hold' THEN
   -- Switching the carrier is a different native connection decision.
   -- Do not silently replace an accepted Person using a new policy event.
   RAISE EXCEPTION 'Explicit hold is required before changing the entrusted carrier'
   USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.continuing_work_source_governance_events_v1(
   organization_id,ledger_id,source_kind,source_id,worker_scope_id,action_id,
   authorization_method,governor_visibility,worker_visibility,eligibility_window,
   observation_max_age_seconds,decided_by_person_id,reason
 ) VALUES(
   p_organization_id,p_ledger_id,'rhythm_state',p_rhythm_state_id,p_scope_id,p_action_id,
   p_authorization_method,p_governor_visibility,p_worker_visibility,p_eligibility_window,
   p_observation_max_age_seconds,v_owner,btrim(p_reason)
 ) RETURNING * INTO v_event;
 RETURN jsonb_build_object('ok',true,'contractVersion','continuing_source_governance_v1',
   'policyEventId',v_event.id,'idempotent',false,
   'authorizationMethod',v_event.authorization_method,
   'governorVisibility',v_event.governor_visibility,
   'workerVisibility',v_event.worker_visibility,
   'noWorkCreated',true,'noImplicitDayScheduled',true);
END;
$decide$;
REVOKE ALL ON FUNCTION atlas.owner_decide_continuing_source_governance_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.owner_decide_continuing_source_governance_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_rhythm_state_id uuid,
 p_scope_id uuid, p_authorization_method text, p_governor_visibility text,
 p_worker_visibility text, p_eligibility_window text,
 p_observation_max_age_seconds integer, p_reason text, p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.owner_decide_continuing_source_governance_self_api_v1(
 p_organization_id,p_ledger_id,p_rhythm_state_id,p_scope_id,p_authorization_method,
 p_governor_visibility,p_worker_visibility,p_eligibility_window,
 p_observation_max_age_seconds,p_reason,p_action_id);
$public$;
REVOKE ALL ON FUNCTION public.owner_decide_continuing_source_governance_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.owner_decide_continuing_source_governance_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid
) TO authenticated;

-- Read-only source eligibility, not a task generator or an owner Clock.
-- Evaluates rule time window + actual post-satisfaction physical observations.
-- Connected workers receive no source details without accepted scope AND both
-- exact identity and condition disclosure decisions, plus governor's worker
-- visibility configuration. Unconfigured sources fail closed.
CREATE OR REPLACE FUNCTION atlas.continuing_work_source_eligibility_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $eligible$
DECLARE
 v_actor uuid;
 v_owner uuid;
 v_is_owner boolean:=false;
 v_state atlas.rhythm_state%ROWTYPE;
 v_policy atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_rule atlas.rhythm_rules%ROWTYPE;
 v_observation atlas.care_observation_events%ROWTYPE;
 v_current atlas.care_current_state%ROWTYPE;
 v_reason text:='source_unavailable';
 v_eligible boolean:=false;
 v_window_at timestamptz;
 v_last_satisfied_at timestamptz;
 v_has_open boolean:=false;
 v_legacy_open boolean:=false;
 v_physical_ok boolean:=false;
BEGIN
 v_actor:=atlas.current_person_id_v1();
 IF auth.uid() IS NULL OR v_actor IS NULL
   OR p_organization_id IS NULL OR p_ledger_id IS NULL
   OR p_rhythm_state_id IS NULL THEN
   RAISE EXCEPTION 'Signed exact Work source required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_policy FROM atlas.continuing_work_source_governance_events_v1 p
 WHERE p.organization_id=p_organization_id AND p.ledger_id=p_ledger_id
 AND p.source_kind='rhythm_state' AND p.source_id=p_rhythm_state_id
 ORDER BY p.recorded_at DESC,p.id DESC LIMIT 1;
 IF v_policy.id IS NULL OR v_policy.authorization_method='hold' THEN
   RAISE EXCEPTION 'Standing Work source is not currently disclosed'
   USING ERRCODE='42501';
 END IF;
 BEGIN
   v_owner:=atlas.company_work_native_ledger_owner_self_v1(
     p_organization_id,p_ledger_id);
   v_is_owner:=(v_owner=v_actor);
 EXCEPTION WHEN SQLSTATE '42501' THEN
   v_is_owner:=false;
 END;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=v_policy.worker_scope_id AND s.organization_id=p_organization_id
 AND s.ledger_id=p_ledger_id;
 IF v_scope.id IS NULL OR v_scope.scope_state<>'active'
 OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.coverage_mode<>'ledger_all_work'
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
       p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN
   RAISE EXCEPTION 'Current entrusted native connection is required' USING ERRCODE='42501';
 END IF;
 IF NOT v_is_owner THEN
   IF v_actor IS DISTINCT FROM v_scope.worker_person_id
    OR v_policy.worker_visibility<>'eligible_disclosed'
    OR NOT atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_actor,'spatial','growing_object',
       (SELECT s.subject_id FROM atlas.rhythm_state s
        WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id),'identity')
    OR NOT atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_actor,'spatial','growing_object',
       (SELECT s.subject_id FROM atlas.rhythm_state s
        WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id),'condition')
   THEN
     RAISE EXCEPTION 'Standing eligibility is not disclosed to this Person'
       USING ERRCODE='42501';
   END IF;
 END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
 AND s.subject_kind='growing_object';
 SELECT * INTO v_rule FROM atlas.rhythm_rules r
 JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
 WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
 AND b.organization_id=p_organization_id AND b.farm_id=v_state.farm_id
 AND b.active AND r.status='active';
 IF v_state.id IS NULL OR v_rule.id IS NULL OR v_state.state='paused'
 OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
 OR NOT EXISTS(SELECT 1 FROM atlas.farms f
   WHERE f.id=v_state.farm_id AND f.organization_id=p_organization_id AND f.status='active')
 OR NOT EXISTS(SELECT 1 FROM atlas.growing_objects g
   WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id)
 THEN
   v_reason:='source_unavailable';
 ELSE
   v_window_at:=CASE WHEN v_policy.eligibility_window='warning'
     THEN v_state.warning_at ELSE v_state.due_at END;
   IF v_window_at IS NULL OR now()<v_window_at THEN
     v_reason:='rhythm_window_not_reached';
   ELSE
     SELECT sat.satisfied_at INTO v_last_satisfied_at
     FROM atlas.rhythm_satisfactions sat
     WHERE sat.id=v_state.last_qualifying_satisfaction_id
       AND sat.rhythm_state_id=v_state.id;
     SELECT * INTO v_current FROM atlas.care_current_state cs
     WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
       AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
       AND cs.subject_id=v_state.subject_id::text;
     SELECT * INTO v_observation FROM atlas.care_observation_events e
     WHERE e.id=v_current.last_observation_id
       AND e.scope_kind='farm' AND e.scope_id=v_state.farm_id
       AND e.subject_kind='growing_object'
       AND e.subject_id=v_state.subject_id::text
       AND NOT e.inferred_from_clock AND e.observed_by_user_id IS NOT NULL
       AND e.observed_at>coalesce(v_last_satisfied_at,'-infinity'::timestamptz)
       AND e.observed_at>=now()-
          (v_policy.observation_max_age_seconds*interval '1 second')
       AND e.observed_at<=now()+interval '5 minutes';
     IF v_current.id IS NULL OR v_observation.id IS NULL
       OR v_current.last_observed_at IS DISTINCT FROM v_observation.observed_at
       OR v_current.condition_state IS DISTINCT FROM v_observation.condition_state
     THEN
       v_reason:='fresh_physical_observation_required';
     ELSE
       IF v_state.rhythm_key='weed_stewardship' THEN
         v_physical_ok:=v_observation.condition_state IN (
           'needs_inspection','row_readable','medium_pressure','heavy')
           AND EXISTS(SELECT 1 FROM atlas.weed_cards c
             WHERE c.farm_id=v_state.farm_id AND c.object_id=v_state.subject_id)
           AND atlas.care_strategy_allows_ordinary_weeding_v1(
             v_state.subject_id,v_observation.observed_at::date);
       ELSE
         v_physical_ok:=v_observation.condition_state IN (
           'needs_inspection','ready_for_mowing','overgrown')
           AND EXISTS(SELECT 1 FROM atlas.mowing_area_state m
             WHERE m.farm_id=v_state.farm_id AND m.object_id=v_state.subject_id
             AND m.organization_id=p_organization_id AND m.status<>'closed');
       END IF;
       IF NOT v_physical_ok THEN
         v_reason:='physical_condition_or_strategy_not_eligible';
       ELSE
         SELECT EXISTS(SELECT 1 FROM atlas.work_items w
           WHERE w.organization_id=p_organization_id
           AND w.source_object_type='rhythm_state'
           AND w.source_object_id=v_state.id AND w.work_state='open')
           INTO v_has_open;
         SELECT EXISTS(
           SELECT 1 FROM atlas.tasks t
           LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
           WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
             AND (t.metadata->>'rhythm_state_id'=v_state.id::text
               OR (o.source_kind='rhythm_state' AND o.source_id=v_state.id))
         ) INTO v_legacy_open;
         IF v_has_open OR v_legacy_open THEN
           v_reason:='existing_work_already_serves_need';
         ELSE
           v_reason:='source_qualified_and_timing_eligible';
           v_eligible:=true;
         END IF;
       END IF;
     END IF;
   END IF;
 END IF;
 IF v_is_owner AND v_policy.governor_visibility='exceptions_only' AND v_eligible THEN
   RETURN jsonb_build_object('ok',true,'visible',false,
     'view','governor_exception_projection','noWorkCreated',true);
 END IF;
 -- Worker projection has no private notes, historical events, scope IDs,
 -- unrelated subjects, or private governor policy reason.
 IF NOT v_is_owner THEN
   RETURN jsonb_build_object('ok',true,'visible',true,
      'view','connected_person_disclosed_eligibility',
      'sourceId',v_state.id,'eligible',v_eligible,'reasonCode',v_reason,
      'noWorkCreated',true,'notAnAssignment',true,'notOnToday',true);
 END IF;
 RETURN jsonb_build_object('ok',true,'visible',true,
    'view','governor_eligibility',
    'sourceId',v_state.id,'eligible',v_eligible,'reasonCode',v_reason,
    'authorizationMethod',v_policy.authorization_method,
    'workerVisibility',v_policy.worker_visibility,
    'governorVisibility',v_policy.governor_visibility,
    'observationAt',v_observation.observed_at,
    'windowAt',v_window_at,
    'noWorkCreated',true,'notOnOwnerClock',true);
END;
$eligible$;
REVOKE ALL ON FUNCTION atlas.continuing_work_source_eligibility_self_api_v1(
 uuid,uuid,uuid
) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.continuing_work_source_eligibility_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.continuing_work_source_eligibility_self_api_v1(
 p_organization_id,p_ledger_id,p_rhythm_state_id);
$public$;
REVOKE ALL ON FUNCTION public.continuing_work_source_eligibility_self_api_v1(
 uuid,uuid,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.continuing_work_source_eligibility_self_api_v1(
 uuid,uuid,uuid
) TO authenticated;
SELECT pg_catalog.pg_notify('pgrst','reload schema');
