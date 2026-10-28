-- SOURCE-ONLY: owner preview of real governed rhythm candidates.
-- No tasks, decisions, observations or assignments are inserted.
-- The same source can be consumed by a reviewed, capacity-bounded successor
-- writer; time alone does NOT prove physical weeds or mowing safety.
CREATE OR REPLACE FUNCTION atlas.owner_preview_standing_care_candidates_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,p_farm_id uuid,
 p_rhythm_key text,p_on_date date,p_campaign_id uuid DEFAULT NULL,
 p_limit integer DEFAULT 25
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $preview$
DECLARE
  v_owner uuid;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_rows jsonb;
  v_total integer;
  v_withheld integer;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_scope_id IS NULL OR p_farm_id IS NULL OR p_on_date IS NULL
    OR p_rhythm_key IS NULL OR p_rhythm_key NOT IN ('weed_stewardship','mowing')
    OR p_limit NOT BETWEEN 1 AND 50
  THEN RAISE EXCEPTION 'Signed exact rhythm preview requested'
    USING ERRCODE='22023'; END IF;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id AND ledger_id=p_ledger_id
      AND organization_id=p_organization_id;
  IF v_scope.id IS NULL OR v_scope.scope_state<>'active'
    OR v_scope.worker_membership_id IS NOT NULL
    OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
    OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR v_scope.coverage_mode<>'ledger_all_work'
    OR v_scope.accepted_at IS NULL
    OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
    OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id)
    OR NOT EXISTS(SELECT 1 FROM atlas.farms f
      WHERE f.id=p_farm_id AND f.organization_id=p_organization_id
        AND f.status='active')
  THEN RAISE EXCEPTION 'No governed active Person/Farm scope for preview'
    USING ERRCODE='42501'; END IF;

  WITH candidates AS MATERIALIZED (
    SELECT s.id rhythm_state_id,s.subject_id,g.label subject_label,
      r.id rule_id,r.rule_key,r.validity_interval_seconds,
      s.due_at,
      coalesce(
        extract(epoch FROM ((p_on_date::timestamp AT TIME ZONE
          coalesce(nullif(r.metadata->>'timezoneName',''),
            nullif(f.metadata->>'timezoneName',''),'UTC'))-s.due_at))
          /greatest(r.validity_interval_seconds,86400),
        0
      ) overdue_cycles,
      atlas.has_current_subject_disclosure_v1(p_ledger_id,
        v_scope.worker_person_id,'spatial','growing_object',
        s.subject_id,'identity') identity_disclosed,
      atlas.has_current_subject_disclosure_v1(p_ledger_id,
        v_scope.worker_person_id,'spatial','growing_object',
        s.subject_id,'condition') condition_disclosed
    FROM atlas.rhythm_state s
    JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
      AND b.organization_id=p_organization_id AND b.farm_id=p_farm_id
      AND b.active
    JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
      AND r.id=s.rhythm_rule_id AND r.status='active'
    JOIN atlas.growing_objects g ON g.id=s.subject_id
      AND g.farm_id=p_farm_id
    JOIN atlas.farms f ON f.id=s.farm_id
      AND f.organization_id=p_organization_id AND f.status='active'
    WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
      AND s.subject_kind='growing_object'
      AND s.rhythm_key=p_rhythm_key AND s.state<>'paused'
      AND (r.validity_interval_seconds IS NOT NULL
        AND r.validity_interval_seconds>0)
      AND NOT EXISTS (
        SELECT 1 FROM atlas.work_items w
        WHERE w.organization_id=p_organization_id
          AND w.source_object_type='rhythm_state'
          AND w.source_object_id=s.id AND w.work_state='open'
      )
      AND NOT EXISTS (
        SELECT 1 FROM atlas.tasks t
        LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
        WHERE t.farm_id=p_farm_id AND t.status IN ('open','blocked')
          AND (t.metadata->>'rhythm_state_id'=s.id::text
            OR (o.source_kind='rhythm_state' AND o.source_id=s.id))
      )
      AND (p_campaign_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM atlas.work_items served
        WHERE served.organization_id=p_organization_id
          AND served.metadata->>'sourceStandingCampaignId'=p_campaign_id::text
          AND served.metadata->>'sourceSubjectId'=s.subject_id::text
          AND served.work_state IN ('completed','open')
      ))
  ), ranked AS (
    SELECT c.*,row_number() OVER(
      ORDER BY c.overdue_cycles DESC,c.validity_interval_seconds ASC,
        c.subject_label,c.rhythm_state_id
    ) position FROM candidates c
  )
  SELECT count(*)::integer,
    count(*) FILTER (WHERE NOT identity_disclosed OR NOT condition_disclosed)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'rhythmStateId',rhythm_state_id,'subjectId',subject_id,
      'subjectLabel',subject_label,'sourceRuleId',rule_id,'ruleKey',rule_key,
      'normalIntervalSeconds',validity_interval_seconds,
      'rhythmDueAt',due_at,
      'priorityPosition',position,
      'releasableToConnectedPerson',identity_disclosed AND condition_disclosed,
      'requiresSourceDisclosure',NOT(identity_disclosed AND condition_disclosed),
      'eligibilityBasis','owner_standing_visit_not_physical_condition'
    ) ORDER BY position) FILTER (WHERE position<=p_limit),'[]'::jsonb)
  INTO v_total,v_withheld,v_rows FROM ranked;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','standing_care_candidate_preview_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'farmId',p_farm_id,'rhythmKey',p_rhythm_key,
    'workerPersonId',v_scope.worker_person_id,'viewDate',p_on_date,
    'candidateCount',v_total,'missingDisclosureCount',v_withheld,
    'candidates',v_rows,'newWorkCreated',false,
    'doesNotAssertPhysicalNeed',true);
END;
$preview$;

REVOKE ALL ON FUNCTION atlas.owner_preview_standing_care_candidates_self_api_v1(
 uuid,uuid,uuid,uuid,text,date,uuid,integer
) FROM PUBLIC,anon,authenticated,service_role;
