-- Build 5: owner-directed, reversible retirement of obsolete Company Work.
-- History/receipts are preserved; an ungoverned hard DELETE is not exposed.
-- The preview and writer both use the authenticated exact Ledger owner seam.
BEGIN;

CREATE FUNCTION atlas.company_work_retirement_review_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_work_item_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_owner_person uuid;
  v_work atlas.work_items%ROWTYPE;
  v_related jsonb := '[]'::jsonb;
  v_pending_offers bigint := 0;
  v_unresolved_reports bigint := 0;
  v_source_links bigint := 0;
  v_exact_relevance boolean := false;
  v_legacy_task_status text;
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Organization, selected Ledger and exact Work required'
      USING ERRCODE='22023';
  END IF;
  v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id AND organization_id=p_organization_id;
  IF v_work.id IS NULL
     OR NOT atlas.can_adjudicate_company_work_v1(v_work.id) THEN
    RAISE EXCEPTION 'Company Work unavailable to this owner' USING ERRCODE='42501';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
    WHERE rel.organization_id=v_work.organization_id AND rel.work_item_id=v_work.id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
      AND (rel.evidence_kind='owner_attested'
        OR (rel.evidence_kind='source_verified' AND EXISTS(
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          WHERE proof.source_schema=rel.source_schema
            AND proof.source_table=rel.source_table AND proof.source_id=rel.source_id)))
  ) INTO v_exact_relevance;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'relationId',r.id,
      'relationKind',r.relation_kind,
      'direction',CASE WHEN r.from_work_item_id=v_work.id THEN 'outgoing'
                       ELSE 'incoming' END,
      'relatedWorkItemId',other.id,
      'relatedWorkState',other.work_state
    ) ORDER BY r.id),'[]'::jsonb)
    INTO v_related
  FROM atlas.work_item_relations r
  JOIN atlas.work_items other
    ON other.id=CASE WHEN r.from_work_item_id=v_work.id
                    THEN r.to_work_item_id ELSE r.from_work_item_id END
    AND other.organization_id=v_work.organization_id
  WHERE r.organization_id=v_work.organization_id AND r.active
    AND (r.from_work_item_id=v_work.id OR r.to_work_item_id=v_work.id)
    AND other.id<>v_work.id AND other.work_state='open';

  SELECT count(*) INTO v_pending_offers
  FROM atlas.company_work_initial_responsibility_offers o
  WHERE o.organization_id=v_work.organization_id
    AND o.work_item_id=v_work.id AND o.offer_state='offered';

  SELECT count(*) INTO v_unresolved_reports
  FROM atlas.work_execution_results report
  WHERE report.organization_id=v_work.organization_id
    AND report.work_item_id=v_work.id
    AND NOT EXISTS(
      SELECT 1 FROM atlas.work_result_acceptances decision
      WHERE decision.execution_result_id=report.id);

  SELECT count(*) INTO v_source_links
  FROM atlas.work_requirement_links link
  WHERE link.organization_id=v_work.organization_id
    AND link.work_item_id=v_work.id AND link.active;

  IF v_work.source_object_type='legacy_task' THEN
    SELECT task.status INTO v_legacy_task_status
    FROM atlas.tasks task
    JOIN atlas.farms farm ON farm.id=task.farm_id
    WHERE task.id=v_work.source_object_id
      AND farm.organization_id=v_work.organization_id;
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','company_work_retirement_review_v1',
    'workItemId',v_work.id,'organizationId',v_work.organization_id,
    'selectedLedgerId',p_ledger_id,
    'nativeLedgerRelevanceProven',v_exact_relevance,
    'workState',v_work.work_state,'title',v_work.title,
    'sourceObjectType',v_work.source_object_type,
    'legacyTaskStatus',v_legacy_task_status,
    'activeOpenWorkRelations',v_related,
    'relatedOpenWorkCount',jsonb_array_length(v_related),
    'pendingOffersCount',v_pending_offers,
    'unresolvedWorkerReportsCount',v_unresolved_reports,
    'activeSourceRequirementLinksCount',v_source_links,
    'sourceReconciliationRequired',
      (v_source_links>0
       OR (v_work.source_object_type IS NOT NULL
           AND v_work.source_object_type<>'legacy_task')
       OR (v_work.source_object_type='legacy_task'
           AND v_legacy_task_status IS NULL)),
    'relatedWorkReconciliationRequired',jsonb_array_length(v_related)>0,
    'preserveHistory',true,'hardDeleteAvailable',false);
END
$function$;

CREATE FUNCTION atlas.retire_company_work_from_active_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_work_item_id uuid,
  p_reason text,
  p_acknowledge_related_work boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_owner_person uuid;
  v_work atlas.work_items%ROWTYPE;
  v_review jsonb;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_source_task_id uuid;
  v_source_status text;
  v_receipt jsonb;
  v_now timestamptz:=clock_timestamp();
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL
     OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 8 AND 1200 THEN
    RAISE EXCEPTION 'Exact Work and a meaningful owner removal reason are required'
      USING ERRCODE='22023';
  END IF;
  v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
  WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
  IF v_work.id IS NULL OR NOT atlas.can_adjudicate_company_work_v1(v_work.id) THEN
    RAISE EXCEPTION 'Company Work unavailable to this owner' USING ERRCODE='42501';
  END IF;
  IF v_work.work_state='cancelled' THEN
    RETURN jsonb_build_object('ok',true,'contractVersion','company_work_retirement_v1',
      'state','already_removed_from_active_work','workItemId',v_work.id,
      'companyWorkState','cancelled','workerCompletionRecorded',false);
  END IF;
  IF v_work.work_state<>'open' THEN
    RAISE EXCEPTION 'Historical/completed Work cannot be rewritten as obsolete'
      USING ERRCODE='23514';
  END IF;

  -- Recompute impact INSIDE the source Work lock; an earlier UI preview is not
  -- permission and cannot make a stale-impact removal succeed silently.
  v_review:=atlas.company_work_retirement_review_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  IF (v_review->>'sourceReconciliationRequired')::boolean THEN
    RETURN v_review||jsonb_build_object('state','source_reconciliation_required',
      'removed',false,'explanation',
      'An active domain source still owns this Work; reconcile its source first.');
  END IF;
  IF ((v_review->>'relatedOpenWorkCount')::integer>0
      OR (v_review->>'unresolvedWorkerReportsCount')::bigint>0)
      AND p_acknowledge_related_work IS DISTINCT FROM true THEN
    RETURN v_review||jsonb_build_object('state','impact_review_required',
      'removed',false,'explanation',
      'Review affected Work and unresolved worker results before confirming removal.');
  END IF;

  -- A legacy task is a real source carrier. Retire the *verified same-org*
  -- task as well; otherwise its sync trigger may recreate obsolete Company Work.
  -- Never rewrite a different Organization's task by a guessed title.
  IF v_work.source_object_type='legacy_task' THEN
    SELECT task.id,task.status INTO v_source_task_id,v_source_status
    FROM atlas.tasks task
    JOIN atlas.farms farm ON farm.id=task.farm_id
    WHERE task.id=v_work.source_object_id
      AND farm.organization_id=v_work.organization_id
    FOR UPDATE OF task;
    IF v_source_task_id IS NULL THEN
      RETURN v_review||jsonb_build_object('state','source_reconciliation_required',
        'removed',false,'explanation','Original same-Organization task could not be verified.');
    END IF;
    IF v_source_status='done' THEN
      RETURN v_review||jsonb_build_object('state','source_reconciliation_required',
        'removed',false,'explanation','Source task says done but Company Work remains open; adjudicate the conflicting evidence.');
    END IF;
    IF v_source_status<>'archived' THEN
      UPDATE atlas.tasks SET status='archived' WHERE id=v_source_task_id;
    END IF;
  END IF;

  -- The existing audited institutional adjudication owns Work cancellation,
  -- allocation release, adapter retirement, plan withdrawal and receipt.
  v_receipt:=atlas.organization_management_adjudicate_company_work_api_v1(
    p_work_item_id,'not_relevant','{}'::jsonb,v_reason,v_now,
    'company-work-retirement-v1:'||p_work_item_id::text);
  IF v_receipt->>'companyWorkState'<>'cancelled' THEN
    RAISE EXCEPTION 'Obsolete Work was not actually cancelled' USING ERRCODE='23514';
  END IF;

  UPDATE atlas.company_work_initial_responsibility_offers
    SET offer_state='stale',resolved_at=v_now,
        resolution_reason='source_work_removed_from_active'
  WHERE organization_id=v_work.organization_id AND work_item_id=v_work.id
    AND offer_state='offered';

  UPDATE atlas.work_items
    SET metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'ownerRemovedFromActiveAt',v_now,'ownerRemovalReason',v_reason,
      'ownerRemovalSelectedLedgerId',p_ledger_id,
      'relatedWorkReconciliationPending',
        (v_review->>'relatedWorkReconciliationRequired')::boolean,
      'unresolvedWorkerReportsPreserved',
        (v_review->>'unresolvedWorkerReportsCount')::bigint>0),
      updated_at=v_now
  WHERE id=v_work.id AND organization_id=v_work.organization_id
    AND work_state='cancelled';

  RETURN v_review||jsonb_build_object(
    'contractVersion','company_work_retirement_v1',
    'state','removed_from_active_work','removed',true,
    'companyWorkState','cancelled','workerCompletionRecorded',false,
    'managementAdjudicationId',v_receipt->>'adjudicationId',
    'sourceTaskArchived',v_source_task_id IS NOT NULL,
    'relatedWorkReconciliationPending',
      (v_review->>'relatedWorkReconciliationRequired')::boolean,
    'relationsAutoDeleted',false,'historyPreserved',true);
END
$function$;

REVOKE ALL ON FUNCTION atlas.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)
  TO authenticated;

CREATE FUNCTION public.company_work_retirement_review_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.company_work_retirement_review_self_api_v1(
   p_organization_id,p_ledger_id,p_work_item_id);
$fn$;
CREATE FUNCTION public.retire_company_work_from_active_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_reason text,p_acknowledge_related_work boolean DEFAULT false
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.retire_company_work_from_active_self_api_v1(
   p_organization_id,p_ledger_id,p_work_item_id,p_reason,p_acknowledge_related_work);
$fn$;

REVOKE ALL ON FUNCTION public.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)
  TO authenticated;

COMMIT;
