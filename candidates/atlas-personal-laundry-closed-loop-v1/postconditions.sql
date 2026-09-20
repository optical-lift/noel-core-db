-- Personal Laundry Closed Loop v1 — combined postconditions.

-- ============================================================================
-- Postconditions 1: atlas-personal-laundry-authority-split-v1
-- ============================================================================

-- Postconditions for Atlas Personal Laundry Authority Split v1.
-- These assertions are intentionally identity-free. Production-shaped behavioral
-- fixture coverage is required when the candidate is promoted to a real migration.

do $$
declare
  v_def text;
  v_comment text;
begin
  select pg_get_functiondef(
    'atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)'::regprocedure
  ) into v_def;

  if v_def is null then
    raise exception 'Laundry calibration function is missing.';
  end if;

  if position('principal_upsert_household_rhythm_api_v1' in v_def) > 0 then
    raise exception 'Laundry calibration still carries Household Rhythm write authority.';
  end if;

  if position('rhythmMutation' in v_def) = 0
     or position('calibrationDoesNotCreateRhythm' in v_def) = 0
     or position('calibrationDoesNotAssignPrincipalResponsibility' in v_def) = 0 then
    raise exception 'Laundry calibration authority-boundary return contract is incomplete.';
  end if;

  select obj_description(
    'atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)'::regprocedure,
    'pg_proc'
  ) into v_comment;

  if v_comment is null
     or position('creates, modifies, and deletes no Household Rhythm' in v_comment) = 0 then
    raise exception 'Laundry calibration function comment does not preserve the authority split.';
  end if;

  if not exists (
    select 1
    from atlas.world_kernel_definitions
    where kernel_key='household.laundry'
      and active
  ) then
    raise exception 'Active household.laundry world kernel is missing.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 2: atlas-household-claim-evidence-membrane-v1
-- ============================================================================

-- Identity-free source/schema postconditions for Household Claim/Evidence membrane v1.

do $$
declare
  v_write_def text;
  v_read_def text;
begin
  select pg_get_functiondef(
    'atlas.record_current_household_claim_evidence_api_v1(jsonb)'::regprocedure
  ) into v_write_def;

  select pg_get_functiondef(
    'atlas.current_household_claim_evidence_state_api_v1()'::regprocedure
  ) into v_read_def;

  if v_write_def is null or v_read_def is null then
    raise exception 'Household Claim/Evidence APIs are missing.';
  end if;

  if position('principal_current_household_id_v1' in v_write_def)=0
     or position('principal_current_household_id_v1' in v_read_def)=0 then
    raise exception 'Household custody is not derived from current Principal Household.';
  end if;

  if position('scope_kind=''household''' in v_write_def)=0
     or position('scope_kind=''household''' in v_read_def)=0 then
    raise exception 'Household scope is not fixed in the membrane.';
  end if;

  if position('Household Claim/Evidence subjects must use the household domain.' in v_write_def)=0 then
    raise exception 'Household subject-domain boundary is missing.';
  end if;

  if position('doesNotCreateClockPlacement' in v_write_def)=0
     or position('doesNotCreateRhythm' in v_write_def)=0
     or position('doesNotSelectCarrier' in v_write_def)=0 then
    raise exception 'Write truth-boundary contract is incomplete.';
  end if;

  if has_function_privilege('anon',
       'atlas.record_current_household_claim_evidence_api_v1(jsonb)'::regprocedure,
       'EXECUTE') then
    raise exception 'Anonymous role must not execute Household Claim/Evidence writer.';
  end if;

  if not has_function_privilege('authenticated',
       'atlas.record_current_household_claim_evidence_api_v1(jsonb)'::regprocedure,
       'EXECUTE') then
    raise exception 'Authenticated role cannot execute Household Claim/Evidence writer.';
  end if;

  if not exists (
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.record_current_household_claim_evidence_api_v1(p_payload jsonb)'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Household Claim/Evidence writer RPC registry entry is missing or incorrect.';
  end if;

  if not exists (
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.current_household_claim_evidence_state_api_v1()'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Household Claim/Evidence reader RPC registry entry is missing or incorrect.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 3: atlas-personal-laundry-instance-truth-v1
-- ============================================================================

-- Identity-free source/schema postconditions for Personal Laundry Instance Truth v1.

do $$
declare
  v_internal_def text;
  v_write_def text;
  v_read_def text;
begin
  select pg_get_functiondef(
    'atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb)'::regprocedure
  ) into v_internal_def;

  select pg_get_functiondef(
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'::regprocedure
  ) into v_write_def;

  select pg_get_functiondef(
    'atlas.personal_laundry_kernel_self_api_v2()'::regprocedure
  ) into v_read_def;

  if v_internal_def is null or v_write_def is null or v_read_def is null then
    raise exception 'Laundry V2 authority functions are missing.';
  end if;

  if position('record_current_household_claim_evidence_api_v1' in v_internal_def)=0 then
    raise exception 'Laundry fact adapter is not persisting through Household Claim/Evidence authority.';
  end if;

  if position('record_laundry_instance_fact_internal_v1' in v_write_def)=0 then
    raise exception 'Laundry V2 calibration is not routing facts through the Laundry fact adapter.';
  end if;

  if position('principal_upsert_household_rhythm_api_v1' in v_write_def)>0
     or position('household_rhythms' in v_write_def)>0
     or position('principal_upsert_household_rhythm_api_v1' in v_internal_def)>0
     or position('household_rhythms' in v_internal_def)>0 then
    raise exception 'Laundry V2 improperly carries Household Rhythm mutation authority.';
  end if;

  if position('At least one explicit Laundry fact is required; modelKey alone is not household truth.' in v_write_def)=0 then
    raise exception 'Laundry V2 does not preserve model-vs-household truth boundary.';
  end if;

  if position('responsibilityDoesNotSelectCarrier' in v_write_def)=0
     or position('needGenerationDoesNotCreateRecurrence' in v_write_def)=0
     or position('doesNotCreateClockPlacement' in v_write_def)=0 then
    raise exception 'Laundry V2 authority-boundary return contract is incomplete.';
  end if;

  if position('instanceFacts' in v_read_def)=0
     or position('acceptedInstanceFacts' in v_read_def)=0
     or position('legacyConfigurationIsNotV2FactAuthority' in v_read_def)=0
     or position('rhythmIsSeparateDownstreamAuthority' in v_read_def)=0 then
    raise exception 'Laundry V2 read projection does not preserve fact/Rhythm separation.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not execute Laundry V2 calibration.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Laundry V2 calibration.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute internal Laundry fact adapter.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Laundry V2 writer RPC registry entry is missing or incorrect.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.personal_laundry_kernel_self_api_v2()'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Laundry V2 reader RPC registry entry is missing or incorrect.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 4: atlas-personal-reality-household-claim-route-v1
-- ============================================================================

-- Identity-free postconditions for Personal Reality -> Household Claim Route v1.

do $$
declare
  v_guard_def text;
  v_writer_def text;
  v_apply_def text;
begin
  select pg_get_functiondef(
    'atlas.guard_personal_reality_household_claim_scope_v1()'::regprocedure
  ) into v_guard_def;

  select pg_get_functiondef(
    'atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)'::regprocedure
  ) into v_writer_def;

  select pg_get_functiondef(
    'atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::regprocedure
  ) into v_apply_def;

  if v_guard_def is null or v_writer_def is null or v_apply_def is null then
    raise exception 'Household Personal Reality claim route functions are missing.';
  end if;

  if position('new.scope_kind=''person''' in v_guard_def)=0
     or position('new.source_kind=''personal_reality_claim''' in v_guard_def)=0
     or position('new.subject_domain like ''household.%''' in v_guard_def)=0 then
    raise exception 'Legacy person-route fail-closed guard is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='claim_records'
      and t.tgname='personal_reality_household_claim_scope_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Personal Reality Household claim scope guard trigger is missing.';
  end if;

  if position('sourceEvidenceScope' in v_writer_def)=0
     or position('rawTestimonyNotCopied' in v_writer_def)=0
     or position('crossScopeClaimEvidenceLinkCreated' in v_writer_def)=0 then
    raise exception 'Household promotion writer does not preserve cross-scope provenance boundary.';
  end if;

  if position('insert into atlas.claim_evidence_links' in v_writer_def)=0 then
    raise exception 'Household promotion writer does not link same-scope interpretation Evidence.';
  end if;

  if position('record_current_household_claim_from_capture_evidence_v1' in v_apply_def)=0
     or position('Household Personal Reality correction must remain on the same subject.' in v_apply_def)=0 then
    raise exception 'Household Personal Reality apply route is not bound to same-subject Household promotion.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute internal Household capture promotion writer.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Household Personal Reality apply route.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not execute Household Personal Reality apply route.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.apply_personal_reality_household_claim_effect_self_api_v1(p_proposal_id uuid)'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Household Personal Reality apply RPC registry entry is missing or incorrect.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 5: atlas-laundry-household-consequence-v1
-- ============================================================================

-- Identity-free source/schema postconditions for Laundry Household Evidence -> Person Consequence v1.

do $$
declare
  v_policy_def text;
  v_definition_guard_def text;
  v_snapshot_def text;
  v_household_guard_def text;
  v_eval_def text;
begin
  select pg_get_functiondef(
    'atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(uuid,uuid)'::regprocedure
  ) into v_policy_def;

  select pg_get_functiondef(
    'atlas.guard_personal_laundry_consequence_definition_authority_v1()'::regprocedure
  ) into v_definition_guard_def;

  select pg_get_functiondef(
    'atlas.household_consequence_evidence_snapshot_v1(uuid,uuid)'::regprocedure
  ) into v_snapshot_def;

  select pg_get_functiondef(
    'atlas.guard_household_consequence_evaluation_authority_v1()'::regprocedure
  ) into v_household_guard_def;

  select pg_get_functiondef(
    'atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)'::regprocedure
  ) into v_eval_def;

  if v_policy_def is null
     or v_definition_guard_def is null
     or v_snapshot_def is null
     or v_household_guard_def is null
     or v_eval_def is null then
    raise exception 'Laundry Household consequence authority functions are missing.';
  end if;

  if position('accumulation_threshold' in v_policy_def)=0
     or position('ready_for_cycle' in v_policy_def)=0
     or position('laundry_cycle_needed' in v_policy_def)=0
     or position('unsupportedNeedGenerationIsNotGuessed' in v_policy_def)=0 then
    raise exception 'Laundry deterministic consequence policy is incomplete.';
  end if;

  if position('personal_laundry_consequence_policy_from_need_generation_claim_v1' in v_definition_guard_def)=0
     or position('deterministic policy derived from accepted need-generation truth' in v_definition_guard_def)=0 then
    raise exception 'Laundry consequence definition guard does not enforce deterministic accepted-rule policy.';
  end if;

  if position('scope_kind=''household''' in v_snapshot_def)=0
     or position('cannot drive a Consequence' in v_snapshot_def)=0 then
    raise exception 'Household consequence Evidence snapshot boundary is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_state_events'
      and t.tgname='person_consequence_evaluation_authority_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Person consequence evaluation guard trigger is missing after split.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_state_events'
      and t.tgname='household_consequence_evaluation_authority_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Household consequence evaluation guard trigger is missing.';
  end if;

  if position('evidenceScopeKind' in v_household_guard_def)=0
     or position('evaluate_life_state_consequence_policies_v1' in v_household_guard_def)=0
     or position('policyDerivedNotCallerSupplied' in v_eval_def)=0
     or position('doesNotCreateClockPlacement' in v_eval_def)=0 then
    raise exception 'Laundry Household consequence evaluation authority boundary is incomplete.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute Laundry deterministic policy adapter.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.household_consequence_evidence_snapshot_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute Household consequence snapshot builder.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.ensure_personal_laundry_consequence_definition_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot ensure Laundry consequence definition.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot evaluate Laundry consequence from Household Evidence.';
  end if;

  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1()
  ) then
    raise exception 'Authenticated RPC registry drift exists after Laundry Household consequence candidate.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 6: atlas-principal-consequence-clock-characterization-v1
-- ============================================================================

-- Identity-free postconditions for Principal Consequence Clock Characterization v1.

do $$
declare
  v_write_def text;
  v_admission_def text;
begin
  select pg_get_functiondef(
    'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)'::regprocedure
  ) into v_write_def;

  select pg_get_functiondef(
    'atlas.person_life_consequence_clock_admission_state_v1(uuid,uuid)'::regprocedure
  ) into v_admission_def;

  if v_write_def is null or v_admission_def is null then
    raise exception 'Principal consequence Clock characterization functions are missing.';
  end if;

  if position('record_person_claim_evidence_api_v1' in v_write_def)=0 then
    raise exception 'Clock characterization is not persisted through universal person Claim/Evidence.';
  end if;

  if position('missingRelevanceStartDoesNotMeanOpenNow' in v_write_def)=0
     or position('deadlineAloneDoesNotEstablishCurrentRelevance' in v_write_def)=0
     or position('doesNotCreateClockCandidate' in v_write_def)=0 then
    raise exception 'Clock characterization truth boundary is incomplete.';
  end if;

  if position('principal_carrier_required' in v_admission_def)=0
     or position('execution_readiness_required' in v_admission_def)=0
     or position('clock_characterization_incomplete' in v_admission_def)=0 then
    raise exception 'Clock admission blocker contract is incomplete.';
  end if;

  if position('principal_clock_candidates_v1' in v_write_def)>0
     or position('principal_clock_candidates_v1' in v_admission_def)>0 then
    raise exception 'Characterization candidate improperly mutates or depends on live Clock candidate inventory.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot record owned consequence Clock characterization.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.person_life_consequence_clock_admission_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot read owned consequence Clock admission state.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.person_life_consequence_clock_admission_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not access consequence Clock characterization APIs.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Clock characterization candidate.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 7: atlas-laundry-consequence-axis-authority-v1
-- ============================================================================

-- Identity-free postconditions for Laundry Consequence Axis Authority v1.

do $$
declare
  v_carrier_def text;
  v_readiness_def text;
  v_guard_def text;
  v_reconcile_def text;
begin
  select pg_get_functiondef(
    'atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(uuid,uuid,uuid)'::regprocedure
  ) into v_carrier_def;

  select pg_get_functiondef(
    'atlas.personal_laundry_execution_readiness_from_claim_v1(uuid,uuid,uuid)'::regprocedure
  ) into v_readiness_def;

  select pg_get_functiondef(
    'atlas.guard_personal_laundry_consequence_axis_authority_v1()'::regprocedure
  ) into v_guard_def;

  select pg_get_functiondef(
    'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::regprocedure
  ) into v_reconcile_def;

  if v_carrier_def is null
     or v_readiness_def is null
     or v_guard_def is null
     or v_reconcile_def is null then
    raise exception 'Laundry consequence axis authority functions are missing.';
  end if;

  if position('ordinary_responsibility' in v_carrier_def)=0
     or position('sharedDoesNotMeanPrincipal' in v_carrier_def)=0
     or position('principal:' in v_carrier_def)=0 then
    raise exception 'Laundry carrier resolution boundary is incomplete.';
  end if;

  if position('execution_readiness' in v_readiness_def)=0
     or position('blockedDoesNotDeleteRequirement' in v_readiness_def)=0
     or position('unknownDoesNotBecomeReady' in v_readiness_def)=0 then
    raise exception 'Laundry readiness resolution boundary is incomplete.';
  end if;

  if position('Preserve the separately' in v_guard_def)=0
     or position('Placement is intentionally outside this authority.' in v_guard_def)=0 then
    raise exception 'Laundry consequence axis persistence guard does not preserve independent authority.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_consequence_instances'
      and t.tgname='person_life_laundry_consequence_axis_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Laundry consequence axis authority trigger is missing.';
  end if;

  if position('placement_state=v_new' in v_reconcile_def)>0
     or position('doesNotCreateClockPlacement' in v_reconcile_def)=0 then
    raise exception 'Laundry reconciliation improperly carries placement authority.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot reconcile owned Laundry consequence axes.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not reconcile Laundry consequence axes.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Laundry consequence axis candidate.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 8: atlas-person-life-consequence-clock-candidate-v1
-- ============================================================================

-- Identity-free source/schema postconditions for Person Life Consequence -> Principal Clock Candidate v1.

do $$
declare
  v_candidate_view text;
  v_inventory_view text;
  v_arb text;
  v_api text;
begin
  select pg_get_viewdef(
    'atlas.principal_person_life_consequence_clock_candidates_v1'::regclass,
    true
  ) into v_candidate_view;

  select pg_get_viewdef(
    'atlas.principal_clock_candidates_v2'::regclass,
    true
  ) into v_inventory_view;

  select pg_get_functiondef(
    'atlas.principal_clock_arbitration_v2(uuid,date,timestamptz)'::regprocedure
  ) into v_arb;

  select pg_get_functiondef(
    'atlas.principal_clock_api_v2(date,timestamptz)'::regprocedure
  ) into v_api;

  if v_candidate_view is null
     or v_inventory_view is null
     or v_arb is null
     or v_api is null then
    raise exception 'Principal Clock V2 consequence candidate contracts are missing.';
  end if;

  if position('carrier_state = ''established''' in v_candidate_view)=0
     or position('execution_readiness = ''ready''' in v_candidate_view)=0
     or position('clock_characterization' in v_candidate_view)=0
     or position('person_life_consequence_clock_characterization_completeness_v1' in v_candidate_view)=0 then
    raise exception 'Person Life consequence Clock candidate admission is incomplete.';
  end if;

  if position('principal_clock_candidates_v1' in v_inventory_view)=0
     or position('principal_person_life_consequence_clock_candidates_v1' in v_inventory_view)=0 then
    raise exception 'Principal Clock V2 inventory does not preserve V1 plus the new admitted source.';
  end if;

  if position('principal_clock_candidates_v2' in v_arb)=0
     or position('principal_clock_candidates_v1' in v_arb)>0 then
    raise exception 'Principal Clock arbitration V2 is not isolated to the V2 candidate inventory.';
  end if;

  if position('principal_clock_arbitration_v2' in v_api)=0
     or position('personLifeConsequenceCandidatesRequireExplicitAdmission' in v_api)=0 then
    raise exception 'Principal Clock API V2 is not bound to V2 arbitration/admission truth.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.principal_clock_api_v2(date,timestamptz)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Principal Clock API V2.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.principal_clock_api_v2(date,timestamptz)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not execute Principal Clock API V2.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.principal_clock_arbitration_v2(uuid,date,timestamptz)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute internal Principal Clock arbitration V2.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Principal Clock V2 candidate.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 9: atlas-laundry-actual-consequence-resolution-v1
-- ============================================================================

-- Identity-free postconditions for Laundry Actual -> Consequence Resolution v1.

do $$
declare
  v_actual_def text;
  v_authority_def text;
  v_guard_def text;
  v_resolver_def text;
begin
  select pg_get_functiondef(
    'atlas.record_personal_laundry_actual_self_api_v1(jsonb)'::regprocedure
  ) into v_actual_def;

  select pg_get_functiondef(
    'atlas.personal_laundry_actual_resolution_authority_v1(uuid,uuid,uuid)'::regprocedure
  ) into v_authority_def;

  select pg_get_functiondef(
    'atlas.guard_personal_laundry_consequence_resolution_actual_v1()'::regprocedure
  ) into v_guard_def;

  select pg_get_functiondef(
    'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)'::regprocedure
  ) into v_resolver_def;

  if v_actual_def is null
     or v_authority_def is null
     or v_guard_def is null
     or v_resolver_def is null then
    raise exception 'Laundry actual-resolution authority functions are missing.';
  end if;

  if position('physical_process_actual' in v_actual_def)=0
     or position('process_actual' in v_actual_def)=0
     or position('actualIsNotTaskCompletion' in v_actual_def)=0 then
    raise exception 'Laundry actual writer boundary is incomplete.';
  end if;

  if position('entered_washing' in v_authority_def)=0
     or position('laundry_cycle_needed' in v_authority_def)=0
     or position('predates the consequence requirement' in v_authority_def)=0 then
    raise exception 'Laundry actual resolution law is incomplete.';
  end if;

  if position('resolutionActualClaimId' in v_guard_def)=0
     or position('canonical physical-actual envelope' in v_guard_def)=0 then
    raise exception 'Laundry resolution persistence guard is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_state_events'
      and t.tgname='personal_laundry_consequence_resolution_actual_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Laundry consequence-resolution actual guard trigger is missing.';
  end if;

  if position('record_person_life_state_api_v1' in v_resolver_def)=0
     or position('taskCompletionDidNotResolveRequirement' in v_resolver_def)=0 then
    raise exception 'Laundry resolver does not reuse governed Person Life resolution authority.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.record_personal_laundry_actual_self_api_v1(jsonb)'::regprocedure,
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated Laundry actual/resolution APIs are unavailable.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.record_personal_laundry_actual_self_api_v1(jsonb)'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not use Laundry actual/resolution APIs.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Laundry actual-resolution candidate.';
  end if;
end
$$;

-- ============================================================================
-- Postconditions 10: atlas-laundry-learning-proposal-v1
-- ============================================================================

-- Identity-free postconditions for Laundry Learning Proposal v1.

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::regprocedure
  ) into v_def;

  if v_def is null then
    raise exception 'Laundry learning proposal function is missing.';
  end if;

  if position('requiredDistinctDates' in v_def)=0
     or position('between 6 and 8' in v_def)=0
     or position('pattern_not_stable' in v_def)=0 then
    raise exception 'Laundry learning threshold/gap law is incomplete.';
  end if;

  if position('rhythm_pattern_proposal' in v_def)=0
     or position('derived_pattern_proposal' in v_def)=0
     or position('household_learning_engine' in v_def)=0 then
    raise exception 'Laundry learning proposal provenance/lifecycle boundary is incomplete.';
  end if;

  if position('derived_pattern_analysis' in v_def)=0
     or position('supportRole' in v_def)=0
     or position('physical_actual' in v_def)=0 then
    raise exception 'Laundry learning Evidence spine is incomplete.';
  end if;

  if position('doesNotCreateRhythm' in v_def)=0
     or position('proposalRequiresAdjudication' in v_def)=0 then
    raise exception 'Laundry learner does not preserve proposal-only authority.';
  end if;

  if position('insert into atlas.household_rhythms' in lower(v_def))>0
     or position('principal_upsert_household_rhythm_api_v1' in v_def)>0
     or position('insert into atlas.tasks' in lower(v_def))>0 then
    raise exception 'Laundry learner improperly materializes Rhythm/task state.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot run Laundry learning proposal analysis.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not run Laundry learning proposal analysis.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Laundry learning proposal candidate.';
  end if;
end
$$;

do $$
begin
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after complete Personal Laundry closed-loop bundle.';
  end if;
end
$$;
