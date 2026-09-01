BEGIN;

-- Atlas Principal Decision Read Membrane v1
--
-- This migration exposes explicit Principal operational decisions through one
-- generic authenticated read contract. It does not claim complete decision
-- coverage, does not arbitrate the Clock, and does not execute domain commands.

create table if not exists atlas.principal_decision_adapter_registry (
  adapter_key text primary key,
  source_system text not null,
  source_type text not null,
  escalation_kind text not null,
  active boolean not null default true,
  evidence jsonb not null default '{}'::jsonb,
  registered_at timestamptz not null default now(),
  unique(source_system,source_type,escalation_kind)
);

revoke all on table atlas.principal_decision_adapter_registry from public,anon,authenticated,service_role;

insert into atlas.principal_decision_adapter_registry(
  adapter_key,source_system,source_type,escalation_kind,active,evidence
) values (
  'flower_demand_sale_v1',
  'flower_commerce',
  'flower_demand_order',
  'sale_commitment_decision',
  true,
  jsonb_build_object(
    'contract','flower_demand_sale_principal_decision_v1',
    'purpose','Require canonical Demand -> Sale readiness in addition to explicit Principal admission.',
    'truthBoundary',jsonb_build_object(
      'specializedAdapterMayFurtherContainAnAdmittedEscalation',true,
      'genericReadMembraneDoesNotBypassDomainTransitionReadiness',true
    )
  )
)
on conflict (adapter_key) do update set
  source_system=excluded.source_system,
  source_type=excluded.source_type,
  escalation_kind=excluded.escalation_kind,
  active=excluded.active,
  evidence=excluded.evidence;

create or replace function atlas.dispatch_principal_decision_adapter_v1(
  p_adapter_key text,
  p_escalation jsonb
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_source_id uuid;
begin
  if p_adapter_key is null or btrim(p_adapter_key)='' then
    return jsonb_build_object(
      'contractVersion','principal_decision_adapter_dispatch_v1',
      'state','translation_required',
      'candidate',null,
      'missingFields',jsonb_build_array('adapterKey')
    );
  end if;
  if p_escalation is null or jsonb_typeof(p_escalation)<>'object' then
    raise exception 'Principal decision adapter escalation must be an object.' using errcode='22023';
  end if;

  case p_adapter_key
    when 'flower_demand_sale_v1' then
      begin
        v_source_id:=(p_escalation->>'source_id')::uuid;
      exception when invalid_text_representation then
        return jsonb_build_object(
          'contractVersion','principal_decision_adapter_dispatch_v1',
          'state','translation_required',
          'candidate',null,
          'missingFields',jsonb_build_array('valid flower_demand_order source_id'),
          'adapterKey',p_adapter_key
        );
      end;
      return atlas.flower_demand_sale_principal_decision_v1(v_source_id)
        ||jsonb_build_object('dispatchContract','principal_decision_adapter_dispatch_v1');
    else
      return jsonb_build_object(
        'contractVersion','principal_decision_adapter_dispatch_v1',
        'state','translation_required',
        'candidate',null,
        'missingFields',jsonb_build_array('registered dispatch implementation: '||p_adapter_key),
        'adapterKey',p_adapter_key,
        'truthBoundary',jsonb_build_object('unknownAdapterNeverFallsThroughToGuessedDomainSemantics',true)
      );
  end case;
end;
$function$;

revoke all on function atlas.dispatch_principal_decision_adapter_v1(text,jsonb) from public,anon,authenticated,service_role;

create or replace function atlas.principal_decision_packet_from_operational_escalation_v1(
  p_escalation_id uuid
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_e atlas.operational_escalations%rowtype;
  v_adapter atlas.principal_decision_adapter_registry%rowtype;
  v_org_id uuid;
  v_decision_kind text;
  v_command jsonb;
  v_packet jsonb;
begin
  select * into v_e
  from atlas.operational_escalations e
  where e.id=p_escalation_id;

  if v_e.id is null then
    return jsonb_build_object(
      'contractVersion','principal_operational_decision_adapter_v1',
      'state','missing_source',
      'escalationId',p_escalation_id,
      'candidate',null
    );
  end if;

  if v_e.status in ('resolved','dismissed') then
    v_packet:=jsonb_build_object(
      'principalId',v_e.principal_id,
      'source',jsonb_build_object(
        'domain',v_e.source_system,
        'kind',v_e.source_type,
        'id',v_e.source_id,
        'state',v_e.current_state
      ),
      'authority',jsonb_build_object('principalRequired',true,'basis','operational_escalation:'||v_e.id::text),
      'admission',jsonb_build_object(
        'state','established',
        'basis',v_e.threshold_crossed,
        'consequence',v_e.consequence,
        'reasonForFloor',v_e.reason_for_floor
      ),
      'resolution',jsonb_build_object('state','resolved','sourceKind','operational_escalation_status','sourceId',v_e.id),
      'decision',jsonb_build_object(
        'kind',coalesce(nullif(v_e.metadata->>'decisionKind',''),v_e.escalation_kind),
        'prompt',v_e.owner_decision_required,
        'options',v_e.options_json
      )
    );
    return atlas.evaluate_principal_decision_packet_v1(v_packet)
      ||jsonb_build_object('adapterContract','principal_operational_decision_adapter_v1','escalationId',v_e.id);
  end if;

  if v_e.status not in ('open','acknowledged') then
    return jsonb_build_object(
      'contractVersion','principal_operational_decision_adapter_v1',
      'state','translation_required',
      'candidate',null,
      'escalationId',v_e.id,
      'missingFields',jsonb_build_array('supported operational escalation status'),
      'truthBoundary',jsonb_build_object('unknownEscalationStateDoesNotBecomeOutstandingDecision',true)
    );
  end if;

  select * into v_adapter
  from atlas.principal_decision_adapter_registry r
  where r.source_system=v_e.source_system
    and r.source_type=v_e.source_type
    and r.escalation_kind=v_e.escalation_kind
    and r.active
  limit 1;

  if v_adapter.adapter_key is not null then
    return atlas.dispatch_principal_decision_adapter_v1(v_adapter.adapter_key,to_jsonb(v_e))
      ||jsonb_build_object(
        'readAdapterContract','principal_operational_decision_adapter_v1',
        'adapterKey',v_adapter.adapter_key,
        'escalationId',v_e.id
      );
  end if;

  if v_e.portfolio_unit_id is not null then
    select u.organization_id into v_org_id
    from atlas.portfolio_units u
    where u.id=v_e.portfolio_unit_id;
  end if;

  v_decision_kind:=coalesce(nullif(v_e.metadata->>'decisionKind',''),v_e.escalation_kind);
  v_command:=case
    when jsonb_typeof(v_e.metadata->'principalCommand')='object' then v_e.metadata->'principalCommand'
    else null
  end;

  v_packet:=jsonb_build_object(
    'principalId',v_e.principal_id,
    'scope',jsonb_strip_nulls(jsonb_build_object(
      'kind',case when v_e.portfolio_unit_id is null then 'principal' else 'portfolio_unit' end,
      'portfolioUnitId',v_e.portfolio_unit_id,
      'organizationId',v_org_id
    )),
    'source',jsonb_build_object(
      'domain',v_e.source_system,
      'kind',v_e.source_type,
      'id',v_e.source_id,
      'state',v_e.current_state
    ),
    'authority',jsonb_build_object(
      'principalRequired',true,
      'basis','operational_escalation:'||v_e.id::text
    ),
    'admission',jsonb_build_object(
      'state','established',
      'basis',v_e.threshold_crossed,
      'consequence',v_e.consequence,
      'reasonForFloor',v_e.reason_for_floor,
      'escalationId',v_e.id
    ),
    'resolution',jsonb_build_object(
      'state','unresolved',
      'sourceKind','operational_escalation_status',
      'sourceId',v_e.id
    ),
    'decision',jsonb_strip_nulls(jsonb_build_object(
      'kind',v_decision_kind,
      'prompt',v_e.owner_decision_required,
      'options',v_e.options_json,
      'command',v_command
    )),
    'timing',jsonb_strip_nulls(jsonb_build_object(
      'windowStart',v_e.window_start,
      'windowEnd',v_e.window_end,
      'expectedPrincipalMinutes',v_e.expected_owner_minutes,
      'floorClass',v_e.floor_class,
      'protectionLevel',v_e.protection_level,
      'interruptibility',v_e.interruptibility
    )),
    'presentation',jsonb_build_object(
      'title',coalesce(nullif(v_e.metadata->>'principalTitle',''),initcap(replace(v_e.escalation_kind,'_',' ')))
    ),
    'metadata',jsonb_build_object(
      'adapterContract','principal_operational_decision_adapter_v1',
      'operationalEscalationId',v_e.id,
      'operationalEscalationStatus',v_e.status,
      'severity',v_e.severity,
      'horizon',v_e.horizon,
      'sourceMetadata',v_e.metadata
    )
  );

  return atlas.evaluate_principal_decision_packet_v1(v_packet)
    ||jsonb_build_object('adapterContract','principal_operational_decision_adapter_v1','escalationId',v_e.id);
end;
$function$;

revoke all on function atlas.principal_decision_packet_from_operational_escalation_v1(uuid) from public,anon,authenticated,service_role;

create or replace function atlas.principal_decision_packets_api_v1()
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal_id uuid;
  v_e record;
  v_doc jsonb;
  v_candidates jsonb:='[]'::jsonb;
  v_translation jsonb:='[]'::jsonb;
  v_contained jsonb:='[]'::jsonb;
  v_resolved jsonb:='[]'::jsonb;
  v_source_count integer:=0;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_decision_packets_api_v1',
      'state','principal_required',
      'coverageState','principal_required',
      'coverageMode','no_principal_context',
      'completeFieldClaim',false,
      'candidates','[]'::jsonb,
      'translationRequired','[]'::jsonb,
      'truthBoundary',jsonb_build_object('noPrincipalContextNeverFallsBackToCrossPrincipalData',true)
    );
  end if;

  for v_e in
    select e.id
    from atlas.operational_escalations e
    where e.principal_id=v_principal_id
      and e.status in ('open','acknowledged')
    order by e.floor_class,e.window_end nulls last,e.updated_at,e.id
  loop
    v_source_count:=v_source_count+1;
    v_doc:=atlas.principal_decision_packet_from_operational_escalation_v1(v_e.id);
    case v_doc->>'state'
      when 'candidate' then v_candidates:=v_candidates||jsonb_build_array(v_doc->'candidate');
      when 'translation_required' then v_translation:=v_translation||jsonb_build_array(v_doc);
      when 'contained' then v_contained:=v_contained||jsonb_build_array(v_doc);
      when 'resolved' then v_resolved:=v_resolved||jsonb_build_array(v_doc);
      else v_translation:=v_translation||jsonb_build_array(v_doc||jsonb_build_object('readMembraneIssue','unsupported_adapter_state'));
    end case;
  end loop;

  return jsonb_build_object(
    'contractVersion','principal_decision_packets_api_v1',
    'state','ready',
    'principalId',v_principal_id,
    'coverageState','partial',
    'coverageMode','explicit_operational_escalations_v1',
    'completeFieldClaim',false,
    'sourceCount',v_source_count,
    'candidateCount',jsonb_array_length(v_candidates),
    'translationRequiredCount',jsonb_array_length(v_translation),
    'containedCount',jsonb_array_length(v_contained),
    'sourceResolvedCount',jsonb_array_length(v_resolved),
    'candidates',v_candidates,
    'translationRequired',v_translation,
    'contained',v_contained,
    'sourceResolved',v_resolved,
    'truthBoundary',jsonb_build_object(
      'includedSourceClass','explicit_operational_escalations',
      'partialCoverageDoesNotProveNoOtherPrincipalDecisionExists',true,
      'operationalEscalationEstablishesAdmissionNotDomainTruth',true,
      'specializedAdaptersMayFurtherContainAClaim',true,
      'decisionFeedDoesNotArbitrateClock',true,
      'decisionFeedDoesNotExecuteCommands',true,
      'decisionFeedDoesNotCreateCommitments',true,
      'domainResolutionRemainsSourceOwned',true,
      'notebookMayConsumeThisProjectionWithoutReadingDomainTables',true
    )
  );
end;
$function$;

revoke all on function atlas.principal_decision_packets_api_v1() from public,anon,authenticated,service_role;
grant execute on function atlas.principal_decision_packets_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.principal_decision_packets_api_v1()',
  'app_endpoint','verified','active',
  true,true,true,
  0,0,
  jsonb_build_object(
    'purpose','Return explicitly admitted Principal operational decisions as generic decision packets.',
    'boundary','Authenticated Principal identity only; partial explicit-operational-escalation coverage; no Clock arbitration or domain mutation.',
    'contract','principal_decision_packets_api_v1',
    'coverageMode','explicit_operational_escalations_v1',
    'completeFieldClaim',false,
    'publicInheritanceRemoved',true
  ),
  now(),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

-- Deployment-time structural proofs.
do $proof$
declare
  v_adapter_count integer;
  v_drift_count integer;
begin
  select count(*) into v_adapter_count
  from atlas.principal_decision_adapter_registry r
  where r.adapter_key='flower_demand_sale_v1'
    and r.source_system='flower_commerce'
    and r.source_type='flower_demand_order'
    and r.escalation_kind='sale_commitment_decision'
    and r.active;
  if v_adapter_count<>1 then
    raise exception 'Principal decision read proof failed: flower adapter registration missing or ambiguous.';
  end if;

  if has_function_privilege('authenticated','atlas.dispatch_principal_decision_adapter_v1(text,jsonb)','EXECUTE') then
    raise exception 'Principal decision read proof failed: internal dispatch is authenticated-executable.';
  end if;
  if has_function_privilege('authenticated','atlas.principal_decision_packet_from_operational_escalation_v1(uuid)','EXECUTE') then
    raise exception 'Principal decision read proof failed: internal adapter is authenticated-executable.';
  end if;
  if not has_function_privilege('authenticated','atlas.principal_decision_packets_api_v1()','EXECUTE') then
    raise exception 'Principal decision read proof failed: authenticated read API is not executable.';
  end if;
  if has_function_privilege('anon','atlas.principal_decision_packets_api_v1()','EXECUTE') then
    raise exception 'Principal decision read proof failed: anonymous read access leaked.';
  end if;

  select count(*) into v_drift_count
  from atlas.authenticated_rpc_registry_drift_v1()
  where signature in (
    'atlas.principal_decision_packets_api_v1()',
    'atlas.dispatch_principal_decision_adapter_v1(text, jsonb)',
    'atlas.principal_decision_packet_from_operational_escalation_v1(uuid)'
  );
  if v_drift_count<>0 then
    raise exception 'Principal decision read proof failed: authenticated RPC registry drift detected.';
  end if;
end;
$proof$;

COMMIT;
