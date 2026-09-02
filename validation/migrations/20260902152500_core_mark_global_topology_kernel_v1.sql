\set ON_ERROR_STOP on

-- Mark Global Topology Kernel v1 postcondition.
-- The validator database is a production-schema clone. This migration itself
-- seeds every new registry row exercised below, so no semantic/context fixture
-- is needed outside the canonical postcondition.

-- Core topology/context objects must exist and the balanced pilot must total 1500.
do $$
begin
  if to_regclass('mark.morphology_registry') is null
     or to_regclass('mark.component_morphologies') is null
     or to_regclass('mark.feature_registry') is null
     or to_regclass('mark.feature_observations') is null
     or to_regclass('mark.operator_registry') is null
     or to_regclass('mark.operator_observations') is null
     or to_regclass('mark_context.system_registry') is null
     or to_regclass('mark_context.corpus_batch_targets') is null then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: required table missing';
  end if;

  if to_regprocedure('mark.ingest_physical_topology_edges_v1(jsonb)') is null then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: cross-instance topology intake missing';
  end if;

  if (select count(*) from mark_context.system_registry where blind_code between 'SYS001' and 'SYS020') <> 20 then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: expected 20 pilot systems';
  end if;

  if (select coalesce(sum(target_units),0) from mark_context.corpus_batch_targets where batch_key='global_topology_pilot_v1') <> 1500 then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: pilot target must total 1500';
  end if;

  if not exists (select 1 from mark_context.system_registry where system_key='khipu' and blind_code='SYS017' and comparison_role='cross_medium_foundation') then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: khipu is not a foundational cross-medium pilot system';
  end if;

  if not exists (select 1 from mark.channel_registry where channel_key='fiber_or_cord')
     or not exists (select 1 from mark.channel_registry where channel_key='void_interval')
     or not exists (select 1 from mark.relation_registry where relation_key='attached_to')
     or not exists (select 1 from mark.relation_registry where relation_key='wraps_around')
     or not exists (select 1 from mark.morphology_registry where morphology_key='localized_interlacing')
     or not exists (select 1 from mark.operator_registry where operator_key='OP_GAP') then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: universal physical vocabulary incomplete';
  end if;
end
$$;

-- Runtime/application roles must be outside both blind and context membranes.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE')
       or has_schema_privilege(role_name,'mark_context','USAGE')
       or has_function_privilege(role_name,'mark.ingest_physical_topology_edges_v1(jsonb)','EXECUTE') then
      raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: runtime role % can reach topology/context authority', role_name;
    end if;
  end loop;
end
$$;

-- Build one synthetic cord-like physical object using the existing neutral
-- physical-sequence intake. Two anonymous instances model distinguishable
-- substructures; the new topology intake must be able to connect them.
do $$
declare
  payload jsonb := jsonb_build_object(
    'witness',jsonb_build_object(
      'object_key','__mark_topology_validation_object__',
      'surface_key','__mark_topology_validation_surface__',
      'capture_key','__mark_topology_validation_capture__',
      'source_uri','validation://topology-object',
      'original_filename','topology-validation.png',
      'mime_type','image/png',
      'width_px',1200,
      'height_px',800,
      'sha256',repeat('b',64),
      'surface_bbox',jsonb_build_object('x',0,'y',0,'width',1200,'height',800)
    ),
    'zone',jsonb_build_object(
      'region_key','__mark_topology_validation_zone_region__',
      'bbox',jsonb_build_object('x',0,'y',0,'width',1000,'height',700),
      'zone_key','__mark_topology_validation_zone__',
      'flow_direction','network'
    ),
    'instances',jsonb_build_array(
      jsonb_build_object(
        'instance_key','__mark_topology_validation_i0__',
        'region_key','__mark_topology_validation_i0_region__',
        'bbox',jsonb_build_object('x',50,'y',50,'width',900,'height',60),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_topology_validation_primary__',
            'region_key','__mark_topology_validation_primary_region__',
            'bbox',jsonb_build_object('x',50,'y',70,'width',900,'height',20),
            'channel_key','fiber_or_cord'
          )
        )
      ),
      jsonb_build_object(
        'instance_key','__mark_topology_validation_i1__',
        'region_key','__mark_topology_validation_i1_region__',
        'bbox',jsonb_build_object('x',450,'y',80,'width',80,'height',500),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_topology_validation_pendant__',
            'region_key','__mark_topology_validation_pendant_region__',
            'bbox',jsonb_build_object('x',480,'y',80,'width',20,'height',500),
            'channel_key','fiber_or_cord'
          ),
          jsonb_build_object(
            'component_key','__mark_topology_validation_interlacing__',
            'region_key','__mark_topology_validation_interlacing_region__',
            'bbox',jsonb_build_object('x',460,'y',300,'width',60,'height',70),
            'channel_key','fiber_or_cord'
          ),
          jsonb_build_object(
            'component_key','__mark_topology_validation_gap__',
            'region_key','__mark_topology_validation_gap_region__',
            'bbox',jsonb_build_object('x',455,'y',200,'width',70,'height',50),
            'channel_key','void_interval'
          )
        )
      )
    )
  );
  first_edges jsonb;
  second_edges jsonb;
  primary_id bigint;
  pendant_id bigint;
  interlacing_id bigint;
  gap_id bigint;
  edge_id bigint;
  zone_region_id bigint;
begin
  perform mark.ingest_physical_sequence_v1(payload);

  first_edges := mark.ingest_physical_topology_edges_v1(jsonb_build_object(
    'relations',jsonb_build_array(
      jsonb_build_object(
        'relation_instance_key','__mark_topology_validation_attach__',
        'subject_component_key','__mark_topology_validation_pendant__',
        'object_component_key','__mark_topology_validation_primary__',
        'relation_key','attached_to',
        'evidence_region_key','__mark_topology_validation_zone_region__',
        'confidence',1
      ),
      jsonb_build_object(
        'relation_instance_key','__mark_topology_validation_wrap__',
        'subject_component_key','__mark_topology_validation_interlacing__',
        'object_component_key','__mark_topology_validation_pendant__',
        'relation_key','wraps_around',
        'evidence_region_key','__mark_topology_validation_interlacing_region__',
        'confidence',1
      )
    )
  ));
  second_edges := mark.ingest_physical_topology_edges_v1(jsonb_build_object(
    'relations',jsonb_build_array(
      jsonb_build_object(
        'relation_instance_key','__mark_topology_validation_attach__',
        'subject_component_key','__mark_topology_validation_pendant__',
        'object_component_key','__mark_topology_validation_primary__',
        'relation_key','attached_to',
        'evidence_region_key','__mark_topology_validation_zone_region__',
        'confidence',1
      ),
      jsonb_build_object(
        'relation_instance_key','__mark_topology_validation_wrap__',
        'subject_component_key','__mark_topology_validation_interlacing__',
        'object_component_key','__mark_topology_validation_pendant__',
        'relation_key','wraps_around',
        'evidence_region_key','__mark_topology_validation_interlacing_region__',
        'confidence',1
      )
    )
  ));

  if first_edges <> second_edges or (first_edges->>'relation_count')::integer <> 2 then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: topology edge replay is not idempotent';
  end if;

  if (select count(*) from mark.component_relations where relation_instance_key like '__mark_topology_validation_%__') <> 2 then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: topology replay duplicated edges';
  end if;

  select component_id into primary_id from mark.components where component_key='__mark_topology_validation_primary__';
  select component_id into pendant_id from mark.components where component_key='__mark_topology_validation_pendant__';
  select component_id into interlacing_id from mark.components where component_key='__mark_topology_validation_interlacing__';
  select component_id into gap_id from mark.components where component_key='__mark_topology_validation_gap__';
  select component_relation_id into edge_id from mark.component_relations where relation_instance_key='__mark_topology_validation_attach__';
  select region_id into zone_region_id from mark.regions where region_key='__mark_topology_validation_zone_region__';

  if not exists (
    select 1 from mark.component_relations
    where relation_instance_key='__mark_topology_validation_attach__'
      and subject_component_id=pendant_id
      and object_component_id=primary_id
      and relation_key='attached_to'
  ) then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: cross-instance attachment edge missing';
  end if;

  insert into mark.component_morphologies(component_id,morphology_key,confidence)
  values
    (primary_id,'elongated',1),
    (pendant_id,'elongated',1),
    (interlacing_id,'localized_interlacing',1),
    (gap_id,'void_interval',1);

  insert into mark.feature_observations(
    observation_key,feature_key,component_id,categorical_value,confidence
  ) values (
    '__mark_topology_validation_twist__','observed_twist_slant',pendant_id,'s_like',1
  );

  insert into mark.feature_observations(
    observation_key,feature_key,component_relation_id,numeric_value,confidence
  ) values (
    '__mark_topology_validation_attach_pos__','attachment_position_normalized',edge_id,0.5,1
  );

  insert into mark.operator_observations(
    observation_key,operator_key,region_id,observation_basis,confidence
  ) values
    ('__mark_topology_validation_op_attach__','OP_ATTACH',zone_region_id,'deterministic_derived',1),
    ('__mark_topology_validation_op_gap__','OP_GAP',zone_region_id,'deterministic_derived',1);

  if not exists (
    select 1 from mark.blind_component_graph_v1
    where component_id=interlacing_id and morphology_key='localized_interlacing'
  ) then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: morphology is absent from blind graph surface';
  end if;

  if not exists (
    select 1 from mark.blind_feature_observations_v1
    where feature_key='observed_twist_slant' and component_id=pendant_id and categorical_value='s_like'
  ) then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: physical feature is absent from blind feature surface';
  end if;
end
$$;

-- Typed feature guard must reject semantically/structurally invalid values.
do $$
declare
  pendant_id bigint;
  rejected boolean := false;
begin
  select component_id into pendant_id from mark.components where component_key='__mark_topology_validation_pendant__';

  begin
    insert into mark.feature_observations(
      observation_key,feature_key,component_id,categorical_value
    ) values (
      '__mark_topology_validation_bad_twist__','observed_twist_slant',pendant_id,'means_priesthood'
    );
  exception when others then
    if position('MARK_FEATURE_CATEGORY_REJECTED' in sqlerrm) > 0 then
      rejected := true;
    else
      raise;
    end if;
  end;

  if not rejected then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: unapproved categorical feature value was accepted';
  end if;
end
$$;

-- Context can map the object to khipu, but the blind clustering views must not
-- expose that identity or source keys.
do $$
declare source_id bigint;
begin
  select source_object_id into source_id
  from mark.source_objects
  where object_key='__mark_topology_validation_object__';

  insert into mark_context.source_system_assignments(
    source_object_id,system_key,assignment_basis,confidence
  ) values (source_id,'khipu','project_control',1);

  if not exists (
    select 1 from mark_context.source_system_assignments
    where source_object_id=source_id and system_key='khipu'
  ) then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: rejoin mapping missing';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='mark'
      and table_name in ('blind_component_graph_v1','blind_topology_edges_v1','blind_feature_observations_v1')
      and column_name in ('system_key','blind_code','canonical_label','object_key','object_label','source_uri')
  ) then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: blind clustering surface leaks context/source identity';
  end if;
end
$$;

-- Cross-object physical edges must remain impossible.
do $$
declare
  blocked boolean := false;
  payload jsonb := jsonb_build_object(
    'witness',jsonb_build_object(
      'object_key','__mark_topology_validation_other_object__',
      'surface_key','__mark_topology_validation_other_surface__',
      'capture_key','__mark_topology_validation_other_capture__'
    ),
    'zone',jsonb_build_object(
      'region_key','__mark_topology_validation_other_zone_region__',
      'bbox',jsonb_build_object('x',0,'y',0,'width',100,'height',100),
      'zone_key','__mark_topology_validation_other_zone__',
      'flow_direction','network'
    ),
    'instances',jsonb_build_array(
      jsonb_build_object(
        'instance_key','__mark_topology_validation_other_i0__',
        'region_key','__mark_topology_validation_other_i0_region__',
        'bbox',jsonb_build_object('x',0,'y',0,'width',50,'height',50),
        'components',jsonb_build_array(
          jsonb_build_object(
            'component_key','__mark_topology_validation_other_component__',
            'region_key','__mark_topology_validation_other_component_region__',
            'bbox',jsonb_build_object('x',0,'y',0,'width',20,'height',20),
            'channel_key','solid_object'
          )
        )
      )
    )
  );
begin
  perform mark.ingest_physical_sequence_v1(payload);

  begin
    perform mark.ingest_physical_topology_edges_v1(jsonb_build_object(
      'relations',jsonb_build_array(
        jsonb_build_object(
          'relation_instance_key','__mark_topology_validation_cross_object_reject__',
          'subject_component_key','__mark_topology_validation_other_component__',
          'object_component_key','__mark_topology_validation_primary__',
          'relation_key','attached_to'
        )
      )
    ));
  exception when others then
    if position('MARK_TOPOLOGY_CROSS_OBJECT_RELATION' in sqlerrm) > 0 then
      blocked := true;
    else
      raise;
    end if;
  end;

  if not blocked then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: cross-object physical relation was accepted';
  end if;

  if exists (
    select 1 from mark.component_relations
    where relation_instance_key='__mark_topology_validation_cross_object_reject__'
  ) then
    raise exception 'MARK_GLOBAL_TOPOLOGY_POSTCONDITION: rejected cross-object relation left evidence';
  end if;
end
$$;
