begin;

create or replace function atlas.commercial_order_fulfillment_requirements_preview_v1(
  p_commercial_order_id uuid,
  p_requirements jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_order atlas.commercial_orders%rowtype;
  v_req jsonb;
  v_existing atlas.work_requirements%rowtype;
  v_line_id uuid;
  v_line atlas.commercial_order_lines%rowtype;

  v_key text;
  v_class text;
  v_summary text;
  v_jurisdiction text;
  v_stable_key text;
  v_source_type text;
  v_source_id uuid;

  v_quantity numeric;
  v_unit text;
  v_specification jsonb;
  v_domain_metadata jsonb;
  v_consequence jsonb;
  v_expected_metadata jsonb;

  v_requirement_began_at timestamptz;
  v_earliest_relevant_at timestamptz;
  v_latest_satisfactory_at timestamptz;

  v_keys text[]:='{}'::text[];
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_normalized jsonb:='[]'::jsonb;

  v_cancelled boolean:=false;
  v_commitment_at timestamptz;
  v_commitment_time_basis text;
  v_compatible boolean;
  v_would_create integer:=0;
  v_existing_count integer:=0;
begin
  if p_requirements is null or jsonb_typeof(p_requirements)<>'array' then
    raise exception 'Requirements must be a JSON array.'
      using errcode='22023';
  end if;

  if p_interpretation_basis is null or jsonb_typeof(p_interpretation_basis)<>'object' then
    raise exception 'Interpretation basis must be a JSON object.'
      using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_interpretation_basis->>'adapterKey','')),'') is null
     or nullif(btrim(coalesce(p_interpretation_basis->>'adapterVersion','')),'') is null then
    raise exception 'Interpretation basis requires adapterKey and adapterVersion.'
      using errcode='22023';
  end if;

  select * into v_order
  from atlas.commercial_orders
  where id=p_commercial_order_id;

  if v_order.id is null then
    raise exception 'Commercial Order not found.'
      using errcode='P0002';
  end if;

  select min(e.occurred_at)
  into v_commitment_at
  from atlas.commercial_order_events e
  where e.commercial_order_id=v_order.id
    and e.event_kind='recorded';

  if v_commitment_at is null then
    v_commitment_at:=v_order.created_at;
    v_commitment_time_basis:='order_created_at_fallback';
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object(
      'key','commitment_time_fallback',
      'message','No recorded Commercial Order event exists; using order.created_at as commitment timestamp fallback.'
    ));
  else
    v_commitment_time_basis:='commercial_order_event_recorded';
  end if;

  select exists(
    select 1
    from atlas.commercial_order_events e
    where e.commercial_order_id=v_order.id
      and e.event_kind='cancelled'
  ) into v_cancelled;

  if v_cancelled then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','commercial_order_cancelled',
      'message','Cancelled Commercial Order cannot establish new active fulfillment requirements.'
    ));
  end if;

  for v_req in
    select value
    from jsonb_array_elements(p_requirements)
  loop
    v_line_id:=null;
    v_line:=null;
    v_quantity:=null;
    v_unit:=null;
    v_requirement_began_at:=v_commitment_at;
    v_earliest_relevant_at:=v_commitment_at;
    v_latest_satisfactory_at:=null;
    v_existing:=null;

    if jsonb_typeof(v_req)<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','requirement_not_object',
        'message','Each fulfillment requirement must be a JSON object.'
      ));
      continue;
    end if;

    v_key:=nullif(btrim(coalesce(v_req->>'requirementKey','')),'');
    if v_key is null or v_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_key',
        'requirementKey',v_req->>'requirementKey',
        'message','requirementKey must be a stable 1-128 character identifier.'
      ));
      continue;
    end if;

    if v_key=any(v_keys) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','duplicate_requirement_key',
        'requirementKey',v_key
      ));
      continue;
    end if;
    v_keys:=array_append(v_keys,v_key);

    v_class:=nullif(btrim(coalesce(v_req->>'requirementClass','')),'');
    if v_class is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_requirement_class',
        'requirementKey',v_key
      ));
    end if;

    v_summary:=nullif(btrim(coalesce(v_req->>'summary','')),'');
    if v_summary is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_summary',
        'requirementKey',v_key
      ));
    end if;

    v_jurisdiction:=nullif(btrim(coalesce(v_req->>'jurisdictionKey','')),'');
    if v_jurisdiction is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_jurisdiction',
        'requirementKey',v_key
      ));
    end if;

    if v_req ? 'sourceOrderLineId' and v_req->>'sourceOrderLineId' is not null then
      begin
        v_line_id:=nullif(btrim(v_req->>'sourceOrderLineId'),'')::uuid;
      exception when invalid_text_representation then
        v_line_id:=null;
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_source_order_line_id',
          'requirementKey',v_key
        ));
      end;

      if v_line_id is not null then
        select * into v_line
        from atlas.commercial_order_lines
        where id=v_line_id;

        if v_line.id is null or v_line.commercial_order_id is distinct from v_order.id then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','source_order_line_outside_order',
            'requirementKey',v_key,
            'sourceOrderLineId',v_line_id
          ));
        end if;
      end if;
    end if;

    if v_line_id is null then
      v_source_type:='commercial_order';
      v_source_id:=v_order.id;
    else
      v_source_type:='commercial_order_line';
      v_source_id:=v_line_id;
    end if;

    if v_req ? 'quantity' then
      if jsonb_typeof(v_req->'quantity')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_quantity',
          'requirementKey',v_key
        ));
      else
        v_quantity:=(v_req->>'quantity')::numeric;
        if v_quantity<=0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_quantity',
            'requirementKey',v_key,
            'message','quantity must be greater than zero.'
          ));
        end if;
      end if;

      v_unit:=nullif(btrim(coalesce(v_req->>'unit','')),'');
      if v_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','quantity_without_unit',
          'requirementKey',v_key
        ));
      end if;
    elsif v_req ? 'unit' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','unit_without_quantity',
        'requirementKey',v_key
      ));
    end if;

    if v_req ? 'specification' then
      if jsonb_typeof(v_req->'specification')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_specification',
          'requirementKey',v_key
        ));
        v_specification:='{}'::jsonb;
      else
        v_specification:=v_req->'specification';
      end if;
    else
      v_specification:='{}'::jsonb;
    end if;

    if v_req ? 'metadata' then
      if jsonb_typeof(v_req->'metadata')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_metadata',
          'requirementKey',v_key
        ));
        v_domain_metadata:='{}'::jsonb;
      else
        v_domain_metadata:=v_req->'metadata';
      end if;
    else
      v_domain_metadata:='{}'::jsonb;
    end if;

    if not (v_req ? 'consequenceOfDelay')
       or jsonb_typeof(v_req->'consequenceOfDelay')<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_consequence_of_delay',
        'requirementKey',v_key,
        'message','consequenceOfDelay must be an explicit JSON object.'
      ));
      v_consequence:='{}'::jsonb;
    else
      v_consequence:=v_req->'consequenceOfDelay';
    end if;

    if v_req ? 'requirementBeganAt' and nullif(btrim(coalesce(v_req->>'requirementBeganAt','')),'') is not null then
      begin
        v_requirement_began_at:=(v_req->>'requirementBeganAt')::timestamptz;
      exception when others then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_requirement_began_at',
          'requirementKey',v_key
        ));
      end;
    end if;

    v_earliest_relevant_at:=v_requirement_began_at;
    if v_req ? 'earliestRelevantAt' and nullif(btrim(coalesce(v_req->>'earliestRelevantAt','')),'') is not null then
      begin
        v_earliest_relevant_at:=(v_req->>'earliestRelevantAt')::timestamptz;
      exception when others then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_earliest_relevant_at',
          'requirementKey',v_key
        ));
      end;
    end if;

    if not (v_req ? 'latestSatisfactoryAt')
       or nullif(btrim(coalesce(v_req->>'latestSatisfactoryAt','')),'') is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_latest_satisfactory_at',
        'requirementKey',v_key
      ));
    else
      begin
        v_latest_satisfactory_at:=(v_req->>'latestSatisfactoryAt')::timestamptz;
      exception when others then
        v_latest_satisfactory_at:=null;
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_latest_satisfactory_at',
          'requirementKey',v_key
        ));
      end;
    end if;

    if v_latest_satisfactory_at is not null
       and v_earliest_relevant_at is not null
       and v_latest_satisfactory_at<v_earliest_relevant_at then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_window',
        'requirementKey',v_key,
        'message','latestSatisfactoryAt cannot precede earliestRelevantAt.'
      ));
    end if;

    v_stable_key:='commercial_order:'||v_order.id::text||':fulfillment:'||v_key;

    v_expected_metadata:=jsonb_build_object(
      'commercialFulfillment',jsonb_build_object(
        'contractVersion','commercial_order_fulfillment_requirements_v1',
        'commercialOrderId',v_order.id,
        'commercialOrderLineId',v_line_id,
        'requirementKey',v_key,
        'requirementClass',v_class,
        'quantity',v_quantity,
        'unit',v_unit,
        'specification',coalesce(v_specification,'{}'::jsonb),
        'interpretationBasis',p_interpretation_basis
      ),
      'domain',coalesce(v_domain_metadata,'{}'::jsonb)
    );

    select * into v_existing
    from atlas.work_requirements wr
    where wr.organization_id=v_order.organization_id
      and wr.stable_key=v_stable_key;

    if v_existing.id is not null then
      v_existing_count:=v_existing_count+1;
      v_compatible:=
        v_existing.organization_unit_id is not distinct from v_order.organization_unit_id
        and v_existing.requirement_kind='fulfillment_coverage'
        and v_existing.summary is not distinct from v_summary
        and v_existing.source_object_type=v_source_type
        and v_existing.source_object_id=v_source_id
        and v_existing.established_at=v_commitment_at
        and v_existing.requirement_began_at is not distinct from v_requirement_began_at
        and v_existing.earliest_relevant_at is not distinct from v_earliest_relevant_at
        and v_existing.latest_satisfactory_at is not distinct from v_latest_satisfactory_at
        and v_existing.consequence_of_delay=v_consequence
        and v_existing.jurisdiction_key is not distinct from v_jurisdiction
        and v_existing.metadata->'commercialFulfillment'=v_expected_metadata->'commercialFulfillment'
        and coalesce(v_existing.metadata->'domain','{}'::jsonb)=v_expected_metadata->'domain';

      if not v_compatible then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','existing_requirement_conflicts',
          'requirementKey',v_key,
          'stableKey',v_stable_key,
          'existingWorkRequirementId',v_existing.id
        ));
      end if;
    else
      v_compatible:=true;
      v_would_create:=v_would_create+1;
    end if;

    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'requirementKey',v_key,
      'requirementClass',v_class,
      'stableKey',v_stable_key,
      'summary',v_summary,
      'organizationId',v_order.organization_id,
      'organizationUnitId',v_order.organization_unit_id,
      'requirementKind','fulfillment_coverage',
      'sourceObjectType',v_source_type,
      'sourceObjectId',v_source_id,
      'sourceOrderLineId',v_line_id,
      'establishedAt',v_commitment_at,
      'requirementBeganAt',v_requirement_began_at,
      'earliestRelevantAt',v_earliest_relevant_at,
      'latestSatisfactoryAt',v_latest_satisfactory_at,
      'consequenceOfDelay',v_consequence,
      'jurisdictionKey',v_jurisdiction,
      'metadata',v_expected_metadata,
      'existingWorkRequirementId',v_existing.id,
      'existingState',v_existing.state,
      'compatibleWithExisting',v_compatible,
      'wouldCreate',(v_existing.id is null)
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','commercial_order_fulfillment_requirements_preview_v1',
    'state',case when jsonb_array_length(v_violations)=0 then 'ready' else 'blocked' end,
    'commercialOrderId',v_order.id,
    'organizationId',v_order.organization_id,
    'organizationUnitId',v_order.organization_unit_id,
    'orderCreatedAt',v_order.created_at,
    'commitmentOccurredAt',v_commitment_at,
    'commitmentTimeBasis',v_commitment_time_basis,
    'orderCancelled',v_cancelled,
    'requirementCount',jsonb_array_length(p_requirements),
    'wouldCreateCount',v_would_create,
    'existingCompatibleCount',v_existing_count,
    'requirements',v_normalized,
    'violations',v_violations,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'commercialOrderIsCommitmentAuthority',true,
      'domainAdapterOwnsRequirementMeaning',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCreateWorkItem',true,
      'doesNotChooseCarrier',true,
      'doesNotPurchase',true,
      'doesNotReserve',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true
    )
  );
end;
$function$;


create or replace function atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
  p_commercial_order_id uuid,
  p_requirements jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path=pg_catalog,atlas
as $function$
declare
  v_preview jsonb;
  v_req jsonb;
  v_existing atlas.work_requirements%rowtype;
  v_requirement_id uuid;
  v_results jsonb:='[]'::jsonb;
  v_created_count integer:=0;
  v_existing_count integer:=0;
  v_expected_metadata jsonb;
  v_compatible boolean;
  v_created boolean;
begin
  v_preview:=atlas.commercial_order_fulfillment_requirements_preview_v1(
    p_commercial_order_id,
    p_requirements,
    p_interpretation_basis
  );

  if v_preview->>'state'<>'ready' then
    if exists(
      select 1
      from jsonb_array_elements(v_preview->'violations') x
      where x->>'key'='existing_requirement_conflicts'
    ) then
      raise exception 'Commercial Order fulfillment requirement conflicts with existing structural truth: %',
        (v_preview->'violations')::text
        using errcode='23505';
    end if;

    raise exception 'Commercial Order fulfillment requirements are blocked: %',
      (v_preview->'violations')::text
      using errcode='22023';
  end if;

  for v_req in
    select value
    from jsonb_array_elements(v_preview->'requirements')
  loop
    v_requirement_id:=null;
    v_created:=false;
    v_expected_metadata:=v_req->'metadata';

    if nullif(v_req->>'existingWorkRequirementId','') is not null then
      v_requirement_id:=(v_req->>'existingWorkRequirementId')::uuid;
      v_existing_count:=v_existing_count+1;
    else
      insert into atlas.work_requirements(
        organization_id,
        organization_unit_id,
        stable_key,
        requirement_kind,
        summary,
        source_object_type,
        source_object_id,
        state,
        established_at,
        requirement_began_at,
        earliest_relevant_at,
        latest_satisfactory_at,
        consequence_of_delay,
        jurisdiction_key,
        metadata
      ) values (
        (v_req->>'organizationId')::uuid,
        nullif(v_req->>'organizationUnitId','')::uuid,
        v_req->>'stableKey',
        'fulfillment_coverage',
        v_req->>'summary',
        v_req->>'sourceObjectType',
        (v_req->>'sourceObjectId')::uuid,
        'active',
        (v_req->>'establishedAt')::timestamptz,
        nullif(v_req->>'requirementBeganAt','')::timestamptz,
        nullif(v_req->>'earliestRelevantAt','')::timestamptz,
        (v_req->>'latestSatisfactoryAt')::timestamptz,
        v_req->'consequenceOfDelay',
        v_req->>'jurisdictionKey',
        v_expected_metadata
      )
      on conflict (organization_id,stable_key)
        where stable_key is not null
      do nothing
      returning id into v_requirement_id;

      if v_requirement_id is not null then
        v_created:=true;
        v_created_count:=v_created_count+1;
      else
        select * into v_existing
        from atlas.work_requirements wr
        where wr.organization_id=(v_req->>'organizationId')::uuid
          and wr.stable_key=v_req->>'stableKey';

        if v_existing.id is null then
          raise exception 'Work Requirement stable-key conflict could not be resolved.'
            using errcode='23505';
        end if;

        v_compatible:=
          v_existing.organization_unit_id is not distinct from nullif(v_req->>'organizationUnitId','')::uuid
          and v_existing.requirement_kind='fulfillment_coverage'
          and v_existing.summary is not distinct from v_req->>'summary'
          and v_existing.source_object_type=v_req->>'sourceObjectType'
          and v_existing.source_object_id=(v_req->>'sourceObjectId')::uuid
          and v_existing.established_at=(v_req->>'establishedAt')::timestamptz
          and v_existing.requirement_began_at is not distinct from nullif(v_req->>'requirementBeganAt','')::timestamptz
          and v_existing.earliest_relevant_at is not distinct from nullif(v_req->>'earliestRelevantAt','')::timestamptz
          and v_existing.latest_satisfactory_at is not distinct from (v_req->>'latestSatisfactoryAt')::timestamptz
          and v_existing.consequence_of_delay=v_req->'consequenceOfDelay'
          and v_existing.jurisdiction_key is not distinct from v_req->>'jurisdictionKey'
          and v_existing.metadata->'commercialFulfillment'=v_expected_metadata->'commercialFulfillment'
          and coalesce(v_existing.metadata->'domain','{}'::jsonb)=coalesce(v_expected_metadata->'domain','{}'::jsonb);

        if not v_compatible then
          raise exception 'Work Requirement stable key already exists with different structural truth: %',
            v_req->>'stableKey'
            using errcode='23505';
        end if;

        v_requirement_id:=v_existing.id;
        v_existing_count:=v_existing_count+1;
      end if;
    end if;

    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'requirementKey',v_req->>'requirementKey',
      'stableKey',v_req->>'stableKey',
      'workRequirementId',v_requirement_id,
      'created',v_created,
      'sourceObjectType',v_req->>'sourceObjectType',
      'sourceObjectId',v_req->>'sourceObjectId'
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','ensure_commercial_order_fulfillment_requirements_service_v1',
    'commercialOrderId',p_commercial_order_id,
    'createdCount',v_created_count,
    'existingCount',v_existing_count,
    'requirements',v_results,
    'truthBoundary',jsonb_build_object(
      'establishesOnlyCompanyWorkRequirement',true,
      'doesNotCreateWorkItem',true,
      'doesNotChooseCarrier',true,
      'doesNotCreatePurchase',true,
      'doesNotReserveResource',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCreateFulfillmentEvent',true
    )
  );
end;
$function$;


revoke all on function atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)
  to service_role;

revoke all on function atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_commercial_commitment_to_company_work_v1","purpose":"Read-only preview of explicit domain fulfillment requirements that a committed Commercial Order would establish in Company Work.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_commercial_commitment_to_company_work_v1","purpose":"Idempotently establish explicit domain-interpreted fulfillment coverage as existing Company Work Requirements; creates no execution carrier.","classificationRuleVersion":3}'::jsonb,
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
