-- CANDIDATE ONLY. Do not apply to production or call from a client.
-- Reuse canonical atlas.work_items; this is a private source-to-one-serving primitive,
-- NOT an independent recurring task generator, Today writer or farm care engine.
-- Caller must already have established the exact physical/operational Need and
-- domain-specific qualifying Result contract before calling this internal primitive.
CREATE OR REPLACE FUNCTION atlas.establish_continuing_original_work_internal_v1(
  p_custody_kind text,
  p_custody_id uuid,
  p_ledger_id uuid,
  p_need_kind text,
  p_need_id uuid,
  p_serving_key text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id uuid,
  p_title text,
  p_instructions text,
  p_result_contract_key text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_need atlas.household_need_occurrences_v1%ROWTYPE;
  v_rhythm atlas.rhythm_state%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_person uuid;
  v_stable_key text;
  v_existing_count integer;
  v_source_domain text;
BEGIN
  -- No arbitrary authenticated client is authorized to call this function:
  -- EXECUTE is revoked below. The only authorized caller is a governed
  -- source-owned writer that already proved the exact present Need and
  -- compatible Result, not a planner or a legacy task/clock reader.
  IF auth.uid() IS NULL OR p_custody_kind IS NULL
    OR p_custody_kind NOT IN ('household','organization')
    OR p_need_kind IS NULL OR p_subject_domain IS NULL
    OR p_subject_kind IS NULL
    OR p_custody_id IS NULL OR p_need_id IS NULL
    OR p_subject_id IS NULL OR p_result_contract_key IS NULL
    OR nullif(btrim(coalesce(p_title,'')),'') IS NULL
    OR length(p_title)>500
    OR nullif(btrim(coalesce(p_serving_key,'')),'') IS NULL
    OR length(p_serving_key)>200
    OR length(coalesce(p_instructions,''))>8000
  THEN
    RAISE EXCEPTION 'Exact signed custody, source Need, serving and result are required'
      USING ERRCODE='22023';
  END IF;

  IF p_custody_kind='household' THEN
    IF p_ledger_id IS NOT NULL OR p_need_kind<>'household_need_occurrence'
       OR p_subject_domain<>'household' OR p_subject_kind<>'kernel_instance' THEN
      RAISE EXCEPTION 'Household source cannot claim organization authority'
        USING ERRCODE='42501';
    END IF;
    v_source_domain:='household';
    v_person:=atlas.require_household_governor_self_v1(p_custody_id);
    SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
      WHERE id=p_need_id AND household_id=p_custody_id
        AND instance_id=p_subject_id AND state='open'
      FOR UPDATE;
    IF v_need.id IS NULL THEN
      RAISE EXCEPTION 'Unconfirmed or closed original Household Need'
        USING ERRCODE='23514';
    END IF;
    -- Household Work already has a source guard; preserve its exact custody,
    -- type, and policy. This helper must never silently broaden that guard.
    IF p_result_contract_key<>'household_laundry_begin_cycle_v1' THEN
      RAISE EXCEPTION 'Household Need does not have a released physical Result policy'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.household_kernel_instances inst
      WHERE inst.id=p_subject_id AND inst.household_id=p_custody_id
        AND inst.kernel_key='household.laundry' AND inst.state='active'
    ) THEN
      RAISE EXCEPTION 'Exact established Household kernel and Need are required'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.care_current_state c
      WHERE c.scope_kind='household' AND c.scope_id=p_custody_id
        AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
        AND c.subject_id=p_subject_id::text
        AND c.condition_state='ready_for_cycle'
        AND c.last_observation_id=v_need.opened_by_observation_id
    ) THEN
      RAISE EXCEPTION 'Household Need lacks current confirmed physical condition'
        USING ERRCODE='23514';
    END IF;
  ELSE
    IF p_need_kind<>'rhythm_state' OR p_ledger_id IS NULL
       OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object' THEN
      RAISE EXCEPTION 'Organization source requires exact governed jurisdiction'
        USING ERRCODE='42501';
    END IF;
    v_source_domain:='organization';
    v_person:=atlas.company_work_native_ledger_owner_self_v1(
      p_custody_id,p_ledger_id);
    SELECT * INTO v_rhythm FROM atlas.rhythm_state s
    WHERE s.id=p_need_id AND s.organization_id=p_custody_id
      AND s.subject_kind='growing_object' AND s.subject_id=p_subject_id
      AND s.state IN ('due','fallen_out_of_rhythm','recovering')
      AND EXISTS (
        SELECT 1 FROM atlas.growing_objects go
        WHERE go.id=s.subject_id AND go.farm_id=s.farm_id
      )
      AND EXISTS (
        SELECT 1 FROM atlas.rhythm_bindings b
        JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
        WHERE b.id=s.rhythm_binding_id AND b.active AND r.status='active'
      )
    FOR UPDATE;
    IF v_rhythm.id IS NULL THEN
      RAISE EXCEPTION 'Absent, paused or non-actionable original Need'
        USING ERRCODE='23514';
    END IF;
    -- This primitive cannot adjudicate weed pressure, mower safety, a
    -- seasonal Resting state, or stale observations. No caller is released
    -- until its domain adapter enforces those independent physical gates.
    -- A special source-qualified physical-Actual policy is also required;
    -- generic worker attestation cannot assert care state/satisfaction.
    -- It is never called by farm_rhythm_tick or by legacy task release.
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.work_result_contract_policies policy
    WHERE policy.contract_key=p_result_contract_key AND policy.active
      AND policy.source_domain=v_source_domain
      AND policy.acceptance_mode='domain_adapter'
      AND (
        v_source_domain='household'
        OR policy.metadata->>'continuingActualQualification'='source_proven_v1'
      )
  ) THEN
    RAISE EXCEPTION 'No active Result contract in exact native custody'
      USING ERRCODE='23514';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-work:'||p_custody_kind||':'||p_custody_id::text||
      ':'||p_need_kind||':'||p_need_id::text,0));

  -- Source-id lock prevents two concurrently valid servings for one Need.
  -- A new serving key may be used only after the previous actual Work closes.
  SELECT count(*) INTO v_existing_count FROM atlas.work_items w
  WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
      OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
    AND w.source_object_type=p_need_kind AND w.source_object_id=p_need_id
    AND w.work_state='open';
  IF v_existing_count>1 THEN
    RAISE EXCEPTION 'Multiple active original Work servings for one Need'
      USING ERRCODE='23514';
  END IF;
  IF v_existing_count=1 THEN
    SELECT * INTO v_work FROM atlas.work_items w
    WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
       OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
      AND w.source_object_type=p_need_kind AND w.source_object_id=p_need_id
      AND w.work_state='open'
    FOR UPDATE;
    IF v_work.result_contract_key IS DISTINCT FROM p_result_contract_key THEN
      RAISE EXCEPTION 'Existing Need Work has a different Result contract'
        USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'workItemId',v_work.id,'existingOpenServing',true,
      'noNewWorkCreated',true,'clockAdmitted',false,
      'sourceKind',p_need_kind,'sourceId',p_need_id);
  END IF;

  v_stable_key:='continuing:v1:'||md5(
    p_custody_kind||':'||p_custody_id::text||':'||
    p_need_kind||':'||p_need_id::text||':'||p_serving_key);
  -- A closed identical serving cannot be reopened via a retry.
  IF EXISTS (
    SELECT 1 FROM atlas.work_items w
    WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
       OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
      AND w.stable_key=v_stable_key
  ) THEN
    RAISE EXCEPTION 'This continuing Work serving already has closed history'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_items(
    organization_id,household_id,title,instructions,work_state,
    source_object_type,source_object_id,stable_key,result_contract_key,
    created_by_user_id,metadata
  ) VALUES (
    CASE WHEN p_custody_kind='organization' THEN p_custody_id ELSE NULL END,
    CASE WHEN p_custody_kind='household' THEN p_custody_id ELSE NULL END,
    p_title,p_instructions,'open',p_need_kind,p_need_id,v_stable_key,
    p_result_contract_key,auth.uid(),
    jsonb_build_object(
      'sourceContract','continuing_original_work_v1',
      'needKind',p_need_kind,'needId',p_need_id,'servingKey',p_serving_key,
      'sourceConfirmedBy','governed_domain_writer',
      'noCalendarDateInferred',true,'noClockAdmissionInferred',true)
  ) RETURNING * INTO v_work;

  INSERT INTO atlas.work_item_context_links(
    organization_id,household_id,work_item_id,subject_domain,
    subject_kind,subject_id,relation_kind,provenance,metadata
  ) VALUES (
    v_work.organization_id,v_work.household_id,v_work.id,
    p_subject_domain,p_subject_kind,p_subject_id,'acts_on',
    jsonb_build_object('needKind',p_need_kind,'needId',p_need_id,
      'sourceContract','continuing_original_work_v1'),
    '{}'::jsonb
  );

  IF p_custody_kind='household' THEN
    UPDATE atlas.household_need_occurrences_v1
    SET current_work_item_id=v_work.id,updated_at=now()
    WHERE id=v_need.id AND current_work_item_id IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Household Need already owns another original Work'
        USING ERRCODE='23514';
    END IF;
  END IF;
  -- Native Ledger relevance is NOT inferred or automatically attested here.
  -- The domain writer must establish exact source-governed Ledger relevance
  -- and original Person responsibility in the same authorized transaction,
  -- otherwise the entire source transaction must fail/roll back.

  RETURN jsonb_build_object('ok',true,'contractVersion',
    'continuing_original_work_v1','workItemId',v_work.id,
    'sourceKind',p_need_kind,'sourceId',p_need_id,
    'existingOpenServing',false,'noNewWorkCreated',false,
    'ledgerRelevanceEstablished',false,
    'responsibilityEstablished',false,'clockAdmitted',false);
END;
$function$;
-- Never expose this primitive as an executable signed-user command.
-- Only separately reviewed source domain writers may call it.
REVOKE ALL ON FUNCTION atlas.establish_continuing_original_work_internal_v1(
  text,uuid,uuid,text,uuid,text,text,text,uuid,text,text,text
) FROM PUBLIC, anon, authenticated, service_role;


-- Reuse Atlas's existing reality_continuation_v1 contract. This private
-- post-Result review is READ ONLY. A domain's signed Actual writer remains
-- responsible for accepting and recording physical truth; this function
-- cannot mark an area clear, close Work or pre-create another occurrence.
CREATE OR REPLACE FUNCTION atlas.continuing_original_work_result_continuation_internal_v1(
  p_execution_result_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $continuation$
DECLARE
  v_result atlas.work_execution_results%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_acceptance atlas.work_result_acceptances%ROWTYPE;
  v_care atlas.care_result_events%ROWTYPE;
  v_need atlas.household_need_occurrences_v1%ROWTYPE;
  v_rhythm atlas.rhythm_state%ROWTYPE;
  v_satisfaction atlas.rhythm_satisfactions%ROWTYPE;
  v_domain text;
  v_scope_id uuid;
  v_source_kind text;
  v_source_id uuid;
  v_decision text := 'blocked';
  v_reason text := 'source_result_not_accepted';
  v_blockers jsonb := '[]'::jsonb;
  v_current jsonb := '{}'::jsonb;
  v_refs jsonb := '[]'::jsonb;
  v_care_ref text;
  v_target jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_execution_result_id IS NULL THEN
    RAISE EXCEPTION 'An exact signed Result is required'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_result FROM atlas.work_execution_results
    WHERE id=p_execution_result_id;
  IF v_result.id IS NULL THEN
    RAISE EXCEPTION 'Exact original Work Result unavailable'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=v_result.work_item_id
      AND organization_id IS NOT DISTINCT FROM v_result.organization_id
      AND household_id IS NOT DISTINCT FROM v_result.household_id;
  IF v_work.id IS NULL OR
     ((v_work.organization_id IS NULL) = (v_work.household_id IS NULL)) OR
     v_work.result_contract_key IS DISTINCT FROM v_result.result_contract_key OR
     v_work.source_object_id IS NULL OR
     v_work.source_object_type NOT IN ('household_need_occurrence','rhythm_state')
  THEN
    RAISE EXCEPTION 'Result has no supported original Need-bound Work'
      USING ERRCODE='23514';
  END IF;
  v_domain := CASE WHEN v_work.household_id IS NOT NULL
    THEN 'household' ELSE 'organization' END;
  v_scope_id := COALESCE(v_work.household_id,v_work.organization_id);
  v_source_kind:=v_work.source_object_type;
  v_source_id:=v_work.source_object_id;
  -- This is not a public reader. No raw result content or cross-scope data
  -- can leave this function through an authenticated or service-role grant.
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key=v_result.result_contract_key
      AND p.active AND p.source_domain=v_domain
      AND p.acceptance_mode='domain_adapter'
      AND (v_domain='household'
        OR p.metadata->>'continuingActualQualification'='source_proven_v1')
  ) THEN
    RAISE EXCEPTION 'Result is not qualified for source-owned continuation'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_acceptance FROM atlas.work_result_acceptances a
    WHERE a.execution_result_id=v_result.id
      AND a.work_item_id=v_work.id
      AND a.organization_id IS NOT DISTINCT FROM v_work.organization_id
      AND a.household_id IS NOT DISTINCT FROM v_work.household_id;
  v_refs:=jsonb_build_array(jsonb_build_object(
    'kind','work_execution_result','ref',v_result.id));
  IF v_acceptance.id IS NOT NULL THEN
    v_refs:=v_refs||jsonb_build_array(jsonb_build_object(
      'kind','work_result_acceptance','ref',v_acceptance.id));
  END IF;

  IF v_domain='household' THEN
    SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 n
      WHERE n.id=v_source_id AND n.household_id=v_scope_id
        AND n.current_work_item_id=v_work.id;
    IF v_need.id IS NULL OR v_result.result_contract_key IS DISTINCT FROM
        'household_laundry_begin_cycle_v1' THEN
      RAISE EXCEPTION 'Household Result has no original confirmed Need'
        USING ERRCODE='23514';
    END IF;
  ELSE
    SELECT * INTO v_rhythm FROM atlas.rhythm_state s
      WHERE s.id=v_source_id AND s.organization_id=v_scope_id
        AND s.subject_kind='growing_object';
    IF v_rhythm.id IS NULL THEN
      RAISE EXCEPTION 'Organization Result has no original governed Rhythm Need'
        USING ERRCODE='23514';
    END IF;
  END IF;

  v_current:=jsonb_build_object(
    'workState',v_work.work_state,
    'resultKind',v_result.result_kind,
    'acceptanceDecision',v_acceptance.decision);
  IF v_acceptance.id IS NULL OR v_acceptance.decision<>'accepted'
     OR v_acceptance.acceptance_kind IS DISTINCT FROM
        'source_qualified_physical_actual' THEN
    v_blockers:=jsonb_build_array('qualifying_original_result_acceptance_required');
  ELSE
    v_care_ref:=v_result.payload->>'careResultId';
    IF v_care_ref IS NULL OR v_care_ref !~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
      v_blockers:=jsonb_build_array('source_physical_actual_reference_required');
    ELSE
      SELECT * INTO v_care FROM atlas.care_result_events c
      WHERE c.id=v_care_ref::uuid
        AND c.scope_id=CASE WHEN v_domain='household'
          THEN v_scope_id ELSE v_rhythm.farm_id END
        AND c.scope_kind=CASE WHEN v_domain='household'
          THEN 'household' ELSE 'farm' END
        AND c.subject_kind=CASE WHEN v_domain='household'
          THEN 'household_kernel_instance' ELSE 'growing_object' END
        AND c.subject_id=CASE WHEN v_domain='household'
          THEN v_need.instance_id::text ELSE v_rhythm.subject_id::text END
        AND c.actor_user_id=v_result.reported_by_user_id;
      IF v_care.id IS NULL THEN
        v_blockers:=jsonb_build_array('matching_first_party_physical_actual_required');
      ELSE
        v_refs:=v_refs||jsonb_build_array(jsonb_build_object(
          'kind','care_result_event','ref',v_care.id));
        v_current:=v_current||jsonb_build_object(
          'actualResultKind',v_care.result_kind,
          'conditionAfter',v_care.condition_after);
        IF v_domain='household' THEN
          IF v_need.state='satisfied'
             AND v_need.satisfied_by_care_result_id=v_care.id
             AND v_work.work_state='completed'
             AND v_result.result_kind='completed'
          THEN
            v_decision:='settled';
            v_reason:='original_need_satisfied_by_accepted_actual';
            -- The wash-started result ends begin_cycle ONLY. It does not
            -- establish another wash Need, or complete later Laundry stages.
          ELSE
            v_decision:='reconsider';
            v_reason:='household_need_state_requires_reconciliation';
            v_blockers:=jsonb_build_array('household_need_satisfaction_not_confirmed');
          END IF;
          v_current:=v_current||jsonb_build_object('needState',v_need.state);
        ELSE
          -- Farm satisfaction is not inferred from generic Done or a
          -- possibly-stale deadline. Require exact qualified source evidence.
          SELECT * INTO v_satisfaction FROM atlas.rhythm_satisfactions s
          WHERE s.organization_id=v_scope_id
            AND s.rhythm_state_id=v_rhythm.id
            AND s.source_id=v_care.id
            AND s.evidence->>'workItemId'=v_work.id::text
          ORDER BY s.satisfied_at DESC,s.id DESC LIMIT 1;
          IF v_satisfaction.id IS NOT NULL THEN
            v_refs:=v_refs||jsonb_build_array(jsonb_build_object(
              'kind','rhythm_satisfaction','ref',v_satisfaction.id));
            v_current:=v_current||jsonb_build_object(
              'rhythmState',v_rhythm.state,
              'satisfactionKind',v_satisfaction.satisfaction_kind,
              'nextEligibleAt',v_rhythm.due_at);
            IF v_work.work_state='completed'
               AND v_result.result_kind='completed'
               AND v_satisfaction.satisfaction_kind IN ('full','conditional')
            THEN
              v_decision:='settled';
              v_reason:='qualified_source_rhythm_satisfaction_recorded';
              -- The next window is only source eligibility, not a Work,
              -- assignment, work-on date, Today admission, or observation.
            ELSE
              v_decision:='reconsider';
              v_reason:='partial_actual_requires_original_need_review';
            END IF;
          ELSE
            v_decision:='reconsider';
            v_reason:='farm_source_satisfaction_not_established';
            v_blockers:=jsonb_build_array(
              'domain_owned_rhythm_satisfaction_required');
            v_current:=v_current||jsonb_build_object(
              'rhythmState',v_rhythm.state);
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  v_target:=jsonb_build_object(
    'target',jsonb_build_object(
      'domain',v_domain,'kind',v_source_kind,'ref',v_source_id,
      'scope',jsonb_build_object(
        CASE WHEN v_domain='household' THEN 'householdId'
          ELSE 'organizationId' END,v_scope_id)),
    'resolver',jsonb_build_object(
      'key','continuing_original_need_source_qualification','version','v1'),
    'reason',jsonb_build_object('kind',v_reason,'basisRefs',v_refs),
    'disposition',v_decision,'current',v_current,'blockers',v_blockers
  );
  RETURN atlas.reality_continuation_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_continuation_v1',
      'source',jsonb_build_object(
        'domain',v_domain,'kind','work_execution_result',
        'ref',v_result.id,'changedAt',v_result.reported_at,
        'state',v_decision),
      'targets',jsonb_build_array(v_target),
      'provenance',jsonb_build_object(
        'adapter','continuing_original_work_result_continuation_internal_v1',
        'existingCanonicalWork',true,'readOnly',true,
        'doesNotCreateWork',true,'doesNotAdvanceRhythm',true,
        'doesNotGrantAuthority',true)
    )
  );
END;
$continuation$;

-- Internal-only. Never turn cross-scope result inspection into a client
-- reader, even for service-role transport. The eventual signed domain
-- Result writer is a separate source-enforced authorization boundary.
REVOKE ALL ON FUNCTION atlas.continuing_original_work_result_continuation_internal_v1(
  uuid
) FROM PUBLIC, anon, authenticated, service_role;
