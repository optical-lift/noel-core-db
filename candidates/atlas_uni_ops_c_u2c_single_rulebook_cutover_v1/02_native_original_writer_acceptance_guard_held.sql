-- U2C BUILT-AHEAD SOURCE CUTOVER (NOT A MIGRATION, NOT RELEASED).
-- This overlays the exact R01/R02 owner-standing writer from pinned
-- Noel branch r02/universal-rhythm-offering-governor-20261103.
-- It preserves the native canonical original/Result/planning writer and its
-- authority/collision checks. The ONLY change is the source helper after
-- the already required signed native owner resolution.
--
-- Existing R02 SQL must be installed in the SAME disposable clone before
-- this overlay. Also install 01_single_authority_arbiter_held.sql first.
-- The direct public transports are withdrawn by 03_public_cutover_held.sql.
-- This source is NOT safe to release until signed clone/negative proof.

CREATE FUNCTION atlas.require_accepted_prework_standing_original_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_scope_id uuid,p_reason text,p_service_date date,
 p_campaign_end_date date,p_iso_weekdays smallint[],p_action_id uuid
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $require_offer$
DECLARE
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_owner uuid;
BEGIN
 IF p_action_id IS NULL THEN
  RAISE EXCEPTION 'An accepted candidate must exist before original Work'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_offer FROM atlas.governed_prework_candidate_offers_v1
 WHERE id=p_action_id FOR SHARE;
 IF v_offer.id IS NULL OR v_offer.offer_state<>'accepted'
   OR v_offer.responded_at IS NULL
   OR v_offer.responding_principal_id IS NULL
   OR v_offer.response_action_id IS NULL
   OR v_offer.organization_id IS DISTINCT FROM p_organization_id
   OR v_offer.ledger_id IS DISTINCT FROM p_ledger_id
   OR v_offer.source_candidate_id IS DISTINCT FROM p_rhythm_state_id
   OR v_offer.accepted_standing_scope_id IS DISTINCT FROM p_scope_id
   OR v_offer.first_service_day IS DISTINCT FROM p_service_date
   OR v_offer.campaign_end_date IS DISTINCT FROM p_campaign_end_date
   OR v_offer.approved_iso_weekdays IS DISTINCT FROM p_iso_weekdays
   OR v_offer.reason IS DISTINCT FROM btrim(coalesce(p_reason,''))
 THEN
  RAISE EXCEPTION 'Original writer cannot bypass exact worker acceptance'
   USING ERRCODE='42501';
 END IF;
 -- Source-governed root must still exist at the instant of original creation.
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
  p_organization_id,p_ledger_id);
 IF v_owner IS DISTINCT FROM v_offer.offered_by_person_id
    OR NOT atlas.governed_prework_offer_still_admissible_v1(v_offer.id)
 THEN
  RAISE EXCEPTION 'Accepted candidate source, custody or capacity is stale'
   USING ERRCODE='42501';
 END IF;
END;
$require_offer$;
REVOKE ALL ON FUNCTION atlas.require_accepted_prework_standing_original_v1(
 uuid,uuid,uuid,uuid,text,date,date,smallint[],uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- BEGIN EXACT R02 SOURCE-OWNER WRITER WITH AN ACCEPT-FIRST CALL ADDED.
CREATE OR REPLACE FUNCTION atlas.owner_establish_standing_continuing_care_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_rhythm_state_id uuid,
  p_scope_id uuid,
  p_visit_reason text,
  p_service_date date,
  p_campaign_end_date date,
  p_action_id uuid,
  p_workdays_iso smallint[]
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $writer$
DECLARE
  v_owner uuid;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_object atlas.growing_objects%ROWTYPE;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_existing atlas.work_items%ROWTYPE;
  v_work uuid;
  v_source jsonb;
  v_assignment jsonb;
  v_allocation uuid;
  v_plan uuid;
  v_title text;
  v_instructions text;
  v_reason text:=nullif(btrim(coalesce(p_visit_reason,'')),'');
  v_key text;
  v_today date;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
     OR p_rhythm_state_id IS NULL OR p_scope_id IS NULL
     OR p_action_id IS NULL OR p_service_date IS NULL
     OR p_campaign_end_date IS NULL
     OR p_workdays_iso IS NULL
     OR coalesce(cardinality(p_workdays_iso),0) NOT BETWEEN 1 AND 7
     OR EXISTS (SELECT 1 FROM unnest(p_workdays_iso) AS wd(day)
        WHERE wd.day IS NULL OR wd.day NOT BETWEEN 1 AND 7)
     OR p_workdays_iso IS DISTINCT FROM
        ARRAY(SELECT DISTINCT wd.day FROM unnest(p_workdays_iso) AS wd(day)
              ORDER BY wd.day)::smallint[]
     OR p_campaign_end_date<p_service_date OR p_campaign_end_date>p_service_date+120
     OR v_reason IS NULL OR length(v_reason)<10 OR length(v_reason)>1500 THEN
    RAISE EXCEPTION 'Exact signed owner standing visit and workday required'
      USING ERRCODE='22023';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  -- U2C source replacement: root alone cannot bypass worker consent.
  -- Only one exact accepted and still-current pre-original source action
  -- can invoke this existing canonical writer; no new original store.
  PERFORM atlas.require_accepted_prework_standing_original_v1(
    p_organization_id,p_ledger_id,p_rhythm_state_id,p_scope_id,
    p_visit_reason,p_service_date,p_campaign_end_date,
    p_workdays_iso,p_action_id);

  SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id FOR UPDATE;
  IF v_scope.id IS NULL OR v_scope.organization_id<>p_organization_id
    OR v_scope.ledger_id<>p_ledger_id
    OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR v_scope.scope_state<>'active'
    OR v_scope.worker_membership_id IS NOT NULL
    OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
    OR v_scope.accepted_at IS NULL
    OR v_scope.coverage_mode<>'ledger_all_work'
    OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
    OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id) THEN
    RAISE EXCEPTION 'Existing accepted connected-Person Ledger-wide scope required'
      USING ERRCODE='42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-need-owner:'||p_organization_id||':'||p_rhythm_state_id,0));
  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
      AND s.subject_kind='growing_object' AND s.state<>'paused'
    FOR UPDATE;
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Original active Subject Need unavailable' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.farm_id=v_state.farm_id AND b.organization_id=p_organization_id
      AND b.active AND r.status='active';
  SELECT * INTO v_object FROM atlas.growing_objects g
    WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id;
  v_today:=(now() at time zone
    coalesce(nullif(v_rule.metadata->>'timezoneName',''),'UTC'))::date;
  IF NOT (extract(isodow FROM p_service_date)::integer = ANY(p_workdays_iso)) THEN
    RAISE EXCEPTION 'Owner service date is not an approved campaign workday'
      USING ERRCODE='22023';
  END IF;
  IF p_service_date<v_today-1 OR p_service_date>v_today+14 THEN
    RAISE EXCEPTION 'Person-day placement must be an explicit bounded civil date'
      USING ERRCODE='22023';
  END IF;
  IF v_rule.id IS NULL OR v_object.id IS NULL OR
    v_state.rhythm_key NOT IN ('weed_stewardship','mowing') OR
    NOT EXISTS(SELECT 1 FROM atlas.farms f WHERE f.id=v_state.farm_id
      AND f.organization_id=p_organization_id AND f.status='active') THEN
    RAISE EXCEPTION 'Standing Need lacks active bound Subject and Rule'
      USING ERRCODE='23514';
  END IF;
  IF v_state.rhythm_key='mowing' THEN
    IF NOT EXISTS(SELECT 1 FROM atlas.mowing_area_state m
      WHERE m.object_id=v_state.subject_id AND m.farm_id=v_state.farm_id
        AND m.organization_id=p_organization_id AND m.status<>'closed') THEN
      RAISE EXCEPTION 'No active mowing Subject' USING ERRCODE='23514';
    END IF;
    v_title:='Attend mowing route — '||v_object.label;
    v_instructions:='Owner-standing inspection: check safety, mow only if appropriate; report the actual. '||v_reason;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM atlas.weed_cards c
      WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id) THEN
      RAISE EXCEPTION 'No governed weed-stewardship Subject' USING ERRCODE='23514';
    END IF;
    v_title:='Attend bed — '||v_object.label;
    v_instructions:='Owner-standing visit: inspect occupants; weed or tidy only as appropriate. Report actual full, partial, acceptable or blocked. '||v_reason;
  END IF;

  -- The source Disclosure gate is NOT the same as assigning responsibility.
  -- The worker must actually be permitted to find identity AND condition.
  IF NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
     v_state.subject_id,'identity')
    OR NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
     v_state.subject_id,'condition')
  THEN
    RAISE EXCEPTION 'The connected Person cannot receive this protected physical Subject'
      USING ERRCODE='42501';
  END IF;

  -- Same source action is never a second original, even after completion.
  SELECT * INTO v_existing FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='rhythm_state'
    AND w.source_object_id=v_state.id
    AND w.metadata->>'servingKey'=p_action_id::text
  ORDER BY w.created_at LIMIT 1 FOR UPDATE;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.metadata->>'sourceScopeId' IS DISTINCT FROM p_scope_id::text
      OR v_existing.metadata->>'sourceServiceDate' IS DISTINCT FROM p_service_date::text
      OR v_existing.metadata->>'sourceStandingCampaignEndsOn' IS DISTINCT FROM p_campaign_end_date::text
      OR v_existing.metadata->'sourceStandingWorkdaysIso' IS DISTINCT FROM to_jsonb(p_workdays_iso)
      OR v_existing.metadata->>'sourceAdmissionMode' IS DISTINCT FROM 'owner_standing_visit_v1'
      OR v_existing.metadata->>'sourceRuleId' IS DISTINCT FROM v_rule.id::text
      OR v_existing.metadata->>'sourceVisitReasonDigest' IS DISTINCT FROM md5(v_reason)
    THEN
      RAISE EXCEPTION 'Source action replay cannot change Person, date or owner mandate'
        USING ERRCODE='23505';
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=p_organization_id AND rel.work_item_id=v_existing.id
        AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'Replayed action does not match the native Ledger'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,
      'contractVersion','owner_standing_continuing_care_work_v1',
      'workItemId',v_existing.id,'existingAction',true,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;

  SELECT * INTO v_existing FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='rhythm_state'
    AND w.source_object_id=v_state.id AND w.work_state='open'
  LIMIT 1 FOR UPDATE;
  IF v_existing.id IS NOT NULL THEN
    -- Never reveal or reassign an existing original that belongs to another
    -- native Ledger, even when the same underlying spatial Subject is known.
    IF NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=p_organization_id
        AND rel.work_item_id=v_existing.id
        AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'Another governing Ledger already has the open original Work'
        USING ERRCODE='23514';
    END IF;
    -- Never overwrite another person's task/plan with a later observation.
    RETURN jsonb_build_object('ok',true,
      'contractVersion','owner_standing_continuing_care_work_v1',
      'workItemId',v_existing.id,'existingOpenServing',true,
      'noNewWorkCreated',true,'assignmentUnchanged',true,
      'noNewObservationCreated',true,'clockAdmitted',false);
  END IF;

  -- Do not promote the same Need while an unresolved legacy obligation
  -- still exists. Keep that older task and its history unchanged; exact
  -- legacy disposition/transfer is a separate governed owner decision.
  IF EXISTS (
    SELECT 1 FROM atlas.tasks t
    LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
    WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
      AND (
        t.metadata->>'rhythm_state_id'=v_state.id::text
        OR (o.source_kind='rhythm_state' AND o.source_id=v_state.id)
      )
  ) THEN
    RAISE EXCEPTION 'An older active task still serves this exact Need; resolve its custody before creating another original Work'
      USING ERRCODE='23514';
  END IF;

  -- No care_current_state transition and no care_observation_events write.
  -- Only the worker's later signed Actual can establish observed condition.
  v_source:=atlas.establish_continuing_original_work_internal_v1(
    'organization',p_organization_id,p_ledger_id,'rhythm_state',v_state.id,
    p_action_id::text,'spatial','growing_object',v_state.subject_id,
    left(v_title,500),v_instructions,'continuing_care_actual_v1');
  v_work:=(v_source->>'workItemId')::uuid;
  IF v_work IS NULL OR v_source->>'noNewWorkCreated' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Original Work serving was not newly established'
      USING ERRCODE='23514';
  END IF;

  -- Freeze the original signed source action: replay must be an exact
  -- repeat, never a second assignment, observation or service date.
  UPDATE atlas.work_items SET
    metadata=metadata||jsonb_build_object(
      'sourceScopeId',p_scope_id,
      'sourceServiceDate',p_service_date,
      'sourceStandingCampaignId',p_action_id,
      'sourceStandingCampaignEndsOn',p_campaign_end_date,
      'sourceStandingWorkdaysIso',to_jsonb(p_workdays_iso),
      'sourceStandingCampaignMode','seasonal_closeout',
      'sourceStandingVisitReason',v_reason,
      'sourceApprovedByPersonId',v_owner,
      'sourceAdmissionMode','owner_standing_visit_v1',
      'sourceRuleId',v_rule.id,
      'sourceSubjectId',v_state.subject_id,
      'sourceRhythmIntervalSeconds',v_rule.validity_interval_seconds,
      'sourceVisitReasonDigest',md5(v_reason)),
    updated_at=now()
  WHERE id=v_work AND organization_id=p_organization_id;

  INSERT INTO atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id
  ) VALUES(
    p_organization_id,v_work,p_ledger_id,'owner_attested',
    'atlas.rhythm_rules:'||v_rule.id::text,
    'Governor established a standing Subject visit; no condition inferred.',
    v_owner
  );

  -- Reuse the governed native Person allocation, not an employee seat.
  v_assignment:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
    v_work,p_scope_id,
    'Owner-approved standing visit under the existing accepted native Person scope.');
  IF v_assignment->>'state' IS DISTINCT FROM 'assigned'
    OR v_assignment->>'workItemId' IS DISTINCT FROM v_work::text THEN
    RAISE EXCEPTION 'Exact native Person responsibility was not verified'
      USING ERRCODE='23514';
  END IF;
  v_allocation:=(v_assignment->>'allocationId')::uuid;

  -- Only the governor-selected service date creates this Work's Person-day
  -- plan. Rhythm due_at is NOT the Person's scheduling/attention authority.
  INSERT INTO atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,planned_by_membership_id,
    plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_allocation,NULL,NULL,'active',
    p_service_date,p_service_date,p_service_date,
    'Owner deliberately selected the standing visit service date.',
    jsonb_build_object('source','owner_standing_visit_v1',
      'ownerPersonId',v_owner,'sourceRuleId',v_rule.id,
      'sourceStandingCampaignEndsOn',p_campaign_end_date,
      'connectedPersonDay',true,'principalClockAdmitted',false)
  ) RETURNING id INTO v_plan;
  INSERT INTO atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_plan,'planned',
    p_service_date,p_service_date,NULL,
    'Governor selected standing visit service date',
    jsonb_build_object('sourceRuleId',v_rule.id,
      'governorPersonId',v_owner,'notLegacyWorkerDay',true)
  );

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','owner_standing_continuing_care_work_v1',
    'workItemId',v_work,'rhythmStateId',v_state.id,
    'sourceRuleId',v_rule.id,
    'responsiblePersonId',v_scope.worker_person_id,
    'allocationId',v_allocation,'planId',v_plan,
    'serviceDate',p_service_date,
    'campaignEndDate',p_campaign_end_date,
    'approvedWorkdaysIso',to_jsonb(p_workdays_iso),
    'newOriginalWorkCreated',true,
    'ownerStandingVisitApproved',true,
    'clockAdmitted',false,'noNextWorkPrecreated',true);
END;
$writer$;

-- END R02 owner-standing writer overlay. Ownership/return signatures,
-- existing Work creation and verified Result chain remain source-identical.
REVOKE ALL ON FUNCTION atlas.owner_establish_standing_continuing_care_work_self_api_v1(
 uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[]
) FROM PUBLIC,anon,authenticated,service_role;


-- BEGIN U2C RHYTHM-ORIGINAL CONTEXT GUARD BRIDGE (HELD; NO MIGRATION)
-- Original installed trigger is preserved; one signed pre-original source
-- is admitted after the accepted-first U2C writer gate, with exact source
-- identity, consent, native custody and per-Subject disclosure checked again.
-- Legacy growing-object task guard below remains text-identical apart from
-- the one bounded first branch; no public endpoint/ACL or role is added.
CREATE OR REPLACE FUNCTION atlas.guard_work_growing_object_context_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE
  v_ledger uuid;
BEGIN
  IF NEW.subject_domain<>'spatial'
     OR NEW.subject_kind<>'growing_object'
  THEN
    RETURN NEW;
  END IF;


  -- New narrowly admitted source: one accepted pre-original mowing offer
  -- may create the canonical rhythm_state -> growing_object Subject link
  -- inside the SAME signed governor transaction. It is not a general
  -- capacity, observation, context-disclosure or task creation permission.
  -- The original legacy-task branch below must remain byte-identical.
  IF NEW.provenance->>'sourceContract'='continuing_original_work_v1' THEN
    IF TG_OP<>'INSERT' OR TG_TABLE_SCHEMA<>'atlas'
       OR TG_TABLE_NAME<>'work_item_context_links'
       OR NEW.organization_id IS NULL OR NEW.household_id IS NOT NULL
       OR NEW.relation_kind<>'acts_on'
       OR NEW.provenance->>'needKind' IS DISTINCT FROM 'rhythm_state'
       OR NEW.metadata IS DISTINCT FROM '{}'::jsonb
       OR auth.uid() IS NULL
       OR atlas.current_principal_id_v1() IS NULL
       OR coalesce(NEW.metadata->>'confersAccess','false')='true'
       OR coalesce(NEW.metadata->>'createsWork','false')='true'
    THEN
      RAISE EXCEPTION 'Accepted rhythm Work context requires exact signed provenance'
        USING ERRCODE='42501';
    END IF;

    -- Verify, rather than assume, the SAME original written by the internal
    -- continuing source and the SAME accepted response issued before Work.
    -- The source's ordinary admissibility reader cannot be called AFTER
    -- inserting Work: its correct duplicate-Work guard would deny itself.
    -- U2B and U2C verify it immediately BEFORE original creation under
    -- the original Subject/offer transaction locks.
    IF NOT EXISTS (
      SELECT 1
      FROM atlas.work_items w
      JOIN atlas.governed_prework_candidate_offers_v1 o
        ON o.id::text=w.metadata->>'servingKey'
       AND o.organization_id=w.organization_id
       AND o.source_candidate_id=w.source_object_id
       AND o.subject_id=NEW.subject_id
      JOIN atlas.company_work_standing_assignment_scopes scope
        ON scope.id=o.accepted_standing_scope_id
       AND scope.organization_id=o.organization_id
       AND scope.ledger_id=o.ledger_id
       AND scope.worker_person_id=o.target_person_id
      JOIN atlas.rhythm_state rhythm
        ON rhythm.id=o.source_candidate_id
       AND rhythm.organization_id=o.organization_id
       AND rhythm.subject_id=o.subject_id
       AND rhythm.farm_id=o.farm_id
       AND rhythm.rhythm_rule_id=o.source_rule_id
       AND rhythm.rhythm_key='mowing'
       AND rhythm.state<>'paused'
      JOIN atlas.growing_objects obj
        ON obj.id=NEW.subject_id AND obj.farm_id=o.farm_id
      JOIN atlas.farm_crop_ledger_custody_v1 custody
        ON custody.farm_id=o.farm_id
       AND custody.ledger_id=o.ledger_id
       AND custody.custody_state='active'
       AND custody.ended_at IS NULL
      JOIN atlas.ledger_organization_participations lop
        ON lop.organization_id=o.organization_id
       AND lop.ledger_id=o.ledger_id
       AND lop.status='active'
       AND lop.ended_at IS NULL
       AND lop.participation_kind='governing'
       AND lop.is_compatibility_primary=true
      CROSS JOIN LATERAL (
        SELECT atlas.resolve_governed_canonical_farm_rule_authority_v1(
          o.organization_id,o.ledger_id,o.farm_id,
          o.source_rule_id,o.subject_id) AS truth
      ) rule
      WHERE w.id=NEW.work_item_id
        AND w.organization_id=NEW.organization_id
        AND w.household_id IS NULL AND w.work_state='open'
        AND w.created_by_user_id=auth.uid()
        AND w.source_object_type='rhythm_state'
        AND w.result_contract_key='continuing_care_actual_v1'
        AND w.metadata->>'sourceContract'='continuing_original_work_v1'
        AND w.metadata->>'needKind'='rhythm_state'
        AND w.metadata->>'needId'=o.source_candidate_id::text
        AND NEW.provenance=pg_catalog.jsonb_build_object(
          'needKind','rhythm_state',
          'needId',o.source_candidate_id,
          'sourceContract','continuing_original_work_v1')
        AND o.offer_state='accepted'
        AND o.original_work_item_id IS NULL
        AND o.responded_at IS NOT NULL
        AND o.response_action_id IS NOT NULL
        AND o.responding_principal_id IS NOT NULL
        AND (pg_catalog.now() AT TIME ZONE o.timezone_name)::date
              <=o.first_service_day
        AND o.offered_by_person_id=
          atlas.company_work_native_ledger_owner_self_v1(
            o.organization_id,o.ledger_id)
        AND scope.proposed_by_person_id=o.offered_by_person_id
        AND scope.scope_state='active'
        AND scope.coverage_mode='ledger_all_work'
        AND scope.worker_membership_id IS NULL
        AND scope.accepted_by_person_id=o.target_person_id
        AND scope.accepted_at IS NOT NULL
        AND (scope.valid_until IS NULL OR scope.valid_until>pg_catalog.now())
        AND atlas.person_has_native_ledger_connection_v1(
          o.organization_id,o.ledger_id,o.target_person_id)
        AND atlas.has_current_subject_disclosure_v1(
          o.ledger_id,o.target_person_id,'spatial',
          'growing_object',o.subject_id,'identity')
        AND atlas.has_current_subject_disclosure_v1(
          o.ledger_id,o.target_person_id,'spatial',
          'growing_object',o.subject_id,'condition')
        AND rule.truth->>'state'='native_source_admitted_for_offer'
        AND rule.truth->>'candidateOfferAdmissible'='true'
        AND rule.truth->>'propertyRuleVersionId'=o.property_rule_version_id::text
        AND rule.truth->>'effectiveRuleVersionId'=o.rule_version_id::text
    ) THEN
      RAISE EXCEPTION 'Accepted current native mowing original context not proven'
        USING ERRCODE='42501';
    END IF;
    -- Only the one linked original Subject; no reader authorization,
    -- physical Actual, allocation or future successor can be inferred.
    RETURN NEW;
  END IF;

  -- An established work link does not automatically authorize reading it.
  -- This source-owned path requires a current exact-Ledger governor and
  -- separately verified real Work/farm/physical source at every creation.
  IF auth.uid() IS NULL
     OR atlas.current_principal_id_v1() IS NULL
     OR coalesce(NEW.provenance->>'humanConfirmed','false')<>'true'
     OR coalesce(NEW.provenance->>'reviewedObjectKey','')=''
     OR coalesce(NEW.provenance->>'reviewedWorkStableKey','')=''
     OR coalesce(NEW.metadata->>'confersAccess','false')='true'
     OR coalesce(NEW.metadata->>'createsWork','false')='true'
  THEN
    RAISE EXCEPTION 'governed work-context establishment required'
      USING ERRCODE='42501';
  END IF;

  BEGIN
    v_ledger := (NEW.provenance->>'nativeLedgerId')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'invalid native Ledger proof'
      USING ERRCODE='42501';
  END;
  IF v_ledger IS NULL
     OR NOT atlas.principal_has_ledger_authority_v1(
       atlas.current_principal_id_v1(), v_ledger
     )
  THEN
    RAISE EXCEPTION 'exact Ledger governor required'
      USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM atlas.work_items w
    JOIN atlas.tasks t
      ON t.id=w.source_object_id
     AND w.source_object_type IN ('legacy_task','legacy_task_slice')
    JOIN atlas.growing_objects g
      ON g.id=NEW.subject_id
    JOIN atlas.farms f
      ON f.id=g.farm_id AND f.id=t.farm_id
    JOIN atlas.farm_crop_ledger_custody_v1 custody
      ON custody.farm_id=f.id
     AND custody.ledger_id=v_ledger
     AND custody.custody_state='active'
     AND custody.ended_at IS NULL
    JOIN atlas.ledger_organization_participations lop
      ON lop.organization_id=w.organization_id
     AND lop.organization_id=f.organization_id
     AND lop.ledger_id=v_ledger
     AND lop.status='active' AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
    JOIN ledger.ledgers nl
      ON nl.id=lop.ledger_id
     AND nl.ledger_state='active' AND nl.retired_at IS NULL
    WHERE w.id=NEW.work_item_id
      AND w.organization_id=NEW.organization_id
      AND f.organization_unit_id=w.organization_unit_id
      AND t.zone_id=g.zone_id
      AND g.object_type='bed'
      AND w.work_state IN ('open','in_progress')
      AND g.stable_key=NEW.provenance->>'reviewedObjectKey'
      AND w.stable_key=NEW.provenance->>'reviewedWorkStableKey'
      AND t.id::text=NEW.provenance->>'originalTaskId'
      AND EXISTS (
        SELECT 1 FROM atlas.work_allocations a
        WHERE a.work_item_id=w.id AND a.state='active'
      )
      AND (
        w.source_object_type<>'legacy_task_slice'
        OR EXISTS (
          SELECT 1
          FROM atlas.company_work_legacy_slice_contract_provenance_v1 src
          WHERE src.work_item_id=w.id AND src.source_task_id=t.id
        )
      )
  ) THEN
    RAISE EXCEPTION 'physical Work source and exact Ledger custody unproven'
      USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$body$;
-- END U2C RHYTHM-ORIGINAL CONTEXT GUARD BRIDGE
