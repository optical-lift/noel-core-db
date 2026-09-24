begin;

do $validation$
declare
  v_result jsonb;
  v_resource_requirement_id uuid;
  v_resource_ready boolean;

  v_before_work bigint;
  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_ready bigint;
  v_before_composition bigint;
begin
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_ready from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_composition from atlas.composition_runs;

  -- 1. All required nodes satisfied -> qualified.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"all-satisfied"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-a"}'::jsonb,
    '[
      {"requirementKey":"identity","required":true,"state":"satisfied","evidence":[]},
      {"requirementKey":"quantity","required":true,"state":"satisfied","evidence":[]},
      {"requirementKey":"timing","required":true,"state":"satisfied","evidence":[]}
    ]'::jsonb,
    '{"fixture":"all_required_satisfied"}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,false)=false
     or v_result->'evaluation'->>'state'<>'satisfied' then
    raise exception 'All-satisfied qualification failed: %',v_result;
  end if;

  -- 2. Required unsatisfied -> incompatible.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"incompatible"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-b"}'::jsonb,
    '[
      {"requirementKey":"identity","state":"satisfied"},
      {"requirementKey":"minimum_length","state":"unsatisfied","details":{"minimum":50,"candidate":40}},
      {"requirementKey":"availability","state":"unresolved"}
    ]'::jsonb,
    '{}'::jsonb
  );

  if v_result->>'qualificationState'<>'incompatible'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,true)
     or v_result->'evaluation'->>'state'<>'unsatisfied' then
    raise exception 'Required-unsatisfied precedence failed: %',v_result;
  end if;

  -- 3. No known failure but one required unresolved -> unresolved.
  -- This is the real first flower-source shape: a price-list row can satisfy
  -- source/spec facts while availability remains unknown.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"feast_guild_flower_requirement","sourceRef":"fixture:white-standard-rose"}'::jsonb,
    '{"sourceDomain":"external_supply_offering","sourceRef":"fixture:supplier-white-rose-60cm"}'::jsonb,
    '[
      {
        "requirementKey":"flower_family",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_source_item","value":"rose"}]
      },
      {
        "requirementKey":"color",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_source_item","value":"white"}]
      },
      {
        "requirementKey":"stem_length_minimum",
        "required":true,
        "state":"satisfied",
        "evidence":[{"source":"supplier_source_item","valueCm":60}],
        "details":{"minimumCm":50,"candidateCm":60}
      },
      {
        "requirementKey":"availability_for_required_window",
        "required":true,
        "state":"unresolved",
        "evidence":[{"source":"supplier_price_list","availabilityStated":false}]
      }
    ]'::jsonb,
    '{"stage":"quote_planning"}'::jsonb
  );

  if v_result->>'qualificationState'<>'unresolved'
     or coalesce((v_result->>'mayEnterPlanning')::boolean,true)
     or (v_result->'evaluation'->>'requiredUnresolvedCount')::integer<>1 then
    raise exception 'Unresolved flower-source fixture was not preserved: %',v_result;
  end if;

  -- 4. Optional soft preference does not block a candidate.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"soft-preference"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-c"}'::jsonb,
    '[
      {"requirementKey":"material_spec","required":true,"state":"satisfied"},
      {"requirementKey":"delivery_window","required":true,"state":"satisfied"},
      {"requirementKey":"domestic_preference","required":false,"state":"unsatisfied"}
    ]'::jsonb,
    '{}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or (v_result->'evaluation'->>'optionalUnsatisfiedCount')::integer<>1 then
    raise exception 'Optional unsatisfied preference incorrectly blocked qualification: %',v_result;
  end if;

  -- 5. Optional unresolved preference also does not block.
  v_result:=atlas.fulfillment_candidate_qualification_v1(
    '{"sourceDomain":"fixture_requirement","sourceRef":"optional-unresolved"}'::jsonb,
    '{"sourceDomain":"fixture_candidate","sourceRef":"candidate-d"}'::jsonb,
    '[
      {"requirementKey":"hard_spec","required":true,"state":"satisfied"},
      {"requirementKey":"preferred_origin","required":false,"state":"unresolved"}
    ]'::jsonb,
    '{}'::jsonb
  );

  if v_result->>'qualificationState'<>'qualified'
     or (v_result->'evaluation'->>'optionalUnresolvedCount')::integer<>1 then
    raise exception 'Optional unresolved preference incorrectly blocked qualification: %',v_result;
  end if;

  -- 6. Existing live Atlas Resource Requirement can enter the seam without
  -- rewriting its source truth. The adapter simply reports the existing helper result.
  select trr.id
  into v_resource_requirement_id
  from atlas.task_resource_requirements trr
  where trr.resource_id is not null
  order by trr.created_at,trr.id
  limit 1;

  if v_resource_requirement_id is null then
    raise exception 'Qualification validation requires one existing task resource requirement fixture.';
  end if;

  v_resource_ready:=atlas.resource_requirement_ready_v1(v_resource_requirement_id);

  v_result:=atlas.fulfillment_candidate_qualification_v1(
    jsonb_build_object(
      'sourceDomain','task_resource_requirement',
      'sourceRef',v_resource_requirement_id::text
    ),
    jsonb_build_object(
      'sourceDomain','atlas_resource',
      'sourceRef',(
        select trr.resource_id::text
        from atlas.task_resource_requirements trr
        where trr.id=v_resource_requirement_id
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'requirementKey','resource_ready',
        'required',true,
        'state',case when v_resource_ready then 'satisfied' else 'unsatisfied' end,
        'evidence',jsonb_build_array(jsonb_build_object(
          'source','atlas.resource_requirement_ready_v1',
          'requirementId',v_resource_requirement_id
        ))
      )
    ),
    '{"adapter":"existing_resource_requirement"}'::jsonb
  );

  if v_result->>'qualificationState'
       is distinct from case when v_resource_ready then 'qualified' else 'incompatible' end then
    raise exception 'Existing Resource Requirement adapter disagrees with source authority: ready %, result %',
      v_resource_ready,v_result;
  end if;

  -- 7. Empty set fails closed.
  begin
    perform atlas.requirement_set_evaluate_v2('[]'::jsonb);
    raise exception 'Empty requirement set was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 8. Duplicate keys fail closed.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[
        {"requirementKey":"same","state":"satisfied"},
        {"requirementKey":"same","state":"satisfied"}
      ]'::jsonb
    );
    raise exception 'Duplicate requirement keys were admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 9. Malformed state fails closed.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"bad","state":"probably"}]'::jsonb
    );
    raise exception 'Invalid requirement state was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 10. Evidence must remain structured.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"bad_evidence","state":"satisfied","evidence":"because I said so"}]'::jsonb
    );
    raise exception 'Non-array evidence was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 11. Details must remain structured.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"bad_details","state":"satisfied","details":"50cm"}]'::jsonb
    );
    raise exception 'Non-object details were admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 12. All-optional set fails closed: qualification needs at least one hard requirement.
  begin
    perform atlas.requirement_set_evaluate_v2(
      '[{"requirementKey":"preference_only","required":false,"state":"satisfied"}]'::jsonb
    );
    raise exception 'All-optional requirement set was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 13. Opaque refs still require identity.
  begin
    perform atlas.fulfillment_candidate_qualification_v1(
      '{"sourceDomain":"fixture"}'::jsonb,
      '{"sourceDomain":"fixture_candidate","sourceRef":"x"}'::jsonb,
      '[{"requirementKey":"x","state":"satisfied"}]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Requirement ref without sourceRef was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform atlas.fulfillment_candidate_qualification_v1(
      '{"sourceDomain":"fixture","sourceRef":"x"}'::jsonb,
      '{"sourceRef":"y"}'::jsonb,
      '[{"requirementKey":"x","state":"satisfied"}]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'Candidate ref without sourceDomain was admitted.';
  exception when sqlstate '22023' then
    null;
  end;

  -- 14. Read-only means exactly that.
  if (select count(*) from atlas.work_requirements)<>v_before_work
     or (select count(*) from atlas.commercial_orders)<>v_before_orders
     or (select count(*) from atlas.commercial_payments)<>v_before_payments
     or (select count(*) from atlas.organization_spend_occurrences)<>v_before_spend
     or (select count(*) from atlas.flower_ready_inventory_lots)<>v_before_ready
     or (select count(*) from atlas.composition_runs)<>v_before_composition then
    raise exception 'Qualification evaluation created durable operational/commercial truth.';
  end if;

  -- 15. Browser roles do not receive the internal evaluator.
  if has_function_privilege(
       'authenticated',
       'atlas.requirement_set_evaluate_v2(jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.requirement_set_evaluate_v2(jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Qualification service/browser privilege boundary is incorrect.';
  end if;

  raise notice 'PASS atlas_fulfillment_candidate_qualification_v1: three-state qualification is read-only, fail-closed, resource-compatible, and flower-agnostic';
end;
$validation$;

rollback;
