-- HELD SOURCE-ONLY candidate stacked on Noel #2362.
-- Discover ONLY a signed native Person's explicitly disclosed standing care
-- expectations. A cadence is not an original Work, deadline or overdue task.
CREATE OR REPLACE FUNCTION atlas.connected_person_disclosed_standing_rhythms_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_limit integer DEFAULT 30,
 p_after_state_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $rhythms$
DECLARE
 v_person uuid;
 v_items jsonb := '[]'::jsonb;
 v_has_more boolean := false;
 v_last uuid;
BEGIN
 IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
   OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
   RAISE EXCEPTION 'Signed bounded Ledger source required' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL THEN
   RAISE EXCEPTION 'Current native Person required' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_person) THEN
   RAISE EXCEPTION 'Exact native Ledger connection required' USING ERRCODE='42501';
 END IF;

 WITH admitted AS MATERIALIZED (
   SELECT s.id state_id,s.rhythm_key rhythm_kind,
     g.label subject_label,r.label rhythm_label,
     r.validity_interval_seconds cadence_seconds,s.warning_at,s.due_at
   FROM atlas.rhythm_state s
   JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
     AND b.rhythm_rule_id=s.rhythm_rule_id AND b.active
     AND b.organization_id=p_organization_id AND b.farm_id=s.farm_id
   JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
     AND r.organization_id=p_organization_id AND r.status='active'
   JOIN atlas.farms f ON f.id=s.farm_id
     AND f.organization_id=p_organization_id AND f.status='active'
   JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=s.farm_id
   JOIN LATERAL (
     SELECT e.* FROM atlas.continuing_work_source_governance_events_v1 e
     WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
       AND e.source_kind='rhythm_state' AND e.source_id=s.id
     ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1
   ) policy ON TRUE
   JOIN atlas.company_work_standing_assignment_scopes scope
     ON scope.id=policy.worker_scope_id
     AND scope.organization_id=p_organization_id
     AND scope.ledger_id=p_ledger_id AND scope.worker_person_id=v_person
   WHERE s.organization_id=p_organization_id
     AND s.subject_kind='growing_object'
     AND s.rhythm_key IN ('mowing','weed_stewardship')
     AND s.state <> 'paused'
     AND (p_after_state_id IS NULL OR s.id>p_after_state_id)
     AND policy.authorization_method='standing_source_observed'
     AND policy.worker_visibility='eligible_disclosed'
     AND scope.scope_state='active'
     AND scope.accepted_at IS NOT NULL
     AND scope.accepted_by_person_id=v_person
     AND scope.worker_membership_id IS NULL
     AND scope.coverage_mode='ledger_all_work'
     AND (scope.valid_until IS NULL OR scope.valid_until>now())
     AND atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person,'spatial','growing_object',s.subject_id,'identity')
     AND atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person,'spatial','growing_object',s.subject_id,'condition')
   ORDER BY s.id
   LIMIT (p_limit+1)
 ), numbered AS (
   SELECT admitted.*,row_number() over(ORDER BY state_id) ordinal
   FROM admitted
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'rhythmStateId',state_id,'rhythmKind',rhythm_kind,
   'rhythmLabel',rhythm_label,'subjectLabel',subject_label,
   'cadenceSeconds',cadence_seconds,'cadenceWarningAt',warning_at,
   'cadenceDueAt',due_at,'isWork',false,'isAssignment',false
 ) ORDER BY state_id) FILTER(WHERE ordinal<=p_limit),'[]'::jsonb),
 count(*)>p_limit,(max(state_id::text) FILTER(WHERE ordinal<=p_limit))::uuid
 INTO v_items,v_has_more,v_last FROM numbered;

 RETURN jsonb_build_object(
   'ok',true,'contractVersion','connected_person_disclosed_standing_rhythms_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'items',v_items,'hasMore',v_has_more,
   'nextAfterStateId',CASE WHEN v_has_more THEN v_last ELSE NULL END,
   'coverage','admitted_person_only','noUndisclosedCounts',true,
   'noWorkCreated',true,'notAnExecutionPlan',true,
   'notAnAutomaticOverdueBacklog',true);
END;
$rhythms$;
REVOKE ALL ON FUNCTION atlas.connected_person_disclosed_standing_rhythms_self_api_v1(
 uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_limit integer DEFAULT 30,
 p_after_state_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.connected_person_disclosed_standing_rhythms_self_api_v1(
   p_organization_id,p_ledger_id,p_limit,p_after_state_id);
$public$;
REVOKE ALL ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1(
 uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1(
 uuid,uuid,integer,uuid) TO authenticated;
