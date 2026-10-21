BEGIN;
-- Atlas Personal Daily Log reads: no new custody, no data copy.
-- All rows remain owned by their original Person or canonical Work authority.

CREATE OR REPLACE FUNCTION atlas.personal_daily_raw_notes_self_api_v1(p_date date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_principal uuid;
  v_items jsonb := '[]'::jsonb;
  v_truncated boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Signed-in Person required.' USING errcode='42501';
  END IF;
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'Exact notebook date required.' USING errcode='22023';
  END IF;
  v_principal := atlas.require_active_task_principal_v1();
  -- notebookDate is a page coordinate, NOT the observed occurrence date.
  WITH source_rows AS MATERIALIZED (
    SELECT c.id,c.testimony,c.captured_at,c.capture_state
    FROM atlas.personal_reality_captures c
    WHERE c.owner_user_id=v_user AND c.principal_id=v_principal
      AND c.source_surface='personal_notebook_daily_log'
      AND c.metadata->>'notebookEntryKind'='raw_note'
      AND c.capture_context->>'notebookDate'=p_date::text
    ORDER BY c.captured_at,c.id LIMIT 101
  ), ranked AS (
    SELECT source_rows.*,
      row_number() OVER (ORDER BY captured_at,id) AS rn
    FROM source_rows
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',r.id,'text',r.testimony,'capturedAt',r.captured_at,
      'captureState',r.capture_state,'sourceKind','first_party_testimony',
      'subjectUnresolved',true
    ) ORDER BY r.rn) FILTER(WHERE r.rn<=100),'[]'::jsonb),
    count(*)>100
  INTO v_items,v_truncated FROM ranked r;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','personal_daily_raw_notes_self_v1',
    'date',p_date,'items',v_items,'truncated',v_truncated,
    'total',CASE WHEN v_truncated THEN NULL ELSE jsonb_array_length(v_items) END,
    'dateIsNotebookPageContextNotObservedAt',true
  );
END
$function$;

-- Public browser membrane. The internal source table remains unexposed.
CREATE OR REPLACE FUNCTION public.personal_daily_raw_notes_self_api_v1(p_date date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
  SELECT atlas.personal_daily_raw_notes_self_api_v1(p_date);
$function$;
REVOKE ALL ON FUNCTION atlas.personal_daily_raw_notes_self_api_v1(date) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.personal_daily_raw_notes_self_api_v1(date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.personal_daily_raw_notes_self_api_v1(date) TO authenticated;

-- Preserve the existing public RPC signature and all existing item fields.
-- A completed work/allocation pair remains on its original dated plan,\n-- whose state changes from active to completed via the released completion trigger.
CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_day_self_api_v1(p_date date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_self uuid:=atlas.current_person_id_v1();
  v_items jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person and exact day required.' USING errcode='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',w.id,'allocationId',a.id,'planId',p.id,
    'organizationId',w.organization_id,
    'ledgerId',(a.establishment_basis->>'nativeLedgerId')::uuid,
    'title',w.title,'instructions',w.instructions,
    'executionDate',p.planned_service_date,'exposureDate',p.exposure_service_date,
    'dueDate',t.due_on_date,'taskClassification',
      coalesce(w.metadata->>'taskClassification','ordinary'),
    'workState',w.work_state,'allocationState',a.state,
    'completedAt',w.completed_at,
    'latestResultId',res.id,'latestResultKind',res.result_kind,
    'latestResultAt',res.reported_at,'latestAcceptanceDecision',res.acceptance_decision,
    'canReportOrdinaryCompletion',
      w.work_state='open' AND a.state='active'
      AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
  ) ORDER BY p.created_at,w.id),'[]'::jsonb) INTO v_items
  FROM atlas.work_allocations a
  JOIN atlas.work_items w ON w.id=a.work_item_id AND w.organization_id=a.organization_id
  JOIN atlas.work_execution_plans p ON p.work_item_id=w.id
    AND p.organization_id=w.organization_id
    AND p.responsible_allocation_id=a.id
    AND (
      (p.plan_state='active' AND w.work_state='open' AND a.state='active')
      OR
      (p.plan_state='completed' AND w.work_state='completed' AND a.state='completed')
    )
    AND p.exposure_service_date=p_date
    AND p.assignee_membership_id IS NULL
  LEFT JOIN LATERAL (
    SELECT due_on_date FROM atlas.work_time_contracts t
    WHERE t.work_item_id=w.id AND t.contract_state='active'
    ORDER BY t.created_at DESC LIMIT 1
  ) t ON true
  LEFT JOIN LATERAL (
    SELECT r.id,r.result_kind,r.reported_at,
      (SELECT ra.decision FROM atlas.work_result_acceptances ra
       WHERE ra.execution_result_id=r.id
       ORDER BY ra.accepted_at DESC,ra.id DESC LIMIT 1) AS acceptance_decision
    FROM atlas.work_execution_results r
    WHERE r.work_item_id=w.id AND r.responsible_allocation_id=a.id
    ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
  ) res ON true
  WHERE a.assignee_canonical_person_id=v_self
    AND a.assignee_membership_id IS NULL
    AND a.allocation_role='responsible'
    AND a.establishment_basis_kind IN
      ('person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment')
    AND ((a.state='active' AND w.work_state='open')
      OR (a.state='completed' AND w.work_state='completed'))
    AND atlas.person_has_native_ledger_connection_v1(
      w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self);
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_company_work_day_v1',
    'date',p_date,'personId',v_self,'items',v_items,
    'oneCanonicalWorkIdentity',true,'deliveryReadProven',false);
END
$function$;
COMMIT;
