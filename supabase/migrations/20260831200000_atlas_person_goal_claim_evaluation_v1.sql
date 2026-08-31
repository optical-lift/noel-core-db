-- Atlas Person Goal Claim Evaluation v1
--
-- Resolves explicitly authorized Goal requirement thresholds from current,
-- evidence-backed person claims. This is intentionally not a domain-specific
-- Goal engine: the Goal requirement itself must name the evidence subject,
-- claim type, admissible lifecycle/authority, numeric value path, comparison
-- operator, threshold, and unit contract.
--
-- Missing, malformed, stale, superseded, or unauthorized evidence remains
-- unknown. This membrane does not invent requirements, infer customary domain
-- practice, convert units, select carriers, create consequences, or arbitrate
-- Clock.

begin;

create or replace function atlas.resolve_person_goal_requirement_results_v1(
  p_owner_user_id uuid,
  p_goal_packet jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_requirement jsonb;
  v_requirement_key text;
  v_requirement_kind text;
  v_authorization jsonb;
  v_authorization_claim_id uuid;
  v_authorization_evidence_id uuid;
  v_authorization_claim_value jsonb;
  v_authorization_claim_evidence_id uuid;
  v_authorization_claim_state text;
  v_authorization_claim_authority text;
  v_authorization_claim_subject_domain text;
  v_authorization_claim_subject_kind text;
  v_authorization_claim_subject_id text;
  v_selector jsonb;
  v_selector_subject jsonb;
  v_selector_domain text;
  v_selector_kind text;
  v_selector_id text;
  v_selector_claim_type text;
  v_lifecycle_states jsonb;
  v_authority_kinds jsonb;
  v_criterion jsonb;
  v_operator text;
  v_threshold numeric;
  v_expected_unit text;
  v_value_path text[];
  v_unit_path text[];
  v_candidate record;
  v_candidate_value numeric;
  v_candidate_unit text;
  v_candidate_count integer;
  v_comparable_count integer;
  v_selected_claim_id uuid;
  v_selected_evidence_id uuid;
  v_selected_lifecycle text;
  v_selected_authority text;
  v_selected_recorded_at timestamptz;
  v_selected_observed_at timestamptz;
  v_selected_value numeric;
  v_state text;
  v_reason text;
  v_satisfied boolean;
  v_results jsonb := '[]'::jsonb;
  v_goal_subject_domain text;
  v_goal_subject_kind text;
  v_goal_subject_id text;
  v_now timestamptz := now();
begin
  if p_owner_user_id is null then
    raise exception 'owner user id is required.' using errcode='22023';
  end if;
  if p_goal_packet is null
     or jsonb_typeof(p_goal_packet)<>'object'
     or p_goal_packet->>'contractVersion'<>'life_goal_packet_v1' then
    raise exception 'life_goal_packet_v1 is required.' using errcode='22023';
  end if;
  if p_goal_packet->'scope'->>'kind'<>'person'
     or p_goal_packet->'scope'->>'id'<>p_owner_user_id::text then
    raise exception 'Goal packet scope must match person custody.' using errcode='42501';
  end if;

  v_goal_subject_domain := btrim(coalesce(p_goal_packet->'subject'->>'domain',''));
  v_goal_subject_kind := btrim(coalesce(p_goal_packet->'subject'->>'kind',''));
  v_goal_subject_id := btrim(coalesce(p_goal_packet->'subject'->>'id',''));

  for v_requirement in
    select value from jsonb_array_elements(coalesce(p_goal_packet->'requirements','[]'::jsonb))
  loop
    v_requirement_key := btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key',''));
    v_requirement_kind := btrim(coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind',''));
    v_state := 'unknown';
    v_reason := null;
    v_authorization := null;
    v_authorization_claim_id := null;
    v_authorization_evidence_id := null;
    v_authorization_claim_value := null;
    v_authorization_claim_evidence_id := null;
    v_authorization_claim_state := null;
    v_authorization_claim_authority := null;
    v_authorization_claim_subject_domain := null;
    v_authorization_claim_subject_kind := null;
    v_authorization_claim_subject_id := null;
    v_selector := null;
    v_selector_subject := null;
    v_selector_domain := null;
    v_selector_kind := null;
    v_selector_id := null;
    v_selector_claim_type := null;
    v_lifecycle_states := null;
    v_authority_kinds := null;
    v_criterion := null;
    v_operator := null;
    v_threshold := null;
    v_expected_unit := null;
    v_value_path := null;
    v_unit_path := null;
    v_candidate_value := null;
    v_candidate_unit := null;
    v_candidate_count := 0;
    v_comparable_count := 0;
    v_selected_claim_id := null;
    v_selected_evidence_id := null;
    v_selected_lifecycle := null;
    v_selected_authority := null;
    v_selected_recorded_at := null;
    v_selected_observed_at := null;
    v_selected_value := null;
    v_satisfied := false;

    if v_requirement_key='' then
      v_reason := 'missing_requirement_key';
    elsif v_requirement_kind<>'claim_threshold' then
      v_reason := 'unsupported_requirement_kind';
    end if;

    -- A requirement can govern evidence-backed evaluation only while its exact
    -- person-accepted authorization claim remains current. If that claim is
    -- later corrected/superseded, this Goal version becomes stale rather than
    -- silently inheriting the new requirement.
    if v_reason is null then
      v_authorization := v_requirement->'authorization';
      if jsonb_typeof(v_authorization)<>'object'
         or v_authorization->>'basis'<>'person_accepted_goal_requirement_claim' then
        v_reason := 'missing_current_requirement_authorization';
      elsif coalesce(v_authorization->>'claimId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or coalesce(v_authorization->>'evidenceId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        v_reason := 'invalid_requirement_authorization_reference';
      else
        v_authorization_claim_id := (v_authorization->>'claimId')::uuid;
        v_authorization_evidence_id := (v_authorization->>'evidenceId')::uuid;

        select c.value,c.primary_evidence_id,c.lifecycle_state,c.authority_kind,
               c.subject_domain,c.subject_kind,c.subject_id
        into v_authorization_claim_value,v_authorization_claim_evidence_id,
             v_authorization_claim_state,v_authorization_claim_authority,
             v_authorization_claim_subject_domain,v_authorization_claim_subject_kind,v_authorization_claim_subject_id
        from atlas.claim_records c
        where c.id=v_authorization_claim_id
          and c.scope_kind='person'
          and c.scope_id=p_owner_user_id
          and c.claim_type='goal_requirement'
          and (c.valid_from is null or c.valid_from<=v_now)
          and (c.valid_until is null or c.valid_until>=v_now);

        if v_authorization_claim_value is null
           or v_authorization_claim_state<>'accepted'
           or v_authorization_claim_authority<>'person_acceptance'
           or v_authorization_claim_evidence_id is distinct from v_authorization_evidence_id
           or v_authorization_claim_subject_domain is distinct from v_goal_subject_domain
           or v_authorization_claim_subject_kind is distinct from v_goal_subject_kind
           or v_authorization_claim_subject_id is distinct from v_goal_subject_id
           or v_authorization_claim_value is distinct from (v_requirement - 'authorization') then
          v_reason := 'requirement_authorization_is_not_current';
        end if;
      end if;
    end if;

    if v_reason is null then
      v_selector := v_requirement->'evidenceSelector';
      v_selector_subject := v_selector->'subject';
      v_selector_domain := btrim(coalesce(v_selector_subject->>'domain',''));
      v_selector_kind := btrim(coalesce(v_selector_subject->>'kind',''));
      v_selector_id := btrim(coalesce(v_selector_subject->>'id',''));
      v_selector_claim_type := btrim(coalesce(v_selector->>'claimType',''));
      v_lifecycle_states := v_selector->'lifecycleStates';
      v_authority_kinds := v_selector->'authorityKinds';

      if jsonb_typeof(v_selector)<>'object'
         or jsonb_typeof(v_selector_subject)<>'object'
         or v_selector_domain=''
         or v_selector_kind=''
         or v_selector_id=''
         or v_selector_claim_type=''
         or jsonb_typeof(v_lifecycle_states)<>'array'
         or jsonb_array_length(v_lifecycle_states)=0
         or jsonb_typeof(v_authority_kinds)<>'array'
         or jsonb_array_length(v_authority_kinds)=0
         or exists (select 1 from jsonb_array_elements_text(v_lifecycle_states) x(value) where btrim(x.value)='')
         or exists (select 1 from jsonb_array_elements_text(v_authority_kinds) x(value) where btrim(x.value)='') then
        v_reason := 'invalid_evidence_selector';
      end if;
    end if;

    if v_reason is null then
      v_criterion := v_requirement->'criterion';
      v_operator := btrim(coalesce(v_criterion->>'operator',''));
      if jsonb_typeof(v_criterion)<>'object'
         or jsonb_typeof(v_criterion->'path')<>'array'
         or jsonb_array_length(v_criterion->'path')=0
         or exists (select 1 from jsonb_array_elements_text(v_criterion->'path') x(value) where btrim(x.value)='')
         or jsonb_typeof(v_criterion->'value')<>'number'
         or v_operator not in ('>=','>','<=','<','=','!=') then
        v_reason := 'invalid_claim_threshold_criterion';
      else
        select array_agg(x.value order by x.ordinality)
        into v_value_path
        from jsonb_array_elements_text(v_criterion->'path') with ordinality x(value,ordinality);
        v_threshold := (v_criterion->>'value')::numeric;
        v_expected_unit := nullif(btrim(v_criterion->>'unit'),'');

        if v_expected_unit is not null then
          if jsonb_typeof(v_criterion->'unitPath')<>'array'
             or jsonb_array_length(v_criterion->'unitPath')=0
             or exists (select 1 from jsonb_array_elements_text(v_criterion->'unitPath') x(value) where btrim(x.value)='') then
            v_reason := 'invalid_claim_threshold_unit_contract';
          else
            select array_agg(x.value order by x.ordinality)
            into v_unit_path
            from jsonb_array_elements_text(v_criterion->'unitPath') with ordinality x(value,ordinality);
          end if;
        end if;
      end if;
    end if;

    if v_reason is null then
      for v_candidate in
        select c.id,c.value,c.lifecycle_state,c.authority_kind,c.primary_evidence_id,c.recorded_at,e.observed_at
        from atlas.claim_records c
        join atlas.evidence_records e on e.id=c.primary_evidence_id
        where c.scope_kind='person'
          and c.scope_id=p_owner_user_id
          and c.subject_domain=v_selector_domain
          and c.subject_kind=v_selector_kind
          and c.subject_id=v_selector_id
          and c.claim_type=v_selector_claim_type
          and c.lifecycle_state not in ('superseded','expired')
          and (c.valid_from is null or c.valid_from<=v_now)
          and (c.valid_until is null or c.valid_until>=v_now)
          and exists (
            select 1 from jsonb_array_elements_text(v_lifecycle_states) allowed(value)
            where allowed.value=c.lifecycle_state
          )
          and exists (
            select 1 from jsonb_array_elements_text(v_authority_kinds) allowed(value)
            where allowed.value=c.authority_kind
          )
        order by c.recorded_at desc,c.id desc
      loop
        v_candidate_count := v_candidate_count + 1;

        if jsonb_typeof(v_candidate.value #> v_value_path)<>'number' then
          continue;
        end if;

        if v_expected_unit is not null then
          if jsonb_typeof(v_candidate.value #> v_unit_path)<>'string' then
            continue;
          end if;
          v_candidate_unit := v_candidate.value #>> v_unit_path;
          if v_candidate_unit is distinct from v_expected_unit then
            continue;
          end if;
        end if;

        v_candidate_value := (v_candidate.value #>> v_value_path)::numeric;
        v_comparable_count := v_comparable_count + 1;
        v_satisfied := case v_operator
          when '>=' then v_candidate_value>=v_threshold
          when '>' then v_candidate_value>v_threshold
          when '<=' then v_candidate_value<=v_threshold
          when '<' then v_candidate_value<v_threshold
          when '=' then v_candidate_value=v_threshold
          when '!=' then v_candidate_value<>v_threshold
          else false
        end;

        if v_selected_claim_id is null then
          v_selected_claim_id := v_candidate.id;
          v_selected_evidence_id := v_candidate.primary_evidence_id;
          v_selected_lifecycle := v_candidate.lifecycle_state;
          v_selected_authority := v_candidate.authority_kind;
          v_selected_recorded_at := v_candidate.recorded_at;
          v_selected_observed_at := v_candidate.observed_at;
          v_selected_value := v_candidate_value;
        end if;

        if v_satisfied then
          v_state := 'satisfied';
          v_selected_claim_id := v_candidate.id;
          v_selected_evidence_id := v_candidate.primary_evidence_id;
          v_selected_lifecycle := v_candidate.lifecycle_state;
          v_selected_authority := v_candidate.authority_kind;
          v_selected_recorded_at := v_candidate.recorded_at;
          v_selected_observed_at := v_candidate.observed_at;
          v_selected_value := v_candidate_value;
          exit;
        end if;
      end loop;

      if v_state<>'satisfied' then
        if v_comparable_count>0 then
          v_state := 'unmet';
          v_reason := 'current_comparable_claims_do_not_meet_threshold';
        elsif v_candidate_count>0 then
          v_state := 'unknown';
          v_reason := 'current_claims_are_not_comparable_under_explicit_criterion';
        else
          v_state := 'unknown';
          v_reason := 'no_current_claim_matches_explicit_evidence_selector';
        end if;
      else
        v_reason := 'current_evidence_backed_claim_meets_threshold';
      end if;
    end if;

    v_results := v_results || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'requirementKey',v_requirement_key,
      'state',v_state,
      'detail',jsonb_strip_nulls(jsonb_build_object(
        'reason',v_reason,
        'candidateCount',v_candidate_count,
        'comparableCandidateCount',v_comparable_count,
        'observedValue',v_selected_value,
        'operator',case when v_reason not in ('missing_requirement_key','unsupported_requirement_kind','missing_current_requirement_authorization','invalid_requirement_authorization_reference','requirement_authorization_is_not_current','invalid_evidence_selector','invalid_claim_threshold_criterion','invalid_claim_threshold_unit_contract') then v_operator else null end,
        'threshold',case when v_reason not in ('missing_requirement_key','unsupported_requirement_kind','missing_current_requirement_authorization','invalid_requirement_authorization_reference','requirement_authorization_is_not_current','invalid_evidence_selector','invalid_claim_threshold_criterion','invalid_claim_threshold_unit_contract') then v_threshold else null end,
        'unit',v_expected_unit
      )),
      'source',jsonb_strip_nulls(jsonb_build_object(
        'resolver','atlas.resolve_person_goal_requirement_results_v1',
        'contractVersion','person_goal_claim_requirement_result_v1',
        'basis','current_claim_evidence',
        'requirementAuthorizationClaimId',v_authorization_claim_id,
        'requirementAuthorizationEvidenceId',v_authorization_evidence_id,
        'claimId',v_selected_claim_id,
        'evidenceId',v_selected_evidence_id,
        'claimLifecycleState',v_selected_lifecycle,
        'claimAuthorityKind',v_selected_authority,
        'claimRecordedAt',v_selected_recorded_at,
        'evidenceObservedAt',v_selected_observed_at
      ))
    )));
  end loop;

  return v_results;
end;
$$;

comment on function atlas.resolve_person_goal_requirement_results_v1(uuid,jsonb) is
  'Internal evidence resolver for person Goal claim_threshold requirements. Requires the exact current person-accepted requirement authorization and explicit evidence selector/criterion; compares current claims without unit conversion and emits evidence-cited requirement results.';

revoke all on function atlas.resolve_person_goal_requirement_results_v1(uuid,jsonb) from public, anon, authenticated;
grant execute on function atlas.resolve_person_goal_requirement_results_v1(uuid,jsonb) to service_role;

create or replace function atlas.evaluate_person_goal_from_claim_evidence_api_v1(
  p_definition_id uuid,
  p_source_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_goal_packet jsonb;
  v_results jsonb;
  v_payload jsonb;
  v_receipt jsonb;
  v_existing_event_id uuid;
  v_existing_definition_id uuid;
  v_existing_event_kind text;
  v_existing_payload jsonb;
  v_existing_evaluation jsonb;
  v_existing_evidence jsonb;
  v_existing_occurred_at timestamptz;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_definition_id is null then raise exception 'definitionId is required.' using errcode='22023'; end if;
  v_source_key := btrim(coalesce(p_source_key,''));
  if v_source_key='' then raise exception 'sourceKey is required.' using errcode='22023'; end if;

  -- Serialize exact operation identity so concurrent retries cannot manufacture
  -- distinct observedAt payloads for the same sourceKey.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':' || v_source_key,0));

  select e.id,e.definition_id,e.event_kind,e.input_payload,e.evaluation,e.evidence,e.occurred_at
  into v_existing_event_id,v_existing_definition_id,v_existing_event_kind,v_existing_payload,
       v_existing_evaluation,v_existing_evidence,v_existing_occurred_at
  from atlas.person_life_state_events e
  where e.owner_user_id=v_user_id and e.source_key=v_source_key;

  if v_existing_event_id is not null then
    if v_existing_definition_id is distinct from p_definition_id
       or v_existing_event_kind<>'goal_evaluation'
       or v_existing_payload->>'resolverContract'<>'person_goal_claim_evaluation_v1' then
      raise exception 'sourceKey retry does not match existing evidence-backed Goal evaluation.' using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'replayed',true,
      'eventId',v_existing_event_id,
      'definitionId',p_definition_id,
      'eventKind','goal_evaluation',
      'occurredAt',v_existing_occurred_at,
      'requirementResults',coalesce(v_existing_payload->'requirementResults','[]'::jsonb),
      'evaluation',v_existing_evaluation,
      'evidence',v_existing_evidence,
      'truthBoundary',jsonb_build_object(
        'serverResolvedFromCurrentClaims',true,
        'missingEvidenceRemainsUnknown',true,
        'requirementAuthorizationMustRemainCurrent',true,
        'unitConversionAuthority',false,
        'evaluationDoesNotCreateTask',true,
        'evaluationDoesNotSelectCarrier',true,
        'evaluationDoesNotCreateConsequence',true,
        'evaluationDoesNotCreateClockPlacement',true
      )
    );
  end if;

  select d.engine_packet into v_goal_packet
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='goal'
    and d.status='active';

  if v_goal_packet is null then
    raise exception 'Active person Goal definition not found for this user.' using errcode='42501';
  end if;

  v_results := atlas.resolve_person_goal_requirement_results_v1(v_user_id,v_goal_packet);
  v_payload := jsonb_build_object(
    'sourceKey',v_source_key,
    'eventKind','goal_evaluation',
    'observedAt',now(),
    'requirementResults',v_results,
    'resolverContract','person_goal_claim_evaluation_v1',
    'evidence',jsonb_build_object(
      'resolver','atlas.resolve_person_goal_requirement_results_v1',
      'basis','current_claim_evidence',
      'requirementResults',v_results
    )
  );

  v_receipt := atlas.record_person_life_state_api_v1(p_definition_id,v_payload);

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'eventId',v_receipt->'eventId',
    'definitionId',p_definition_id,
    'eventKind','goal_evaluation',
    'occurredAt',v_receipt->'occurredAt',
    'requirementResults',v_results,
    'evaluation',v_receipt->'evaluation',
    'truthBoundary',jsonb_build_object(
      'serverResolvedFromCurrentClaims',true,
      'missingEvidenceRemainsUnknown',true,
      'requirementAuthorizationMustRemainCurrent',true,
      'unitConversionAuthority',false,
      'evaluationDoesNotCreateTask',true,
      'evaluationDoesNotSelectCarrier',true,
      'evaluationDoesNotCreateConsequence',true,
      'evaluationDoesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.evaluate_person_goal_from_claim_evidence_api_v1(uuid,text) is
  'Signed-in person Goal evidence-backed evaluator. Resolves explicit claim_threshold requirements from current governed claims, records the resulting Goal evaluation event, and grants no task, carrier, consequence, unit-conversion, or Clock authority.';

revoke all on function atlas.evaluate_person_goal_from_claim_evidence_api_v1(uuid,text) from public, anon;
grant execute on function atlas.evaluate_person_goal_from_claim_evidence_api_v1(uuid,text) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values (
  'atlas.evaluate_person_goal_from_claim_evidence_api_v1(uuid, text)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Evaluate the signed-in person active Goal from current governed Claim/Evidence truth using only explicit claim_threshold selectors and criteria embedded in person-authorized requirements.',
    'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); each requirement must retain its exact current person-accepted goal_requirement authorization claim. Evidence selection and numeric comparison are requirement-defined. Missing or malformed evidence remains unknown. No unit conversion, inference of customary requirements, task, carrier, consequence, or Clock authority is granted.',
    'directSignedInEndpoint',true
  ),now(),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry remains incomplete after person Goal claim-evidence evaluation registration.';
  end if;
end
$$;

commit;
