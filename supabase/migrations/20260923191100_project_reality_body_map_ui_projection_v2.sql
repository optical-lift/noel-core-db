begin;

drop function if exists intelligence.render_body_map_vocabulary_page_v1(jsonb,integer);
drop function if exists intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer);
drop function if exists intelligence.render_body_map_vocabulary_page_v2(jsonb,integer);
drop function if exists intelligence.project_body_map_vocabulary_for_ui_v2(jsonb,integer);

create or replace function intelligence.project_body_map_vocabulary_for_ui_v2(
  p_query jsonb,
  p_limit integer default 100
)
returns table (
  object_type text,
  object_id text,
  headline text,
  lane_key text,
  lane_label text,
  result_kind text,
  source_status text,
  definition_text text,
  matched_region_count integer,
  matched_feature_count integer,
  why_surfaced_short text,
  input_matches jsonb,
  relation_types text[],
  source_basis text[],
  provenance_sources jsonb,
  default_visibility text
)
language sql
security invoker
stable
set search_path=''
as $$
with r as (
  select * from intelligence.search_body_map_vocabulary_v2(p_query,p_limit)
),
x as (
  select r.*, b.value as m
  from r
  cross join lateral jsonb_array_elements(r.match_basis) b(value)
),
a as (
  select
    x.object_type,
    x.object_id,
    jsonb_agg(distinct jsonb_build_object(
      'selectionNo',(x.m->>'selection_no')::int,
      'regionKey',x.m->>'query_region',
      'side',x.m->>'query_side',
      'dimension',x.m->>'query_dimension',
      'value',x.m->>'query_value'
    )) as input_matches,
    array_agg(distinct x.m->>'relation_type' order by x.m->>'relation_type')
      filter (where x.m->>'relation_type' is not null) as relation_types,
    array_agg(distinct x.m->>'source_basis' order by x.m->>'source_basis')
      filter (where x.m->>'source_basis' is not null) as source_basis,
    coalesce(jsonb_agg(distinct s.value) filter (where s.value is not null),'[]'::jsonb) as sources
  from x
  left join lateral jsonb_array_elements(
    case
      when jsonb_typeof(x.m->'mapping_metadata'->'evidence_ref'->'sources')='array'
      then x.m->'mapping_metadata'->'evidence_ref'->'sources'
      else '[]'::jsonb
    end
  ) s(value) on true
  group by x.object_type,x.object_id
),
p as (
  select
    r.object_type,
    r.object_id,
    string_agg(
      case
        when q.feature_values is null then q.region_phrase
        else q.region_phrase || ': ' || array_to_string(q.feature_values,' + ')
      end,
      '; ' order by q.selection_no
    ) as why_phrase
  from r
  cross join lateral (
    select
      (m->>'selection_no')::int as selection_no,
      coalesce(nullif(initcap(m->>'query_side'),'') || ' ','') ||
        coalesce(br.region_name,initcap(replace(m->>'query_region','_',' '))) as region_phrase,
      array_agg(distinct m->>'query_value' order by m->>'query_value')
        filter (where m->>'query_dimension' not in ('body_region','laterality','body_region_side')) as feature_values
    from jsonb_array_elements(r.match_basis) m
    left join practice.body_regions br on br.region_key=m->>'query_region'
    group by (m->>'selection_no')::int,m->>'query_side',br.region_name,m->>'query_region'
  ) q
  group by r.object_type,r.object_id
)
select
  r.object_type,
  r.object_id,
  r.display_label,
  coalesce(r.framework_key,r.source_jurisdiction),
  case
    when r.framework_name is not null then r.framework_name
    when r.source_jurisdiction='neutral_anatomy' then 'Anatomy'
    when r.source_jurisdiction='canon_vocabulary' then 'Canon vocabulary'
    when r.source_jurisdiction='neutral_observation' then 'Observed phenomena'
    when r.source_jurisdiction='noel_function' then 'Noel functions'
    when r.source_jurisdiction='cross_domain_term' then 'Cross-domain terms'
    when r.source_jurisdiction='practitioner_vocabulary' then 'Practitioner vocabulary'
    when r.source_jurisdiction='song' then 'Song'
    when r.source_jurisdiction='research_claim' then 'Research claims'
    when r.source_jurisdiction='celestial_research_hypothesis' then 'Celestial research'
    else initcap(replace(r.source_jurisdiction,'_',' '))
  end,
  case
    when r.source_jurisdiction='neutral_anatomy' then 'Anatomical context'
    when r.source_jurisdiction='canon_vocabulary' and r.object_kind='part' then 'Canon lexeme'
    when r.source_jurisdiction='canon_vocabulary' then 'Canon vocabulary'
    when r.object_kind='drug_intervention' then 'Intervention'
    when r.object_kind='diagnostic_concept' then 'Condition'
    when r.object_kind in ('reported_symptom_term','symptom_classification','symptom_term','symptom_quality','symptom_pattern') then 'Descriptive term'
    when r.object_kind='repertory_rubric' then 'Repertory rubric'
    when r.object_kind='correspondence_map' then 'Correspondence map'
    when r.object_kind='pattern_context' then 'Framework pattern'
    when r.object_kind in ('diagnostic_category','symptom_category') then 'Framework category'
    when r.object_kind in ('framework_term','therapeutic_modality_family') then 'Framework term'
    when r.source_jurisdiction='research_claim' then 'Research claim'
    when r.source_jurisdiction='celestial_research_hypothesis' then 'Research hypothesis'
    else initcap(replace(r.object_kind,'_',' '))
  end,
  r.source_status,
  r.definition_text,
  r.matched_region_count,
  r.matched_feature_count,
  'Matches ' || p.why_phrase || '.',
  a.input_matches,
  coalesce(a.relation_types,array[]::text[]),
  coalesce(a.source_basis,array[]::text[]),
  (
    select coalesce(jsonb_agg(distinct z),'[]'::jsonb)
    from (
      select value z
      from jsonb_array_elements(
        case when jsonb_typeof(r.object_metadata->'sources')='array'
          then r.object_metadata->'sources' else '[]'::jsonb end
      )
      union all
      select value from jsonb_array_elements(a.sources)
    ) u
  ),
  case when r.source_jurisdiction='neutral_anatomy' then 'supporting' else 'primary' end
from r
join a using(object_type,object_id)
join p using(object_type,object_id);
$$;

create or replace function intelligence.render_body_map_vocabulary_page_v2(
  p_query jsonb,
  p_limit integer default 100
)
returns jsonb
language sql
security invoker
stable
set search_path=''
as $$
with selections as (
  select
    q.selection_no,
    q.region_key,
    max(br.region_name) as region_label,
    max(q.side) as side,
    coalesce(
      jsonb_agg(jsonb_build_object('dimensionKey',q.dimension_key,'value',q.dimension_value)
        order by q.dimension_key,q.dimension_value)
        filter (where q.dimension_key not in ('body_region','laterality','body_region_side')),
      '[]'::jsonb
    ) as features
  from intelligence.body_map_query_dimensions_v1(p_query) q
  join practice.body_regions br on br.region_key=q.region_key
  group by q.selection_no,q.region_key
),
results as (
  select * from intelligence.project_body_map_vocabulary_for_ui_v2(p_query,p_limit)
),
stats as (
  select
    count(*)::int as result_count,
    count(*) filter (where default_visibility='primary')::int as primary_result_count,
    count(*) filter (where default_visibility='supporting')::int as supporting_result_count,
    count(distinct lane_key)::int as lane_count
  from results
)
select jsonb_build_object(
  'contractVersion','body_map_vocabulary_page_v2',
  'query',p_query,
  'selections',coalesce((
    select jsonb_agg(jsonb_build_object(
      'selectionNo',selection_no,
      'regionKey',region_key,
      'regionLabel',region_label,
      'side',side,
      'features',features
    ) order by selection_no)
    from selections
  ),'[]'::jsonb),
  'summary',jsonb_build_object(
    'resultCount',s.result_count,
    'primaryResultCount',s.primary_result_count,
    'supportingResultCount',s.supporting_result_count,
    'laneCount',s.lane_count
  ),
  'results',coalesce((
    select jsonb_agg(jsonb_build_object(
      'objectType',object_type,
      'objectId',object_id,
      'headline',headline,
      'laneKey',lane_key,
      'laneLabel',lane_label,
      'resultKind',result_kind,
      'sourceStatus',source_status,
      'definition',definition_text,
      'matchedRegionCount',matched_region_count,
      'matchedFeatureCount',matched_feature_count,
      'whySurfaced',why_surfaced_short,
      'inputMatches',input_matches,
      'relationTypes',relation_types,
      'sourceBasis',source_basis,
      'sources',provenance_sources,
      'defaultVisibility',default_visibility
    ) order by
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
$$;

revoke all on function intelligence.project_body_map_vocabulary_for_ui_v2(jsonb,integer) from public,anon,authenticated;
grant execute on function intelligence.project_body_map_vocabulary_for_ui_v2(jsonb,integer) to service_role;
revoke all on function intelligence.render_body_map_vocabulary_page_v2(jsonb,integer) from public,anon,authenticated;
grant execute on function intelligence.render_body_map_vocabulary_page_v2(jsonb,integer) to service_role;

do $$
declare
  q jsonb := '{"selections":[{"region_key":"head","features":[{"dimension_key":"sensation","value":"pressure"},{"dimension_key":"reported_symptom","value":"dizziness"}]},{"region_key":"knee","side":"right","features":[{"dimension_key":"sensation","value":"ache"},{"dimension_key":"temporal_pattern","value":"intermittent"}]}]}'::jsonb;
  page jsonb;
begin
  page := intelligence.render_body_map_vocabulary_page_v2(q,200);
  if page->>'contractVersion' <> 'body_map_vocabulary_page_v2' then raise exception 'wrong contract version'; end if;
  if (page->'summary'->>'resultCount')::int <> 52 then raise exception 'unexpected result count'; end if;
  if to_regprocedure('intelligence.project_body_map_vocabulary_for_ui_v1(jsonb,integer)') is not null
     or to_regprocedure('intelligence.render_body_map_vocabulary_page_v1(jsonb,integer)') is not null then
    raise exception 'superseded UI v1 still exists';
  end if;
end;
$$;

commit;
