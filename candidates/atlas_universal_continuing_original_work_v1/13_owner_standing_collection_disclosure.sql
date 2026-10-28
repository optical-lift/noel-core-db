-- DRAFT / SOURCE ONLY: rooted owner can authorize the exact currently
-- bound real Subject collection for an accepted native connected Person.
-- Existing explicit per-Subject WITHHOLD decisions are never silently
-- overridden. No permission, Work or task exists unless this signed call
-- is separately approved and released.
CREATE OR REPLACE FUNCTION atlas.governor_grant_standing_care_collection_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
  p_farm_id uuid,p_rhythm_key text,p_action_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $bulk$
DECLARE
  v_owner uuid;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_row record;
  v_class text;
  v_current text;
  v_subject_count integer;
  v_granted integer:=0;
  v_existing integer:=0;
  v_withheld integer:=0;
  v_result jsonb;
  v_action uuid;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_scope_id IS NULL OR p_farm_id IS NULL OR p_action_id IS NULL
    OR p_rhythm_key NOT IN ('weed_stewardship','mowing')
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 900 THEN
    RAISE EXCEPTION 'Exact signed collection and reason required' USING ERRCODE='22023';
  END IF;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  SELECT * INTO v_scope
  FROM atlas.company_work_standing_assignment_scopes s
  WHERE s.id=p_scope_id AND s.organization_id=p_organization_id
    AND s.ledger_id=p_ledger_id
    AND s.scope_state='active'
    AND s.worker_membership_id IS NULL
    AND s.proposed_by_person_id=v_owner
    AND s.accepted_by_person_id=s.worker_person_id
    AND s.accepted_at IS NOT NULL
    AND s.coverage_mode='ledger_all_work'
    AND (s.valid_until IS NULL OR s.valid_until>now());
  IF v_scope.id IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_scope.worker_person_id)
    OR NOT EXISTS(SELECT 1 FROM atlas.farms f WHERE f.id=p_farm_id
      AND f.organization_id=p_organization_id AND f.status='active')
  THEN RAISE EXCEPTION 'Current accepted native Person and farm not proven'
    USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.standing-collection-disclosure:'||p_ledger_id::text||':'||
      p_scope_id::text||':'||p_farm_id::text||':'||p_rhythm_key,0));
  SELECT count(*)::integer INTO v_subject_count
  FROM atlas.rhythm_state s
  JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id AND b.active
    AND b.organization_id=p_organization_id AND b.farm_id=p_farm_id
  JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
    AND r.id=s.rhythm_rule_id AND r.status='active'
  JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=p_farm_id
  WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
    AND s.rhythm_key=p_rhythm_key AND s.subject_kind='growing_object'
    AND s.state<>'paused';
  IF v_subject_count<1 OR v_subject_count>150 THEN
    RAISE EXCEPTION 'Collection size outside bounded owner approval'
      USING ERRCODE='23514';
  END IF;
  FOR v_row IN
    SELECT DISTINCT s.subject_id
    FROM atlas.rhythm_state s
    JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id AND b.active
      AND b.organization_id=p_organization_id AND b.farm_id=p_farm_id
    JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
      AND r.id=s.rhythm_rule_id AND r.status='active'
    JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=p_farm_id
    WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
      AND s.rhythm_key=p_rhythm_key AND s.subject_kind='growing_object'
      AND s.state<>'paused'
    ORDER BY s.subject_id
  LOOP
    FOREACH v_class IN ARRAY ARRAY['identity','condition']::text[] LOOP
      -- The same lock used by the exact single-Subject governor writer
      -- prevents a concurrent WITHHOLD being silently overridden.
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'atlas.subject_disclosure:'||p_ledger_id::text||':'||
        v_scope.worker_person_id::text||':spatial:growing_object:'||
        v_row.subject_id::text||':'||v_class,0));
      v_current:=NULL;
      SELECT d.decision_kind INTO v_current
      FROM atlas.subject_disclosure_decision_events_v1 d
      WHERE d.ledger_id=p_ledger_id
        AND d.target_person_id=v_scope.worker_person_id
        AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
        AND d.subject_id=v_row.subject_id AND d.disclosure_class=v_class
      ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1;
      IF v_current='withhold' THEN
        v_withheld:=v_withheld+1;CONTINUE;
      ELSIF v_current='grant' THEN
        v_existing:=v_existing+1;CONTINUE;
      END IF;
      v_action:=pg_catalog.md5(p_action_id::text||':'||
        v_row.subject_id::text||':'||v_class)::uuid;
      v_result:=atlas.governor_set_subject_disclosure_self_api_v1(
        p_organization_id,p_ledger_id,v_scope.worker_person_id,
        'spatial','growing_object',v_row.subject_id,v_class,'grant',
        v_action,'Owner explicitly approved this bounded routine care collection: '||v_reason);
      IF v_result->>'ok' IS DISTINCT FROM 'true'
        OR v_result->>'currentlyGranted' IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'Exact Subject disclosure receipt not verified'
          USING ERRCODE='23514';
      END IF;
      v_granted:=v_granted+1;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','standing_collection_disclosure_v1',
    'farmId',p_farm_id,'rhythmKey',p_rhythm_key,'scopeId',p_scope_id,
    'workerPersonId',v_scope.worker_person_id,
    'subjectCount',v_subject_count,'newFieldGrants',v_granted,
    'existingFieldGrants',v_existing,'retainedWithholdFields',v_withheld,
    'sourceActionId',p_action_id,'workCreated',false);
END;
$bulk$;

-- Grant only AFTER exact signed governor, worker, unrelated, revoked and
-- existing-withhold tests. Never execute as SQL admin on the user's behalf.
REVOKE ALL ON FUNCTION atlas.governor_grant_standing_care_collection_self_api_v1(
 uuid,uuid,uuid,uuid,text,uuid,text
) FROM PUBLIC,anon,authenticated,service_role;
