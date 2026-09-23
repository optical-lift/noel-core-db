-- Reality shape viewport v1

create or replace view intelligence.v_reality_coordinate_shape_v1
with (security_invoker=true)
as
 SELECT o.occurrence_id,
    o.occurrence_key,
    c.occurrence_coordinate_id,
    c.coordinate_group_key,
    c.dimension_key,
    d.dimension_family,
    c.dimension_value,
    c.normalized_value,
    c.coordinate_role,
    c.coordinate_order,
    count(DISTINCT s.alignment_segment_id)::integer AS alignment_count,
    count(DISTINCT wm.witness_key)::integer AS witness_count,
    count(DISTINCT wm.object_type)::integer AS witness_object_type_count,
    count(DISTINCT s.relation_type)::integer AS relation_type_count,
    COALESCE(jsonb_agg(DISTINCT wm.witness_key ORDER BY wm.witness_key) FILTER (WHERE wm.witness_key IS NOT NULL), '[]'::jsonb) AS witness_keys,
    COALESCE(jsonb_agg(DISTINCT wm.metadata ->> 'objectKind'::text ORDER BY (wm.metadata ->> 'objectKind'::text)) FILTER (WHERE (wm.metadata ->> 'objectKind'::text) IS NOT NULL), '[]'::jsonb) AS object_kinds,
    COALESCE(jsonb_agg(DISTINCT s.relation_type ORDER BY s.relation_type) FILTER (WHERE s.relation_type IS NOT NULL), '[]'::jsonb) AS relation_types,
    COALESCE(jsonb_agg(DISTINCT
        CASE
            WHEN rc.reality_count = 1 AND wc.witness_count = 1 THEN 'one_to_one'::text
            WHEN rc.reality_count = 1 AND wc.witness_count > 1 THEN 'one_to_many'::text
            WHEN rc.reality_count > 1 AND wc.witness_count = 1 THEN 'many_to_one'::text
            ELSE 'many_to_many'::text
        END) FILTER (WHERE s.alignment_segment_id IS NOT NULL), '[]'::jsonb) AS relationship_shapes
   FROM draft.reality_occurrence_coordinates c
     JOIN draft.reality_occurrences o USING (occurrence_id)
     JOIN draft.reality_query_dimension_registry d USING (dimension_key)
     LEFT JOIN draft.reality_alignment_members rm ON rm.occurrence_coordinate_id = c.occurrence_coordinate_id AND rm.side = 'reality'::text
     LEFT JOIN draft.reality_alignment_segments s ON s.alignment_segment_id = rm.alignment_segment_id
     LEFT JOIN LATERAL ( SELECT count(*)::integer AS reality_count
           FROM draft.reality_alignment_members x
          WHERE x.alignment_segment_id = s.alignment_segment_id AND x.side = 'reality'::text) rc ON true
     LEFT JOIN LATERAL ( SELECT count(*)::integer AS witness_count
           FROM draft.reality_alignment_members x
          WHERE x.alignment_segment_id = s.alignment_segment_id AND x.side = 'witness'::text) wc ON true
     LEFT JOIN draft.reality_alignment_members wm ON wm.alignment_segment_id = s.alignment_segment_id AND wm.side = 'witness'::text
  GROUP BY o.occurrence_id, o.occurrence_key, c.occurrence_coordinate_id, c.coordinate_group_key, c.dimension_key, d.dimension_family, c.dimension_value, c.normalized_value, c.coordinate_role, c.coordinate_order;;

comment on view intelligence.v_reality_coordinate_shape_v1 is
'Reality-first structural shape view. Coordinates are grouped by dimension family and expose witness density, relation diversity, object-kind diversity, and one/many alignment shape without organizing the page by discipline.';

CREATE OR REPLACE FUNCTION intelligence.render_reality_shape_viewport_v1(p_occurrence_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with o as (
  select *
  from draft.reality_occurrences
  where occurrence_key=p_occurrence_key
),
coords as (
  select s.*
  from intelligence.v_reality_coordinate_shape_v1 s
  join o on o.occurrence_id=s.occurrence_id
),
families as (
  select
    dimension_family,
    count(*)::integer coordinate_count,
    sum(alignment_count)::integer alignment_touch_count,
    max(witness_count)::integer max_witness_count,
    jsonb_agg(
      jsonb_build_object(
        'coordinateId',occurrence_coordinate_id,
        'groupKey',coordinate_group_key,
        'dimensionKey',dimension_key,
        'value',dimension_value,
        'role',coordinate_role,
        'alignmentCount',alignment_count,
        'witnessCount',witness_count,
        'witnessObjectTypeCount',witness_object_type_count,
        'relationTypeCount',relation_type_count,
        'witnessKeys',witness_keys,
        'objectKinds',object_kinds,
        'relationTypes',relation_types,
        'relationshipShapes',relationship_shapes
      )
      order by coordinate_group_key,coordinate_order,occurrence_coordinate_id
    ) coordinates
  from coords
  group by dimension_family
),
cross_group as (
  select
    s.alignment_segment_id,
    s.alignment_key,
    s.relation_type,
    count(distinct c.coordinate_group_key)::integer group_count,
    array_agg(distinct c.coordinate_group_key order by c.coordinate_group_key) coordinate_groups,
    count(distinct wm.witness_key)::integer witness_count,
    jsonb_agg(distinct wm.witness_key order by wm.witness_key)
      filter(where wm.witness_key is not null) witness_keys
  from draft.reality_alignment_segments s
  join o on o.occurrence_id=s.occurrence_id
  join draft.reality_alignment_members rm
    on rm.alignment_segment_id=s.alignment_segment_id
   and rm.side='reality'
  join draft.reality_occurrence_coordinates c
    on c.occurrence_coordinate_id=rm.occurrence_coordinate_id
  left join draft.reality_alignment_members wm
    on wm.alignment_segment_id=s.alignment_segment_id
   and wm.side='witness'
  group by s.alignment_segment_id,s.alignment_key,s.relation_type
  having count(distinct c.coordinate_group_key)>1
),
residue as (
  select
    count(*) filter(where r.residue_status='open')::integer open_residue_count,
    count(*) filter(where r.residue_status='open' and r.residue_class='unmapped_coordinate')::integer unmapped_coordinate_count,
    count(*) filter(where r.residue_status='open' and r.residue_class='no_cross_group_alignment')::integer missing_cross_group_count
  from draft.reality_alignment_residue_registry r
  join o on o.occurrence_id=r.occurrence_id
)
select jsonb_build_object(
  'contractVersion','reality_shape_viewport_v1',
  'occurrence',jsonb_build_object(
    'occurrenceId',o.occurrence_id,
    'occurrenceKey',o.occurrence_key,
    'occurrenceKind',o.occurrence_kind,
    'occurredAt',o.occurred_at,
    'rawSummary',o.raw_summary
  ),
  'families',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'dimensionFamily',f.dimension_family,
        'coordinateCount',f.coordinate_count,
        'alignmentTouchCount',f.alignment_touch_count,
        'maxWitnessCount',f.max_witness_count,
        'coordinates',f.coordinates
      )
      order by case f.dimension_family
        when 'body' then 10
        when 'phenomenology' then 20
        when 'state' then 30
        when 'time' then 40
        when 'operation' then 50
        when 'transition' then 60
        when 'measurement' then 70
        when 'process' then 80
        when 'relation' then 90
        when 'context' then 100
        when 'vocabulary' then 110
        else 999
      end,
      f.dimension_family
    )
    from families f
  ),'[]'::jsonb),
  'crossGroupAlignments',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'alignmentSegmentId',c.alignment_segment_id,
        'alignmentKey',c.alignment_key,
        'relationType',c.relation_type,
        'groupCount',c.group_count,
        'coordinateGroups',c.coordinate_groups,
        'witnessCount',c.witness_count,
        'witnessKeys',c.witness_keys
      )
      order by c.alignment_segment_id
    )
    from cross_group c
  ),'[]'::jsonb),
  'residue',(
    select jsonb_build_object(
      'openResidueCount',r.open_residue_count,
      'unmappedCoordinateCount',r.unmapped_coordinate_count,
      'missingCrossGroupCount',r.missing_cross_group_count
    )
    from residue r
  )
)
from o;
$function$
;

comment on function intelligence.render_reality_shape_viewport_v1(text) is
'Shape-first viewport over one Reality Occurrence. It organizes observed reality by coordinate family and structural alignment shape, not by disciplinary source lane.';

revoke all on intelligence.v_reality_coordinate_shape_v1 from anon,authenticated;
grant select on intelligence.v_reality_coordinate_shape_v1 to service_role;
revoke all on function intelligence.render_reality_shape_viewport_v1(text) from public,anon,authenticated;
grant execute on function intelligence.render_reality_shape_viewport_v1(text) to service_role;
