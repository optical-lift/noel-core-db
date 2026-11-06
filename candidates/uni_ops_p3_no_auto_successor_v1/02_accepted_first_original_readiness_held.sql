-- UNI-OPS-01: one pre-original source readiness envelope (HELD).
-- Dependencies: U1A #2465 + U1B #2481 + U2A/B #2482 + U2C #2485.
-- Reads but NEVER replaces the one Rulebook arbiter, existing offer protocol,
-- recipient acceptance or existing R02 canonical original writer.
-- This is NOT a public function, policy executable, issuer or scheduler.
CREATE FUNCTION atlas.uni_ops_accepted_first_original_source_receipt_held_v1(
  p_offer_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $receipt$
DECLARE
  v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
  v_authority jsonb;
  v_root uuid;
BEGIN
  IF p_offer_id IS NULL OR auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Exact signed original pre-Work offer required'
      USING ERRCODE='42501';
  END IF;

  -- This READ never chooses a Subject, Worker, date, policy or successor.
  -- All original receipt facts are read from the existing source.
  SELECT * INTO v_offer
  FROM atlas.governed_prework_candidate_offers_v1 o
  WHERE o.id=p_offer_id FOR SHARE;
  IF v_offer.id IS NULL
     OR v_offer.offer_state<>'accepted'
     OR v_offer.responded_at IS NULL
     OR v_offer.responding_principal_id IS NULL
     OR v_offer.response_action_id IS NULL
     OR v_offer.original_work_item_id IS NOT NULL
  THEN
    RAISE EXCEPTION 'Current independently accepted unfulfilled source offer required'
      USING ERRCODE='42501';
  END IF;

  -- Re-check actual CURRENT first-party Ledger root. The original offering
  -- root identity may not be replayed by a service or old signed session.
  v_root:=atlas.company_work_native_ledger_owner_self_v1(
    v_offer.organization_id,v_offer.ledger_id);
  IF v_root IS NULL OR v_root IS DISTINCT FROM v_offer.offered_by_person_id
  THEN
    RAISE EXCEPTION 'Original governing Ledger root is no longer current'
      USING ERRCODE='42501';
  END IF;

  -- Existing U2C gate checks exact original offer, worker signed consent,
  -- frozen service day/ISO weekdays, native scope, disclosures, policy
  -- currentness, collisions and the three-open Work capacity ceiling.
  PERFORM atlas.require_accepted_prework_standing_original_v1(
    v_offer.organization_id,v_offer.ledger_id,
    v_offer.source_candidate_id,v_offer.accepted_standing_scope_id,
    v_offer.reason,v_offer.first_service_day,
    v_offer.campaign_end_date,v_offer.approved_iso_weekdays,
    v_offer.id
  );

  -- The arbiter returns a source-admissible offer only when U1A/U1B's
  -- current Subject priority has been resolved. A hold NEVER falls
  -- through to either competing policy history or a guessed fallback.
  v_authority:=atlas.resolve_governed_canonical_farm_rule_authority_v1(
    v_offer.organization_id,v_offer.ledger_id,v_offer.farm_id,
    v_offer.source_rule_id,v_offer.subject_id
  );
  IF (v_authority->>'state') IS DISTINCT FROM
       'native_source_admitted_for_offer'
     OR (v_authority->>'candidateOfferAdmissible') IS DISTINCT FROM 'true'
     OR (v_authority->>'crossSourceUncontested') IS DISTINCT FROM 'true'
     OR (v_authority->>'propertyRuleVersionId') IS DISTINCT FROM
       v_offer.property_rule_version_id::text
     OR (v_authority->>'effectiveRuleVersionId') IS DISTINCT FROM
       v_offer.rule_version_id::text
  THEN
    RAISE EXCEPTION 'Single U1A/U1B Rulebook authority is not current'
      USING ERRCODE='42501';
  END IF;

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_accepted_first_original_readiness_held_v1',
    'state','accepted_source_checks_current_for_review_only',
    'sourceOfferId',v_offer.id,
    'governingLedgerId',v_offer.ledger_id,
    'sourceSubjectId',v_offer.subject_id,
    'sourceRuleId',v_offer.source_rule_id,
    'effectiveApprovedRulebookVersionId',v_offer.rule_version_id,
    'propertyRulebookVersionId',v_offer.property_rule_version_id,
    'recipientAcceptedIndependently',true,
    'originalWorkAlreadyIssued',false,
    'rootMayDirectlyBypassWorkerAcceptance',false,
    'sourcePreflightIsNotAnIssuanceReservation',true,
    'unattendedCarrierAuthorized',false,
    'policyExecutable',false,
    'newWorkCreated',false,
    'candidateOfferCreated',false,
    'newCampaignCreated',false,
    'principalClockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$receipt$;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
