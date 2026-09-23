-- Atlas Person resolution for Reality Witness adapters v1

alter table draft.reality_witness_adapter_registry
  add column if not exists identity_source_system_key text,
  add column if not exists identity_source_record_kind text;

update draft.reality_witness_adapter_registry
set identity_source_system_key='practice',
    identity_source_record_kind='person',
    updated_at=now()
where adapter_key in (
  'practice_body_observation',
  'practice_context_observation',
  'practice_intervention',
  'practice_outcome',
  'practice_discernment_signal'
);

update draft.reality_witness_adapter_registry
set identity_source_system_key='celestial',
    identity_source_record_kind='subject',
    updated_at=now()
where adapter_key in ('celestial_body_state','celestial_chart_event');

comment on column draft.reality_witness_adapter_registry.identity_source_system_key is
'Atlas identity source_system_key used when this adapter emits subject-bound objects. Null means the adapter does not participate in Atlas identity resolution.';

comment on column draft.reality_witness_adapter_registry.identity_source_record_kind is
'Atlas identity source_record_kind used to resolve this adapter''s source-local subject reference.';

create or replace view intelligence.v_reality_source_subject_resolution_v1
with (security_invoker=true)
as
 SELECT DISTINCT wo.adapter_key,
    wo.witness_key,
    wo.object_type,
    wo.object_id,
    wo.subject_ref_type,
    wo.subject_ref,
    isr.organization_id,
    isa.subject_id AS identity_subject_id,
    ipr.person_id AS atlas_person_id,
    isa.assertion_kind,
    isa.confidence,
    isa.basis,
    isr.source_system_key,
    isr.source_record_kind,
    isr.source_record_key
   FROM intelligence.v_reality_witness_objects_v2 wo
     JOIN draft.reality_witness_adapter_registry ar ON ar.adapter_key = wo.adapter_key AND ar.identity_source_system_key IS NOT NULL AND ar.identity_source_record_kind IS NOT NULL
     JOIN atlas.identity_source_records isr ON isr.source_system_key = ar.identity_source_system_key AND isr.source_record_kind = ar.identity_source_record_kind AND isr.source_record_key = wo.subject_ref
     JOIN atlas.identity_source_subject_assertions isa ON isa.source_record_id = isr.id
     JOIN atlas.institutional_person_records ipr ON ipr.organization_id = isr.organization_id AND ipr.identity_subject_id = isa.subject_id AND ipr.status = 'active'::text
  WHERE wo.subject_ref IS NOT NULL;;

comment on view intelligence.v_reality_source_subject_resolution_v1 is
'Resolves source-local Reality Witness subjects through Atlas identity custody to canonical atlas.people Person IDs. It does not infer identity from names, labels, or string similarity.';

revoke all on intelligence.v_reality_source_subject_resolution_v1 from anon,authenticated;
grant select on intelligence.v_reality_source_subject_resolution_v1 to service_role;

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
        and (
          (
            wo.subject_ref=o.subject_ref
            and (
              o.subject_ref_type is null
              or wo.subject_ref_type is null
              or wo.subject_ref_type=o.subject_ref_type
            )
          )
          or (
            o.subject_ref_type='atlas_person'
            and exists (
              select 1
              from intelligence.v_reality_source_subject_resolution_v1 sr
              where sr.adapter_key=wo.adapter_key
                and sr.witness_key=wo.witness_key
                and sr.object_type=wo.object_type
                and sr.object_id=wo.object_id
                and sr.atlas_person_id::text=o.subject_ref
            )
          )
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
'Finds coordinate contact surfaces between one Reality Occurrence and all enabled witness-object adapters. Subject-bound objects require either the same native subject or an Atlas-established canonical Person resolution. Subjectless occurrences cannot pull subject-bound records.';

revoke all on function intelligence.find_reality_witness_matches_v1(bigint,text[]) from public,anon,authenticated;
grant execute on function intelligence.find_reality_witness_matches_v1(bigint,text[]) to service_role;
