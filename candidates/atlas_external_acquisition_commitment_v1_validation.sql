begin;

do $validation$
declare
  v_org_id uuid;
  v_other_org_id uuid;
  v_supplier_subject_id uuid;
  v_supplier_relationship_id uuid;
  v_other_supplier_subject_id uuid;
  v_other_supplier_relationship_id uuid;
  v_offering_id uuid;
  v_other_offering_id uuid;
  v_observation_id uuid;
  v_other_observation_id uuid;

  v_r40 uuid;
  v_r30 uuid;
  v_r20 uuid;
  v_other_r uuid;

  v_input jsonb;
  v_preview jsonb;
  v_result jsonb;
  v_commitment_id uuid;
  v_position jsonb;
  v_coverage jsonb;

  v_before_spend bigint;
  v_before_inventory bigint;
  v_before_orders bigint;
  v_before_payments bigint;
  v_before_work bigint;

  v_fact jsonb;
begin
  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_external_acquisition_v1',
    'Fixture External Acquisition Organization',
    'active',
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  )
  returning id into v_org_id;

  insert into atlas.organizations(stable_key,name,status,metadata)
  values(
    'fixture_external_acquisition_other_v1',
    'Fixture External Acquisition Other Organization',
    'active',
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  )
  returning id into v_other_org_id;

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(v_org_id,'{"fixture":"supplier"}'::jsonb)
  returning id into v_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,v_supplier_subject_id,'fixture-supplier','active',
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  )
  returning id into v_supplier_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_supplier_relationship_id,'supplier','active',
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  );

  insert into atlas.identity_subjects(organization_id,creation_basis)
  values(v_org_id,'{"fixture":"other_supplier"}'::jsonb)
  returning id into v_other_supplier_subject_id;

  insert into atlas.external_relationships(
    organization_id,subject_id,stable_key,relationship_state,metadata
  ) values (
    v_org_id,v_other_supplier_subject_id,'fixture-other-supplier','active',
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  )
  returning id into v_other_supplier_relationship_id;

  insert into atlas.external_relationship_roles(
    external_relationship_id,role_key,role_state,basis
  ) values (
    v_other_supplier_relationship_id,'supplier','active',
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  );

  v_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,null,v_supplier_relationship_id,
    'fixture-carnation-100','fixture-carnation-100','Standard Carnations',
    'item','stem',
    '{"flowerFamily":"carnation","grade":"standard"}'::jsonb,
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  );

  v_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_offering_id,
    'fixture-carnation-quote',
    '2026-09-24T13:00:00Z'::timestamptz,
    '2026-09-24','2026-09-25',
    38.00,'USD','source_explicit',
    100,'stem',
    100,'stem',
    100,'stem',
    1,'day',
    'available',
    '{"freightIncluded":true}'::jsonb,
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb,
    'supplier_quote',
    'fixture:quote:carnation-100',
    null,null,
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  );
  v_observation_id:=(v_result->>'externalSupplyOfferObservationId')::uuid;

  v_other_offering_id:=atlas.ensure_external_supply_offering_service_v1(
    v_org_id,null,v_other_supplier_relationship_id,
    'fixture-other-offer','fixture-other-offer','Other Supplier Carnations',
    'item','stem',
    '{"flowerFamily":"carnation"}'::jsonb,
    '{"fixture":"atlas_external_acquisition_commitment_v1"}'::jsonb
  );

  v_result:=atlas.record_external_supply_offer_observation_service_v1(
    v_other_offering_id,
    'fixture-other-quote',
    '2026-09-24T13:00:00Z'::timestamptz,
    null,null,
    35.00,'USD','source_explicit',
    100,'stem',
    100,'stem',
    null,null,
    null,null,
    'available',
    '{}'::jsonb,'{}'::jsonb,
    'supplier_quote',
    'fixture:other',
    null,null,'{}'::jsonb
  );
  v_other_observation_id:=(v_result->>'externalSupplyOfferObservationId')::uuid;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_org_id,'fixture:acq:r40','fulfillment_coverage','Secure 40 carnations',
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
    v_org_id,'fixture:acq:r30','fulfillment_coverage','Secure 30 carnations',
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
    v_org_id,'fixture:acq:r20','fulfillment_coverage','Secure 20 carnations',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":20,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{"flowerFamily":"carnation"}}}'::jsonb
  )
  returning id into v_r20;

  insert into atlas.work_requirements(
    organization_id,stable_key,requirement_kind,summary,
    source_object_type,source_object_id,state,
    established_at,requirement_began_at,earliest_relevant_at,latest_satisfactory_at,
    consequence_of_delay,jurisdiction_key,metadata
  ) values
  (
    v_other_org_id,'fixture:acq:other','fulfillment_coverage','Other org requirement',
    'commercial_order_line',gen_random_uuid(),'active',
    '2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-24T12:00:00Z','2026-09-25T17:00:00Z',
    '{}'::jsonb,'commerce.fulfillment_coverage',
    '{"commercialFulfillment":{"quantity":10,"unit":"stem","requirementKey":"flowers","requirementClass":"product_coverage","specification":{}}}'::jsonb
  )
  returning id into v_other_r;

  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_work from atlas.work_requirements;

  v_input:=jsonb_build_object(
    'contractVersion','external_acquisition_commitment_input_v1',
    'organizationId',v_org_id,
    'supplierRelationshipId',v_supplier_relationship_id,
    'commitmentKey','fixture:carnation-po-100',
    'commitmentKind','supplier_order',
    'committedAt','2026-09-24T14:00:00Z',
    'expectedFulfillmentFromAt','2026-09-25T13:00:00Z',
    'expectedFulfillmentByAt','2026-09-25T16:00:00Z',
    'acceptedTerms',jsonb_build_object(
      'paymentTerms','card_on_file',
      'freightIncluded',true
    ),
    'economics',jsonb_build_object(
      'state','known',
      'knownCommittedAmount',38.00,
      'currency','USD',
      'costComponents',jsonb_build_array(
        jsonb_build_object(
          'componentKey','landed_pool_cost',
          'state','known',
          'amount',38.00,
          'currency','USD'
        )
      )
    ),
    'source',jsonb_build_object(
      'kind','supplier_confirmation',
      'ref','fixture:supplier-order-100'
    ),
    'authorizationBasis',jsonb_build_object(
      'authorityRef','fixture:purchasing-policy',
      'decisionRef','fixture:approved-pool-plan',
      'authorizedAt','2026-09-24T13:55:00Z'
    ),
    'lines',jsonb_build_array(
      jsonb_build_object(
        'lineKey','carnations',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLineKey','supplier-line-1',
        'description','100 Standard Carnations',
        'orderedQuantity',100,
        'orderedUnit','stem',
        'coverageOutputQuantity',100,
        'coverageOutputUnit','stem',
        'knownLineAmount',38.00,
        'currency','USD',
        'acceptedTerms',jsonb_build_object('freightIncluded',true),
        'metadata',jsonb_build_object('transformationBasis','1 ordered stem = 1 coverage stem'),
        'allocations',jsonb_build_array(
          jsonb_build_object(
            'allocationKey','wickmans',
            'workRequirementId',v_r40,
            'coverageQuantity',40,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:one-pack-three-buyers')
          ),
          jsonb_build_object(
            'allocationKey','flowerama',
            'workRequirementId',v_r30,
            'coverageQuantity',30,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:one-pack-three-buyers')
          ),
          jsonb_build_object(
            'allocationKey','buyer-c',
            'workRequirementId',v_r20,
            'coverageQuantity',20,
            'coverageUnit','stem',
            'qualificationBasis',jsonb_build_object('state','qualified'),
            'planningBasis',jsonb_build_object('poolKey','fixture:one-pack-three-buyers')
          )
        )
      )
    ),
    'metadata',jsonb_build_object(
      'fixture','atlas_external_acquisition_commitment_v1'
    )
  );

  -- 1. Preview is ready and read-only.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(v_input);

  if v_preview->>'state'<>'ready'
     or (v_preview->>'lineCount')::integer<>1
     or (v_preview->>'allocationCount')::integer<>3
     or v_preview->>'economicState'<>'known'
     or (v_preview->>'knownCommittedAmount')::numeric<>38
     or jsonb_array_length(v_preview->'violations')<>0 then
    raise exception 'External acquisition preview failed: %',v_preview;
  end if;

  if exists(select 1 from atlas.external_acquisition_commitments where organization_id=v_org_id) then
    raise exception 'External acquisition preview created commitment truth.';
  end if;

  -- 2. Record real buy-side commitment.
  v_result:=atlas.record_external_acquisition_commitment_service_v1(v_input);
  v_commitment_id:=(v_result->>'externalAcquisitionCommitmentId')::uuid;

  if v_commitment_id is null
     or coalesce((v_result->>'created')::boolean,false)=false then
    raise exception 'External acquisition commitment writer failed: %',v_result;
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(v_commitment_id);

  if v_position->>'state'<>'committed'
     or v_position->>'economicState'<>'known'
     or (v_position->>'knownCommittedAmount')::numeric<>38
     or jsonb_array_length(v_position->'lines')<>1
     or (v_position->'lines'->0->>'allocatedCoverageQuantity')::numeric<>90
     or (v_position->'lines'->0->>'unallocatedCoverageOutputQuantity')::numeric<>10
     or jsonb_array_length(v_position->'lines'->0->'allocations')<>3 then
    raise exception 'External acquisition position failed: %',v_position;
  end if;

  -- 3. Financial obligation exists before Spend/payment/inventory.
  if (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.work_requirements)<>v_before_work then
    raise exception 'External acquisition commitment created Spend/inventory/sell-side/payment/new-Work truth.';
  end if;

  -- 4. Same packet is idempotent.
  v_result:=atlas.record_external_acquisition_commitment_service_v1(v_input);

  if coalesce((v_result->>'created')::boolean,true)
     or (v_result->>'externalAcquisitionCommitmentId')::uuid<>v_commitment_id then
    raise exception 'External acquisition writer is not idempotent: %',v_result;
  end if;

  -- 5. Same key with changed truth conflicts.
  begin
    perform atlas.record_external_acquisition_commitment_service_v1(
      jsonb_set(v_input,'{economics,knownCommittedAmount}','39'::jsonb,false)
    );
    raise exception 'Changed acquisition truth was admitted under same commitment key.';
  exception when sqlstate '23505' then
    null;
  end;

  -- 6. Authorization must precede commitment.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(v_input,'{authorizationBasis,authorizedAt}','"2026-09-24T14:05:00Z"'::jsonb,false)
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='authorization_after_commitment'
     ) then
    raise exception 'Post-commitment authorization was admitted: %',v_preview;
  end if;

  -- 7. Wrong supplier offering cannot enter this supplier commitment.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(v_input,'{commitmentKey}','"fixture:wrong-supplier-offer"'::jsonb,false),
      '{lines,0,externalSupplyOfferingId}',
      to_jsonb(v_other_offering_id::text),
      false
    )
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='invalid_line_offering'
     ) then
    raise exception 'Offering from another supplier was admitted: %',v_preview;
  end if;

  -- 8. Cross-organization Work Requirement cannot be allocated.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(v_input,'{commitmentKey}','"fixture:cross-org"'::jsonb,false),
      '{lines,0,allocations,2,workRequirementId}',
      to_jsonb(v_other_r::text),
      false
    )
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='invalid_allocation_requirement'
     ) then
    raise exception 'Cross-organization requirement allocation was admitted: %',v_preview;
  end if;

  -- 9. Allocations cannot exceed line coverage output.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(v_input,'{commitmentKey}','"fixture:overallocated"'::jsonb,false),
      '{lines,0,allocations,2,coverageQuantity}',
      '40'::jsonb,
      false
    )
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='allocations_exceed_line_output'
     ) then
    raise exception 'Line overallocation was admitted: %',v_preview;
  end if;

  -- 10. Known economics cannot hide unresolved required freight.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(v_input,'{commitmentKey}','"fixture:known-with-unknown-freight"'::jsonb,false),
      '{economics,costComponents}',
      '[
        {"componentKey":"merchandise","state":"known","amount":31,"currency":"USD"},
        {"componentKey":"freight","state":"unresolved","required":true}
      ]'::jsonb,
      false
    )
  );

  if v_preview->>'state'<>'blocked'
     or not exists(
       select 1 from jsonb_array_elements(v_preview->'violations') x
       where x->>'key'='known_economics_has_unresolved_required_component'
     ) then
    raise exception 'Known economics hid unresolved required component: %',v_preview;
  end if;

  -- 11. Partially-known economics requires and preserves unresolved required component.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(
        jsonb_set(v_input,'{commitmentKey}','"fixture:partial-economics"'::jsonb,false),
        '{economics,state}','"partially_known"'::jsonb,false
      ),
      '{economics,knownCommittedAmount}','31'::jsonb,false
    )
  );
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(v_input,'{commitmentKey}','"fixture:partial-economics"'::jsonb,false),
          '{economics,state}','"partially_known"'::jsonb,false
        ),
        '{economics,knownCommittedAmount}','31'::jsonb,false
      ),
      '{economics,costComponents}',
      '[
        {"componentKey":"merchandise","state":"known","amount":31,"currency":"USD"},
        {"componentKey":"freight","state":"unresolved","required":true}
      ]'::jsonb,
      false
    )
  );

  if v_preview->>'state'<>'ready'
     or v_preview->>'economicState'<>'partially_known'
     or (v_preview->>'knownCommittedAmount')::numeric<>31 then
    raise exception 'Partially-known acquisition economics failed: %',v_preview;
  end if;

  -- 12. Unresolved economics may not assert a numeric obligation.
  v_preview:=atlas.external_acquisition_commitment_preview_v1(
    jsonb_set(
      jsonb_set(
        jsonb_set(v_input,'{commitmentKey}','"fixture:unresolved-economics"'::jsonb,false),
        '{economics,state}','"unresolved"'::jsonb,false
      ),
      '{economics,knownCommittedAmount}','null'::jsonb,false
    )
  );

  if v_preview->>'state'<>'ready'
     or v_preview->>'economicState'<>'unresolved'
     or v_preview->>'knownCommittedAmount' is not null then
    raise exception 'Unresolved acquisition economics failed: %',v_preview;
  end if;

  -- 13. Before physical/service fulfillment, commitment allocations emit secured residual coverage.
  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);

  if v_coverage->>'coverageMode'<>'split_commitment_and_accepted_fulfillment'
     or jsonb_array_length(v_coverage->'facts')<>3
     or exists(
       select 1
       from jsonb_array_elements(v_coverage->'facts') x
       where x->'coverageFact'->>'state'<>'secured'
          or x->'coverageFact'->'metadata'->>'coverageLayer'
             <>'remaining_supplier_commitment'
     ) then
    raise exception 'Committed acquisition residual coverage adapter failed: %',v_coverage;
  end if;

  select value into v_fact
  from jsonb_array_elements(v_coverage->'facts')
  where (value->>'workRequirementId')::uuid=v_r40
  limit 1;

  v_result:=atlas.work_requirement_coverage_position_v1(
    v_r40,
    jsonb_build_array(v_fact->'coverageFact')
  );

  if v_result->>'hardCoverageState'<>'exact'
     or (v_result->>'securedQuantity')::numeric<>40 then
    raise exception 'External acquisition did not secure 40-unit Work Requirement: %',v_result;
  end if;

  -- 14. Cancellation releases only outstanding supplier-commitment coverage.
  v_result:=atlas.record_external_acquisition_commitment_event_service_v1(
    v_commitment_id,
    'fixture:cancel',
    'cancelled',
    '2026-09-24T15:00:00Z'::timestamptz,
    '{"kind":"supplier_confirmation","ref":"fixture:cancel"}'::jsonb,
    '{"reason":"fixture"}'::jsonb
  );

  if v_result->'position'->>'state'<>'cancelled' then
    raise exception 'Cancellation event failed: %',v_result;
  end if;

  -- Retry same event stays idempotent.
  v_result:=atlas.record_external_acquisition_commitment_event_service_v1(
    v_commitment_id,
    'fixture:cancel',
    'cancelled',
    '2026-09-24T15:00:00Z'::timestamptz,
    '{"kind":"supplier_confirmation","ref":"fixture:cancel"}'::jsonb,
    '{"reason":"fixture"}'::jsonb
  );

  if coalesce((v_result->>'created')::boolean,true) then
    raise exception 'Lifecycle event retry was not idempotent: %',v_result;
  end if;

  v_coverage:=atlas.external_acquisition_commitment_coverage_facts_v1(v_commitment_id);

  if jsonb_array_length(v_coverage->'facts')<>3
     or exists(
       select 1
       from jsonb_array_elements(v_coverage->'facts') x
       where x->'coverageFact'->>'state'<>'released'
     ) then
    raise exception 'Cancelled acquisition did not release residual commitment coverage: %',v_coverage;
  end if;

  -- There is no free-standing received lifecycle event anymore.
  begin
    perform atlas.record_external_acquisition_commitment_event_service_v1(
      v_commitment_id,'fixture:bad-receive','received',
      '2026-09-24T15:05:00Z',
      '{"kind":"supplier_confirmation"}'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Deprecated free-standing received event was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- A cancelled commitment may close.
  perform atlas.record_external_acquisition_commitment_event_service_v1(
    v_commitment_id,'fixture:close','closed',
    '2026-09-24T15:10:00Z',
    '{"kind":"authorized_human_report"}'::jsonb,
    '{}'::jsonb
  );

  begin
    perform atlas.record_external_acquisition_commitment_event_service_v1(
      v_commitment_id,'fixture:after-close','closed',
      '2026-09-24T15:20:00Z',
      '{"kind":"authorized_human_report"}'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Closed acquisition accepted another lifecycle transition.';
  exception when sqlstate '23514' then
    null;
  end;

  -- 15. Accepted commitment truth is immutable.
  begin
    update atlas.external_acquisition_commitments
    set accepted_terms='{"mutated":true}'::jsonb
    where id=v_commitment_id;
    raise exception 'Immutable acquisition commitment was updated.';
  exception when sqlstate '55000' then
    null;
  end;

  begin
    delete from atlas.external_acquisition_commitment_lines
    where external_acquisition_commitment_id=v_commitment_id;
    raise exception 'Immutable acquisition line was deleted.';
  exception when sqlstate '55000' then
    null;
  end;

  -- 16. Consequential writer still creates no Spend/inventory/payment/sell-side/new Work.
  if (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_inventory
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.work_requirements)<>v_before_work then
    raise exception 'External acquisition lifecycle created downstream Spend/inventory/payment/order/new-Work truth.';
  end if;

  -- 17. Browser roles cannot invoke internal authority.
  if has_function_privilege(
       'authenticated',
       'atlas.external_acquisition_commitment_preview_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.record_external_acquisition_commitment_service_v1(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.external_acquisition_commitment_position_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.external_acquisition_commitment_coverage_facts_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated browser role received external acquisition authority.';
  end if;

  if not has_function_privilege(
       'service_role',
       'atlas.record_external_acquisition_commitment_service_v1(jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Service role cannot execute external acquisition writer.';
  end if;

  -- 18. Consequential writers are SECURITY DEFINER; read evaluators are not.
  if not exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='record_external_acquisition_commitment_service_v1'
      and p.prosecdef
  )
  or not exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='record_external_acquisition_commitment_event_service_v1'
      and p.prosecdef
  )
  or exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'external_acquisition_commitment_preview_v1',
        'external_acquisition_commitment_position_v1',
        'external_acquisition_commitment_coverage_facts_v1'
      )
      and p.prosecdef
  ) then
    raise exception 'External acquisition SECURITY DEFINER boundary is incorrect.';
  end if;

  if has_table_privilege('service_role','atlas.external_acquisition_commitments','INSERT')
     or has_table_privilege('service_role','atlas.external_acquisition_commitment_lines','INSERT')
     or has_table_privilege('service_role','atlas.external_acquisition_requirement_allocations','INSERT')
     or has_table_privilege('service_role','atlas.external_acquisition_commitment_events','INSERT') then
    raise exception 'Service role can bypass governed External Acquisition writers with direct table insert.';
  end if;

  raise notice 'PASS atlas_external_acquisition_commitment_v1: authorized immutable buy-side commitment, governed write boundary, known/partial/unresolved obligation, 40/30/20 secured coverage, 10-unit remainder, residual-release semantics, and no Spend/inventory side effects hold';
end;
$validation$;

rollback;
