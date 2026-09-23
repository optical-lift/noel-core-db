begin;

CREATE OR REPLACE FUNCTION intelligence.project_body_map_vocabulary_for_ui_v1(p_query jsonb, p_limit integer DEFAULT 100)
 RETURNS TABLE(object_type text, object_id text, headline text, lane_key text, lane_label text, result_kind text, claim_posture text, claim_ceiling text, source_status text, definition_text text, match_scope text, matched_region_count integer, matched_feature_count integer, matched_regions text[], why_surfaced_short text, input_matches jsonb, source_explanations jsonb, boundaries jsonb, provenance jsonb, default_visibility text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with r as (
  select *
  from intelligence.search_body_map_vocabulary_v2(p_query,p_limit)
),
expanded as (
  select r.*, mb.value basis
  from r
  cross join lateral jsonb_array_elements(coalesce(r.match_basis,'[]'::jsonb)) mb(value)
),
detail as (
  select
    e.object_type,
    e.object_id,
    jsonb_agg(
      distinct jsonb_build_object(
        'selectionNo',(e.basis->>'selection_no')::integer,
        'regionKey',e.basis->>'query_region',
        'side',e.basis->>'query_side',
        'dimension',e.basis->>'query_dimension',
        'value',e.basis->>'query_value'
      )
    ) input_matches,
    jsonb_agg(
      distinct jsonb_build_object(
        'relationType',e.basis->>'relation_type',
        'rationale',e.basis->'mapping_metadata'->>'rationale',
        'sourceBasis',e.basis->>'source_basis',
        'confidence',e.basis->>'confidence',
        'mappingStatus',e.basis->>'mapping_status',
        'scopeRegionKey',e.basis->>'scope_region_key',
        'scopeSide',e.basis->>'scope_side',
        'evidenceSources',coalesce(e.basis->'mapping_metadata'->'evidence_ref'->'sources','[]'::jsonb)
      )
    ) source_explanations,
    coalesce(jsonb_agg(distinct req.value) filter(where req.value is not null),'[]'::jsonb) mapping_requires,
    coalesce(jsonb_agg(distinct dne.value) filter(where dne.value is not null),'[]'::jsonb) mapping_does_not_establish,
    coalesce(jsonb_agg(distinct src.value) filter(where src.value is not null),'[]'::jsonb) mapping_sources
  from expanded e
  left join lateral jsonb_array_elements(
    case when jsonb_typeof(e.basis->'mapping_metadata'->'requires')='array'
      then e.basis->'mapping_metadata'->'requires' else '[]'::jsonb end
  ) req(value) on true
  left join lateral jsonb_array_elements(
    case when jsonb_typeof(e.basis->'mapping_metadata'->'does_not_establish')='array'
      then e.basis->'mapping_metadata'->'does_not_establish' else '[]'::jsonb end
  ) dne(value) on true
  left join lateral jsonb_array_elements(
    case when jsonb_typeof(e.basis->'mapping_metadata'->'evidence_ref'->'sources')='array'
      then e.basis->'mapping_metadata'->'evidence_ref'->'sources' else '[]'::jsonb end
  ) src(value) on true
  group by e.object_type,e.object_id
),
base as (
  select
    r.*,
    d.input_matches,
    d.source_explanations,
    d.mapping_requires,
    d.mapping_does_not_establish,
    d.mapping_sources,
    coalesce(r.framework_key,r.source_jurisdiction) lane_key,
    case
      when r.framework_name is not null then r.framework_name
      when r.source_jurisdiction='neutral_anatomy' then 'Anatomy'
      when r.source_jurisdiction='neutral_observation' then 'Observed phenomena'
      when r.source_jurisdiction='canon_vocabulary' then 'Canon vocabulary'
      when r.source_jurisdiction='noel_function' then 'Noel functions'
      when r.source_jurisdiction='cross_domain_term' then 'Cross-domain terms'
      when r.source_jurisdiction='practitioner_vocabulary' then 'Practitioner vocabulary'
      when r.source_jurisdiction='song' then 'Song'
      when r.source_jurisdiction='research_claim' then 'Research claims'
      when r.source_jurisdiction='celestial_research_hypothesis' then 'Celestial research'
      else replace(initcap(replace(r.source_jurisdiction,'_',' ')),'  ',' ')
    end lane_label,
    case
      when r.source_jurisdiction='neutral_anatomy' then 'anatomical_context'
      when r.source_jurisdiction='canon_vocabulary' and r.object_kind='part' then 'canon_lexeme'
      when r.source_jurisdiction='canon_vocabulary' then 'canon_structural_adjacency'
      when r.object_kind='drug_intervention' then 'intervention_vocabulary'
      when r.object_kind='diagnostic_concept' then 'condition_vocabulary'
      when r.object_kind in ('reported_symptom_term','symptom_classification','symptom_term','symptom_quality','symptom_pattern')
        then 'descriptive_vocabulary'
      when r.object_kind='repertory_rubric' then 'historical_repertory_vocabulary'
      when r.object_kind='correspondence_map' then 'framework_correspondence'
      when r.object_kind in ('pattern_context','diagnostic_category','symptom_category')
        then 'framework_native_pattern_or_category'
      when r.object_kind in ('framework_term','therapeutic_modality_family')
        then 'framework_vocabulary'
      when r.source_jurisdiction='research_claim' then 'research_claim'
      when r.source_jurisdiction='celestial_research_hypothesis' then 'research_hypothesis'
      else 'source_vocabulary'
    end claim_posture,
    case
      when r.source_jurisdiction='neutral_anatomy' then 'Anatomical context'
      when r.source_jurisdiction='canon_vocabulary' and r.object_kind='part' then 'Canon lexeme'
      when r.source_jurisdiction='canon_vocabulary' then 'Canon adjacency'
      when r.object_kind='drug_intervention' then 'Intervention'
      when r.object_kind='diagnostic_concept' then 'Condition'
      when r.object_kind in ('reported_symptom_term','symptom_classification','symptom_term','symptom_quality','symptom_pattern')
        then 'Descriptive term'
      when r.object_kind='repertory_rubric' then 'Repertory rubric'
      when r.object_kind='correspondence_map' then 'Correspondence map'
      when r.object_kind='pattern_context' then 'Framework pattern'
      when r.object_kind in ('diagnostic_category','symptom_category') then 'Framework category'
      when r.object_kind in ('framework_term','therapeutic_modality_family') then 'Framework term'
      when r.source_jurisdiction='research_claim' then 'Research claim'
      when r.source_jurisdiction='celestial_research_hypothesis' then 'Research hypothesis'
      else replace(initcap(replace(r.object_kind,'_',' ')),'  ',' ')
    end result_kind
  from r
  join detail d using(object_type,object_id)
),
phrases as (
  select
    b.object_type,
    b.object_id,
    string_agg(
      case
        when s.feature_values is null or cardinality(s.feature_values)=0
          then s.region_phrase
        else s.region_phrase || ': ' || array_to_string(s.feature_values,' + ')
      end,
      '; ' order by s.selection_no
    ) why_phrase
  from base b
  cross join lateral (
    select
      (x->>'selectionNo')::integer selection_no,
      coalesce(
        nullif(initcap(x->>'side'),'') || ' ',
        ''
      ) || coalesce(br.region_name,initcap(replace(x->>'regionKey','_',' '))) region_phrase,
      array_agg(distinct x->>'value' order by x->>'value')
        filter(where x->>'dimension' not in ('body_region','laterality','body_region_side')) feature_values
    from jsonb_array_elements(b.input_matches) x
    left join practice.body_regions br on br.region_key=x->>'regionKey'
    group by
      (x->>'selectionNo')::integer,
      x->>'side',
      br.region_name,
      x->>'regionKey'
  ) s
  group by b.object_type,b.object_id
)
select
  b.object_type,
  b.object_id,
  b.display_label headline,
  b.lane_key,
  b.lane_label,
  b.result_kind,
  b.claim_posture,
  case
    when b.claim_posture='anatomical_context'
      then 'May identify anatomical scope only.'
    when b.claim_posture='canon_lexeme'
      then 'May expose source-attested lexical vocabulary; it may not convert a body selection into theological meaning.'
    when b.claim_posture='canon_structural_adjacency'
      then 'May expose structurally adjacent canon vocabulary; it is not equivalent to the reported symptom.'
    when b.claim_posture='intervention_vocabulary'
      then 'May be shown as intervention vocabulary used in a matching source context; it is not a recommendation, dose, safety judgment, or personal treatment plan.'
    when b.claim_posture='condition_vocabulary'
      then 'May be shown as condition vocabulary that contains one or more matching features; it is not a diagnosis.'
    when b.claim_posture='descriptive_vocabulary'
      then 'May be shown as descriptive source vocabulary for what was marked; it does not establish a cause.'
    when b.claim_posture='historical_repertory_vocabulary'
      then 'May be shown as historical framework-native repertory language; it does not establish remedy indication or efficacy.'
    when b.claim_posture='framework_correspondence'
      then 'May be shown as a framework correspondence; it does not establish an anatomical connection, physiological mechanism, or clinical effect.'
    when b.claim_posture='framework_native_pattern_or_category'
      then 'May be shown as this framework’s own pattern or category language; it is not silently converted into a biomedical diagnosis or cross-framework fact.'
    when b.claim_posture='framework_vocabulary'
      then 'May be shown as framework-native vocabulary; proposed mechanisms or effects remain source-specific.'
    when b.claim_posture='research_claim'
      then 'May be shown as a research claim with its own qualification state; it is not promoted beyond that state.'
    when b.claim_posture='research_hypothesis'
      then 'May be shown as a research hypothesis only; it is not an established interpretation.'
    else 'May be shown as source-custodied vocabulary without widening the claim beyond its source.'
  end claim_ceiling,
  b.source_status,
  b.definition_text,
  b.coverage_class match_scope,
  b.matched_region_count,
  b.matched_feature_count,
  b.matched_regions,
  'Matches ' || coalesce(p.why_phrase,'the governed vocabulary graph') || '.' why_surfaced_short,
  b.input_matches,
  b.source_explanations,
  jsonb_strip_nulls(jsonb_build_object(
    'requires',(
      select coalesce(jsonb_agg(distinct x),'[]'::jsonb)
      from (
        select value x
        from jsonb_array_elements(
          case when jsonb_typeof(b.object_metadata->'requires')='array'
            then b.object_metadata->'requires' else '[]'::jsonb end
        )
        union all
        select value
        from jsonb_array_elements(coalesce(b.mapping_requires,'[]'::jsonb))
      ) req
    ),
    'doesNotEstablish',(
      select coalesce(jsonb_agg(distinct x),'[]'::jsonb)
      from (
        select value x
        from jsonb_array_elements(
          case when jsonb_typeof(b.object_metadata->'does_not_establish')='array'
            then b.object_metadata->'does_not_establish' else '[]'::jsonb end
        )
        union all
        select value
        from jsonb_array_elements(coalesce(b.mapping_does_not_establish,'[]'::jsonb))
      ) dne
    ),
    'definitionCeiling',b.object_metadata->>'definition_ceiling'
  )) boundaries,
  jsonb_build_object(
    'sourceJurisdiction',b.source_jurisdiction,
    'sourceDomain',b.source_domain,
    'frameworkKey',b.framework_key,
    'frameworkName',b.framework_name,
    'objectKind',b.object_kind,
    'sourceStatus',b.source_status,
    'sources',(
      select coalesce(jsonb_agg(distinct x),'[]'::jsonb)
      from (
        select value x
        from jsonb_array_elements(
          case when jsonb_typeof(b.object_metadata->'sources')='array'
            then b.object_metadata->'sources' else '[]'::jsonb end
        )
        union all
        select value
        from jsonb_array_elements(coalesce(b.mapping_sources,'[]'::jsonb))
      ) src
    )
  ) provenance,
  case when b.source_jurisdiction='neutral_anatomy' then 'supporting' else 'primary' end default_visibility
from base b
join phrases p using(object_type,object_id)
order by
  case when b.source_jurisdiction='neutral_anatomy' then 1 else 0 end,
  b.matched_region_count desc,
  b.matched_feature_count desc,
  b.lane_label,
  b.display_label;
$function$
;

comment on function intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer) is
'Human-facing projection over governed body-map vocabulary retrieval. It supplies source lane, result kind, claim posture, exact match basis, boundaries, and provenance without scoring or diagnosing results.';

revoke all on function intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer) from public,anon,authenticated;
grant execute on function intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer) to service_role;

CREATE OR REPLACE FUNCTION intelligence.render_body_map_vocabulary_page_v1(p_query jsonb, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with selections as (
  select
    q.selection_no,
    q.region_key,
    max(br.region_name) region_label,
    max(q.side) side,
    coalesce(
      jsonb_agg(
        jsonb_build_object('dimensionKey',q.dimension_key,'value',q.dimension_value)
        order by q.dimension_key,q.dimension_value
      ) filter(where q.dimension_key not in ('body_region','laterality','body_region_side')),
      '[]'::jsonb
    ) features
  from intelligence.body_map_query_dimensions_v1(p_query) q
  join practice.body_regions br on br.region_key=q.region_key
  group by q.selection_no,q.region_key
),
results as (
  select *
  from intelligence.project_body_map_vocabulary_for_ui_v1(p_query,p_limit)
),
stats as (
  select
    count(*)::integer result_count,
    count(*) filter(where default_visibility='primary')::integer primary_result_count,
    count(*) filter(where default_visibility='supporting')::integer supporting_result_count,
    count(distinct lane_key)::integer lane_count,
    count(*) filter(where matched_region_count>=2)::integer cross_region_match_count
  from results
),
lane_summary as (
  select
    lane_key,
    min(lane_label) lane_label,
    count(*)::integer result_count,
    count(*) filter(where default_visibility='primary')::integer primary_result_count
  from results
  group by lane_key
)
select jsonb_build_object(
  'contractVersion','body_map_vocabulary_page_v1',
  'query',p_query,
  'selections',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'selectionNo',selection_no,
        'regionKey',region_key,
        'regionLabel',region_label,
        'side',side,
        'features',features
      )
      order by selection_no
    )
    from selections
  ),'[]'::jsonb),
  'summary',jsonb_build_object(
    'resultCount',s.result_count,
    'primaryResultCount',s.primary_result_count,
    'supportingResultCount',s.supporting_result_count,
    'laneCount',s.lane_count,
    'crossRegionMatchCount',s.cross_region_match_count,
    'crossRegionNote',
      case
        when s.cross_region_match_count=0
          then 'No retrieved vocabulary object currently matches more than one selected body region.'
        else 'Some vocabulary objects match more than one selected region. A cross-region match is retrieval evidence only and does not by itself establish causation or a whole-body relationship.'
      end,
    'governingRule','Non-discriminating retrieval; discriminating provenance.'
  ),
  'lanes',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'laneKey',lane_key,
        'laneLabel',lane_label,
        'resultCount',result_count,
        'primaryResultCount',primary_result_count
      )
      order by case when lane_label='Anatomy' then 1 else 0 end,lane_label
    )
    from lane_summary
  ),'[]'::jsonb),
  'results',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'objectType',object_type,
        'objectId',object_id,
        'headline',headline,
        'laneKey',lane_key,
        'laneLabel',lane_label,
        'resultKind',result_kind,
        'claimPosture',claim_posture,
        'claimCeiling',claim_ceiling,
        'sourceStatus',source_status,
        'definition',definition_text,
        'matchScope',match_scope,
        'matchedRegionCount',matched_region_count,
        'matchedFeatureCount',matched_feature_count,
        'matchedRegions',matched_regions,
        'whySurfaced',why_surfaced_short,
        'inputMatches',input_matches,
        'sourceExplanations',source_explanations,
        'boundaries',boundaries,
        'provenance',provenance,
        'defaultVisibility',default_visibility
      )
      order by
        case when default_visibility='supporting' then 1 else 0 end,
        matched_region_count desc,
        matched_feature_count desc,
        lane_label,
        headline
    )
    from results
  ),'[]'::jsonb)
)
from stats s;
$function$
;

comment on function intelligence.render_body_map_vocabulary_page_v1(jsonb,integer) is
'UI-ready body-map vocabulary page contract: quiet flat results with lane/type/claim boundaries, exact source explanations, provenance, and a non-causal cross-region summary.';

revoke all on function intelligence.render_body_map_vocabulary_page_v1(jsonb,integer) from public,anon,authenticated;
grant execute on function intelligence.render_body_map_vocabulary_page_v1(jsonb,integer) to service_role;


do $validation$
declare
  v_query jsonb := '{
    "selections":[
      {"region_key":"head","features":[
        {"dimension_key":"sensation","value":"pressure"},
        {"dimension_key":"reported_symptom","value":"dizziness"}
      ]},
      {"region_key":"knee","side":"right","features":[
        {"dimension_key":"sensation","value":"ache"},
        {"dimension_key":"temporal_pattern","value":"intermittent"}
      ]}
    ]
  }'::jsonb;
  v_page jsonb;
begin
  v_page := intelligence.render_body_map_vocabulary_page_v1(v_query,200);

  if v_page->>'contractVersion' <> 'body_map_vocabulary_page_v1' then
    raise exception 'Body-map vocabulary page contract version mismatch: %',v_page->>'contractVersion';
  end if;

  if (v_page->'summary'->>'resultCount')::integer <> 52
     or (v_page->'summary'->>'primaryResultCount')::integer <> 37
     or (v_page->'summary'->>'supportingResultCount')::integer <> 15
     or (v_page->'summary'->>'laneCount')::integer <> 7
     or (v_page->'summary'->>'crossRegionMatchCount')::integer <> 0 then
    raise exception 'Body-map vocabulary page proving summary changed unexpectedly: %',v_page->'summary';
  end if;

  if not exists(
    select 1
    from intelligence.project_body_map_vocabulary_for_ui_v1(v_query,200)
    where headline='Aspirin'
      and result_kind='Intervention'
      and claim_posture='intervention_vocabulary'
      and why_surfaced_short='Matches Right Knee: ache.'
      and boundaries->'doesNotEstablish' ? 'dose'
      and boundaries->'doesNotEstablish' ? 'safety'
  ) then
    raise exception 'Aspirin UI projection lost intervention boundary or readable match explanation.';
  end if;

  if not exists(
    select 1
    from intelligence.project_body_map_vocabulary_for_ui_v1(v_query,200)
    where headline='Concussion / mild traumatic brain injury'
      and result_kind='Condition'
      and claim_posture='condition_vocabulary'
      and why_surfaced_short='Matches Head: dizziness.'
      and boundaries->'requires' ? 'injury_context'
  ) then
    raise exception 'Concussion UI projection lost condition boundary or required context.';
  end if;

  if not exists(
    select 1
    from intelligence.project_body_map_vocabulary_for_ui_v1(v_query,200)
    where headline='Intermitting pain — right knee'
      and result_kind='Repertory rubric'
      and claim_posture='historical_repertory_vocabulary'
      and why_surfaced_short='Matches Right Knee: ache + intermittent.'
  ) then
    raise exception 'Homeopathy UI projection lost exact right-knee intermittent match explanation.';
  end if;

  if not exists(
    select 1
    from intelligence.project_body_map_vocabulary_for_ui_v1(v_query,200)
    where headline='rosh'
      and result_kind='Canon lexeme'
      and claim_posture='canon_lexeme'
      and why_surfaced_short='Matches Head.'
      and boundaries ? 'definitionCeiling'
  ) then
    raise exception 'Canon lexeme UI projection lost lexical claim ceiling.';
  end if;

  if not exists(
    select 1
    from intelligence.project_body_map_vocabulary_for_ui_v1(v_query,200)
    where headline='Head / brain reflex area'
      and result_kind='Correspondence map'
      and claim_posture='framework_correspondence'
      and boundaries->'doesNotEstablish' ? 'anatomical_connection'
  ) then
    raise exception 'Reflexology UI projection lost correspondence-map boundary.';
  end if;

  if has_function_privilege(
       'anon',
       'intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'intelligence.render_body_map_vocabulary_page_v1(jsonb,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'intelligence.render_body_map_vocabulary_page_v1(jsonb,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'intelligence.render_body_map_vocabulary_page_v1(jsonb,integer)',
       'EXECUTE'
     ) then
    raise exception 'Body-map UI projection execution boundary is not service-only.';
  end if;
end;
$validation$;


commit;
