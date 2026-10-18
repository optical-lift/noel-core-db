-- Universal owner-verified personal-to-institutional Work custody.
-- Uses the original dated task only as provenance, never as a second Company Work owner.
BEGIN;
CREATE OR REPLACE FUNCTION atlas.promote_personal_dated_task_to_company_work_self_api_v1(
  p_task_id uuid, p_organization_id uuid, p_ledger_id uuid, p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_owner_person uuid;
  v_principal uuid;
  v_task atlas.task_entries%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_attribution uuid;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_new boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501';
  END IF;
  IF p_task_id IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR v_reason IS NULL OR char_length(v_reason)>1200 THEN
    RAISE EXCEPTION 'Personal task, exact Organization/Ledger and reason required.'
      USING ERRCODE='22023';
  END IF;

  -- Both institutional governing roots AND the user's own Personal Atlas
  -- Principal are checked. There is no target Person/assignee input.
  v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_principal:=atlas.require_active_task_principal_v1();

  -- Serializes promotion of this exact original task, including competing
  -- attempts to place it in a different Organization or Ledger.
  SELECT * INTO v_task FROM atlas.task_entries t
  WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
    AND t.principal_id=v_principal FOR UPDATE;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Owned original dated task unavailable.' USING ERRCODE='42501';
  END IF;
  IF v_task.status<>'open' THEN
    RAISE EXCEPTION 'Only still-open personal tasks may enter Company Work.'
      USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_work FROM atlas.work_items w
  WHERE w.source_object_type='personal_dated_task'
    AND w.source_object_id=v_task.id
  ORDER BY w.created_at,w.id LIMIT 1;

  IF v_work.id IS NULL THEN
    -- Work ID becomes the single institution-owned executable identity.
    -- The personal date is evidence only; it does NOT authorize employee
    -- scheduling, a hard finish time or Worker Day delivery.
    INSERT INTO atlas.work_items(
      organization_id,title,instructions,work_state,
      source_object_type,source_object_id,created_by_user_id,stable_key,metadata
    ) VALUES(
      p_organization_id,v_task.sentence,NULL,'open',
      'personal_dated_task',v_task.id,auth.uid(),
      'personal-dated-task-company-work:'||v_task.id::text,
      jsonb_build_object(
        'sourceContract','personal_dated_task_to_company_work_v1',
        'sourceTaskDate',v_task.due_date,
        'dateMeaning','personal_source_page_not_institutional_schedule',
        'custody','institutional_work_item',
        'ownerIntentReason',v_reason,
        'declaredByPersonId',v_owner_person
      )
    ) RETURNING * INTO v_work;
    v_new:=true;
  ELSE
    IF v_work.organization_id IS DISTINCT FROM p_organization_id THEN
      RAISE EXCEPTION 'This personal source is already held by another Organization.'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance l
      WHERE l.work_item_id=v_work.id AND l.organization_id=p_organization_id
        AND l.ledger_id=p_ledger_id AND l.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'This personal source already has different institutional custody.'
        USING ERRCODE='23514';
    END IF;
  END IF;

  INSERT INTO atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id
  ) VALUES(
    p_organization_id,v_work.id,p_ledger_id,'owner_attested',
    'atlas.task_entries:'||v_task.id::text,v_reason,v_owner_person
  )
  ON CONFLICT(work_item_id,ledger_id,evidence_kind)
    WHERE attribution_state='active'
  DO NOTHING;

  SELECT l.id INTO v_attribution
  FROM atlas.company_work_native_ledger_relevance l
  WHERE l.organization_id=p_organization_id AND l.work_item_id=v_work.id
    AND l.ledger_id=p_ledger_id AND l.evidence_kind='owner_attested'
    AND l.attribution_state='active';
  IF v_attribution IS NULL THEN
    RAISE EXCEPTION 'Exact native Ledger source receipt not established.'
      USING ERRCODE='23514';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','personal_task_company_work_custody_v1',
    'workItemId',v_work.id,'organizationId',p_organization_id,
    'nativeLedgerId',p_ledger_id,'sourceTaskId',v_task.id,
    'sourceDate',v_task.due_date,'sourceTitle',v_task.sentence,
    'attributionId',v_attribution,'createdNow',v_new,
    'institutionalDateEstablished',false,
    'responsibleAllocationEstablished',false,
    'sourceRemainsProvenance',true
  );
END
$fn$;

REVOKE ALL ON FUNCTION atlas.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)
  TO authenticated;
CREATE OR REPLACE FUNCTION public.promote_personal_dated_task_to_company_work_self_api_v1(
  p_task_id uuid,p_organization_id uuid,p_ledger_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
SELECT atlas.promote_personal_dated_task_to_company_work_self_api_v1(
  p_task_id,p_organization_id,p_ledger_id,p_reason);
$fn$;
REVOKE ALL ON FUNCTION public.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)
  TO authenticated;

-- The existing Person day is retained for source history, but its title
-- cannot be independently marked Done once institutional custody exists.
CREATE OR REPLACE FUNCTION atlas.atlas_task_day_self_api_v1(p_date date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $fn$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_rows jsonb;
BEGIN
 IF p_date IS NULL THEN RAISE EXCEPTION 'Date required.' USING ERRCODE='22023'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
   'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
   'institutionalWorkItemId',wi.id,
   'institutionalWorkState',wi.work_state,
   'institutionalTransfer',wi.id IS NOT NULL
 )) ORDER BY CASE WHEN t.status='open' THEN 0 ELSE 1 END,t.created_at,t.id),'[]'::jsonb)
 INTO v_rows
 FROM atlas.task_entries t
 LEFT JOIN LATERAL (
   SELECT w.id,w.work_state FROM atlas.work_items w
   WHERE w.source_object_type='personal_dated_task'
     AND w.source_object_id=t.id
   ORDER BY w.created_at,w.id LIMIT 1
 ) wi ON true
 WHERE t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal AND t.due_date=p_date;
 RETURN jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.set_atlas_task_done_self_api_v1(
 p_task_id uuid,p_done boolean
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $fn$
DECLARE
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_task atlas.task_entries%ROWTYPE;
BEGIN
  IF p_task_id IS NULL OR p_done IS NULL THEN
    RAISE EXCEPTION 'Task and completion state required.' USING ERRCODE='22023';
  END IF;
  -- Serialize with the institutional promotion's SELECT FOR UPDATE:
  -- neither request can inspect a stale source state while the other acts.
  SELECT * INTO v_task FROM atlas.task_entries t
  WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
    AND t.principal_id=v_principal FOR UPDATE;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE='42501';
  END IF;

  -- Do not permit independent success/failure state on original Person
  -- evidence once Company Work has accepted custody of execution.
  IF EXISTS (
    SELECT 1 FROM atlas.task_entries t
    JOIN atlas.work_items w ON w.source_object_type='personal_dated_task'
     AND w.source_object_id=t.id
    WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
      AND t.principal_id=v_principal
  ) THEN
    RAISE EXCEPTION 'Transferred Company Work cannot be completed as a personal dated task.'
      USING ERRCODE='23514';
  END IF;
  UPDATE atlas.task_entries
    SET status=CASE WHEN p_done THEN 'done' ELSE 'open' END,
        completed_at=CASE WHEN p_done THEN now() ELSE NULL END
  WHERE id=p_task_id AND owner_user_id=auth.uid() AND principal_id=v_principal
  RETURNING * INTO v_task;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
END
$fn$;
COMMIT;
