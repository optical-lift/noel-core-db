-- UNI-OPS-01 / company-neutral case decision receipt, HELD.
-- A principal reading one already authorized case does NOT become authorized
-- to see Subject/worker/source details. This reader reveals NO raw source
-- key, Subject identity, narrative or Person roster. Real domain disclosure
-- and current source fitness must be enforced by a separate adapter.
CREATE FUNCTION atlas.uni_ops_company_governed_case_receipt_self_held_v1(
 p_case_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $receipt$
DECLARE
 v_case atlas.uni_ops_governed_source_cases_v1%ROWTYPE;
 v_decision atlas.uni_ops_governed_case_decision_events_v1%ROWTYPE;
 v_root uuid;
 v_latest_is_this boolean:=false;
BEGIN
 IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL
    OR p_case_id IS NULL
 THEN RAISE EXCEPTION 'Known current signed governing case required'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_case FROM atlas.uni_ops_governed_source_cases_v1
 WHERE id=p_case_id;
 IF v_case.id IS NULL THEN
   RAISE EXCEPTION 'Governed source case unavailable' USING ERRCODE='42501';
 END IF;
 v_root:=atlas.company_work_native_ledger_owner_self_v1(
    v_case.organization_id,v_case.governing_ledger_id);
 IF v_root IS NULL OR v_root IS DISTINCT FROM
    atlas.current_person_id_v1()
    OR NOT EXISTS(
      SELECT 1 FROM atlas.organizations o
      JOIN atlas.ledgers l ON l.id=v_case.governing_ledger_id
        AND l.organization_id=o.id AND l.status='active'
      JOIN atlas.ledger_organization_participations p
        ON p.ledger_id=l.id AND p.organization_id=o.id
        AND p.status='active' AND p.ended_at IS NULL
        AND p.participation_kind='governing'
        AND p.is_compatibility_primary=true
      WHERE o.id=v_case.organization_id AND o.status='active')
 THEN RAISE EXCEPTION 'Current governing Company Ledger root required'
    USING ERRCODE='42501'; END IF;

 SELECT NOT EXISTS(
   SELECT 1 FROM atlas.uni_ops_governed_source_cases_v1 newer
   WHERE newer.organization_id=v_case.organization_id
     AND newer.governing_ledger_id=v_case.governing_ledger_id
     AND newer.source_domain=v_case.source_domain
     AND newer.source_kind=v_case.source_kind
     AND newer.source_key=v_case.source_key
     AND newer.source_admission_state='source_verified_by_adapter'
     AND (newer.source_registered_at,newer.id)>
         (v_case.source_registered_at,v_case.id)
 ) INTO v_latest_is_this;

 SELECT * INTO v_decision
 FROM atlas.uni_ops_governed_case_decision_events_v1 e
 WHERE e.case_id=v_case.id
 ORDER BY e.decided_at DESC,e.id DESC
 LIMIT 1;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,
  'contractVersion','uni_ops_company_governed_case_receipt_v1',
  'caseId',v_case.id,
  'sourceCaseRegisteredAt',v_case.source_registered_at,
  'sourceEvidenceRecordedAt',v_case.source_evidence_recorded_at,
  'domainAdapterMarkedVerified',
     v_case.source_admission_state='source_verified_by_adapter',
  'latestRegisteredAdmittedRevision',v_latest_is_this,
  'latestGovernorDecisionId',v_decision.id,
  'latestGovernorDecisionAt',v_decision.decided_at,
  'latestGovernorDecisionOutcome',v_decision.outcome,
  'currentDomainSourceStillNeedsFreshProof',true,
  'realSourceSubjectDisclosureWasNotGrantedByThisReader',true,
  'permissionToCreateOriginalWork',false,
  'permissionToAssignWorker',false,
  'permissionToPlacePrincipalClockCandidate',false,
  'permissionToAcceptActualOrDone',false,
  'permissionToAutoCreateNextWork',false);
END;
$receipt$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
