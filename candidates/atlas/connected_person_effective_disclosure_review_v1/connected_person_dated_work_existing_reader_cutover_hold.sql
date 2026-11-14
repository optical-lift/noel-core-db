-- HOLD / UNAPPLIED Gate 0 source candidate for Noel #2255/#2263.
-- Exact live original signature: atlas.connected_person_company_work_day_self_api_v1(date).
-- Keep both active and completed original Work, plan/result/acceptance receipts,
-- and original Worker Day separate. Never fabricate a new task or completion.
-- Signed current Person + exact active Ledger Seat + verified original Work
-- source relevance are necessary for any row. Task classification and Work
-- instructions are separate field grants: NULL until governance approves them.
-- WARNING: result/acceptance fields and Work titles still require governor
-- field decisions; legitimate worker instructions parity remains INCOMPLETE.
-- NOT for live production, migrations or standalone release.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.connected_person_company_work_day_self_api_v1(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_self uuid:=atlas.current_person_id_v1();
  v_access jsonb;
  v_items jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person and exact day required.' USING errcode='42501';
  END IF;
  -- Signed JWT alone is not a live session: protect the Person/Seat surface.
  v_access:=atlas.reality_access_self_api_v1();
  IF v_access->>'state' IS DISTINCT FROM 'ready'
     OR v_access->>'authenticated' IS DISTINCT FROM 'true'
     OR v_access->'person'->>'id' IS DISTINCT FROM v_self::text THEN
    RAISE EXCEPTION 'Source authorization unavailable' USING errcode='42501';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',w.id,'allocationId',a.id,'planId',p.id,
    'organizationId',w.organization_id,
    'ledgerId',(a.establishment_basis->>'nativeLedgerId')::uuid,
    'title',w.title,'instructions',
      CASE WHEN atlas.connected_person_work_field_currently_approved_v1(
        (a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self,
        'instructions') THEN w.instructions ELSE NULL::text END,
    'executionDate',p.planned_service_date,'exposureDate',p.exposure_service_date,
    'dueDate',t.due_on_date,'taskClassification',
      NULL::text,
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
      w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self)
    AND atlas.connected_person_work_field_currently_approved_v1(
      (a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self,'title')
    -- Exact original Work->Ledger attribution is a source requirement,
    -- not a UI diagnostic, even for retained completed Work history.
    AND EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=w.id AND rel.organization_id=w.organization_id
        AND rel.ledger_id::text=a.establishment_basis->>'nativeLedgerId'
        AND rel.attribution_state='active'
        AND (
          rel.evidence_kind IN ('owner_attested','participant_attested')
          OR (rel.evidence_kind='source_verified' AND EXISTS (
            SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
              w.id,rel.ledger_id) proof
            WHERE proof.source_schema=rel.source_schema
              AND proof.source_table=rel.source_table
              AND proof.source_id=rel.source_id
          ))
        )
    );
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_company_work_day_v1',
    'date',p_date,'personId',v_self,'items',v_items,
    'oneCanonicalWorkIdentity',true,'deliveryReadProven',false);
END
$function$
;
COMMIT;
