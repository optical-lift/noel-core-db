-- Atlas worker unresolved-execution-fact release membrane v1
-- Generalizes the treatment-specific fail-closed rule to every worker-facing task.
-- Unknown execution truth stays in Owner/truth-acquisition custody; it is never worker copy.

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
  v_worker_surface text := '';
BEGIN
  v_packet := coalesce(new.metadata,'{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object('operation_class',new.operation_class));

  v_violations := atlas.worker_task_authoring_violations_v1(
    new.title,
    v_packet,
    new.visibility_scope
  );

  IF new.visibility_scope = 'assigned_worker'
     AND coalesce(new.status,'open') NOT IN ('done','archived','cancelled') THEN
    -- Generic epistemic membrane: explicit unresolved-truth custody can never
    -- cross into worker execution, regardless of task family.
    IF lower(coalesce(new.metadata->>'owner_definition_required','false')) = 'true'
       OR lower(coalesce(new.metadata->>'worker_packet_hold','false')) = 'true'
       OR lower(coalesce(new.metadata->>'truth_acquisition_required','false')) = 'true' THEN
      v_violations := array_append(v_violations,'unresolved_execution_truth_hold');
    END IF;

    v_worker_surface := lower(concat_ws(' ',
      coalesce(new.title,''),
      coalesce(new.note,''),
      coalesce(new.blocker_text,''),
      coalesce(new.metadata->>'execution_do',''),
      coalesce(new.metadata->>'execution_how',''),
      coalesce(new.metadata->>'execution_done_when',''),
      coalesce(new.metadata->>'display_detail',''),
      coalesce(new.metadata->>'method_constraints','')
    ));

    IF v_worker_surface ~ 'method resource not attached|do not infer product|owner must define|to be determined|(^|[^a-z])tbd([^a-z]|$)' THEN
      v_violations := array_append(v_violations,'unresolved_execution_placeholder');
    END IF;

    -- Treatment work has an additional complete-method packet contract.
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

      IF NOT v_execution_how_present THEN
        v_violations := array_append(v_violations,'missing_required_method_instructions');
      END IF;
      IF NOT v_method_contract_present THEN
        v_violations := array_append(v_violations,'missing_required_method_contract');
      END IF;
      IF NOT v_method_resource_present THEN
        v_violations := array_append(v_violations,'missing_required_method_resource');
      END IF;
    END IF;
  END IF;

  IF coalesce(array_length(v_violations,1),0) > 0 THEN
    RAISE EXCEPTION 'Worker task execution contract rejected: %. Resolve required execution facts or route the unknown back to Owner/truth acquisition; worker-facing placeholders are forbidden.',
      array_to_string(v_violations,', ')
      USING errcode='23514';
  END IF;

  RETURN new;
END;
$function$;

REVOKE ALL ON FUNCTION atlas.guard_worker_task_authoring_v1() FROM PUBLIC;

DO $test$
DECLARE
  v_rejected boolean := false;
BEGIN
  BEGIN
    UPDATE atlas.tasks
    SET visibility_scope='assigned_worker',
        status='open',
        assigned_membership_id='23e98e5e-16ca-40d8-872c-c77e06baa167'::uuid,
        assigned_user_id='21436a28-40fd-4914-8015-a248d0dca14e'::uuid,
        updated_at=now()
    WHERE id='53590d76-5e63-4c3a-9c58-724639f81067'::uuid;
  EXCEPTION
    WHEN check_violation THEN
      v_rejected := true;
  END;

  IF NOT v_rejected THEN
    RAISE EXCEPTION 'General worker unresolved-fact membrane negative control failed.';
  END IF;
END
$test$;

DO $test$
DECLARE
  v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM atlas.tasks t
  WHERE t.visibility_scope='assigned_worker'
    AND t.status NOT IN ('done','archived','cancelled')
    AND (
      lower(coalesce(t.metadata->>'owner_definition_required','false'))='true'
      OR lower(coalesce(t.metadata->>'worker_packet_hold','false'))='true'
      OR lower(coalesce(t.metadata->>'truth_acquisition_required','false'))='true'
      OR lower(concat_ws(' ',
        t.title,
        t.note,
        t.blocker_text,
        t.metadata->>'execution_do',
        t.metadata->>'execution_how',
        t.metadata->>'execution_done_when',
        t.metadata->>'display_detail',
        t.metadata->>'method_constraints'
      )) ~ 'method resource not attached|do not infer product|owner must define|to be determined|(^|[^a-z])tbd([^a-z]|$)'
    );

  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'General worker unresolved-fact membrane positive control failed: % unresolved worker task(s).', v_bad;
  END IF;
END
$test$;
