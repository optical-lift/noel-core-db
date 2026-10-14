BEGIN;

-- Atlas-only read membrane. This is a practitioner-visible IMPLEMENTATION
-- COVERAGE projection, not a private notebook read or completion decision.
-- No human data, entitlement, payment, or domain truth is written.
CREATE OR REPLACE FUNCTION atlas.implementation_personal_coverage_self_v1(
  p_implementation_case_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','reality','auth'
AS $coverage$
DECLARE
  v_person_id uuid;
  v_case_state text;
  v_principal_id uuid;
  v_subject_user_id uuid;
  v_household_id uuid;
  v_session_state text;
  v_identity_bound boolean := false;
  v_household_present boolean := false;
  v_bookplate_evidence boolean := false;
  v_discovery_evidence boolean := false;
  v_dated_task_receipt boolean := false;
BEGIN
  -- This authority already explicitly excludes an ordinary Personal Atlas login.
  IF NOT atlas.implementation_practitioner_authorized_self_v1() THEN
    RETURN jsonb_build_object('ok',false,'code','practitioner_authority_required');
  END IF;

  SELECT c.personal_subject_person_entity_id,c.state
    INTO v_person_id,v_case_state
  FROM atlas.implementation_cases c
  WHERE c.id=p_implementation_case_id AND c.case_origin='personal_atlas';

  IF v_person_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','personal_case_not_found');
  END IF;

  SELECT p.id,p.user_id,p.active_household_id
    INTO v_principal_id,v_subject_user_id,v_household_id
  FROM atlas.principals p
  WHERE p.person_id=v_person_id AND p.status='active'
  ORDER BY p.created_at,p.id LIMIT 1;

  v_identity_bound := v_principal_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM reality.auth_person_bindings b
      WHERE b.person_entity_id=v_person_id
        AND b.auth_user_id=v_subject_user_id
        AND b.binding_state='active' AND b.retired_at IS NULL
    )
    AND EXISTS (
      SELECT 1 FROM personal.atlases a
      WHERE a.person_entity_id=v_person_id AND a.native AND a.atlas_state='active'
    );

  v_household_present := v_principal_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM atlas.households h
      WHERE h.id=v_household_id AND h.principal_id=v_principal_id AND h.status='active'
    );

  IF v_principal_id IS NOT NULL THEN
    v_bookplate_evidence := EXISTS (
      SELECT 1 FROM atlas.personal_atlas_bookplate_events b
      WHERE b.principal_id=v_principal_id AND b.owner_user_id=v_subject_user_id
    );

    SELECT s.state INTO v_session_state
    FROM atlas.reality_discovery_sessions s
    WHERE s.principal_id=v_principal_id
      AND s.owner_user_id=v_subject_user_id AND s.session_kind='first_day'
    ORDER BY s.started_at DESC,s.id DESC LIMIT 1;

    v_discovery_evidence := EXISTS (
      SELECT 1 FROM atlas.reality_discovery_evidence_candidates e
      WHERE e.principal_id=v_principal_id
        AND e.owner_user_id=v_subject_user_id
        AND e.epistemic_state IN ('human_confirmed','promoted')
    );

    -- Evidence of ONE narrow action type, not proof of real-life completion.
    v_dated_task_receipt := EXISTS (
      SELECT 1 FROM atlas.task_entries t
      WHERE t.principal_id=v_principal_id AND t.owner_user_id=v_subject_user_id
    );
  END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_personal_coverage_self_api_v1',
    'caseId',p_implementation_case_id,
    'caseOrigin','personal_atlas',
    'caseState',v_case_state,
    'readAt',now(),
    'observations',jsonb_build_object(
      'canonicalIdentity',CASE WHEN v_identity_bound THEN 'established' ELSE 'unresolved' END,
      'activeHousehold',CASE WHEN v_household_present THEN 'established' ELSE 'unresolved' END,
      'bookplateEvidence',CASE WHEN v_bookplate_evidence THEN 'recorded' ELSE 'not_observed' END,
      'firstDaySession',coalesce(v_session_state,'not_observed'),
      'discoveryEvidence',CASE WHEN v_discovery_evidence THEN 'recorded' ELSE 'not_observed' END,
      'datedTaskEntry',CASE WHEN v_dated_task_receipt THEN 'recorded' ELSE 'not_observed' END,
      'connectedSourceAssessment','not_assessed',
      'ledgerScopeAssessment','not_assessed',
      'domainPromotionAssessment','not_assessed',
      'completionDecision','not_evaluated'
    ),
    'boundary',jsonb_build_object(
      'privateFieldsReturned',false,
      'evidenceIsNotCanonicalPromotion',true,
      'absenceIsNotNegativeEvidence',true,
      'taskEntryIsNotCompletion',true,
      'noAutomaticClosure',true
    )
  );
END;
$coverage$;

CREATE OR REPLACE FUNCTION public.implementation_personal_coverage_self_api_v1(
  p_implementation_case_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $rpc$
  SELECT atlas.implementation_personal_coverage_self_v1(p_implementation_case_id);
$rpc$;

REVOKE ALL ON FUNCTION atlas.implementation_personal_coverage_self_v1(uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.implementation_personal_coverage_self_api_v1(uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.implementation_personal_coverage_self_api_v1(uuid)
  TO authenticated;

COMMIT;
