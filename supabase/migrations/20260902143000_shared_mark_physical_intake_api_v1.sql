begin;

-- Mark Engine physical intake v1.
-- This layer deliberately accepts physical custody, geometry, channel, topology,
-- and anonymous sequence order only. It does not accept linguistic labels,
-- readings, culture assignments, semantic glosses, free-text category labels,
-- or arbitrary metadata.

create index if not exists source_objects_parent_source_object_idx
  on mark.source_objects(parent_source_object_id);

create index if not exists captures_derivative_of_capture_idx
  on mark.captures(derivative_of_capture_id);

create index if not exists relation_registry_inverse_relation_idx
  on mark.relation_registry(inverse_relation_key);

create index if not exists regions_created_by_run_idx
  on mark.regions(created_by_run_id);

create index if not exists instances_created_by_run_idx
  on mark.instances(created_by_run_id);

create index if not exists component_relations_evidence_region_idx
  on mark.component_relations(evidence_region_id);

create index if not exists component_relations_derived_by_run_idx
  on mark.component_relations(derived_by_run_id);

create or replace function mark.assert_json_keys_v1(
  p_value jsonb,
  p_allowed text[],
  p_context text
)
returns void
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  v_key text;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'object' then
    raise exception 'MARK_INTAKE_INVALID_OBJECT: % must be a JSON object', p_context;
  end if;

  for v_key in select jsonb_object_keys(p_value)
  loop
    if not (v_key = any(p_allowed)) then
      raise exception 'MARK_INTAKE_UNAPPROVED_FIELD: %.% is not part of the physical intake contract', p_context, v_key;
    end if;
  end loop;
end
$$;

create or replace function mark.require_bbox_v1(
  p_bbox jsonb,
  p_context text
)
returns table(x integer, y integer, width integer, height integer)
language plpgsql
set search_path = pg_catalog, mark
as $$
begin
  perform mark.assert_json_keys_v1(p_bbox, array['x','y','width','height'], p_context || '.bbox');

  begin
    x := (p_bbox->>'x')::integer;
    y := (p_bbox->>'y')::integer;
    width := (p_bbox->>'width')::integer;
    height := (p_bbox->>'height')::integer;
  exception when others then
    raise exception 'MARK_INTAKE_INVALID_BBOX: % requires integer x, y, width, height', p_context;
  end;

  if x is null or y is null or width is null or height is null
     or x < 0 or y < 0 or width <= 0 or height <= 0 then
    raise exception 'MARK_INTAKE_INVALID_BBOX: % requires x/y >= 0 and width/height > 0', p_context;
  end if;

  return next;
end
$$;

create or replace function mark.ensure_region_v1(
  p_region_key text,
  p_capture_id bigint,
  p_surface_id bigint,
  p_parent_region_id bigint,
  p_region_kind text,
  p_bbox jsonb,
  p_observation_status text default 'observed_visible',
  p_segmentation_origin text default 'human',
  p_confidence numeric default 1.0
)
returns bigint
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  v_region_id bigint;
  v_x integer;
  v_y integer;
  v_width integer;
  v_height integer;
  v_existing mark.regions%rowtype;
begin
  if p_region_key is null or btrim(p_region_key) = '' then
    raise exception 'MARK_INTAKE_REQUIRED_FIELD: region_key';
  end if;

  select b.x, b.y, b.width, b.height
    into v_x, v_y, v_width, v_height
  from mark.require_bbox_v1(p_bbox, 'region ' || p_region_key) b;

  select * into v_existing
  from mark.regions
  where region_key = p_region_key;

  if found then
    if v_existing.capture_id <> p_capture_id
       or v_existing.surface_id <> p_surface_id
       or v_existing.parent_region_id is distinct from p_parent_region_id
       or v_existing.region_kind <> p_region_kind
       or v_existing.bbox_x <> v_x
       or v_existing.bbox_y <> v_y
       or v_existing.bbox_width <> v_width
       or v_existing.bbox_height <> v_height
       or v_existing.observation_status <> p_observation_status
       or v_existing.segmentation_origin <> p_segmentation_origin
       or v_existing.confidence <> p_confidence then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: region_key % already names different physical evidence', p_region_key;
    end if;
    return v_existing.region_id;
  end if;

  insert into mark.regions(
    region_key, capture_id, surface_id, parent_region_id, region_kind,
    bbox_x, bbox_y, bbox_width, bbox_height,
    observation_status, segmentation_origin, confidence
  ) values (
    p_region_key, p_capture_id, p_surface_id, p_parent_region_id, p_region_kind,
    v_x, v_y, v_width, v_height,
    p_observation_status, p_segmentation_origin, p_confidence
  )
  returning region_id into v_region_id;

  return v_region_id;
end
$$;

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
  v_source mark.source_objects%rowtype;
  v_surface mark.surfaces%rowtype;
  v_capture mark.captures%rowtype;
  v_capture_surface mark.capture_surfaces%rowtype;
  v_zone_row mark.sequence_zones%rowtype;
  v_instance_row mark.instances%rowtype;
  v_component_row mark.components%rowtype;
  v_subject mark.components%rowtype;
  v_object mark.components%rowtype;
  v_source_id bigint;
  v_surface_id bigint;
  v_capture_id bigint;
  v_zone_region_id bigint;
  v_instance_region_id bigint;
  v_component_region_id bigint;
  v_evidence_region_id bigint;
  v_sequence_zone_id bigint;
  v_instance_id bigint;
  v_component_id bigint;
  v_ordinal integer;
  v_component_count integer := 0;
  v_relation_count integer := 0;
  v_instance_count integer := 0;
  v_x integer;
  v_y integer;
  v_width integer;
  v_height integer;
  v_confidence numeric;
  v_observation_status text;
  v_segmentation_origin text;
  v_component_order integer;
  v_instance_key text;
  v_component_key text;
  v_relation_instance_key text;
  v_subject_key text;
  v_object_key text;
begin
  perform mark.assert_json_keys_v1(p_payload, array['witness','zone','instances'], 'payload');

  v_witness := p_payload->'witness';
  v_zone := p_payload->'zone';

  -- The caller may identify the physical witness and its bytes, but may not
  -- assign free-text object/surface/capture categories through this intake.
  perform mark.assert_json_keys_v1(
    v_witness,
    array[
      'object_key','surface_key','physical_order',
      'capture_key','source_uri','original_filename','mime_type',
      'width_px','height_px','sha256','surface_bbox'
    ],
    'witness'
  );

  -- Likewise, sequence-zone classification is mechanism-owned. The caller
  -- supplies only physical region geometry, ordering, and flow geometry.
  perform mark.assert_json_keys_v1(
    v_zone,
    array['region_key','bbox','zone_key','flow_direction','physical_order','confidence'],
    'zone'
  );

  if jsonb_typeof(p_payload->'instances') <> 'array'
     or jsonb_array_length(p_payload->'instances') = 0 then
    raise exception 'MARK_INTAKE_REQUIRED_FIELD: instances must be a non-empty JSON array';
  end if;

  if nullif(btrim(v_witness->>'object_key'), '') is null
     or nullif(btrim(v_witness->>'surface_key'), '') is null
     or nullif(btrim(v_witness->>'capture_key'), '') is null then
    raise exception 'MARK_INTAKE_REQUIRED_FIELD: witness object_key/surface_key/capture_key are required';
  end if;

  select * into v_source
  from mark.source_objects
  where object_key = v_witness->>'object_key';

  if found then
    if v_source.object_kind <> 'physical_witness' then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: object_key % is not owned by the neutral physical intake class', v_source.object_key;
    end if;
    v_source_id := v_source.source_object_id;
  else
    insert into mark.source_objects(object_key, object_kind)
    values (v_witness->>'object_key', 'physical_witness')
    returning source_object_id into v_source_id;
  end if;

  select * into v_surface
  from mark.surfaces
  where surface_key = v_witness->>'surface_key';

  if found then
    if v_surface.source_object_id <> v_source_id
       or v_surface.surface_role <> 'unspecified'
       or v_surface.physical_order is distinct from nullif(v_witness->>'physical_order','')::numeric then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: surface_key % already names different physical evidence', v_surface.surface_key;
    end if;
    v_surface_id := v_surface.surface_id;
  else
    insert into mark.surfaces(source_object_id, surface_key, surface_role, physical_order)
    values (
      v_source_id,
      v_witness->>'surface_key',
      'unspecified',
      nullif(v_witness->>'physical_order','')::numeric
    )
    returning surface_id into v_surface_id;
  end if;

  select * into v_capture
  from mark.captures
  where capture_key = v_witness->>'capture_key';

  if found then
    if v_capture.capture_kind <> 'raster_capture'
       or v_capture.source_uri is distinct from nullif(v_witness->>'source_uri','')
       or v_capture.original_filename is distinct from nullif(v_witness->>'original_filename','')
       or v_capture.mime_type is distinct from nullif(v_witness->>'mime_type','')
       or v_capture.width_px is distinct from nullif(v_witness->>'width_px','')::integer
       or v_capture.height_px is distinct from nullif(v_witness->>'height_px','')::integer
       or v_capture.sha256 is distinct from nullif(lower(v_witness->>'sha256'),'') then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: capture_key % already names different capture evidence', v_capture.capture_key;
    end if;
    v_capture_id := v_capture.capture_id;
  else
    insert into mark.captures(
      capture_key, capture_kind, source_uri, original_filename, mime_type,
      width_px, height_px, sha256,
      capture_status
    ) values (
      v_witness->>'capture_key',
      'raster_capture',
      nullif(v_witness->>'source_uri',''),
      nullif(v_witness->>'original_filename',''),
      nullif(v_witness->>'mime_type',''),
      nullif(v_witness->>'width_px','')::integer,
      nullif(v_witness->>'height_px','')::integer,
      nullif(lower(v_witness->>'sha256'),''),
      case
        when nullif(v_witness->>'sha256','') is not null
         and nullif(v_witness->>'width_px','') is not null
         and nullif(v_witness->>'height_px','') is not null
        then 'bytes_verified'
        else 'registered_remote'
      end
    )
    returning capture_id into v_capture_id;
  end if;

  if v_witness ? 'surface_bbox' then
    select b.x, b.y, b.width, b.height
      into v_x, v_y, v_width, v_height
    from mark.require_bbox_v1(v_witness->'surface_bbox', 'witness.surface') b;
  else
    v_x := null; v_y := null; v_width := null; v_height := null;
  end if;

  select * into v_capture_surface
  from mark.capture_surfaces
  where capture_id = v_capture_id and surface_id = v_surface_id;

  if found then
    if v_capture_surface.bbox_x is distinct from v_x
       or v_capture_surface.bbox_y is distinct from v_y
       or v_capture_surface.bbox_width is distinct from v_width
       or v_capture_surface.bbox_height is distinct from v_height then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: capture/surface mapping already has different geometry';
    end if;
  else
    insert into mark.capture_surfaces(
      capture_id, surface_id, bbox_x, bbox_y, bbox_width, bbox_height
    ) values (
      v_capture_id, v_surface_id, v_x, v_y, v_width, v_height
    );
  end if;

  v_confidence := coalesce(nullif(v_zone->>'confidence','')::numeric, 1.0);
  v_zone_region_id := mark.ensure_region_v1(
    v_zone->>'region_key', v_capture_id, v_surface_id, null,
    'sequence_zone',
    v_zone->'bbox', 'observed_visible', 'human', v_confidence
  );

  select * into v_zone_row
  from mark.sequence_zones
  where zone_key = v_zone->>'zone_key';

  if found then
    if v_zone_row.region_id <> v_zone_region_id
       or v_zone_row.zone_kind <> 'ordered_physical_region'
       or v_zone_row.flow_direction <> coalesce(nullif(v_zone->>'flow_direction',''), 'undetermined')
       or v_zone_row.physical_order is distinct from nullif(v_zone->>'physical_order','')::numeric
       or v_zone_row.confidence <> v_confidence then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: zone_key % already names different physical evidence', v_zone_row.zone_key;
    end if;
    v_sequence_zone_id := v_zone_row.sequence_zone_id;
  else
    if nullif(btrim(v_zone->>'zone_key'),'') is null then
      raise exception 'MARK_INTAKE_REQUIRED_FIELD: zone.zone_key is required';
    end if;
    insert into mark.sequence_zones(region_id, zone_key, zone_kind, flow_direction, physical_order, confidence)
    values (
      v_zone_region_id,
      v_zone->>'zone_key',
      'ordered_physical_region',
      coalesce(nullif(v_zone->>'flow_direction',''), 'undetermined'),
      nullif(v_zone->>'physical_order','')::numeric,
      v_confidence
    )
    returning sequence_zone_id into v_sequence_zone_id;
  end if;

  v_ordinal := 0;
  for v_instance in select value from jsonb_array_elements(p_payload->'instances')
  loop
    perform mark.assert_json_keys_v1(
      v_instance,
      array['instance_key','region_key','bbox','observation_status','segmentation_origin','confidence','components','relations'],
      'instance[' || v_ordinal || ']'
    );

    v_instance_key := v_instance->>'instance_key';
    if nullif(btrim(v_instance_key),'') is null then
      raise exception 'MARK_INTAKE_REQUIRED_FIELD: instance[%].instance_key', v_ordinal;
    end if;
    if jsonb_typeof(v_instance->'components') <> 'array' or jsonb_array_length(v_instance->'components') = 0 then
      raise exception 'MARK_INTAKE_REQUIRED_FIELD: instance[%].components must be non-empty', v_ordinal;
    end if;
    if v_instance ? 'relations' and jsonb_typeof(v_instance->'relations') <> 'array' then
      raise exception 'MARK_INTAKE_INVALID_ARRAY: instance[%].relations', v_ordinal;
    end if;

    v_observation_status := coalesce(nullif(v_instance->>'observation_status',''), 'observed_visible');
    v_segmentation_origin := coalesce(nullif(v_instance->>'segmentation_origin',''), 'human');
    v_confidence := coalesce(nullif(v_instance->>'confidence','')::numeric, 1.0);

    v_instance_region_id := mark.ensure_region_v1(
      v_instance->>'region_key', v_capture_id, v_surface_id, v_zone_region_id,
      'candidate_mark_instance', v_instance->'bbox',
      v_observation_status, v_segmentation_origin, v_confidence
    );

    select * into v_instance_row from mark.instances where instance_key = v_instance_key;
    if found then
      if v_instance_row.region_id <> v_instance_region_id
         or v_instance_row.observation_status <> v_observation_status
         or v_instance_row.segmentation_origin <> v_segmentation_origin
         or v_instance_row.confidence <> v_confidence then
        raise exception 'MARK_INTAKE_KEY_CONFLICT: instance_key % already names different physical evidence', v_instance_key;
      end if;
      v_instance_id := v_instance_row.instance_id;
    else
      insert into mark.instances(instance_key, region_id, observation_status, segmentation_origin, confidence)
      values (v_instance_key, v_instance_region_id, v_observation_status, v_segmentation_origin, v_confidence)
      returning instance_id into v_instance_id;
    end if;

    insert into mark.sequence_members(sequence_zone_id, instance_id, ordinal_position)
    values (v_sequence_zone_id, v_instance_id, v_ordinal)
    on conflict (sequence_zone_id, instance_id) do nothing;

    if not exists (
      select 1 from mark.sequence_members
      where sequence_zone_id = v_sequence_zone_id
        and instance_id = v_instance_id
        and ordinal_position = v_ordinal
    ) then
      raise exception 'MARK_INTAKE_KEY_CONFLICT: instance % already occupies a different sequence position', v_instance_key;
    end if;

    v_component_order := 0;
    for v_component in select value from jsonb_array_elements(v_instance->'components')
    loop
      perform mark.assert_json_keys_v1(
        v_component,
        array['component_key','region_key','bbox','channel_key','component_order','observation_status','confidence'],
        'instance[' || v_ordinal || '].component[' || v_component_order || ']'
      );

      v_component_key := v_component->>'component_key';
      if nullif(btrim(v_component_key),'') is null or nullif(btrim(v_component->>'channel_key'),'') is null then
        raise exception 'MARK_INTAKE_REQUIRED_FIELD: component_key and channel_key are required';
      end if;
      if not exists (select 1 from mark.channel_registry where channel_key = v_component->>'channel_key') then
        raise exception 'MARK_INTAKE_UNKNOWN_CHANNEL: %', v_component->>'channel_key';
      end if;

      v_observation_status := coalesce(nullif(v_component->>'observation_status',''), 'observed_visible');
      v_confidence := coalesce(nullif(v_component->>'confidence','')::numeric, 1.0);
      v_component_region_id := mark.ensure_region_v1(
        v_component->>'region_key', v_capture_id, v_surface_id, v_instance_region_id,
        'mark_component', v_component->'bbox',
        v_observation_status, v_segmentation_origin, v_confidence
      );

      select * into v_component_row from mark.components where component_key = v_component_key;
      if found then
        if v_component_row.instance_id <> v_instance_id
           or v_component_row.region_id <> v_component_region_id
           or v_component_row.channel_key <> v_component->>'channel_key'
           or v_component_row.component_order is distinct from coalesce(nullif(v_component->>'component_order','')::integer, v_component_order)
           or v_component_row.observation_status <> v_observation_status
           or v_component_row.confidence <> v_confidence then
          raise exception 'MARK_INTAKE_KEY_CONFLICT: component_key % already names different physical evidence', v_component_key;
        end if;
        v_component_id := v_component_row.component_id;
      else
        insert into mark.components(
          component_key, instance_id, region_id, channel_key, component_order,
          observation_status, confidence
        ) values (
          v_component_key, v_instance_id, v_component_region_id,
          v_component->>'channel_key',
          coalesce(nullif(v_component->>'component_order','')::integer, v_component_order),
          v_observation_status, v_confidence
        ) returning component_id into v_component_id;
      end if;

      v_component_order := v_component_order + 1;
      v_component_count := v_component_count + 1;
    end loop;

    for v_relation in select value from jsonb_array_elements(coalesce(v_instance->'relations','[]'::jsonb))
    loop
      perform mark.assert_json_keys_v1(
        v_relation,
        array['relation_instance_key','subject_component_key','object_component_key','relation_key','evidence_region_key','distance_px','angle_degrees','observation_status','confidence'],
        'instance[' || v_ordinal || '].relation'
      );

      v_relation_instance_key := v_relation->>'relation_instance_key';
      v_subject_key := v_relation->>'subject_component_key';
      v_object_key := v_relation->>'object_component_key';

      if nullif(btrim(v_relation_instance_key),'') is null
         or nullif(btrim(v_subject_key),'') is null
         or nullif(btrim(v_object_key),'') is null
         or nullif(btrim(v_relation->>'relation_key'),'') is null then
        raise exception 'MARK_INTAKE_REQUIRED_FIELD: relation_instance_key, subject_component_key, object_component_key, relation_key';
      end if;

      select * into v_subject from mark.components where component_key = v_subject_key;
      select * into v_object from mark.components where component_key = v_object_key;
      if v_subject.component_id is null or v_object.component_id is null then
        raise exception 'MARK_INTAKE_UNKNOWN_COMPONENT: relation % endpoints must already exist in this intake', v_relation_instance_key;
      end if;
      if v_subject.instance_id <> v_instance_id or v_object.instance_id <> v_instance_id then
        raise exception 'MARK_INTAKE_CROSS_INSTANCE_RELATION: relation % endpoints must belong to instance %', v_relation_instance_key, v_instance_key;
      end if;
      if not exists (select 1 from mark.relation_registry where relation_key = v_relation->>'relation_key') then
        raise exception 'MARK_INTAKE_UNKNOWN_RELATION: %', v_relation->>'relation_key';
      end if;

      v_evidence_region_id := null;
      if nullif(v_relation->>'evidence_region_key','') is not null then
        select region_id into v_evidence_region_id
        from mark.regions
        where region_key = v_relation->>'evidence_region_key'
          and capture_id = v_capture_id
          and surface_id = v_surface_id;
        if v_evidence_region_id is null then
          raise exception 'MARK_INTAKE_UNKNOWN_EVIDENCE_REGION: %', v_relation->>'evidence_region_key';
        end if;
      end if;

      if exists (select 1 from mark.component_relations where relation_instance_key = v_relation_instance_key) then
        if not exists (
          select 1 from mark.component_relations
          where relation_instance_key = v_relation_instance_key
            and subject_component_id = v_subject.component_id
            and object_component_id = v_object.component_id
            and relation_key = v_relation->>'relation_key'
            and evidence_region_id is not distinct from v_evidence_region_id
            and distance_px is not distinct from nullif(v_relation->>'distance_px','')::numeric
            and angle_degrees is not distinct from nullif(v_relation->>'angle_degrees','')::numeric
            and observation_status = coalesce(nullif(v_relation->>'observation_status',''), 'observed_visible')
            and confidence = coalesce(nullif(v_relation->>'confidence','')::numeric, 1.0)
        ) then
          raise exception 'MARK_INTAKE_KEY_CONFLICT: relation_instance_key % already names different physical evidence', v_relation_instance_key;
        end if;
      else
        insert into mark.component_relations(
          relation_instance_key, subject_component_id, object_component_id,
          relation_key, evidence_region_id, distance_px, angle_degrees,
          observation_status, confidence
        ) values (
          v_relation_instance_key, v_subject.component_id, v_object.component_id,
          v_relation->>'relation_key', v_evidence_region_id,
          nullif(v_relation->>'distance_px','')::numeric,
          nullif(v_relation->>'angle_degrees','')::numeric,
          coalesce(nullif(v_relation->>'observation_status',''), 'observed_visible'),
          coalesce(nullif(v_relation->>'confidence','')::numeric, 1.0)
        );
      end if;
      v_relation_count := v_relation_count + 1;
    end loop;

    v_instance_count := v_instance_count + 1;
    v_ordinal := v_ordinal + 1;
  end loop;

  return jsonb_build_object(
    'source_object_id', v_source_id,
    'surface_id', v_surface_id,
    'capture_id', v_capture_id,
    'sequence_zone_id', v_sequence_zone_id,
    'instance_count', v_instance_count,
    'component_count', v_component_count,
    'relation_count', v_relation_count
  );
end
$$;

comment on function mark.ingest_physical_sequence_v1(jsonb) is
  'Atomic governed semantic-blind intake for physical witness custody, capture/surface registration, anonymous mark instances, physical components, junction/topology relations, and sequence order. Caller-authored category labels and arbitrary metadata are rejected.';

revoke all on function mark.assert_json_keys_v1(jsonb, text[], text) from public, anon, authenticated, service_role;
revoke all on function mark.require_bbox_v1(jsonb, text) from public, anon, authenticated, service_role;
revoke all on function mark.ensure_region_v1(text, bigint, bigint, bigint, text, jsonb, text, text, numeric) from public, anon, authenticated, service_role;
revoke all on function mark.ingest_physical_sequence_v1(jsonb) from public, anon, authenticated, service_role;

-- Prove the application membrane remains closed after function creation.
do $$
declare
  role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name, 'mark', 'USAGE')
       or has_function_privilege(role_name, 'mark.ingest_physical_sequence_v1(jsonb)', 'EXECUTE') then
      raise exception 'MARK_MEMBRANE_VIOLATION: role % can reach physical intake', role_name;
    end if;
  end loop;
end
$$;

commit;
