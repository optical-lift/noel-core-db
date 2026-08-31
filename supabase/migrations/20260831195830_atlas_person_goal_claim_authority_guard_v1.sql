-- Atlas Person Goal Claim Authority Guard v1
--
-- Hardens the claim-threshold resolver introduced immediately before this
-- migration. A Goal requirement may contribute a governing requirement result
-- only while the exact person-accepted goal_requirement claim that authorized
-- that immutable Goal version remains current.
--
-- If the authorization claim is later corrected/superseded, the active Goal
-- version does not silently inherit the replacement requirement. Its result
-- becomes unknown until an explicit Goal revision creates the next version.

begin;

create or replace function atlas.resolve_person_goal_authorized_claim_thresholds_v1(
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
  v_raw_results jsonb;
  v_requirement jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_key text;
  v_authorization jsonb;
  v_claim_id uuid;
  v_evidence_id uuid;
  v_claim_value jsonb;
  v_claim_primary_evidence_id uuid;
  v_claim_state text;
  v_claim_authority text;
  v_claim_subject_domain text;
  v_claim_subject_kind text;
  v_claim_subject_id text;
  v_goal_subject_domain text;
  v_goal_subject_kind text;
  v_goal_subject_id text;
  v_reason text;
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
  if p_goal_packet->'scope'->>'kind'<>'person'
     or p_goal_packet->'scope'->>'id'<>p_owner_user_id::text then
    raise exception 'Goal packet scope must match person custody.' using errcode='42501';
  end if;

  v_goal_subject_domain := btrim(coalesce(p_goal_packet->'subject'->>'domain',''));
  v_goal_subject_kind := btrim(coalesce(p_goal_packet->'subject'->>'kind',''));
  v_goal_subject_id := btrim(coalesce(p_goal_packet->'subject'->>'id',''));

  v_raw_results := atlas.resolve_person_goal_claim_thresholds_v1(
    p_goal_packet,
    p_owner_user_id,
    p_as_of
  );

  for v_requirement in
    select value from jsonb_array_elements(coalesce(p_goal_packet->'requirements','[]'::jsonb))
  loop
    v_index := v_index + 1;
    v_key := nullif(btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key','')),'');
    if v_key is null then
      v_key := concat_ws(':',
        v_goal_subject_domain,
        v_goal_subject_kind,
        v_goal_subject_id,
        'goal_requirement',
        v_index::text
      );
    end if;

    v_result := null;
    select value into v_result
    from jsonb_array_elements(v_raw_results)
    where value->>'requirementKey'=v_key
    limit 1;

    v_authorization := null;
    v_claim_id := null;
    v_evidence_id := null;
    v_claim_value := null;
    v_claim_primary_evidence_id := null;
    v_claim_state := null;
    v_claim_authority := null;
    v_claim_subject_domain := null;
    v_claim_subject_kind := null;
    v_claim_subject_id := null;
    v_reason := null;

    v_authorization := v_requirement->'authorization';
    if jsonb_typeof(v_authorization)<>'object'
       or v_authorization->>'basis'<>'person_accepted_goal_requirement_claim' then
      v_reason := 'missing_person_accepted_requirement_authorization';
    elsif coalesce(v_authorization->>'claimId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(v_authorization->>'evidenceId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_reason := 'invalid_requirement_authorization_reference';
    else
      v_claim_id := (v_authorization->>'claimId')::uuid;
      v_evidence_id := (v_authorization->>'evidenceId')::uuid;

      select c.value,c.primary_evidence_id,c.lifecycle_state,c.authority_kind,
             c.subject_domain,c.subject_kind,c.subject_id
      into v_claim_value,v_claim_primary_evidence_id,v_claim_state,v_claim_authority,
           v_claim_subject_domain,v_claim_subject_kind,v_claim_subject_id
      from atlas.claim_records c
      where c.id=v_claim_id
        and c.scope_kind='person'
        and c.scope_id=p_owner_user_id
        and c.claim_type='goal_requirement'
        and c.recorded_at<=p_as_of
        and (c.valid_from is null or c.valid_from<=p_as_of)
        and (c.valid_until is null or c.valid_until>=p_as_of);

      if v_claim_value is null then
        v_reason := 'requirement_authorization_claim_not_found';
      elsif v_claim_state<>'accepted' or v_claim_authority<>'person_acceptance' then
        v_reason := 'requirement_authorization_claim_is_not_current_acceptance';
      elsif v_claim_primary_evidence_id is distinct from v_evidence_id then
        v_reason := 'requirement_authorization_evidence_mismatch';
      elsif v_claim_subject_domain is distinct from v_goal_subject_domain
         or v_claim_subject_kind is distinct from v_goal_subject_kind
         or v_claim_subject_id is distinct from v_goal_subject_id then
        v_reason := 'requirement_authorization_subject_mismatch';
      elsif v_claim_value is distinct from (v_requirement - 'authorization') then
        v_reason := 'requirement_authorization_value_mismatch';
      end if;
    end if;

    if v_reason is not null then
      v_results := v_results || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'requirementKey',v_key,
        'state','unknown',
        'detail',jsonb_build_object(
          'resolutionState','requirement_authorization_not_current',
          'reason',v_reason,
          'resolverContract','person_goal_authorized_claim_threshold_resolution_v1',
          'asOf',p_as_of
        ),
        'source',jsonb_strip_nulls(jsonb_build_object(
          'kind','goal_requirement_authorization',
          'claimId',v_claim_id,
          'primaryEvidenceId',v_evidence_id,
          'scope',jsonb_build_object('kind','person','id',p_owner_user_id)
        ))
      )));
      continue;
    end if;

    if v_result is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'requirementKey',v_key,
        'state','unknown',
        'detail',jsonb_build_object(
          'resolutionState','claim_threshold_result_missing',
          'resolverContract','person_goal_authorized_claim_threshold_resolution_v1',
          'asOf',p_as_of
        ),
        'source',jsonb_build_object(
          'kind','goal_requirement_authorization',
          'claimId',v_claim_id,
          'primaryEvidenceId',v_evidence_id,
          'scope',jsonb_build_object('kind','person','id',p_owner_user_id)
        )
      ));
      continue;
    end if;

    v_results := v_results || jsonb_build_array(
      jsonb_set(
        jsonb_set(
          v_result,
          '{detail}',
          coalesce(v_result->'detail','{}'::jsonb) || jsonb_build_object(
            'authorizationState','current_person_acceptance',
            'authorizationClaimId',v_claim_id,
            'authorizationEvidenceId',v_evidence_id,
            'authorizedResolverContract','person_goal_authorized_claim_threshold_resolution_v1'
          ),
          true
        ),
        '{source}',
        coalesce(v_result->'source','{}'::jsonb) || jsonb_build_object(
          'requirementAuthorization',jsonb_build_object(
            'basis','person_accepted_goal_requirement_claim',
            'claimId',v_claim_id,
            'primaryEvidenceId',v_evidence_id
          )
        ),
        true
      )
    );
  end loop;

  return v_results;
end;
$$;

comment on function atlas.resolve_person_goal_authorized_claim_thresholds_v1(jsonb,uuid,timestamptz) is
  'Authority wrapper around person Goal claim-threshold resolution. The exact person-accepted goal_requirement claim embedded by Goal revision must still be current at evaluation time; otherwise the requirement result is unknown.';

revoke all on function atlas.resolve_person_goal_authorized_claim_thresholds_v1(jsonb,uuid,timestamptz) from public, anon, authenticated;
grant execute on function atlas.resolve_person_goal_authorized_claim_thresholds_v1(jsonb,uuid,timestamptz) to service_role;

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
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_definition_id is null then raise exception 'definitionId is required.' using errcode='22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;
  if (p_payload - 'sourceKey') <> '{}'::jsonb then
    raise exception 'Evidence-backed Goal evaluation v1 accepts sourceKey only; requirement results are resolved server-side.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key='' then raise exception 'sourceKey is required.' using errcode='22023'; end if;

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
        'requirementAuthorizationMustRemainCurrent',true,
        'currentClaimsOnly',true,
        'supersededClaimsExcluded',true,
        'evidenceProvenancePreserved',true,
        'unitConversionAuthority',false,
        'doesNotCreateTask',true,
        'doesNotSelectCarrier',true,
        'doesNotCreateConsequence',true,
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
  v_results := atlas.resolve_person_goal_authorized_claim_thresholds_v1(v_packet,v_user_id,v_as_of);
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
    'resolver','atlas.resolve_person_goal_authorized_claim_thresholds_v1',
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
      'requirementAuthorizationMustRemainCurrent',true,
      'currentClaimsOnly',true,
      'supersededClaimsExcluded',true,
      'evidenceProvenancePreserved',true,
      'unitConversionAuthority',false,
      'doesNotCreateTask',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.evaluate_person_goal_from_current_claims_api_v1(uuid,jsonb) is
  'Signed-in person Goal evaluation endpoint. Caller supplies sourceKey only. Requirement results are resolved from current governed Claim/Evidence truth and remain governing only while the exact person-accepted requirement authorization claim is current.';

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
    'authorizationBoundary','SECURITY DEFINER fixes owner scope to auth.uid(); caller supplies definitionId and sourceKey only. Each Goal requirement must still be backed by the exact current person-accepted goal_requirement claim embedded by the Goal revision membrane.',
    'truthBoundary','Current non-superseded claim evidence may satisfy only explicitly structured claim_threshold requirements whose authorization remains current. Missing, incomparable, unsupported, malformed, stale, or superseded authority remains unknown; no unit conversion, task, carrier, consequence, or Clock authority is granted.',
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
    raise exception 'Authenticated RPC registry remains incomplete after Goal requirement authorization guard.';
  end if;
end
$$;

commit;
