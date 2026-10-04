
create or replace view intelligence.v_reality_coordinate_convergence_v1
with (security_invoker=true)
as
select
  o.occurrence_id,
  o.occurrence_key,
  c.occurrence_coordinate_id,
  c.coordinate_group_key,
  c.dimension_key,
  c.dimension_value,
  c.normalized_value,
  c.coordinate_role,
  c.coordinate_order,
  count(distinct s.alignment_segment_id)::integer as alignment_count,
  count(distinct wm.witness_key)::integer as witness_count,
  coalesce(
    jsonb_agg(
      distinct jsonb_build_object(
        'alignmentSegmentId',s.alignment_segment_id,
        'alignmentKey',s.alignment_key,
        'alignmentKind',s.alignment_kind,
        'relationType',s.relation_type,
        'alignmentStatus',s.alignment_status,
        'resolutionConfidence',s.resolution_confidence,
        'reviewStatus',s.review_status,
        'sourceBasis',s.source_basis,
        'witnessKey',wm.witness_key,
        'witnessName',wr.witness_name,
        'witnessKind',wr.witness_kind,
        'objectType',wm.object_type,
        'objectId',wm.object_id,
        'objectLabel',wm.metadata->>'displayLabel',
        'objectKind',wm.metadata->>'objectKind',
        'definition',wm.metadata->>'definition'
      )
    ) filter(where s.alignment_segment_id is not null and wm.alignment_member_id is not null),
    '[]'::jsonb
  ) as witness_touches
from draft.reality_occurrence_coordinates c
join draft.reality_occurrences o using(occurrence_id)
left join draft.reality_alignment_members rm
  on rm.occurrence_coordinate_id=c.occurrence_coordinate_id
 and rm.side='reality'
left join draft.reality_alignment_segments s
  on s.alignment_segment_id=rm.alignment_segment_id
left join draft.reality_alignment_members wm
  on wm.alignment_segment_id=s.alignment_segment_id
 and wm.side='witness'
left join draft.reality_witness_registry wr
  on wr.witness_key=wm.witness_key
group by
  o.occurrence_id,o.occurrence_key,
  c.occurrence_coordinate_id,c.coordinate_group_key,c.dimension_key,
  c.dimension_value,c.normalized_value,c.coordinate_role,c.coordinate_order;

comment on view intelligence.v_reality_coordinate_convergence_v1 is
'Reality-first convergence view. Each observed coordinate is primary; source traditions appear only as witness touches on that coordinate.';

create or replace function intelligence.render_reality_occurrence_viewport_v1(
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
groups as (
  select distinct c.coordinate_group_key
  from draft.reality_occurrence_coordinates c
  join o on o.occurrence_id=c.occurrence_id
),
group_payload as (
  select
    g.coordinate_group_key,
    (
      select c.dimension_value
      from draft.reality_occurrence_coordinates c
      join o on o.occurrence_id=c.occurrence_id
      where c.coordinate_group_key=g.coordinate_group_key
        and c.dimension_key='body_region'
      order by c.coordinate_order
      limit 1
    ) as location,
    (
      select c.dimension_value
      from draft.reality_occurrence_coordinates c
      join o on o.occurrence_id=c.occurrence_id
      where c.coordinate_group_key=g.coordinate_group_key
        and c.dimension_key='laterality'
      order by c.coordinate_order
      limit 1
    ) as side,
    (
      select jsonb_agg(
        jsonb_build_object(
          'coordinateId',c.occurrence_coordinate_id,
          'dimensionKey',c.dimension_key,
          'value',c.dimension_value,
          'role',c.coordinate_role,
          'alignmentCount',cv.alignment_count,
          'witnessCount',cv.witness_count
        )
        order by c.coordinate_order,c.occurrence_coordinate_id
      )
      from draft.reality_occurrence_coordinates c
      left join intelligence.v_reality_coordinate_convergence_v1 cv
        on cv.occurrence_coordinate_id=c.occurrence_coordinate_id
      join o on o.occurrence_id=c.occurrence_id
      where c.coordinate_group_key=g.coordinate_group_key
    ) as coordinates,
    (
      select coalesce(jsonb_agg(t.payload order by t.alignment_segment_id),'[]'::jsonb)
      from (
        select
          s.alignment_segment_id,
          jsonb_build_object(
            'alignmentSegmentId',s.alignment_segment_id,
            'alignmentKey',s.alignment_key,
            'alignmentKind',s.alignment_kind,
            'relationType',s.relation_type,
            'relationshipShape',
              case
                when rc.reality_count=1 and wc.witness_count=1 then 'one_to_one'
                when rc.reality_count=1 and wc.witness_count>1 then 'one_to_many'
                when rc.reality_count>1 and wc.witness_count=1 then 'many_to_one'
                else 'many_to_many'
              end,
            'alignmentStatus',s.alignment_status,
            'resolutionConfidence',s.resolution_confidence,
            'reviewStatus',s.review_status,
            'sourceBasis',s.source_basis,
            'matchedCoordinates',mc.coordinates,
            'witnessObjects',wo.objects
          ) as payload
        from draft.reality_alignment_segments s
        join o on o.occurrence_id=s.occurrence_id
        join lateral (
          select count(*)::integer reality_count
          from draft.reality_alignment_members m
          where m.alignment_segment_id=s.alignment_segment_id
            and m.side='reality'
        ) rc on true
        join lateral (
          select count(*)::integer witness_count
          from draft.reality_alignment_members m
          where m.alignment_segment_id=s.alignment_segment_id
            and m.side='witness'
        ) wc on true
        join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'coordinateId',c.occurrence_coordinate_id,
              'dimensionKey',c.dimension_key,
              'value',c.dimension_value,
              'role',m.member_role
            )
            order by c.coordinate_order,c.occurrence_coordinate_id
          ) as coordinates
          from draft.reality_alignment_members m
          join draft.reality_occurrence_coordinates c
            on c.occurrence_coordinate_id=m.occurrence_coordinate_id
          where m.alignment_segment_id=s.alignment_segment_id
            and m.side='reality'
            and c.coordinate_group_key=g.coordinate_group_key
        ) mc on mc.coordinates is not null
        join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'witnessKey',m.witness_key,
              'witnessName',w.witness_name,
              'witnessKind',w.witness_kind,
              'objectType',m.object_type,
              'objectId',m.object_id,
              'label',m.metadata->>'displayLabel',
              'objectKind',m.metadata->>'objectKind',
              'definition',m.metadata->>'definition',
              'resolutionStatus',m.resolution_status
            )
            order by m.member_order,m.alignment_member_id
          ) as objects
          from draft.reality_alignment_members m
          join draft.reality_witness_registry w on w.witness_key=m.witness_key
          where m.alignment_segment_id=s.alignment_segment_id
            and m.side='witness'
        ) wo on true
      ) t
    ) as touches
  from groups g
),
cross_group as (
  select
    s.alignment_segment_id,
    jsonb_build_object(
      'alignmentSegmentId',s.alignment_segment_id,
      'alignmentKey',s.alignment_key,
      'alignmentKind',s.alignment_kind,
      'relationType',s.relation_type,
      'sourceBasis',s.source_basis,
      'coordinateGroups',array_agg(distinct c.coordinate_group_key order by c.coordinate_group_key)
    ) as payload
  from draft.reality_alignment_segments s
  join o on o.occurrence_id=s.occurrence_id
  join draft.reality_alignment_members m
    on m.alignment_segment_id=s.alignment_segment_id
   and m.side='reality'
  join draft.reality_occurrence_coordinates c
    on c.occurrence_coordinate_id=m.occurrence_coordinate_id
  group by s.alignment_segment_id,s.alignment_key,s.alignment_kind,s.relation_type,s.source_basis
  having count(distinct c.coordinate_group_key)>1
)
select jsonb_build_object(
  'contractVersion','reality_occurrence_viewport_v1',
  'occurrence',jsonb_build_object(
    'occurrenceId',o.occurrence_id,
    'occurrenceKey',o.occurrence_key,
    'occurrenceKind',o.occurrence_kind,
    'subjectRefType',o.subject_ref_type,
    'subjectRef',o.subject_ref,
    'occurredAt',o.occurred_at,
    'rawSummary',o.raw_summary,
    'status',o.occurrence_status
  ),
  'coordinateGroups',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'groupKey',g.coordinate_group_key,
        'location',g.location,
        'side',g.side,
        'coordinates',g.coordinates,
        'touches',g.touches
      )
      order by g.coordinate_group_key
    )
    from group_payload g
  ),'[]'::jsonb),
  'crossGroupAlignments',coalesce((
    select jsonb_agg(c.payload order by c.alignment_segment_id)
    from cross_group c
  ),'[]'::jsonb),
  'residue',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'residueId',r.residue_id,
        'coordinateId',r.occurrence_coordinate_id,
        'witnessKey',r.witness_key,
        'residueClass',r.residue_class,
        'disposition',r.disposition,
        'status',r.residue_status,
        'notes',r.notes
      )
      order by r.residue_id
    )
    from draft.reality_alignment_residue_registry r
    where r.occurrence_id=o.occurrence_id
  ),'[]'::jsonb)
)
from o;
$$;

comment on function intelligence.render_reality_occurrence_viewport_v1(text) is
'Unified reality-first viewport. Coordinate groups organize the page; witness-native objects are shown as touches with explicit relationship shape and source basis. No disciplinary lane owns the viewport.';

revoke all on intelligence.v_reality_coordinate_convergence_v1 from anon,authenticated;
grant select on intelligence.v_reality_coordinate_convergence_v1 to service_role;

revoke all on function intelligence.render_reality_occurrence_viewport_v1(text)
  from public,anon,authenticated;
grant execute on function intelligence.render_reality_occurrence_viewport_v1(text)
  to service_role;
