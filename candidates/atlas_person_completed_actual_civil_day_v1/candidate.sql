-- SOURCE-ONLY candidate. Do not apply directly to production.
-- Same signed reader, same original Work/Person authorization.
-- Completed Work belongs on the day its signed, accepted Result was recorded
-- in the signed-in Person's authoritative civil timezone, not the earlier or
-- future planned/exposure date. Preserve original dates for Work history.
CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_day_self_api_v1(
  p_date date
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_self uuid := atlas.current_person_id_v1();
  v_principal_id uuid;
  v_timezone text;
  v_items jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person and exact day required.'
      USING errcode='42501';
  END IF;

  -- A completed Result's civil day belongs to the actual signed-in Person,
  -- NOT to the browser-supplied timezone, the Ledger owner, or a server UTC day.
  SELECT pr.id INTO v_principal_id
  FROM atlas.principals pr
  WHERE pr.person_id=v_self AND pr.user_id=auth.uid()
  ORDER BY pr.created_at DESC,pr.id DESC LIMIT 1;
  IF v_principal_id IS NULL THEN
    RAISE EXCEPTION 'Canonical Person timezone unavailable.'
      USING errcode='42501';
  END IF;
  v_timezone := atlas.principal_authoritative_timezone_v1(v_principal_id);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',w.id,'allocationId',a.id,'planId',p.id,
    'organizationId',w.organization_id,
    'ledgerId',(a.establishment_basis->>'nativeLedgerId')::uuid,
    'title',w.title,'instructions',w.instructions,
    'executionDate',p.planned_service_date,
    'exposureDate',CASE WHEN p.plan_state='completed'
      THEN (res.reported_at AT TIME ZONE v_timezone)::date
      ELSE p.exposure_service_date END,
    'originalExposureDate',p.exposure_service_date,
    'completionLocalDate',CASE WHEN p.plan_state='completed'
      THEN (res.reported_at AT TIME ZONE v_timezone)::date ELSE NULL END,
    'dueDate',t.due_on_date,'taskClassification',
      coalesce(w.metadata->>'taskClassification','ordinary'),
    'workState',w.work_state,'allocationState',a.state,
    'completedAt',w.completed_at,
    'latestResultId',res.id,'latestResultKind',res.result_kind,
    'latestResultAt',res.reported_at,
    'latestAcceptanceDecision',res.acceptance_decision,
    'canReportOrdinaryCompletion',
      w.work_state='open' AND a.state='active'
      AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
  ) ORDER BY p.created_at,w.id),'[]'::jsonb) INTO v_items
  FROM atlas.work_allocations a
  JOIN atlas.work_items w ON w.id=a.work_item_id
    AND w.organization_id=a.organization_id
  JOIN atlas.work_execution_plans p ON p.work_item_id=w.id
    AND p.organization_id=w.organization_id
    AND p.responsible_allocation_id=a.id
    AND ((p.plan_state='active' AND w.work_state='open' AND a.state='active')
      OR (p.plan_state='completed' AND w.work_state='completed' AND a.state='completed'))
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
    AND a.establishment_basis_kind IN (
      'person_connection_receiver_uptake','delegated_under_standing_scope',
      'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
    )
    AND ((a.state='active' AND w.work_state='open')
      OR (a.state='completed' AND w.work_state='completed'))
    AND (
      (p.plan_state='active' AND p.exposure_service_date=p_date)
      OR
      (p.plan_state='completed' AND res.result_kind='completed'
        AND res.acceptance_decision='accepted'
        AND (res.reported_at AT TIME ZONE v_timezone)::date=p_date)
    )
    AND atlas.person_has_native_ledger_connection_v1(
      w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self)
    AND atlas.person_original_work_identity_disclosed_self_v1(
      w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self);
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_company_work_day_v1',
    'date',p_date,'personId',v_self,'items',v_items,
    'oneCanonicalWorkIdentity',true,'deliveryReadProven',false,
    'completedOnActualCivilDay',true);
END
$function$;

-- The same wrapper in public delegates to this exact atlas source.
-- Its existing signature and exact EXECUTE/RLS grants remain unchanged.
