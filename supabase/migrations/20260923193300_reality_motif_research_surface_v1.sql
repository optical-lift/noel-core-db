-- Reality Motif research surfaces v1

create or replace view intelligence.v_reality_motif_instance_context_v1
with (security_invoker=true)
as
 SELECT i.motif_instance_id,
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
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('coordinateId', c.occurrence_coordinate_id, 'groupKey', c.coordinate_group_key, 'dimensionKey', c.dimension_key, 'dimensionFamily', d.dimension_family, 'value', c.dimension_value, 'role', am.member_role) ORDER BY c.coordinate_group_key, c.coordinate_order, c.occurrence_coordinate_id) AS jsonb_agg
           FROM unnest(i.edge_keys) ek(ek)
             JOIN draft.reality_alignment_members am ON am.alignment_member_id = split_part(ek.ek, ':'::text, 2)::bigint AND am.side = 'reality'::text
             JOIN draft.reality_occurrence_coordinates c ON c.occurrence_coordinate_id = am.occurrence_coordinate_id
             JOIN draft.reality_query_dimension_registry d USING (dimension_key)), '[]'::jsonb) AS native_coordinates,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('witnessKey', am.witness_key, 'witnessName', wr.witness_name, 'objectType', am.object_type, 'objectId', am.object_id, 'label', COALESCE(am.metadata ->> 'label'::text, am.metadata ->> 'displayLabel'::text), 'objectKind', am.metadata ->> 'objectKind'::text, 'nativeDefinition', COALESCE(am.metadata ->> 'nativeDefinition'::text, am.metadata ->> 'definition'::text), 'resolutionStatus', am.resolution_status) ORDER BY am.witness_key, am.object_type, am.object_id) AS jsonb_agg
           FROM unnest(i.edge_keys) ek(ek)
             JOIN draft.reality_alignment_members am ON am.alignment_member_id = split_part(ek.ek, ':'::text, 2)::bigint AND am.side = 'witness'::text
             LEFT JOIN draft.reality_witness_registry wr ON wr.witness_key = am.witness_key), '[]'::jsonb) AS native_witness_objects,
    i.metadata,
    i.created_at,
    i.updated_at
   FROM draft.reality_motif_instances i
     JOIN draft.reality_motif_registry m USING (motif_id)
     JOIN draft.reality_occurrences o USING (occurrence_id);;

comment on view intelligence.v_reality_motif_instance_context_v1 is
'Post-discovery motif drill-down. Structural motif identity remains label-blind; this view restores native coordinate values and witness objects for inspection of concrete instances.';

CREATE OR REPLACE FUNCTION intelligence.render_reality_motif_v1(p_motif_key text, p_instance_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$
;

comment on function intelligence.render_reality_motif_v1(text,integer) is
'Motif research view. Abstract structure and recurrence are shown first; native coordinate values and witness labels are restored only inside concrete instance drill-down.';

create or replace view intelligence.v_reality_motif_recovery_queue_v1
with (security_invoker=true)
as
 SELECT motif_id,
    motif_key,
    edge_count,
    node_count,
    recurrence_state,
    instance_count,
    occurrence_count,
    independent_occurrence_count,
    witness_key_count,
    role_signature_count,
    max_coordinate_group_span,
        CASE
            WHEN independent_occurrence_count >= 2 THEN 'inspect_independent_recurrence'::text
            WHEN occurrence_count >= 2 THEN 'hold_as_nonindependent_repeat'::text
            WHEN instance_count >= 2 THEN 'inspect_within_occurrence_density'::text
            ELSE 'hold_singleton'::text
        END AS research_next_move,
    canonical_signature
   FROM intelligence.v_reality_motif_recurrence_v1 r
  ORDER BY independent_occurrence_count DESC, witness_key_count DESC, role_signature_count DESC, instance_count DESC, edge_count DESC, motif_key;;

comment on view intelligence.v_reality_motif_recovery_queue_v1 is
'Research queue for recovered structural motifs. Independent recurrence is separated from duplicate/non-independent recurrence and within-occurrence density.';

revoke all on intelligence.v_reality_motif_instance_context_v1 from anon,authenticated;
revoke all on intelligence.v_reality_motif_recovery_queue_v1 from anon,authenticated;
revoke all on function intelligence.render_reality_motif_v1(text,integer)
  from public,anon,authenticated;

grant select on intelligence.v_reality_motif_instance_context_v1 to service_role;
grant select on intelligence.v_reality_motif_recovery_queue_v1 to service_role;
grant execute on function intelligence.render_reality_motif_v1(text,integer) to service_role;
