
create or replace view intelligence.v_reality_coordinate_shape_v1
with (security_invoker=true)
as
select
  o.occurrence_id,
  o.occurrence_key,
  c.occurrence_coordinate_id,
  c.coordinate_group_key,
  c.dimension_key,
  d.dimension_family,
  c.dimension_value,
  c.normalized_value,
  c.coordinate_role,
  c.coordinate_order,
  count(distinct s.alignment_segment_id)::integer alignment_count,
  count(distinct wm.witness_key)::integer witness_count,
  count(distinct wm.object_type)::integer witness_object_type_count,
  count(distinct s.relation_type)::integer relation_type_count,
  coalesce(
    jsonb_agg(distinct wm.witness_key order by wm.witness_key)
      filter(where wm.witness_key is not null),
    '[]'::jsonb
  ) witness_keys,
  coalesce(
    jsonb_agg(distinct wm.metadata->>'objectKind' order by wm.metadata->>'objectKind')
      filter(where wm.metadata->>'objectKind' is not null),
    '[]'::jsonb
  ) object_kinds,
  coalesce(
    jsonb_agg(distinct s.relation_type order by s.relation_type)
      filter(where s.relation_type is not null),
    '[]'::jsonb
  ) relation_types,
  coalesce(
    jsonb_agg(
      distinct case
        when rc.reality_count=1 and wc.witness_count=1 then 'one_to_one'
        when rc.reality_count=1 and wc.witness_count>1 then 'one_to_many'
        when rc.reality_count>1 and wc.witness_count=1 then 'many_to_one'
        else 'many_to_many'
      end
    ) filter(where s.alignment_segment_id is not null),
    '[]'::jsonb
  ) relationship_shapes
from draft.reality_occurrence_coordinates c
join draft.reality_occurrences o using(occurrence_id)
join draft.reality_query_dimension_registry d using(dimension_key)
left join draft.reality_alignment_members rm
  on rm.occurrence_coordinate_id=c.occurrence_coordinate_id
 and rm.side='reality'
left join draft.reality_alignment_segments s
  on s.alignment_segment_id=rm.alignment_segment_id
left join lateral (
  select count(*)::integer reality_count
  from draft.reality_alignment_members x
  where x.alignment_segment_id=s.alignment_segment_id
    and x.side='reality'
) rc on true
left join lateral (
  select count(*)::integer witness_count
  from draft.reality_alignment_members x
  where x.alignment_segment_id=s.alignment_segment_id
    and x.side='witness'
) wc on true
left join draft.reality_alignment_members wm
  on wm.alignment_segment_id=s.alignment_segment_id
 and wm.side='witness'
group by
  o.occurrence_id,o.occurrence_key,
  c.occurrence_coordinate_id,c.coordinate_group_key,c.dimension_key,d.dimension_family,
  c.dimension_value,c.normalized_value,c.coordinate_role,c.coordinate_order;

comment on view intelligence.v_reality_coordinate_shape_v1 is
'Reality-first structural shape view. Coordinates are grouped by dimension family and expose witness density, relation diversity, object-kind diversity, and one/many alignment shape without organizing the page by discipline.';

create or replace function intelligence.render_reality_shape_viewport_v1(
  p_occurrence_key text
)
returns jsonb
language sql
security invoker
stable
set search_path=''
as $$
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
$$;

comment on function intelligence.render_reality_shape_viewport_v1(text) is
'Shape-first viewport over one Reality Occurrence. It organizes observed reality by coordinate family and structural alignment shape, not by disciplinary source lane.';

revoke all on intelligence.v_reality_coordinate_shape_v1 from anon,authenticated;
grant select on intelligence.v_reality_coordinate_shape_v1 to service_role;
revoke all on function intelligence.render_reality_shape_viewport_v1(text) from public,anon,authenticated;
grant execute on function intelligence.render_reality_shape_viewport_v1(text) to service_role;
