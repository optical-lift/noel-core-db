-- UNI-OPS-01 / ONE Company governor history, farm SOURCE wrapper only.
-- HELD, uncompiled, no public API grants or authority to issue Work.
-- A generic signed decision writer cannot validate crop/inventory truth;
-- this wrapper rechecks the real first-party source in the SAME atomic
-- transaction before entering ONE canonical company decision history.
-- Farm P3 17 independent governor decision table is NOT used or installed.

CREATE FUNCTION atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(
 p_case_id uuid,
 p_attention_id uuid,
 p_ledger_id uuid,
 p_outcome text,
 p_reason text,
 p_action_id uuid,
 p_expected_previous_decision_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $governed$
DECLARE
 v_attestation jsonb;
 v_case atlas.uni_ops_governed_source_cases_v1%ROWTYPE;
 v_link atlas.uni_ops_farm_company_source_links_v1%ROWTYPE;
 v_j atlas.journal_event_index%ROWTYPE;
 v_decision jsonb;
BEGIN
 IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL
    OR p_case_id IS NULL OR p_attention_id IS NULL
    OR p_ledger_id IS NULL OR p_action_id IS NULL
    OR p_outcome IS NULL OR p_outcome NOT IN (
      'request_independent_work_admission',
      'hold_for_more_source',
      'decline_new_action_at_present')
 THEN RAISE EXCEPTION 'Exact current signed farm-to-company choice required'
  USING ERRCODE='42501'; END IF;

 -- Operational owner attention is NOT eligible to directly ask for
 -- Principal arbitration. A separately verified cross-domain escalation
 -- threshold and protected Principal floor remain unbuilt.
 SELECT * INTO v_j FROM atlas.journal_event_index j
 WHERE j.id=p_attention_id FOR UPDATE;
 IF v_j.id IS NULL THEN
   RAISE EXCEPTION 'Original first-party attention source missing'
     USING ERRCODE='42501'; END IF;

 -- This source attestation rechecks exactly the original bucket observation
 -- or latest physical seed count + current uncovered production need,
 -- native farm/Company governing Ledger, and BOTH source Subject grants.
 v_attestation:=
   atlas.uni_ops_farm_current_attention_attestation_self_held_v1(
     p_attention_id,p_ledger_id);
 IF v_attestation->>'ok' IS DISTINCT FROM 'true'
    OR v_attestation->>'principalEscalationQualified'
      IS DISTINCT FROM 'false'
    OR v_attestation->>'subjectDisclosuresVerifiedCurrently'
      IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'Native source is no longer verified and disclosed'
    USING ERRCODE='42501'; END IF;

 SELECT * INTO v_case FROM atlas.uni_ops_governed_source_cases_v1 c
 WHERE c.id=p_case_id
   AND c.organization_id=(v_attestation->>'organizationId')::uuid
   AND c.governing_ledger_id=p_ledger_id
   AND c.source_domain='farm_operations'
   AND c.source_kind=v_attestation->>'sourceKind'
   AND c.source_key=v_attestation->>'sourceKey'
   AND c.source_revision_key=v_attestation->>'sourceRevisionKey'
   AND c.source_adapter_contract=v_attestation->>'sourceAdapterContract'
   AND c.source_attestation_fingerprint=
      v_attestation->>'sourceAttestationFingerprint'
   AND c.source_evidence_recorded_at=
      (v_attestation->>'sourceEvidenceRecordedAt')::timestamptz
   AND c.source_admission_state='source_verified_by_adapter'
   AND c.attention_contract='operational_governor_review_v1'
 FOR UPDATE;
 SELECT * INTO v_link FROM atlas.uni_ops_farm_company_source_links_v1 l
 WHERE l.case_id=v_case.id
   AND l.attention_journal_event_id=p_attention_id
   AND l.governing_ledger_id=p_ledger_id
   AND l.farm_id=(v_attestation->>'farmId')::uuid
   AND l.farm_source_kind=v_attestation->>'sourceKind'
   AND l.native_subject_id=(v_attestation->>'sourceSubjectId')::uuid
   AND l.native_evidence_event_id=
       (v_attestation->>'sourceEvidenceEventId')::uuid
   AND l.source_attestation_fingerprint=
       v_attestation->>'sourceAttestationFingerprint';
 IF v_case.id IS NULL OR v_link.case_id IS NULL THEN
   RAISE EXCEPTION
     'A real unchanged source-linked Company case is required before decision'
     USING ERRCODE='42501';
 END IF;

 -- Canonical decision is done through the ONE Company writer with the
 -- TRUE signed user, Company root, previous event CAS, and current case.
 -- This adapter never makes or accepts a worker/Work/Result/Clock.
 v_decision:=atlas.uni_ops_company_governor_decide_source_case_self_held_v1(
    v_case.id,p_outcome,p_reason,p_action_id,
    p_expected_previous_decision_id);
 IF v_decision->>'ok' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Company-governed decision failed closed'
     USING ERRCODE='42501'; END IF;

 RETURN pg_catalog.jsonb_build_object(
   'ok',true,
   'contractVersion','farm_to_company_one_governor_decision_held_v1',
   'companySourceCaseId',v_case.id,
   'sourceAttentionId',p_attention_id,
   'nativeEvidenceEventId',v_link.native_evidence_event_id,
   'decisionEventId',v_decision->'decisionEventId',
   'decisionRecordedAt',v_decision->'decisionRecordedAt',
   'decisionOutcome',v_decision->>'outcome',
   'replay',v_decision->'replay',
   'operationalGovernorDecisionOnly',true,
   'newWorkCreated',false,'workerAccepted',false,
   'principalEscalationQualified',false,
   'principalClockCandidateCreated',false,
   'separateAcceptedFirstOriginalSourceNeeded',true);
END;
$governed$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(
 uuid,uuid,uuid,text,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
