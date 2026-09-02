begin;

-- Harden the governed Mark intake boundary so callers cannot supply
-- free-text category labels through the physical intake API. The original
-- implementation becomes an internal executor; the public v1 contract
-- supplies neutral physical categories itself.

alter function mark.ingest_physical_sequence_v1(jsonb)
  rename to ingest_physical_sequence_internal_v1;

comment on function mark.ingest_physical_sequence_internal_v1(jsonb) is
  'Internal executor for Mark physical intake. Do not call directly from corpus tooling; use mark.ingest_physical_sequence_v1(jsonb), which strips caller authority over category labels.';

create or replace function mark.ingest_physical_sequence_v1(p_payload jsonb)
returns jsonb
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  v_witness jsonb;
  v_zone jsonb;
  v_instance jsonb;
  v_component jsonb;
  v_relation jsonb;
  v_sanitized jsonb;
  v_i integer := 0;
  v_j integer;
  v_k integer;
begin
  perform mark.assert_json_keys_v1(
    p_payload,
    array['witness','zone','instances'],
    'payload'
  );

  v_witness := p_payload->'witness';
  v_zone := p_payload->'zone';

  -- Category-like fields are intentionally absent here. Corpus intake may
  -- state physical custody, geometry, byte identity, channel, topology,
  -- observation state, and order, but not what the witness/zone "is".
  perform mark.assert_json_keys_v1(
    v_witness,
    array[
      'object_key','surface_key','physical_order',
      'capture_key','source_uri','original_filename','mime_type',
      'width_px','height_px','sha256','surface_bbox'
    ],
    'witness'
  );

  perform mark.assert_json_keys_v1(
    v_zone,
    array['region_key','bbox','zone_key','flow_direction','physical_order','confidence'],
    'zone'
  );

  if jsonb_typeof(p_payload->'instances') <> 'array'
     or jsonb_array_length(p_payload->'instances') = 0 then
    raise exception 'MARK_INTAKE_REQUIRED_FIELD: instances must be a non-empty JSON array';
  end if;

  -- Re-run nested allow-list validation at the external boundary so future
  -- expansion of the internal executor cannot silently widen this contract.
  for v_instance in select value from jsonb_array_elements(p_payload->'instances')
  loop
    perform mark.assert_json_keys_v1(
      v_instance,
      array['instance_key','region_key','bbox','observation_status','segmentation_origin','confidence','components','relations'],
      'instance[' || v_i || ']'
    );

    if jsonb_typeof(v_instance->'components') <> 'array'
       or jsonb_array_length(v_instance->'components') = 0 then
      raise exception 'MARK_INTAKE_REQUIRED_FIELD: instance[%].components must be non-empty', v_i;
    end if;

    v_j := 0;
    for v_component in select value from jsonb_array_elements(v_instance->'components')
    loop
      perform mark.assert_json_keys_v1(
        v_component,
        array['component_key','region_key','bbox','channel_key','component_order','observation_status','confidence'],
        'instance[' || v_i || '].component[' || v_j || ']'
      );
      v_j := v_j + 1;
    end loop;

    if v_instance ? 'relations' then
      if jsonb_typeof(v_instance->'relations') <> 'array' then
        raise exception 'MARK_INTAKE_INVALID_ARRAY: instance[%].relations', v_i;
      end if;

      v_k := 0;
      for v_relation in select value from jsonb_array_elements(v_instance->'relations')
      loop
        perform mark.assert_json_keys_v1(
          v_relation,
          array[
            'relation_instance_key','subject_component_key','object_component_key',
            'relation_key','evidence_region_key','distance_px','angle_degrees',
            'observation_status','confidence'
          ],
          'instance[' || v_i || '].relation[' || v_k || ']'
        );
        v_k := v_k + 1;
      end loop;
    end if;

    v_i := v_i + 1;
  end loop;

  -- Neutral physical classifications are owned by the intake mechanism,
  -- not asserted by the observer. More specific custody classification can
  -- be added later through an explicitly governed provenance transition.
  v_sanitized := jsonb_build_object(
    'witness',
      v_witness || jsonb_build_object(
        'object_kind', 'physical_witness',
        'surface_role', 'unspecified',
        'capture_kind', 'raster_capture'
      ),
    'zone',
      v_zone || jsonb_build_object(
        'region_kind', 'sequence_zone',
        'zone_kind', 'ordered_physical_region'
      ),
    'instances',
      p_payload->'instances'
  );

  return mark.ingest_physical_sequence_internal_v1(v_sanitized);
end
$$;

comment on function mark.ingest_physical_sequence_v1(jsonb) is
  'Governed semantic-blind intake for physical witness custody, capture geometry, anonymous mark components, physical junction/topology relations, and sequence order. Caller-authored category labels and arbitrary metadata are rejected.';

revoke all on function mark.ingest_physical_sequence_internal_v1(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function mark.ingest_physical_sequence_v1(jsonb)
  from public, anon, authenticated, service_role;

-- Application roles must remain unable to reach either the external intake
-- contract or its internal executor.
do $$
declare
  role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name, 'mark', 'USAGE')
       or has_function_privilege(role_name, 'mark.ingest_physical_sequence_v1(jsonb)', 'EXECUTE')
       or has_function_privilege(role_name, 'mark.ingest_physical_sequence_internal_v1(jsonb)', 'EXECUTE') then
      raise exception 'MARK_MEMBRANE_VIOLATION: role % can reach physical intake', role_name;
    end if;
  end loop;
end
$$;

commit;
