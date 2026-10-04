
create or replace view intelligence.v_reality_witness_objects_v2
with (security_invoker=true)
as
select * from intelligence.v_reality_witness_objects_v1

union all
select
  'universal_vocabulary'::text adapter_key,
  case
    when v.framework_key is not null then 'framework:'||v.framework_key
    else 'jurisdiction:'||v.source_jurisdiction
  end witness_key,
  v.object_type,
  v.object_id,
  v.display_label object_label,
  v.object_kind,
  v.source_status,
  null::text subject_ref_type,
  null::text subject_ref,
  null::timestamptz occurred_at,
  v.definition_text native_definition,
  v.metadata || jsonb_build_object(
    'sourceDomain',v.source_domain,
    'sourceJurisdiction',v.source_jurisdiction,
    'frameworkKey',v.framework_key,
    'frameworkName',v.framework_name
  ) metadata
from intelligence.v_universal_vocabulary_index_v1 v
where not exists (
  select 1
  from intelligence.v_reality_witness_objects_v1 x
  where x.object_type=v.object_type and x.object_id=v.object_id
);

comment on view intelligence.v_reality_witness_objects_v2 is
'Universal Reality Witness Object envelope: native practice/celestial records plus all indexed Noel vocabulary/research objects not already represented by a native adapter.';

create or replace view intelligence.v_reality_witness_object_coordinates_v2
with (security_invoker=true)
as
select * from intelligence.v_reality_witness_object_coordinates_v1

union all
select
  'universal_vocabulary'::text adapter_key,
  case
    when vi.framework_key is not null then 'framework:'||vi.framework_key
    else 'jurisdiction:'||vi.source_jurisdiction
  end witness_key,
  dm.object_type,
  dm.object_id,
  dm.dimension_key,
  dm.dimension_value,
  dm.normalized_value,
  case
    when dm.dimension_key='laterality' then 'laterality'
    when dm.dimension_key in ('body_region','body_region_side') then 'location'
    else 'feature'
  end coordinate_role,
  dm.relation_type source_relation,
  dm.source_basis,
  dm.confidence,
  dm.status coordinate_status,
  dm.scope_region_key,
  dm.scope_side,
  dm.metadata metadata
from intelligence.v_universal_vocabulary_dimension_map_v2 dm
join intelligence.v_universal_vocabulary_index_v1 vi
  on vi.object_type=dm.object_type and vi.object_id=dm.object_id
where not exists (
  select 1
  from intelligence.v_reality_witness_object_coordinates_v1 x
  where x.object_type=dm.object_type
    and x.object_id=dm.object_id
    and x.dimension_key=dm.dimension_key
    and x.normalized_value=dm.normalized_value
    and coalesce(x.source_relation,'')=coalesce(dm.relation_type,'')
);

comment on view intelligence.v_reality_witness_object_coordinates_v2 is
'Complete candidate coordinate membrane for Reality Alignment. It combines native adapter coordinates with existing governed Noel vocabulary mappings while preserving witness identity and source basis.';

revoke all on intelligence.v_reality_witness_objects_v2 from anon,authenticated;
revoke all on intelligence.v_reality_witness_object_coordinates_v2 from anon,authenticated;
grant select on intelligence.v_reality_witness_objects_v2 to service_role;
grant select on intelligence.v_reality_witness_object_coordinates_v2 to service_role;
