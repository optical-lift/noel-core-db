
create or replace view intelligence.v_reality_motif_instance_context_v1
with (security_invoker=true)
as
select
  i.motif_instance_id,
  i.motif_id,
  m.motif_key,
  i.occurrence_id,
  o.occurrence_key,
  i.independence_key,
  i.edge_count,
  i.node_count,
  i.role_signature,
  i.coordinate_groups,
  i.witness_keys,
  i.structure,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'coordinateId',c.occurrence_coordinate_id,
        'groupKey',c.coordinate_group_key,
        'dimensionKey',c.dimension_key,
        'dimensionFamily',d.dimension_family,
        'value',c.dimension_value,
        'role',am.member_role
      )
      order by c.coordinate_group_key,c.coordinate_order,c.occurrence_coordinate_id
    )
    from unnest(i.edge_keys) ek
    join draft.reality_alignment_members am
      on am.alignment_member_id=split_part(ek,':',2)::bigint
     and am.side='reality'
    join draft.reality_occurrence_coordinates c
      on c.occurrence_coordinate_id=am.occurrence_coordinate_id
    join draft.reality_query_dimension_registry d using(dimension_key)
  ),'[]'::jsonb) native_coordinates,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'witnessKey',am.witness_key,
        'witnessName',wr.witness_name,
        'objectType',am.object_type,
        'objectId',am.object_id,
        'label',coalesce(am.metadata->>'label',am.metadata->>'displayLabel'),
        'objectKind',am.metadata->>'objectKind',
        'nativeDefinition',coalesce(am.metadata->>'nativeDefinition',am.metadata->>'definition'),
        'resolutionStatus',am.resolution_status
      )
      order by am.witness_key,am.object_type,am.object_id
    )
    from unnest(i.edge_keys) ek
    join draft.reality_alignment_members am
      on am.alignment_member_id=split_part(ek,':',2)::bigint
     and am.side='witness'
    left join draft.reality_witness_registry wr
      on wr.witness_key=am.witness_key
  ),'[]'::jsonb) native_witness_objects,
  i.metadata,
  i.created_at,
  i.updated_at
from draft.reality_motif_instances i
join draft.reality_motif_registry m using(motif_id)
join draft.reality_occurrences o using(occurrence_id);

comment on view intelligence.v_reality_motif_instance_context_v1 is
'Post-discovery motif drill-down. Structural motif identity remains label-blind; this view restores native coordinate values and witness objects for inspection of concrete instances.';

create or replace function intelligence.render_reality_motif_v1(
  p_motif_key text,
  p_instance_limit integer default 20
)
returns jsonb
language sql
security invoker
stable
set search_path=''
as $$
with m as (
  select *
  from intelligence.v_reality_motif_recurrence_v1
  where motif_key=p_motif_key
),
instances as (
  select c.*
  from intelligence.v_reality_motif_instance_context_v1 c
  join m on m.motif_id=c.motif_id
  order by c.independence_key,c.occurrence_key,c.motif_instance_id
  limit greatest(1,least(coalesce(p_instance_limit,20),100))
),
children as (
  select
    c.child_motif_id,
    child.motif_key child_motif_key,
    child.edge_count child_edge_count,
    c.composition_role,
    c.composition_status,
    c.evidence_count
  from draft.reality_motif_compositions c
  join m on m.motif_id=c.parent_motif_id
  join draft.reality_motif_registry child on child.motif_id=c.child_motif_id
),
parents as (
  select
    c.parent_motif_id,
    parent.motif_key parent_motif_key,
    parent.edge_count parent_edge_count,
    c.composition_role,
    c.composition_status,
    c.evidence_count
  from draft.reality_motif_compositions c
  join m on m.motif_id=c.child_motif_id
  join draft.reality_motif_registry parent on parent.motif_id=c.parent_motif_id
)
select jsonb_build_object(
  'contractVersion','reality_motif_view_v1',
  'motif',jsonb_build_object(
    'motifId',m.motif_id,
    'motifKey',m.motif_key,
    'structureVersion',m.structure_version,
    'edgeCount',m.edge_count,
    'nodeCount',m.node_count,
    'canonicalSignature',m.canonical_signature,
    'status',m.motif_status,
    'recurrenceState',m.recurrence_state,
    'instanceCount',m.instance_count,
    'occurrenceCount',m.occurrence_count,
    'independentOccurrenceCount',m.independent_occurrence_count,
    'witnessKeyCount',m.witness_key_count,
    'roleSignatureCount',m.role_signature_count,
    'maxCoordinateGroupSpan',m.max_coordinate_group_span,
    'abstractStructure',m.metadata->'exemplarStructure'
  ),
  'composedOf',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'motifId',c.child_motif_id,
        'motifKey',c.child_motif_key,
        'edgeCount',c.child_edge_count,
        'role',c.composition_role,
        'status',c.composition_status,
        'evidenceCount',c.evidence_count
      )
      order by c.child_edge_count,c.child_motif_key
    )
    from children c
  ),'[]'::jsonb),
  'appearsInside',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'motifId',p.parent_motif_id,
        'motifKey',p.parent_motif_key,
        'edgeCount',p.parent_edge_count,
        'role',p.composition_role,
        'status',p.composition_status,
        'evidenceCount',p.evidence_count
      )
      order by p.parent_edge_count,p.parent_motif_key
    )
    from parents p
  ),'[]'::jsonb),
  'instances',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'motifInstanceId',i.motif_instance_id,
        'occurrenceId',i.occurrence_id,
        'occurrenceKey',i.occurrence_key,
        'independenceKey',i.independence_key,
        'roleSignature',i.role_signature,
        'coordinateGroups',i.coordinate_groups,
        'witnessKeys',i.witness_keys,
        'nativeCoordinates',i.native_coordinates,
        'nativeWitnessObjects',i.native_witness_objects
      )
      order by i.independence_key,i.occurrence_key,i.motif_instance_id
    )
    from instances i
  ),'[]'::jsonb)
)
from m;
$$;

comment on function intelligence.render_reality_motif_v1(text,integer) is
'Motif research view. Abstract structure and recurrence are shown first; native coordinate values and witness labels are restored only inside concrete instance drill-down.';

create or replace view intelligence.v_reality_motif_recovery_queue_v1
with (security_invoker=true)
as
select
  r.motif_id,
  r.motif_key,
  r.edge_count,
  r.node_count,
  r.recurrence_state,
  r.instance_count,
  r.occurrence_count,
  r.independent_occurrence_count,
  r.witness_key_count,
  r.role_signature_count,
  r.max_coordinate_group_span,
  case
    when r.independent_occurrence_count>=2 then 'inspect_independent_recurrence'
    when r.occurrence_count>=2 then 'hold_as_nonindependent_repeat'
    when r.instance_count>=2 then 'inspect_within_occurrence_density'
    else 'hold_singleton'
  end research_next_move,
  r.canonical_signature
from intelligence.v_reality_motif_recurrence_v1 r
order by
  r.independent_occurrence_count desc,
  r.witness_key_count desc,
  r.role_signature_count desc,
  r.instance_count desc,
  r.edge_count desc,
  r.motif_key;

comment on view intelligence.v_reality_motif_recovery_queue_v1 is
'Research queue for recovered structural motifs. Independent recurrence is separated from duplicate/non-independent recurrence and within-occurrence density.';

revoke all on intelligence.v_reality_motif_instance_context_v1 from anon,authenticated;
revoke all on intelligence.v_reality_motif_recovery_queue_v1 from anon,authenticated;
revoke all on function intelligence.render_reality_motif_v1(text,integer)
  from public,anon,authenticated;

grant select on intelligence.v_reality_motif_instance_context_v1 to service_role;
grant select on intelligence.v_reality_motif_recovery_queue_v1 to service_role;
grant execute on function intelligence.render_reality_motif_v1(text,integer) to service_role;
