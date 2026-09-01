BEGIN;

-- Atlas Principal Decision Packet v1
--
-- Trust boundary:
--   domain truth remains domain-owned;
--   an unresolved fact does not automatically become Principal work;
--   Principal admission must already be warranted by explicit authority,
--   threshold, window, consequence, or other source-backed jurisdiction;
--   the generic packet may describe a canonical command but never executes it;
--   resolution is supplied by canonical source truth, not by a notebook card.

create or replace function atlas.evaluate_principal_decision_packet_v1(p_packet jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_principal_id text;
  v_source_domain text;
  v_source_kind text;
  v_source_id text;
  v_decision_kind text;
  v_prompt text;
  v_resolution_state text;
  v_admission_state text;
  v_principal_required boolean;
  v_authority_basis text;
  v_admission_basis text;
  v_consequence text;
  v_reason_for_floor text;
  v_command jsonb;
  v_missing jsonb := '[]'::jsonb;
  v_candidate_key text;
begin
  if p_packet is null or jsonb_typeof(p_packet) <> 'object' then
    raise exception 'Principal decision packet must be a JSON object.' using errcode='22023';
  end if;

  v_principal_id:=nullif(btrim(p_packet->>'principalId'),'');
  v_source_domain:=nullif(btrim(p_packet#>>'{source,domain}'),'');
  v_source_kind:=nullif(btrim(p_packet#>>'{source,kind}'),'');
  v_source_id:=nullif(btrim(p_packet#>>'{source,id}'),'');
  v_decision_kind:=nullif(btrim(p_packet#>>'{decision,kind}'),'');
  v_prompt:=nullif(btrim(p_packet#>>'{decision,prompt}'),'');
  v_resolution_state:=lower(coalesce(nullif(btrim(p_packet#>>'{resolution,state}'),''),'unknown'));
  v_admission_state:=lower(coalesce(nullif(btrim(p_packet#>>'{admission,state}'),''),'unknown'));
  v_principal_required:=coalesce((p_packet#>>'{authority,principalRequired}')::boolean,false);
  v_authority_basis:=nullif(btrim(p_packet#>>'{authority,basis}'),'');
  v_admission_basis:=nullif(btrim(p_packet#>>'{admission,basis}'),'');
  v_consequence:=nullif(btrim(p_packet#>>'{admission,consequence}'),'');
  v_reason_for_floor:=nullif(btrim(p_packet#>>'{admission,reasonForFloor}'),'');
  v_command:=case when jsonb_typeof(p_packet#>'{decision,command}')='object' then p_packet#>'{decision,command}' else null end;

  if v_resolution_state not in ('unresolved','resolved','unknown') then
    raise exception 'Principal decision resolution state must be unresolved, resolved, or unknown.' using errcode='22023';
  end if;
  if v_admission_state not in ('established','not_established','unknown') then
    raise exception 'Principal decision admission state must be established, not_established, or unknown.' using errcode='22023';
  end if;

  if v_source_domain is null then v_missing:=v_missing||jsonb_build_array('source.domain'); end if;
  if v_source_kind is null then v_missing:=v_missing||jsonb_build_array('source.kind'); end if;
  if v_source_id is null then v_missing:=v_missing||jsonb_build_array('source.id'); end if;

  if jsonb_array_length(v_missing)>0 then
    return jsonb_build_object(
      'contractVersion','principal_decision_packet_v1',
      'state','translation_required',
      'missingFields',v_missing,
      'candidate',null,
      'truthBoundary',jsonb_build_object(
        'canonicalSourceIdentityRequired',true,
        'genericLayerDoesNotInventSourceIdentity',true
      )
    );
  end if;

  if v_resolution_state='resolved' then
    return jsonb_build_object(
      'contractVersion','principal_decision_packet_v1',
      'state','resolved',
      'source',p_packet->'source',
      'resolution',p_packet->'resolution',
      'candidate',null,
      'truthBoundary',jsonb_build_object(
        'resolutionComesFromCanonicalSource',true,
        'resolvedSourceDoesNotRemainPrincipalWork',true
      )
    );
  end if;

  if v_resolution_state='unknown' then
    return jsonb_build_object(
      'contractVersion','principal_decision_packet_v1',
      'state','translation_required',
      'source',p_packet->'source',
      'missingFields',jsonb_build_array('resolution.state'),
      'candidate',null,
      'truthBoundary',jsonb_build_object(
        'unknownResolutionDoesNotBecomeUnresolvedByAssumption',true
      )
    );
  end if;

  if not v_principal_required or v_admission_state='not_established' then
    return jsonb_build_object(
      'contractVersion','principal_decision_packet_v1',
      'state','contained',
      'source',p_packet->'source',
      'candidate',null,
      'reason',case when not v_principal_required then 'Principal responsibility is not established.' else 'The source has not earned Principal admission.' end,
      'truthBoundary',jsonb_build_object(
        'unresolvedDoesNotMeanPrincipalWork',true,
        'delegatedWorkRemainsContainedWithoutExplicitAdmission',true
      )
    );
  end if;

  if v_admission_state='unknown' then
    return jsonb_build_object(
      'contractVersion','principal_decision_packet_v1',
      'state','translation_required',
      'source',p_packet->'source',
      'missingFields',jsonb_build_array('admission.state'),
      'candidate',null,
      'truthBoundary',jsonb_build_object(
        'unknownAdmissionDoesNotEarnRightToFloor',true
      )
    );
  end if;

  v_missing:='[]'::jsonb;
  if v_principal_id is null then v_missing:=v_missing||jsonb_build_array('principalId'); end if;
  if v_decision_kind is null then v_missing:=v_missing||jsonb_build_array('decision.kind'); end if;
  if v_prompt is null then v_missing:=v_missing||jsonb_build_array('decision.prompt'); end if;
  if v_authority_basis is null then v_missing:=v_missing||jsonb_build_array('authority.basis'); end if;
  if v_admission_basis is null then v_missing:=v_missing||jsonb_build_array('admission.basis'); end if;
  if v_consequence is null then v_missing:=v_missing||jsonb_build_array('admission.consequence'); end if;
  if v_reason_for_floor is null then v_missing:=v_missing||jsonb_build_array('admission.reasonForFloor'); end if;

  if v_command is not null then
    if nullif(btrim(v_command->>'kind'),'') is null then v_missing:=v_missing||jsonb_build_array('decision.command.kind'); end if;
    if nullif(btrim(v_command->>'targetKind'),'') is null then v_missing:=v_missing||jsonb_build_array('decision.command.targetKind'); end if;
    if nullif(btrim(v_command->>'targetId'),'') is null then v_missing:=v_missing||jsonb_build_array('decision.command.targetId'); end if;
  end if;

  if jsonb_array_length(v_missing)>0 then
    return jsonb_build_object(
      'contractVersion','principal_decision_packet_v1',
      'state','translation_required',
      'source',p_packet->'source',
      'missingFields',v_missing,
      'candidate',null,
      'truthBoundary',jsonb_build_object(
        'principalTranslationMustBeComplete',true,
        'rawDomainVocabularyDoesNotBecomePrincipalUIByDefault',true
      )
    );
  end if;

  v_candidate_key:='principal_decision:'||v_source_domain||':'||v_source_kind||':'||v_source_id||':'||v_decision_kind;

  return jsonb_build_object(
    'contractVersion','principal_decision_packet_v1',
    'state','candidate',
    'candidate',jsonb_strip_nulls(jsonb_build_object(
      'candidateKey',v_candidate_key,
      'principalId',v_principal_id,
      'scope',p_packet->'scope',
      'source',p_packet->'source',
      'decisionKind',v_decision_kind,
      'prompt',v_prompt,
      'options',case when jsonb_typeof(p_packet#>'{decision,options}')='array' then p_packet#>'{decision,options}' else '[]'::jsonb end,
      'command',v_command,
      'authority',p_packet->'authority',
      'admission',p_packet->'admission',
      'resolution',p_packet->'resolution',
      'timing',p_packet->'timing',
      'presentation',p_packet->'presentation',
      'metadata',p_packet->'metadata',
      'truthBoundary',jsonb_build_object(
        'domainTruthRemainsCanonical',true,
        'candidateIsProjectionNotSourceTruth',true,
        'admissionMustBeExplicitlyWarranted',true,
        'commandDescriptorDoesNotExecuteCommand',true,
        'resolutionMustReturnFromCanonicalSource',true,
        'notAClockPlacement',true,
        'notACommitmentLedgerEntry',true
      )
    ))
  );
end;
$function$;

revoke all on function atlas.evaluate_principal_decision_packet_v1(jsonb) from public,anon,authenticated;

-- First adapter/proof: Flower Demand -> Sale.
--
-- This adapter does not make ordinary demand Principal work. It requires an
-- already-open Principal operational escalation with the exact source identity
-- below. The escalation supplies the admission/threshold/consequence truth;
-- Flower Demand supplies transition readiness and Sale supplies resolution.
create or replace function atlas.flower_demand_sale_principal_decision_v1(p_demand_order_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_order atlas.flower_demand_orders%rowtype;
  v_unit atlas.portfolio_units%rowtype;
  v_escalation atlas.operational_escalations%rowtype;
  v_sale_id uuid;
  v_line_count integer:=0;
  v_not_ready integer:=0;
  v_packet jsonb;
begin
  select * into v_order from atlas.flower_demand_orders where id=p_demand_order_id;
  if v_order.id is null then
    return jsonb_build_object('contractVersion','flower_demand_sale_principal_decision_v1','state','missing_source','demandOrderId',p_demand_order_id);
  end if;

  select * into v_unit
  from atlas.portfolio_units u
  where u.linked_farm_id=v_order.farm_id and u.archived_at is null
  order by case when u.portfolio_role='current_engine' then 0 else 1 end,u.created_at,u.id
  limit 1;
  if v_unit.id is null then
    return jsonb_build_object(
      'contractVersion','flower_demand_sale_principal_decision_v1',
      'state','contained','demandOrderId',v_order.id,
      'reason','No Principal portfolio custody is established for this source.',
      'truthBoundary',jsonb_build_object('unmappedOperatingUnitDoesNotEscalate',true)
    );
  end if;

  select so.id into v_sale_id
  from atlas.flower_demand_sale_order_links l
  join atlas.flower_sale_orders so on so.id=l.sale_order_id
  where l.demand_order_id=v_order.id
    and not exists(select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=so.id)
  order by so.created_at desc
  limit 1;

  select * into v_escalation
  from atlas.operational_escalations e
  where e.principal_id=v_unit.owner_id
    and e.portfolio_unit_id=v_unit.id
    and e.source_system='flower_commerce'
    and e.source_type='flower_demand_order'
    and e.source_id=v_order.id::text
    and e.escalation_kind='sale_commitment_decision'
    and e.status in ('open','acknowledged')
  order by e.updated_at desc,e.id
  limit 1;

  if v_escalation.id is null then
    return jsonb_build_object(
      'contractVersion','flower_demand_sale_principal_decision_v1',
      'state',case when v_sale_id is null then 'contained' else 'resolved' end,
      'demandOrderId',v_order.id,
      'saleOrderId',v_sale_id,
      'reason',case when v_sale_id is null then 'No explicit Principal admission exists for this demand.' else 'Canonical Sale already resolves the transition.' end,
      'candidate',null,
      'truthBoundary',jsonb_build_object(
        'ordinaryAllocatedDemandDoesNotAutoEscalate',true,
        'principalAdmissionMustExistSeparately',true
      )
    );
  end if;

  if v_sale_id is null then
    select count(*),count(*) filter(where c.coverage_state<>'covered' or c.sold_quantity<>0 or c.target_unit_price is null)
    into v_line_count,v_not_ready
    from atlas.flower_demand_coverage_v1 c
    where c.demand_order_id=v_order.id;

    if v_order.demand_strength<>'committed'
       or exists(select 1 from atlas.flower_demand_order_cancellation_events dc where dc.demand_order_id=v_order.id)
       or v_line_count=0
       or v_not_ready>0 then
      return jsonb_build_object(
        'contractVersion','flower_demand_sale_principal_decision_v1',
        'state','contained',
        'demandOrderId',v_order.id,
        'escalationId',v_escalation.id,
        'reason','The canonical Demand -> Sale transition is not currently executable; this adapter will not relabel a different problem as Sale commitment.',
        'candidate',null,
        'truthBoundary',jsonb_build_object(
          'demandMustBeCommitted',true,
          'demandMustBeFullyReserved',true,
          'pricesMustAlreadyBeEstablished',true,
          'adapterDoesNotInventMissingPrerequisites',true
        )
      );
    end if;
  end if;

  v_packet:=jsonb_build_object(
    'principalId',v_unit.owner_id,
    'scope',jsonb_build_object('kind','organization','id',v_unit.organization_id,'portfolioUnitId',v_unit.id),
    'source',jsonb_build_object(
      'domain','flower_commerce','kind','flower_demand_order','id',v_order.id,
      'state',jsonb_strip_nulls(jsonb_build_object(
        'demandStrength',v_order.demand_strength,
        'requestedForDate',v_order.requested_for_date,
        'fulfillmentMode',v_order.fulfillment_mode,
        'canonicalSaleOrderId',v_sale_id
      ))
    ),
    'authority',jsonb_build_object(
      'principalRequired',true,
      'basis','operational_escalation:'||v_escalation.id::text,
      'executionAuthority','owner_or_manager'
    ),
    'admission',jsonb_build_object(
      'state','established',
      'basis',v_escalation.threshold_crossed,
      'consequence',v_escalation.consequence,
      'reasonForFloor',v_escalation.reason_for_floor,
      'escalationId',v_escalation.id
    ),
    'resolution',jsonb_build_object(
      'state',case when v_sale_id is null then 'unresolved' else 'resolved' end,
      'sourceKind','flower_demand_sale_order_link',
      'sourceId',v_sale_id
    ),
    'decision',jsonb_build_object(
      'kind','commit_demand_to_sale',
      'prompt',v_escalation.owner_decision_required,
      'options',v_escalation.options_json,
      'command',jsonb_build_object(
        'kind','flower_demand_commit_to_sale',
        'contractVersion','record_flower_sale_from_demand_core_v1',
        'targetKind','flower_demand_order',
        'targetId',v_order.id
      )
    ),
    'timing',jsonb_strip_nulls(jsonb_build_object(
      'windowStart',v_escalation.window_start,
      'windowEnd',v_escalation.window_end,
      'expectedPrincipalMinutes',v_escalation.expected_owner_minutes,
      'floorClass',v_escalation.floor_class,
      'protectionLevel',v_escalation.protection_level,
      'interruptibility',v_escalation.interruptibility
    )),
    'presentation',jsonb_build_object('title','Commit established demand to Sale'),
    'metadata',jsonb_build_object(
      'adapterContract','flower_demand_sale_principal_decision_v1',
      'escalationKind',v_escalation.escalation_kind,
      'severity',v_escalation.severity,
      'horizon',v_escalation.horizon
    )
  );

  return atlas.evaluate_principal_decision_packet_v1(v_packet)
    ||jsonb_build_object('adapterContract','flower_demand_sale_principal_decision_v1','escalationId',v_escalation.id);
end;
$function$;

revoke all on function atlas.flower_demand_sale_principal_decision_v1(uuid) from public,anon,authenticated;

-- Source-derived resolution: when the canonical Demand -> Sale link is minted,
-- any matching Principal Sale-commitment escalation resolves automatically.
create or replace function atlas.resolve_flower_demand_sale_principal_escalation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  update atlas.operational_escalations e
  set status='resolved',resolved_at=coalesce(e.resolved_at,now()),updated_at=now(),
      metadata=coalesce(e.metadata,'{}'::jsonb)||jsonb_build_object(
        'resolvedBy','flower_demand_sale_link_v1',
        'resolvedReason','canonical_demand_to_sale_transition_completed',
        'resolvedSaleOrderId',new.sale_order_id
      )
  where e.source_system='flower_commerce'
    and e.source_type='flower_demand_order'
    and e.source_id=new.demand_order_id::text
    and e.escalation_kind='sale_commitment_decision'
    and e.status in ('open','acknowledged');
  return new;
end;
$function$;

drop trigger if exists flower_demand_sale_resolves_principal_escalation_v1 on atlas.flower_demand_sale_order_links;
create trigger flower_demand_sale_resolves_principal_escalation_v1
after insert on atlas.flower_demand_sale_order_links
for each row execute function atlas.resolve_flower_demand_sale_principal_escalation_v1();

-- Deployment-time pure-contract proofs. These persist no fixture data.
do $proof$
declare
  v_packet jsonb;
  v_a jsonb;
  v_b jsonb;
begin
  v_packet:=jsonb_build_object(
    'principalId','00000000-0000-0000-0000-000000000001',
    'scope',jsonb_build_object('kind','organization','id','00000000-0000-0000-0000-000000000002'),
    'source',jsonb_build_object('domain','proof','kind','foreign_shape','id','alpha'),
    'authority',jsonb_build_object('principalRequired',true,'basis','explicit_authority'),
    'admission',jsonb_build_object('state','established','basis','explicit_threshold','consequence','A real consequence exists.','reasonForFloor','The explicit Principal threshold was crossed.'),
    'resolution',jsonb_build_object('state','unresolved'),
    'decision',jsonb_build_object('kind','choose_response','prompt','Choose the warranted response.','options',jsonb_build_array('a','b'),'command',jsonb_build_object('kind','proof_command','targetKind','foreign_shape','targetId','alpha'))
  );
  v_a:=atlas.evaluate_principal_decision_packet_v1(v_packet);
  v_b:=atlas.evaluate_principal_decision_packet_v1(v_packet);
  if v_a->>'state'<>'candidate' then raise exception 'Principal decision proof failed: warranted packet did not become candidate.'; end if;
  if v_a#>>'{candidate,candidateKey}' is distinct from v_b#>>'{candidate,candidateKey}' then raise exception 'Principal decision proof failed: candidate identity is not deterministic.'; end if;

  v_a:=atlas.evaluate_principal_decision_packet_v1(jsonb_set(v_packet,'{admission,state}','"not_established"'::jsonb));
  if v_a->>'state'<>'contained' then raise exception 'Principal decision proof failed: unadmitted source escaped containment.'; end if;

  v_a:=atlas.evaluate_principal_decision_packet_v1(jsonb_set(v_packet,'{resolution,state}','"resolved"'::jsonb));
  if v_a->>'state'<>'resolved' or v_a->'candidate' is distinct from 'null'::jsonb then raise exception 'Principal decision proof failed: resolved source remained candidate.'; end if;

  v_a:=atlas.evaluate_principal_decision_packet_v1(jsonb_set(v_packet,'{authority,principalRequired}','false'::jsonb));
  if v_a->>'state'<>'contained' then raise exception 'Principal decision proof failed: non-Principal responsibility escaped containment.'; end if;
end;
$proof$;

COMMIT;
