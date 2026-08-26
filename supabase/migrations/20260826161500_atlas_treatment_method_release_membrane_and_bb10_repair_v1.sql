-- Atlas treatment-method release membrane + BB10 repair v1
-- Owner instruction 2026-08-26:
--   * unknown execution-critical method/resource facts must never become worker-facing placeholders;
--   * treatment work must fail closed at authoring/release until its method packet is real;
--   * BB10 uses the black jug with electric sprayer attachment;
--   * refill is 2/3 cup concentrate to 1 gallon water;
--   * treatment is applied through foliage/leaf contact, not root treatment;
--   * product identity is intentionally not inferred.

DO $block$
DECLARE
  v_farm_id uuid := '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
  v_resource_id uuid;
  v_template_id uuid;
  v_task_count integer;
BEGIN
  INSERT INTO atlas.resources (
    id,
    farm_id,
    stable_key,
    label,
    resource_type,
    resource_category,
    status,
    quantity,
    unit,
    restock_needed,
    consumable,
    condition_notes,
    metadata
  )
  VALUES (
    gen_random_uuid(),
    v_farm_id,
    'black_jug_electric_sprayer',
    'Black jug with electric sprayer attachment',
    'equipment',
    'pest_control',
    'available',
    1,
    'sprayer',
    false,
    false,
    'Owner identified this as the canonical sprayer resource for the BB10 Bermuda-grass treatment on 2026-08-26.',
    jsonb_build_object(
      'source','owner_instruction_20260826',
      'resource_identity_scope','equipment_only',
      'product_identity_asserted',false
    )
  )
  ON CONFLICT (farm_id, stable_key) DO UPDATE
  SET label = EXCLUDED.label,
      resource_type = EXCLUDED.resource_type,
      resource_category = EXCLUDED.resource_category,
      status = EXCLUDED.status,
      quantity = EXCLUDED.quantity,
      unit = EXCLUDED.unit,
      restock_needed = EXCLUDED.restock_needed,
      consumable = EXCLUDED.consumable,
      condition_notes = EXCLUDED.condition_notes,
      metadata = coalesce(atlas.resources.metadata,'{}'::jsonb) || EXCLUDED.metadata,
      updated_at = now()
  RETURNING id INTO v_resource_id;

  INSERT INTO atlas.action_requirement_templates (
    id,
    farm_id,
    stable_key,
    action_type,
    label,
    applies_to_task_type,
    required_resource_keys,
    hard_parts,
    notes,
    metadata
  )
  VALUES (
    gen_random_uuid(),
    v_farm_id,
    'bb10_bermuda_spray_method_v1',
    'spray',
    'BB10 Bermuda grass spray method',
    'weed_control',
    ARRAY['black_jug_electric_sprayer']::text[],
    jsonb_build_array(
      'Use the black jug with electric sprayer attachment.',
      'Refill instructions: 2/3 cup concentrate to 1 gallon water.',
      'The treatment works through contact with the leaves, not the roots.'
    ),
    'Owner-confirmed BB10 treatment method. Product identity is intentionally not asserted or inferred.',
    jsonb_build_object(
      'source','owner_instruction_20260826',
      'method_contract_version','bb10_bermuda_spray_method_v1',
      'product_identity_status','unknown_not_asserted',
      'forbid_product_inference',true
    )
  )
  ON CONFLICT (farm_id, stable_key) DO UPDATE
  SET action_type = EXCLUDED.action_type,
      label = EXCLUDED.label,
      applies_to_task_type = EXCLUDED.applies_to_task_type,
      required_resource_keys = EXCLUDED.required_resource_keys,
      hard_parts = EXCLUDED.hard_parts,
      notes = EXCLUDED.notes,
      metadata = coalesce(atlas.action_requirement_templates.metadata,'{}'::jsonb) || EXCLUDED.metadata,
      updated_at = now()
  RETURNING id INTO v_template_id;

  SELECT count(*) INTO v_task_count
  FROM atlas.tasks
  WHERE id = ANY(ARRAY[
    '1405c7a2-270f-494a-8e1c-59884a8b4fc9'::uuid,
    '14bd6679-d764-4feb-a275-dbe96ddd03a0'::uuid,
    'd19b9a69-e2ee-4860-b768-a30f95e44414'::uuid
  ]);

  IF v_task_count <> 3 THEN
    RAISE EXCEPTION 'BB10 treatment-family repair expected 3 canonical tasks; found %.', v_task_count;
  END IF;

  -- Set the canonical resource key on the tasks first. The existing Atlas
  -- resource-key synchronizer owns creation of task_resource_requirements;
  -- do not create a competing requirement row here.
  UPDATE atlas.tasks
  SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'execution_how', jsonb_build_array(
          'Use the black jug with electric sprayer attachment.',
          'Refill instructions: 2/3 cup concentrate to 1 gallon water.',
          'The treatment works through contact with the leaves, not the roots.'
        ),
        'method_constraints', jsonb_build_array(
          'Refill instructions: 2/3 cup concentrate to 1 gallon water.',
          'The treatment works through contact with the leaves, not the roots.'
        ),
        'worker_method_required', true,
        'method_contract_key', 'bb10_bermuda_spray_method_v1',
        'action_requirement_template_key', 'bb10_bermuda_spray_method_v1',
        'method_resource_key', 'black_jug_electric_sprayer',
        'required_resource_keys', jsonb_build_array('black_jug_electric_sprayer'),
        'method_source', 'owner_instruction_20260826',
        'method_product_identity_status', 'unknown_not_asserted',
        'forbid_product_inference', true
      ),
      updated_at = now()
  WHERE id = ANY(ARRAY[
    '1405c7a2-270f-494a-8e1c-59884a8b4fc9'::uuid,
    '14bd6679-d764-4feb-a275-dbe96ddd03a0'::uuid,
    'd19b9a69-e2ee-4860-b768-a30f95e44414'::uuid
  ]);

  -- Attach the reusable method template to the single canonical requirement
  -- created by required_resource_keys. This preserves one resource authority.
  UPDATE atlas.task_resource_requirements trr
  SET template_id = v_template_id,
      requirement_source = 'template',
      quantity_needed = 1,
      unit = 'sprayer',
      note = 'Use the owner-confirmed black jug with electric sprayer attachment.',
      metadata = coalesce(trr.metadata,'{}'::jsonb) || jsonb_build_object(
        'source','owner_instruction_20260826',
        'method_contract_key','bb10_bermuda_spray_method_v1',
        'product_identity_asserted',false
      ),
      move_role = 'equipment',
      updated_at = now()
  WHERE trr.task_id = ANY(ARRAY[
    '1405c7a2-270f-494a-8e1c-59884a8b4fc9'::uuid,
    '14bd6679-d764-4feb-a275-dbe96ddd03a0'::uuid,
    'd19b9a69-e2ee-4860-b768-a30f95e44414'::uuid
  ])
    AND trr.resource_id = v_resource_id
    AND trr.requirement_role = 'required';

  SELECT count(*) INTO v_task_count
  FROM atlas.task_resource_requirements trr
  WHERE trr.task_id = ANY(ARRAY[
    '1405c7a2-270f-494a-8e1c-59884a8b4fc9'::uuid,
    '14bd6679-d764-4feb-a275-dbe96ddd03a0'::uuid,
    'd19b9a69-e2ee-4860-b768-a30f95e44414'::uuid
  ])
    AND trr.resource_id = v_resource_id
    AND trr.template_id = v_template_id
    AND trr.requirement_role = 'required';

  IF v_task_count <> 3 THEN
    RAISE EXCEPTION 'BB10 treatment-family repair expected 3 canonical method/resource requirements; found %.', v_task_count;
  END IF;
END
$block$;

CREATE OR REPLACE FUNCTION atlas.guard_worker_task_authoring_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'atlas'
AS $function$
DECLARE
  v_violations text[];
  v_packet jsonb;
  v_method_required boolean := false;
  v_execution_how_present boolean := false;
  v_method_contract_present boolean := false;
  v_method_resource_present boolean := false;
  v_worker_method_surface text := '';
BEGIN
  v_packet := coalesce(new.metadata,'{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object('operation_class',new.operation_class));

  v_violations := atlas.worker_task_authoring_violations_v1(
    new.title,
    v_packet,
    new.visibility_scope
  );

  -- Execution-critical treatment unknowns are not worker copy. They are an
  -- authoring stop: resolve the fact or return to Owner custody before release.
  IF new.visibility_scope = 'assigned_worker'
     AND coalesce(new.status,'open') NOT IN ('done','archived','cancelled') THEN
    v_method_required := lower(coalesce(new.operation_class,'')) = 'apply_treatment'
      OR lower(coalesce(new.metadata->>'worker_method_required','false')) = 'true';

    IF v_method_required THEN
      v_execution_how_present := CASE jsonb_typeof(new.metadata->'execution_how')
        WHEN 'array' THEN jsonb_array_length(new.metadata->'execution_how') > 0
        WHEN 'string' THEN btrim(coalesce(new.metadata->>'execution_how','')) <> ''
        ELSE false
      END;

      v_method_contract_present := btrim(coalesce(
        new.metadata->>'method_contract_key',
        new.metadata->>'action_requirement_template_key',
        ''
      )) <> '';

      v_method_resource_present :=
        (jsonb_typeof(new.metadata->'required_resource_keys') = 'array'
         AND jsonb_array_length(new.metadata->'required_resource_keys') > 0)
        OR btrim(coalesce(new.metadata->>'method_resource_key','')) <> '';

      v_worker_method_surface := lower(concat_ws(' ',
        coalesce(new.metadata->>'execution_how',''),
        coalesce(new.metadata->>'method_constraints',''),
        coalesce(new.metadata->>'display_detail','')
      ));

      IF NOT v_execution_how_present THEN
        v_violations := array_append(v_violations,'missing_required_method_instructions');
      END IF;
      IF NOT v_method_contract_present THEN
        v_violations := array_append(v_violations,'missing_required_method_contract');
      END IF;
      IF NOT v_method_resource_present THEN
        v_violations := array_append(v_violations,'missing_required_method_resource');
      END IF;
      IF v_worker_method_surface ~ 'method resource not attached|do not infer product|owner must define|to be determined|(^|[^a-z])tbd([^a-z]|$)' THEN
        v_violations := array_append(v_violations,'unresolved_required_method_placeholder');
      END IF;
    END IF;
  END IF;

  IF coalesce(array_length(v_violations,1),0) > 0 THEN
    RAISE EXCEPTION 'Worker task execution contract rejected: %. Resolve required execution facts or route the unknown back to Owner; worker-facing placeholders are forbidden.',
      array_to_string(v_violations,', ')
      USING errcode='23514';
  END IF;

  RETURN new;
END;
$function$;

REVOKE ALL ON FUNCTION atlas.guard_worker_task_authoring_v1() FROM PUBLIC;

-- Negative control: the authoring membrane itself must reject an unresolved
-- treatment packet. Catch the expected constraint error so the migration can
-- continue while proving the membrane is live.
DO $test$
DECLARE
  v_existing atlas.tasks%rowtype;
  v_rejected boolean := false;
BEGIN
  SELECT * INTO v_existing
  FROM atlas.tasks
  WHERE id = '53590d76-5e63-4c3a-9c58-724639f81067'::uuid;

  IF v_existing.id IS NULL THEN
    RAISE EXCEPTION 'Treatment-method negative-control task is missing.';
  END IF;

  BEGIN
    UPDATE atlas.tasks
    SET visibility_scope='assigned_worker',
        status='open',
        assigned_membership_id='23e98e5e-16ca-40d8-872c-c77e06baa167'::uuid,
        assigned_user_id='21436a28-40fd-4914-8015-a248d0dca14e'::uuid,
        updated_at=now()
    WHERE id=v_existing.id;
  EXCEPTION
    WHEN check_violation THEN
      v_rejected := true;
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Treatment-method release membrane negative control failed: unresolved treatment reached assigned_worker.';
  END IF;
END
$test$;

-- Positive control: all currently nonterminal assigned-worker treatment tasks
-- must now carry a real method contract and resource key.
DO $test$
DECLARE
  v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM atlas.tasks t
  WHERE t.visibility_scope='assigned_worker'
    AND t.status NOT IN ('done','archived','cancelled')
    AND lower(coalesce(t.operation_class,''))='apply_treatment'
    AND (
      coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(t.metadata->'execution_how')='array' THEN t.metadata->'execution_how' ELSE '[]'::jsonb END),0)=0
      OR btrim(coalesce(t.metadata->>'action_requirement_template_key',t.metadata->>'method_contract_key',''))=''
      OR coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(t.metadata->'required_resource_keys')='array' THEN t.metadata->'required_resource_keys' ELSE '[]'::jsonb END),0)=0
    );

  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'Treatment-method release membrane positive control failed: % assigned-worker treatment task(s) remain incomplete.', v_bad;
  END IF;
END
$test$;
