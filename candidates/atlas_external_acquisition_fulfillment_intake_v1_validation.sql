begin;

do $validation$
declare
  v_org_id uuid;
  v_supplier_subject_id uuid;
  v_supplier_relationship_id uuid;
  v_offering_id uuid;

  v_r40 uuid;
  v_r30 uuid;
  v_r20 uuid;

  v_commitment_input jsonb;
  v_commitment_result jsonb;
  v_commitment_id uuid;
  v_line_id uuid;
  v_a40 uuid;
  v_a30 uuid;
  v_a20 uuid;

  v_f1 jsonb;
  v_f2 jsonb;
  v_preview jsonb;
  v_result jsonb;
  v_fulfillment_id uuid;
  v_position jsonb;
  v_coverage jsonb;
  v_facts jsonb;
  v_check jsonb;

  v_cancel_commitment_id uuid;
  v_cancel_line_id uuid;
  v_ca40 uuid;
  v_ca30 uuid;
  v_ca20 uuid;

  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_payments bigint;
  v_before_orders bigint;
  v_before_work bigint;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_external_acquisition_fulfillment_v1',
    'Fixture External Acquisition Fulfillment Organization',
    'active',
    '{"fixture":"atlas_external_acquisition_fulfillment_intake_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(v_org_id,'{"fixture":"supplier"}'::jsonb)
  returning id into v_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,v_supplier_subject_id,'fixture-supplier','active',
    '{"fixture":"atlas_external_acquisition_fulfillment_intake_v1"}'::jsonb
  )
  returning id into v_supplier_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_supplier_relationship_id,'supplier','active',
    '{"fixture":"atlas_external_acquisition_fulfillment_intake_v1"}'::jsonb
  );

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,null,v_supplier_relationship_id,
    'fixture-carnation-100','fixture-carnation-100','Standard Carnations',
    'item','stem',
    '{"flowerFamily":"carnation","grade":"standard"}'::jsonb,
    '{"fixture":"atlas_external_acquisition_fulfillment_intake_v1"}'::jsonb
  );

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:fulfillment:r40','fulfillment_coverage','Secure 40 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":40,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation"}}}'::jsonb
  )
  returning id into v_r40;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:fulfillment:r30','fulfillment_coverage','Secure 30 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":30,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation"}}}'::jsonb
  )
  returning id into v_r30;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:fulfillment:r20','fulfillment_coverage','Secure 20 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":20,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation"}}}'::jsonb
  )
  returning id into v_r20;

  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_work from atlas.work_requirements;

  v_commitment_input:=jsonb_build_object(
    'contractVersion','external_acquisition_commitment_input_v1',
    'organizationId',v_org_id,
    'supplierRelationshipId',v_supplier_relationship_id,
    'commitmentKey','fixture:fulfillment:po-100',
    'commitmentKind','supplier_order',
    'committedAt','2026-09-24T14:00:00Z',
    'expectedFulfillmentFromAt','2026-09-25T13:00:00Z',
    'expectedFulfillmentByAt','2026-09-25T16:00:00Z',
    'acceptedTerms',jsonb_build_object('freightIncluded',true),
    'economics',jsonb_build_object(
      'state','known',
      'knownCommittedAmount',38,
      'currency','USD',
      'costComponents',jsonb_build_array(
        jsonb_build_object(
          'componentKey','landed_pool_cost',
          'state','known',
          'amount',38,
          'currency','USD'
        )
      )
    ),
    'source',jsonb_build_object(
      'kind','supplier_confirmation',
      'ref','fixture:po-100'
    ),
    'authorizationBasis',jsonb_build_object(
      'authorityRef','fixture:purchasing-authority',
      'decisionRef','fixture:approved-pool',
      'authorizedAt','2026-09-24T13:55:00Z'
    ),
    'lines',jsonb_build_array(
      jsonb_build_object(
        'lineKey','carnations',
        'externalSupplyOfferingId',v_offering_id,
        'description','100 Standard Carnations',
        'orderedQuantity',100,
        'orderedUnit','stem',
        'coverageOutputQuantity',100,
        'coverageOutputUnit','stem',
        'knownLineAmount',38,
        'currency','USD',
        'allocations',jsonb_build_array(
          jsonb_build_object(
            'allocationKey','buyer-40',
            'workRequirementId',v_r40,
            'coverageQuantity',40,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:pool')
          ),
          jsonb_build_object(
            'allocationKey','buyer-30',
            'workRequirementId',v_r30,
            'coverageQuantity',30,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:pool')
          ),
          jsonb_build_object(
            'allocationKey','buyer-20',
            'workRequirementId',v_r20,
            'coverageQuantity',20,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:pool')
          )
        )
      )
    ),
    'metadata',jsonb_build_object(
      'fixture','atlas_external_acquisition_fulfillment_intake_v1'
    )
  );

  v_commitment_result:=atlas.record_external_acquisition_commitment_service_v1(
    v_commitment_input
  );
  v_commitment_id:=(v_commitment_result->>'externalAcquisitionCommitmentId')::uuid;

  select l.id
  into v_line_id
  from atlas.external_acquisition_commitment_lines l
  where l.external_acquisition_commitment_id=v_commitment_id
    and l.line_key='carnations';

  select a.id into v_a40
  from atlas.external_acquisition_requirement_allocations a
  where a.external_acquisition_commitment_line_id=v_line_id
    and a.work_requirement_id=v_r40;

  select a.id into v_a30
  from atlas.external_acquisition_requirement_allocations a
  where a.external_acquisition_commitment_line_id=v_line_id
    and a.work_requirement_id=v_r30;

  select a.id into v_a20
  from atlas.external_acquisition_requirement_allocations a
  where a.external_acquisition_commitment_line_id=v_line_id
    and a.work_requirement_id=v_r20;

  -- 1. First physical receipt: 50 delivered, 48 accepted, 2 rejected.
  v_f1:=jsonb_build_object(
    'contractVersion','external_acquisition_fulfillment_input_v1',
    'externalAcquisitionCommitmentId',v_commitment_id,
    'fulfillmentKey','fixture:delivery-1',
    'fulfillmentKind','delivery',
    'occurredAt','2026-09-25T13:30:00Z',
    'source',jsonb_build_object(
      'kind','receiving_observation',
      'ref','fixture:delivery-1'
    ),
    'lines',jsonb_build_array(
      jsonb_build_object(
        'lineKey','carnations-1',
        'externalAcquisitionCommitmentLineId',v_line_id,
        'sourceQuantity',50,
        'sourceUnit','stem',
        'deliveredOutputQuantity',50,
        'acceptedOutputQuantity',48,
        'rejectedOutputQuantity',2,
        'unresolvedOutputQuantity',0,
        'coverageOutputUnit','stem',
        'condition',jsonb_build_object(
          'summary','48 acceptable, 2 damaged'
        ),
        'allocations',jsonb_build_array(
          jsonb_build_object(
            'allocationKey','buyer-40-part-1',
            'externalAcquisitionRequirementAllocationId',v_a40,
            'acceptedCoverageQuantity',20,
            'coverageUnit','stem'
          ),
          jsonb_build_object(
            'allocationKey','buyer-30-part-1',
            'externalAcquisitionRequirementAllocationId',v_a30,
            'acceptedCoverageQuantity',18,
            'coverageUnit','stem'
          ),
          jsonb_build_object(
            'allocationKey','buyer-20-part-1',
            'externalAcquisitionRequirementAllocationId',v_a20,
            'acceptedCoverageQuantity',10,
            'coverageUnit','stem'
          )
        )
      )
    ),
    'metadata',jsonb_build_object(
      'fixture','atlas_external_acquisition_fulfillment_intake_v1'
    )
  );

  v_preview:=atlas.external_acquisition_fulfillment_preview_v1(v_f1);

  if v_preview->>'state'<>'ready'
     or jsonb_array_length(v_preview->'violations')<>0
     or (v_preview->>'lineCount')::integer<>1
     or (v_preview->>'allocationCount')::integer<>3 then
    raise exception 'First fulfillment preview failed: %',v_preview;
  end if;

  v_result:=atlas.record_external_acquisition_fulfillment_service_v1(v_f1);
  v_fulfillment_id:=(v_result->>'externalAcquisitionFulfillmentId')::uuid;

  if v_fulfillment_id is null
     or coalesce((v_result->>'created')::boolean,false)=false then
    raise exception 'First fulfillment writer failed: %',v_result;
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(v_commitment_id);

  if v_position->>'state'<>'partially_fulfilled'
     or (v_position->'lines'->0->>'deliveredOutputQuantity')::numeric<>50
     or (v_position->'lines'->0->>'acceptedOutputQuantity')::numeric<>48
     or (v_position->'lines'->0->>'rejectedOutputQuantity')::numeric<>2
     or (v_position->'lines'->0->>'remainingExpectedOutputQuantity')::numeric<>50
     or (v_position->'lines'->0->>'acceptedAllocatedQuantity')::numeric<>48 then
    raise exception 'Partial fulfillment position failed: %',v_position;
  end if;

  -- 2. Coverage is split between actual accepted output and residual commitment,
  -- but remains exact for every Work Requirement.
  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);

  if v_coverage->>'coverageMode'<>'split_commitment_and_accepted_fulfillment'
     or jsonb_array_length(v_coverage->'facts')<>6 then
    raise exception 'Partial fulfillment coverage split failed: %',v_coverage;
  end if;

  select coalesce(jsonb_agg(value->'coverageFact'),'[]'::jsonb)
  into v_facts
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_r40;

  v_check:=atlas.work_requirement_coverage_position_v1(v_r40,v_facts);

  if v_check->>'hardCoverageState'<>'exact'
     or (v_check->>'securedQuantity')::numeric<>40
     or jsonb_array_length(v_facts)<>2 then
    raise exception 'Partial handoff double-counted or dropped 40-unit coverage: %',v_check;
  end if;

  select coalesce(jsonb_agg(value->'coverageFact'),'[]'::jsonb)
  into v_facts
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_r30;

  v_check:=atlas.work_requirement_coverage_position_v1(v_r30,v_facts);

  if v_check->>'hardCoverageState'<>'exact'
     or (v_check->>'securedQuantity')::numeric<>30 then
    raise exception 'Partial handoff failed 30-unit coverage: %',v_check;
  end if;

  select coalesce(jsonb_agg(value->'coverageFact'),'[]'::jsonb)
  into v_facts
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_r20;

  v_check:=atlas.work_requirement_coverage_position_v1(v_r20,v_facts);

  if v_check->>'hardCoverageState'<>'exact'
     or (v_check->>'securedQuantity')::numeric<>20 then
    raise exception 'Partial handoff failed 20-unit coverage: %',v_check;
  end if;

  -- 3. Retry is idempotent.
  v_result:=atlas.record_external_acquisition_fulfillment_service_v1(v_f1);

  if coalesce((v_result->>'created')::boolean,true)
     or (v_result->>'externalAcquisitionFulfillmentId')::uuid<>v_fulfillment_id then
    raise exception 'Fulfillment writer is not idempotent: %',v_result;
  end if;

  -- 4. Same key with changed condition truth conflicts.
  begin
    perform atlas.record_external_acquisition_fulfillment_service_v1(
      jsonb_set(v_f1,'{lines,0,rejectedOutputQuantity}','3'::jsonb,false)
    );
    raise exception 'Changed fulfillment truth was admitted under same key.';
  exception when sqlstate '23505' then
    null;
  end;

  -- 5. Partition mismatch fails closed.
  v_preview:=atlas.external_acquisition_fulfillment_preview_v1(
    jsonb_set(
      jsonb_set(v_f1,'{fulfillmentKey}','"fixture:bad-partition"'::jsonb,false),
      '{lines,0,acceptedOutputQuantity}','47'::jsonb,false
    )
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='output_partition_mismatch'
     ) then
    raise exception 'Invalid fulfillment quantity partition was admitted: %',v_preview;
  end if;

  -- 6. Allocations cannot exceed accepted output.
  v_preview:=atlas.external_acquisition_fulfillment_preview_v1(
    jsonb_set(
      jsonb_set(v_f1,'{fulfillmentKey}','"fixture:overallocate-accepted"'::jsonb,false),
      '{lines,0,allocations,0,acceptedCoverageQuantity}','30'::jsonb,false
    )
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='allocations_exceed_accepted_output'
     ) then
    raise exception 'Accepted-output overallocation was admitted: %',v_preview;
  end if;

  -- 7. Second receipt completes delivery with 47 accepted / 3 rejected.
  -- Only 42 accepted units are needed by the prior customer allocations,
  -- leaving 5 accepted units explicit and unallocated.
  v_f2:=jsonb_build_object(
    'contractVersion','external_acquisition_fulfillment_input_v1',
    'externalAcquisitionCommitmentId',v_commitment_id,
    'fulfillmentKey','fixture:delivery-2',
    'fulfillmentKind','delivery',
    'occurredAt','2026-09-25T15:00:00Z',
    'source',jsonb_build_object(
      'kind','receiving_observation',
      'ref','fixture:delivery-2'
    ),
    'lines',jsonb_build_array(
      jsonb_build_object(
        'lineKey','carnations-2',
        'externalAcquisitionCommitmentLineId',v_line_id,
        'sourceQuantity',50,
        'sourceUnit','stem',
        'deliveredOutputQuantity',50,
        'acceptedOutputQuantity',47,
        'rejectedOutputQuantity',3,
        'unresolvedOutputQuantity',0,
        'coverageOutputUnit','stem',
        'condition',jsonb_build_object(
          'summary','47 acceptable, 3 damaged'
        ),
        'allocations',jsonb_build_array(
          jsonb_build_object(
            'allocationKey','buyer-40-part-2',
            'externalAcquisitionRequirementAllocationId',v_a40,
            'acceptedCoverageQuantity',20,
            'coverageUnit','stem'
          ),
          jsonb_build_object(
            'allocationKey','buyer-30-part-2',
            'externalAcquisitionRequirementAllocationId',v_a30,
            'acceptedCoverageQuantity',12,
            'coverageUnit','stem'
          ),
          jsonb_build_object(
            'allocationKey','buyer-20-part-2',
            'externalAcquisitionRequirementAllocationId',v_a20,
            'acceptedCoverageQuantity',10,
            'coverageUnit','stem'
          )
        )
      )
    )
  );

  v_result:=atlas.record_external_acquisition_fulfillment_service_v1(v_f2);

  if coalesce((v_result->>'created')::boolean,false)=false then
    raise exception 'Second fulfillment writer failed: %',v_result;
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(v_commitment_id);

  if v_position->>'state'<>'fulfilled_with_exception'
     or (v_position->'lines'->0->>'deliveredOutputQuantity')::numeric<>100
     or (v_position->'lines'->0->>'acceptedOutputQuantity')::numeric<>95
     or (v_position->'lines'->0->>'rejectedOutputQuantity')::numeric<>5
     or (v_position->'lines'->0->>'acceptedAllocatedQuantity')::numeric<>90
     or (v_position->'lines'->0->>'acceptedUnallocatedQuantity')::numeric<>5
     or (v_position->'lines'->0->>'remainingExpectedOutputQuantity')::numeric<>0 then
    raise exception 'Completed fulfillment-with-exception position failed: %',v_position;
  end if;

  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);

  if jsonb_array_length(v_coverage->'facts')<>6
     or exists(
       select 1
       from jsonb_array_elements(v_coverage->'facts') x
       where x->'coverageFact'->'metadata'->>'coverageLayer'
             <>'accepted_external_fulfillment'
          or x->'coverageFact'->>'state'<>'secured'
     ) then
    raise exception 'Full accepted handoff left residual supplier coverage: %',v_coverage;
  end if;

  select coalesce(jsonb_agg(value->'coverageFact'),'[]'::jsonb)
  into v_facts
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_r40;

  v_check:=atlas.work_requirement_coverage_position_v1(v_r40,v_facts);

  if v_check->>'hardCoverageState'<>'exact'
     or (v_check->>'securedQuantity')::numeric<>40 then
    raise exception 'Full accepted handoff failed 40-unit coverage: %',v_check;
  end if;

  -- 8. A fulfilled-with-exception acquisition may close without losing accepted coverage.
  perform atlas.record_external_acquisition_commitment_event_service_v1(
    v_commitment_id,
    'fixture:close-after-receipt',
    'closed',
    '2026-09-25T15:30:00Z',
    '{"kind":"authorized_human_report","ref":"fixture:close"}'::jsonb,
    '{"acceptedException":true}'::jsonb
  );

  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);

  if exists(
       select 1 from jsonb_array_elements(v_coverage->'facts') x
       where x->'coverageFact'->>'state'<>'secured'
     ) then
    raise exception 'Closing fulfilled acquisition disturbed accepted fulfillment coverage: %',v_coverage;
  end if;

  -- 9. Cancellation after partial fulfillment keeps accepted reality and releases only residual commitment.
  v_commitment_result:=atlas.record_external_acquisition_commitment_service_v1(
    jsonb_set(
      v_commitment_input,
      '{commitmentKey}',
      '"fixture:fulfillment:cancel-after-partial"'::jsonb,
      false
    )
  );
  v_cancel_commitment_id:=(v_commitment_result->>'externalAcquisitionCommitmentId')::uuid;

  select l.id into v_cancel_line_id
  from atlas.external_acquisition_commitment_lines l
  where l.external_acquisition_commitment_id=v_cancel_commitment_id
    and l.line_key='carnations';

  select a.id into v_ca40
  from atlas.external_acquisition_requirement_allocations a
  where a.external_acquisition_commitment_line_id=v_cancel_line_id
    and a.work_requirement_id=v_r40;

  select a.id into v_ca30
  from atlas.external_acquisition_requirement_allocations a
  where a.external_acquisition_commitment_line_id=v_cancel_line_id
    and a.work_requirement_id=v_r30;

  select a.id into v_ca20
  from atlas.external_acquisition_requirement_allocations a
  where a.external_acquisition_commitment_line_id=v_cancel_line_id
    and a.work_requirement_id=v_r20;

  perform atlas.record_external_acquisition_fulfillment_service_v1(
    jsonb_build_object(
      'contractVersion','external_acquisition_fulfillment_input_v1',
      'externalAcquisitionCommitmentId',v_cancel_commitment_id,
      'fulfillmentKey','fixture:cancel-path-delivery-1',
      'fulfillmentKind','delivery',
      'occurredAt','2026-09-25T13:30:00Z',
      'source',jsonb_build_object('kind','receiving_observation'),
      'lines',jsonb_build_array(
        jsonb_build_object(
          'lineKey','carnations-1',
          'externalAcquisitionCommitmentLineId',v_cancel_line_id,
          'deliveredOutputQuantity',50,
          'acceptedOutputQuantity',48,
          'rejectedOutputQuantity',2,
          'unresolvedOutputQuantity',0,
          'coverageOutputUnit','stem',
          'allocations',jsonb_build_array(
            jsonb_build_object(
              'allocationKey','buyer-40-part-1',
              'externalAcquisitionRequirementAllocationId',v_ca40,
              'acceptedCoverageQuantity',20,
              'coverageUnit','stem'
            ),
            jsonb_build_object(
              'allocationKey','buyer-30-part-1',
              'externalAcquisitionRequirementAllocationId',v_ca30,
              'acceptedCoverageQuantity',18,
              'coverageUnit','stem'
            ),
            jsonb_build_object(
              'allocationKey','buyer-20-part-1',
              'externalAcquisitionRequirementAllocationId',v_ca20,
              'acceptedCoverageQuantity',10,
              'coverageUnit','stem'
            )
          )
        )
      )
    )
  );

  -- 10. Actual overdelivery is preserved as a warning rather than suppressed.
  v_preview:=atlas.external_acquisition_fulfillment_preview_v1(
    jsonb_build_object(
      'contractVersion','external_acquisition_fulfillment_input_v1',
      'externalAcquisitionCommitmentId',v_cancel_commitment_id,
      'fulfillmentKey','fixture:overdelivery-preview',
      'fulfillmentKind','delivery',
      'occurredAt','2026-09-25T13:50:00Z',
      'source',jsonb_build_object('kind','receiving_observation'),
      'lines',jsonb_build_array(
        jsonb_build_object(
          'lineKey','overdelivery',
          'externalAcquisitionCommitmentLineId',v_cancel_line_id,
          'deliveredOutputQuantity',60,
          'acceptedOutputQuantity',60,
          'rejectedOutputQuantity',0,
          'unresolvedOutputQuantity',0,
          'coverageOutputUnit','stem'
        )
      )
    )
  );

  if v_preview->>'state'<>'ready'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'warnings') x
       where x->>'key'='actual_overdelivery'
         and (x->>'cumulativeDeliveredOutputQuantity')::numeric=110
     ) then
    raise exception 'Actual overdelivery was not preserved as explicit warning: %',v_preview;
  end if;

  perform atlas.record_external_acquisition_commitment_event_service_v1(
    v_cancel_commitment_id,
    'fixture:cancel-after-partial',
    'cancelled',
    '2026-09-25T14:00:00Z',
    '{"kind":"supplier_confirmation"}'::jsonb,
    '{}'::jsonb
  );

  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(
    v_cancel_commitment_id
  );

  select coalesce(jsonb_agg(value->'coverageFact'),'[]'::jsonb)
  into v_facts
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_r40;

  v_check:=atlas.work_requirement_coverage_position_v1(v_r40,v_facts);

  if v_check->>'hardCoverageState'<>'partial'
     or (v_check->>'securedQuantity')::numeric<>20
     or (v_check->>'releasedFactCount')::integer<>1 then
    raise exception 'Cancellation after partial fulfillment erased or retained wrong coverage: %',v_check;
  end if;

  -- 11. Fulfillment history is immutable.
  begin
    update atlas.external_acquisition_fulfillments
    set metadata='{"mutated":true}'::jsonb
    where id=v_fulfillment_id;
    raise exception 'Immutable External Acquisition Fulfillment was updated.';
  exception when sqlstate '55000' then
    null;
  end;

  -- 12. Recording supplier fulfillment creates no downstream inventory, Spend, payment,
  -- sell-side order, or Company Work mutation.
  if (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.work_requirements)<>v_before_work then
    raise exception 'External Acquisition Fulfillment created downstream truth.';
  end if;

  -- 13. Browser roles cannot call or directly write fulfillment authority.
  if has_function_privilege(
       'authenticated',
       'atlas.external_acquisition_fulfillment_preview_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.record_external_acquisition_fulfillment_service_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.external_acquisition_fulfillment_position_v1(uuid)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'atlas.external_acquisition_fulfillments',
       'INSERT'
     )
     or has_table_privilege(
       'service_role',
       'atlas.external_acquisition_fulfillment_lines',
       'INSERT'
     )
     or has_table_privilege(
       'service_role',
       'atlas.external_acquisition_fulfillment_allocations',
       'INSERT'
     ) then
    raise exception 'External Acquisition Fulfillment privilege boundary is incorrect.';
  end if;

  if not has_function_privilege(
       'service_role',
       'atlas.record_external_acquisition_fulfillment_service_v1(jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Service role cannot execute fulfillment writer.';
  end if;

  if not exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='record_external_acquisition_fulfillment_service_v1'
      and p.prosecdef
  )
  or exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'external_acquisition_fulfillment_preview_v1',
        'external_acquisition_fulfillment_position_v1'
      )
      and p.prosecdef
  ) then
    raise exception 'External Acquisition Fulfillment SECURITY DEFINER boundary is incorrect.';
  end if;

  raise notice 'PASS atlas_external_acquisition_fulfillment_intake_v1: partial quantitative handoff, exact split coverage, accepted/rejected/excess truth, cancellation residual release, immutability, and no downstream side effects hold';
end;
$validation$;

rollback;
