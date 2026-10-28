-- Atlas source candidate (not a migration): signed, read-only original legacy
-- farm Task projection for the same currently connected canonical Person.
-- The prior employee/farm seat is evidence of historical task identity only;
-- it NEVER supplies present authority to discover any Task.
CREATE OR REPLACE FUNCTION atlas.connected_person_legacy_farm_task_self_api_v1(
    p_limit integer DEFAULT 50, p_after_task_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_person uuid;
  v_items jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next uuid;
BEGIN
  IF auth.uid() IS NULL
    OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
    OR (atlas.reality_access_self_api_v1()->>'authenticated') IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'Signed canonical Person required.'
      USING ERRCODE='42501';
  END IF;
  v_person := atlas.current_person_id_v1();
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Canonical Person required.'
      USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Task page limit must be between 1 and 100.'
      USING ERRCODE='22023';
  END IF;

  WITH admitted AS MATERIALIZED (
    SELECT DISTINCT t.id,t.title,t.status,t.due_date,f.name AS farm_name,
      lop.ledger_id
    FROM atlas.tasks t
    JOIN atlas.farms f ON f.id=t.farm_id
      AND f.organization_id=t.organization_id AND f.status='active'
    -- Historical assignment is *data*, never authentication.
    JOIN atlas.farm_memberships fm ON fm.id=t.assigned_membership_id
      AND fm.farm_id=f.id AND fm.active=true
    JOIN atlas.identity_subjects legacy_subject
      ON legacy_subject.id=fm.identity_subject_id
      AND legacy_subject.organization_id=f.organization_id
      AND legacy_subject.state='active'
    -- Current institutionally adjudicated identity must resolve the exact
    -- historical subject to the current signed canonical Reality Person.
    JOIN atlas.institutional_person_records ipr
      ON ipr.organization_id=f.organization_id
      AND ipr.identity_subject_id=legacy_subject.id
      AND ipr.person_id=v_person AND ipr.status='active'
    JOIN atlas.ledger_organization_participations lop
      ON lop.organization_id=f.organization_id
      AND lop.participation_kind='governing'
      AND lop.is_compatibility_primary=true
      AND lop.status='active' AND lop.ended_at IS NULL
    JOIN atlas.ledgers al ON al.id=lop.ledger_id AND al.status='active'
    JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
      AND nl.ledger_state='active' AND nl.retired_at IS NULL
    -- CURRENT canonical native Ledger seat, not an obsolete farm role,
    -- old auth.user, employee seat, or user-supplied Person ID.
    JOIN ledger.seats seat ON seat.ledger_id=lop.ledger_id
      AND seat.person_entity_id=v_person
      AND seat.seat_state='active' AND seat.ended_at IS NULL
    WHERE t.task_scope='farm_operation'
      AND t.visibility_scope='assigned_worker'
      AND t.status IN ('open','blocked')
      AND (p_after_task_id IS NULL OR t.id>p_after_task_id)
      AND NOT EXISTS (
        SELECT 1 FROM atlas.work_items w
        JOIN atlas.work_allocations a ON a.work_item_id=w.id
          AND a.organization_id=w.organization_id
          AND a.assignee_canonical_person_id=v_person
          AND a.allocation_role='responsible' AND a.state='active'
        WHERE w.organization_id=f.organization_id
          AND w.source_object_id=t.id
          AND w.source_object_type IN ('legacy_task','legacy_task_slice')
          AND w.work_state='open'
      )
  ), page AS (
    SELECT * FROM admitted ORDER BY id LIMIT p_limit+1
  ), visible AS (
    SELECT * FROM page ORDER BY id LIMIT p_limit
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'taskId',visible.id,
    'title',visible.title,
    'sourceStatus',visible.status,
    'dueDate',visible.due_date,
    'farmName',visible.farm_name,
    'ledgerId',visible.ledger_id,
    'sourceKind','legacy_farm_task',
    'readOnlyPendingWorkReconciliation',true
  ) ORDER BY visible.id),'[]'::jsonb),
  (SELECT count(*)>p_limit FROM page),
  max(visible.id::text)::uuid
  INTO v_items,v_has_more,v_next
  FROM visible;
  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','connected_person_legacy_farm_task_v1',
    'viewerPersonId',v_person,
    'items',v_items,
    'hasMore',v_has_more,
    'nextTaskId',CASE WHEN v_has_more THEN v_next ELSE NULL END,
    'scope','signed_canonical_person_primary_governing_ledger',
    'legacyMembershipIsNotAuthority',true,
    'sourceOriginalsRemainUnmodified',true
  );
END
$function$;

REVOKE ALL ON FUNCTION atlas.connected_person_legacy_farm_task_self_api_v1(integer,uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION atlas.connected_person_legacy_farm_task_self_api_v1(integer,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.connected_person_legacy_farm_task_self_api_v1(
    p_limit integer DEFAULT 50, p_after_task_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'pg_catalog'
AS $function$
  SELECT atlas.connected_person_legacy_farm_task_self_api_v1(p_limit,p_after_task_id);
$function$;
REVOKE ALL ON FUNCTION public.connected_person_legacy_farm_task_self_api_v1(integer,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_legacy_farm_task_self_api_v1(integer,uuid)
  TO authenticated;
