-- Source-owned continuation of an existing approved campaign, not a
-- recurring-task store. Called ONLY after the first-party physical Actual was
-- accepted and its original Work + native allocation completed.
CREATE OR REPLACE FUNCTION atlas.advance_owner_standing_campaign_after_actual_internal_v1(
 p_prior_result_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $advance$
DECLARE
 v_result atlas.work_execution_results%ROWTYPE;
 v_prior atlas.work_items%ROWTYPE;
 v_prior_allocation atlas.work_allocations%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_prior_rule atlas.rhythm_rules%ROWTYPE;
 v_next_state atlas.rhythm_state%ROWTYPE;
 v_next_rule atlas.rhythm_rules%ROWTYPE;
 v_next_object atlas.growing_objects%ROWTYPE;
 v_work_id uuid;
 v_alloc_id uuid;
 v_plan_id uuid;
 v_next_date date;
 v_end date;
 v_ledger uuid;
 v_actor uuid:=atlas.current_person_id_v1();
 v_tz text;
 v_title text;
 v_instructions text;
 v_existing uuid;
 v_campaign text;
 v_serving text;
BEGIN
 IF auth.uid() IS NULL OR v_actor IS NULL OR p_prior_result_id IS NULL THEN
   RAISE EXCEPTION 'Signed physical Result required for campaign continuation'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_result FROM atlas.work_execution_results
 WHERE id=p_prior_result_id AND reported_by_user_id=auth.uid()
   AND result_contract_key='continuing_care_actual_v1'
   AND result_kind='completed';
 IF v_result.id IS NULL THEN
   RAISE EXCEPTION 'Signed qualifying completed Result unavailable'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior FROM atlas.work_items w WHERE w.id=v_result.work_item_id;
 IF v_prior.id IS NULL OR v_prior.work_state<>'completed'
   OR v_prior.source_object_type<>'rhythm_state'
   OR v_prior.result_contract_key<>'continuing_care_actual_v1'
   OR v_prior.metadata->>'sourceStandingCampaignId' IS NULL THEN
   RETURN jsonb_build_object('ok',true,'nextWorkCreated',false,
     'reason','not_an_active_standing_campaign');
 END IF;
 v_campaign:=v_prior.metadata->>'sourceStandingCampaignId';
 IF atlas.rhythm_safe_uuid_v1(v_campaign) IS NULL THEN
   RAISE EXCEPTION 'Campaign lacks exact source action'
     USING ERRCODE='23514';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.standing-care-campaign:'||v_prior.organization_id::text||':'||
   v_campaign,0));
 SELECT * INTO v_prior_allocation FROM atlas.work_allocations a
 WHERE a.id=v_result.responsible_allocation_id
   AND a.work_item_id=v_prior.id AND a.organization_id=v_prior.organization_id
   AND a.assignee_canonical_person_id=v_actor
   AND a.assignee_membership_id IS NULL AND a.allocation_role='responsible'
   AND a.state='completed';
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes sc
 WHERE sc.id=atlas.rhythm_safe_uuid_v1(v_prior.metadata->>'sourceScopeId');
 IF v_prior_allocation.id IS NULL OR v_scope.id IS NULL
   OR v_scope.organization_id<>v_prior.organization_id
   OR v_scope.ledger_id::text IS DISTINCT FROM
       v_prior_allocation.establishment_basis->>'nativeLedgerId'
   OR v_scope.worker_person_id<>v_actor
   OR v_scope.worker_membership_id IS NOT NULL
   OR v_scope.accepted_by_person_id IS DISTINCT FROM v_actor
   OR v_scope.accepted_at IS NULL
   OR v_scope.scope_state<>'active'
   OR v_scope.coverage_mode<>'ledger_all_work'
   OR v_scope.proposed_by_person_id::text IS DISTINCT FROM
       v_prior.metadata->>'sourceApprovedByPersonId'
   OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 THEN
   RETURN jsonb_build_object('ok',true,'nextWorkCreated',false,
     'reason','approved_scope_no_longer_current');
 END IF;
 v_ledger:=v_scope.ledger_id;
 IF NOT atlas.person_has_native_ledger_connection_v1(
     v_prior.organization_id,v_ledger,v_actor)
   OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
     WHERE rel.work_item_id=v_prior.id AND rel.organization_id=v_prior.organization_id
       AND rel.ledger_id=v_ledger AND rel.attribution_state='active'
       AND rel.evidence_kind='owner_attested')
   OR NOT EXISTS(SELECT 1 FROM atlas.work_result_acceptances accepted
     JOIN atlas.care_result_events care ON care.id=
       atlas.rhythm_safe_uuid_v1(v_result.payload->>'careResultId')
       AND care.actor_user_id=auth.uid()
       AND care.source_kind='continuing_care_actual'
     JOIN atlas.rhythm_satisfactions satisfied ON satisfied.source_id=care.id
       AND satisfied.organization_id=v_prior.organization_id
       AND satisfied.satisfaction_kind IN ('full','conditional')
       AND satisfied.evidence->>'workItemId'=v_prior.id::text
       AND satisfied.evidence->>'workResultId'=v_result.id::text
     WHERE accepted.execution_result_id=v_result.id
       AND accepted.work_item_id=v_prior.id
       AND accepted.organization_id=v_prior.organization_id
       AND accepted.decision='accepted'
       AND accepted.acceptance_kind='source_qualified_physical_actual')
 THEN
   RAISE EXCEPTION 'Standing campaign result lacks accepted original care source'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior_rule FROM atlas.rhythm_rules r
 WHERE r.id=atlas.rhythm_safe_uuid_v1(v_prior.metadata->>'sourceRuleId');
 IF v_prior_rule.id IS NULL THEN
   RAISE EXCEPTION 'Original standing policy not found' USING ERRCODE='23514';
 END IF;
 v_tz:=coalesce(nullif(v_prior_rule.metadata->>'timezoneName',''),
   (SELECT nullif(pr.home_timezone,'') FROM atlas.principals pr
    WHERE pr.person_id=v_actor AND pr.user_id=auth.uid() AND pr.status='active'
    ORDER BY pr.created_at DESC LIMIT 1),'UTC');
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names tz WHERE tz.name=v_tz)
 THEN RAISE EXCEPTION 'No governed service timezone' USING ERRCODE='22023'; END IF;
 v_next_date:=(v_result.reported_at AT TIME ZONE v_tz)::date+1;
 IF extract(dow FROM v_next_date)=0 THEN v_next_date:=v_next_date+1; END IF;
 v_end:=(v_prior.metadata->>'sourceStandingCampaignEndsOn')::date;
 IF v_next_date>v_end THEN
   RETURN jsonb_build_object('ok',true,'nextWorkCreated',false,
      'reason','campaign_window_ended','campaignId',v_campaign);
 END IF;
 -- An already delivered original is the campaign's outstanding capacity.
 SELECT w.id INTO v_existing FROM atlas.work_items w
 WHERE w.organization_id=v_prior.organization_id
   AND w.metadata->>'sourceStandingCampaignId'=v_campaign
   AND w.work_state='open'
 ORDER BY w.created_at,w.id LIMIT 1;
 IF v_existing IS NOT NULL THEN
   RETURN jsonb_build_object('ok',true,'nextWorkCreated',false,
     'reason','existing_open_campaign_work',
     'nextWorkItemId',v_existing);
 END IF;
 -- Source action replay must return the same serving, never another task.
 SELECT w.id INTO v_existing FROM atlas.work_items w
 WHERE w.organization_id=v_prior.organization_id
   AND w.metadata->>'sourceAutoPriorResultId'=v_result.id::text
   AND w.metadata->>'sourceStandingCampaignId'=v_campaign
 ORDER BY w.created_at,w.id LIMIT 1;
 IF v_existing IS NOT NULL THEN
   RETURN jsonb_build_object('ok',true,'nextWorkCreated',false,
     'reason','already_advanced_from_this_result',
     'nextWorkItemId',v_existing);
 END IF;
 SELECT * INTO v_next_state FROM atlas.rhythm_state s
 WHERE s.id=atlas.standing_care_next_subject_internal_v1(v_prior.id)
   AND s.organization_id=v_prior.organization_id;
 IF v_next_state.id IS NULL THEN
   RETURN jsonb_build_object('ok',true,'nextWorkCreated',false,
     'reason','no_disclosed_eligible_subject',
     'campaignId',v_campaign);
 END IF;
 SELECT * INTO v_next_rule FROM atlas.rhythm_rules
 WHERE id=v_next_state.rhythm_rule_id AND status='active';
 SELECT * INTO v_next_object FROM atlas.growing_objects
 WHERE id=v_next_state.subject_id AND farm_id=v_next_state.farm_id;
 IF v_next_rule.id IS NULL OR v_next_object.id IS NULL THEN
   RAISE EXCEPTION 'Selected Subject cannot be resolved' USING ERRCODE='23514';
 END IF;
 IF v_next_state.rhythm_key='mowing' THEN
   v_title:='Attend mowing route — '||v_next_object.label;
   v_instructions:='Owner-standing visit: inspect safety and mow only if appropriate. Report the actual. ';
 ELSE
   v_title:='Attend bed — '||v_next_object.label;
   v_instructions:='Owner-standing visit: inspect current occupants; weed or prepare only as appropriate. Report full, partial, already acceptable or blocked. ';
 END IF;
 v_instructions:=v_instructions||
   coalesce(v_prior.metadata->>'sourceStandingVisitReason','');
 v_serving:='standing-care:v1:'||v_campaign||':'||v_next_object.id::text;
 INSERT INTO atlas.work_items(
   organization_id,title,instructions,work_state,
   source_object_type,source_object_id,stable_key,result_contract_key,
   created_by_user_id,metadata
 ) VALUES(
   v_prior.organization_id,left(v_title,500),v_instructions,'open',
   'rhythm_state',v_next_state.id,
   'continuing:v1:'||pg_catalog.md5(
     v_prior.organization_id::text||':'||v_serving),
   'continuing_care_actual_v1',auth.uid(),
   jsonb_build_object(
     'sourceContract','continuing_original_work_v1',
     'needKind','rhythm_state','needId',v_next_state.id,
     'servingKey',v_serving,
     'sourceConfirmedBy','accepted_actual_under_owner_campaign',
     'sourceAdmissionMode','owner_standing_successor_v1',
     'sourceStandingCampaignMode','seasonal_closeout',
     'sourceStandingCampaignId',v_campaign,
     'sourceStandingCampaignEndsOn',v_end,
     'sourceStandingVisitReason',
       coalesce(v_prior.metadata->>'sourceStandingVisitReason',''),
     'sourceScopeId',v_scope.id,
     'sourceApprovedByPersonId',v_scope.proposed_by_person_id,
     'sourceRuleId',v_next_rule.id,
     'sourceRhythmIntervalSeconds',v_next_rule.validity_interval_seconds,
     'sourceSubjectId',v_next_object.id,
     'sourceServiceDate',v_next_date,
     'sourceAutoPriorWorkItemId',v_prior.id,
     'sourceAutoPriorResultId',v_result.id,
     'noConditionInferredFromClock',true)
 ) RETURNING id INTO v_work_id;
 INSERT INTO atlas.work_item_context_links(
   organization_id,work_item_id,subject_domain,subject_kind,
   subject_id,relation_kind,provenance,metadata
 ) VALUES (
   v_prior.organization_id,v_work_id,'spatial','growing_object',
   v_next_object.id,'acts_on',
   jsonb_build_object('sourceKind','rhythm_state',
     'sourceId',v_next_state.id,'campaignId',v_campaign),
   '{}'::jsonb
 );
 INSERT INTO atlas.company_work_native_ledger_relevance(
   organization_id,work_item_id,ledger_id,evidence_kind,
   attestation_source_ref,attestation_reason,established_by_person_id
 ) VALUES(
   v_prior.organization_id,v_work_id,v_ledger,'owner_attested',
   'atlas.work_execution_results:'||v_result.id::text,
   'Original root-admin seasonal visit campaign, continued by the accepted signed physical care Actual.',
   v_scope.proposed_by_person_id
 );
 INSERT INTO atlas.work_allocations(
   organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
   assignee_canonical_person_id,allocation_role,state,
   establishment_basis_kind,establishment_basis,metadata
 ) VALUES (
   v_prior.organization_id,v_work_id,NULL,NULL,
   v_actor,'responsible','active',
   'delegated_under_standing_scope',
   jsonb_build_object(
     'contractVersion','exact_work_responsibility_establishment_v2',
     'basisKind','delegated_under_standing_scope',
     'organizationId',v_prior.organization_id,
     'workItemId',v_work_id,
     'assigneePersonId',v_actor,
     'nativeLedgerId',v_ledger,
     'scopeId',v_scope.id,
     'priorResultId',v_result.id,
     'authorizationBasis','owner_preapproved_standing_care_actual_successor_v1'),
   jsonb_build_object('source','standing_care_auto_continuation_v1',
     'sourceStandingCampaignId',v_campaign,'sourcePriorResultId',v_result.id)
 ) RETURNING id INTO v_alloc_id;
 INSERT INTO atlas.work_execution_plans(
   organization_id,work_item_id,responsible_allocation_id,
   assignee_membership_id,planned_by_membership_id,plan_state,
   first_planned_service_date,planned_service_date,exposure_service_date,
   plan_reason,metadata
 ) VALUES (
   v_prior.organization_id,v_work_id,v_alloc_id,NULL,NULL,'active',
   v_next_date,v_next_date,v_next_date,
   'Next approved seasonal stewardship visit after signed accepted prior Actual.',
   jsonb_build_object('source','standing_care_auto_continuation_v1',
     'priorResultId',v_result.id,'campaignId',v_campaign)
 ) RETURNING id INTO v_plan_id;
 INSERT INTO atlas.work_execution_plan_events(
   organization_id,work_item_id,plan_id,event_kind,
   to_planned_service_date,to_exposure_service_date,
   actor_membership_id,reason,metadata
 ) VALUES(
   v_prior.organization_id,v_work_id,v_plan_id,'planned',
   v_next_date,v_next_date,NULL,
   'Owner-approved standing campaign automatically continued after accepted Actual.',
   jsonb_build_object('source','standing_care_auto_continuation_v1',
     'priorResultId',v_result.id,'sourceScopeId',v_scope.id)
 );
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','standing_care_auto_continuation_v1',
   'nextWorkCreated',true,'nextWorkItemId',v_work_id,
   'nextPlanId',v_plan_id,'nextServiceDate',v_next_date,
   'subjectId',v_next_object.id,'sourceRuleId',v_next_rule.id,
   'campaignId',v_campaign,'actualResultId',v_result.id,
   'notLegacyTask',true,'noPhysicalConditionInferred',true);
END;
$advance$;
REVOKE ALL ON FUNCTION atlas.advance_owner_standing_campaign_after_actual_internal_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
