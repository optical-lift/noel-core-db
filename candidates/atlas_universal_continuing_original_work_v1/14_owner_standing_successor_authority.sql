-- Held candidate: one sourced next Subject for an already approved standing campaign.
-- Reuses existing original Work and source authority. No legacy task clock.
CREATE OR REPLACE FUNCTION atlas.standing_care_next_subject_internal_v1(
 p_prior_work_item_id uuid,p_ignore_work_item_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $next$
DECLARE
 v_prior atlas.work_items%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_ledger uuid;
 v_next uuid;
BEGIN
 SELECT * INTO v_prior FROM atlas.work_items WHERE id=p_prior_work_item_id;
 IF v_prior.id IS NULL OR v_prior.source_object_type<>'rhythm_state'
   OR v_prior.result_contract_key<>'continuing_care_actual_v1'
   OR v_prior.metadata->>'sourceStandingCampaignId' IS NULL
   OR v_prior.metadata->>'sourceScopeId' IS NULL
 THEN RETURN NULL; END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=v_prior.source_object_id AND s.organization_id=v_prior.organization_id;
 IF v_state.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
 WHERE id=atlas.rhythm_safe_uuid_v1(v_prior.metadata->>'sourceScopeId');
 IF v_scope.id IS NULL OR v_scope.organization_id<>v_prior.organization_id
   OR v_scope.scope_state<>'active' OR v_scope.worker_membership_id IS NOT NULL
   OR v_scope.accepted_at IS NULL
   OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
   OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 THEN RETURN NULL; END IF;
 v_ledger:=v_scope.ledger_id;
 SELECT s.id INTO v_next
 FROM atlas.rhythm_state s
 JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
   AND b.organization_id=v_prior.organization_id
   AND b.farm_id=v_state.farm_id AND b.active
 JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
   AND r.id=s.rhythm_rule_id AND r.status='active'
 JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=s.farm_id
 WHERE s.organization_id=v_prior.organization_id
   AND s.farm_id=v_state.farm_id AND s.rhythm_key=v_state.rhythm_key
   AND s.subject_kind='growing_object' AND s.state<>'paused'
   AND r.validity_interval_seconds>0
   AND ((s.rhythm_key='weed_stewardship' AND EXISTS (
       SELECT 1 FROM atlas.weed_cards wc
       WHERE wc.object_id=s.subject_id AND wc.farm_id=s.farm_id))
     OR (s.rhythm_key='mowing' AND EXISTS (
       SELECT 1 FROM atlas.mowing_area_state m
       WHERE m.object_id=s.subject_id AND m.organization_id=s.organization_id
         AND m.farm_id=s.farm_id AND m.status<>'closed')))
   AND atlas.has_current_subject_disclosure_v1(
     v_ledger,v_scope.worker_person_id,'spatial','growing_object',s.subject_id,'identity')
   AND atlas.has_current_subject_disclosure_v1(
     v_ledger,v_scope.worker_person_id,'spatial','growing_object',s.subject_id,'condition')
   -- Earlier seasonal visits are permanent history, not work reissued in a
   -- loop. The one newly inserted Work can be ignored during guard checking.
   AND NOT EXISTS(
     SELECT 1 FROM atlas.work_items w
     WHERE w.organization_id=v_prior.organization_id
       AND w.id IS DISTINCT FROM p_ignore_work_item_id
       AND w.metadata->>'sourceStandingCampaignId'=
         v_prior.metadata->>'sourceStandingCampaignId'
       AND w.metadata->>'sourceSubjectId'=s.subject_id::text
       AND w.work_state IN ('open','completed'))
   -- Neither another original nor an unresolved legacy Work may be doubled.
   AND NOT EXISTS(
     SELECT 1 FROM atlas.work_items w
     WHERE w.organization_id=v_prior.organization_id
       AND w.id IS DISTINCT FROM p_ignore_work_item_id
       AND w.source_object_type='rhythm_state'
       AND w.source_object_id=s.id AND w.work_state='open')
   AND NOT EXISTS(
     SELECT 1 FROM atlas.tasks t
     LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
     WHERE t.farm_id=s.farm_id AND t.status IN ('open','blocked')
       AND (t.metadata->>'rhythm_state_id'=s.id::text
         OR (o.source_kind='rhythm_state' AND o.source_id=s.id))
   )
 ORDER BY
   greatest(0,
     extract(epoch FROM (now()-s.due_at)) /
       greatest(86400,r.validity_interval_seconds)) DESC,
   r.validity_interval_seconds ASC,g.label,s.id
 LIMIT 1;
 RETURN v_next;
END;
$next$;
REVOKE ALL ON FUNCTION atlas.standing_care_next_subject_internal_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- The delegated worker can never appoint themselves. They may only cause
-- the next allocation through an accepted physical Actual from the same
-- original owner-approved campaign. This verifier is also called by the
-- existing allocation's responsibility establishment trigger.
CREATE OR REPLACE FUNCTION atlas.standing_care_auto_successor_authorized_v1(
 p_work_item_id uuid,p_responsible_person_id uuid,p_basis jsonb
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $verify$
DECLARE
 v_current atlas.work_items%ROWTYPE;
 v_prior atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_prior_alloc atlas.work_allocations%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_prior_rule atlas.rhythm_rules%ROWTYPE;
 v_ledger uuid;
 v_tz text;
 v_expected_date date;
 v_campaign_end date;
 v_owner uuid;
BEGIN
 IF auth.uid() IS NULL OR atlas.current_person_id_v1()
    IS DISTINCT FROM p_responsible_person_id
    OR p_work_item_id IS NULL OR p_responsible_person_id IS NULL
    OR p_basis IS NULL OR jsonb_typeof(p_basis)<>'object'
    OR p_basis->>'contractVersion'<>'exact_work_responsibility_establishment_v2'
    OR p_basis->>'basisKind'<>'delegated_under_standing_scope'
    OR p_basis->>'authorizationBasis'<>'owner_preapproved_standing_care_actual_successor_v1'
 THEN RETURN false; END IF;
 SELECT * INTO v_current FROM atlas.work_items w WHERE w.id=p_work_item_id;
 IF v_current.id IS NULL OR v_current.work_state<>'open'
   OR v_current.source_object_type<>'rhythm_state'
   OR v_current.result_contract_key<>'continuing_care_actual_v1'
   OR v_current.metadata->>'sourceAdmissionMode'<>'owner_standing_successor_v1'
   OR v_current.metadata->>'sourceContract'<>'continuing_original_work_v1'
   OR v_current.metadata->>'sourceAutoPriorResultId' IS NULL
 THEN RETURN false; END IF;
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.id=atlas.rhythm_safe_uuid_v1(v_current.metadata->>'sourceAutoPriorResultId')
   AND r.result_kind='completed' AND r.result_contract_key='continuing_care_actual_v1'
   AND r.reported_by_user_id=auth.uid();
 IF v_result.id IS NULL THEN RETURN false; END IF;
 SELECT * INTO v_prior FROM atlas.work_items w WHERE w.id=v_result.work_item_id;
 SELECT * INTO v_prior_alloc FROM atlas.work_allocations a
 WHERE a.id=v_result.responsible_allocation_id
   AND a.work_item_id=v_prior.id AND a.organization_id=v_prior.organization_id;
 IF v_prior.id IS NULL OR v_prior.work_state<>'completed'
   OR v_prior.organization_id IS DISTINCT FROM v_current.organization_id
   OR v_prior_alloc.id IS NULL OR v_prior_alloc.state<>'completed'
   OR v_prior_alloc.assignee_canonical_person_id IS DISTINCT FROM p_responsible_person_id
   OR v_prior_alloc.assignee_membership_id IS NOT NULL
   OR v_prior.metadata->>'sourceStandingCampaignId' IS NULL
   OR v_prior.metadata->>'sourceStandingCampaignId'
      IS DISTINCT FROM v_current.metadata->>'sourceStandingCampaignId'
   OR v_prior.metadata->>'sourceStandingCampaignEndsOn'
      IS DISTINCT FROM v_current.metadata->>'sourceStandingCampaignEndsOn'
   OR v_prior.metadata->>'sourceScopeId'
      IS DISTINCT FROM v_current.metadata->>'sourceScopeId'
   OR v_prior.metadata->>'sourceApprovedByPersonId'
      IS DISTINCT FROM v_current.metadata->>'sourceApprovedByPersonId'
   OR v_current.metadata->>'sourceAutoPriorWorkItemId'
      IS DISTINCT FROM v_prior.id::text
 THEN RETURN false; END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes sc
 WHERE sc.id=atlas.rhythm_safe_uuid_v1(v_prior.metadata->>'sourceScopeId');
 IF v_scope.id IS NULL OR v_scope.scope_state<>'active'
   OR v_scope.organization_id IS DISTINCT FROM v_prior.organization_id
   OR v_scope.worker_person_id IS DISTINCT FROM p_responsible_person_id
   OR v_scope.worker_membership_id IS NOT NULL
   OR v_scope.accepted_at IS NULL
   OR v_scope.accepted_by_person_id IS DISTINCT FROM p_responsible_person_id
   OR v_scope.coverage_mode<>'ledger_all_work'
   OR v_scope.proposed_by_person_id::text
      IS DISTINCT FROM v_prior.metadata->>'sourceApprovedByPersonId'
   OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 THEN RETURN false; END IF;
 v_owner:=v_scope.proposed_by_person_id;
 v_ledger:=v_scope.ledger_id;
 IF p_basis->>'scopeId' IS DISTINCT FROM v_scope.id::text
   OR p_basis->>'nativeLedgerId' IS DISTINCT FROM v_ledger::text
   OR p_basis->>'organizationId' IS DISTINCT FROM v_current.organization_id::text
   OR p_basis->>'workItemId' IS DISTINCT FROM v_current.id::text
   OR p_basis->>'assigneePersonId' IS DISTINCT FROM p_responsible_person_id::text
   OR p_basis->>'priorResultId' IS DISTINCT FROM v_result.id::text
   OR NOT atlas.person_has_native_ledger_connection_v1(
      v_current.organization_id,v_ledger,p_responsible_person_id)
 THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.principals issuer
   JOIN atlas.principal_ledger_authorities authority
     ON authority.principal_id=issuer.id
     AND authority.ledger_id=v_ledger
     AND authority.authority_kind='root_governing'
     AND authority.status='active'
   WHERE issuer.person_id=v_owner AND issuer.status='active')
   OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
     WHERE rel.organization_id=v_prior.organization_id
       AND rel.work_item_id=v_prior.id
       AND rel.ledger_id=v_ledger
       AND rel.attribution_state='active' AND rel.evidence_kind='owner_attested')
   OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
     WHERE rel.organization_id=v_current.organization_id
       AND rel.work_item_id=v_current.id
       AND rel.ledger_id=v_ledger AND rel.attribution_state='active'
       AND rel.evidence_kind='owner_attested')
   OR NOT EXISTS (
     SELECT 1 FROM atlas.work_result_acceptances ra
     JOIN atlas.care_result_events care
       ON care.id=atlas.rhythm_safe_uuid_v1(v_result.payload->>'careResultId')
       AND care.actor_user_id=auth.uid()
       AND care.source_kind='continuing_care_actual'
     JOIN atlas.rhythm_satisfactions sat ON sat.source_id=care.id
       AND sat.organization_id=v_prior.organization_id
       AND sat.satisfaction_kind IN ('full','conditional')
       AND sat.evidence->>'workItemId'=v_prior.id::text
       AND sat.evidence->>'workResultId'=v_result.id::text
     WHERE ra.execution_result_id=v_result.id AND ra.work_item_id=v_prior.id
       AND ra.organization_id=v_prior.organization_id
       AND ra.decision='accepted'
       AND ra.acceptance_kind='source_qualified_physical_actual'
   )
 THEN RETURN false; END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=v_prior.source_object_id AND s.organization_id=v_prior.organization_id;
 SELECT * INTO v_prior_rule FROM atlas.rhythm_rules r
 WHERE r.id=atlas.rhythm_safe_uuid_v1(v_prior.metadata->>'sourceRuleId');
 IF v_state.id IS NULL OR v_prior_rule.id IS NULL THEN RETURN false; END IF;
 v_tz:=coalesce(nullif(v_prior_rule.metadata->>'timezoneName',''),
   (SELECT nullif(pr.home_timezone,'') FROM atlas.principals pr
     WHERE pr.person_id=p_responsible_person_id
       AND pr.user_id=auth.uid() AND pr.status='active'
     ORDER BY pr.created_at DESC LIMIT 1),'UTC');
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names t WHERE t.name=v_tz)
 THEN RETURN false; END IF;
 v_expected_date:=(v_result.reported_at AT TIME ZONE v_tz)::date+1;
 IF extract(dow FROM v_expected_date)=0 THEN v_expected_date:=v_expected_date+1; END IF;
 v_campaign_end:=(v_prior.metadata->>'sourceStandingCampaignEndsOn')::date;
 IF v_expected_date>v_campaign_end
   OR v_current.metadata->>'sourceServiceDate' IS DISTINCT FROM v_expected_date::text
   OR atlas.standing_care_next_subject_internal_v1(v_prior.id,v_current.id)
     IS DISTINCT FROM v_current.source_object_id
 THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_item_context_links l
   JOIN atlas.rhythm_state n ON n.id=v_current.source_object_id
   WHERE l.organization_id=v_current.organization_id
     AND l.work_item_id=v_current.id AND l.subject_domain='spatial'
     AND l.subject_kind='growing_object' AND l.subject_id=n.subject_id
     AND l.relation_kind='acts_on')
 THEN RETURN false; END IF;
 RETURN true;
END;
$verify$;
REVOKE ALL ON FUNCTION atlas.standing_care_auto_successor_authorized_v1(uuid,uuid,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
