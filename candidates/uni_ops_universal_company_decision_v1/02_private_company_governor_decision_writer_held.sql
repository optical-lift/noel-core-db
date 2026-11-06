-- UNI-OPS-01 universal COMPANY GOVERNOR case decision / HELD.
-- This is a decision, never an original Work/Person/Clock/Result writer.
-- Do not expose through public RPC until source-adapter signatures,
-- domain freshness, current company role and genuine actor tests pass.
--
-- A caller's source IDs, subject names, Need claims, metadata or company
-- labels cannot create source_admission_state='source_verified_by_adapter'.
-- That status must come from a separately audited, domain-bounded
-- first-party source adapter. There is NO generic admission writer here.

CREATE FUNCTION atlas.uni_ops_company_governor_decide_source_case_self_held_v1(
 p_case_id uuid,
 p_outcome text,
 p_reason text,
 p_action_id uuid,
 p_expected_previous_decision_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $governor$
DECLARE
 v_case atlas.uni_ops_governed_source_cases_v1%ROWTYPE;
 v_latest atlas.uni_ops_governed_case_decision_events_v1%ROWTYPE;
 v_existing atlas.uni_ops_governed_case_decision_events_v1%ROWTYPE;
 v_decision atlas.uni_ops_governed_case_decision_events_v1%ROWTYPE;
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_current_root uuid;
 v_reason text:=pg_catalog.nullif(pg_catalog.btrim(p_reason),'');
BEGIN
 IF v_uid IS NULL OR v_person IS NULL OR p_case_id IS NULL
    OR p_action_id IS NULL OR p_outcome IS NULL
    OR p_outcome NOT IN(
      'request_independent_work_admission',
      'request_principal_arbitration',
      'hold_for_more_source',
      'decline_new_action_at_present')
    OR v_reason IS NULL
    OR pg_catalog.char_length(v_reason) NOT BETWEEN 12 AND 2000
 THEN
   RAISE EXCEPTION 'Exact current signed company source decision required'
     USING ERRCODE='42501';
 END IF;

 -- Case lock serializes multiple concurrent governors revising the
 -- SAME source Revision. Different revisions are distinct case IDs.
 SELECT * INTO v_case
 FROM atlas.uni_ops_governed_source_cases_v1 c
 WHERE c.id=p_case_id FOR UPDATE;
 IF v_case.id IS NULL
   OR v_case.source_admission_state IS DISTINCT FROM
      'source_verified_by_adapter'
 THEN
   RAISE EXCEPTION 'A source-attested admitted case is required'
     USING ERRCODE='42501';
 END IF;

 -- A later source revision must be reviewed as a NEW case; old source
 -- evidence and old governor choices are never rewritten/backdated.
 IF EXISTS(
   SELECT 1 FROM atlas.uni_ops_governed_source_cases_v1 newer
   WHERE newer.organization_id=v_case.organization_id
     AND newer.governing_ledger_id=v_case.governing_ledger_id
     AND newer.source_domain=v_case.source_domain
     AND newer.source_kind=v_case.source_kind
     AND newer.source_key=v_case.source_key
     AND newer.source_admission_state='source_verified_by_adapter'
     AND (newer.source_registered_at,newer.id)>
         (v_case.source_registered_at,v_case.id)
 ) THEN
   RAISE EXCEPTION 'Superseded source case must not be decided as current'
     USING ERRCODE='42501';
 END IF;

 -- A Company Ledger is a jurisdictional context, not just a label.
 -- Current native governing ROOT Person is independent from the worker,
 -- source evidence actor, service_role and technical DB function owner.
 v_current_root:=atlas.company_work_native_ledger_owner_self_v1(
    v_case.organization_id,v_case.governing_ledger_id);
 IF v_current_root IS NULL OR v_current_root IS DISTINCT FROM v_person
    OR NOT EXISTS(
      SELECT 1 FROM atlas.organizations o
      JOIN atlas.ledgers l
        ON l.id=v_case.governing_ledger_id
       AND l.organization_id=o.id AND l.status='active'
      JOIN atlas.ledger_organization_participations lop
        ON lop.ledger_id=l.id AND lop.organization_id=o.id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind='governing'
       AND lop.is_compatibility_primary=true
      WHERE o.id=v_case.organization_id AND o.status='active'
    )
 THEN
   RAISE EXCEPTION 'Current signed native Company Ledger governor required'
     USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_latest
 FROM atlas.uni_ops_governed_case_decision_events_v1 d
 WHERE d.case_id=v_case.id
 ORDER BY d.decided_at DESC,d.id DESC
 LIMIT 1 FOR UPDATE;

 SELECT * INTO v_existing
 FROM atlas.uni_ops_governed_case_decision_events_v1 d
 WHERE d.source_action_id=p_action_id;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.case_id IS DISTINCT FROM v_case.id
     OR v_existing.organization_id IS DISTINCT FROM
        v_case.organization_id
     OR v_existing.governing_ledger_id IS DISTINCT FROM
        v_case.governing_ledger_id
     OR v_existing.governor_person_id IS DISTINCT FROM v_person
     OR v_existing.governor_user_id IS DISTINCT FROM v_uid
     OR v_existing.outcome IS DISTINCT FROM p_outcome
     OR v_existing.reason IS DISTINCT FROM v_reason
     OR v_existing.previous_decision_event_id IS DISTINCT FROM
        p_expected_previous_decision_id
     OR v_existing.source_attestation_fingerprint IS DISTINCT FROM
        v_case.source_attestation_fingerprint
   THEN
      RAISE EXCEPTION 'Immutable source decision action conflicts with replay'
        USING ERRCODE='23505';
   END IF;
   RETURN pg_catalog.jsonb_build_object(
     'ok',true,'contractVersion',
       'uni_ops_company_governed_source_decision_v1',
     'decisionEventId',v_existing.id,'replay',true,
     'outcome',v_existing.outcome,
     'sourceCaseId',v_case.id,
     'workCreated',false,'workerAssigned',false,
     'principalClockEntered',false,
     'physicalActualAccepted',false);
 END IF;

 IF v_latest.id IS DISTINCT FROM p_expected_previous_decision_id THEN
   RAISE EXCEPTION 'Exact prior immutable governor decision required'
     USING ERRCODE='23505';
 END IF;

 INSERT INTO atlas.uni_ops_governed_case_decision_events_v1(
   case_id,organization_id,governing_ledger_id,
   source_action_id,previous_decision_event_id,
   governor_person_id,governor_user_id,outcome,reason,
   source_attestation_fingerprint)
 VALUES(
   v_case.id,v_case.organization_id,v_case.governing_ledger_id,
   p_action_id,p_expected_previous_decision_id,
   v_person,v_uid,p_outcome,v_reason,
   v_case.source_attestation_fingerprint)
 RETURNING * INTO v_decision;

 RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion',
     'uni_ops_company_governed_source_decision_v1',
   'sourceCaseId',v_case.id,
   'sourceEvidenceRecordedAt',v_case.source_evidence_recorded_at,
   'caseSourceRegisteredAt',v_case.source_registered_at,
   'decisionEventId',v_decision.id,
   'decisionRecordedAt',v_decision.decided_at,
   'outcome',v_decision.outcome,
   'replay',false,
   'independentWorkAdmissionRequested',
     v_decision.outcome='request_independent_work_admission',
   'independentWorkAdmissionAuthorized',false,
   'principalArbitrationRequested',
     v_decision.outcome='request_principal_arbitration',
   'principalClockCandidateCreated',false,
   'originalWorkCreated',false,'workerAssigned',false,
   'workerConsentCreated',false,
   'actualAccepted',false,'doneCreated',false,
   'successorWorkAutomaticallyCreated',false,
   'domainSourceFreshnessStillOwnedByAdapter',true,
   'separateSourceAuthorizedIssuerRequired',true);
END;
$governor$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_company_governor_decide_source_case_self_held_v1(
 uuid,text,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
