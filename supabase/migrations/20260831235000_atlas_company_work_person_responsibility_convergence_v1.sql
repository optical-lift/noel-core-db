-- Atlas Company Work person-responsibility convergence v1
--
-- Governing boundary:
--   Company Work is durable organization truth.
--   Allocation is durable responsibility truth.
--   Readiness, planning, capacity, Clock placement, and execution leases may
--   organize attention/action, but may not suppress an unfinished allocation.
--
-- Transitional boundary:
--   Legacy atlas.tasks still author some real worker responsibilities. Until
--   those domain writers move Company Work-first, an explicit top-level
--   assigned_worker task is adopted transactionally into Company Work and the
--   task becomes an execution adapter. Internal/child rows are never adopted.

BEGIN;

CREATE OR REPLACE FUNCTION atlas.sync_explicit_worker_task_company_work_v1(
  p_task_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, atlas, auth
AS $function$
DECLARE
  v_task atlas.tasks%rowtype;
  v_farm atlas.farms%rowtype;
  v_farm_assignee_user_id uuid;
  v_assignee_user_id uuid;
  v_assignee_membership_id uuid;
  v_requirement atlas.work_requirements%rowtype;
  v_work atlas.work_items%rowtype;
  v_existing_work atlas.work_items%rowtype;
  v_existing_allocation atlas.work_allocations%rowtype;
  v_requirement_key text;
  v_work_key text;
  v_timezone text := 'America/Chicago';
  v_due_target timestamptz;
  v_existing_time_id uuid;
  v_is_top_level boolean := false;
  v_is_worker_responsibility boolean := false;
BEGIN
  SELECT * INTO v_task
  FROM atlas.tasks
  WHERE id = p_task_id;

  IF v_task.id IS NULL THEN
    RETURN jsonb_build_object('state','missing_task','taskId',p_task_id);
  END IF;

  v_work_key := 'legacy_task_adoption:' || v_task.id::text;
  v_requirement_key := v_work_key || ':requirement';

  SELECT * INTO v_existing_work
  FROM atlas.work_items
  WHERE organization_id = v_task.organization_id
    AND stable_key = v_work_key
  LIMIT 1;

  -- A completed execution carrier is valid completion evidence for work that
  -- was already adopted. It does not cause historical completed tasks to be
  -- backfilled as new Company Work.
  IF v_task.status = 'done' THEN
    IF v_existing_work.id IS NULL THEN
      RETURN jsonb_build_object('state','completed_not_adopted','taskId',v_task.id);
    END IF;

    UPDATE atlas.work_items
    SET work_state = 'completed',
        completed_at = coalesce(v_task.completed_at, now()),
        updated_at = now(),
        metadata = metadata || jsonb_build_object(
          'completionEvidenceKind','legacy_task_completion',
          'completionTaskId',v_task.id
        )
    WHERE id = v_existing_work.id
      AND work_state = 'open'
    RETURNING * INTO v_work;

    IF v_work.id IS NULL THEN
      v_work := v_existing_work;
    END IF;

    UPDATE atlas.work_requirements r
    SET state = 'satisfied',
        satisfied_at = coalesce(v_task.completed_at, now()),
        updated_at = now(),
        metadata = r.metadata || jsonb_build_object(
          'satisfactionEvidenceKind','legacy_task_completion',
          'completionTaskId',v_task.id
        )
    FROM atlas.work_requirement_links l
    WHERE l.work_item_id = v_existing_work.id
      AND l.requirement_id = r.id
      AND l.active
      AND r.state = 'active';

    UPDATE atlas.work_allocations
    SET state = 'completed',
        completed_at = coalesce(v_task.completed_at, now()),
        updated_at = now()
    WHERE work_item_id = v_existing_work.id
      AND state = 'active';

    UPDATE atlas.work_time_contracts
    SET contract_state = 'satisfied',
        updated_at = now()
    WHERE work_item_id = v_existing_work.id
      AND contract_state = 'active';

    UPDATE atlas.work_execution_adapters
    SET state = 'completed',
        completed_at = coalesce(v_task.completed_at, now()),
        updated_at = now(),
        metadata = metadata || jsonb_build_object('completionTaskId',v_task.id)
    WHERE task_id = v_task.id
      AND state = 'active';

    RETURN jsonb_build_object(
      'state','completed',
      'taskId',v_task.id,
      'workItemId',v_existing_work.id
    );
  END IF;

  IF v_task.farm_id IS NOT NULL THEN
    SELECT * INTO v_farm
    FROM atlas.farms
    WHERE id = v_task.farm_id;
  END IF;

  v_is_top_level := v_task.parent_task_id IS NULL
    AND coalesce(nullif(btrim(v_task.metadata->>'parent_task_id'),''),'') = '';

  IF v_task.assigned_membership_id IS NOT NULL THEN
    SELECT fm.user_id INTO v_farm_assignee_user_id
    FROM atlas.farm_memberships fm
    WHERE fm.id = v_task.assigned_membership_id
      AND fm.active;
  END IF;

  IF v_task.assigned_user_id IS NOT NULL
     AND v_farm_assignee_user_id IS NOT NULL
     AND v_task.assigned_user_id <> v_farm_assignee_user_id THEN
    RAISE EXCEPTION 'Task % carries conflicting explicit assignee identities.', v_task.id
      USING errcode = '23514';
  END IF;

  v_assignee_user_id := coalesce(v_task.assigned_user_id, v_farm_assignee_user_id);

  v_is_worker_responsibility :=
    v_task.organization_id IS NOT NULL
    AND v_task.status IN ('open','blocked')
    AND v_task.visibility_scope = 'assigned_worker'
    AND v_is_top_level
    AND v_assignee_user_id IS NOT NULL;

  -- If a previously adopted carrier stops declaring worker responsibility,
  -- release the person but preserve the organization's unfinished work.
  IF NOT v_is_worker_responsibility THEN
    IF v_existing_work.id IS NOT NULL AND v_existing_work.work_state = 'open' THEN
      UPDATE atlas.work_allocations
      SET state = 'released',
          released_at = now(),
          release_reason = 'legacy_execution_carrier_no_longer_declares_responsibility',
          updated_at = now()
      WHERE work_item_id = v_existing_work.id
        AND state = 'active';

      UPDATE atlas.work_execution_adapters
      SET state = 'retired',
          retired_at = now(),
          updated_at = now(),
          metadata = metadata || jsonb_build_object(
            'retirementReason','carrier_no_longer_declares_worker_responsibility'
          )
      WHERE task_id = v_task.id
        AND state = 'active';
    END IF;

    RETURN jsonb_build_object(
      'state','not_worker_responsibility',
      'taskId',v_task.id,
      'preservedWorkItemId',v_existing_work.id
    );
  END IF;

  IF v_farm.id IS NULL
     OR v_farm.organization_id IS NULL
     OR v_farm.organization_id <> v_task.organization_id
     OR v_farm.organization_unit_id IS NULL THEN
    RAISE EXCEPTION 'Task % cannot be adopted without matching farm organization/unit custody.', v_task.id
      USING errcode = '23514';
  END IF;

  SELECT om.id INTO v_assignee_membership_id
  FROM atlas.organization_memberships om
  WHERE om.organization_id = v_task.organization_id
    AND om.user_id = v_assignee_user_id
    AND om.active
  ORDER BY om.created_at
  LIMIT 1;

  IF v_assignee_membership_id IS NULL THEN
    RAISE EXCEPTION 'Task % assignee has no active organization membership.', v_task.id
      USING errcode = '23514';
  END IF;

  v_timezone := coalesce(nullif(v_farm.metadata->>'timezone',''),'America/Chicago');
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone) THEN
    v_timezone := 'America/Chicago';
  END IF;

  IF v_task.due_date IS NOT NULL THEN
    v_due_target := ((v_task.due_date + 1)::timestamp AT TIME ZONE v_timezone);
  ELSE
    v_due_target := NULL;
  END IF;

  INSERT INTO atlas.work_requirements (
    organization_id,
    organization_unit_id,
    stable_key,
    requirement_kind,
    summary,
    source_object_type,
    source_object_id,
    state,
    established_at,
    requirement_began_at,
    earliest_relevant_at,
    latest_satisfactory_at,
    consequence_of_delay,
    jurisdiction_key,
    metadata
  ) VALUES (
    v_task.organization_id,
    v_farm.organization_unit_id,
    v_requirement_key,
    'operational',
    v_task.title,
    'legacy_task',
    v_task.id,
    'active',
    coalesce(v_task.released_at,v_task.created_at,now()),
    coalesce(v_task.released_at,v_task.created_at,now()),
    coalesce(v_task.released_at,v_task.created_at,now()),
    v_due_target,
    '{}'::jsonb,
    coalesce(nullif(v_task.task_scope,''),'operations'),
    jsonb_build_object(
      'adoptedFromLegacyTask',true,
      'legacyTaskId',v_task.id,
      'legacyFarmId',v_task.farm_id,
      'dueDateIsTargetNotHardLaw',true,
      'readinessMayNotSuppressRequirement',true
    )
  )
  ON CONFLICT (organization_id, stable_key) WHERE stable_key IS NOT NULL
  DO UPDATE SET
    organization_unit_id = excluded.organization_unit_id,
    summary = excluded.summary,
    latest_satisfactory_at = excluded.latest_satisfactory_at,
    metadata = atlas.work_requirements.metadata || excluded.metadata,
    updated_at = now()
  RETURNING * INTO v_requirement;

  INSERT INTO atlas.work_items (
    organization_id,
    organization_unit_id,
    stable_key,
    title,
    instructions,
    work_state,
    operation_class,
    jurisdiction_key,
    source_object_type,
    source_object_id,
    result_contract_key,
    metadata
  ) VALUES (
    v_task.organization_id,
    v_farm.organization_unit_id,
    v_work_key,
    v_task.title,
    coalesce(nullif(btrim(v_task.note),''),nullif(btrim(v_task.unlock_text),'')),
    'open',
    coalesce(nullif(v_task.operation_class,''),nullif(v_task.task_type,''),'task'),
    coalesce(nullif(v_task.task_scope,''),'operations'),
    'legacy_task',
    v_task.id,
    nullif(v_task.metadata->>'result_contract_key',''),
    jsonb_build_object(
      'adoptedFromLegacyTask',true,
      'legacyTaskId',v_task.id,
      'legacyTaskType',v_task.task_type,
      'legacyFarmId',v_task.farm_id,
      'legacyCarrierIsAuthority',false,
      'companyWorkIsResponsibilityAuthority',true
    )
  )
  ON CONFLICT (organization_id, stable_key) WHERE stable_key IS NOT NULL
  DO UPDATE SET
    organization_unit_id = excluded.organization_unit_id,
    title = excluded.title,
    instructions = excluded.instructions,
    operation_class = excluded.operation_class,
    jurisdiction_key = excluded.jurisdiction_key,
    metadata = atlas.work_items.metadata || excluded.metadata,
    updated_at = now()
  RETURNING * INTO v_work;

  INSERT INTO atlas.work_requirement_links (
    organization_id, requirement_id, work_item_id, link_role, active, metadata
  ) VALUES (
    v_task.organization_id,v_requirement.id,v_work.id,'resolves',true,
    jsonb_build_object('source','explicit_worker_task_company_work_adoption_v1')
  )
  ON CONFLICT (requirement_id, work_item_id, link_role)
  DO UPDATE SET active = true,
                metadata = atlas.work_requirement_links.metadata || excluded.metadata;

  INSERT INTO atlas.work_execution_adapters (
    organization_id,organization_unit_id,work_item_id,adapter_kind,task_id,state,metadata
  ) VALUES (
    v_task.organization_id,v_farm.organization_unit_id,v_work.id,'legacy_task',v_task.id,'active',
    jsonb_build_object(
      'transitional',true,
      'responsibilityAuthority','company_work',
      'executionCarrierAuthorityOnly',true
    )
  )
  ON CONFLICT (task_id) WHERE task_id IS NOT NULL
  DO UPDATE SET
    organization_id = excluded.organization_id,
    organization_unit_id = excluded.organization_unit_id,
    work_item_id = excluded.work_item_id,
    adapter_kind = excluded.adapter_kind,
    state = 'active',
    retired_at = NULL,
    completed_at = NULL,
    metadata = atlas.work_execution_adapters.metadata || excluded.metadata,
    updated_at = now();

  SELECT * INTO v_existing_allocation
  FROM atlas.work_allocations
  WHERE work_item_id = v_work.id
    AND state = 'active'
    AND allocation_role = 'responsible'
  LIMIT 1;

  IF v_existing_allocation.id IS NOT NULL
     AND v_existing_allocation.assignee_membership_id <> v_assignee_membership_id THEN
    UPDATE atlas.work_allocations
    SET state = 'released',
        released_at = now(),
        release_reason = 'legacy_task_explicit_reassignment',
        updated_at = now()
    WHERE id = v_existing_allocation.id;
    v_existing_allocation.id := NULL;
  END IF;

  IF v_existing_allocation.id IS NULL THEN
    INSERT INTO atlas.work_allocations (
      organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
      allocation_role,state,allocated_at,metadata
    ) VALUES (
      v_task.organization_id,v_work.id,v_assignee_membership_id,NULL,
      'responsible','active',coalesce(v_task.released_at,v_task.created_at,now()),
      jsonb_build_object(
        'source','explicit_worker_task_company_work_adoption_v1',
        'legacyTaskId',v_task.id,
        'assignerNotInferred',true
      )
    );
  END IF;

  SELECT wt.id INTO v_existing_time_id
  FROM atlas.work_time_contracts wt
  WHERE wt.work_item_id = v_work.id
    AND wt.contract_state = 'active'
  ORDER BY wt.created_at DESC
  LIMIT 1;

  IF v_due_target IS NULL THEN
    IF v_existing_time_id IS NOT NULL THEN
      UPDATE atlas.work_time_contracts
      SET contract_state='superseded',superseded_at=now(),updated_at=now(),
          metadata=metadata || jsonb_build_object('reason','legacy_task_due_target_removed')
      WHERE id=v_existing_time_id;
    END IF;
  ELSIF v_existing_time_id IS NULL THEN
    INSERT INTO atlas.work_time_contracts (
      organization_id,work_item_id,contract_state,preferred_end_at,movement_policy,
      source_kind,source_id,source_confidence,metadata
    ) VALUES (
      v_task.organization_id,v_work.id,'active',v_due_target,'movable',
      'legacy_task',v_task.id,1,
      jsonb_build_object(
        'dueDate',v_task.due_date,
        'dueDateIsTargetNotHardLaw',true,
        'timezone',v_timezone
      )
    );
  ELSE
    UPDATE atlas.work_time_contracts
    SET preferred_end_at=v_due_target,
        movement_policy='movable',
        source_kind='legacy_task',
        source_id=v_task.id,
        source_confidence=1,
        metadata=metadata || jsonb_build_object(
          'dueDate',v_task.due_date,
          'dueDateIsTargetNotHardLaw',true,
          'timezone',v_timezone
        ),
        updated_at=now()
    WHERE id=v_existing_time_id;
  END IF;

  RETURN jsonb_build_object(
    'state','adopted',
    'taskId',v_task.id,
    'workItemId',v_work.id,
    'requirementId',v_requirement.id,
    'assigneeOrganizationMembershipId',v_assignee_membership_id,
    'dueTarget',v_due_target,
    'trustBoundary',jsonb_build_object(
      'companyWorkIsDurableTruth',true,
      'allocationIsResponsibilityTruth',true,
      'taskIsExecutionAdapter',true,
      'readinessCannotEraseWork',true,
      'plannerCannotEraseWork',true,
      'leaseCannotEraseWork',true
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION atlas.sync_explicit_worker_task_company_work_v1(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION atlas.sync_explicit_worker_task_company_work_v1(uuid) TO service_role;

CREATE OR REPLACE FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, atlas, auth
AS $function$
BEGIN
  PERFORM atlas.sync_explicit_worker_task_company_work_v1(NEW.id);
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v1() TO service_role;

DROP TRIGGER IF EXISTS tasks_company_work_responsibility_adoption_v1 ON atlas.tasks;
CREATE TRIGGER tasks_company_work_responsibility_adoption_v1
AFTER INSERT OR UPDATE OF status, visibility_scope, assigned_membership_id, assigned_user_id,
  parent_task_id, due_date, title, note, unlock_text, operation_class, task_type, task_scope
ON atlas.tasks
FOR EACH ROW
EXECUTE FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v1();

COMMENT ON TRIGGER tasks_company_work_responsibility_adoption_v1 ON atlas.tasks IS
  'Transitional adoption membrane only. Explicit top-level assigned_worker legacy tasks become durable Company Work immediately; internal/child rows do not. Company Work remains after carrier retirement.';

-- One-time adoption of the real unfinished human-responsibility rows that were
-- previously stranded in the legacy task system. No system_internal or child
-- task is eligible.
DO $backfill$
DECLARE
  v_task_id uuid;
BEGIN
  FOR v_task_id IN
    SELECT t.id
    FROM atlas.tasks t
    WHERE t.status IN ('open','blocked')
      AND t.visibility_scope='assigned_worker'
      AND t.parent_task_id IS NULL
      AND coalesce(nullif(btrim(t.metadata->>'parent_task_id'),''),'')=''
      AND t.organization_id IS NOT NULL
      AND (t.assigned_membership_id IS NOT NULL OR t.assigned_user_id IS NOT NULL)
    ORDER BY t.created_at,t.id
  LOOP
    PERFORM atlas.sync_explicit_worker_task_company_work_v1(v_task_id);
  END LOOP;
END;
$backfill$;

CREATE OR REPLACE FUNCTION atlas.company_work_self_responsibilities_api_v1()
RETURNS TABLE(
  organization_id uuid,
  organization_name text,
  organization_unit_id uuid,
  organization_unit_key text,
  organization_unit_name text,
  work_item_id uuid,
  allocation_id uuid,
  title text,
  instructions text,
  work_state text,
  operation_class text,
  allocation_role text,
  allocated_at timestamptz,
  requirements jsonb,
  next_target_at timestamptz,
  execution_state text,
  execution_reason text,
  legacy_task_id uuid,
  legacy_task_status text,
  legacy_task_due_date date,
  attention_lease_id uuid,
  attention_lease_state text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, atlas, auth
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING errcode='42501';
  END IF;

  RETURN QUERY
  WITH memberships AS MATERIALIZED (
    SELECT om.id,om.organization_id
    FROM atlas.organization_memberships om
    WHERE om.user_id=auth.uid()
      AND om.active
  ), base AS MATERIALIZED (
    SELECT
      wi.organization_id,
      o.name AS organization_name,
      wi.organization_unit_id,
      ou.stable_key AS organization_unit_key,
      ou.name AS organization_unit_name,
      wi.id AS work_item_id,
      wa.id AS allocation_id,
      wi.title,
      wi.instructions,
      wi.work_state,
      wi.operation_class,
      wa.allocation_role,
      wa.allocated_at,
      wea.task_id AS legacy_task_id,
      t.status AS legacy_task_status,
      t.due_date AS legacy_task_due_date,
      t.blocker_text,
      CASE WHEN t.id IS NULL THEN NULL ELSE atlas.task_execution_readiness_v1(t.id) END AS readiness,
      CASE WHEN t.id IS NULL THEN NULL ELSE atlas.task_operation_fit_warrant_v1(t.id) END AS operation_fit
    FROM memberships m
    JOIN atlas.work_allocations wa
      ON wa.organization_id=m.organization_id
     AND wa.assignee_membership_id=m.id
     AND wa.state='active'
     AND wa.allocation_role='responsible'
    JOIN atlas.work_items wi
      ON wi.organization_id=wa.organization_id
     AND wi.id=wa.work_item_id
     AND wi.work_state='open'
    JOIN atlas.organizations o ON o.id=wi.organization_id
    LEFT JOIN atlas.organization_units ou
      ON ou.organization_id=wi.organization_id
     AND ou.id=wi.organization_unit_id
    LEFT JOIN LATERAL (
      SELECT a.task_id
      FROM atlas.work_execution_adapters a
      WHERE a.organization_id=wi.organization_id
        AND a.work_item_id=wi.id
        AND a.state='active'
        AND a.task_id IS NOT NULL
      ORDER BY a.created_at DESC
      LIMIT 1
    ) wea ON true
    LEFT JOIN atlas.tasks t ON t.id=wea.task_id
  )
  SELECT
    b.organization_id,
    b.organization_name,
    b.organization_unit_id,
    b.organization_unit_key,
    b.organization_unit_name,
    b.work_item_id,
    b.allocation_id,
    b.title,
    b.instructions,
    b.work_state,
    b.operation_class,
    b.allocation_role,
    b.allocated_at,
    coalesce(req.requirements,'[]'::jsonb),
    req.next_target_at,
    CASE
      WHEN b.legacy_task_id IS NULL THEN 'unassessed'
      WHEN b.legacy_task_status='blocked' THEN 'waiting'
      WHEN NOT coalesce((b.readiness->>'executionReady')::boolean,false) THEN 'waiting'
      WHEN NOT coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 'needs_resolution'
      ELSE 'ready'
    END AS execution_state,
    CASE
      WHEN b.legacy_task_id IS NULL THEN NULL
      WHEN b.legacy_task_status='blocked' THEN coalesce(nullif(btrim(b.blocker_text),''),'task_blocked')
      WHEN NOT coalesce((b.readiness->>'executionReady')::boolean,false) THEN 'execution_requirements_not_ready'
      WHEN NOT coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 'operation_identity_unresolved'
      ELSE NULL
    END AS execution_reason,
    b.legacy_task_id,
    b.legacy_task_status,
    b.legacy_task_due_date,
    focus.lease_id,
    focus.lease_state
  FROM base b
  LEFT JOIN LATERAL (
    SELECT
      jsonb_agg(jsonb_build_object(
        'requirementId',r.id,
        'summary',r.summary,
        'state',r.state,
        'earliestRelevantAt',r.earliest_relevant_at,
        'latestSatisfactoryAt',r.latest_satisfactory_at,
        'consequenceOfDelay',r.consequence_of_delay
      ) ORDER BY r.latest_satisfactory_at NULLS LAST,r.created_at,r.id) AS requirements,
      min(r.latest_satisfactory_at) FILTER (WHERE r.state='active') AS next_target_at
    FROM atlas.work_requirement_links l
    JOIN atlas.work_requirements r
      ON r.organization_id=l.organization_id
     AND r.id=l.requirement_id
    WHERE l.organization_id=b.organization_id
      AND l.work_item_id=b.work_item_id
      AND l.active
      AND r.state='active'
  ) req ON true
  LEFT JOIN LATERAL (
    SELECT el.id AS lease_id,
           atlas.execution_lease_current_state_v1(el.id) AS lease_state
    FROM atlas.execution_leases el
    WHERE el.organization_id=b.organization_id
      AND el.shadow_only=false
      AND el.execution_kind='task'
      AND el.execution_id=b.legacy_task_id
      AND atlas.execution_lease_current_state_v1(el.id) IN ('leased','started','interrupted')
    ORDER BY el.created_at DESC
    LIMIT 1
  ) focus ON true
  ORDER BY
    CASE
      WHEN focus.lease_id IS NOT NULL THEN 0
      WHEN b.legacy_task_status='blocked' THEN 3
      WHEN b.legacy_task_id IS NOT NULL
       AND coalesce((b.readiness->>'executionReady')::boolean,false)
       AND coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 1
      ELSE 2
    END,
    req.next_target_at NULLS LAST,
    b.allocated_at,
    b.work_item_id;
END;
$function$;

COMMENT ON FUNCTION atlas.company_work_self_responsibilities_api_v1() IS
  'Signed-in person view of every active responsible Company Work allocation across organizations. Readiness, planning, capacity, Clock placement, and execution leases annotate/order responsibility but never filter it out.';

REVOKE ALL ON FUNCTION atlas.company_work_self_responsibilities_api_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION atlas.company_work_self_responsibilities_api_v1() TO authenticated, service_role;

INSERT INTO atlas.authenticated_rpc_registry (
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at,anonymous_execute_expected
) VALUES (
  'atlas.company_work_self_responsibilities_api_v1()',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_company_work_person_responsibility_convergence_v1',
    'reason','Expose only the signed-in person''s active responsible Company Work allocations across organizations.',
    'authorization','auth.uid() must resolve to the active organization membership that owns each returned allocation.',
    'truthBoundary','Responsibility is allocation truth. Readiness/planning/capacity/Clock/leases annotate but cannot suppress unfinished allocated work.',
    'classificationRuleVersion',3
  ),
  now(),NULL,false
)
ON CONFLICT (signature) DO UPDATE SET
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  registered_at=excluded.registered_at,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

-- The adoption itself must have produced only human-declared top-level work.
DO $proof$
DECLARE
  v_bad_count integer;
BEGIN
  SELECT count(*) INTO v_bad_count
  FROM atlas.work_items wi
  JOIN atlas.work_execution_adapters a ON a.work_item_id=wi.id AND a.adapter_kind='legacy_task'
  JOIN atlas.tasks t ON t.id=a.task_id
  WHERE coalesce((wi.metadata->>'adoptedFromLegacyTask')::boolean,false)
    AND (
      t.visibility_scope <> 'assigned_worker'
      OR t.parent_task_id IS NOT NULL
      OR coalesce(nullif(btrim(t.metadata->>'parent_task_id'),''),'') <> ''
    );

  IF v_bad_count <> 0 THEN
    RAISE EXCEPTION 'Company Work adoption included % non-responsibility legacy rows.', v_bad_count;
  END IF;
END;
$proof$;

COMMIT;
