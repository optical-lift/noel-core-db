-- HELD SOURCE ADMISSION, NOT A FARM TASK ENGINE.
-- An explicitly entrusted Person may admit exactly one native original Work
-- for a currently due, observed and disclosed Need under the Ledger owner's
-- immutable standing authorization. Work and day are explicit in this call.
-- No synthetic owner session, employee seat, clock-triggered work, or copied
-- physical observation. Built on native Work, Ledger, allocation, plan, Today.
CREATE OR REPLACE FUNCTION atlas.admit_standing_continuing_source_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_action_id uuid,p_service_date date
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $admit$
DECLARE
 v_actor uuid:=atlas.current_person_id_v1();
 v_policy atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_rule atlas.rhythm_rules%ROWTYPE;
 v_object atlas.growing_objects%ROWTYPE;
 v_current atlas.care_current_state%ROWTYPE;
 v_observation atlas.care_observation_events%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_allocation uuid;
 v_plan uuid;
 v_stable text;
 v_eligibility jsonb;
 v_today date;
 v_title text;
 v_instructions text;
BEGIN
 IF auth.uid() IS NULL OR v_actor IS NULL OR p_organization_id IS NULL
 OR p_ledger_id IS NULL OR p_rhythm_state_id IS NULL
 OR p_action_id IS NULL OR p_service_date IS NULL
 THEN
  RAISE EXCEPTION 'Signed exact source and deliberate Person-day required'
   USING ERRCODE='22023';
 END IF;
 -- Lock physical observation -> source Need -> canonical serving. Signed
 -- concurrent reports and admission cannot mint two valid original servings.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.standing-physical-observation:'||p_organization_id||':'||p_rhythm_state_id,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.continuing-need-owner:'||p_organization_id||':'||p_rhythm_state_id,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.continuing-work:organization:'||p_organization_id||
   ':rhythm_state:'||p_rhythm_state_id,0));
 SELECT * INTO v_policy FROM atlas.continuing_work_source_governance_events_v1 p
 WHERE p.organization_id=p_organization_id AND p.ledger_id=p_ledger_id
 AND p.source_kind='rhythm_state' AND p.source_id=p_rhythm_state_id
 ORDER BY p.recorded_at DESC,p.id DESC LIMIT 1;
 IF v_policy.id IS NULL OR v_policy.authorization_method<>'standing_source_observed'
 OR v_policy.worker_visibility<>'eligible_disclosed' THEN
   RAISE EXCEPTION 'No current governor-authorized standing admission'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=v_policy.worker_scope_id AND s.organization_id=p_organization_id
 AND s.ledger_id=p_ledger_id FOR SHARE;
 IF v_scope.id IS NULL OR v_scope.proposed_by_person_id IS DISTINCT FROM
   v_policy.decided_by_person_id
 OR v_scope.worker_person_id IS DISTINCT FROM v_actor
 OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.scope_state<>'active' OR v_scope.coverage_mode<>'ledger_all_work'
 OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_actor)
 OR NOT EXISTS (
   SELECT 1 FROM atlas.principals principal
   JOIN atlas.principal_ledger_authorities a ON a.principal_id=principal.id
   WHERE principal.person_id=v_policy.decided_by_person_id
    AND principal.status='active' AND a.ledger_id=p_ledger_id
    AND a.authority_kind='root_governing' AND a.status='active')
 THEN
   RAISE EXCEPTION 'Current owner mandate and accepted connected Person required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
 AND s.subject_kind='growing_object' FOR UPDATE;
 SELECT * INTO v_rule FROM atlas.rhythm_rules r
 JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
 WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
 AND b.farm_id=v_state.farm_id AND b.organization_id=p_organization_id
 AND b.active AND r.status='active';
 SELECT * INTO v_object FROM atlas.growing_objects g
 WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id;
 IF v_state.id IS NULL OR v_rule.id IS NULL OR v_object.id IS NULL
 OR v_state.state='paused'
 OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
 OR NOT EXISTS(SELECT 1 FROM atlas.farms f
   WHERE f.id=v_state.farm_id AND f.organization_id=p_organization_id
   AND f.status='active')
 THEN RAISE EXCEPTION 'Current physical governing source unavailable'
   USING ERRCODE='23514'; END IF;
 IF NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'identity')
 OR NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'condition')
 THEN RAISE EXCEPTION 'Standing Work physical Subject withheld'
   USING ERRCODE='42501'; END IF;
 v_today:=(now() AT TIME ZONE
   coalesce(nullif(v_rule.metadata->>'timezoneName',''),'UTC'))::date;
 IF p_service_date<v_today OR p_service_date>v_today+14 THEN
   RAISE EXCEPTION 'Worker-selected source Work service day must be within the next 14 local days'
   USING ERRCODE='22023'; END IF;
 v_stable:='continuing:v1:'||md5(
   'organization:'||p_organization_id||':rhythm_state:'||p_rhythm_state_id
   ||':'||p_action_id);
 -- Exact retry preserves Work and plan history. Never shift the assigned
 -- day or source authority as a side-effect of an idempotency retry.
 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.organization_id=p_organization_id
 AND w.stable_key=v_stable AND w.source_object_type='rhythm_state'
 AND w.source_object_id=p_rhythm_state_id FOR UPDATE;
 IF v_work.id IS NOT NULL THEN
   IF v_work.metadata->>'standingPolicyEventId' IS DISTINCT FROM v_policy.id::text
   OR v_work.metadata->>'sourceScopeId' IS DISTINCT FROM v_scope.id::text
   OR v_work.metadata->>'sourceServiceDate' IS DISTINCT FROM p_service_date::text
   OR v_work.metadata->>'standingAdmissionActorId' IS DISTINCT FROM v_actor::text
   THEN RAISE EXCEPTION 'Standing action replay would change original Work'
    USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('ok',true,'idempotent',true,
     'workItemId',v_work.id,'workState',v_work.work_state,
     'noNewWorkCreated',true,'assignmentUnchanged',true);
 END IF;
 -- NO second serving while the prior original or legacy obligation is open.
 IF EXISTS (SELECT 1 FROM atlas.work_items w
    WHERE w.organization_id=p_organization_id
      AND w.source_object_type='rhythm_state'
      AND w.source_object_id=p_rhythm_state_id AND w.work_state='open')
 OR EXISTS (SELECT 1 FROM atlas.tasks t
    LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
    WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
    AND (t.metadata->>'rhythm_state_id'=p_rhythm_state_id::text
       OR (o.source_kind='rhythm_state' AND o.source_id=p_rhythm_state_id)))
 THEN RAISE EXCEPTION 'Existing original or legacy Work still serves this Need'
    USING ERRCODE='23514'; END IF;
 -- Reuse the existing signed source evaluator: due clock alone never admits.
 v_eligibility:=atlas.continuing_work_source_eligibility_self_api_v1(
    p_organization_id,p_ledger_id,p_rhythm_state_id);
 IF v_eligibility->>'eligible' IS DISTINCT FROM 'true'
 OR v_eligibility->>'reasonCode' IS DISTINCT FROM 'source_qualified_and_timing_eligible'
 THEN RAISE EXCEPTION 'Current observed source is not eligible for new Work'
    USING ERRCODE='23514'; END IF;
 SELECT * INTO v_current FROM atlas.care_current_state c
 WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
  AND c.subject_domain='farm' AND c.subject_kind='growing_object'
  AND c.subject_id=v_state.subject_id::text FOR SHARE;
 SELECT * INTO v_observation FROM atlas.care_observation_events e
 WHERE e.id=v_current.last_observation_id AND e.scope_id=v_state.farm_id
  AND e.subject_kind='growing_object' AND e.subject_id=v_state.subject_id::text;
 IF v_observation.id IS NULL OR v_observation.inferred_from_clock
 OR v_observation.observed_by_user_id IS NULL
 OR v_observation.condition_state IS DISTINCT FROM v_current.condition_state
 OR v_current.last_observed_at IS DISTINCT FROM v_observation.observed_at
 OR v_observation.observed_at < now()-(
     v_policy.observation_max_age_seconds * interval '1 second')
 OR v_observation.observed_at <= COALESCE(
   (SELECT satisfaction.satisfied_at FROM atlas.rhythm_satisfactions satisfaction
    WHERE satisfaction.id=v_state.last_qualifying_satisfaction_id),
   '-infinity'::timestamptz)
 THEN RAISE EXCEPTION 'Fresh source condition changed; review again'
  USING ERRCODE='23514'; END IF;
 IF v_state.rhythm_key='mowing' THEN
   v_title:='Inspect and mow if warranted — '||v_object.label;
   v_instructions:='Inspect route and ground safety. Mow only if appropriate and report the physical result.';
 ELSE
   v_title:='Inspect and weed if warranted — '||v_object.label;
   v_instructions:='Inspect weed pressure and care strategy. Weed only if warranted and report actual condition.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_result_contract_policies p
   WHERE p.contract_key='continuing_care_actual_v1' AND p.active
     AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
     AND p.metadata->>'continuingActualQualification'='source_proven_v1')
 THEN RAISE EXCEPTION 'Native physical Result contract unavailable'
   USING ERRCODE='23514'; END IF;
 INSERT INTO atlas.work_items (
   organization_id,title,instructions,work_state,
   source_object_type,source_object_id,stable_key,result_contract_key,
   created_by_user_id,metadata
 ) VALUES(
   p_organization_id,left(v_title,500),v_instructions,'open',
   'rhythm_state',p_rhythm_state_id,v_stable,'continuing_care_actual_v1',
   auth.uid(),
   jsonb_build_object(
     'sourceContract','continuing_original_work_v1',
     'needKind','rhythm_state','needId',p_rhythm_state_id,
     'servingKey',p_action_id,
     'sourceConfirmedBy','standing_source_observed_with_signed_physical_evidence',
     'standingPolicyEventId',v_policy.id,
     'sourceScopeId',v_scope.id,
     'sourceServiceDate',p_service_date,
     'sourceObservationId',v_observation.id,
     'sourceObservedAt',v_observation.observed_at,
     'sourceObservedCondition',v_observation.condition_state,
     'standingAdmissionActorId',v_actor,
     'noCalendarDateInferred',true,'noClockAdmissionInferred',true)
 ) RETURNING * INTO v_work;
 INSERT INTO atlas.work_item_context_links(
   organization_id,work_item_id,subject_domain,
   subject_kind,subject_id,relation_kind,provenance,metadata
 ) VALUES(
   p_organization_id,v_work.id,'spatial','growing_object',
   v_state.subject_id,'acts_on',
   jsonb_build_object('needKind','rhythm_state','needId',p_rhythm_state_id,
     'sourceContract','continuing_original_work_v1',
     'standingPolicyEventId',v_policy.id,'sourceObservationId',v_observation.id),
   '{}'::jsonb);
 -- Source verified, NOT a false new governor attestation. The trusted
 -- exact-source resolver must return this immutable owner policy event.
 INSERT INTO atlas.company_work_native_ledger_relevance(
   organization_id,work_item_id,ledger_id,evidence_kind,
   source_schema,source_table,source_id,verified_at,established_by_person_id
 ) VALUES(
   p_organization_id,v_work.id,p_ledger_id,'source_verified',
   'atlas','continuing_work_source_governance_events_v1',v_policy.id,
   clock_timestamp(),v_actor);
 IF NOT EXISTS(SELECT 1
    FROM atlas.company_work_native_ledger_exact_source_v1(v_work.id,p_ledger_id) source
    WHERE source.source_schema='atlas'
      AND source.source_table='continuing_work_source_governance_events_v1'
      AND source.source_id=v_policy.id)
 THEN RAISE EXCEPTION 'Existing native Work Ledger source resolver rejected standing authority'
  USING ERRCODE='23514'; END IF;
 INSERT INTO atlas.work_allocations(
   organization_id,work_item_id,assignee_membership_id,
   assignee_canonical_person_id,assigned_by_membership_id,
   allocation_role,state,allocated_at,establishment_basis_kind,
   establishment_basis,metadata
 ) VALUES(
   p_organization_id,v_work.id,NULL,v_scope.worker_person_id,NULL,
   'responsible','active',clock_timestamp(),
   'delegated_under_standing_scope',
   jsonb_build_object('contractVersion','exact_work_responsibility_establishment_v2',
     'basisKind','delegated_under_standing_scope',
     'organizationId',p_organization_id,'workItemId',v_work.id,
     'nativeLedgerId',p_ledger_id,'scopeId',v_scope.id,
     'assigneePersonId',v_scope.worker_person_id,
     'scopeAcceptedAt',v_scope.accepted_at,'establishedAt',clock_timestamp(),
     'standingPolicyEventId',v_policy.id,
     'physicalSourceObservationId',v_observation.id),
   jsonb_build_object('source','standing_continuing_source_admission_v1',
     'governorPersonId',v_policy.decided_by_person_id,
     'admittedByPersonId',v_actor,'noEmployeeSeatRequired',true)
 ) RETURNING id INTO v_allocation;
 INSERT INTO atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,planned_by_membership_id,
    plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata
 ) VALUES(
    p_organization_id,v_work.id,v_allocation,NULL,NULL,
    'active',p_service_date,p_service_date,p_service_date,
    'Connected Person explicitly selected this service day under preauthorized, physically verified standing care.',
    jsonb_build_object('source','standing_continuing_source_admission_v1',
       'governorPolicyEventId',v_policy.id,
       'physicalObservationId',v_observation.id,
       'personSelectedDay',true,'noClockPlacement',true)
 ) RETURNING id INTO v_plan;
 INSERT INTO atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata
 ) VALUES(
   p_organization_id,v_work.id,v_plan,'planned',
   p_service_date,p_service_date,NULL,
   'Original Work date explicitly selected by signed entrusted Person within owner mandate',
   jsonb_build_object('standingPolicyEventId',v_policy.id,
       'sourceObservationId',v_observation.id,'workerPersonId',v_actor));
 RETURN jsonb_build_object('ok',true,'contractVersion',
    'standing_continuing_original_work_admission_v1',
    'workItemId',v_work.id,'rhythmStateId',p_rhythm_state_id,
    'responsiblePersonId',v_actor,'policyEventId',v_policy.id,
    'physicalObservationId',v_observation.id,
    'allocationId',v_allocation,'planId',v_plan,
    'serviceDate',p_service_date,'newOriginalWorkCreated',true,
    'noNextWorkPrecreated',true,'noClockAdmission',true);
END;
$admit$;
REVOKE ALL ON FUNCTION atlas.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date
) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.admit_standing_continuing_source_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_action_id uuid,p_service_date date
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.admit_standing_continuing_source_work_self_api_v1(
 p_organization_id,p_ledger_id,p_rhythm_state_id,p_action_id,p_service_date);
$public$;
REVOKE ALL ON FUNCTION public.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date
) TO authenticated;
SELECT pg_catalog.pg_notify('pgrst','reload schema');
