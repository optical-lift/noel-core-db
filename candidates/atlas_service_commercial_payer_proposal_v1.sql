begin;

create or replace function atlas.propose_atlas_service_item_payer_service_v1(
  p_item_id uuid,
  p_payer_profile_id uuid,
  p_proposal_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_item atlas.atlas_service_commercial_composition_items%rowtype;
  v_payer atlas.atlas_service_payer_profiles%rowtype;
  v_resp atlas.atlas_service_item_payer_responsibilities%rowtype;
begin
  if p_proposal_evidence is null
     or jsonb_typeof(p_proposal_evidence)<>'object' then
    raise exception 'Payer proposal evidence must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_item
  from atlas.atlas_service_commercial_composition_items
  where id=p_item_id;

  if v_item.id is null then
    raise exception 'Commercial Composition Item not found.'
      using errcode='P0002';
  end if;

  if v_item.state not in ('candidate','proposed','elected','settlement_ready') then
    raise exception 'Payer may be proposed only for unsettled commercial items.'
      using errcode='23514';
  end if;

  select * into v_payer
  from atlas.atlas_service_payer_profiles
  where id=p_payer_profile_id
    and status='active';

  if v_payer.id is null
     or v_payer.composition_id<>v_item.composition_id then
    raise exception 'Active payer must belong to the same Commercial Composition.'
      using errcode='23514';
  end if;

  select * into v_resp
  from atlas.atlas_service_item_payer_responsibilities
  where composition_item_id=v_item.id
    and payer_profile_id=v_payer.id
    and state='proposed'
  limit 1;

  if v_resp.id is null then
    insert into atlas.atlas_service_item_payer_responsibilities(
      composition_item_id,payer_profile_id,state,metadata
    ) values(
      v_item.id,v_payer.id,'proposed',
      jsonb_build_object('proposalEvidence',p_proposal_evidence)
    )
    returning * into v_resp;
  end if;

  return jsonb_build_object(
    'itemId',v_item.id,
    'payerProfileId',v_payer.id,
    'payerResponsibilityId',v_resp.id,
    'payerState',v_resp.state,
    'itemState',v_item.state
  );
end;
$function$;

revoke all on function atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'atlas_service_payer_responsibility',
  'atlas_service_commerce',
  'Who has accepted financial responsibility for an elected Atlas service commercial item?',
  'atlas_service_payer_profiles + atlas_service_item_payer_responsibilities',
  'incomplete',
  array[
    'atlas.atlas_service_payer_profiles',
    'atlas.atlas_service_item_payer_responsibilities'
  ],
  array[
    'atlas.ensure_atlas_service_payer_profile_service_v1',
    'atlas.propose_atlas_service_item_payer_service_v1',
    'atlas.accept_atlas_service_item_payer_service_v1'
  ],
  array[]::text[],
  array[]::text[],
  array[]::text[],
  'Billing identity is commercial evidence and must not silently establish Person, Principal, Organization, setup sponsor, institutional authority, or payer acceptance.',
  'Preserves proposed payer responsibility separately from accepted financial responsibility and from Atlas/institutional identity.',
  now()
)
on conflict(authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.propose_atlas_service_item_payer_service_v1(uuid,uuid,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  jsonb_build_object(
    'source','atlas_service_commercial_payer_proposal_v1',
    'purpose','Record a proposed payer relationship without accepting financial responsibility or making an item settlement-ready.',
    'truthBoundary','Payer proposal is commercial context only; it does not establish payer acceptance, settlement authority, identity, purchase, or entitlement.',
    'classificationRuleVersion',3
  ),
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
