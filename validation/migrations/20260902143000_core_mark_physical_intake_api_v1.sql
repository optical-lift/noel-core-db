\set ON_ERROR_STOP on

-- Production schema-clone validation is intentionally schema-only, so seeded
-- registry rows are absent from the disposable clone. Recreate only the
-- physical registry fixtures exercised by this postcondition. These rows live
-- only in the disposable validator database; production release does not run
-- validation/migrations SQL.
insert into mark.channel_registry(
  channel_key, channel_family, channel_name, physical_basis, strict_blind_allowed
)
values
  ('ink_dark', 'pigment', 'Dark ink/pigment', 'Observed low-luminance deposited material.', true),
  ('pigment_red', 'pigment', 'Red pigment', 'Observed red-hued deposited material.', true)
on conflict (channel_key) do nothing;

insert into mark.relation_registry(
  relation_key, relation_family, relation_name, directed, physical_definition,
  inverse_relation_key, strict_blind_allowed
)
values
  ('touches', 'junction', 'Touches', false,
   'Two observed components meet at one or more physical boundary points.',
   null, true)
on conflict (relation_key) do nothing;

-- The governed physical intake surface and its supporting indexes must exist.
do $$
declare
  idx text;
  expected_indexes text[] := array[
    'source_objects_parent_source_object_idx',
    'captures_derivative_of_capture_idx',
    'relation_registry_inverse_relation_idx',
    'regions_created_by_run_idx',
    'instances_created_by_run_idx',
    'component_relations_evidence_region_idx',
    'component_relations_derived_by_run_idx'
  ];
begin
  if to_regprocedure('mark.ingest_physical_sequence_v1(jsonb)') is null then
    raise exception 'MARK_INTAKE_POSTCONDITION: intake function missing';
  end if;

  foreach idx in array expected_indexes loop
    if not exists (
      select 1 from pg_indexes
      where schemaname='mark' and indexname=idx
    ) then
      raise exception 'MARK_INTAKE_POSTCONDITION: expected index % missing', idx;
    end if;
  end loop;
end
$$;

-- Runtime/application roles must remain outside the Mark membrane.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE')
       or has_schema_privilege(role_name,'mark','CREATE')
       or has_function_privilege(role_name,'mark.ingest_physical_sequence_v1(jsonb)','EXECUTE') then
      raise exception 'MARK_INTAKE_POSTCONDITION: role % can reach physical intake', role_name;
    end if;
  end loop;
end
$$;

-- Happy path: anonymous physical units, components, a junction, and sequence order.
do $$
declare
  payload jsonb := jsonb_build_object(
    'witness', jsonb_build_object(
      'object_key','__mark_intake_validation_object__',
      'surface_key','__mark_intake_validation_surface__',
      'physical_order',1,
      'capture_key','__mark_intake_validation_capture__',
      'source_uri','validation://physical-witness',
      'original_filename','validation.png',
      'mime_type','image/png',
      'width_px',1000,
      'height_px',500,
      'sha256',repeat('a',64),
      'surface_bbox',jsonb_build_object('x',0,'y',0,'width',1000,'height',500)
    ),
    'zone', jsonb_build_object(
      'region_key','__mark_intake_validation_zone_region__',
      'bbox',jsonb_build_object('x',10,'y',10,'width',900,'height',200),
      'zone_key','__mark_intake_validation_zone__',
      'flow_direction','left_to_right',
      'physical_order',1,
      'confidence',1
    ),
    'instances', jsonb_build_array(
      jsonb_build_object(
        'instance_key','__mark_intake_validation_i0__',
        'region_key','__mark_intake_validation_i0_region__',
        'bbox',jsonb_build_object('x',20,'y',20,'width',80,'height',100),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_intake_validation_i0_c0__',
            'region_key','__mark_intake_validation_i0_c0_region__',
            'bbox',jsonb_build_object('x',25,'y',25,'width',10,'height',90),
            'channel_key','ink_dark'
          ),
          jsonb_build_object(
            'component_key','__mark_intake_validation_i0_c1__',
            'region_key','__mark_intake_validation_i0_c1_region__',
            'bbox',jsonb_build_object('x',20,'y',65,'width',70,'height',10),
            'channel_key','ink_dark'
          )
        ),
        'relations',jsonb_build_array(
          jsonb_build_object(
            'relation_instance_key','__mark_intake_validation_i0_j0__',
            'subject_component_key','__mark_intake_validation_i0_c0__',
            'object_component_key','__mark_intake_validation_i0_c1__',
            'relation_key','touches',
            'confidence',1
          )
        )
      ),
      jsonb_build_object(
        'instance_key','__mark_intake_validation_i1__',
        'region_key','__mark_intake_validation_i1_region__',
        'bbox',jsonb_build_object('x',120,'y',20,'width',60,'height',100),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_intake_validation_i1_c0__',
            'region_key','__mark_intake_validation_i1_c0_region__',
            'bbox',jsonb_build_object('x',130,'y',25,'width',10,'height',90),
            'channel_key','pigment_red'
          )
        )
      )
    )
  );
  first_result jsonb;
  second_result jsonb;
begin
  first_result := mark.ingest_physical_sequence_v1(payload);
  second_result := mark.ingest_physical_sequence_v1(payload);

  if first_result <> second_result then
    raise exception 'MARK_INTAKE_POSTCONDITION: idempotent replay returned different identity/count result';
  end if;

  if (first_result->>'instance_count')::integer <> 2
     or (first_result->>'component_count')::integer <> 3
     or (first_result->>'relation_count')::integer <> 1 then
    raise exception 'MARK_INTAKE_POSTCONDITION: unexpected intake counts %', first_result;
  end if;

  if (select count(*) from mark.instances where instance_key like '__mark_intake_validation_i%__') <> 2 then
    raise exception 'MARK_INTAKE_POSTCONDITION: idempotent replay duplicated instances';
  end if;

  if (select count(*) from mark.components where component_key like '__mark_intake_validation_i%_c%__') <> 3 then
    raise exception 'MARK_INTAKE_POSTCONDITION: idempotent replay duplicated components';
  end if;

  if not exists (
    select 1
    from mark.component_relations cr
    join mark.relation_registry rr on rr.relation_key=cr.relation_key
    where cr.relation_instance_key='__mark_intake_validation_i0_j0__'
      and rr.relation_family='junction'
      and cr.relation_key='touches'
  ) then
    raise exception 'MARK_INTAKE_POSTCONDITION: physical junction was not recorded';
  end if;

  if not exists (
    select 1
    from mark.sequence_members sm
    join mark.sequence_zones sz on sz.sequence_zone_id=sm.sequence_zone_id
    join mark.instances i on i.instance_id=sm.instance_id
    where sz.zone_key='__mark_intake_validation_zone__'
      and i.instance_key='__mark_intake_validation_i0__'
      and sm.ordinal_position=0
  ) or not exists (
    select 1
    from mark.sequence_members sm
    join mark.sequence_zones sz on sz.sequence_zone_id=sm.sequence_zone_id
    join mark.instances i on i.instance_id=sm.instance_id
    where sz.zone_key='__mark_intake_validation_zone__'
      and i.instance_key='__mark_intake_validation_i1__'
      and sm.ordinal_position=1
  ) then
    raise exception 'MARK_INTAKE_POSTCONDITION: sequence order was not preserved';
  end if;

  if not exists (
    select 1 from mark.source_objects
    where object_key='__mark_intake_validation_object__'
      and object_kind='physical_witness'
  ) or not exists (
    select 1 from mark.captures
    where capture_key='__mark_intake_validation_capture__'
      and capture_kind='raster_capture'
  ) or not exists (
    select 1 from mark.sequence_zones
    where zone_key='__mark_intake_validation_zone__'
      and zone_kind='ordered_physical_region'
  ) then
    raise exception 'MARK_INTAKE_POSTCONDITION: mechanism-owned neutral categories were not enforced';
  end if;
end
$$;

-- Caller-authored category/meaning fields must be rejected before any evidence is written.
do $$
declare
  blocked boolean := false;
  bad_payload jsonb := jsonb_build_object(
    'witness', jsonb_build_object(
      'object_key','__mark_intake_semantic_reject_object__',
      'object_kind','letter_or_word',
      'surface_key','__mark_intake_semantic_reject_surface__',
      'capture_key','__mark_intake_semantic_reject_capture__'
    ),
    'zone', jsonb_build_object(
      'region_key','__mark_intake_semantic_reject_zone_region__',
      'bbox',jsonb_build_object('x',0,'y',0,'width',10,'height',10),
      'zone_key','__mark_intake_semantic_reject_zone__'
    ),
    'instances',jsonb_build_array(
      jsonb_build_object(
        'instance_key','__mark_intake_semantic_reject_i0__',
        'region_key','__mark_intake_semantic_reject_i0_region__',
        'bbox',jsonb_build_object('x',0,'y',0,'width',5,'height',5),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_intake_semantic_reject_c0__',
            'region_key','__mark_intake_semantic_reject_c0_region__',
            'bbox',jsonb_build_object('x',0,'y',0,'width',1,'height',5),
            'channel_key','ink_dark'
          )
        )
      )
    )
  );
begin
  begin
    perform mark.ingest_physical_sequence_v1(bad_payload);
  exception when others then
    if position('MARK_INTAKE_UNAPPROVED_FIELD' in sqlerrm) > 0 then
      blocked := true;
    else
      raise;
    end if;
  end;

  if not blocked then
    raise exception 'MARK_INTAKE_POSTCONDITION: semantic category field was accepted';
  end if;

  if exists (select 1 from mark.source_objects where object_key='__mark_intake_semantic_reject_object__') then
    raise exception 'MARK_INTAKE_POSTCONDITION: rejected semantic payload left partial evidence';
  end if;
end
$$;

-- Junction endpoints must belong to the same anonymous physical instance.
-- The failed call must roll back its earlier witness/capture/instance inserts atomically.
do $$
declare
  blocked boolean := false;
  bad_payload jsonb := jsonb_build_object(
    'witness',jsonb_build_object(
      'object_key','__mark_intake_cross_reject_object__',
      'surface_key','__mark_intake_cross_reject_surface__',
      'capture_key','__mark_intake_cross_reject_capture__'
    ),
    'zone',jsonb_build_object(
      'region_key','__mark_intake_cross_reject_zone_region__',
      'bbox',jsonb_build_object('x',0,'y',0,'width',100,'height',100),
      'zone_key','__mark_intake_cross_reject_zone__'
    ),
    'instances',jsonb_build_array(
      jsonb_build_object(
        'instance_key','__mark_intake_cross_reject_i0__',
        'region_key','__mark_intake_cross_reject_i0_region__',
        'bbox',jsonb_build_object('x',0,'y',0,'width',20,'height',20),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_intake_cross_reject_i0_c0__',
            'region_key','__mark_intake_cross_reject_i0_c0_region__',
            'bbox',jsonb_build_object('x',0,'y',0,'width',5,'height',20),
            'channel_key','ink_dark'
          )
        )
      ),
      jsonb_build_object(
        'instance_key','__mark_intake_cross_reject_i1__',
        'region_key','__mark_intake_cross_reject_i1_region__',
        'bbox',jsonb_build_object('x',30,'y',0,'width',20,'height',20),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_intake_cross_reject_i1_c0__',
            'region_key','__mark_intake_cross_reject_i1_c0_region__',
            'bbox',jsonb_build_object('x',30,'y',0,'width',5,'height',20),
            'channel_key','ink_dark'
          )
        ),
        'relations',jsonb_build_array(
          jsonb_build_object(
            'relation_instance_key','__mark_intake_cross_reject_j0__',
            'subject_component_key','__mark_intake_cross_reject_i0_c0__',
            'object_component_key','__mark_intake_cross_reject_i1_c0__',
            'relation_key','touches'
          )
        )
      )
    )
  );
begin
  begin
    perform mark.ingest_physical_sequence_v1(bad_payload);
  exception when others then
    if position('MARK_INTAKE_CROSS_INSTANCE_RELATION' in sqlerrm) > 0 then
      blocked := true;
    else
      raise;
    end if;
  end;

  if not blocked then
    raise exception 'MARK_INTAKE_POSTCONDITION: cross-instance junction was accepted';
  end if;

  if exists (select 1 from mark.source_objects where object_key='__mark_intake_cross_reject_object__')
     or exists (select 1 from mark.captures where capture_key='__mark_intake_cross_reject_capture__')
     or exists (select 1 from mark.instances where instance_key='__mark_intake_cross_reject_i0__') then
    raise exception 'MARK_INTAKE_POSTCONDITION: failed cross-instance intake was not atomic';
  end if;
end
$$;
