-- Source-agnostic Reality Witness aligner v1

CREATE OR REPLACE FUNCTION intelligence.find_reality_witness_matches_v1(p_occurrence_id bigint, p_adapter_keys text[] DEFAULT NULL::text[])
 RETURNS TABLE(adapter_key text, witness_key text, object_type text, object_id text, object_label text, object_kind text, source_status text, subject_ref_type text, subject_ref text, object_occurred_at timestamp with time zone, native_definition text, matched_coordinate_count integer, matched_group_count integer, relation_types text[], source_basis text[], match_basis jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with occ as (
  select *
  from draft.reality_occurrences
  where occurrence_id=p_occurrence_id
),
matches as (
  select
    wo.adapter_key,
    wo.witness_key,
    wo.object_type,
    wo.object_id,
    wo.object_label,
    wo.object_kind,
    wo.source_status,
    wo.subject_ref_type,
    wo.subject_ref,
    wo.occurred_at object_occurred_at,
    wo.native_definition,
    oc.occurrence_coordinate_id,
    oc.coordinate_group_key,
    oc.dimension_key query_dimension_key,
    oc.dimension_value query_dimension_value,
    oc.normalized_value query_normalized_value,
    wc.dimension_key witness_dimension_key,
    wc.dimension_value witness_dimension_value,
    wc.normalized_value witness_normalized_value,
    wc.coordinate_role witness_coordinate_role,
    wc.source_relation,
    wc.source_basis,
    wc.confidence,
    wc.coordinate_status,
    wc.scope_region_key,
    wc.scope_side,
    wc.metadata coordinate_metadata,
    o.occurred_at occurrence_occurred_at
  from occ o
  join draft.reality_occurrence_coordinates oc
    on oc.occurrence_id=o.occurrence_id
  join intelligence.v_reality_witness_object_coordinates_v2 wc
    on (
      (
        oc.dimension_key='body_region'
        and wc.dimension_key='body_region'
        and exists (
          select 1
          from intelligence.v_body_region_hierarchy_v1 h
          where h.ancestor_region_key=oc.normalized_value
            and h.descendant_region_key=wc.normalized_value
        )
      )
      or
      (
        oc.dimension_key<>'body_region'
        and wc.dimension_key=oc.dimension_key
        and wc.normalized_value=oc.normalized_value
      )
    )
  join intelligence.v_reality_witness_objects_v2 wo
    on wo.adapter_key=wc.adapter_key
   and wo.witness_key=wc.witness_key
   and wo.object_type=wc.object_type
   and wo.object_id=wc.object_id
  where
    (p_adapter_keys is null or wo.adapter_key=any(p_adapter_keys))
    and (
      wo.subject_ref is null
      or (
        o.subject_ref is not null
        and wo.subject_ref=o.subject_ref
        and (
          o.subject_ref_type is null
          or wo.subject_ref_type is null
          or wo.subject_ref_type=o.subject_ref_type
        )
      )
    )
    and (
      wc.scope_region_key is null
      or exists (
        select 1
        from draft.reality_occurrence_coordinates rg
        join intelligence.v_body_region_hierarchy_v1 h
          on h.ancestor_region_key=rg.normalized_value
         and h.descendant_region_key=wc.scope_region_key
        where rg.occurrence_id=o.occurrence_id
          and rg.coordinate_group_key=oc.coordinate_group_key
          and rg.dimension_key='body_region'
      )
    )
    and (
      wc.scope_side is null
      or wc.scope_side='unspecified'
      or exists (
        select 1
        from draft.reality_occurrence_coordinates sd
        where sd.occurrence_id=o.occurrence_id
          and sd.coordinate_group_key=oc.coordinate_group_key
          and sd.dimension_key='laterality'
          and (
            sd.normalized_value=wc.scope_side
            or (sd.normalized_value='bilateral' and wc.scope_side in ('left','right','bilateral'))
          )
      )
    )
),
agg as (
  select
    m.adapter_key,
    m.witness_key,
    m.object_type,
    m.object_id,
    m.object_label,
    m.object_kind,
    m.source_status,
    m.subject_ref_type,
    m.subject_ref,
    m.object_occurred_at,
    m.native_definition,
    count(distinct m.occurrence_coordinate_id)::integer matched_coordinate_count,
    count(distinct m.coordinate_group_key)::integer matched_group_count,
    array_agg(distinct m.source_relation order by m.source_relation)
      filter(where m.source_relation is not null) relation_types,
    array_agg(distinct m.source_basis order by m.source_basis)
      filter(where m.source_basis is not null) source_basis,
    jsonb_agg(
      distinct jsonb_strip_nulls(jsonb_build_object(
        'coordinateId',m.occurrence_coordinate_id,
        'groupKey',m.coordinate_group_key,
        'queryDimension',m.query_dimension_key,
        'queryValue',m.query_dimension_value,
        'witnessDimension',m.witness_dimension_key,
        'witnessValue',m.witness_dimension_value,
        'witnessCoordinateRole',m.witness_coordinate_role,
        'relationType',m.source_relation,
        'sourceBasis',m.source_basis,
        'confidence',m.confidence,
        'coordinateStatus',m.coordinate_status,
        'scopeRegionKey',m.scope_region_key,
        'scopeSide',m.scope_side,
        'coordinateMetadata',m.coordinate_metadata,
        'objectOccurredAt',m.object_occurred_at,
        'occurrenceOccurredAt',m.occurrence_occurred_at,
        'timeDeltaSeconds',
          case
            when m.object_occurred_at is not null and m.occurrence_occurred_at is not null
            then extract(epoch from (m.object_occurred_at-m.occurrence_occurred_at))
            else null
          end
      ))
    ) match_basis
  from matches m
  group by
    m.adapter_key,m.witness_key,m.object_type,m.object_id,m.object_label,
    m.object_kind,m.source_status,m.subject_ref_type,m.subject_ref,
    m.object_occurred_at,m.native_definition
)
select
  a.adapter_key,
  a.witness_key,
  a.object_type,
  a.object_id,
  a.object_label,
  a.object_kind,
  a.source_status,
  a.subject_ref_type,
  a.subject_ref,
  a.object_occurred_at,
  a.native_definition,
  a.matched_coordinate_count,
  a.matched_group_count,
  coalesce(a.relation_types,array[]::text[]),
  coalesce(a.source_basis,array[]::text[]),
  a.match_basis
from agg a
order by
  a.matched_group_count desc,
  a.matched_coordinate_count desc,
  a.witness_key,
  a.object_label,
  a.object_id;
$function$
;

comment on function intelligence.find_reality_witness_matches_v1(bigint,text[]) is
'Finds coordinate contact surfaces between one Reality Occurrence and all enabled witness-object adapters. Subject-bound source objects are excluded from subjectless occurrences and require matching governed subject references.';

CREATE OR REPLACE FUNCTION draft.refresh_reality_alignment_residue_v1(p_occurrence_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_unmapped integer;
  v_cross_group integer;
  v_total integer;
begin
  delete from draft.reality_alignment_residue_registry
  where occurrence_id=p_occurrence_id
    and metadata->>'generatedBy'='refresh_reality_alignment_residue_v1';

  insert into draft.reality_alignment_residue_registry(
    occurrence_id,
    occurrence_coordinate_id,
    residue_class,
    disposition,
    residue_status,
    notes,
    metadata
  )
  select
    p_occurrence_id,
    c.occurrence_coordinate_id,
    'unmapped_coordinate',
    'hold',
    'open',
    null,
    jsonb_build_object('generatedBy','refresh_reality_alignment_residue_v1')
  from draft.reality_occurrence_coordinates c
  where c.occurrence_id=p_occurrence_id
    and c.coordinate_role<>'derived_location'
    and not exists (
      select 1
      from draft.reality_alignment_members m
      join draft.reality_alignment_segments s using(alignment_segment_id)
      where s.occurrence_id=p_occurrence_id
        and m.side='reality'
        and m.occurrence_coordinate_id=c.occurrence_coordinate_id
    )
  on conflict do nothing;

  select count(*) into v_cross_group
  from (
    select s.alignment_segment_id
    from draft.reality_alignment_segments s
    join draft.reality_alignment_members m
      on m.alignment_segment_id=s.alignment_segment_id
     and m.side='reality'
    join draft.reality_occurrence_coordinates c
      on c.occurrence_coordinate_id=m.occurrence_coordinate_id
    where s.occurrence_id=p_occurrence_id
    group by s.alignment_segment_id
    having count(distinct c.coordinate_group_key)>1
  ) x;

  if (
    select count(distinct coordinate_group_key)
    from draft.reality_occurrence_coordinates
    where occurrence_id=p_occurrence_id
      and coordinate_role='location'
  ) > 1
  and v_cross_group=0 then
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
      jsonb_build_object('generatedBy','refresh_reality_alignment_residue_v1')
    )
    on conflict do nothing;
  end if;

  select count(*) into v_unmapped
  from draft.reality_alignment_residue_registry
  where occurrence_id=p_occurrence_id
    and residue_class='unmapped_coordinate'
    and residue_status='open';

  select count(*) into v_total
  from draft.reality_alignment_residue_registry
  where occurrence_id=p_occurrence_id
    and residue_status='open';

  return jsonb_build_object(
    'occurrenceId',p_occurrence_id,
    'unmappedCoordinateCount',v_unmapped,
    'crossGroupAlignmentCount',v_cross_group,
    'openResidueCount',v_total
  );
end;
$function$
;

comment on function draft.refresh_reality_alignment_residue_v1(bigint) is
'Recomputes generated residue from the complete current Reality Alignment graph for an occurrence. Manually curated residue is left untouched.';

CREATE OR REPLACE FUNCTION draft.materialize_reality_witness_alignments_v1(p_occurrence_id bigint, p_adapter_keys text[] DEFAULT NULL::text[], p_replace_generated boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_occurrence_key text;
  v_alignment_count integer;
  v_member_count integer;
  v_residue jsonb;
begin
  select occurrence_key
  into v_occurrence_key
  from draft.reality_occurrences
  where occurrence_id=p_occurrence_id;

  if v_occurrence_key is null then
    raise exception 'Unknown occurrence_id %',p_occurrence_id;
  end if;

  if p_replace_generated then
    delete from draft.reality_alignment_segments
    where occurrence_id=p_occurrence_id
      and metadata->>'origin'='witness_adapter_v1'
      and (
        p_adapter_keys is null
        or metadata->>'adapterKey'=any(p_adapter_keys)
      );
  end if;

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
    v_occurrence_key||'::adapter::'||m.adapter_key||'::'||m.object_type||'::'||m.object_id,
    p_occurrence_id,
    'witness_adapter_correspondence',
    case
      when cardinality(m.relation_types)=1 then m.relation_types[1]
      else 'multi_relation'
    end,
    'materialized',
    case
      when m.match_basis @> '[{"confidence":"high"}]'::jsonb then 'high'
      when m.match_basis @> '[{"confidence":"medium"}]'::jsonb then 'medium'
      else null
    end,
    'unreviewed',
    array_to_string(m.source_basis,' | '),
    jsonb_build_object(
      'origin','witness_adapter_v1',
      'adapterKey',m.adapter_key,
      'witnessKey',m.witness_key,
      'objectType',m.object_type,
      'objectId',m.object_id,
      'objectLabel',m.object_label,
      'objectKind',m.object_kind,
      'sourceStatus',m.source_status,
      'subjectRefType',m.subject_ref_type,
      'subjectRef',m.subject_ref,
      'objectOccurredAt',m.object_occurred_at,
      'nativeDefinition',m.native_definition,
      'matchedCoordinateCount',m.matched_coordinate_count,
      'matchedGroupCount',m.matched_group_count,
      'matchBasis',m.match_basis
    )
  from intelligence.find_reality_witness_matches_v1(p_occurrence_id,p_adapter_keys) m
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
    (b.value->>'coordinateId')::bigint,
    null,
    null,
    case
      when b.value->>'queryDimension'='body_region' then 'location'
      when b.value->>'queryDimension'='laterality' then 'laterality'
      when b.value->>'queryDimension'='body_region_side' then 'derived_location'
      else 'feature:'||(b.value->>'queryDimension')
    end,
    c.coordinate_order,
    coalesce(b.value->>'coordinateStatus','working'),
    jsonb_strip_nulls(jsonb_build_object(
      'witnessDimension',b.value->>'witnessDimension',
      'witnessValue',b.value->>'witnessValue',
      'relationType',b.value->>'relationType',
      'sourceBasis',b.value->>'sourceBasis',
      'confidence',b.value->>'confidence',
      'scopeRegionKey',b.value->>'scopeRegionKey',
      'scopeSide',b.value->>'scopeSide',
      'coordinateMetadata',b.value->'coordinateMetadata',
      'timeDeltaSeconds',b.value->'timeDeltaSeconds'
    ))
  from intelligence.find_reality_witness_matches_v1(p_occurrence_id,p_adapter_keys) m
  join draft.reality_alignment_segments s
    on s.alignment_key=v_occurrence_key||'::adapter::'||m.adapter_key||'::'||m.object_type||'::'||m.object_id
  cross join lateral jsonb_array_elements(m.match_basis) b(value)
  join draft.reality_occurrence_coordinates c
    on c.occurrence_coordinate_id=(b.value->>'coordinateId')::bigint
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
  select distinct
    s.alignment_segment_id,
    'reality',
    null,
    lat.occurrence_coordinate_id,
    null,
    null,
    'laterality',
    lat.coordinate_order,
    'derived',
    jsonb_build_object(
      'derivedFromDimension','body_region_side',
      'derivedFromObjectType',m.object_type,
      'derivedFromObjectId',m.object_id
    )
  from intelligence.find_reality_witness_matches_v1(p_occurrence_id,p_adapter_keys) m
  join draft.reality_alignment_segments s
    on s.alignment_key=v_occurrence_key||'::adapter::'||m.adapter_key||'::'||m.object_type||'::'||m.object_id
  cross join lateral jsonb_array_elements(m.match_basis) b(value)
  join draft.reality_occurrence_coordinates compound
    on compound.occurrence_coordinate_id=(b.value->>'coordinateId')::bigint
   and compound.dimension_key='body_region_side'
  join draft.reality_occurrence_coordinates lat
    on lat.occurrence_id=p_occurrence_id
   and lat.coordinate_group_key=compound.coordinate_group_key
   and lat.dimension_key='laterality'
   and lat.normalized_value=split_part(compound.normalized_value,':',2)
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
    m.witness_key,
    null,
    m.object_type,
    m.object_id,
    'source_object',
    1000,
    m.source_status,
    jsonb_build_object(
      'adapterKey',m.adapter_key,
      'label',m.object_label,
      'objectKind',m.object_kind,
      'nativeDefinition',m.native_definition,
      'subjectRefType',m.subject_ref_type,
      'subjectRef',m.subject_ref,
      'occurredAt',m.object_occurred_at
    )
  from intelligence.find_reality_witness_matches_v1(p_occurrence_id,p_adapter_keys) m
  join draft.reality_alignment_segments s
    on s.alignment_key=v_occurrence_key||'::adapter::'||m.adapter_key||'::'||m.object_type||'::'||m.object_id
  on conflict do nothing;

  v_residue := draft.refresh_reality_alignment_residue_v1(p_occurrence_id);

  select count(*) into v_alignment_count
  from draft.reality_alignment_segments
  where occurrence_id=p_occurrence_id
    and metadata->>'origin'='witness_adapter_v1';

  select count(*) into v_member_count
  from draft.reality_alignment_members rm
  join draft.reality_alignment_segments s using(alignment_segment_id)
  where s.occurrence_id=p_occurrence_id
    and s.metadata->>'origin'='witness_adapter_v1';

  return jsonb_build_object(
    'occurrenceId',p_occurrence_id,
    'occurrenceKey',v_occurrence_key,
    'alignmentCount',v_alignment_count,
    'memberCount',v_member_count,
    'residue',v_residue
  );
end;
$function$
;

comment on function draft.materialize_reality_witness_alignments_v1(bigint,text[],boolean) is
'Materializes source-agnostic Reality Alignments from the universal witness adapter membrane. Source identity and native objects remain intact; only explicit coordinate contact is materialized.';

revoke all on function intelligence.find_reality_witness_matches_v1(bigint,text[]) from public,anon,authenticated;
revoke all on function draft.refresh_reality_alignment_residue_v1(bigint) from public,anon,authenticated;
revoke all on function draft.materialize_reality_witness_alignments_v1(bigint,text[],boolean) from public,anon,authenticated;
grant execute on function intelligence.find_reality_witness_matches_v1(bigint,text[]) to service_role;
grant execute on function draft.refresh_reality_alignment_residue_v1(bigint) to service_role;
grant execute on function draft.materialize_reality_witness_alignments_v1(bigint,text[],boolean) to service_role;
