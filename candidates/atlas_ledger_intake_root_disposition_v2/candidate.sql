-- GOVERNED SOURCE ONLY: never execute directly on production.
-- Exact root, same original Work; unresolved needs_details is not discarded.
-- One atomic transaction for the protected migration receipt.
BEGIN;

ALTER TABLE atlas.ledger_work_intakes
 DROP CONSTRAINT ledger_work_intakes_review_state_check;
ALTER TABLE atlas.ledger_work_intakes
 ADD CONSTRAINT ledger_work_intakes_review_state_check CHECK
 (review_state IN ('submitted','needs_details','accepted_for_ledger','rejected'));
ALTER TABLE atlas.ledger_work_intake_decisions
 DROP CONSTRAINT ledger_work_intake_decisions_decision_check;
ALTER TABLE atlas.ledger_work_intake_decisions
 ADD CONSTRAINT ledger_work_intake_decisions_decision_check CHECK
 (decision IN ('needs_details','accepted_for_ledger','rejected'));
ALTER TABLE atlas.ledger_work_intake_decisions
 ADD COLUMN IF NOT EXISTS title_before text,
 ADD COLUMN IF NOT EXISTS title_after text,
 ADD COLUMN IF NOT EXISTS instructions_before text,
 ADD COLUMN IF NOT EXISTS instructions_after text;

CREATE OR REPLACE FUNCTION atlas.ledger_work_review_queue_root_self_api_v2(
 p_ledger_id uuid,p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_principal uuid;items jsonb;total integer;
BEGIN
 SELECT principal_id INTO root_principal
 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);
 IF root_principal IS NULL THEN
  RAISE EXCEPTION 'Exact Ledger root required' USING errcode='42501';
 END IF;
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Page size invalid' USING errcode='22023';END IF;

 SELECT count(*) INTO total FROM atlas.ledger_work_intakes i
 JOIN atlas.work_items w ON w.id=i.work_item_id AND w.work_state='open'
 WHERE i.ledger_id=p_ledger_id
 AND i.review_state IN ('submitted','needs_details');

 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'intakeId',x.id,'workItemId',x.work_item_id,
  'title',x.title,'instructions',x.instructions,
  'submittedAt',x.created_at,'attentionDateProposal',x.attention_date_proposal,
  'reviewState',x.review_state,'revision',x.revision,
  'lastReviewReason',x.last_reason,
  'assignedToPerson',false)
  ORDER BY x.created_at,x.id),'[]'::jsonb) INTO items
 FROM (
  SELECT i.id,i.work_item_id,i.created_at,i.attention_date_proposal,
   i.review_state,i.revision,w.title,w.instructions,
   (SELECT d.reason FROM atlas.ledger_work_intake_decisions d
    WHERE d.intake_id=i.id ORDER BY d.revision DESC LIMIT 1) AS last_reason
  FROM atlas.ledger_work_intakes i
  JOIN atlas.work_items w ON w.id=i.work_item_id AND w.work_state='open'
  WHERE i.ledger_id=p_ledger_id
  AND i.review_state IN ('submitted','needs_details')
  ORDER BY i.created_at,i.id LIMIT p_limit
 ) x;
 RETURN jsonb_build_object('ok',true,
  'contractVersion','ledger_work_root_review_queue_v2',
  'ledgerId',p_ledger_id,'items',items,'pendingCount',total,
  'isPersonalWorkObligation',false,'notificationDeliveryClaimed',false,
  'supportsReject',true,'supportsSameOriginalEdit',true);
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.review_ledger_work_intake_root_self_api_v2(
 p_intake_id uuid,p_decision text,p_expected_revision integer,
 p_reason text,p_title text,p_instructions text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE intake atlas.ledger_work_intakes%rowtype;
 work atlas.work_items%rowtype;root_principal uuid;
 reason text:=nullif(btrim(coalesce(p_reason,'')),'');
 new_title text:=nullif(btrim(coalesce(p_title,'')),'');
 new_instructions text:=nullif(btrim(coalesce(p_instructions,'')),'');
 BEGIN
 IF p_decision NOT IN ('accepted_for_ledger','rejected') OR
    p_expected_revision IS NULL OR p_expected_revision<0 OR
    reason IS NULL OR length(reason)>1000
 THEN RAISE EXCEPTION 'Decision, revision or reason invalid' USING errcode='22023';END IF;
 IF p_decision='accepted_for_ledger' AND (new_title IS NULL OR length(new_title)>500 OR
      length(coalesce(new_instructions,''))>10000)
 THEN RAISE EXCEPTION 'Edited Work title or instructions invalid' USING errcode='22023';END IF;
 IF p_decision='rejected' AND (p_title IS NOT NULL OR p_instructions IS NOT NULL)
 THEN RAISE EXCEPTION 'Rejection cannot rewrite the submitted original' USING errcode='22023';END IF;
 SELECT * INTO intake FROM atlas.ledger_work_intakes
 WHERE id=p_intake_id FOR UPDATE;
 IF intake.id IS NULL
 THEN RAISE EXCEPTION 'Intake unavailable' USING errcode='42501';END IF;
 SELECT principal_id INTO root_principal
 FROM atlas.capability_root_authority_context_self_v1(intake.ledger_id);
 IF root_principal IS NULL
 THEN RAISE EXCEPTION 'Exact Ledger root required' USING errcode='42501';END IF;
 IF intake.revision<>p_expected_revision OR
 intake.review_state NOT IN ('submitted','needs_details')
 THEN RAISE EXCEPTION 'Stale Work review' USING errcode='40001';END IF;
 SELECT * INTO work FROM atlas.work_items
 WHERE id=intake.work_item_id FOR UPDATE;
 IF work.id IS NULL OR work.work_state<>'open' OR
    work.organization_id IS DISTINCT FROM intake.organization_id OR
    work.source_object_type IS DISTINCT FROM 'ledger_work_intake' OR
    work.source_object_id IS DISTINCT FROM intake.id
 THEN RAISE EXCEPTION 'Original Work unavailable for this intake'
 USING errcode='23514';END IF;
 IF p_decision='rejected' THEN
  IF EXISTS(SELECT 1 FROM atlas.work_allocations a
    WHERE a.work_item_id=work.id AND a.state='active')
  THEN RAISE EXCEPTION 'Assigned Work cannot be rejected as an unassigned intake'
  USING errcode='23514';END IF;
  UPDATE atlas.work_items
    SET work_state='cancelled',cancelled_at=now(),updated_at=now(),
    metadata=metadata || jsonb_build_object(
     'intakeDisposition','rejected','intakeDispositionRevision',intake.revision+1)
    WHERE id=work.id;
 ELSE
  UPDATE atlas.work_items
    SET title=new_title,instructions=new_instructions,updated_at=now(),
    metadata=metadata || jsonb_build_object(
     'intakeDisposition','accepted_for_ledger',
     'intakeDispositionRevision',intake.revision+1)
    WHERE id=work.id;
 END IF;
 UPDATE atlas.ledger_work_intakes
 SET review_state=p_decision,revision=revision+1,
  reviewed_by_principal_id=root_principal,reviewed_at=now(),updated_at=now()
 WHERE id=intake.id RETURNING * INTO intake;
 INSERT INTO atlas.ledger_work_intake_decisions(
  intake_id,reviewer_principal_id,decision,reason,revision,
  title_before,title_after,instructions_before,instructions_after)
 VALUES(intake.id,root_principal,p_decision,reason,intake.revision,
  work.title,CASE WHEN p_decision='rejected' THEN work.title ELSE new_title END,
  work.instructions,CASE WHEN p_decision='rejected' THEN work.instructions ELSE new_instructions END);
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','ledger_work_root_disposition_v2',
  'intakeId',intake.id,'workItemId',work.id,'ledgerId',intake.ledger_id,
  'reviewState',intake.review_state,'revision',intake.revision,
  'workState',CASE WHEN p_decision='rejected' THEN 'cancelled' ELSE 'open' END,
  'sameOriginalWork',true,'personWorkAssignmentCreated',false,
  'personalTodayChanged',false,'workPlanCreated',false,
  'notificationDeliveryClaimed',false);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.ledger_work_review_queue_root_self_api_v2(
 p_ledger_id uuid,p_limit integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT atlas.ledger_work_review_queue_root_self_api_v2($1,$2);
$fn$;
CREATE OR REPLACE FUNCTION public.review_ledger_work_intake_root_self_api_v2(
 p_intake_id uuid,p_decision text,p_expected_revision integer,
 p_reason text,p_title text,p_instructions text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT atlas.review_ledger_work_intake_root_self_api_v2($1,$2,$3,$4,$5,$6);
$fn$;

REVOKE ALL ON FUNCTION
  public.ledger_work_review_queue_root_self_api_v2(uuid,integer),
  public.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text),
  atlas.ledger_work_review_queue_root_self_api_v2(uuid,integer),
  atlas.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
  public.ledger_work_review_queue_root_self_api_v2(uuid,integer),
  public.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text),
  atlas.ledger_work_review_queue_root_self_api_v2(uuid,integer),
  atlas.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text)
TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
