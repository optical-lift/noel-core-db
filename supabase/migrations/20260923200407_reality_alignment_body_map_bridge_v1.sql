
insert into draft.reality_witness_registry
(witness_key,witness_name,witness_kind,native_domain,source_object_type,source_object_id,source_role,provenance_status,is_active,metadata)
select
  'framework:'||f.framework_key,
  f.framework_name,
  'framework',
  f.framework_family,
  'reality_framework',
  f.framework_key,
  f.framework_kind,
  f.framework_status,
  true,
  jsonb_build_object('source_table','draft.reality_frameworks')
from draft.reality_frameworks f
on conflict (witness_key) do update set
  witness_name=excluded.witness_name,
  witness_kind=excluded.witness_kind,
  native_domain=excluded.native_domain,
  source_object_type=excluded.source_object_type,
  source_object_id=excluded.source_object_id,
  source_role=excluded.source_role,
  provenance_status=excluded.provenance_status,
  is_active=excluded.is_active,
  metadata=excluded.metadata,
  updated_at=now();

with j as (
  select
    source_jurisdiction,
    min(source_domain) as source_domain
  from intelligence.v_universal_vocabulary_index_v1
  where framework_key is null
  group by source_jurisdiction
)
insert into draft.reality_witness_registry
(witness_key,witness_name,witness_kind,native_domain,source_role,provenance_status,is_active,metadata)
select
  'jurisdiction:'||j.source_jurisdiction,
  case
    when j.source_jurisdiction='neutral_anatomy' then 'Anatomy'
    when j.source_jurisdiction='neutral_observation' then 'Observed phenomena'
    when j.source_jurisdiction='canon_vocabulary' then 'Canon vocabulary'
    when j.source_jurisdiction='noel_function' then 'Noel functions'
    when j.source_jurisdiction='cross_domain_term' then 'Cross-domain terms'
    when j.source_jurisdiction='practitioner_vocabulary' then 'Practitioner vocabulary'
    when j.source_jurisdiction='song' then 'Song'
    when j.source_jurisdiction='research_claim' then 'Research claims'
    when j.source_jurisdiction='celestial_research_hypothesis' then 'Celestial research'
    else initcap(replace(j.source_jurisdiction,'_',' '))
  end,
  'source_jurisdiction',
  j.source_domain,
  j.source_jurisdiction,
  'registered',
  true,
  jsonb_build_object('source_view','intelligence.v_universal_vocabulary_index_v1')
from j
on conflict (witness_key) do update set
  witness_name=excluded.witness_name,
  witness_kind=excluded.witness_kind,
  native_domain=excluded.native_domain,
  source_role=excluded.source_role,
  is_active=excluded.is_active,
  metadata=excluded.metadata,
  updated_at=now();

insert into draft.reality_witness_registry
(witness_key,witness_name,witness_kind,native_domain,source_role,provenance_status,is_active,metadata)
values
('observation:human_report','Human report','direct_observation','human_experience','reported_observation','registered',true,
 '{"purpose":"capture what a person reports before framework interpretation"}'::jsonb)
on conflict (witness_key) do nothing;

create or replace function draft.capture_body_map_occurrence_v1(
  p_occurrence_key text,
  p_query jsonb,
  p_subject_ref_type text default null,
  p_subject_ref text default null,
  p_raw_summary text default null
)
returns bigint
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_occurrence_id bigint;
begin
  perform 1 from intelligence.body_map_query_dimensions_v1(p_query);

  insert into draft.reality_occurrences(
    occurrence_key,
    occurrence_kind,
    subject_ref_type,
    subject_ref,
    captured_by_witness_key,
    raw_summary,
    raw_payload,
    occurrence_status,
    metadata
  )
  values(
    p_occurrence_key,
    'body_map_selection',
    p_subject_ref_type,
    p_subject_ref,
    'observation:human_report',
    p_raw_summary,
    p_query,
    'captured',
    jsonb_build_object('capture_contract','body_map_query_dimensions_v1')
  )
  on conflict (occurrence_key) do update set
    subject_ref_type=excluded.subject_ref_type,
    subject_ref=excluded.subject_ref,
    captured_by_witness_key=excluded.captured_by_witness_key,
    raw_summary=excluded.raw_summary,
    raw_payload=excluded.raw_payload,
    occurrence_status=excluded.occurrence_status,
    metadata=excluded.metadata,
    updated_at=now()
  returning occurrence_id into v_occurrence_id;

  delete from draft.reality_alignment_segments
  where occurrence_id=v_occurrence_id;

  delete from draft.reality_alignment_residue_registry
  where occurrence_id=v_occurrence_id;

  delete from draft.reality_occurrence_coordinates
  where occurrence_id=v_occurrence_id;

  insert into draft.reality_occurrence_coordinates(
    occurrence_id,
    coordinate_group_key,
    dimension_key,
    dimension_value,
    normalized_value,
    coordinate_role,
    coordinate_order,
    metadata
  )
  select
    v_occurrence_id,
    'selection:'||q.selection_no::text,
    q.dimension_key,
    q.dimension_value,
    q.normalized_value,
    case
      when q.dimension_key='body_region' then 'location'
      when q.dimension_key='laterality' then 'laterality'
      when q.dimension_key='body_region_side' then 'derived_location'
      else 'feature'
    end,
    row_number() over(
      partition by q.selection_no
      order by
        case
          when q.dimension_key='body_region' then 0
          when q.dimension_key='laterality' then 1
          when q.dimension_key='body_region_side' then 2
          else 3
        end,
        q.dimension_key,
        q.normalized_value
    )::integer,
    jsonb_build_object(
      'selectionNo',q.selection_no,
      'side',q.side,
      'sourcePath',q.source_path
    )
  from intelligence.body_map_query_dimensions_v1(p_query) q;

  return v_occurrence_id;
end;
$$;

comment on function draft.capture_body_map_occurrence_v1(text,jsonb,text,text,text) is
'Captures a body-map query as one Reality Occurrence with grouped coordinates. Re-capture replaces only that occurrence''s derived alignment material and coordinates.';

create or replace function draft.materialize_body_map_alignments_v1(
  p_occurrence_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_query jsonb;
  v_occurrence_key text;
  v_alignment_count integer;
  v_member_count integer;
  v_residue_count integer;
begin
  select raw_payload,occurrence_key
  into v_query,v_occurrence_key
  from draft.reality_occurrences
  where occurrence_id=p_occurrence_id
    and occurrence_kind='body_map_selection';

  if v_query is null then
    raise exception 'No body-map occurrence found for occurrence_id %',p_occurrence_id;
  end if;

  insert into draft.reality_witness_registry(
    witness_key,witness_name,witness_kind,native_domain,source_object_type,source_object_id,
    source_role,provenance_status,is_active,metadata
  )
  select distinct
    'framework:'||r.framework_key,
    coalesce(r.framework_name,r.framework_key),
    'framework',
    r.source_domain,
    'reality_framework',
    r.framework_key,
    r.source_jurisdiction,
    'registered',
    true,
    jsonb_build_object('materialized_from','intelligence.search_body_map_vocabulary_v2')
  from intelligence.search_body_map_vocabulary_v2(v_query,500) r
  where r.framework_key is not null
  on conflict (witness_key) do nothing;

  insert into draft.reality_witness_registry(
    witness_key,witness_name,witness_kind,native_domain,source_role,
    provenance_status,is_active,metadata
  )
  select distinct
    'jurisdiction:'||r.source_jurisdiction,
    initcap(replace(r.source_jurisdiction,'_',' ')),
    'source_jurisdiction',
    r.source_domain,
    r.source_jurisdiction,
    'registered',
    true,
    jsonb_build_object('materialized_from','intelligence.search_body_map_vocabulary_v2')
  from intelligence.search_body_map_vocabulary_v2(v_query,500) r
  where r.framework_key is null
  on conflict (witness_key) do nothing;

  delete from draft.reality_alignment_segments
  where occurrence_id=p_occurrence_id
    and metadata->>'origin'='body_map_search_v2';

  delete from draft.reality_alignment_residue_registry
  where occurrence_id=p_occurrence_id
    and metadata->>'origin'='body_map_search_v2';

  insert into draft.reality_alignment_segments(
    alignment_key,
    occurrence_id,
    alignment_kind,
    relation_type,
    alignment_status,
    resolution_confidence,
    review_status,
    source_basis,
    metadata
  )
  select
    v_occurrence_key||'::'||r.object_type||'::'||r.object_id,
    p_occurrence_id,
    'witness_correspondence',
    case
      when (
        select count(distinct x->>'relation_type')
        from jsonb_array_elements(r.match_basis) x
      )=1
      then (
        select min(x->>'relation_type')
        from jsonb_array_elements(r.match_basis) x
      )
      else 'multi_relation'
    end,
    'materialized',
    case
      when exists(
        select 1
        from jsonb_array_elements(r.match_basis) x
        where x->>'confidence'='high'
      ) then 'high'
      when exists(
        select 1
        from jsonb_array_elements(r.match_basis) x
        where x->>'confidence'='medium'
      ) then 'medium'
      else null
    end,
    'unreviewed',
    (
      select string_agg(distinct x->>'source_basis',' | ' order by x->>'source_basis')
      from jsonb_array_elements(r.match_basis) x
      where x->>'source_basis' is not null
    ),
    jsonb_build_object(
      'origin','body_map_search_v2',
      'objectType',r.object_type,
      'objectId',r.object_id,
      'displayLabel',r.display_label,
      'objectKind',r.object_kind,
      'sourceDomain',r.source_domain,
      'sourceJurisdiction',r.source_jurisdiction,
      'frameworkKey',r.framework_key,
      'frameworkName',r.framework_name,
      'sourceStatus',r.source_status,
      'matchBasis',r.match_basis
    )
  from intelligence.search_body_map_vocabulary_v2(v_query,500) r
  on conflict (alignment_key) do update set
    alignment_kind=excluded.alignment_kind,
    relation_type=excluded.relation_type,
    alignment_status=excluded.alignment_status,
    resolution_confidence=excluded.resolution_confidence,
    review_status=excluded.review_status,
    source_basis=excluded.source_basis,
    metadata=excluded.metadata,
    updated_at=now();

  insert into draft.reality_alignment_members(
    alignment_segment_id,
    side,
    witness_key,
    occurrence_coordinate_id,
    object_type,
    object_id,
    member_role,
    member_order,
    resolution_status,
    metadata
  )
  select distinct
    s.alignment_segment_id,
    'reality',
    null,
    c.occurrence_coordinate_id,
    null,
    null,
    case
      when c.coordinate_role='location' then 'location'
      when c.coordinate_role='laterality' then 'laterality'
      when c.coordinate_role='derived_location' then 'derived_location'
      else 'feature:'||c.dimension_key
    end,
    c.coordinate_order,
    coalesce(m.basis->>'mapping_status','working'),
    jsonb_build_object(
      'queryDimension',m.basis->>'query_dimension',
      'queryValue',m.basis->>'query_value',
      'matchedDimension',m.basis->>'matched_dimension',
      'matchedValue',m.basis->>'matched_value',
      'relationType',m.basis->>'relation_type',
      'confidence',m.basis->>'confidence',
      'scopeRegionKey',m.basis->>'scope_region_key',
      'scopeSide',m.basis->>'scope_side',
      'regionDepth',m.basis->'region_depth',
      'mappingMetadata',m.basis->'mapping_metadata'
    )
  from intelligence.search_body_map_vocabulary_v2(v_query,500) r
  join draft.reality_alignment_segments s
    on s.alignment_key=v_occurrence_key||'::'||r.object_type||'::'||r.object_id
  cross join lateral jsonb_array_elements(r.match_basis) m(basis)
  join draft.reality_occurrence_coordinates c
    on c.occurrence_id=p_occurrence_id
   and c.coordinate_group_key='selection:'||(m.basis->>'selection_no')
   and c.dimension_key=m.basis->>'query_dimension'
   and c.normalized_value=lower(regexp_replace(trim(m.basis->>'query_value'),'\s+','_','g'))
  on conflict do nothing;

  insert into draft.reality_alignment_members(
    alignment_segment_id,
    side,
    witness_key,
    occurrence_coordinate_id,
    object_type,
    object_id,
    member_role,
    member_order,
    resolution_status,
    metadata
  )
  select
    s.alignment_segment_id,
    'witness',
    case
      when r.framework_key is not null then 'framework:'||r.framework_key
      else 'jurisdiction:'||r.source_jurisdiction
    end,
    null,
    r.object_type,
    r.object_id,
    'source_object',
    1000,
    r.source_status,
    jsonb_build_object(
      'displayLabel',r.display_label,
      'objectKind',r.object_kind,
      'definition',r.definition_text,
      'sourceDomain',r.source_domain,
      'sourceJurisdiction',r.source_jurisdiction,
      'frameworkKey',r.framework_key,
      'frameworkName',r.framework_name
    )
  from intelligence.search_body_map_vocabulary_v2(v_query,500) r
  join draft.reality_alignment_segments s
    on s.alignment_key=v_occurrence_key||'::'||r.object_type||'::'||r.object_id
  on conflict do nothing;

  insert into draft.reality_alignment_residue_registry(
    occurrence_id,
    occurrence_coordinate_id,
    residue_class,
    disposition,
    residue_status,
    metadata
  )
  select
    p_occurrence_id,
    c.occurrence_coordinate_id,
    'unmapped_coordinate',
    'hold',
    'open',
    jsonb_build_object('origin','body_map_search_v2')
  from draft.reality_occurrence_coordinates c
  where c.occurrence_id=p_occurrence_id
    and c.coordinate_role<>'derived_location'
    and not exists(
      select 1
      from draft.reality_alignment_members m
      join draft.reality_alignment_segments s using(alignment_segment_id)
      where s.occurrence_id=p_occurrence_id
        and m.side='reality'
        and m.occurrence_coordinate_id=c.occurrence_coordinate_id
    )
  on conflict do nothing;

  if (
    select count(distinct coordinate_group_key)
    from draft.reality_occurrence_coordinates
    where occurrence_id=p_occurrence_id
      and coordinate_role='location'
  ) > 1
  and not exists(
    select 1
    from draft.reality_alignment_segments s
    join draft.reality_alignment_members m
      on m.alignment_segment_id=s.alignment_segment_id
     and m.side='reality'
    join draft.reality_occurrence_coordinates c
      on c.occurrence_coordinate_id=m.occurrence_coordinate_id
    where s.occurrence_id=p_occurrence_id
    group by s.alignment_segment_id
    having count(distinct c.coordinate_group_key)>1
  ) then
    insert into draft.reality_alignment_residue_registry(
      occurrence_id,
      occurrence_coordinate_id,
      residue_class,
      disposition,
      residue_status,
      notes,
      metadata
    )
    values(
      p_occurrence_id,
      null,
      'no_cross_group_alignment',
      'hold',
      'open',
      'No current alignment segment touches more than one selected coordinate group.',
      jsonb_build_object('origin','body_map_search_v2')
    )
    on conflict do nothing;
  end if;

  select count(*) into v_alignment_count
  from draft.reality_alignment_segments
  where occurrence_id=p_occurrence_id;

  select count(*) into v_member_count
  from draft.reality_alignment_members m
  join draft.reality_alignment_segments s using(alignment_segment_id)
  where s.occurrence_id=p_occurrence_id;

  select count(*) into v_residue_count
  from draft.reality_alignment_residue_registry
  where occurrence_id=p_occurrence_id;

  return jsonb_build_object(
    'occurrenceId',p_occurrence_id,
    'occurrenceKey',v_occurrence_key,
    'alignmentCount',v_alignment_count,
    'memberCount',v_member_count,
    'residueCount',v_residue_count
  );
end;
$$;

comment on function draft.materialize_body_map_alignments_v1(bigint) is
'Materializes governed body-map search matches as Reality Alignment segments. Each segment preserves exact reality-side coordinates, witness identity, native source object, relation type, and mapping basis. Unmatched coordinates and missing cross-group bridges become residue.';

revoke all on function draft.capture_body_map_occurrence_v1(text,jsonb,text,text,text)
  from public,anon,authenticated;
revoke all on function draft.materialize_body_map_alignments_v1(bigint)
  from public,anon,authenticated;
grant execute on function draft.capture_body_map_occurrence_v1(text,jsonb,text,text,text)
  to service_role;
grant execute on function draft.materialize_body_map_alignments_v1(bigint)
  to service_role;

grant usage,select on all sequences in schema draft to service_role;
