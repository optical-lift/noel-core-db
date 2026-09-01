-- Atlas Company Work person-responsibility convergence v2
--
-- Replacement for unapplied 20260831235000 after its fail-closed production
-- proof exposed one legacy task carrying conflicting explicit assignee IDs.
--
-- Governing contract:
--   Company Work = what the organization owes.
--   Allocation = who is responsible.
--   Planning conflict = responsibility/execution truth that needs resolution.
--   Readiness / planning / capacity / Clock / leases organize attention only.
--   None of those may erase unfinished Company Work.

BEGIN;

DO $prerequisite$
BEGIN
  IF to_regclass('atlas.work_execution_adapters') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_attribute
       WHERE attrelid='atlas.work_items'::regclass
         AND attname='stable_key' AND NOT attisdropped
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_attribute
       WHERE attrelid='atlas.work_requirements'::regclass
         AND attname='stable_key' AND NOT attisdropped
     ) THEN
    RAISE EXCEPTION 'Company Work adapter prerequisite 20260831123000 is not live.';
  END IF;
END;
$prerequisite$;

CREATE OR REPLACE FUNCTION atlas.sync_explicit_worker_task_company_work_v2(p_task_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, atlas, auth
AS $function$
DECLARE
  v_task atlas.tasks%rowtype;
  v_farm atlas.farms%rowtype;
  v_work atlas.work_items%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_existing_work atlas.work_items%rowtype;
  v_active_allocation atlas.work_allocations%rowtype;
  v_farm_user_id uuid;
  v_assignee_user_id uuid;
  v_assignee_org_membership_id uuid;
  v_work_key text;
  v_requirement_key text;
  v_timezone text;
  v_target_at timestamptz;
  v_time_id uuid;
  v_conflict_id uuid;
  v_is_top_level boolean;
  v_has_assignment_signal boolean;
  v_assignment_conflict boolean := false;
  v_declares_company_work boolean;
  v_adopted_from_legacy boolean := false;
BEGIN
  SELECT * INTO v_task
  FROM atlas.tasks
  WHERE id=p_task_id;

  IF v_task.id IS NULL THEN
    RETURN jsonb_build_object('state','missing_task','taskId',p_task_id);
  END IF;

  v_work_key := 'legacy_task_adoption:' || v_task.id::text;
  v_requirement_key := v_work_key || ':requirement';

  -- If another domain has already established canonical Company Work for this
  -- task carrier, reuse that identity rather than creating a second obligation.
  SELECT wi.* INTO v_existing_work
  FROM atlas.work_execution_adapters a
  JOIN atlas.work_items wi
    ON wi.organization_id=a.organization_id
   AND wi.id=a.work_item_id
  WHERE a.task_id=v_task.id
  ORDER BY CASE WHEN a.state='active' THEN 0 ELSE 1 END,a.created_at DESC
  LIMIT 1;

  IF v_existing_work.id IS NULL THEN
    SELECT * INTO v_existing_work
    FROM atlas.work_items
    WHERE organization_id=v_task.organization_id
      AND stable_key=v_work_key
    LIMIT 1;
  END IF;

  -- Completion is evidence for work already connected to this execution
  -- carrier. Historical completed tasks are not invented as new Company Work.
  IF v_task.status='done' THEN
    IF v_existing_work.id IS NULL THEN
      RETURN jsonb_build_object('state','completed_not_adopted','taskId',v_task.id);
    END IF;

    UPDATE atlas.work_items
    SET work_state='completed',
        completed_at=coalesce(v_task.completed_at,now()),
        updated_at=now(),
        metadata=metadata || jsonb_build_object(
          'completionEvidenceKind','legacy_task_completion',
          'completionTaskId',v_task.id
        )
    WHERE id=v_existing_work.id
      AND work_state='open';

    UPDATE atlas.work_requirements r
    SET state='satisfied',
        satisfied_at=coalesce(v_task.completed_at,now()),
        updated_at=now(),
        metadata=r.metadata || jsonb_build_object('completionTaskId',v_task.id)
    FROM atlas.work_requirement_links l
    WHERE l.work_item_id=v_existing_work.id
      AND l.requirement_id=r.id
      AND l.active
      AND r.state='active';

    UPDATE atlas.work_allocations
    SET state='completed',
        completed_at=coalesce(v_task.completed_at,now()),
        updated_at=now()
    WHERE work_item_id=v_existing_work.id
      AND state='active';

    UPDATE atlas.work_time_contracts
    SET contract_state='satisfied',updated_at=now()
    WHERE work_item_id=v_existing_work.id
      AND contract_state='active';

    UPDATE atlas.work_execution_adapters
    SET state='completed',
        completed_at=coalesce(v_task.completed_at,now()),
        updated_at=now()
    WHERE task_id=v_task.id
      AND state='active';

    UPDATE atlas.work_planning_conflicts
    SET state='resolved',
        resolution_kind='work_completed',
        resolution_note='The underlying Company Work completed before responsibility identity required further resolution.',
        resolved_at=coalesce(v_task.completed_at,now()),
        updated_at=now()
    WHERE work_item_id=v_existing_work.id
      AND state='open'
      AND metadata->>'sourceTaskId'=v_task.id::text;

    RETURN jsonb_build_object(
      'state','completed',
      'taskId',v_task.id,
      'workItemId',v_existing_work.id
    );
  END IF;

  SELECT * INTO v_farm
  FROM atlas.farms
  WHERE id=v_task.farm_id;

  v_is_top_level := v_task.parent_task_id IS NULL
    AND coalesce(nullif(btrim(v_task.metadata->>'parent_task_id'),''),'')='';

  IF v_task.assigned_membership_id IS NOT NULL THEN
    SELECT fm.user_id INTO v_farm_user_id
    FROM atlas.farm_memberships fm
    WHERE fm.id=v_task.assigned_membership_id
      AND fm.active;
  END IF;

  v_has_assignment_signal := v_task.assigned_user_id IS NOT NULL
    OR v_farm_user_id IS NOT NULL;

  v_assignment_conflict := v_task.assigned_user_id IS NOT NULL
    AND v_farm_user_id IS NOT NULL
    AND v_task.assigned_user_id<>v_farm_user_id;

  IF NOT v_assignment_conflict THEN
    v_assignee_user_id := coalesce(v_task.assigned_user_id,v_farm_user_id);
  ELSE
    v_assignee_user_id := NULL;
  END IF;

  v_declares_company_work :=
       v_task.organization_id IS NOT NULL
   AND v_task.status IN ('open','blocked')
   AND v_task.visibility_scope='assigned_worker'
   AND v_is_top_level
   AND v_has_assignment_signal;

  -- Once work has been adopted, later retirement/change of the execution
  -- carrier does not erase the organization obligation. It releases the human
  -- allocation and retires only the carrier relation.
  IF NOT v_declares_company_work THEN
    IF v_existing_work.id IS NOT NULL
       AND v_existing_work.work_state='open'
       AND coalesce((v_existing_work.metadata->>'adoptedFromLegacyTask')::boolean,false) THEN
      UPDATE atlas.work_allocations
      SET state='released',
          released_at=now(),
          release_reason='legacy_carrier_no_longer_declares_responsibility',
          updated_at=now()
      WHERE work_item_id=v_existing_work.id
        AND state='active';

      UPDATE atlas.work_execution_adapters
      SET state='retired',retired_at=now(),updated_at=now(),
          metadata=metadata || jsonb_build_object(
            'retirementReason','carrier_no_longer_declares_responsibility'
          )
      WHERE task_id=v_task.id
        AND state='active';
    END IF;

    RETURN jsonb_build_object(
      'state','not_current_worker_responsibility',
      'taskId',v_task.id,
      'preservedWorkItemId',v_existing_work.id
    );
  END IF;

  IF v_farm.id IS NULL
     OR v_farm.organization_id IS NULL
     OR v_farm.organization_id<>v_task.organization_id
     OR v_farm.organization_unit_id IS NULL THEN
    RAISE EXCEPTION 'Task % lacks matching organization/unit custody.',v_task.id
      USING errcode='23514';
  END IF;

  v_timezone := coalesce(nullif(v_farm.metadata->>'timezone',''),'America/Chicago');
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN
    v_timezone := 'America/Chicago';
  END IF;

  v_target_at := CASE WHEN v_task.due_date IS NULL THEN NULL
                      ELSE ((v_task.due_date+1)::timestamp AT TIME ZONE v_timezone) END;

  IF v_existing_work.id IS NULL THEN
    v_adopted_from_legacy := true;

    INSERT INTO atlas.work_requirements(
      organization_id,organization_unit_id,stable_key,requirement_kind,summary,
      source_object_type,source_object_id,state,established_at,requirement_began_at,
      earliest_relevant_at,latest_satisfactory_at,consequence_of_delay,jurisdiction_key,metadata
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
      NULL,
      v_target_at,
      '{}'::jsonb,
      coalesce(nullif(v_task.task_scope,''),'operations'),
      jsonb_build_object(
        'adoptedFromLegacyTask',true,
        'legacyTaskId',v_task.id,
        'dueDateIsTargetNotHardLaw',true,
        'earliestRelevantAtNotInferred',true,
        'readinessMayNotSuppressRequirement',true
      )
    )
    ON CONFLICT (organization_id,stable_key) WHERE stable_key IS NOT NULL
    DO UPDATE SET
      organization_unit_id=excluded.organization_unit_id,
      summary=excluded.summary,
      latest_satisfactory_at=excluded.latest_satisfactory_at,
      metadata=atlas.work_requirements.metadata || excluded.metadata,
      updated_at=now()
    RETURNING * INTO v_requirement;

    INSERT INTO atlas.work_items(
      organization_id,organization_unit_id,stable_key,title,instructions,work_state,
      operation_class,jurisdiction_key,source_object_type,source_object_id,result_contract_key,metadata
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
        'legacyCarrierIsAuthority',false,
        'companyWorkIsResponsibilityAuthority',true
      )
    )
    ON CONFLICT (organization_id,stable_key) WHERE stable_key IS NOT NULL
    DO UPDATE SET
      organization_unit_id=excluded.organization_unit_id,
      title=excluded.title,
      instructions=excluded.instructions,
      operation_class=excluded.operation_class,
      jurisdiction_key=excluded.jurisdiction_key,
      metadata=atlas.work_items.metadata || excluded.metadata,
      updated_at=now()
    RETURNING * INTO v_work;

    INSERT INTO atlas.work_requirement_links(
      organization_id,requirement_id,work_item_id,link_role,active,metadata
    ) VALUES (
      v_task.organization_id,v_requirement.id,v_work.id,'resolves',true,
      jsonb_build_object('source','explicit_worker_task_company_work_adoption_v2')
    )
    ON CONFLICT (requirement_id,work_item_id,link_role)
    DO UPDATE SET active=true,
      metadata=atlas.work_requirement_links.metadata || excluded.metadata;

    INSERT INTO atlas.work_execution_adapters(
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
      organization_id=excluded.organization_id,
      organization_unit_id=excluded.organization_unit_id,
      work_item_id=excluded.work_item_id,
      adapter_kind=excluded.adapter_kind,
      state='active',retired_at=NULL,completed_at=NULL,
      metadata=atlas.work_execution_adapters.metadata || excluded.metadata,
      updated_at=now();
  ELSE
    v_work := v_existing_work;
    v_adopted_from_legacy := coalesce((v_work.metadata->>'adoptedFromLegacyTask')::boolean,false);
  END IF;

  -- Only adoption-owned time contracts are synchronized from legacy due dates.
  -- If another domain already owns the Company Work identity, its timing truth
  -- remains authoritative.
  IF v_adopted_from_legacy THEN
    SELECT wt.id INTO v_time_id
    FROM atlas.work_time_contracts wt
    WHERE wt.work_item_id=v_work.id
      AND wt.contract_state='active'
      AND wt.source_kind='legacy_task'
      AND wt.source_id=v_task.id
    ORDER BY wt.created_at DESC
    LIMIT 1;

    IF v_target_at IS NULL AND v_time_id IS NOT NULL THEN
      UPDATE atlas.work_time_contracts
      SET contract_state='superseded',superseded_at=now(),updated_at=now(),
          metadata=metadata || jsonb_build_object('reason','legacy_task_due_target_removed')
      WHERE id=v_time_id;
    ELSIF v_target_at IS NOT NULL AND v_time_id IS NULL THEN
      INSERT INTO atlas.work_time_contracts(
        organization_id,work_item_id,contract_state,preferred_end_at,movement_policy,
        source_kind,source_id,source_confidence,metadata
      ) VALUES (
        v_task.organization_id,v_work.id,'active',v_target_at,'movable',
        'legacy_task',v_task.id,1,
        jsonb_build_object(
          'dueDate',v_task.due_date,
          'dueDateIsTargetNotHardLaw',true,
          'timezone',v_timezone
        )
      );
    ELSIF v_target_at IS NOT NULL THEN
      UPDATE atlas.work_time_contracts
      SET preferred_end_at=v_target_at,
          movement_policy='movable',
          source_confidence=1,
          metadata=metadata || jsonb_build_object(
            'dueDate',v_task.due_date,
            'dueDateIsTargetNotHardLaw',true,
            'timezone',v_timezone
          ),
          updated_at=now()
      WHERE id=v_time_id;
    END IF;
  END IF;

  SELECT * INTO v_active_allocation
  FROM atlas.work_allocations
  WHERE work_item_id=v_work.id
    AND state='active'
    AND allocation_role='responsible'
  LIMIT 1;

  IF v_assignment_conflict THEN
    -- Conflicting identity is management truth, not a reason to erase the work
    -- or guess which human is accountable.
    IF v_active_allocation.id IS NOT NULL
       AND v_adopted_from_legacy THEN
      UPDATE atlas.work_allocations
      SET state='released',released_at=now(),
          release_reason='execution_carrier_assignment_identity_conflict',updated_at=now()
      WHERE id=v_active_allocation.id;
    END IF;

    SELECT pc.id INTO v_conflict_id
    FROM atlas.work_planning_conflicts pc
    WHERE pc.organization_id=v_task.organization_id
      AND pc.work_item_id=v_work.id
      AND pc.conflict_kind='no_eligible_assignee'
      AND pc.state='open'
      AND pc.metadata->>'sourceTaskId'=v_task.id::text
    ORDER BY pc.detected_at DESC
    LIMIT 1;

    IF v_conflict_id IS NULL THEN
      INSERT INTO atlas.work_planning_conflicts(
        organization_id,work_item_id,allocation_id,conflict_kind,detected_at,
        required_by,capacity_snapshot,reason,state,metadata
      ) VALUES (
        v_task.organization_id,
        v_work.id,
        NULL,
        'no_eligible_assignee',
        now(),
        v_target_at,
        jsonb_build_object('assignmentIdentityConflict',true),
        'The execution carrier contains conflicting explicit assignee identities. Manager resolution is required; Atlas will not choose a person.',
        'open',
        jsonb_build_object(
          'source','legacy_assignment_identity_conflict',
          'sourceTaskId',v_task.id,
          'assignedUserId',v_task.assigned_user_id,
          'assignedFarmMembershipId',v_task.assigned_membership_id,
          'farmMembershipUserId',v_farm_user_id
        )
      ) RETURNING id INTO v_conflict_id;
    ELSE
      UPDATE atlas.work_planning_conflicts
      SET required_by=v_target_at,
          capacity_snapshot=jsonb_build_object('assignmentIdentityConflict',true),
          reason='The execution carrier contains conflicting explicit assignee identities. Manager resolution is required; Atlas will not choose a person.',
          metadata=metadata || jsonb_build_object(
            'assignedUserId',v_task.assigned_user_id,
            'assignedFarmMembershipId',v_task.assigned_membership_id,
            'farmMembershipUserId',v_farm_user_id
          ),
          updated_at=now()
      WHERE id=v_conflict_id;
    END IF;

    RETURN jsonb_build_object(
      'state','responsibility_needs_resolution',
      'taskId',v_task.id,
      'workItemId',v_work.id,
      'planningConflictId',v_conflict_id,
      'trustBoundary',jsonb_build_object(
        'workPreserved',true,
        'personNotGuessed',true,
        'managerResolutionRequired',true
      )
    );
  END IF;

  SELECT om.id INTO v_assignee_org_membership_id
  FROM atlas.organization_memberships om
  WHERE om.organization_id=v_task.organization_id
    AND om.user_id=v_assignee_user_id
    AND om.active
  ORDER BY om.created_at
  LIMIT 1;

  IF v_assignee_org_membership_id IS NULL THEN
    -- Same principle: preserve work, surface unresolved responsibility.
    SELECT pc.id INTO v_conflict_id
    FROM atlas.work_planning_conflicts pc
    WHERE pc.organization_id=v_task.organization_id
      AND pc.work_item_id=v_work.id
      AND pc.conflict_kind='no_eligible_assignee'
      AND pc.state='open'
      AND pc.metadata->>'sourceTaskId'=v_task.id::text
    ORDER BY pc.detected_at DESC LIMIT 1;

    IF v_conflict_id IS NULL THEN
      INSERT INTO atlas.work_planning_conflicts(
        organization_id,work_item_id,conflict_kind,detected_at,required_by,
        capacity_snapshot,reason,state,metadata
      ) VALUES (
        v_task.organization_id,v_work.id,'no_eligible_assignee',now(),v_target_at,
        jsonb_build_object('missingActiveOrganizationMembership',true),
        'The assigned person does not resolve to an active organization membership. Manager resolution is required.',
        'open',jsonb_build_object('source','legacy_assignment_membership_resolution','sourceTaskId',v_task.id,
                                 'assignedUserId',v_assignee_user_id)
      ) RETURNING id INTO v_conflict_id;
    END IF;

    RETURN jsonb_build_object('state','responsibility_needs_resolution','taskId',v_task.id,
                              'workItemId',v_work.id,'planningConflictId',v_conflict_id);
  END IF;

  -- For work adopted from the legacy carrier, explicit reassignment on that
  -- carrier is valid responsibility evidence. For pre-existing canonical work,
  -- the Company Work allocation wins; a disagreement becomes a conflict rather
  -- than letting a downstream carrier silently rewrite custody.
  IF v_active_allocation.id IS NOT NULL
     AND v_active_allocation.assignee_membership_id<>v_assignee_org_membership_id THEN
    IF v_adopted_from_legacy THEN
      UPDATE atlas.work_allocations
      SET state='released',released_at=now(),release_reason='legacy_task_explicit_reassignment',updated_at=now()
      WHERE id=v_active_allocation.id;
      v_active_allocation.id := NULL;
    ELSE
      INSERT INTO atlas.work_planning_conflicts(
        organization_id,work_item_id,allocation_id,conflict_kind,detected_at,required_by,
        capacity_snapshot,reason,state,metadata
      )
      SELECT v_task.organization_id,v_work.id,v_active_allocation.id,'other',now(),v_target_at,
        jsonb_build_object('carrierAllocationMismatch',true),
        'The execution carrier assignee conflicts with the canonical Company Work allocation. Company Work custody remains authoritative.',
        'open',jsonb_build_object('source','execution_carrier_allocation_mismatch','sourceTaskId',v_task.id,
                                 'carrierAssigneeMembershipId',v_assignee_org_membership_id,
                                 'companyWorkAssigneeMembershipId',v_active_allocation.assignee_membership_id)
      WHERE NOT EXISTS (
        SELECT 1 FROM atlas.work_planning_conflicts pc
        WHERE pc.work_item_id=v_work.id AND pc.state='open'
          AND pc.metadata->>'sourceTaskId'=v_task.id::text
          AND pc.metadata->>'source'='execution_carrier_allocation_mismatch'
      );

      RETURN jsonb_build_object('state','canonical_allocation_preserved','taskId',v_task.id,
                                'workItemId',v_work.id,'allocationId',v_active_allocation.id);
    END IF;
  END IF;

  IF v_active_allocation.id IS NULL THEN
    INSERT INTO atlas.work_allocations(
      organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
      allocation_role,state,allocated_at,metadata
    ) VALUES (
      v_task.organization_id,v_work.id,v_assignee_org_membership_id,NULL,
      'responsible','active',coalesce(v_task.released_at,v_task.created_at,now()),
      jsonb_build_object(
        'source','explicit_worker_task_company_work_adoption_v2',
        'legacyTaskId',v_task.id,
        'assignerNotInferred',true
      )
    ) RETURNING * INTO v_active_allocation;
  END IF;

  UPDATE atlas.work_planning_conflicts
  SET state='resolved',
      resolution_kind='assignment_identity_resolved',
      resolution_note='The execution carrier now resolves to one active organization membership.',
      resolved_at=now(),
      updated_at=now()
  WHERE work_item_id=v_work.id
    AND state='open'
    AND conflict_kind='no_eligible_assignee'
    AND metadata->>'sourceTaskId'=v_task.id::text;

  RETURN jsonb_build_object(
    'state','responsibility_active',
    'taskId',v_task.id,
    'workItemId',v_work.id,
    'assigneeOrganizationMembershipId',v_assignee_org_membership_id,
    'allocationId',v_active_allocation.id,
    'trustBoundary',jsonb_build_object(
      'companyWorkIsDurableTruth',true,
      'allocationIsResponsibilityTruth',true,
      'readinessCannotEraseWork',true,
      'plannerCannotEraseWork',true,
      'leaseCannotEraseWork',true
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION atlas.sync_explicit_worker_task_company_work_v2(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.sync_explicit_worker_task_company_work_v2(uuid) TO service_role;

CREATE OR REPLACE FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,atlas,auth
AS $function$
BEGIN
  PERFORM atlas.sync_explicit_worker_task_company_work_v2(NEW.id);
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v2() TO service_role;

DROP TRIGGER IF EXISTS tasks_company_work_responsibility_adoption_v1 ON atlas.tasks;
DROP TRIGGER IF EXISTS tasks_company_work_responsibility_adoption_v2 ON atlas.tasks;
CREATE TRIGGER tasks_company_work_responsibility_adoption_v2
AFTER INSERT OR UPDATE OF status,visibility_scope,assigned_membership_id,assigned_user_id,
  parent_task_id,due_date,title,note,unlock_text,operation_class,task_type,task_scope
ON atlas.tasks
FOR EACH ROW
EXECUTE FUNCTION atlas.sync_explicit_worker_task_company_work_trigger_v2();

COMMENT ON TRIGGER tasks_company_work_responsibility_adoption_v2 ON atlas.tasks IS
  'Transitional membrane: explicit top-level assigned_worker legacy tasks become durable Company Work immediately. Identity conflicts create management resolution work instead of hiding or guessing.';

-- Backfill only rows that already declare top-level unfinished human work.
DO $backfill$
DECLARE v_task_id uuid;
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
    PERFORM atlas.sync_explicit_worker_task_company_work_v2(v_task_id);
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
SET search_path=pg_catalog,atlas,auth
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING errcode='42501';
  END IF;

  RETURN QUERY
  WITH memberships AS MATERIALIZED(
    SELECT om.id,om.organization_id
    FROM atlas.organization_memberships om
    WHERE om.user_id=auth.uid()
      AND om.active
  ), base AS MATERIALIZED(
    SELECT
      wi.organization_id,
      o.name organization_name,
      wi.organization_unit_id,
      ou.stable_key organization_unit_key,
      ou.name organization_unit_name,
      wi.id work_item_id,
      wa.id allocation_id,
      wi.title,
      wi.instructions,
      wi.work_state,
      wi.operation_class,
      wa.allocation_role,
      wa.allocated_at,
      a.task_id legacy_task_id,
      t.status legacy_task_status,
      t.due_date legacy_task_due_date,
      t.blocker_text,
      CASE WHEN t.id IS NULL THEN NULL ELSE atlas.task_execution_readiness_v1(t.id) END readiness,
      CASE WHEN t.id IS NULL THEN NULL ELSE atlas.task_operation_fit_warrant_v1(t.id) END operation_fit
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
    LEFT JOIN LATERAL(
      SELECT wea.task_id
      FROM atlas.work_execution_adapters wea
      WHERE wea.organization_id=wi.organization_id
        AND wea.work_item_id=wi.id
        AND wea.state='active'
        AND wea.task_id IS NOT NULL
      ORDER BY wea.created_at DESC
      LIMIT 1
    ) a ON true
    LEFT JOIN atlas.tasks t ON t.id=a.task_id
  )
  SELECT
    b.organization_id,b.organization_name,b.organization_unit_id,b.organization_unit_key,
    b.organization_unit_name,b.work_item_id,b.allocation_id,b.title,b.instructions,b.work_state,
    b.operation_class,b.allocation_role,b.allocated_at,
    coalesce(req.requirements,'[]'::jsonb),
    req.next_target_at,
    CASE
      WHEN b.legacy_task_id IS NULL THEN 'unassessed'
      WHEN b.legacy_task_status='blocked' THEN 'waiting'
      WHEN NOT coalesce((b.readiness->>'executionReady')::boolean,false) THEN 'waiting'
      WHEN NOT coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 'needs_resolution'
      ELSE 'ready'
    END,
    CASE
      WHEN b.legacy_task_id IS NULL THEN NULL
      WHEN b.legacy_task_status='blocked' THEN coalesce(nullif(btrim(b.blocker_text),''),'task_blocked')
      WHEN NOT coalesce((b.readiness->>'executionReady')::boolean,false) THEN 'execution_requirements_not_ready'
      WHEN NOT coalesce((b.operation_fit->>'exactIdentitySupported')::boolean,false) THEN 'operation_identity_unresolved'
      ELSE NULL
    END,
    b.legacy_task_id,b.legacy_task_status,b.legacy_task_due_date,
    focus.lease_id,focus.lease_state
  FROM base b
  LEFT JOIN LATERAL(
    SELECT
      jsonb_agg(jsonb_build_object(
        'requirementId',r.id,
        'summary',r.summary,
        'state',r.state,
        'earliestRelevantAt',r.earliest_relevant_at,
        'latestSatisfactoryAt',r.latest_satisfactory_at,
        'consequenceOfDelay',r.consequence_of_delay
      ) ORDER BY r.latest_satisfactory_at NULLS LAST,r.created_at,r.id) requirements,
      min(r.latest_satisfactory_at) next_target_at
    FROM atlas.work_requirement_links l
    JOIN atlas.work_requirements r
      ON r.organization_id=l.organization_id
     AND r.id=l.requirement_id
    WHERE l.organization_id=b.organization_id
      AND l.work_item_id=b.work_item_id
      AND l.active
      AND r.state='active'
  ) req ON true
  LEFT JOIN LATERAL(
    SELECT el.id lease_id,
           (atlas.execution_lease_current_state_v1(el.id)->>'state')::text lease_state
    FROM atlas.execution_leases el
    WHERE el.organization_id=b.organization_id
      AND NOT el.shadow_only
      AND el.execution_kind='task'
      AND el.execution_id=b.legacy_task_id
      AND (atlas.execution_lease_current_state_v1(el.id)->>'state') IN ('leased','started','interrupted')
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
  'Returns every active responsible Company Work allocation for the signed-in person across organizations. Readiness, planning, capacity, Clock, and leases annotate/order but never suppress responsibility.';

REVOKE ALL ON FUNCTION atlas.company_work_self_responsibilities_api_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.company_work_self_responsibilities_api_v1() TO authenticated,service_role;

INSERT INTO atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at,anonymous_execute_expected
) VALUES (
  'atlas.company_work_self_responsibilities_api_v1()',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_company_work_person_responsibility_convergence_v2',
    'authorization','Only active organization memberships belonging to auth.uid() contribute responsible allocations.',
    'truthBoundary','Allocation is responsibility truth. Readiness/planning/capacity/Clock/leases may annotate/order but cannot suppress unfinished allocated work.',
    'classificationRuleVersion',3
  ),now(),NULL,false
)
ON CONFLICT(signature) DO UPDATE SET
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  evidence=excluded.evidence,
  registered_at=excluded.registered_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

-- Acceptance invariant for legacy-adopted open work:
-- exactly one of these must be true:
--   A) one active responsible allocation exists;
--   B) an open responsibility-resolution conflict exists.
DO $proof$
DECLARE v_bad integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM atlas.work_items wi
  WHERE wi.work_state='open'
    AND coalesce((wi.metadata->>'adoptedFromLegacyTask')::boolean,false)
    AND (
      (SELECT count(*) FROM atlas.work_allocations wa
       WHERE wa.work_item_id=wi.id AND wa.state='active' AND wa.allocation_role='responsible')
      +
      CASE WHEN EXISTS(
        SELECT 1 FROM atlas.work_planning_conflicts pc
        WHERE pc.work_item_id=wi.id AND pc.state='open'
          AND pc.conflict_kind='no_eligible_assignee'
      ) THEN 1 ELSE 0 END
    ) <> 1;

  IF v_bad<>0 THEN
    RAISE EXCEPTION 'Every open adopted Company Work row must have exactly one responsible allocation or one open responsibility-resolution conflict; bad rows=%',v_bad;
  END IF;

  SELECT count(*) INTO v_bad
  FROM atlas.work_execution_adapters a
  JOIN atlas.tasks t ON t.id=a.task_id
  JOIN atlas.work_items wi ON wi.id=a.work_item_id
  WHERE a.adapter_kind='legacy_task'
    AND coalesce((wi.metadata->>'adoptedFromLegacyTask')::boolean,false)
    AND (t.visibility_scope<>'assigned_worker'
      OR t.parent_task_id IS NOT NULL
      OR coalesce(nullif(btrim(t.metadata->>'parent_task_id'),''),'')<>'');

  IF v_bad<>0 THEN
    RAISE EXCEPTION 'Adoption included % non-responsibility legacy rows.',v_bad;
  END IF;
END;
$proof$;

COMMIT;
