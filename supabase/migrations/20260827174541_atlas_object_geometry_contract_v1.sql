-- Atlas object geometry contract v1
--
-- Irregular Atlas objects carry two distinct kinds of spatial truth:
--   1. reference geometry: a north-aware visual/topological shape in a named
--      diagram coordinate space; reference coordinates are never feet.
--   2. physical_model: optional measured construction facts in real units.
--
-- Main Garden polygons come from the existing north-up Zone Registry SVG and
-- were visually reconfirmed by the owner against the Main Garden clock-face
-- reference on 2026-08-27. Crescent Moon and Spiral keep their existing
-- measured physical models while gaining durable reference paths from the
-- existing Berry Walk Zone Registry SVG.

DO $$
DECLARE
  v_count integer;
BEGIN
  WITH shapes(stable_key, points) AS (
    VALUES
      ('mg1', '[[525,100],[930,100],[930,165],[650,410],[610,370],[525,320]]'::jsonb),
      ('mg2', '[[930,165],[930,425],[650,425],[620,395]]'::jsonb),
      ('mg4', '[[650,475],[930,475],[930,735],[620,505]]'::jsonb),
      ('mg5', '[[610,530],[650,490],[930,735],[930,800],[525,800],[525,580]]'::jsonb),
      ('mg7', '[[475,580],[475,800],[70,800],[70,735],[350,490],[390,530]]'::jsonb),
      ('mg8', '[[70,475],[350,475],[380,505],[70,735]]'::jsonb),
      ('mg10', '[[70,165],[380,395],[350,425],[70,425]]'::jsonb),
      ('mg11', '[[70,100],[475,100],[475,320],[390,370],[350,410],[70,165]]'::jsonb),
      ('mg_center_diamond', '[[500,330],[650,450],[500,570],[350,450]]'::jsonb),
      ('mg_12_walkway', '[[475,100],[525,100],[525,320],[475,320]]'::jsonb),
      ('mg_130_walkway', '[[620,385],[650,415],[930,170],[930,135]]'::jsonb),
      ('mg_3_walkway', '[[650,425],[930,425],[930,475],[650,475]]'::jsonb),
      ('mg_430_walkway', '[[620,515],[650,485],[905,800],[855,800]]'::jsonb),
      ('mg_6_walkway', '[[475,580],[525,580],[525,800],[475,800]]'::jsonb),
      ('mg_730_walkway', '[[350,485],[380,515],[145,800],[95,800]]'::jsonb),
      ('mg_9_walkway', '[[70,425],[350,425],[350,475],[70,475]]'::jsonb),
      ('mg_1030_walkway', '[[70,135],[70,170],[350,415],[380,385]]'::jsonb)
  )
  UPDATE atlas.growing_objects go
  SET
    geometry = jsonb_build_object(
      'schema', 'atlas_object_geometry_v1',
      'reference', jsonb_build_object(
        'kind', 'polygon',
        'coordinate_space', 'main_garden_clock_svg_v1',
        'view_box', jsonb_build_array(0, 0, 1000, 900),
        'points', shapes.points,
        'precision', 'reference_not_surveyed',
        'orientation', jsonb_build_object(
          'north', 'top',
          'south', 'bottom',
          'viewpoint', 'oak_tree_entrance'
        ),
        'source', jsonb_build_object(
          'kind', 'atlas_zone_registry_svg',
          'repository', 'optical-lift/farm-atlas',
          'path', 'app/zones/main-garden-map/page.tsx',
          'blob_sha', 'e029d17874a7363669524684fb13d64095ef0fda',
          'owner_visual_confirmation_date', '2026-08-27'
        )
      )
    ),
    metadata = coalesce(go.metadata, '{}'::jsonb) || jsonb_build_object(
      'geometry_status', 'canonical_reference',
      'geometry_schema', 'atlas_object_geometry_v1',
      'geometry_reference_coordinate_space', 'main_garden_clock_svg_v1',
      'geometry_reference_source_path', 'app/zones/main-garden-map/page.tsx',
      'geometry_reference_source_blob', 'e029d17874a7363669524684fb13d64095ef0fda',
      'geometry_reference_confirmed_at', '2026-08-27',
      'geometry_reference_precision', 'reference_not_surveyed'
    ),
    updated_at = now()
  FROM shapes, atlas.zones z
  WHERE z.stable_key = 'main_garden'
    AND go.zone_id = z.id
    AND go.stable_key = shapes.stable_key
    AND (go.geometry IS NULL OR go.geometry->>'schema' = 'atlas_object_geometry_v1');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 17 THEN
    RAISE EXCEPTION 'Expected 17 Main Garden geometry objects, updated %', v_count;
  END IF;
END
$$;

DO $$
DECLARE
  v_count integer;
BEGIN
  WITH shapes(stable_key, path_d, physical_model) AS (
    VALUES
      (
        'berry_walk_crescent_moon',
        'M92 500 C82 300 220 155 430 155 C590 155 675 300 625 480 C585 420 515 372 430 340 C310 300 205 350 92 500 Z',
        jsonb_build_object(
          'kind', 'semicircular_annulus',
          'units', 'ft',
          'outer_radius_ft', 25,
          'inner_radius_ft', 17,
          'maximum_width_ft', 8,
          'sweep_degrees', 180,
          'area_formula', '0.5*pi*(outer_radius_ft^2-inner_radius_ft^2)',
          'area_sqft', 527.787566,
          'measurement_source', 'user_report_20260711'
        )
      ),
      (
        'berry_walk_labyrinth_walk',
        'M355 655 C195 655 185 480 337 430 C490 380 590 520 505 607 C445 668 325 620 350 525 C370 448 462 458 474 522 C484 570 430 600 394 565',
        jsonb_build_object(
          'kind', 'archimedean_spiral_corridor',
          'units', 'ft',
          'turn_count', 3,
          'containing_radius_ft', 17,
          'path_width_ft', 2,
          'estimated_centerline_length_ft', 162.083598,
          'estimated_area_sqft', 324.167196,
          'measurement_source', 'user_report_20260711',
          'model_status', 'working_geometry_estimate'
        )
      )
  )
  UPDATE atlas.growing_objects go
  SET
    geometry = jsonb_build_object(
      'schema', 'atlas_object_geometry_v1',
      'reference', jsonb_build_object(
        'kind', 'path',
        'coordinate_space', 'berry_walk_svg_v1',
        'view_box', jsonb_build_array(0, 0, 720, 1340),
        'path_d', shapes.path_d,
        'precision', 'reference_not_surveyed',
        'orientation', jsonb_build_object('north', 'top', 'south', 'bottom'),
        'source', jsonb_build_object(
          'kind', 'atlas_zone_registry_svg',
          'repository', 'optical-lift/farm-atlas',
          'path', 'app/zones/berry-walk-map/page.tsx',
          'blob_sha', 'c55a536eafe7894cb5c52ba6c800262f0f751da2'
        )
      ),
      'physical_model', shapes.physical_model
    ),
    metadata = coalesce(go.metadata, '{}'::jsonb) || jsonb_build_object(
      'geometry_status', 'reference_plus_measured_model',
      'geometry_schema', 'atlas_object_geometry_v1',
      'geometry_reference_coordinate_space', 'berry_walk_svg_v1',
      'geometry_reference_source_path', 'app/zones/berry-walk-map/page.tsx',
      'geometry_reference_source_blob', 'c55a536eafe7894cb5c52ba6c800262f0f751da2',
      'geometry_reference_precision', 'reference_not_surveyed'
    ),
    updated_at = now()
  FROM shapes, atlas.zones z
  WHERE z.stable_key = 'original_berry_walk'
    AND go.zone_id = z.id
    AND go.stable_key = shapes.stable_key
    AND (go.geometry IS NULL OR go.geometry->>'schema' = 'atlas_object_geometry_v1');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Expected Crescent Moon and Spiral geometry objects, updated %', v_count;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION atlas.object_crop_bed_map_v1(p_object_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'atlas'
AS $function$
DECLARE
  v_object atlas.growing_objects%rowtype;
  v_frame atlas.object_map_frames%rowtype;
  v_role text;
  v_rows jsonb;
  v_geometry jsonb;
BEGIN
  SELECT * INTO v_object FROM atlas.growing_objects WHERE id = p_object_id;
  IF v_object.id IS NULL THEN
    RAISE EXCEPTION 'Growing object not found.' USING errcode = 'P0002';
  END IF;

  v_role := atlas.current_farm_role(v_object.farm_id);
  IF NOT atlas.is_farm_owner(v_object.farm_id)
     AND coalesce(v_role, '') NOT IN ('farm_hand', 'manager') THEN
    RAISE EXCEPTION 'Bed map is not available to the signed-in farm member.' USING errcode = '42501';
  END IF;

  SELECT * INTO v_frame FROM atlas.object_map_frames WHERE object_id = v_object.id;

  IF v_object.geometry->>'schema' = 'atlas_object_geometry_v1' THEN
    v_geometry := v_object.geometry;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'placementId', q.placement_id,
    'cropCycleId', q.crop_cycle_id,
    'displayLabel', q.display_label,
    'stage', q.stage,
    'stageLabel', atlas.crop_stage_label_v1(q.stage),
    'establishmentDate', q.establishment_date,
    'establishmentKind', q.establishment_kind,
    'lifeCycle', CASE WHEN q.is_perennial THEN 'perennial' ELSE coalesce(q.life_cycle, 'annual') END,
    'placementMode', q.placement_mode,
    'placementLabel', q.placement_label,
    'rowCount', q.row_count,
    'rowLengthFt', q.row_length_ft,
    'areaSqft', q.area_sqft,
    'explicitPlantCount', q.explicit_plant_count,
    'clumpCount', q.clump_count,
    'expectedQuantity', q.expected_quantity,
    'expectedQuantityKind', q.expected_quantity_kind,
    'observedQuantity', q.observed_quantity,
    'observedQuantityUnit', q.observed_quantity_unit,
    'standPercent', q.stand_percent,
    'anchorEdge', q.anchor_edge,
    'longStartFt', q.long_start_ft,
    'longEndFt', q.long_end_ft,
    'crossStartFt', q.cross_start_ft,
    'crossEndFt', q.cross_end_ft,
    'positionConfidence', q.position_confidence
  )) ORDER BY q.anchor_edge NULLS LAST, q.display_label, q.crop_cycle_id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT
      p.id placement_id,
      cc.id crop_cycle_id,
      CASE
        WHEN lower(cc.crop_label) = 'sunflower' AND nullif(btrim(coalesce(cc.variety, '')), '') IS NOT NULL
          THEN btrim(cc.variety) || ' sunflower'
        WHEN lower(cc.crop_label) IN ('bearded iris', 'iris') THEN 'Iris'
        ELSE cc.crop_label
      END display_label,
      coalesce(obs.stage, atlas.crop_stage_from_state_v1(cc.cycle_state, cp.life_cycle)) stage,
      coalesce(cc.planted_date, cc.sown_date) establishment_date,
      CASE WHEN cc.planted_date IS NOT NULL THEN 'planted' WHEN cc.sown_date IS NOT NULL THEN 'sown' ELSE NULL END establishment_kind,
      (
        lower(coalesce(cp.life_cycle, '')) = 'perennial'
        OR p.placement_mode IN ('edge_strip', 'clumps')
           AND lower(cc.crop_label) IN ('iris', 'bearded iris', 'lemon balm', 'yarrow', 'salvia')
      ) is_perennial,
      cp.life_cycle,
      p.placement_mode,
      p.placement_label,
      p.row_count,
      p.row_length_ft,
      p.area_sqft,
      p.explicit_plant_count,
      p.clump_count,
      p.expected_quantity,
      p.expected_quantity_kind,
      obs.observed_quantity,
      obs.quantity_unit observed_quantity_unit,
      obs.stand_percent,
      p.anchor_edge,
      p.long_start_ft,
      p.long_end_ft,
      p.cross_start_ft,
      p.cross_end_ft,
      p.position_confidence
    FROM atlas.crop_cycles cc
    LEFT JOIN atlas.crop_profiles cp ON cp.id = cc.crop_profile_id
    LEFT JOIN LATERAL (
      SELECT p0.*
      FROM atlas.crop_placements p0
      WHERE p0.crop_cycle_id = cc.id
      ORDER BY (p0.position_confidence = 'high') DESC,
               (p0.expected_quantity_kind = 'recorded') DESC,
               p0.created_at
      LIMIT 1
    ) p ON true
    LEFT JOIN LATERAL (
      SELECT o.stage, o.observed_quantity, o.quantity_unit, o.stand_percent
      FROM atlas.crop_observations o
      WHERE o.crop_cycle_id = cc.id
      ORDER BY o.observed_date DESC NULLS LAST, o.created_at DESC
      LIMIT 1
    ) obs ON true
    WHERE cc.object_id = p_object_id
      AND cc.lifecycle_status = 'active'
      AND coalesce(obs.stage, atlas.crop_stage_from_state_v1(cc.cycle_state, cp.life_cycle), 'unknown')
          NOT IN ('cleared', 'failed', 'dead', 'absent', 'abandoned', 'archived', 'removed', 'inactive')
  ) q;

  RETURN jsonb_build_object(
    'objectId', v_object.id,
    'objectKey', v_object.stable_key,
    'objectLabel', v_object.label,
    'lengthFt', v_object.length_ft,
    'widthFt', v_object.width_ft,
    'areaSqft', v_object.area_sqft,
    'geometry', v_geometry,
    'referenceGeometry', v_geometry->'reference',
    'orientationKnown', v_frame.object_id IS NOT NULL AND v_frame.long_axis <> 'unknown',
    'longAxis', coalesce(v_frame.long_axis, 'unknown'),
    'leftEdge', v_frame.left_edge,
    'rightEdge', v_frame.right_edge,
    'topEdge', v_frame.top_edge,
    'bottomEdge', v_frame.bottom_edge,
    'orientationSource', v_frame.orientation_source,
    'placements', coalesce(v_rows, '[]'::jsonb)
  );
END;
$function$;

COMMENT ON COLUMN atlas.growing_objects.geometry IS
  'Atlas object geometry. atlas_object_geometry_v1 separates diagram/reference geometry from optional measured physical_model facts; reference coordinate spaces must never be interpreted as feet unless explicitly declared in the physical model.';

COMMENT ON FUNCTION atlas.object_crop_bed_map_v1(uuid) IS
  'Returns measured dimensions, governed atlas_object_geometry_v1 reference/physical geometry when available, and active crop occupancy. Irregular reference shapes preserve topology without inventing crop placement coordinates or surveyed dimensions.';
