-- R02 HELD / NOT A MIGRATION / NO DATA WRITES.
-- Universal rhythm opportunity review and governor mandate transport.
-- Source-specific eligibility and physical-action semantics remain inside
-- adapters. A new rhythm domain adds an adapter in Noel, not a second Atlas
-- Today, Work, scheduling or recurrence engine.
--
-- R02 currently registers ONE source adapter, continuing-care Actual v1.
-- Source coverage is deliberately partial and must never be represented as
-- every rhythm in the Ledger.

CREATE OR REPLACE FUNCTION atlas.governor_rhythm_care_opportunities_adapter_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
 p_limit integer DEFAULT 20,p_after_candidate_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $care_adapter$
DECLARE
 v_owner uuid;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_items jsonb;v_more boolean;v_cursor uuid;
BEGIN
 IF auth.uid() IS NULL OR p_organization_id IS NULL
   OR p_ledger_id IS NULL OR p_scope_id IS NULL
   OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25
 THEN RAISE EXCEPTION 'Exact bounded signed rhythm source requested'
   USING ERRCODE='42501'; END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=p_scope_id
   AND s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id;
 IF v_scope.id IS NULL OR v_scope.scope_state<>'active'
   OR v_scope.worker_membership_id IS NOT NULL
   OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
   OR v_scope.accepted_at IS NULL
   OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
   OR v_scope.coverage_mode<>'ledger_all_work'
   OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
   OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN RAISE EXCEPTION 'Current accepted source-governed Person scope required'
   USING ERRCODE='42501'; END IF;

 -- Read only source-valid current Need+Rule+Subject pairs. This is an
 -- OPPORTUNITY, not a physical observation, automatically due task, promise,
 -- assignment, or permission to disclose the Subject to the worker.
 WITH admitted AS MATERIALIZED (
  SELECT
    s.id AS candidate_id,s.subject_id,
    s.rhythm_key,g.label AS subject_label,
    r.label AS rhythm_label,r.id AS source_rule_id,
    r.validity_interval_seconds AS cadence_seconds,s.due_at,
    atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
      s.subject_id,'identity') AS identity_disclosed,
    atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
      s.subject_id,'condition') AS condition_disclosed
  FROM atlas.rhythm_state s
  JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
    AND b.farm_id=s.farm_id AND b.organization_id=s.organization_id
    AND b.rhythm_rule_id=s.rhythm_rule_id AND b.active
  JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
    AND r.status='active' AND r.validity_interval_seconds>0
  JOIN atlas.farms f ON f.id=s.farm_id
    AND f.organization_id=p_organization_id AND f.status='active'
  JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=s.farm_id
  WHERE s.organization_id=p_organization_id AND s.state<>'paused'
    AND s.subject_kind='growing_object'
    AND s.rhythm_key IN ('weed_stewardship','mowing')
    AND (p_after_candidate_id IS NULL OR s.id>p_after_candidate_id)
    AND ((s.rhythm_key='weed_stewardship' AND EXISTS(
      SELECT 1 FROM atlas.weed_cards wc
      WHERE wc.object_id=s.subject_id AND wc.farm_id=s.farm_id))
      OR (s.rhythm_key='mowing' AND EXISTS(
      SELECT 1 FROM atlas.mowing_area_state m
      WHERE m.object_id=s.subject_id AND m.farm_id=s.farm_id
        AND m.organization_id=p_organization_id AND m.status<>'closed')))
    AND NOT EXISTS(SELECT 1 FROM atlas.work_items w
      WHERE w.organization_id=p_organization_id
        AND w.source_object_type='rhythm_state'
        AND w.source_object_id=s.id AND w.work_state='open')
    AND NOT EXISTS(SELECT 1 FROM atlas.tasks t
      LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
      WHERE t.farm_id=s.farm_id AND t.status IN ('open','blocked')
        AND (t.metadata->>'rhythm_state_id'=s.id::text
          OR (o.source_kind='rhythm_state' AND o.source_id=s.id)))
  ORDER BY s.id
  LIMIT (p_limit+1)
 ), ordered AS (
  SELECT admitted.*,row_number() OVER(ORDER BY admitted.candidate_id) AS ordinal
  FROM admitted
 )
 SELECT
   coalesce(jsonb_agg(jsonb_build_object(
     'candidateId',candidate_id,
     'adapterKey','continuing_care_actual_v1',
     'rhythmKind',rhythm_key,'rhythmLabel',rhythm_label,
     'subjectLabel',subject_label,'sourceRuleId',source_rule_id,
     'cadenceSeconds',cadence_seconds,'sourceDueAt',due_at,
     'canOffer',identity_disclosed AND condition_disclosed,
     'blockingReason',CASE
       WHEN identity_disclosed AND condition_disclosed THEN NULL
       ELSE 'recipient_subject_disclosure_required' END,
     'sourceVerified',true,'physicalConditionAsserted',false
   ) ORDER BY candidate_id) FILTER(WHERE ordinal<=p_limit),'[]'::jsonb),
   coalesce(bool_or(ordinal>p_limit),false),
   (max(candidate_id::text) FILTER(WHERE ordinal<=p_limit))::uuid
 INTO v_items,v_more,v_cursor
 FROM ordered;
 RETURN jsonb_build_object(
  'ok',true,'adapterKey','continuing_care_actual_v1',
  'workerPersonId',v_scope.worker_person_id,'items',v_items,
  'hasMore',v_more,'nextAfterCandidateId',CASE WHEN v_more THEN v_cursor ELSE NULL END,
  'noNewWorkCreated',true,'notAClockAdmission',true);
END;
$care_adapter$;
REVOKE ALL ON FUNCTION atlas.governor_rhythm_care_opportunities_adapter_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.governor_review_rhythm_opportunities_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
 p_limit integer DEFAULT 20,p_after_candidate_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $review$
DECLARE v_native jsonb;
BEGIN
 -- Source adapter verifies the exact authenticated Ledger root and accepted
 -- responsibility/disclosure; no client-provided role, roster or grant.
 v_native:=atlas.governor_rhythm_care_opportunities_adapter_v1(
  p_organization_id,p_ledger_id,p_scope_id,p_limit,p_after_candidate_id);
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','governed_rhythm_opportunities_v1',
  'organizationId',p_organization_id,'ledgerId',p_ledger_id,
  'scopeId',p_scope_id,'workerPersonId',v_native->'workerPersonId',
  'items',v_native->'items','hasMore',v_native->'hasMore',
  'nextAfterCandidateId',v_native->'nextAfterCandidateId',
  'registeredAdapters',jsonb_build_array('continuing_care_actual_v1'),
  'coverage','registered_source_adapters_only',
  'notAnAllRhythmsCensus',true,'notAnAutomaticTask',true,
  'sourceChangesRequireApprovalRecheck',true);
END;
$review$;
REVOKE ALL ON FUNCTION atlas.governor_review_rhythm_opportunities_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.governor_review_rhythm_opportunities_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
 p_limit integer DEFAULT 20,p_after_candidate_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public_review$
 SELECT atlas.governor_review_rhythm_opportunities_self_api_v1(
  p_organization_id,p_ledger_id,p_scope_id,p_limit,p_after_candidate_id);
$public_review$;
REVOKE ALL ON FUNCTION public.governor_review_rhythm_opportunities_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.governor_review_rhythm_opportunities_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;

-- A universal review/approval transport. Do not move domain operations here:
-- the selected adapter owns all rechecks and creation of ONE original Work.
-- More rhythm domains can register later without changing Atlas's form.
CREATE OR REPLACE FUNCTION atlas.governor_approve_rhythm_opportunity_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
 p_adapter_key text,p_candidate_id uuid,p_reason text,
 p_first_workday date,p_campaign_end_date date,
 p_approved_iso_workdays smallint[],p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $approve$
DECLARE v_source jsonb;
BEGIN
 IF auth.uid() IS NULL OR p_adapter_key IS NULL
   OR p_candidate_id IS NULL OR p_scope_id IS NULL
 THEN RAISE EXCEPTION 'Signed exact source opportunity required'
   USING ERRCODE='42501'; END IF;
 CASE p_adapter_key
 WHEN 'continuing_care_actual_v1' THEN
  v_source:=atlas.owner_establish_standing_continuing_care_work_self_api_v1(
    p_organization_id,p_ledger_id,p_candidate_id,p_scope_id,
    p_reason,p_first_workday,p_campaign_end_date,
    p_action_id,p_approved_iso_workdays);
 ELSE
  RAISE EXCEPTION 'No approved source adapter for requested rhythm'
   USING ERRCODE='22023';
 END CASE;
 IF v_source->>'ok' IS DISTINCT FROM 'true'
   OR v_source->>'workItemId' IS NULL
 THEN RAISE EXCEPTION 'Source adapter did not verify original Work'
   USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','governed_rhythm_approval_v1',
  'adapterKey',p_adapter_key,'candidateId',p_candidate_id,
  'organizationId',p_organization_id,'ledgerId',p_ledger_id,
  'scopeId',p_scope_id,'actionId',p_action_id,
  'workItemId',v_source->'workItemId',
  'firstWorkday',p_first_workday,
  'campaignEndDate',p_campaign_end_date,
  'approvedIsoWorkdays',to_jsonb(p_approved_iso_workdays),
  'newOriginalWorkCreated',
    coalesce((v_source->>'newOriginalWorkCreated')::boolean,false),
  'existingAction',
    coalesce((v_source->>'existingAction')::boolean,false),
  'existingOpenServing',
    coalesce((v_source->>'existingOpenServing')::boolean,false),
  'noPhysicalResultInferred',true,
  'clockDidNotAssignPerson',true,
  'sourceReceiptVersion',v_source->'contractVersion');
END;
$approve$;
REVOKE ALL ON FUNCTION atlas.governor_approve_rhythm_opportunity_self_api_v1(
 uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid
) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.governor_approve_rhythm_opportunity_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
 p_adapter_key text,p_candidate_id uuid,p_reason text,
 p_first_workday date,p_campaign_end_date date,
 p_approved_iso_workdays smallint[],p_action_id uuid
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public_approve$
 SELECT atlas.governor_approve_rhythm_opportunity_self_api_v1(
  p_organization_id,p_ledger_id,p_scope_id,p_adapter_key,p_candidate_id,
  p_reason,p_first_workday,p_campaign_end_date,
  p_approved_iso_workdays,p_action_id);
$public_approve$;
REVOKE ALL ON FUNCTION public.governor_approve_rhythm_opportunity_self_api_v1(
 uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.governor_approve_rhythm_opportunity_self_api_v1(
 uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid
) TO authenticated;
