-- NONRELEASABLE TEST-ONLY EXACT SOURCE COPY. No production execution.
BEGIN;
-- HELD ONLY: same existing owner/Person/Ledger and historical decision custody.
-- No automatic Work, Need, assignment, schedule, Task or queue state change.
DO $source$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=
     to_regprocedure('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)'))
     IS DISTINCT FROM '5fd7ab54881787dfc8fc1aa464e48911'
 OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=
     to_regprocedure('atlas.decide_company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,uuid,boolean)'))
     IS DISTINCT FROM 'c8409d66828d9ac419c73405c6df09c7'
 OR to_regclass('atlas.company_work_legacy_task_reviews_v1') IS NULL
 OR to_regclass('atlas.task_release_queue_items') IS NULL
 THEN RAISE EXCEPTION 'Current owner custody or legacy source drift';
 END IF;
END;$source$;

CREATE OR REPLACE FUNCTION atlas.company_work_legacy_queue_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_limit int DEFAULT 100,
 p_after_queue_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE actor uuid; rows jsonb; more boolean; cursor uuid;
BEGIN
 actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF actor IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
   RAISE EXCEPTION 'Verified owner and bounded page required' USING ERRCODE='42501';
 END IF;
 WITH page AS (
 SELECT q.id,q.queue_key,q.position,q.state,q.updated_at,q.original_due_date,
 q.task_id,q.planned_occurrence_id,t.title task_title,t.status task_status,
 o.title occurrence_title,o.state occurrence_state,
 w.id original_work_id,w.work_state original_work_state,
 r.decision_kind owner_decision,r.target_work_item_id reviewed_work_id,
 row_number() OVER (ORDER BY q.id) rn
 FROM atlas.task_release_queue_items q
 JOIN atlas.farms f ON f.id=q.farm_id AND f.organization_id=p_organization_id
 LEFT JOIN atlas.tasks t ON t.id=q.task_id
   AND t.organization_id=p_organization_id AND t.farm_id=q.farm_id
 LEFT JOIN atlas.planned_work_occurrences o
   ON o.id=q.planned_occurrence_id AND o.farm_id=q.farm_id
 LEFT JOIN LATERAL (
   SELECT x.id,x.work_state FROM atlas.work_items x
   WHERE x.organization_id=p_organization_id
     AND x.source_object_type IN ('legacy_task','legacy_task_slice')
     AND x.source_object_id=t.id ORDER BY x.id LIMIT 1
 ) w ON true
 LEFT JOIN atlas.company_work_legacy_task_reviews_v1 r
   ON r.organization_id=p_organization_id AND r.source_task_id=t.id
 WHERE p_after_queue_item_id IS NULL OR q.id>p_after_queue_item_id
 ORDER BY q.id LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'queueItemId',id,'queueKey',queue_key,'position',position,
 'queueState',state,'queueUpdatedAt',updated_at,
 'originalDueDateHistoricalOnly',original_due_date,
 'sourceTaskId',task_id,'sourceTaskTitle',task_title,
 'sourceTaskStatus',task_status,'sourceOccurrenceId',planned_occurrence_id,
 'sourceOccurrenceTitle',occurrence_title,'sourceOccurrenceState',occurrence_state,
 'sourceLinkedCanonicalWorkId',original_work_id,
 'sourceLinkedCanonicalWorkState',original_work_state,
 'ownerReviewDecision',owner_decision,'ownerReviewTargetWorkItemId',reviewed_work_id,
 'queueDisagreesWithOldTask',coalesce(state='active' AND task_status IN ('done','archived'),false),
 'taskLinkedDecisionPossible',task_id IS NOT NULL AND task_title IS NOT NULL
   AND original_work_id IS NULL AND owner_decision IS NULL,
 'noTaskMeansSeparateOriginalNeedReview',task_id IS NULL
 ) ORDER BY id) FILTER(WHERE rn<=p_limit),'[]'::jsonb),
 coalesce(bool_or(rn>p_limit),false),
 (array_agg(id ORDER BY id) FILTER(WHERE rn=p_limit))[1]
 INTO rows,more,cursor FROM page;
 RETURN jsonb_build_object('ok',true,
 'contractVersion','company_work_legacy_queue_owner_v1',
 'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
 'items',rows,'hasMore',more,
 'nextAfterQueueItemId',CASE WHEN more THEN cursor ELSE NULL END,
 'ownerReviewOnly',true,'queueIsNotCurrentWorkAuthority',true,
 'noCanonicalWorkCreated',true,'noResponsibilityEstablished',true,
 'noScheduleOrQueueStateChanged',true);
END;$function$;

-- Task-linked queue evidence may be explicitly matched to an existing Work
-- original or declared no longer current. The queue does NOT create Work.
-- Queue-only occurrences cannot be falsely recorded as a reviewed Task.
CREATE OR REPLACE FUNCTION atlas.decide_company_work_legacy_queue_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_queue_item_id uuid,
 p_expected_queue_state text,p_expected_queue_updated_at timestamptz,
 p_expected_task_id uuid,p_expected_task_status text,p_expected_task_title text,
 p_decision text,p_reason text,p_existing_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE actor uuid; q atlas.task_release_queue_items%rowtype;
 t atlas.tasks%rowtype; reviewed atlas.company_work_legacy_task_reviews_v1%rowtype;
 original_work uuid; target_work uuid; original_person uuid; executor_label text;
BEGIN
 actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF actor IS NULL OR p_queue_item_id IS NULL OR p_expected_task_id IS NULL
 OR p_expected_queue_state IS NULL OR p_expected_queue_updated_at IS NULL
 OR p_expected_task_status IS NULL OR nullif(btrim(coalesce(p_expected_task_title,'')),'') IS NULL
 OR p_decision IS NULL OR p_decision NOT IN ('matched_existing_work','not_current')
 OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1200
 OR (p_decision='matched_existing_work' AND p_existing_work_item_id IS NULL)
 OR (p_decision='not_current' AND p_existing_work_item_id IS NOT NULL)
 THEN RAISE EXCEPTION 'Explicit exact source, decision and owner reason required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.queue_owner_reconciliation:'||p_organization_id::text||':'||p_expected_task_id::text,0));
 SELECT item.* INTO q FROM atlas.task_release_queue_items item
 JOIN atlas.farms farm ON farm.id=item.farm_id AND farm.organization_id=p_organization_id
 WHERE item.id=p_queue_item_id FOR SHARE OF item;
 IF q.id IS NULL OR q.state IS DISTINCT FROM p_expected_queue_state
 OR q.updated_at IS DISTINCT FROM p_expected_queue_updated_at
 OR q.task_id IS DISTINCT FROM p_expected_task_id
 THEN RAISE EXCEPTION 'Queue evidence changed; reload the source' USING ERRCODE='23514';
 END IF;
 SELECT * INTO t FROM atlas.tasks
 WHERE id=q.task_id AND farm_id=q.farm_id AND organization_id=p_organization_id FOR SHARE;
 IF t.id IS NULL OR t.status IS DISTINCT FROM p_expected_task_status
 OR t.title IS DISTINCT FROM p_expected_task_title
 THEN RAISE EXCEPTION 'Task source changed; reload the source' USING ERRCODE='23514';
 END IF;
 SELECT * INTO reviewed FROM atlas.company_work_legacy_task_reviews_v1
 WHERE organization_id=p_organization_id AND source_task_id=t.id;
 IF reviewed.id IS NOT NULL THEN
   IF reviewed.native_ledger_id IS DISTINCT FROM p_ledger_id THEN
     RAISE EXCEPTION 'Source already reviewed in different Ledger' USING ERRCODE='42501';
   END IF;
   RETURN jsonb_build_object('ok',true,
     'contractVersion','company_work_legacy_queue_owner_decision_v1',
     'state','already_reviewed','queueItemId',q.id,'sourceTaskId',t.id,
     'decision',reviewed.decision_kind,'workItemId',reviewed.target_work_item_id,
     'newWorkCreated',false,'queueStateChanged',false);
 END IF;
 SELECT id INTO original_work FROM atlas.work_items
 WHERE organization_id=p_organization_id
 AND source_object_type IN ('legacy_task','legacy_task_slice')
 AND source_object_id=t.id ORDER BY id LIMIT 1;
 IF original_work IS NOT NULL THEN
   RAISE EXCEPTION 'Original already has canonical Work; review that Work'
     USING ERRCODE='23505';
 END IF;
 IF p_decision='matched_existing_work' THEN
   SELECT id INTO target_work FROM atlas.work_items
   WHERE id=p_existing_work_item_id AND organization_id=p_organization_id
     AND work_state IN ('open','completed');
   IF target_work IS NULL THEN
     RAISE EXCEPTION 'Selected canonical Work unavailable' USING ERRCODE='42501';
   END IF;
 END IF;
 -- Resolve historical source attribution through one existing canonical Principal,
 -- never by resurrecting Organization Membership as Person authority.
 -- If current organization-specific canonical Person reality is unproven,
 -- preserve historical Task evidence and leave original_person NULL.
 SELECT atlas.organization_person_canonical_reality_v1(p_organization_id,p.person_id)
 INTO original_person FROM atlas.principals p
 WHERE p.user_id=t.assigned_user_id AND p.person_id IS NOT NULL;
 executor_label:=coalesce(t.metadata->>'executor_label',t.metadata->>'assigned_to');
 INSERT INTO atlas.company_work_legacy_task_reviews_v1(
 organization_id,native_ledger_id,source_task_id,decision_kind,target_work_item_id,
 decided_by_person_id,source_title_snapshot,source_status_snapshot,
 source_metadata_snapshot,source_note_snapshot,original_executor_label,
 original_assignee_canonical_person_id,owner_reason)
 VALUES(p_organization_id,p_ledger_id,t.id,p_decision,target_work,actor,t.title,t.status,
 coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object('legacyQueueReview',
 jsonb_build_object('queueItemId',q.id,'queueKey',q.queue_key,
 'queueStateAtDecision',q.state,'queueUpdatedAt',q.updated_at,
 'sourceOccurrenceId',q.planned_occurrence_id)),
 t.note,executor_label,original_person,btrim(p_reason));
 IF target_work IS NOT NULL AND NOT EXISTS (
 SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
 WHERE rel.organization_id=p_organization_id AND rel.ledger_id=p_ledger_id
 AND rel.work_item_id=target_work AND rel.attribution_state='active') THEN
 INSERT INTO atlas.company_work_native_ledger_relevance(
 organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
 attestation_source_ref,attestation_reason,established_by_person_id)
 VALUES(p_organization_id,target_work,p_ledger_id,'serves_purpose','owner_attested',
 'legacy_queue_task:'||t.id::text,btrim(p_reason),actor);
 END IF;
 RETURN jsonb_build_object('ok',true,
 'contractVersion','company_work_legacy_queue_owner_decision_v1',
 'state',CASE WHEN target_work IS NULL THEN 'not_current' ELSE 'matched' END,
 'queueItemId',q.id,'sourceTaskId',t.id,'decision',p_decision,
 'workItemId',target_work,'newWorkCreated',false,
 'queueStateChanged',false,'legacyTaskChanged',false,
 'responsibilityEstablished',false,'planCreated',false,'physicalResultCreated',false);
END;$function$;

-- Existing Atlas browser contract: public PostgREST transport -> native atlas
-- governor. The public functions are INVOKER-only, have no independent
-- authority, and never expose tables or bypass the private owner check.
CREATE OR REPLACE FUNCTION public.company_work_legacy_queue_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_limit integer DEFAULT 100,
 p_after_queue_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SET search_path TO ''
AS $function$
 SELECT atlas.company_work_legacy_queue_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_limit,p_after_queue_item_id);
$function$;

CREATE OR REPLACE FUNCTION public.decide_company_work_legacy_queue_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_queue_item_id uuid,
 p_expected_queue_state text,p_expected_queue_updated_at timestamptz,
 p_expected_task_id uuid,p_expected_task_status text,p_expected_task_title text,
 p_decision text,p_reason text,p_existing_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SET search_path TO ''
AS $function$
 SELECT atlas.decide_company_work_legacy_queue_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_queue_item_id,p_expected_queue_state,
   p_expected_queue_updated_at,p_expected_task_id,p_expected_task_status,
   p_expected_task_title,p_decision,p_reason,p_existing_work_item_id);
$function$;

REVOKE ALL ON FUNCTION atlas.company_work_legacy_queue_owner_self_api_v1(uuid,uuid,integer,uuid) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION atlas.decide_company_work_legacy_queue_owner_self_api_v1(uuid,uuid,uuid,text,timestamptz,uuid,text,text,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.company_work_legacy_queue_owner_self_api_v1(uuid,uuid,integer,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.decide_company_work_legacy_queue_owner_self_api_v1(uuid,uuid,uuid,text,timestamptz,uuid,text,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.company_work_legacy_queue_owner_self_api_v1(uuid,uuid,integer,uuid) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.decide_company_work_legacy_queue_owner_self_api_v1(uuid,uuid,uuid,text,timestamptz,uuid,text,text,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.company_work_legacy_queue_owner_self_api_v1(uuid,uuid,integer,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_company_work_legacy_queue_owner_self_api_v1(uuid,uuid,uuid,text,timestamptz,uuid,text,text,text,text,uuid) TO authenticated;
COMMIT;
