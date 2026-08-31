-- Atlas Person Goal Claim Evaluation v1
--
-- Resolves explicitly structured Goal requirements from current Claim/Evidence
-- truth without letting the application manufacture requirement satisfaction.
-- v1 supports one generic requirement kind: claim_threshold.
--
-- The accepted requirement itself must name the evidence subject, claim type,
-- allowed lifecycle/authority, numeric value path, comparison operator,
-- threshold, selection semantics, and (when relevant) unit path/unit. The
-- resolver contributes no 5K, running, health, task, carrier, or Clock knowledge.

begin;

create or replace function atlas.resolve_person_goal_claim_thresholds_v1(
  p_goal_packet jsonb,
  p_owner_user_id uuid,
  p_as_of timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_requirement jsonb;
  v_results jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_key text;
  v_kind text;
  v_rule jsonb;
  v_subject jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_claim_type text;
  v_selection text;
  v_operator text;
  v_threshold numeric;
  v_expected_unit text;
  v_value_path text[];
  v_unit_path text[];
  v_invalid_reason text;
  v_claim record;
  v_value_text text;
  v_value numeric;
  v_actual_unit text;
  v_matches integer;
  v_comparable integer;
  v_satisfying integer;
  v_state text;
  v_match_claim_ids jsonb;
  v_match_evidence_ids jsonb;
  v_comparable_claim_ids jsonb;
  v_satisfying_claim_ids jsonb;
  v_unit_mismatch_claim_ids jsonb;
  v_is_satisfied boolean;
begin
  if p_owner_user_id is null then
    raise exception 'owner user id is required.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'as-of time is required.' using errcode='22023';
  end if;
  if p_goal_packet is null
     or jsonb_typeof(p_goal_packet)<>'object'
     or p_goal_packet->>'contractVersion'<>'life_goal_packet_v1' then
    raise exception 'life_goal_packet_v1 is required.' using errcode='22023';
  end if;
  if coalesce(jsonb_typeof(p_goal_packet->'requirements'),'array')<>'array' then
    raise exception 'goal packet requirements must be an array.' using errcode='22023';
  end if;

  for v_requirement in
    select value from jsonb_array_elements(coalesce(p_goal_packet->'requirements','[]'::jsonb))
  loop
    v_index := v_index + 1;
    v_key := nullif(btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key','')),'');
    if v_key is null then
      v_key := concat_ws(':',
        p_goal_packet->'subject'->>'domain',
        p_goal_packet->'subject'->>'kind',
        p_goal_packet->'subject'->>'id',
        'goal_requirement',
        v_index::text
      );
    end if;

    v_kind := btrim(coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind',''));
    if v_kind <> 'claim_threshold' then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'requirementKey',v_key,
        'state','unknown',
        'detail',jsonb_build_object(
          'resolutionState','unsupported_requirement_kind',
          'requirementKind',nullif(v_kind,''),
          'resolverContract','person_goal_claim_threshold_resolution_v1',
          'asOf',p_as_of
        )
      ));
      continue;
    end if;

    v_rule := v_requirement->'claimThreshold';
    v_invalid_reason := null;
    v_value_path := null;
    v_unit_path := null;
    v_expected_unit := null;

    if coalesce(jsonb_typeof(v_rule),'')<>'object' then
      v_invalid_reason := 'claimThreshold_object_required';
    else
      v_subject := v_rule->'subject';
      if coalesce(jsonb_typeof(v_subject),'')<>'object' then
        v_invalid_reason := 'subject_object_required';
      else
        v_subject_domain := btrim(coalesce(v_subject->>'domain',''));
        v_subject_kind := btrim(coalesce(v_subject->>'kind',''));
        v_subject_id := btrim(coalesce(v_subject->>'id',''));
        if v_subject_domain='' or v_subject_kind='' or v_subject_id='' then
          v_invalid_reason := 'subject_identity_required';
        end if;
      end if;

      v_claim_type := btrim(coalesce(v_rule->>'claimType',''));
      if v_invalid_reason is null and v_claim_type='' then
        v_invalid_reason := 'claimType_required';
      end if;

      v_selection := btrim(coalesce(v_rule->>'selection',''));
      if v_invalid_reason is null and v_selection<>'any_current' then
        v_invalid_reason := 'selection_must_be_any_current';
      end if;

      if v_invalid_reason is null
         and (coalesce(jsonb_typeof(v_rule->'allowedLifecycleStates'),'')<>'array'
              or jsonb_array_length(v_rule->'allowedLifecycleStates')=0) then
        v_invalid_reason := 'allowedLifecycleStates_nonempty_array_required';
      end if;
      if v_invalid_reason is null and exists (
        select 1 from jsonb_array_elements_text(v_rule->'allowedLifecycleStates') s(value)
        where s.value not in ('reported','observed','accepted')
      ) then
        v_invalid_reason := 'allowedLifecycleStates_must_be_reported_observed_or_accepted';
      end if;

      if v_invalid_reason is null
         and (coalesce(jsonb_typeof(v_rule->'allowedAuthorityKinds'),'')<>'array'
              or jsonb_array_length(v_rule->'allowedAuthorityKinds')=0) then
        v_invalid_reason := 'allowedAuthorityKinds_nonempty_array_required';
      end if;

      if v_invalid_reason is null
         and (coalesce(jsonb_typeof(v_rule->'valuePath'),'')<>'array'
              or jsonb_array_length(v_rule->'valuePath')=0) then
        v_invalid_reason := 'valuePath_nonempty_array_required';
      end if;
      if v_invalid_reason is null and exists (
        select 1 from jsonb_array_elements_text(v_rule->'valuePath') p(value)
        where btrim(p.value)=''
      ) then
        v_invalid_reason := 'valuePath_segments_must_be_nonempty';
      end if;

      v_operator := btrim(coalesce(v_rule->>'operator',''));
      if v_invalid_reason is null and v_operator not in ('>=','>','<=','<','=') then
        v_invalid_reason := 'unsupported_numeric_operator';
      end if;

      if v_invalid_reason is null and coalesce(jsonb_typeof(v_rule->'threshold'),'')<>'number' then
        v_invalid_reason := 'numeric_threshold_required';
      end if;

      if v_invalid_reason is null then
        select array_agg(p.value order by p.ordinality)
        into v_value_path
        from jsonb_array_elements_text(v_rule->'valuePath') with ordinality p(value,ordinality);
        v_threshold := (v_rule->>'threshold')::numeric;
      end if;

      v_expected_unit := nullif(btrim(coalesce(v_rule->>'unit','')),'');
      if v_invalid_reason is null and v_expected_unit is not null then
        if coalesce(jsonb_typeof(v_rule->'unitPath'),'')<>'array'
           or jsonb_array_length(v_rule->'unitPath')=0 then
          v_invalid_reason := 'unitPath_nonempty_array_required_when_unit_is_set';
        elsif exists (
          select 1 from jsonb_array_elements_text(v_rule->'unitPath') p(value)
          where btrim(p.value)=''
        ) then
          v_invalid_reason := 'unitPath_segments_must_be_nonempty';
        else
          select array_agg(p.value order by p.ordinality)
          into v_unit_path
          from jsonb_array_elements_text(v_rule->'unitPath') with ordinality p(value,ordinality);
        end if;
      end if;
    end if;

    if v_invalid_reason is not null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'requirementKey',v_key,
        'state','unknown',
        'detail',jsonb_build_object(
          'resolutionState','invalid_claim_threshold_contract',
          'reason',v_invalid_reason,
          'resolverContract','person_goal_claim_threshold_resolution_v1',
          'asOf',p_as_of
        )
      ));
      continue;
    end if;

    v_matches := 0;
    v_comparable := 0;
    v_satisfying := 0;
    v_match_claim_ids := '[]'::jsonb;
    v_match_evidence_ids := '[]'::jsonb;
    v_comparable_claim_ids := '[]'::jsonb;
    v_satisfying_claim_ids := '[]'::jsonb;
    v_unit_mismatch_claim_ids := '[]'::jsonb;

    for v_claim in
      select c.id as claim_id,
             c.primary_evidence_id as evidence_id,
             c.value,
             c.recorded_at,
             c.lifecycle_state,
             c.authority_kind
      from atlas.claim_records c
      join atlas.evidence_records e on e.id=c.primary_evidence_id
      where c.scope_kind='person'
        and c.scope_id=p_owner_user_id
        and c.subject_domain=v_subject_domain
        and c.subject_kind=v_subject_kind
        and c.subject_id=v_subject_id
        and c.claim_type=v_claim_type
        and c.lifecycle_state not in ('superseded','expired')
        and exists (
          select 1 from jsonb_array_elements_text(v_rule->'allowedLifecycleStates') s(value)
          where s.value=c.lifecycle_state
        )
        and exists (
          select 1 from jsonb_array_elements_text(v_rule->'allowedAuthorityKinds') a(value)
          where a.value=c.authority_kind
        )
        and c.recorded_at<=p_as_of
        and (c.valid_from is null or c.valid_from<=p_as_of)
        and (c.valid_until is null or c.valid_until>=p_as_of)
        and e.scope_kind='person'
        and e.scope_id=p_owner_user_id
        and e.learned_at<=p_as_of
      order by c.recorded_at,c.id
    loop
      v_matches := v_matches + 1;
      v_match_claim_ids := v_match_claim_ids || jsonb_build_array(v_claim.claim_id);
      v_match_evidence_ids := v_match_evidence_ids || jsonb_build_array(v_claim.evidence_id);

      v_value_text := v_claim.value #>> v_value_path;
      if v_value_text is null
         or v_value_text !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' then
        continue;
      end if;

      if v_expected_unit is not null then
        v_actual_unit := v_claim.value #>> v_unit_path;
        if v_actual_unit is distinct from v_expected_unit then
          v_unit_mismatch_claim_ids := v_unit_mismatch_claim_ids || jsonb_build_array(v_claim.claim_id);
          continue;
        end if;
      end if;

      v_value := v_value_text::numeric;
      v_comparable := v_comparable + 1;
      v_comparable_claim_ids := v_comparable_claim_ids || jsonb_build_array(v_claim.claim_id);

      v_is_satisfied := case v_operator
        when '>=' then v_value>=v_threshold
        when '>'  then v_value>v_threshold
        when '<=' then v_value<=v_threshold
        when '<'  then v_value<v_threshold
        when '='  then v_value=v_threshold
        else false
      end;

      if v_is_satisfied then
        v_satisfying := v_satisfying + 1;
        v_satisfying_claim_ids := v_satisfying_claim_ids || jsonb_build_array(v_claim.claim_id);
      end if;
    end loop;

    v_state := case
      when v_satisfying>0 then 'satisfied'
      when v_comparable>0 then 'unmet'
      else 'unknown'
    end;

    v_results := v_results || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'requirementKey',v_key,
      'state',v_state,
      'detail',jsonb_strip_nulls(jsonb_build_object(
        'resolutionState','resolved_from_current_claims',
        'resolverContract','person_goal_claim_threshold_resolution_v1',
        'selection',v_selection,
        'operator',v_operator,
        'threshold',v_threshold,
        'unit',v_expected_unit,
        'matchedClaimCount',v_matches,
        'comparableClaimCount',v_comparable,
        'satisfyingClaimCount',v_satisfying,
        'matchedClaimIds',v_match_claim_ids,
        'comparableClaimIds',v_comparable_claim_ids,
        'satisfyingClaimIds',v_satisfying_claim_ids,
        'unitMismatchClaimIds',v_unit_mismatch_claim_ids,
        'asOf',p_as_of
      )),
      'source',jsonb_build_object(
        'kind','claim_evidence_envelope',
        'claimIds',v_match_claim_ids,
        'primaryEvidenceIds',v_match_evidence_ids,
        'scope',jsonb_build_object('kind','person','id',p_owner_user_id)
      )
    )));
  end loop;

  return v_results;
end;
$$;

comment on function atlas.resolve_person_goal_claim_thresholds_v1(jsonb,uuid,timestamptz) is
  'Internal evidence resolver for person Goal claim_threshold requirements. Requirement semantics are explicit in the accepted requirement; the resolver only matches current governed claims and performs the authorized numeric comparison.';

revoke all on function atlas.resolve_person_goal_claim_thresholds_v1(jsonb,uuid,timestamptz) from public, anon, authenticated;
grant execute on function atlas.resolve_person_goal_claim_thresholds_v1(jsonb,uuid,timestamptz) to service_role;

create or replace function atlas.evaluate_person_goal_from_current_claims_api_v1(
  p_definition_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_definition_kind text;
  v_definition_status text;
  v_packet jsonb;
  v_as_of timestamptz;
  v_results jsonb;
  v_evaluation jsonb;
  v_event_id uuid;
  v_existing_definition_id uuid;
  v_existing_event_kind text;
  v_existing_payload jsonb;
  v_existing_evidence jsonb;
  v_existing_evaluation jsonb;
  v_existing_occurred_at timestamptz;
  v_input_payload jsonb;
  v_evidence jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_definition_id is null then
    raise exception 'definitionId is required.' using errcode='22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;
  if (p_payload - 'sourceKey') <> '{}'::jsonb then
    raise exception 'Evidence-backed Goal evaluation v1 accepts sourceKey only; requirement results are resolved server-side.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key='' then
    raise exception 'sourceKey is required.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':goal-claim-eval:' || v_source_key,0));

  select e.id,e.definition_id,e.event_kind,e.input_payload,e.evidence,e.evaluation,e.occurred_at
  into v_event_id,v_existing_definition_id,v_existing_event_kind,v_existing_payload,
       v_existing_evidence,v_existing_evaluation,v_existing_occurred_at
  from atlas.person_life_state_events e
  where e.owner_user_id=v_user_id and e.source_key=v_source_key;

  if v_event_id is not null then
    if v_existing_definition_id is distinct from p_definition_id
       or v_existing_event_kind<>'goal_evaluation'
       or v_existing_payload->>'evaluationSource'<>'claim_evidence_resolver_v1' then
      raise exception 'sourceKey retry does not match existing evidence-backed Goal evaluation.' using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'replayed',true,
      'eventId',v_event_id,
      'definitionId',p_definition_id,
      'eventKind','goal_evaluation',
      'occurredAt',v_existing_occurred_at,
      'requirementResults',v_existing_payload->'requirementResults',
      'evidence',v_existing_evidence,
      'evaluation',v_existing_evaluation,
      'truthBoundary',jsonb_build_object(
        'requirementResultsResolvedServerSide',true,
        'currentClaimsOnly',true,
        'supersededClaimsExcluded',true,
        'evidenceProvenancePreserved',true,
        'doesNotCreateTask',true,
        'doesNotSelectCarrier',true,
        'doesNotCreateClockPlacement',true
      )
    );
  end if;

  select d.signal_kind,d.status,d.engine_packet
  into v_definition_kind,v_definition_status,v_packet
  from atlas.person_life_definitions d
  where d.id=p_definition_id and d.owner_user_id=v_user_id;

  if v_definition_kind is null then
    raise exception 'Person Goal definition not found for this user.' using errcode='42501';
  end if;
  if v_definition_kind<>'goal' or v_definition_status<>'active' then
    raise exception 'Evidence-backed Goal evaluation requires the active person Goal definition.' using errcode='22023';
  end if;

  v_as_of := now();
  v_results := atlas.resolve_person_goal_claim_thresholds_v1(v_packet,v_user_id,v_as_of);
  v_evaluation := atlas.evaluate_life_goal_state_v1(v_packet,v_results);

  v_input_payload := jsonb_build_object(
    'sourceKey',v_source_key,
    'eventKind','goal_evaluation',
    'evaluationSource','claim_evidence_resolver_v1',
    'asOf',v_as_of,
    'requirementResults',v_results
  );
  v_evidence := jsonb_build_object(
    'source','claim_evidence_envelope',
    'resolver','atlas.resolve_person_goal_claim_thresholds_v1',
    'asOf',v_as_of,
    'requirementResults',v_results
  );

  insert into atlas.person_life_state_events(
    definition_id,owner_user_id,event_kind,source_key,occurred_at,input_payload,evidence,evaluation
  ) values (
    p_definition_id,v_user_id,'goal_evaluation',v_source_key,v_as_of,v_input_payload,v_evidence,v_evaluation
  ) returning id into v_event_id;

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'eventId',v_event_id,
    'definitionId',p_definition_id,
    'eventKind','goal_evaluation',
    'occurredAt',v_as_of,
    'requirementResults',v_results,
    'evidence',v_evidence,
    'evaluation',v_evaluation,
    'truthBoundary',jsonb_build_object(
      'requirementResultsResolvedServerSide',true,
      'currentClaimsOnly',true,
      'supersededClaimsExcluded',true,
      'evidenceProvenancePreserved',true,
      'doesNotCreateTask',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.evaluate_person_goal_from_current_claims_api_v1(uuid,jsonb) is
  'Signed-in person Goal evaluation endpoint. The caller supplies only definitionId and sourceKey; requirement results are resolved from current governed Claim/Evidence truth and persisted through the ordinary Goal evaluation stream.';

revoke all on function atlas.evaluate_person_goal_from_current_claims_api_v1(uuid,jsonb) from public, anon;
grant execute on function atlas.evaluate_person_goal_from_current_claims_api_v1(uuid,jsonb) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values (
  'atlas.evaluate_person_goal_from_current_claims_api_v1(uuid, jsonb)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Evaluate the signed-in person active Goal from current governed Claim/Evidence truth without accepting caller-authored requirement results.',
    'authorizationBoundary','SECURITY DEFINER fixes owner scope to auth.uid(); caller supplies definitionId and sourceKey only. Requirement selectors and numeric comparison semantics come from the already-authorized Goal requirement definition.',
    'truthBoundary','Current non-superseded claim evidence may satisfy only explicitly structured claim_threshold requirements. Missing, incomparable, unsupported, or malformed evidence remains unknown; no task, carrier, consequence, or Clock authority is granted.',
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
    raise exception 'Authenticated RPC registry remains incomplete after person Goal claim evaluation registration.';
  end if;
end
$$;

commit;
