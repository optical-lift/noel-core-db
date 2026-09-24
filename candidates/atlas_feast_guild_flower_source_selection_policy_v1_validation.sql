begin;

create or replace function atlas._fixture_feast_guild_source_candidate_v1(
  p_basket_key text,
  p_line_key text,
  p_quantity numeric,
  p_unit text,
  p_source_ref text,
  p_tier text,
  p_landed_cost numeric,
  p_source_quantity numeric default null,
  p_excess_quantity numeric default 0,
  p_unresolved_freight boolean default false,
  p_tier_evidence boolean default true
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $fixture$
declare
  v_allocation jsonb;
  v_costs jsonb;
  v_preference jsonb;
begin
  if p_unresolved_freight then
    v_costs:=jsonb_build_array(
      jsonb_build_object(
        'componentKey','merchandise',
        'state','known',
        'required',true,
        'amount',p_landed_cost,
        'currency','USD'
      ),
      jsonb_build_object(
        'componentKey','freight',
        'state','unresolved',
        'required',true,
        'details',jsonb_build_object('fixtureReason','freight_not_known')
      )
    );
  else
    v_costs:=jsonb_build_array(
      jsonb_build_object(
        'componentKey','landed_economic_cost',
        'state','known',
        'required',true,
        'amount',p_landed_cost,
        'currency','USD'
      )
    );
  end if;

  v_allocation:=jsonb_build_object(
    'allocationKey','fixture:'||p_source_ref,
    'candidateRef',jsonb_build_object(
      'sourceDomain','fixture_source',
      'sourceRef',p_source_ref
    ),
    'qualificationState','qualified',
    'sourceQuantity',coalesce(p_source_quantity,p_quantity),
    'sourceUnit',p_unit,
    'outputQuantity',p_quantity,
    'outputUnit',p_unit,
    'costComponents',v_costs
  );

  if coalesce(p_excess_quantity,0)>0 then
    v_allocation:=v_allocation||jsonb_build_object(
      'excess',jsonb_build_object(
        'quantity',p_excess_quantity,
        'unit',p_unit,
        'dispositionState','unresolved_recovery'
      )
    );
  end if;

  v_preference:=jsonb_build_object(
    'tier',p_tier,
    'evidence',case
      when p_tier_evidence then jsonb_build_array(
        jsonb_build_object(
          'sourceRef',p_source_ref,
          'fact','fixture_explicit_source_tier='||p_tier
        )
      )
      else '[]'::jsonb
    end
  );

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','fixture_source',
      'sourceRef',p_source_ref
    ),
    'qualificationNodes',jsonb_build_array(
      jsonb_build_object(
        'requirementKey','spec',
        'required',true,
        'state','satisfied',
        'evidence',jsonb_build_array(
          jsonb_build_object(
            'sourceRef',p_source_ref,
            'fact','fixture_spec_satisfied'
          )
        )
      )
    ),
    'fulfillmentPacket',jsonb_build_object(
      'contractVersion','neutral_fulfillment_composition_v1',
      'requirementRef',jsonb_build_object(
        'sourceDomain','feast_guild_flower_basket_v1',
        'sourceRef',p_basket_key||':'||p_line_key
      ),
      'requirement',jsonb_build_object(
        'quantity',p_quantity,
        'unit',p_unit
      ),
      'planKey','fixture-plan:'||p_source_ref,
      'allocations',jsonb_build_array(v_allocation),
      'metadata',jsonb_build_object(
        'fixture','atlas_feast_guild_flower_source_selection_policy_v1'
      )
    ),
    'sourcePreference',v_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',p_tier,
      'fixture',true
    )
  );
end;
$fixture$;


do $validation$
declare
  v_policy jsonb;
  v_line jsonb;
  v_candidates jsonb;
  v_result jsonb;

  v_basket jsonb;
  v_candidate_sets jsonb;
  v_pricing_policy jsonb;
  v_quote_context jsonb;
  v_whole jsonb;

  v_before_orders bigint;
  v_before_payments bigint;
  v_before_spend bigint;
  v_before_work bigint;
  v_before_inventory bigint;
  v_before_snapshots bigint;
  v_before_acquisitions bigint;

  v_after_orders bigint;
  v_after_payments bigint;
  v_after_spend bigint;
  v_after_work bigint;
  v_after_inventory bigint;
  v_after_snapshots bigint;
  v_after_acquisitions bigint;
begin
  v_policy:=atlas.feast_guild_flower_source_selection_policy_v1();

  if v_policy->>'comparisonBasis'<>'landed_economic_cost'
     or v_policy->>'currency'<>'USD'
     or (v_policy->>'maximumPreferencePremiumRate')::numeric<>0.10
     or v_policy->'preferenceTiers'->0->>'tier'<>'elm_owned_or_grown'
     or v_policy->'preferenceTiers'->1->>'tier'<>'regional_us'
     or v_policy->'preferenceTiers'->2->>'tier'<>'us_grown'
     or v_policy->'preferenceTiers'->3->>'tier'<>'imported' then
    raise exception 'Feast Guild source policy contract changed unexpectedly: %',v_policy;
  end if;

  v_line:='{
    "basketKey":"fixture-policy-tests",
    "lineKey":"test-line",
    "description":"Fixture Flower",
    "quantity":100,
    "unit":"stem",
    "requirements":[
      {"requirementKey":"spec","required":true,"evidenceRequired":true}
    ]
  }'::jsonb;

  -- Elm within +10% wins over cheaper lower-preference sources.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-100','imported',100
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'us-105','us_grown',105
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'elm-108','elm_owned_or_grown',108
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->>'state'<>'selected'
     or v_result->'selectedCandidateRef'->>'sourceRef'<>'elm-108'
     or v_result->>'selectedPreferenceTier'<>'elm_owned_or_grown'
     or (v_result->>'cheapestQualifiedLandedCost')::numeric<>100
     or (v_result->>'preferenceCeiling')::numeric<>110
     or (v_result->>'premiumRate')::numeric<>0.08 then
    raise exception 'Elm-inside-band selection failed: %',v_result;
  end if;

  -- Elm outside band does not win; best in-band preference tier does.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-100','imported',100
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'us-105','us_grown',105
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'regional-109','regional_us',109
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'elm-120','elm_owned_or_grown',120
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'regional-109'
     or v_result->>'selectedPreferenceTier'<>'regional_us'
     or coalesce((v_result->>'morePreferredCandidateOutsideBand')::boolean,false)=false
     or coalesce((v_result->>'operatorApprovalRequiredToUseMorePreferredOutsideBand')::boolean,false)=false
     or v_result->'preferredCandidateOutsideBand'->'candidateRef'->>'sourceRef'<>'elm-120' then
    raise exception 'Out-of-band Elm exception boundary failed: %',v_result;
  end if;

  -- Exactly +10% is allowed.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-100','imported',100
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'regional-110','regional_us',110
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'regional-110'
     or (v_result->>'premiumRate')::numeric<>0.10 then
    raise exception 'Exactly-10-percent boundary failed: %',v_result;
  end if;

  -- Greater than +10% is not automatically selected.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-100','imported',100
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'regional-11001','regional_us',110.01
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'import-100'
     or coalesce((v_result->>'morePreferredCandidateOutsideBand')::boolean,false)=false then
    raise exception 'Greater-than-10-percent boundary failed: %',v_result;
  end if;

  -- Within one preference tier, lower landed cost wins.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'us-106','us_grown',106
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'us-104','us_grown',104
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-100','imported',100
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'us-104' then
    raise exception 'Within-tier landed-cost ordering failed: %',v_result;
  end if;

  -- Unknown freight excludes the preferred candidate rather than treating freight as zero.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'elm-unknown-freight','elm_owned_or_grown',90,
      null,0,true,true
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-known-100','imported',100
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'import-known-100'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'candidateEvaluations') e(value),
            jsonb_array_elements(e.value->'reasons') r(value)
       where e.value->'candidateRef'->>'sourceRef'='elm-unknown-freight'
         and r.value->>'reason'='landed_economic_cost_not_known'
     ) then
    raise exception 'Unknown-freight fail-closed behavior failed: %',v_result;
  end if;

  -- Missing source-tier evidence excludes the candidate.
  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'elm-no-tier-evidence','elm_owned_or_grown',95,
      null,0,false,false
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-known-100','imported',100
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'import-known-100'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'candidateEvaluations') e(value),
            jsonb_array_elements(e.value->'reasons') r(value)
       where e.value->'candidateRef'->>'sourceRef'='elm-no-tier-evidence'
         and r.value->>'reason'='source_preference_evidence_missing'
     ) then
    raise exception 'Tier-evidence fail-closed behavior failed: %',v_result;
  end if;

  -- Unresolved qualification cannot enter ranking even when the source tier and cost look attractive.
  v_candidates:=jsonb_build_array(
    jsonb_set(
      atlas._fixture_feast_guild_source_candidate_v1(
        'fixture-policy-tests','test-line',100,'stem',
        'elm-unresolved-spec','elm_owned_or_grown',90
      ),
      '{qualificationNodes,0,state}'::text[],
      '"unresolved"'::jsonb,
      false
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-known-100','imported',100
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'import-known-100'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'candidateEvaluations') e(value),
            jsonb_array_elements(e.value->'reasons') r(value)
       where e.value->'candidateRef'->>'sourceRef'='elm-unresolved-spec'
         and r.value->>'reason'='candidate_not_qualified'
     ) then
    raise exception 'Unresolved qualification entered source ranking: %',v_result;
  end if;

  -- A warehouse/provider location is not source-tier evidence.
  v_candidates:=jsonb_build_array(
    (
      atlas._fixture_feast_guild_source_candidate_v1(
        'fixture-policy-tests','test-line',100,'stem',
        'warehouse-missouri-90','regional_us',90
      )
      - 'sourcePreference'
    )
    || jsonb_build_object(
      'customerFacingSourceFacts',
      jsonb_build_object(
        'warehouseState','MO',
        'providerLocation','Missouri'
      )
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-known-100','imported',100
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'import-known-100'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'candidateEvaluations') e(value),
            jsonb_array_elements(e.value->'reasons') r(value)
       where e.value->'candidateRef'->>'sourceRef'='warehouse-missouri-90'
         and r.value->>'reason'='source_preference_missing'
     ) then
    raise exception 'Warehouse/provider geography was allowed to establish source tier: %',v_result;
  end if;

  -- A non-empty but structurally meaningless evidence object is still not evidence.
  v_candidates:=jsonb_build_array(
    jsonb_set(
      atlas._fixture_feast_guild_source_candidate_v1(
        'fixture-policy-tests','test-line',100,'stem',
        'elm-empty-evidence-object','elm_owned_or_grown',95
      ),
      '{sourcePreference,evidence,0}'::text[],
      '{}'::jsonb,
      false
    ),
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-policy-tests','test-line',100,'stem',
      'import-known-100','imported',100
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if v_result->'selectedCandidateRef'->>'sourceRef'<>'import-known-100'
     or not exists(
       select 1
       from jsonb_array_elements(v_result->'candidateEvaluations') e(value),
            jsonb_array_elements(e.value->'reasons') r(value)
       where e.value->'candidateRef'->>'sourceRef'='elm-empty-evidence-object'
         and r.value->>'reason'='source_preference_evidence_invalid'
     ) then
    raise exception 'Invalid source-tier evidence entered source ranking: %',v_result;
  end if;

  -- Pack excess remains inside landed economics: $38 source cost covers 90 requested stems.
  v_line:='{
    "basketKey":"fixture-pack-excess",
    "lineKey":"carnations",
    "description":"Standard Carnations",
    "quantity":90,
    "unit":"stem",
    "requirements":[
      {"requirementKey":"spec","required":true,"evidenceRequired":true}
    ]
  }'::jsonb;

  v_candidates:=jsonb_build_array(
    atlas._fixture_feast_guild_source_candidate_v1(
      'fixture-pack-excess','carnations',90,'stem',
      'import-100-pack','imported',38,
      100,10,false,true
    )
  );

  v_result:=atlas.feast_guild_flower_source_plan_select_v1(v_line,v_candidates);

  if (v_result->>'selectedLandedCost')::numeric<>38
     or (v_result->'selectedPlan'->'fulfillmentPacket'->'allocations'->0->>'sourceQuantity')::numeric<>100
     or (v_result->'selectedPlan'->'fulfillmentPacket'->'allocations'->0->'excess'->>'quantity')::numeric<>10 then
    raise exception 'Pack-excess economics were not preserved: %',v_result;
  end if;

  -- Whole-order orchestration may select different source tiers line by line.
  v_basket:='{
    "contractVersion":"feast_guild_flower_basket_v1",
    "basketKey":"fixture-auto-whole-order",
    "requestedForDate":"2026-09-25",
    "lines":[
      {
        "lineKey":"carnations",
        "description":"Standard Carnations",
        "quantity":90,
        "unit":"stem",
        "requirements":[{"requirementKey":"spec","required":true,"evidenceRequired":true}]
      },
      {
        "lineKey":"white-roses",
        "description":"White Roses 60 cm",
        "quantity":50,
        "unit":"stem",
        "requirements":[{"requirementKey":"spec","required":true,"evidenceRequired":true}]
      },
      {
        "lineKey":"eucalyptus",
        "description":"Eucalyptus",
        "quantity":5,
        "unit":"bunch",
        "requirements":[{"requirementKey":"spec","required":true,"evidenceRequired":true}]
      }
    ]
  }'::jsonb;

  v_candidate_sets:=jsonb_build_array(
    jsonb_build_object(
      'lineKey','carnations',
      'candidates',jsonb_build_array(
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','carnations',90,'stem',
          'carn-import-38','imported',38,100,10,false,true
        ),
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','carnations',90,'stem',
          'carn-elm-41','elm_owned_or_grown',41,90,0,false,true
        )
      )
    ),
    jsonb_build_object(
      'lineKey','white-roses',
      'candidates',jsonb_build_array(
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','white-roses',50,'stem',
          'rose-import-55','imported',55
        ),
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','white-roses',50,'stem',
          'rose-us-58','us_grown',58
        ),
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','white-roses',50,'stem',
          'rose-regional-62','regional_us',62
        )
      )
    ),
    jsonb_build_object(
      'lineKey','eucalyptus',
      'candidates',jsonb_build_array(
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','eucalyptus',5,'bunch',
          'euc-import-25','imported',25
        ),
        atlas._fixture_feast_guild_source_candidate_v1(
          'fixture-auto-whole-order','eucalyptus',5,'bunch',
          'euc-regional-275','regional_us',27.50
        )
      )
    )
  );

  v_pricing_policy:='{
    "contractVersion":"commercial_price_policy_input_v1",
    "method":"gross_margin",
    "rate":0.30,
    "currency":"USD",
    "rounding":{"mode":"ceil","increment":0.01}
  }'::jsonb;

  v_quote_context:='{
    "organizationId":"00000000-0000-0000-0000-000000000001",
    "organizationUnitId":null,
    "snapshotKey":"fixture-auto-whole-order-v1",
    "title":"Fixture policy-selected florist order",
    "validFrom":"2026-09-24T15:00:00Z",
    "validUntil":"2026-09-24T18:00:00Z",
    "sourceRef":"fixture:feast-guild-auto-source-selection-v1"
  }'::jsonb;

  select count(*) into v_before_orders from atlas.commercial_orders;
  select count(*) into v_before_payments from atlas.commercial_payments;
  select count(*) into v_before_spend from atlas.organization_spend_occurrences;
  select count(*) into v_before_work from atlas.work_requirements;
  select count(*) into v_before_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_before_snapshots from atlas.commercial_offer_snapshots;
  select count(*) into v_before_acquisitions from atlas.external_acquisition_commitments;

  v_whole:=atlas.feast_guild_flower_quote_prepare_from_candidates_v1(
    v_basket,
    v_candidate_sets,
    v_pricing_policy,
    v_quote_context
  );

  if v_whole->>'state'<>'complete'
     or (v_whole->>'blockedSelectionCount')::integer<>0
     or v_whole->'quote'->>'state'<>'complete'
     or (v_whole->'quote'->>'wholeOrderTotal')::numeric<>181.70 then
    raise exception 'Whole-order automatic source selection/quote failed: %',v_whole;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_whole->'lineSelections') s(value)
    where s.value->>'lineKey'='carnations'
      and s.value->>'selectedPreferenceTier'='elm_owned_or_grown'
      and s.value->'selectedCandidateRef'->>'sourceRef'='carn-elm-41'
  ) then
    raise exception 'Whole-order carnations did not select Elm: %',v_whole;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_whole->'lineSelections') s(value)
    where s.value->>'lineKey'='white-roses'
      and s.value->>'selectedPreferenceTier'='us_grown'
      and s.value->'selectedCandidateRef'->>'sourceRef'='rose-us-58'
      and coalesce((s.value->>'morePreferredCandidateOutsideBand')::boolean,false)=true
  ) then
    raise exception 'Whole-order roses did not select U.S.-grown inside band: %',v_whole;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_whole->'lineSelections') s(value)
    where s.value->>'lineKey'='eucalyptus'
      and s.value->>'selectedPreferenceTier'='regional_us'
      and s.value->'selectedCandidateRef'->>'sourceRef'='euc-regional-275'
  ) then
    raise exception 'Whole-order eucalyptus did not accept exact 10-percent regional premium: %',v_whole;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_whole->'quote'->'lines') l(value)
    where l.value->>'lineKey'='carnations'
      and l.value->'selectionBasis'->>'decisionKind'='feast_guild_source_policy_v1'
      and (l.value->'selectionBasis'->>'premiumRate')::numeric>0
  ) then
    raise exception 'Quote did not preserve automatic source-selection basis: %',v_whole;
  end if;

  select count(*) into v_after_orders from atlas.commercial_orders;
  select count(*) into v_after_payments from atlas.commercial_payments;
  select count(*) into v_after_spend from atlas.organization_spend_occurrences;
  select count(*) into v_after_work from atlas.work_requirements;
  select count(*) into v_after_inventory from atlas.flower_ready_inventory_lots;
  select count(*) into v_after_snapshots from atlas.commercial_offer_snapshots;
  select count(*) into v_after_acquisitions from atlas.external_acquisition_commitments;

  if v_after_orders<>v_before_orders
     or v_after_payments<>v_before_payments
     or v_after_spend<>v_before_spend
     or v_after_work<>v_before_work
     or v_after_inventory<>v_before_inventory
     or v_after_snapshots<>v_before_snapshots
     or v_after_acquisitions<>v_before_acquisitions then
    raise exception 'Source selection / quote orchestration created durable truth.';
  end if;

  raise notice 'PASS atlas_feast_guild_flower_source_selection_policy_v1: fixed +10%% landed-cost preference band; Elm/regional/U.S./imported ordering; unknown cost/tier evidence fail closed; whole order auto-selects mixed sources and quotes $181.70 without writes';
end;
$validation$;

rollback;
