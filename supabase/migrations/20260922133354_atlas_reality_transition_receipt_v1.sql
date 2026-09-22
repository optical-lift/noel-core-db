begin;

-- Atlas Reality Transition Receipt v1
--
-- Read-only cross-domain composition only.
--
-- The universal layer is the receipt grammar. Domain truth, resolution,
-- consequence, execution and historical evidence remain in their owning
-- tables/functions. No generic transition/event/effect storage is created.

create or replace function atlas.reality_transition_receipt_normalize_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = pg_catalog, atlas
as $function$
declare
  v_source jsonb;
  v_subject jsonb;
  v_interpretation jsonb;
  v_resolution jsonb;
  v_consequence jsonb;
  v_execution jsonb;
  v_continuation jsonb;
  v_provenance jsonb;
  v_occurred_at text;
  v_effective_at text;
begin
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Reality Transition Receipt must be a JSON object.'
      using errcode='22023';
  end if;

  if coalesce(nullif(btrim(p_input->>'contractVersion'),''),'reality_transition_receipt_v1')
     <> 'reality_transition_receipt_v1' then
    raise exception 'Unsupported Reality Transition Receipt contract version.'
      using errcode='22023';
  end if;

  if nullif(btrim(p_input->>'receiptKind'),'') is null then
    raise exception 'Reality Transition Receipt kind is required.'
      using errcode='22023';
  end if;

  v_source:=p_input->'source';
  v_subject:=p_input->'subject';
  v_interpretation:=p_input->'interpretation';
  v_resolution:=p_input->'resolution';
  v_consequence:=p_input->'consequence';
  v_execution:=p_input->'execution';
  v_continuation:=coalesce(p_input->'continuation','{}'::jsonb);
  v_provenance:=coalesce(p_input->'provenance','{}'::jsonb);

  if jsonb_typeof(v_source)<>'object'
     or nullif(btrim(v_source->>'domain'),'') is null
     or nullif(btrim(v_source->>'kind'),'') is null
     or nullif(btrim(v_source->>'ref'),'') is null then
    raise exception 'Reality Transition Receipt source identity is incomplete.'
      using errcode='22023';
  end if;

  v_occurred_at:=nullif(btrim(v_source->>'occurredAt'),'');
  if v_occurred_at is not null then
    begin
      perform v_occurred_at::timestamptz;
    exception when others then
      raise exception 'Reality Transition Receipt source occurredAt is not a timestamp.'
        using errcode='22023';
    end;
  end if;

  if jsonb_typeof(v_subject)<>'object'
     or nullif(btrim(v_subject->>'kind'),'') is null
     or nullif(btrim(v_subject->>'ref'),'') is null
     or (
       v_subject ? 'scope'
       and jsonb_typeof(v_subject->'scope')<>'object'
     ) then
    raise exception 'Reality Transition Receipt subject identity is incomplete.'
      using errcode='22023';
  end if;

  if v_interpretation is not null then
    if jsonb_typeof(v_interpretation)<>'object'
       or (
         v_interpretation ? 'claimRefs'
         and jsonb_typeof(v_interpretation->'claimRefs')<>'array'
       )
       or (
         v_interpretation ? 'proposedEffectRefs'
         and jsonb_typeof(v_interpretation->'proposedEffectRefs')<>'array'
       )
       or (
         v_interpretation ? 'actualRefs'
         and jsonb_typeof(v_interpretation->'actualRefs')<>'array'
       ) then
      raise exception 'Reality Transition Receipt interpretation shape is invalid.'
        using errcode='22023';
    end if;
  end if;

  if jsonb_typeof(v_resolution)<>'object'
     or coalesce(v_resolution->>'state','') not in (
       'effective','rejected','unresolved','not_applicable'
     )
     or nullif(btrim(v_resolution->>'resolver'),'') is null
     or (
       v_resolution ? 'basisRefs'
       and jsonb_typeof(v_resolution->'basisRefs')<>'array'
     ) then
    raise exception 'Reality Transition Receipt resolution shape is invalid.'
      using errcode='22023';
  end if;

  v_effective_at:=nullif(btrim(v_resolution->>'effectiveAt'),'');
  if v_effective_at is not null then
    begin
      perform v_effective_at::timestamptz;
    exception when others then
      raise exception 'Reality Transition Receipt resolution effectiveAt is not a timestamp.'
        using errcode='22023';
    end;
  end if;

  if v_consequence is not null and (
    jsonb_typeof(v_consequence)<>'object'
    or nullif(btrim(v_consequence->>'kind'),'') is null
    or nullif(btrim(v_consequence->>'ref'),'') is null
    or nullif(btrim(v_consequence->>'state'),'') is null
    or (
      v_consequence ? 'details'
      and jsonb_typeof(v_consequence->'details')<>'object'
    )
  ) then
    raise exception 'Reality Transition Receipt consequence shape is invalid.'
      using errcode='22023';
  end if;

  if v_execution is not null and jsonb_typeof(v_execution)<>'object' then
    raise exception 'Reality Transition Receipt execution must be an object.'
      using errcode='22023';
  end if;

  if jsonb_typeof(v_continuation)<>'object'
     or (
       v_continuation ? 'reconsider'
       and jsonb_typeof(v_continuation->'reconsider')<>'array'
     )
     or (
       v_continuation ? 'blockers'
       and jsonb_typeof(v_continuation->'blockers')<>'array'
     ) then
    raise exception 'Reality Transition Receipt continuation shape is invalid.'
      using errcode='22023';
  end if;

  if jsonb_typeof(v_provenance)<>'object' then
    raise exception 'Reality Transition Receipt provenance must be an object.'
      using errcode='22023';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','reality_transition_receipt_v1',
    'receiptKind',btrim(p_input->>'receiptKind'),
    'source',jsonb_strip_nulls(jsonb_build_object(
      'domain',btrim(v_source->>'domain'),
      'kind',btrim(v_source->>'kind'),
      'ref',btrim(v_source->>'ref'),
      'occurredAt',v_occurred_at,
      'details',case
        when v_source ? 'details' and jsonb_typeof(v_source->'details')='object'
        then v_source->'details'
        else null
      end
    )),
    'subject',jsonb_strip_nulls(jsonb_build_object(
      'kind',btrim(v_subject->>'kind'),
      'ref',btrim(v_subject->>'ref'),
      'scope',coalesce(v_subject->'scope','{}'::jsonb)
    )),
    'interpretation',case when v_interpretation is null then null else
      jsonb_build_object(
        'claimRefs',coalesce(v_interpretation->'claimRefs','[]'::jsonb),
        'proposedEffectRefs',coalesce(v_interpretation->'proposedEffectRefs','[]'::jsonb),
        'actualRefs',coalesce(v_interpretation->'actualRefs','[]'::jsonb)
      )
    end,
    'resolution',jsonb_strip_nulls(jsonb_build_object(
      'state',v_resolution->>'state',
      'resolver',btrim(v_resolution->>'resolver'),
      'basisRefs',coalesce(v_resolution->'basisRefs','[]'::jsonb),
      'effectiveAt',v_effective_at,
      'details',case
        when v_resolution ? 'details' and jsonb_typeof(v_resolution->'details')='object'
        then v_resolution->'details'
        else null
      end
    )),
    'consequence',case when v_consequence is null then null else
      jsonb_strip_nulls(jsonb_build_object(
        'kind',btrim(v_consequence->>'kind'),
        'ref',btrim(v_consequence->>'ref'),
        'state',btrim(v_consequence->>'state'),
        'details',case
          when v_consequence ? 'details' then v_consequence->'details'
          else null
        end
      ))
    end,
    'execution',v_execution,
    'continuation',jsonb_build_object(
      'reconsider',coalesce(v_continuation->'reconsider','[]'::jsonb),
      'blockers',coalesce(v_continuation->'blockers','[]'::jsonb)
    ),
    'provenance',v_provenance
  ));
end;
$function$;

comment on function atlas.reality_transition_receipt_normalize_v1(jsonb) is
  'Read-only schema normalizer for one consequential transition. It does not query or mutate domain truth, resolve effects, execute commands, or persist receipts.';

revoke all on function atlas.reality_transition_receipt_normalize_v1(jsonb)
  from public,anon,authenticated,service_role;


create or replace function atlas.company_work_result_transition_receipt_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_result atlas.work_execution_results%rowtype;
  v_work atlas.work_items%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_ledger atlas.organization_ledger_entries%rowtype;
  v_resolution_state text;
  v_effective_at timestamptz;
  v_basis_refs jsonb := '[]'::jsonb;
  v_reconsider jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_consequence jsonb;
begin
  select r.* into v_result
  from atlas.work_execution_results r
  where r.id=p_execution_result_id;

  if v_result.id is null then
    raise exception 'Work Execution Result not found.'
      using errcode='P0002';
  end if;

  select w.* into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id
    and w.organization_id=v_result.organization_id;

  if v_work.id is null then
    raise exception 'Work Execution Result has no matching Company Work identity.'
      using errcode='23514';
  end if;

  select a.* into v_acceptance
  from atlas.work_result_acceptances a
  where a.execution_result_id=v_result.id
  order by a.accepted_at desc,a.id desc
  limit 1;

  select le.* into v_ledger
  from atlas.organization_ledger_entries le
  where le.semantic_type='company_work_completed'
    and le.truth_status='established'
    and (
      le.payload->>'resultId'=v_result.id::text
      or le.correlation->>'executionResultId'=v_result.id::text
    )
  order by le.established_at desc,le.id desc
  limit 1;

  v_basis_refs:=jsonb_build_array(
    jsonb_build_object(
      'kind','work_execution_result',
      'ref',v_result.id
    )
  );

  if v_acceptance.id is not null then
    v_basis_refs:=v_basis_refs||jsonb_build_array(
      jsonb_build_object(
        'kind','work_result_acceptance',
        'ref',v_acceptance.id,
        'decision',v_acceptance.decision
      )
    );
  end if;

  if v_ledger.id is not null then
    v_basis_refs:=v_basis_refs||jsonb_build_array(
      jsonb_build_object(
        'kind','organization_ledger_entry',
        'ref',v_ledger.id,
        'truthStatus',v_ledger.truth_status
      )
    );
  end if;

  if v_acceptance.id is null then
    v_resolution_state:='unresolved';
    v_reconsider:=jsonb_build_array('company_work_result_adjudication');
    v_blockers:=jsonb_build_array('result_acceptance_missing');
  elsif v_acceptance.decision='rejected' then
    v_resolution_state:='rejected';
    v_effective_at:=v_acceptance.accepted_at;
  elsif v_acceptance.decision='accepted'
        and v_work.work_state='completed'
        and v_ledger.id is not null then
    v_resolution_state:='effective';
    v_effective_at:=v_ledger.established_at;
    v_consequence:=jsonb_build_object(
      'kind','organization_ledger_entry',
      'ref',v_ledger.id::text,
      'state','established',
      'details',jsonb_build_object(
        'semanticType',v_ledger.semantic_type,
        'truthStatus',v_ledger.truth_status,
        'designationStatus',v_ledger.designation_status
      )
    );
  else
    v_resolution_state:='unresolved';
    v_reconsider:=jsonb_build_array('company_work_completion_projection');
    if v_acceptance.decision<>'accepted' then
      v_blockers:=v_blockers||jsonb_build_array('accepted_result_required');
    end if;
    if v_work.work_state<>'completed' then
      v_blockers:=v_blockers||jsonb_build_array('work_not_completed');
    end if;
    if v_ledger.id is null then
      v_blockers:=v_blockers||jsonb_build_array('ledger_consequence_missing');
    end if;
  end if;

  return atlas.reality_transition_receipt_normalize_v1(
    jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','reality_transition_receipt_v1',
      'receiptKind','company_work_result',
      'source',jsonb_build_object(
        'domain','company_work',
        'kind','work_execution_result',
        'ref',v_result.id::text,
        'occurredAt',v_result.reported_at,
        'details',jsonb_strip_nulls(jsonb_build_object(
          'resultKind',v_result.result_kind,
          'resultContractKey',v_result.result_contract_key
        ))
      ),
      'subject',jsonb_build_object(
        'kind','work_item',
        'ref',v_work.id::text,
        'scope',jsonb_strip_nulls(jsonb_build_object(
          'organizationId',v_work.organization_id,
          'organizationUnitId',v_work.organization_unit_id
        ))
      ),
      'interpretation',jsonb_build_object(
        'claimRefs','[]'::jsonb,
        'proposedEffectRefs','[]'::jsonb,
        'actualRefs',jsonb_build_array(jsonb_build_object(
          'kind','work_execution_result',
          'ref',v_result.id,
          'resultKind',v_result.result_kind,
          'reportedAt',v_result.reported_at
        ))
      ),
      'resolution',jsonb_strip_nulls(jsonb_build_object(
        'state',v_resolution_state,
        'resolver','company_work_result_acceptance_and_ledger_v1',
        'basisRefs',v_basis_refs,
        'effectiveAt',v_effective_at,
        'details',jsonb_strip_nulls(jsonb_build_object(
          'acceptanceId',v_acceptance.id,
          'acceptanceDecision',v_acceptance.decision,
          'acceptanceKind',v_acceptance.acceptance_kind,
          'workState',v_work.work_state
        ))
      )),
      'consequence',v_consequence,
      'execution',jsonb_strip_nulls(jsonb_build_object(
        'requirementState','established',
        'carrierState',case
          when v_result.responsible_allocation_id is null then 'unresolved'
          else 'established'
        end,
        'carrierRef',case
          when v_result.responsible_allocation_id is null then null
          else 'work_allocation:'||v_result.responsible_allocation_id::text
        end,
        'completionWitnessRef','work_execution_result:'||v_result.id::text
      )),
      'continuation',jsonb_build_object(
        'reconsider',v_reconsider,
        'blockers',v_blockers
      ),
      'provenance',jsonb_build_object(
        'adapter','company_work_result_transition_receipt_v1',
        'sourceTables',jsonb_build_array(
          'work_execution_results',
          'work_items',
          'work_result_acceptances',
          'organization_ledger_entries'
        ),
        'readOnly',true
      )
    ))
  );
end;
$function$;

comment on function atlas.company_work_result_transition_receipt_v1(uuid) is
  'Read-only Company Work Result transition receipt. Separates reported result, result adjudication, Work terminality and Organization Ledger consequence.';

revoke all on function atlas.company_work_result_transition_receipt_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.commercial_financial_transition_receipt_v1(
  p_commercial_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_order atlas.commercial_orders%rowtype;
  v_position atlas.commercial_financial_position_v1%rowtype;
  v_actual_refs jsonb := '[]'::jsonb;
  v_basis_refs jsonb := '[]'::jsonb;
  v_fulfillment_refs jsonb := '[]'::jsonb;
  v_resolution_state text;
  v_effective_at timestamptz;
  v_reconsider jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
begin
  select o.* into v_order
  from atlas.commercial_orders o
  where o.id=p_commercial_order_id;

  if v_order.id is null then
    raise exception 'Commercial Order not found.'
      using errcode='P0002';
  end if;

  select p.* into v_position
  from atlas.commercial_financial_position_v1 p
  where p.commercial_order_id=v_order.id;

  if v_position.commercial_order_id is null then
    raise exception 'Commercial Order has no Financial Reality projection.'
      using errcode='23514';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'kind','commercial_order_event',
      'ref',e.id,
      'eventKind',e.event_kind,
      'occurredAt',e.occurred_at
    )
    order by e.occurred_at,e.id
  ),'[]'::jsonb)
  into v_actual_refs
  from atlas.commercial_order_events e
  where e.commercial_order_id=v_order.id;

  select v_actual_refs||coalesce(jsonb_agg(
    jsonb_build_object(
      'kind','commercial_payment_event',
      'ref',pe.id,
      'commercialPaymentId',pe.commercial_payment_id,
      'eventKind',pe.event_kind,
      'occurredAt',pe.occurred_at
    )
    order by pe.occurred_at,pe.id
  ),'[]'::jsonb)
  into v_actual_refs
  from atlas.commercial_payments p
  join atlas.commercial_payment_events pe
    on pe.commercial_payment_id=p.id
  where p.commercial_order_id=v_order.id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'kind','commercial_fulfillment_event',
      'ref',f.id,
      'eventKind',f.event_kind,
      'occurredAt',f.occurred_at
    )
    order by f.occurred_at,f.id
  ),'[]'::jsonb)
  into v_fulfillment_refs
  from atlas.commercial_fulfillment_events f
  where f.commercial_order_id=v_order.id;

  v_basis_refs:=jsonb_build_array(
    jsonb_build_object(
      'kind',v_position.source_kind,
      'ref',v_position.source_id,
      'domain',v_position.source_domain
    )
  )||v_actual_refs;

  v_resolution_state:=case v_position.financial_state
    when 'outside_canonical_custody' then 'not_applicable'
    when 'collection_unknown' then 'unresolved'
    when 'invariant_gap' then 'unresolved'
    else 'effective'
  end;

  v_effective_at:=coalesce(
    v_position.ended_or_refunded_at,
    v_position.last_collection_at,
    v_order.created_at
  );

  if v_position.financial_state in ('open','partially_paid') then
    v_reconsider:=jsonb_build_array('commercial_collection_or_settlement');
  elsif v_position.financial_state='refund_due' then
    v_reconsider:=jsonb_build_array('commercial_refund_resolution');
  elsif v_position.financial_state in ('collection_unknown','invariant_gap') then
    v_reconsider:=jsonb_build_array('commercial_financial_reconciliation');
  end if;

  if v_position.financial_state='outside_canonical_custody' then
    v_blockers:=jsonb_build_array('outside_canonical_ledger_custody');
  elsif v_position.financial_state='collection_unknown' then
    v_blockers:=jsonb_build_array('collection_evidence_unknown');
  elsif v_position.financial_state='invariant_gap' then
    v_blockers:=jsonb_build_array('financial_evidence_invariant_gap');
  end if;

  return atlas.reality_transition_receipt_normalize_v1(
    jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','reality_transition_receipt_v1',
      'receiptKind','commercial_financial_position',
      'source',jsonb_build_object(
        'domain',v_position.source_domain,
        'kind',v_position.source_kind,
        'ref',v_position.source_id,
        'occurredAt',v_order.created_at,
        'details',jsonb_build_object(
          'commercialOrderId',v_order.id,
          'orderKind',v_order.order_kind,
          'orderDate',v_order.order_date
        )
      ),
      'subject',jsonb_build_object(
        'kind','commercial_order',
        'ref',v_order.id::text,
        'scope',jsonb_strip_nulls(jsonb_build_object(
          'organizationId',v_position.effective_organization_id,
          'organizationUnitId',v_order.organization_unit_id,
          'ledgerId',v_position.effective_ledger_id
        ))
      ),
      'interpretation',jsonb_build_object(
        'claimRefs','[]'::jsonb,
        'proposedEffectRefs','[]'::jsonb,
        'actualRefs',v_actual_refs
      ),
      'resolution',jsonb_build_object(
        'state',v_resolution_state,
        'resolver','commercial_financial_position_v1',
        'basisRefs',v_basis_refs,
        'effectiveAt',v_effective_at,
        'details',jsonb_build_object(
          'financialCoverage',v_position.financial_coverage,
          'financialCoverageBasis',v_position.financial_coverage_basis,
          'custodyDisposition',v_position.custody_disposition,
          'custodyEvidenceBasis',v_position.custody_evidence_basis
        )
      ),
      'consequence',jsonb_build_object(
        'kind','commercial_financial_position',
        'ref',v_order.id::text,
        'state',v_position.financial_state,
        'details',jsonb_strip_nulls(jsonb_build_object(
          'currency',v_position.currency,
          'committedAmount',v_position.committed_amount,
          'grossCollectedAmount',v_position.gross_collected_amount,
          'returnedAmount',v_position.returned_amount,
          'netCollectedAmount',v_position.net_collected_amount,
          'openAmount',v_position.open_amount,
          'overpaidAmount',v_position.overpaid_amount
        ))
      ),
      'continuation',jsonb_build_object(
        'reconsider',v_reconsider,
        'blockers',v_blockers
      ),
      'provenance',jsonb_build_object(
        'adapter','commercial_financial_transition_receipt_v1',
        'sourceTables',jsonb_build_array(
          'commercial_orders',
          'commercial_order_events',
          'commercial_payments',
          'commercial_payment_events',
          'commercial_financial_position_v1'
        ),
        'independentFulfillmentRefs',v_fulfillment_refs,
        'fulfillmentExcludedFromFinancialResolution',true,
        'readOnly',true
      )
    ))
  );
end;
$function$;

comment on function atlas.commercial_financial_transition_receipt_v1(uuid) is
  'Read-only Commercial Financial transition receipt. Payment/order evidence drives derived Financial Reality; fulfillment is preserved separately and does not become settlement evidence.';

revoke all on function atlas.commercial_financial_transition_receipt_v1(uuid)
  from public,anon,authenticated,service_role;

commit;
