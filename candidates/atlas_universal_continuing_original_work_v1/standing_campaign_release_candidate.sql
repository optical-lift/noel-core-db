BEGIN;
-- DRAFT ONLY: compiled standing-care continuation source candidate.
-- Integration order is source base, owner admission, policy preview, disclosure,
-- exact successor authorization, allocation guard, auto-advance, typed Actual.
-- No public app EXECUTE grants. Not approved for deployment.
-- Governed ATLAS continuing original Work candidate. DRAFT ONLY.
-- No production release without full production-schema clone + signed tests.

-- SOURCE SECTION: candidate.sql
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
      AND s.state<>'paused'
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
    -- The domain writer, not an elapsed clock, proves immediate condition.
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

-- SOURCE SECTION: 02_farm_care_actual_adapter.sql
-- DRAFT SOURCE CANDIDATE; requires protected-clone signed positive/negative tests.
-- This is a DOMAIN ADAPTER using universal original Work/Result/Continuation.
-- It DOES NOT create a farm task generator, legacy task, employee seat,
-- new canonical Work store, scheduled task, or automatic next original Work.
-- Apply only after candidate.sql in an isolated, authorized validation clone.
--
-- The existing Household Laundry adapter continues independently under its
-- exact source and Result guard. No generic client is allowed to invent a
-- "source-qualified" Work Result merely by passing a JSON payload.

INSERT INTO atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
)
VALUES(
  'continuing_care_actual_v1','organization','domain_adapter',true,
  'Authenticated original responsible Person reports actual care against a governed continuing Need and physical Subject',
  jsonb_build_object(
    'continuingActualQualification','source_proven_v1',
    'requiresOriginalWork',true,'requiresExactSubject',true,
    'requiresAcceptedNativePerson',true,
    'clockDoesNotAssertCondition',true,
    'noAutogeneratedNextWork',true)
)
ON CONFLICT (contract_key) DO NOTHING;
-- Never overwrite an existing policy with different trust semantics.
DO $policy$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key='continuing_care_actual_v1'
      AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
      AND p.active
      AND p.metadata->>'continuingActualQualification'='source_proven_v1'
  ) THEN
    RAISE EXCEPTION 'Care Actual contract policy does not match required source qualification';
  END IF;
END;
$policy$;

CREATE OR REPLACE FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $actual$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_allocation atlas.work_allocations%ROWTYPE;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_weed atlas.weed_cards%ROWTYPE;
  v_mowing atlas.mowing_area_state%ROWTYPE;
  v_prior atlas.care_current_state%ROWTYPE;
  v_result atlas.work_execution_results%ROWTYPE;
  v_care uuid;
  v_observation uuid;
  v_acceptance uuid;
  v_satisfaction uuid;
  v_actor uuid;
  v_ledger_id uuid;
  v_source_key text;
  v_kind text := nullif(btrim(coalesce(p_actual_kind,'')),'');
  v_after text := nullif(btrim(coalesce(p_condition_after,'')),'');
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_before text;
  v_effect text;
  v_result_kind text;
  v_care_kind text;
  v_source_kind text;
  v_source_event text;
  v_touch jsonb;
  v_touch_index integer;
  v_renew_seconds integer;
  v_warning_at timestamptz;
  v_due_at timestamptz;
  v_failure_at timestamptz;
  v_tz text;
  v_boundary text;
  v_at timestamptz:=clock_timestamp();
BEGIN
  v_actor:=atlas.current_person_id_v1();
  IF auth.uid() IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
     OR p_action_id IS NULL OR v_kind IS NULL OR v_after IS NULL
     OR length(v_after)>120 OR length(coalesce(v_note,''))>1500
     OR (p_minutes IS NOT NULL AND (p_minutes<0 OR p_minutes>1440))
     OR (p_recheck_on IS NOT NULL AND p_recheck_on < (now()::date - 1))
  THEN
    RAISE EXCEPTION 'Exact signed physical Work Actual and valid observation required'
      USING ERRCODE='22023';
  END IF;
  v_source_key:='continuing-care-actual:'||p_work_item_id||':'||p_action_id;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-care-actual:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL
    OR v_work.source_object_type<>'rhythm_state'
    OR v_work.result_contract_key<>'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract' IS DISTINCT FROM 'continuing_original_work_v1'
  THEN
    RAISE EXCEPTION 'Original governed continuing Work is not available'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible'
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      AND a.assignee_canonical_person_id=v_actor
      AND a.state IN ('active','completed')
    ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
  IF v_allocation.id IS NULL
    OR coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
        !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  THEN
    RAISE EXCEPTION 'Real native-Ledger responsible Person required'
      USING ERRCODE='42501';
  END IF;
  v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
  IF NOT atlas.person_original_work_identity_disclosed_self_v1(
        v_work.organization_id,v_ledger_id,v_work.id,v_actor)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=v_work.id
        AND rel.organization_id=v_work.organization_id
        AND rel.ledger_id=v_ledger_id AND rel.attribution_state='active'
    )
  THEN
    RAISE EXCEPTION 'Original Work source and physical Subject are not disclosed'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=v_work.source_object_id
      AND s.organization_id=v_work.organization_id
      AND s.subject_kind='growing_object' FOR UPDATE;
  IF v_state.id IS NULL OR NOT EXISTS(
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on'
    ) THEN
    RAISE EXCEPTION 'Original Work is not linked to this exact physical Subject'
      USING ERRCODE='23514';
  END IF;
  -- Replays must survive a later rule retirement/physical state change;
  -- first confirm the same signed Person, original Subject and exact receipt.
  -- Authorize before replay, so a different Person cannot use the idempotency
  -- key to read someone else's Work Result.
  SELECT * INTO v_result FROM atlas.work_execution_results er
    WHERE er.organization_id=v_work.organization_id
      AND er.idempotency_key=v_source_key;
  IF v_result.id IS NOT NULL THEN
    IF v_result.work_item_id<>v_work.id
      OR v_result.reported_by_user_id IS DISTINCT FROM auth.uid()
      OR v_result.metadata->>'actualKind' IS DISTINCT FROM v_kind
      OR v_result.payload->>'conditionAfter' IS DISTINCT FROM v_after
      OR v_result.payload->>'note' IS DISTINCT FROM v_note
      OR v_result.payload->>'minutes' IS DISTINCT FROM p_minutes::text
      OR v_result.payload->>'recheckOn' IS DISTINCT FROM p_recheck_on::text
      OR NOT EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.organization_id=v_work.organization_id
          AND a.work_item_id=v_work.id AND a.execution_result_id=v_result.id
          AND a.decision='accepted' AND a.acceptance_kind='source_qualified_physical_actual'
      )
    THEN
      RAISE EXCEPTION 'Existing physical Actual does not match original signed action'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'contractVersion','continuing_care_actual_v1',
      'workItemId',v_work.id,'workResultId',v_result.id,'workState',v_work.work_state,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;


  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.organization_id=v_work.organization_id AND b.farm_id=v_state.farm_id
      AND b.active AND r.status='active';
  IF v_rule.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.growing_objects g
      WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id
    )
  THEN
    RAISE EXCEPTION 'Source cannot verify a current allowed care policy'
      USING ERRCODE='23514';
  END IF;

  -- No "generic done": source event type, effect, and postcondition are
  -- explicitly interpreted by the owning domain. Other domains plug in
  -- their own adapters, without changing the Work/Result lifecycle.
  IF v_state.rhythm_key='mowing' THEN
    SELECT * INTO v_mowing FROM atlas.mowing_area_state m
      WHERE m.object_id=v_state.subject_id
        AND m.organization_id=v_work.organization_id
        AND m.farm_id=v_state.farm_id FOR UPDATE;
    IF v_mowing.object_id IS NULL THEN
      RAISE EXCEPTION 'Mowing source state missing' USING ERRCODE='23514';
    END IF;
    v_source_kind:='mowing_result';v_source_event:=v_kind;
    CASE v_kind
      WHEN 'mowed_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        IF v_after<>'resting' THEN
          RAISE EXCEPTION 'Full mowing must report the resting condition' USING ERRCODE='22023';
        END IF;
      WHEN 'mowed_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        IF v_after<>'partial' THEN
          RAISE EXCEPTION 'Partial mowing must retain unfinished condition' USING ERRCODE='22023';
        END IF;
      WHEN 'acceptable_no_cut' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        IF v_after<>'acceptable' THEN
          RAISE EXCEPTION 'No-cut is an observed acceptable condition, not a mow' USING ERRCODE='22023';
        END IF;
      WHEN 'too_wet' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'too_wet' THEN RAISE EXCEPTION 'Wet-ground block must be observed' USING ERRCODE='22023'; END IF;
      WHEN 'equipment_or_area_problem' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'problem' THEN RAISE EXCEPTION 'Equipment/area problem must be observed' USING ERRCODE='22023'; END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified mowing Actual kind' USING ERRCODE='22023';
    END CASE;
  ELSE
    SELECT * INTO v_weed FROM atlas.weed_cards c
      WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      ORDER BY c.created_at,c.id LIMIT 1 FOR UPDATE;
    IF v_weed.id IS NULL THEN
      RAISE EXCEPTION 'Weed stewardship source state missing' USING ERRCODE='23514';
    END IF;
    CASE v_kind
      WHEN 'weeded_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        v_source_kind:='object';v_source_event:='weeded_reset';
        IF v_after<>'clear' THEN
          RAISE EXCEPTION 'Full weed restoration requires observed clear condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeded_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        v_source_kind:='object';v_source_event:='weeded';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy') THEN
          RAISE EXCEPTION 'Partial weed work must preserve residual condition' USING ERRCODE='22023';
        END IF;
      WHEN 'inspection_acceptable' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        v_source_kind:='field_log';v_source_event:='action:weed_inspection_acceptable';
        IF v_after NOT IN ('clear','row_readable') THEN
          RAISE EXCEPTION 'Acceptable weed inspection must preserve observed condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeding_blocked' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy','unknown') THEN
          RAISE EXCEPTION 'Blocked weeding must preserve real condition' USING ERRCODE='22023';
        END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified weed Actual kind' USING ERRCODE='22023';
    END CASE;
  END IF;

  -- Reject invented success when the configured Rhythm doesn't recognize
  -- the submitted domain event and its effect. Blockers are evidence only.
  IF v_effect IN ('full','partial','conditional') THEN
    SELECT t.value,(t.ordinality)::integer
      INTO v_touch,v_touch_index
    FROM pg_catalog.jsonb_array_elements(v_rule.qualifying_touches)
      WITH ORDINALITY AS t(value,ordinality)
    WHERE t.value->>'effect'=v_effect
      AND t.value->>'sourceKind'=v_source_kind
      AND (
        t.value->>'sourceEvent'=v_source_event
        OR t.value->'sourceEvents' ? v_source_event
      )
      AND (
        v_kind<>'weeded_partial'
        OR t.value#>>'{payloadContains,metadata,transition}'='partial'
      )
    ORDER BY t.ordinality LIMIT 1;
    IF v_touch IS NULL THEN
      RAISE EXCEPTION 'Result does not match original governed Rhythm rule'
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_work.work_state<>'open' OR v_allocation.state<>'active'
    OR v_state.state='paused' OR v_rule.status<>'active' THEN
    RAISE EXCEPTION 'Original Work or active Rhythm is no longer actionable'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_prior FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  v_before:=COALESCE(v_prior.condition_state,
     CASE WHEN v_state.rhythm_key='mowing' THEN v_mowing.status
          ELSE v_weed.current_condition END);
  IF v_prior.id IS NOT NULL AND v_prior.last_observed_at>v_at THEN
    RAISE EXCEPTION 'Newer physical observation must be reconciled first' USING ERRCODE='23514';
  END IF;
  -- No ordinary mowing is issued from a stale rhythm state. That condition
  -- gate lives at Work creation, not this legitimate worker reporting step.
  -- The worker is signing the *actual*, not a inferred result of the clock.
  INSERT INTO atlas.care_result_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    occurred_at,result_kind,condition_before,condition_after,
    minutes,minutes_known,actor_user_id,source_kind,source_key,note,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,
    'farm',v_state.farm_id,v_at,v_care_kind,v_before,v_after,
    p_minutes,(p_minutes IS NOT NULL),auth.uid(),'continuing_care_actual',
    v_source_key,v_note,
    jsonb_build_object('workItemId',v_work.id,'rhythmStateId',v_state.id,
      'physicalActualKind',v_kind,'sourceRuleId',v_rule.id,
      'actualReportedByPersonId',v_actor)
  ) RETURNING id INTO v_care;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    v_at,v_after,
    CASE WHEN v_effect='blocked' THEN 'hold'
      WHEN v_effect='partial' THEN 'intervene' ELSE 'observe' END,
    auth.uid(),'continuing_care_actual_observation',
    'continuing-care-observation:'||v_care::text,
    v_note,false,
    jsonb_build_object('careResultId',v_care,'workItemId',v_work.id)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state cs
    WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
      AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
      AND cs.subject_id=v_state.subject_id::text
      AND cs.condition_state=v_after AND cs.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Physical source readback failed'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,result_kind,result_contract_key,
    idempotency_key,payload,metadata,reported_at
  ) VALUES(
    v_work.organization_id,v_work.id,v_allocation.id,
    auth.uid(),v_result_kind,'continuing_care_actual_v1',
    v_source_key,
    jsonb_strip_nulls(jsonb_build_object(
      'careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'conditionAfter',v_after,'note',v_note,
      'minutes',p_minutes,'recheckOn',p_recheck_on)),
    jsonb_build_object('actualKind',v_kind,'rhythmStateId',v_state.id,
      'authenticatedReporterPersonId',v_actor,'nativeLedgerId',v_ledger_id),
    v_at
  ) RETURNING * INTO v_result;
  INSERT INTO atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence
  ) VALUES(
    v_work.organization_id,v_work.id,v_result.id,'accepted',
    'source_qualified_physical_actual','continuing_care_actual',
    jsonb_build_object('careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'sourceRuleId',v_rule.id,'actualReporter',v_actor)
  ) RETURNING id INTO v_acceptance;

  IF v_effect IN ('full','conditional') THEN
    v_renew_seconds:=CASE WHEN coalesce(v_touch->>'renewalIntervalSeconds','') ~ '^[1-9][0-9]*$'
      THEN (v_touch->>'renewalIntervalSeconds')::integer
      ELSE v_rule.validity_interval_seconds END;
    v_tz:=coalesce(nullif(v_rule.metadata->>'timezoneName',''),'America/Chicago');
    v_boundary:=coalesce(nullif(v_rule.metadata->>'boundaryMode',''),'exact_timestamp');
    v_warning_at:=atlas.rhythm_boundary_at_v1(v_at,
      greatest(0,v_renew_seconds-v_rule.warning_window_seconds),v_tz,v_boundary);
    v_due_at:=atlas.rhythm_boundary_at_v1(v_at,v_renew_seconds,v_tz,v_boundary);
    v_failure_at:=atlas.rhythm_boundary_at_v1(v_at,
      v_renew_seconds+v_rule.grace_window_seconds,v_tz,v_boundary);
    IF v_state.last_qualifying_satisfaction_id IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM atlas.rhythm_satisfactions old
        WHERE old.id=v_state.last_qualifying_satisfaction_id
          AND old.satisfied_at>v_at
      ) THEN
      RAISE EXCEPTION 'Existing newer satisfaction must not be reversed'
        USING ERRCODE='23514';
    END IF;
    INSERT INTO atlas.rhythm_satisfactions(
      organization_id,farm_id,rhythm_state_id,rhythm_binding_id,rhythm_rule_id,
      rhythm_key,subject_kind,subject_id,satisfaction_key,satisfaction_kind,
      satisfied_at,renewal_interval_seconds,source_kind,source_id,source_event,
      policy_match,evidence,created_by_user_id
    ) VALUES(
      v_state.organization_id,v_state.farm_id,v_state.id,v_state.rhythm_binding_id,
      v_rule.id,v_state.rhythm_key,v_state.subject_kind,v_state.subject_id,
      'continuing-actual:'||v_result.id::text,v_effect,v_at,
      CASE WHEN v_effect='conditional' THEN v_renew_seconds ELSE NULL END,
      'continuing_care_actual',v_care,v_kind,
      jsonb_build_object('touchIndex',v_touch_index,'touch',v_touch,
        'domainActualVerified',true),
      jsonb_build_object('workItemId',v_work.id,'careResultId',v_care,
        'workResultId',v_result.id),
      auth.uid()
    ) RETURNING id INTO v_satisfaction;
    UPDATE atlas.rhythm_state SET state='resting',
      last_qualifying_satisfaction_id=v_satisfaction,
      lease_started_at=v_at,warning_at=v_warning_at,due_at=v_due_at,
      failure_at=v_failure_at,recovery_started_at=NULL,
      last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'satisfactionId',v_satisfaction,
        'actualKind',v_kind),updated_at=now()
    WHERE id=v_state.id;
  ELSIF v_effect='partial' THEN
    -- One still-open original Work; partial progress does not manufacture
    -- another occurrence. The physical state and Actual remain durable.
    UPDATE atlas.rhythm_state SET state='recovering',
      recovery_started_at=v_at,last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'careResultId',v_care,'actualKind',v_kind),
      updated_at=now()
    WHERE id=v_state.id;
  END IF;

  -- Domain projections retain actual route/bed state; other domains provide
  -- their own projections without altering canonical Work/Result machinery.
  IF v_state.rhythm_key='mowing' THEN
    UPDATE atlas.mowing_area_state SET
      status=v_after,last_observed_at=v_at,
      last_mowed_at=CASE WHEN v_kind='mowed_full' THEN v_at ELSE last_mowed_at END,
      next_check_date=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_check_date END,
      -- source_event_id references legacy mowing_events, NOT care_result_events.
      -- Preserve legacy source_event_id; the canonical Actual is in care history.
      note=v_note,metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
        updated_at=now()
    WHERE object_id=v_state.subject_id AND organization_id=v_work.organization_id;
  ELSIF v_effect IN ('full','partial','conditional') THEN
    UPDATE atlas.weed_cards SET
      current_condition=v_after,
      next_review_on=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_review_on END,
      metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
      last_session_at=v_at,updated_at=now()
    WHERE id=v_weed.id;
  END IF;

  IF v_result_kind='completed' THEN
    UPDATE atlas.work_items SET work_state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_work.id AND work_state='open';
    UPDATE atlas.work_allocations SET state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_allocation.id AND state='active';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','continuing_care_actual_v1',
    'idempotent',false,'workItemId',v_work.id,
    'workResultId',v_result.id,'careResultId',v_care,
    'careObservationId',v_observation,'acceptanceId',v_acceptance,
    'rhythmSatisfactionId',v_satisfaction,
    'workState',CASE WHEN v_result_kind='completed' THEN 'completed' ELSE 'open' END,
    'sourceConditionAfter',v_after,'sourceResultKind',v_care_kind,
    'nextEligibleAt',v_due_at,
    'noNewWorkCreated',true,'noClockAdmission',true);
END;
$actual$;

-- PRE-RELEASE HOLD. Do not grant a domain reporter to authenticated until
-- real native-Person signed positive/negative clone tests + source disclosure
-- coverage pass. Explicitly deny unsafe direct execution for now.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE SECTION: 04_care_actual_source_guards.sql
-- DRAFT; must be included AFTER 02_farm_care_actual_adapter.sql.
-- This is a SOURCE EVIDENCE GUARD for one domain adapter, not a new global
-- Work completion regime. Other domains retain their own Result policies.
CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_actual_result_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF NEW.result_contract_key IS DISTINCT FROM 'continuing_care_actual_v1'
  THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NEW.organization_id IS NULL
    OR NEW.household_id IS NOT NULL
    OR NEW.reported_by_user_id IS DISTINCT FROM auth.uid()
    OR NEW.responsible_allocation_id IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM atlas.work_items w
      JOIN atlas.rhythm_state s ON s.id=w.source_object_id
        AND s.organization_id=w.organization_id
      JOIN atlas.work_allocations a ON a.id=NEW.responsible_allocation_id
        AND a.organization_id=w.organization_id
        AND a.work_item_id=w.id
      JOIN atlas.care_result_events c
        ON c.id=atlas.rhythm_safe_uuid_v1(NEW.payload->>'careResultId')
        AND c.scope_kind='farm' AND c.scope_id=s.farm_id
        AND c.subject_domain='farm' AND c.subject_kind='growing_object'
        AND c.subject_id=s.subject_id::text
        AND c.actor_user_id=NEW.reported_by_user_id
        AND c.source_kind='continuing_care_actual'
      WHERE w.id=NEW.work_item_id
        AND w.organization_id=NEW.organization_id
        AND w.source_object_type='rhythm_state'
        AND w.result_contract_key=NEW.result_contract_key
        AND w.work_state='open'
        AND a.allocation_role='responsible' AND a.state='active'
        AND a.assignee_canonical_person_id=atlas.current_person_id_v1()
        AND c.metadata->>'workItemId'=w.id::text
        AND c.metadata->>'rhythmStateId'=s.id::text
        AND c.metadata->>'physicalActualKind'=NEW.payload->>'actualKind'
        AND c.condition_after=NEW.payload->>'conditionAfter'
        AND (
          (NEW.result_kind='completed'
            AND c.result_kind IN ('recovered','condition_differed'))
          OR (NEW.result_kind='partial'
            AND c.result_kind='improved_more_remains')
          OR (NEW.result_kind='blocked'
            AND c.result_kind='blocked')
        )
    )
  THEN
    RAISE EXCEPTION 'Canonical continuing Work Result requires its accepted first-party Actual'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_actual_result_v1
BEFORE INSERT ON atlas.work_execution_results
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_actual_result_v1();

CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_actual_acceptance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM atlas.work_execution_results r
    WHERE r.id=NEW.execution_result_id
      AND r.organization_id=NEW.organization_id
      AND r.work_item_id=NEW.work_item_id
      AND r.result_contract_key='continuing_care_actual_v1'
  ) THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NEW.household_id IS NOT NULL
     OR NEW.decision<>'accepted'
     OR NEW.acceptance_kind<>'source_qualified_physical_actual'
     OR NEW.accepted_by_domain<>'continuing_care_actual'
     OR NOT EXISTS (
       SELECT 1 FROM atlas.work_execution_results r
       JOIN atlas.care_result_events c
         ON c.id=atlas.rhythm_safe_uuid_v1(r.payload->>'careResultId')
       WHERE r.id=NEW.execution_result_id
         AND r.organization_id=NEW.organization_id
         AND r.work_item_id=NEW.work_item_id
         AND r.reported_by_user_id=auth.uid()
         AND c.actor_user_id=r.reported_by_user_id
         AND c.source_kind='continuing_care_actual'
         AND c.metadata->>'workItemId'=NEW.work_item_id::text
         AND NEW.evidence->>'careResultId'=c.id::text
     )
  THEN
    RAISE EXCEPTION 'Continuing Work acceptance requires exact authenticated physical evidence'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_actual_acceptance_v1
BEFORE INSERT ON atlas.work_result_acceptances
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_actual_acceptance_v1();

CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_work_completion_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF OLD.work_state IS NOT DISTINCT FROM NEW.work_state
     OR NEW.work_state<>'completed'
     OR NEW.result_contract_key IS DISTINCT FROM 'continuing_care_actual_v1'
  THEN RETURN NEW; END IF;

  IF NEW.organization_id IS NULL OR NEW.household_id IS NOT NULL
     OR NOT EXISTS(
       SELECT 1
       FROM atlas.work_execution_results r
       JOIN atlas.work_result_acceptances a ON a.execution_result_id=r.id
         AND a.work_item_id=r.work_item_id AND a.organization_id=r.organization_id
         AND a.decision='accepted'
         AND a.acceptance_kind='source_qualified_physical_actual'
       JOIN atlas.care_result_events c ON
         c.id=atlas.rhythm_safe_uuid_v1(r.payload->>'careResultId')
         AND c.actor_user_id=r.reported_by_user_id
         AND c.source_kind='continuing_care_actual'
       JOIN atlas.rhythm_satisfactions s ON s.source_id=c.id
         AND s.source_kind='continuing_care_actual'
         AND s.organization_id=NEW.organization_id
         AND s.evidence->>'workItemId'=NEW.id::text
         AND s.satisfaction_kind IN ('full','conditional')
       WHERE r.work_item_id=NEW.id AND r.organization_id=NEW.organization_id
         AND r.result_contract_key=NEW.result_contract_key
         AND r.result_kind='completed'
         AND c.metadata->>'workItemId'=NEW.id::text
     )
  THEN
    RAISE EXCEPTION 'Original continuing Work cannot close without its source-qualified satisfaction'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_work_completion_v1
BEFORE UPDATE OF work_state ON atlas.work_items
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_work_completion_v1();

-- No privilege change. Trigger functions do not need exposed client EXECUTE.
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_actual_result_v1()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_actual_acceptance_v1()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_work_completion_v1()
FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE SECTION: 05_governed_observed_need_work_writer.sql
-- DRAFT: source-observed Need → one canonical original Work → accepted
-- connected-Person responsibility → an EXPLICIT service date in existing Today.
-- This is a thin farm DOMAIN ADAPTER to universal Work, NOT a new task engine.
-- No silent assignment, inferred physical need, or auto-generated backlog.
-- Requires candidate.sql and 02_farm_care_actual_adapter.sql first.
CREATE OR REPLACE FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_rhythm_state_id uuid,
  p_scope_id uuid,
  p_observed_condition text,
  p_observation_note text,
  p_observed_at timestamptz,
  p_service_date date,
  p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $writer$
DECLARE
  v_owner uuid;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_object atlas.growing_objects%ROWTYPE;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_current atlas.care_current_state%ROWTYPE;
  v_existing atlas.work_items%ROWTYPE;
  v_work uuid;
  v_source jsonb;
  v_assignment jsonb;
  v_allocation uuid;
  v_plan uuid;
  v_observation uuid;
  v_title text;
  v_instructions text;
  v_condition text:=nullif(btrim(coalesce(p_observed_condition,'')),'');
  v_note text:=nullif(btrim(coalesce(p_observation_note,'')),'');
  v_key text;
  v_today date;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
     OR p_rhythm_state_id IS NULL OR p_scope_id IS NULL
     OR p_action_id IS NULL OR p_observed_at IS NULL
     OR p_service_date IS NULL OR v_condition IS NULL
     OR v_note IS NULL OR length(v_note)<10 OR length(v_note)>1500
     OR p_observed_at<now()-interval '3 days'
     OR p_observed_at>now()+interval '5 minutes' THEN
    RAISE EXCEPTION 'Exact fresh source observation and deliberate Person-day decision required'
      USING ERRCODE='22023';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
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
  IF p_service_date<v_today-1 OR p_service_date>v_today+14 THEN
    RAISE EXCEPTION 'Person-day placement must be an explicit bounded civil date'
      USING ERRCODE='22023';
  END IF;
  IF v_rule.id IS NULL OR v_object.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms f WHERE f.id=v_state.farm_id
      AND f.organization_id=p_organization_id AND f.status='active'
    ) THEN
    RAISE EXCEPTION 'Care Need is not sourced from an active governed place'
      USING ERRCODE='23514';
  END IF;

  IF v_state.rhythm_key='mowing' THEN
    IF v_condition NOT IN ('needs_inspection','ready_for_mowing','overgrown')
      OR NOT EXISTS(
        SELECT 1 FROM atlas.mowing_area_state m
        WHERE m.object_id=v_state.subject_id
          AND m.farm_id=v_state.farm_id
          AND m.organization_id=p_organization_id AND m.status<>'closed'
      ) THEN
      RAISE EXCEPTION 'Mowing needs a real observed route and permitted condition'
        USING ERRCODE='23514';
    END IF;
    v_title:='Inspect and mow if warranted — '||v_object.label;
    v_instructions:='Inspect the route and ground safety. Mow only if appropriate. Report the real outcome: full, partial, acceptable no-cut, too wet, or equipment/area problem.';
  ELSE
    IF v_condition NOT IN ('needs_inspection','row_readable',
         'medium_pressure','heavy')
      OR NOT EXISTS(
        SELECT 1 FROM atlas.weed_cards c
        WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      )
      OR NOT atlas.care_strategy_allows_ordinary_weeding_v1(
        v_state.subject_id,p_observed_at::date) THEN
      RAISE EXCEPTION 'Weeding needs an observed eligible care strategy'
        USING ERRCODE='23514';
    END IF;
    v_title:='Inspect and weed if warranted — '||v_object.label;
    v_instructions:='Inspect current weed condition and care strategy. Weed only if warranted. Report the real outcome: full, partial, acceptable inspection, or blocked.';
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
      OR v_existing.metadata->>'sourceObservedCondition' IS DISTINCT FROM v_condition
      OR v_existing.metadata->>'sourceObservedAt' IS DISTINCT FROM p_observed_at::text
      OR v_existing.metadata->>'sourceObservationNoteDigest' IS DISTINCT FROM md5(v_note)
    THEN
      RAISE EXCEPTION 'Source action replay cannot change original Person, date or observed condition'
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
      'contractVersion','observed_continuing_care_work_v1',
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
      'contractVersion','observed_continuing_care_work_v1',
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

  SELECT * INTO v_current FROM atlas.care_current_state c
  WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
    AND c.subject_domain='farm' AND c.subject_kind='growing_object'
    AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  IF v_current.id IS NOT NULL AND v_current.last_observed_at>p_observed_at THEN
    RAISE EXCEPTION 'Newer physical state cannot be overwritten by older evidence'
      USING ERRCODE='23514';
  END IF;

  v_key:='governed-continuing-need-observation:'||p_action_id::text;
  IF EXISTS(SELECT 1 FROM atlas.care_observation_events e
    WHERE e.source_key=v_key) THEN
    RAISE EXCEPTION 'Source action already belongs to an observation; reconcile first'
      USING ERRCODE='23505';
  END IF;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    p_observed_at,v_condition,'reassess',auth.uid(),
    'governed_continuing_need_observation',v_key,v_note,false,
    jsonb_build_object('rhythmStateId',v_state.id,
      'observingGovernorPersonId',v_owner,
      'chosenLedgerId',p_ledger_id,'notClockInferred',true)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text
      AND c.condition_state=v_condition AND c.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Source observation did not become current physical state'
      USING ERRCODE='23514';
  END IF;

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
      'sourceObservedCondition',v_condition,
      'sourceObservedAt',p_observed_at::text,
      'sourceObservationNoteDigest',md5(v_note)),
    updated_at=now()
  WHERE id=v_work AND organization_id=p_organization_id;

  INSERT INTO atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id
  ) VALUES(
    p_organization_id,v_work,p_ledger_id,'owner_attested',
    'atlas.care_observation_events:'||v_observation::text,
    'Governor explicitly chose this Ledger for Work following a fresh signed physical observation.',
    v_owner
  );

  -- Reuse the governed native Person allocation, not an employee seat.
  v_assignment:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
    v_work,p_scope_id,
    'Fresh original physical Need explicitly given under an accepted native connected-Person scope.');
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
    'Governor explicitly chose service date for real observed continuing Need.',
    jsonb_build_object('source','observed_continuing_care_work_v1',
      'ownerPersonId',v_owner,'sourceObservationId',v_observation,
      'connectedPersonDay',true,'principalClockAdmitted',false)
  ) RETURNING id INTO v_plan;
  INSERT INTO atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_plan,'planned',
    p_service_date,p_service_date,NULL,
    'Governor selected actual service date from observed Need',
    jsonb_build_object('sourceObservationId',v_observation,
      'governorPersonId',v_owner,'notLegacyWorkerDay',true)
  );

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','observed_continuing_care_work_v1',
    'workItemId',v_work,'rhythmStateId',v_state.id,
    'observationId',v_observation,
    'responsiblePersonId',v_scope.worker_person_id,
    'allocationId',v_allocation,'planId',v_plan,
    'serviceDate',p_service_date,
    'newOriginalWorkCreated',true,
    'sourceObservationSigned',true,
    'clockAdmitted',false,'noNextWorkPrecreated',true);
END;
$writer$;

-- Denied until protected-clone signed authority/privacy tests pass. This
-- function is a source-governor operation, not a generic task creation RPC.
REVOKE ALL ON FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid
) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE SECTION: 07_legacy_rhythm_no_duplicate_task_cutover.sql
-- Exact-source compatibility gate for the currently scheduled legacy clock.
-- This does NOT change unrelated rhythms or erase old task/history records.
-- Source snapshot: atlas.ensure_rhythm_task_v1 md5
-- d195ec2ccf9b36858cba9c5bfbfb2724 on 2026-10-28.
-- Verify this fingerprint before replacing in protected clone and prior to
-- any production release; direct legacy helper entrypoints are separately
-- covered by the insert admission guards below.
CREATE OR REPLACE FUNCTION atlas.continuing_rhythm_original_work_has_custody_v1(
  p_state_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $body$
  SELECT COALESCE(p_state_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM atlas.rhythm_state s
    JOIN atlas.work_items w ON w.organization_id=s.organization_id
      AND w.source_object_type='rhythm_state'
      AND w.source_object_id=s.id
      AND w.metadata->>'sourceContract'='continuing_original_work_v1'
    WHERE s.id=p_state_id
  ),false);
$body$;
REVOKE ALL ON FUNCTION atlas.continuing_rhythm_original_work_has_custody_v1(
  uuid
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION atlas.ensure_rhythm_task_v1(
  p_state_id uuid,p_target_state text,p_boundary_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','atlas'
AS $body$
DECLARE
  v_state atlas.rhythm_state%ROWTYPE;
BEGIN
  SELECT state.* INTO v_state
  FROM atlas.rhythm_state state WHERE state.id=p_state_id;
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Rhythm state not found.' USING ERRCODE='P0002';
  END IF;

  -- The FIRST canonical original Work is the exact Need's cutover.
  -- Retain the old rhythm clock but suppress future legacy task births from
  -- this scheduled route, including later cycles; only separately observed
  -- condition + authorization may create a new original Work.
  IF atlas.continuing_rhythm_original_work_has_custody_v1(p_state_id) THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','canonical_original_work_has_custody',
      'legacyTaskCreated',false);
  END IF;

  IF v_state.rhythm_key='weed_stewardship'
    AND v_state.subject_kind='growing_object'
    AND NOT atlas.weed_card_allows_ordinary_work_v1(
      v_state.subject_id,
      (coalesce(p_boundary_at,now()) at time zone 'America/Chicago')::date
    )
  THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','physical_weed_need_not_present',
      'objectId',v_state.subject_id,
      'clockState',p_target_state);
  END IF;

  RETURN atlas.ensure_rhythm_task_without_physical_gate_v1(
    p_state_id,p_target_state,p_boundary_at);
END;
$body$;

-- A source-owned DEFENSE-IN-DEPTH gate covers *direct* legacy task and
-- planned-occurrence insert paths not routed through ensure_rhythm_task_v1.
-- This intentionally rejects an attempted duplicate rather than silently
-- creating ambiguous history. Legacy direct writer callers may need to
-- handle the explicit cutover exception; release tests must prove no
-- uncontrolled tick retry/error churn before this source can be deployed.
CREATE OR REPLACE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $body$
DECLARE
  v_state uuid;
BEGIN
  IF TG_TABLE_NAME='planned_work_occurrences' THEN
    IF NEW.source_kind IS DISTINCT FROM 'rhythm_state' THEN RETURN NEW; END IF;
    v_state:=NEW.source_id;
  ELSIF TG_TABLE_NAME='tasks' THEN
    -- Live legacy carriers often have generated_from NULL and use only
    -- metadata.rhythm_state_id plus an occurrence; do NOT rely on the
    -- generated_from value or an unrelated generated_from_id.
    v_state:=atlas.rhythm_safe_uuid_v1(
      NEW.metadata->>'rhythm_state_id');
    IF v_state IS NULL AND NEW.planned_occurrence_id IS NOT NULL THEN
      SELECT o.source_id INTO v_state
      FROM atlas.planned_work_occurrences o
      WHERE o.id=NEW.planned_occurrence_id
        AND o.source_kind='rhythm_state';
    END IF;
    IF v_state IS NULL AND NEW.generated_from='rhythm_clock' THEN
      SELECT s.id INTO v_state FROM atlas.rhythm_state s
      WHERE s.id=NEW.generated_from_id;
    END IF;
  ELSE RETURN NEW;
  END IF;
  IF v_state IS NOT NULL
     AND atlas.continuing_rhythm_original_work_has_custody_v1(v_state) THEN
    RAISE EXCEPTION 'Legacy rhythm task carrier cannot be created after native original Work custody'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;

CREATE TRIGGER z_guard_continuing_original_rhythm_old_task_v1
BEFORE INSERT ON atlas.tasks FOR EACH ROW
EXECUTE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1();

CREATE TRIGGER z_guard_continuing_original_rhythm_old_occurrence_v1
BEFORE INSERT ON atlas.planned_work_occurrences FOR EACH ROW
EXECUTE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1();

REVOKE ALL ON FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1()
FROM PUBLIC, anon, authenticated, service_role;
-- SOURCE SECTION: 09_rhythm_state_raw_worker_disclosure_cutover.sql
-- DRAFT ONLY: source-enforced raw Rhythm state disclosure cutover.
-- Read-only production role/claims probe 2026-10-28: a current legacy
-- authenticated farm_hand had SELECT access to 181 assigned_worker rhythms,
-- including 102 growing_objects with ZERO current exact identity/condition
-- grants. Scoped Work Subject APIs must be used for selective disclosure.
-- Do not make RLS on the raw table a parallel, unrestricted farm reader.
--
-- This guard keeps existing owner, management, project and system paths.
-- It removes only the legacy worker-credential shortcut and fail-closes
-- unknown visibility values instead of trusting broad farm membership.
-- Historical assignments and rows are preserved (no UPDATE/DELETE).
-- This change MUST be validated with signed genuine Auth/REST + installed
-- schema clone before deployment; it may narrow historic farm-hand reads.
--
-- Fingerprint prevents replacing a concurrently revised source authority.
DO $drift$
DECLARE v_existing text;
BEGIN
 IF to_regprocedure('atlas.can_read_rhythm_state_v1(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Existing raw Rhythm state disclosure function missing'
     USING ERRCODE='23514';
 END IF;
 SELECT md5(pg_catalog.pg_get_functiondef(
   'atlas.can_read_rhythm_state_v1(uuid)'::regprocedure))
 INTO v_existing;
 IF v_existing <> '2b7d7019230d0a9bf172e5e1b3224db3' THEN
   RAISE EXCEPTION 'Raw Rhythm read source changed; reconcile before cutover'
     USING ERRCODE='23514';
 END IF;
END;
$drift$;

CREATE OR REPLACE FUNCTION atlas.can_read_rhythm_state_v1(p_state_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas'
AS $gate$
 SELECT coalesce((
   SELECT CASE s.visibility_scope
     WHEN 'owner' THEN atlas.is_farm_owner(s.farm_id)
     WHEN 'management' THEN atlas.is_farm_manager_or_owner(s.farm_id)
     -- Raw Rhythm state contains full metadata, timings and source details.
     -- Neither historic farm_hand status nor assigned_user_id alone
     -- proves current native Ledger/Subject disclosure for the exact Person.
     -- Connected Persons use bounded source-disclosed original Work readers.
     WHEN 'assigned_worker' THEN atlas.is_farm_manager_or_owner(s.farm_id)
     WHEN 'project_shared' THEN s.subject_kind='project'
       AND atlas.can_read_project(s.subject_id)
     WHEN 'system_internal' THEN atlas.is_farm_owner(s.farm_id)
     -- Unknown/new visibility must not silently restore old farm membership.
     ELSE atlas.is_farm_manager_or_owner(s.farm_id)
   END
   FROM atlas.rhythm_state s WHERE s.id=p_state_id
 ),false);
$gate$;

-- Do not change EXECUTE grants or RLS policies here: the existing
-- atlas.rhythm_state SELECT policy calls this same source function.
-- Do not create an employee seat, blanket Subject grant, or separate reader.


-- EXTENSION SECTION: 10_owner_standing_visit_source_writer.sql
-- DRAFT: owner's standing-visit source adapter to ONE canonical original Work.
-- The signed owner mandate establishes attention, NOT a fabricated physical
-- observation. Field Actual remains a separately signed, typed result.
-- No other task system. Held for protected-clone and signed tests.
CREATE OR REPLACE FUNCTION atlas.owner_establish_standing_continuing_care_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_rhythm_state_id uuid,
  p_scope_id uuid,
  p_visit_reason text,
  p_service_date date,
  p_campaign_end_date date,
  p_action_id uuid
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
     OR p_campaign_end_date<p_service_date OR p_campaign_end_date>p_service_date+120
     OR v_reason IS NULL OR length(v_reason)<10 OR length(v_reason)>1500 THEN
    RAISE EXCEPTION 'Exact signed owner standing visit and workday required'
      USING ERRCODE='22023';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
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
    'newOriginalWorkCreated',true,
    'ownerStandingVisitApproved',true,
    'clockAdmitted',false,'noNextWorkPrecreated',true);
END;
$writer$;

-- Denied until protected-clone signed authority/privacy tests pass. This
-- function is a source-governor operation, not a generic task creation RPC.
REVOKE ALL ON FUNCTION atlas.owner_establish_standing_continuing_care_work_self_api_v1(
  uuid,uuid,uuid,uuid,text,date,date,uuid
) FROM PUBLIC,anon,authenticated,service_role;

-- EXTENSION SECTION: 11_owner_standing_candidate_preview.sql
-- SOURCE-ONLY: owner preview of real governed rhythm candidates.
-- No tasks, decisions, observations or assignments are inserted.
-- The same source can be consumed by a reviewed, capacity-bounded successor
-- writer; time alone does NOT prove physical weeds or mowing safety.
CREATE OR REPLACE FUNCTION atlas.owner_preview_standing_care_candidates_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,p_farm_id uuid,
 p_rhythm_key text,p_on_date date,p_campaign_id uuid DEFAULT NULL,
 p_limit integer DEFAULT 25
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $preview$
DECLARE
  v_owner uuid;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_rows jsonb;
  v_total integer;
  v_withheld integer;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_scope_id IS NULL OR p_farm_id IS NULL OR p_on_date IS NULL
    OR p_rhythm_key IS NULL OR p_rhythm_key NOT IN ('weed_stewardship','mowing')
    OR p_limit NOT BETWEEN 1 AND 50
  THEN RAISE EXCEPTION 'Signed exact rhythm preview requested'
    USING ERRCODE='22023'; END IF;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id AND ledger_id=p_ledger_id
      AND organization_id=p_organization_id;
  IF v_scope.id IS NULL OR v_scope.scope_state<>'active'
    OR v_scope.worker_membership_id IS NOT NULL
    OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
    OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR v_scope.coverage_mode<>'ledger_all_work'
    OR v_scope.accepted_at IS NULL
    OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
    OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id)
    OR NOT EXISTS(SELECT 1 FROM atlas.farms f
      WHERE f.id=p_farm_id AND f.organization_id=p_organization_id
        AND f.status='active')
  THEN RAISE EXCEPTION 'No governed active Person/Farm scope for preview'
    USING ERRCODE='42501'; END IF;

  WITH candidates AS MATERIALIZED (
    SELECT s.id rhythm_state_id,s.subject_id,g.label subject_label,
      r.id rule_id,r.rule_key,r.validity_interval_seconds,
      s.due_at,
      coalesce(
        extract(epoch FROM ((p_on_date::timestamp AT TIME ZONE
          coalesce(nullif(r.metadata->>'timezoneName',''),
            nullif(f.metadata->>'timezoneName',''),'UTC'))-s.due_at))
          /greatest(r.validity_interval_seconds,86400),
        0
      ) overdue_cycles,
      atlas.has_current_subject_disclosure_v1(p_ledger_id,
        v_scope.worker_person_id,'spatial','growing_object',
        s.subject_id,'identity') identity_disclosed,
      atlas.has_current_subject_disclosure_v1(p_ledger_id,
        v_scope.worker_person_id,'spatial','growing_object',
        s.subject_id,'condition') condition_disclosed
    FROM atlas.rhythm_state s
    JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
      AND b.organization_id=p_organization_id AND b.farm_id=p_farm_id
      AND b.active
    JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
      AND r.id=s.rhythm_rule_id AND r.status='active'
    JOIN atlas.growing_objects g ON g.id=s.subject_id
      AND g.farm_id=p_farm_id
    JOIN atlas.farms f ON f.id=s.farm_id
      AND f.organization_id=p_organization_id AND f.status='active'
    WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
      AND s.subject_kind='growing_object'
      AND s.rhythm_key=p_rhythm_key AND s.state<>'paused'
      AND (r.validity_interval_seconds IS NOT NULL
        AND r.validity_interval_seconds>0)
      AND NOT EXISTS (
        SELECT 1 FROM atlas.work_items w
        WHERE w.organization_id=p_organization_id
          AND w.source_object_type='rhythm_state'
          AND w.source_object_id=s.id AND w.work_state='open'
      )
      AND NOT EXISTS (
        SELECT 1 FROM atlas.tasks t
        LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
        WHERE t.farm_id=p_farm_id AND t.status IN ('open','blocked')
          AND (t.metadata->>'rhythm_state_id'=s.id::text
            OR (o.source_kind='rhythm_state' AND o.source_id=s.id))
      )
      AND (p_campaign_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM atlas.work_items served
        WHERE served.organization_id=p_organization_id
          AND served.metadata->>'sourceStandingCampaignId'=p_campaign_id::text
          AND served.metadata->>'sourceSubjectId'=s.subject_id::text
          AND served.work_state IN ('completed','open')
      ))
  ), ranked AS (
    SELECT c.*,row_number() OVER(
      ORDER BY c.overdue_cycles DESC,c.validity_interval_seconds ASC,
        c.subject_label,c.rhythm_state_id
    ) position FROM candidates c
  )
  SELECT count(*)::integer,
    count(*) FILTER (WHERE NOT identity_disclosed OR NOT condition_disclosed)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'rhythmStateId',rhythm_state_id,'subjectId',subject_id,
      'subjectLabel',subject_label,'sourceRuleId',rule_id,'ruleKey',rule_key,
      'normalIntervalSeconds',validity_interval_seconds,
      'rhythmDueAt',due_at,
      'priorityPosition',position,
      'releasableToConnectedPerson',identity_disclosed AND condition_disclosed,
      'requiresSourceDisclosure',NOT(identity_disclosed AND condition_disclosed),
      'eligibilityBasis','owner_standing_visit_not_physical_condition'
    ) ORDER BY position) FILTER (WHERE position<=p_limit),'[]'::jsonb)
  INTO v_total,v_withheld,v_rows FROM ranked;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','standing_care_candidate_preview_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'farmId',p_farm_id,'rhythmKey',p_rhythm_key,
    'workerPersonId',v_scope.worker_person_id,'viewDate',p_on_date,
    'candidateCount',v_total,'missingDisclosureCount',v_withheld,
    'candidates',v_rows,'newWorkCreated',false,
    'doesNotAssertPhysicalNeed',true);
END;
$preview$;

REVOKE ALL ON FUNCTION atlas.owner_preview_standing_care_candidates_self_api_v1(
 uuid,uuid,uuid,uuid,text,date,uuid,integer
) FROM PUBLIC,anon,authenticated,service_role;

-- EXTENSION SECTION: 13_owner_standing_collection_disclosure.sql
-- DRAFT / SOURCE ONLY: rooted owner can authorize the exact currently
-- bound real Subject collection for an accepted native connected Person.
-- Existing explicit per-Subject WITHHOLD decisions are never silently
-- overridden. No permission, Work or task exists unless this signed call
-- is separately approved and released.
CREATE OR REPLACE FUNCTION atlas.governor_grant_standing_care_collection_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_scope_id uuid,
  p_farm_id uuid,p_rhythm_key text,p_action_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $bulk$
DECLARE
  v_owner uuid;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_row record;
  v_class text;
  v_current text;
  v_subject_count integer;
  v_granted integer:=0;
  v_existing integer:=0;
  v_withheld integer:=0;
  v_result jsonb;
  v_action uuid;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_scope_id IS NULL OR p_farm_id IS NULL OR p_action_id IS NULL
    OR p_rhythm_key NOT IN ('weed_stewardship','mowing')
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 900 THEN
    RAISE EXCEPTION 'Exact signed collection and reason required' USING ERRCODE='22023';
  END IF;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  SELECT * INTO v_scope
  FROM atlas.company_work_standing_assignment_scopes s
  WHERE s.id=p_scope_id AND s.organization_id=p_organization_id
    AND s.ledger_id=p_ledger_id
    AND s.scope_state='active'
    AND s.worker_membership_id IS NULL
    AND s.proposed_by_person_id=v_owner
    AND s.accepted_by_person_id=s.worker_person_id
    AND s.accepted_at IS NOT NULL
    AND s.coverage_mode='ledger_all_work'
    AND (s.valid_until IS NULL OR s.valid_until>now());
  IF v_scope.id IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_scope.worker_person_id)
    OR NOT EXISTS(SELECT 1 FROM atlas.farms f WHERE f.id=p_farm_id
      AND f.organization_id=p_organization_id AND f.status='active')
  THEN RAISE EXCEPTION 'Current accepted native Person and farm not proven'
    USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.standing-collection-disclosure:'||p_ledger_id::text||':'||
      p_scope_id::text||':'||p_farm_id::text||':'||p_rhythm_key,0));
  SELECT count(*)::integer INTO v_subject_count
  FROM atlas.rhythm_state s
  JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id AND b.active
    AND b.organization_id=p_organization_id AND b.farm_id=p_farm_id
  JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
    AND r.id=s.rhythm_rule_id AND r.status='active'
  JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=p_farm_id
  WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
    AND s.rhythm_key=p_rhythm_key AND s.subject_kind='growing_object'
    AND s.state<>'paused';
  IF v_subject_count<1 OR v_subject_count>150 THEN
    RAISE EXCEPTION 'Collection size outside bounded owner approval'
      USING ERRCODE='23514';
  END IF;
  FOR v_row IN
    SELECT DISTINCT s.subject_id
    FROM atlas.rhythm_state s
    JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id AND b.active
      AND b.organization_id=p_organization_id AND b.farm_id=p_farm_id
    JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
      AND r.id=s.rhythm_rule_id AND r.status='active'
    JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=p_farm_id
    WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
      AND s.rhythm_key=p_rhythm_key AND s.subject_kind='growing_object'
      AND s.state<>'paused'
    ORDER BY s.subject_id
  LOOP
    FOREACH v_class IN ARRAY ARRAY['identity','condition']::text[] LOOP
      -- The same lock used by the exact single-Subject governor writer
      -- prevents a concurrent WITHHOLD being silently overridden.
      PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'atlas.subject_disclosure:'||p_ledger_id::text||':'||
        v_scope.worker_person_id::text||':spatial:growing_object:'||
        v_row.subject_id::text||':'||v_class,0));
      v_current:=NULL;
      SELECT d.decision_kind INTO v_current
      FROM atlas.subject_disclosure_decision_events_v1 d
      WHERE d.ledger_id=p_ledger_id
        AND d.target_person_id=v_scope.worker_person_id
        AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
        AND d.subject_id=v_row.subject_id AND d.disclosure_class=v_class
      ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1;
      IF v_current='withhold' THEN
        v_withheld:=v_withheld+1;CONTINUE;
      ELSIF v_current='grant' THEN
        v_existing:=v_existing+1;CONTINUE;
      END IF;
      v_action:=pg_catalog.md5(p_action_id::text||':'||
        v_row.subject_id::text||':'||v_class)::uuid;
      v_result:=atlas.governor_set_subject_disclosure_self_api_v1(
        p_organization_id,p_ledger_id,v_scope.worker_person_id,
        'spatial','growing_object',v_row.subject_id,v_class,'grant',
        v_action,'Owner explicitly approved this bounded routine care collection: '||v_reason);
      IF v_result->>'ok' IS DISTINCT FROM 'true'
        OR v_result->>'currentlyGranted' IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'Exact Subject disclosure receipt not verified'
          USING ERRCODE='23514';
      END IF;
      v_granted:=v_granted+1;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','standing_collection_disclosure_v1',
    'farmId',p_farm_id,'rhythmKey',p_rhythm_key,'scopeId',p_scope_id,
    'workerPersonId',v_scope.worker_person_id,
    'subjectCount',v_subject_count,'newFieldGrants',v_granted,
    'existingFieldGrants',v_existing,'retainedWithholdFields',v_withheld,
    'sourceActionId',p_action_id,'workCreated',false);
END;
$bulk$;

-- Grant only AFTER exact signed governor, worker, unrelated, revoked and
-- existing-withhold tests. Never execute as SQL admin on the user's behalf.
REVOKE ALL ON FUNCTION atlas.governor_grant_standing_care_collection_self_api_v1(
 uuid,uuid,uuid,uuid,text,uuid,text
) FROM PUBLIC,anon,authenticated,service_role;

-- EXTENSION SECTION: 14_owner_standing_successor_authority.sql
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

-- EXTENSION SECTION: 15_native_person_successor_allocation_guard.sql
-- Source-locked, narrow extension; NO blanket assignment bypass.
-- Only after 14_owner_standing_successor_authority.sql.
DO $source_guard$
BEGIN
 IF (
   SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
   FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas'
     AND p.proname='guard_work_allocation_responsibility_establishment_v2'
 ) IS DISTINCT FROM '994b08854fb6686786b5862ff04d4d04' THEN
   RAISE EXCEPTION 'Allocation authority guard changed: re-audit exact upstream source before installing continuation';
 END IF;
END
$source_guard$;

CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake',
    'ledger_connection_direct_assignment',
    'original_subject_direct_assignment_v1'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.

  -- A rooted native Ledger owner may issue an existing, source-bound Event
  -- obligation to another actual Person connected to the same Ledger.
  -- Unlike the legacy Event checklist, this uses the ORIGINAL Company Work ID.
  -- No employee membership, impersonation or synthetic worker assent.
  -- This is direct responsibility for an EXISTING original Work ID, not
  -- ledger_direct_create_work and not a new Company/farm task.
  if v_kind='original_subject_direct_assignment_v1' then
    if v_source<>'original_subject_direct_assignment_v1'
       or new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'decompositionId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or nullif(v_basis->>'sourceActionId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>'governor_exact_existing_original_work'
    then
      raise exception 'Exact original Work direct responsibility source fields missing'
        using errcode='23514';
    end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
          is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
       or not exists(
         select 1 from atlas.work_decomposition_members m
         join atlas.work_decomposition_groups g on g.id=m.group_id
         join atlas.work_items w on w.id=m.child_work_item_id
         join atlas.company_work_native_ledger_relevance r
           on r.work_item_id=w.id and r.organization_id=w.organization_id
          and r.ledger_id=g.authorized_ledger_id and r.attribution_state='active'
         where m.child_work_item_id=new.work_item_id
           and g.id=(v_basis->>'decompositionId')::uuid
           and g.authorized_ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and w.organization_id=new.organization_id
           and w.work_state='open' and w.source_object_type='work_decomposition'
           and w.metadata->>'originalParentWorkItemId'=g.parent_work_item_id::text
       ) then
       raise exception 'Exact original Work, connection or governing authority unavailable'
         using errcode='23514';
    end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment'
     and v_source='existing_event_work_connected_direct_assignment_v1' then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'occurrenceId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>
          'governing_principal_and_active_mutual_ledger_connections'
    then raise exception 'Existing Event obligation lacks exact governing Person, Work, Ledger and Event basis'
      using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
           is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
           new.assignee_canonical_person_id)
       or not exists(select 1 from atlas.work_items w
          join atlas.work_item_context_links ctx on ctx.work_item_id=w.id
           and ctx.organization_id=w.organization_id
           and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
           and ctx.subject_id=(v_basis->>'occurrenceId')::uuid
          join atlas.company_work_native_ledger_relevance rel
           on rel.work_item_id=w.id and rel.organization_id=w.organization_id
           and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and rel.attribution_state='active'
          where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.result_contract_key='ordinary_company_work_worker_attestation_v1'
           and not exists(select 1 from atlas.ledger_occurrence_work_actions_v1 a
            where a.ledger_id=rel.ledger_id
             and a.occurrence_id=ctx.subject_id
             and a.work_item_id=w.id and a.action_kind='removed'))
    then raise exception 'Original Event Work or lawful owner/Person Ledger relationship is unavailable'
      using errcode='23514';end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment' then
    if new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or coalesce(new.metadata->>'source','')<>'ledger_connected_direct_assignment_v1'
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'nativeLedgerId','') is null
      or nullif(v_basis->>'senderPersonId','') is null
      or coalesce(v_basis->>'authorizationBasis','')<>'active_mutual_native_ledger_connections'
    then raise exception 'Connected direct assignment requires exact original Person and Ledger source' using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         (v_basis->>'senderPersonId')::uuid)
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
      or not exists(select 1 from atlas.work_items w
         join atlas.company_work_native_ledger_relevance rel
          on rel.work_item_id=w.id and rel.organization_id=w.organization_id
          and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
          and rel.attribution_state='active' and rel.evidence_kind='participant_attested'
         where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
           and w.metadata->>'createdByPersonId'=v_basis->>'senderPersonId'
           and w.metadata->>'recipientPersonId'=new.assignee_canonical_person_id::text)
    then raise exception 'Connection-direct responsibility has no verified original Person and Ledger' using errcode='23514';end if;
    return new;
  end if;

  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id is not distinct from new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  -- A worker's own accepted physical Actual may continue ONLY the exact
  -- campaign previously rooted by a Ledger governor. It is not permission to
  -- give oneself arbitrary Work, choose a different bed or change the scope.
  -- The verifier checks the prior first-party care result, accepted source
  -- satisfaction, unexpired root scope, next eligible Subject, source grants,
  -- campaign cutoff and source original Work identity.
  if v_kind='delegated_under_standing_scope'
    and v_source='standing_care_auto_continuation_v1' then
    if tg_op<>'INSERT'
       or new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or new.organization_id is null
       or coalesce(v_basis->>'authorizationBasis','')<>
         'owner_preapproved_standing_care_actual_successor_v1'
       or not atlas.standing_care_auto_successor_authorized_v1(
         new.work_item_id,new.assignee_canonical_person_id,v_basis)
    then
      raise exception 'Standing care successor requires approved campaign and accepted worker Actual'
        using errcode='42501';
    end if;
    return new;
  end if;

  -- Native Ledger standing agreement: canonical Person is the assignee,
  -- without invented Organization/employee membership. The original
  -- membership-based delegated branch below remains unchanged.
  if v_kind='delegated_under_standing_scope'
     and new.assignee_canonical_person_id is not null then
    if new.assignee_membership_id is not null
      or (tg_op='INSERT' and new.assigned_by_membership_id is not null)
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'scopeId','') is null
      or nullif(v_basis->>'nativeLedgerId','') is null then
       raise exception 'Exact canonical Person standing-scope provenance required'
         using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_standing_assignment_scopes s
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=s.organization_id
      -- Native governing authority belongs to the verified Principal,
      -- not an Organization Membership/role label.
      join atlas.principals issuer
        on issuer.person_id=s.proposed_by_person_id
        and issuer.status='active'
      join atlas.principal_ledger_authorities grantor
        on grantor.principal_id=issuer.id and grantor.ledger_id=s.ledger_id
        and grantor.authority_kind='root_governing'
        and grantor.status='active'
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id
        and relevance.organization_id=s.organization_id
        and relevance.ledger_id=s.ledger_id
      where s.id::text=v_basis->>'scopeId'
        and s.proposed_by_person_id=atlas.current_person_id_v1()
        and s.organization_id=new.organization_id
        and s.ledger_id::text=v_basis->>'nativeLedgerId'
        and s.worker_person_id=new.assignee_canonical_person_id
        and s.worker_membership_id is null
        and s.scope_state='active' and s.accepted_at is not null
        and s.accepted_by_person_id=new.assignee_canonical_person_id
        and (s.valid_until is null or s.valid_until>now())
        and (s.coverage_mode='ledger_all_work' OR
          (s.coverage_mode='operation_class' AND
           work.organization_unit_id=s.organization_unit_id AND
           work.operation_class=s.covered_operation_class) OR
          -- Exact-Work is a third source-bound match, never a class/text grant.
          (s.coverage_mode='exact_work' AND
           s.covered_work_item_id IS NOT NULL AND
           s.covered_work_item_id=work.id))
        and work.work_state='open'
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(
              work.id,s.ledger_id) proof
            where proof.source_schema=relevance.source_schema
              and proof.source_table=relevance.source_table
              and proof.source_id=relevance.source_id)))
    ) then
      raise exception 'Accepted canonical Person standing scope is not current for exact Work'
         using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
      new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
      new.assignee_canonical_person_id) then
      raise exception 'Canonical responsible Person no longer connected to this Ledger'
        using errcode='23514';
    end if;
    return new;
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$function$;

-- EXTENSION SECTION: 16_owner_standing_campaign_auto_advance.sql
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

-- EXTENSION SECTION: 17_care_actual_with_standing_auto_advance.sql
-- DRAFT SOURCE CANDIDATE; requires protected-clone signed positive/negative tests.
-- This is a DOMAIN ADAPTER using universal original Work/Result/Continuation.
-- It DOES NOT create a farm task generator, legacy task, employee seat,
-- new canonical Work store, scheduled task, or automatic next original Work.
-- Apply only after candidate.sql in an isolated, authorized validation clone.
--
-- The existing Household Laundry adapter continues independently under its
-- exact source and Result guard. No generic client is allowed to invent a
-- "source-qualified" Work Result merely by passing a JSON payload.

INSERT INTO atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
)
VALUES(
  'continuing_care_actual_v1','organization','domain_adapter',true,
  'Authenticated original responsible Person reports actual care against a governed continuing Need and physical Subject',
  jsonb_build_object(
    'continuingActualQualification','source_proven_v1',
    'requiresOriginalWork',true,'requiresExactSubject',true,
    'requiresAcceptedNativePerson',true,
    'clockDoesNotAssertCondition',true,
    'noAutogeneratedNextWork',true)
)
ON CONFLICT (contract_key) DO NOTHING;
-- Never overwrite an existing policy with different trust semantics.
DO $policy$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key='continuing_care_actual_v1'
      AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
      AND p.active
      AND p.metadata->>'continuingActualQualification'='source_proven_v1'
  ) THEN
    RAISE EXCEPTION 'Care Actual contract policy does not match required source qualification';
  END IF;
END;
$policy$;

CREATE OR REPLACE FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $actual$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_allocation atlas.work_allocations%ROWTYPE;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_weed atlas.weed_cards%ROWTYPE;
  v_mowing atlas.mowing_area_state%ROWTYPE;
  v_prior atlas.care_current_state%ROWTYPE;
  v_result atlas.work_execution_results%ROWTYPE;
  v_care uuid;
  v_observation uuid;
  v_acceptance uuid;
  v_satisfaction uuid;
  v_actor uuid;
  v_ledger_id uuid;
  v_source_key text;
  v_kind text := nullif(btrim(coalesce(p_actual_kind,'')),'');
  v_after text := nullif(btrim(coalesce(p_condition_after,'')),'');
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_before text;
  v_effect text;
  v_result_kind text;
  v_care_kind text;
  v_source_kind text;
  v_source_event text;
  v_touch jsonb;
  v_touch_index integer;
  v_renew_seconds integer;
  v_warning_at timestamptz;
  v_due_at timestamptz;
  v_failure_at timestamptz;
  v_tz text;
  v_boundary text;
  v_at timestamptz:=clock_timestamp();
  v_campaign_continuation jsonb:=NULL;
BEGIN
  v_actor:=atlas.current_person_id_v1();
  IF auth.uid() IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
     OR p_action_id IS NULL OR v_kind IS NULL OR v_after IS NULL
     OR length(v_after)>120 OR length(coalesce(v_note,''))>1500
     OR (p_minutes IS NOT NULL AND (p_minutes<0 OR p_minutes>1440))
     OR (p_recheck_on IS NOT NULL AND p_recheck_on < (now()::date - 1))
  THEN
    RAISE EXCEPTION 'Exact signed physical Work Actual and valid observation required'
      USING ERRCODE='22023';
  END IF;
  v_source_key:='continuing-care-actual:'||p_work_item_id||':'||p_action_id;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-care-actual:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL
    OR v_work.source_object_type<>'rhythm_state'
    OR v_work.result_contract_key<>'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract' IS DISTINCT FROM 'continuing_original_work_v1'
  THEN
    RAISE EXCEPTION 'Original governed continuing Work is not available'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible'
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      AND a.assignee_canonical_person_id=v_actor
      AND a.state IN ('active','completed')
    ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
  IF v_allocation.id IS NULL
    OR coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
        !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  THEN
    RAISE EXCEPTION 'Real native-Ledger responsible Person required'
      USING ERRCODE='42501';
  END IF;
  v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
  IF NOT atlas.person_original_work_identity_disclosed_self_v1(
        v_work.organization_id,v_ledger_id,v_work.id,v_actor)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=v_work.id
        AND rel.organization_id=v_work.organization_id
        AND rel.ledger_id=v_ledger_id AND rel.attribution_state='active'
    )
  THEN
    RAISE EXCEPTION 'Original Work source and physical Subject are not disclosed'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=v_work.source_object_id
      AND s.organization_id=v_work.organization_id
      AND s.subject_kind='growing_object' FOR UPDATE;
  IF v_state.id IS NULL OR NOT EXISTS(
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on'
    ) THEN
    RAISE EXCEPTION 'Original Work is not linked to this exact physical Subject'
      USING ERRCODE='23514';
  END IF;
  -- Replays must survive a later rule retirement/physical state change;
  -- first confirm the same signed Person, original Subject and exact receipt.
  -- Authorize before replay, so a different Person cannot use the idempotency
  -- key to read someone else's Work Result.
  SELECT * INTO v_result FROM atlas.work_execution_results er
    WHERE er.organization_id=v_work.organization_id
      AND er.idempotency_key=v_source_key;
  IF v_result.id IS NOT NULL THEN
    IF v_result.work_item_id<>v_work.id
      OR v_result.reported_by_user_id IS DISTINCT FROM auth.uid()
      OR v_result.metadata->>'actualKind' IS DISTINCT FROM v_kind
      OR v_result.payload->>'conditionAfter' IS DISTINCT FROM v_after
      OR v_result.payload->>'note' IS DISTINCT FROM v_note
      OR v_result.payload->>'minutes' IS DISTINCT FROM p_minutes::text
      OR v_result.payload->>'recheckOn' IS DISTINCT FROM p_recheck_on::text
      OR NOT EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.organization_id=v_work.organization_id
          AND a.work_item_id=v_work.id AND a.execution_result_id=v_result.id
          AND a.decision='accepted' AND a.acceptance_kind='source_qualified_physical_actual'
      )
    THEN
      RAISE EXCEPTION 'Existing physical Actual does not match original signed action'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'contractVersion','continuing_care_actual_v1',
      'workItemId',v_work.id,'workResultId',v_result.id,'workState',v_work.work_state,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;


  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.organization_id=v_work.organization_id AND b.farm_id=v_state.farm_id
      AND b.active AND r.status='active';
  IF v_rule.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.growing_objects g
      WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id
    )
  THEN
    RAISE EXCEPTION 'Source cannot verify a current allowed care policy'
      USING ERRCODE='23514';
  END IF;

  -- No "generic done": source event type, effect, and postcondition are
  -- explicitly interpreted by the owning domain. Other domains plug in
  -- their own adapters, without changing the Work/Result lifecycle.
  IF v_state.rhythm_key='mowing' THEN
    SELECT * INTO v_mowing FROM atlas.mowing_area_state m
      WHERE m.object_id=v_state.subject_id
        AND m.organization_id=v_work.organization_id
        AND m.farm_id=v_state.farm_id FOR UPDATE;
    IF v_mowing.object_id IS NULL THEN
      RAISE EXCEPTION 'Mowing source state missing' USING ERRCODE='23514';
    END IF;
    v_source_kind:='mowing_result';v_source_event:=v_kind;
    CASE v_kind
      WHEN 'mowed_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        IF v_after<>'resting' THEN
          RAISE EXCEPTION 'Full mowing must report the resting condition' USING ERRCODE='22023';
        END IF;
      WHEN 'mowed_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        IF v_after<>'partial' THEN
          RAISE EXCEPTION 'Partial mowing must retain unfinished condition' USING ERRCODE='22023';
        END IF;
      WHEN 'acceptable_no_cut' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        IF v_after<>'acceptable' THEN
          RAISE EXCEPTION 'No-cut is an observed acceptable condition, not a mow' USING ERRCODE='22023';
        END IF;
      WHEN 'too_wet' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'too_wet' THEN RAISE EXCEPTION 'Wet-ground block must be observed' USING ERRCODE='22023'; END IF;
      WHEN 'equipment_or_area_problem' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'problem' THEN RAISE EXCEPTION 'Equipment/area problem must be observed' USING ERRCODE='22023'; END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified mowing Actual kind' USING ERRCODE='22023';
    END CASE;
  ELSE
    SELECT * INTO v_weed FROM atlas.weed_cards c
      WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      ORDER BY c.created_at,c.id LIMIT 1 FOR UPDATE;
    IF v_weed.id IS NULL THEN
      RAISE EXCEPTION 'Weed stewardship source state missing' USING ERRCODE='23514';
    END IF;
    CASE v_kind
      WHEN 'weeded_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        v_source_kind:='object';v_source_event:='weeded_reset';
        IF v_after<>'clear' THEN
          RAISE EXCEPTION 'Full weed restoration requires observed clear condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeded_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        v_source_kind:='object';v_source_event:='weeded';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy') THEN
          RAISE EXCEPTION 'Partial weed work must preserve residual condition' USING ERRCODE='22023';
        END IF;
      WHEN 'inspection_acceptable' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        v_source_kind:='field_log';v_source_event:='action:weed_inspection_acceptable';
        IF v_after NOT IN ('clear','row_readable') THEN
          RAISE EXCEPTION 'Acceptable weed inspection must preserve observed condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeding_blocked' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy','unknown') THEN
          RAISE EXCEPTION 'Blocked weeding must preserve real condition' USING ERRCODE='22023';
        END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified weed Actual kind' USING ERRCODE='22023';
    END CASE;
  END IF;

  -- Reject invented success when the configured Rhythm doesn't recognize
  -- the submitted domain event and its effect. Blockers are evidence only.
  IF v_effect IN ('full','partial','conditional') THEN
    SELECT t.value,(t.ordinality)::integer
      INTO v_touch,v_touch_index
    FROM pg_catalog.jsonb_array_elements(v_rule.qualifying_touches)
      WITH ORDINALITY AS t(value,ordinality)
    WHERE t.value->>'effect'=v_effect
      AND t.value->>'sourceKind'=v_source_kind
      AND (
        t.value->>'sourceEvent'=v_source_event
        OR t.value->'sourceEvents' ? v_source_event
      )
      AND (
        v_kind<>'weeded_partial'
        OR t.value#>>'{payloadContains,metadata,transition}'='partial'
      )
    ORDER BY t.ordinality LIMIT 1;
    IF v_touch IS NULL THEN
      RAISE EXCEPTION 'Result does not match original governed Rhythm rule'
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_work.work_state<>'open' OR v_allocation.state<>'active'
    OR v_state.state='paused' OR v_rule.status<>'active' THEN
    RAISE EXCEPTION 'Original Work or active Rhythm is no longer actionable'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_prior FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  v_before:=COALESCE(v_prior.condition_state,
     CASE WHEN v_state.rhythm_key='mowing' THEN v_mowing.status
          ELSE v_weed.current_condition END);
  IF v_prior.id IS NOT NULL AND v_prior.last_observed_at>v_at THEN
    RAISE EXCEPTION 'Newer physical observation must be reconciled first' USING ERRCODE='23514';
  END IF;
  -- No ordinary mowing is issued from a stale rhythm state. That condition
  -- gate lives at Work creation, not this legitimate worker reporting step.
  -- The worker is signing the *actual*, not a inferred result of the clock.
  INSERT INTO atlas.care_result_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    occurred_at,result_kind,condition_before,condition_after,
    minutes,minutes_known,actor_user_id,source_kind,source_key,note,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,
    'farm',v_state.farm_id,v_at,v_care_kind,v_before,v_after,
    p_minutes,(p_minutes IS NOT NULL),auth.uid(),'continuing_care_actual',
    v_source_key,v_note,
    jsonb_build_object('workItemId',v_work.id,'rhythmStateId',v_state.id,
      'physicalActualKind',v_kind,'sourceRuleId',v_rule.id,
      'actualReportedByPersonId',v_actor)
  ) RETURNING id INTO v_care;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    v_at,v_after,
    CASE WHEN v_effect='blocked' THEN 'hold'
      WHEN v_effect='partial' THEN 'intervene' ELSE 'observe' END,
    auth.uid(),'continuing_care_actual_observation',
    'continuing-care-observation:'||v_care::text,
    v_note,false,
    jsonb_build_object('careResultId',v_care,'workItemId',v_work.id)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state cs
    WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
      AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
      AND cs.subject_id=v_state.subject_id::text
      AND cs.condition_state=v_after AND cs.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Physical source readback failed'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,result_kind,result_contract_key,
    idempotency_key,payload,metadata,reported_at
  ) VALUES(
    v_work.organization_id,v_work.id,v_allocation.id,
    auth.uid(),v_result_kind,'continuing_care_actual_v1',
    v_source_key,
    jsonb_strip_nulls(jsonb_build_object(
      'careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'conditionAfter',v_after,'note',v_note,
      'minutes',p_minutes,'recheckOn',p_recheck_on)),
    jsonb_build_object('actualKind',v_kind,'rhythmStateId',v_state.id,
      'authenticatedReporterPersonId',v_actor,'nativeLedgerId',v_ledger_id),
    v_at
  ) RETURNING * INTO v_result;
  INSERT INTO atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence
  ) VALUES(
    v_work.organization_id,v_work.id,v_result.id,'accepted',
    'source_qualified_physical_actual','continuing_care_actual',
    jsonb_build_object('careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'sourceRuleId',v_rule.id,'actualReporter',v_actor)
  ) RETURNING id INTO v_acceptance;

  IF v_effect IN ('full','conditional') THEN
    v_renew_seconds:=CASE WHEN coalesce(v_touch->>'renewalIntervalSeconds','') ~ '^[1-9][0-9]*$'
      THEN (v_touch->>'renewalIntervalSeconds')::integer
      ELSE v_rule.validity_interval_seconds END;
    v_tz:=coalesce(nullif(v_rule.metadata->>'timezoneName',''),'America/Chicago');
    v_boundary:=coalesce(nullif(v_rule.metadata->>'boundaryMode',''),'exact_timestamp');
    v_warning_at:=atlas.rhythm_boundary_at_v1(v_at,
      greatest(0,v_renew_seconds-v_rule.warning_window_seconds),v_tz,v_boundary);
    v_due_at:=atlas.rhythm_boundary_at_v1(v_at,v_renew_seconds,v_tz,v_boundary);
    v_failure_at:=atlas.rhythm_boundary_at_v1(v_at,
      v_renew_seconds+v_rule.grace_window_seconds,v_tz,v_boundary);
    IF v_state.last_qualifying_satisfaction_id IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM atlas.rhythm_satisfactions old
        WHERE old.id=v_state.last_qualifying_satisfaction_id
          AND old.satisfied_at>v_at
      ) THEN
      RAISE EXCEPTION 'Existing newer satisfaction must not be reversed'
        USING ERRCODE='23514';
    END IF;
    INSERT INTO atlas.rhythm_satisfactions(
      organization_id,farm_id,rhythm_state_id,rhythm_binding_id,rhythm_rule_id,
      rhythm_key,subject_kind,subject_id,satisfaction_key,satisfaction_kind,
      satisfied_at,renewal_interval_seconds,source_kind,source_id,source_event,
      policy_match,evidence,created_by_user_id
    ) VALUES(
      v_state.organization_id,v_state.farm_id,v_state.id,v_state.rhythm_binding_id,
      v_rule.id,v_state.rhythm_key,v_state.subject_kind,v_state.subject_id,
      'continuing-actual:'||v_result.id::text,v_effect,v_at,
      CASE WHEN v_effect='conditional' THEN v_renew_seconds ELSE NULL END,
      'continuing_care_actual',v_care,v_kind,
      jsonb_build_object('touchIndex',v_touch_index,'touch',v_touch,
        'domainActualVerified',true),
      jsonb_build_object('workItemId',v_work.id,'careResultId',v_care,
        'workResultId',v_result.id),
      auth.uid()
    ) RETURNING id INTO v_satisfaction;
    UPDATE atlas.rhythm_state SET state='resting',
      last_qualifying_satisfaction_id=v_satisfaction,
      lease_started_at=v_at,warning_at=v_warning_at,due_at=v_due_at,
      failure_at=v_failure_at,recovery_started_at=NULL,
      last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'satisfactionId',v_satisfaction,
        'actualKind',v_kind),updated_at=now()
    WHERE id=v_state.id;
  ELSIF v_effect='partial' THEN
    -- One still-open original Work; partial progress does not manufacture
    -- another occurrence. The physical state and Actual remain durable.
    UPDATE atlas.rhythm_state SET state='recovering',
      recovery_started_at=v_at,last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'careResultId',v_care,'actualKind',v_kind),
      updated_at=now()
    WHERE id=v_state.id;
  END IF;

  -- Domain projections retain actual route/bed state; other domains provide
  -- their own projections without altering canonical Work/Result machinery.
  IF v_state.rhythm_key='mowing' THEN
    UPDATE atlas.mowing_area_state SET
      status=v_after,last_observed_at=v_at,
      last_mowed_at=CASE WHEN v_kind='mowed_full' THEN v_at ELSE last_mowed_at END,
      next_check_date=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_check_date END,
      -- source_event_id references legacy mowing_events, NOT care_result_events.
      -- Preserve legacy source_event_id; the canonical Actual is in care history.
      note=v_note,metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
        updated_at=now()
    WHERE object_id=v_state.subject_id AND organization_id=v_work.organization_id;
  ELSIF v_effect IN ('full','partial','conditional') THEN
    UPDATE atlas.weed_cards SET
      current_condition=v_after,
      next_review_on=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_review_on END,
      metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
      last_session_at=v_at,updated_at=now()
    WHERE id=v_weed.id;
  END IF;

  IF v_result_kind='completed' THEN
    UPDATE atlas.work_items SET work_state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_work.id AND work_state='open';
    UPDATE atlas.work_allocations SET state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_allocation.id AND state='active';
  END IF;

  -- The owner-authored campaign is a source-proven delegation, NOT an
  -- independent worker assignment right. A failed next Work never erases the
  -- real care Actual that was just signed and accepted.
  IF v_result_kind='completed'
    AND v_work.metadata->>'sourceStandingCampaignId' IS NOT NULL THEN
    BEGIN
      v_campaign_continuation:=
        atlas.advance_owner_standing_campaign_after_actual_internal_v1(v_result.id);
    EXCEPTION WHEN OTHERS THEN
      -- Subtransaction reverses only the attempted successor. Keep the
      -- accepted Actual and expose an explicit "needs attention" receipt.
      v_campaign_continuation:=jsonb_build_object(
        'ok',false,'nextWorkCreated',false,
        'reason','source_continuation_needs_review',
        'errorCode',SQLSTATE);
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','continuing_care_actual_v1',
    'idempotent',false,'workItemId',v_work.id,
    'workResultId',v_result.id,'careResultId',v_care,
    'careObservationId',v_observation,'acceptanceId',v_acceptance,
    'rhythmSatisfactionId',v_satisfaction,
    'workState',CASE WHEN v_result_kind='completed' THEN 'completed' ELSE 'open' END,
    'sourceConditionAfter',v_after,'sourceResultKind',v_care_kind,
    'nextEligibleAt',v_due_at,
    'campaignContinuation',v_campaign_continuation,
    'noNewWorkCreated',coalesce(
      (v_campaign_continuation->>'nextWorkCreated')::boolean,false)=false,
    'noClockAdmission',true);
END;
$actual$;

-- PRE-RELEASE HOLD. Do not grant a domain reporter to authenticated until
-- real native-Person signed positive/negative clone tests + source disclosure
-- coverage pass. Explicitly deny unsafe direct execution for now.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
