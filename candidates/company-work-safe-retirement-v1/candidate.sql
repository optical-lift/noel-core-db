-- Build 5: governed Company Work retirement, distinct from completion.
-- Source-only candidate. Production requires reviewed source generation,
-- protected schema-clone validation and manual release.
BEGIN;

-- Preserve every deliberate requirement transfer independently of mutable
-- link rows. This is a private audit, never a browser table.
CREATE TABLE atlas.company_work_retirement_requirement_transfers_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  source_work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  source_requirement_link_id uuid NOT NULL UNIQUE
    REFERENCES atlas.work_requirement_links(id) ON DELETE RESTRICT,
  requirement_id uuid NOT NULL REFERENCES atlas.work_requirements(id) ON DELETE RESTRICT,
  replacement_work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 12 AND 1200),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (source_work_item_id<>replacement_work_item_id)
);
ALTER TABLE atlas.company_work_retirement_requirement_transfers_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.company_work_retirement_requirement_transfers_v1
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE atlas.company_work_retirement_requirement_transfers_v1 TO service_role;

CREATE TABLE atlas.company_work_retirement_time_contract_cancellations_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  source_work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  time_contract_id uuid NOT NULL UNIQUE
    REFERENCES atlas.work_time_contracts(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 12 AND 1200),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE atlas.company_work_retirement_time_contract_cancellations_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.company_work_retirement_time_contract_cancellations_v1
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE atlas.company_work_retirement_time_contract_cancellations_v1
  TO service_role;

-- Privileged implementation helper: callers must pass the owner-only self API.
-- VOLATILE is required for snapshot visibility: the owner retirement command
-- reconciles linked rows and then re-reads them in the same SQL statement.
-- A STABLE helper would see the pre-reconciliation snapshot and reject valid
-- retirement (also in the BEFORE UPDATE cancellation guard).
CREATE FUNCTION atlas.company_work_retirement_dependency_snapshot_v1(
 p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT jsonb_build_object(
  'workItemId',w.id,
  'workState',w.work_state,
  'requirements',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'linkId',l.id,'requirementId',l.requirement_id,
      'role',l.link_role,'requirementState',r.state,
      'requirementSummary',r.summary
    ) ORDER BY l.id)
    FROM atlas.work_requirement_links l
    JOIN atlas.work_requirements r ON r.id=l.requirement_id
    WHERE l.work_item_id=w.id AND l.active
  ),'[]'::jsonb),
  'relations',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'relationId',r.id,'kind',r.relation_kind,
      'fromWorkItemId',r.from_work_item_id,'toWorkItemId',r.to_work_item_id
    ) ORDER BY r.id)
    FROM atlas.work_item_relations r
    WHERE r.active AND (r.from_work_item_id=w.id OR r.to_work_item_id=w.id)
  ),'[]'::jsonb),
  'pendingOfferIds',coalesce((
    SELECT jsonb_agg(x.id ORDER BY x.id) FROM (
      SELECT id FROM atlas.company_work_initial_responsibility_offers
      WHERE work_item_id=w.id AND offer_state='offered'
      UNION ALL
      SELECT id FROM atlas.company_work_participation_offers
      WHERE work_item_id=w.id AND offer_state='offered'
      UNION ALL
      SELECT id FROM atlas.company_work_responsibility_transfer_offers
      WHERE work_item_id=w.id AND offer_state='offered'
    ) x
  ),'[]'::jsonb),
  'projectionIds',coalesce((
    SELECT jsonb_agg(s.projection_id ORDER BY s.projection_id)
    FROM atlas.worker_week_projection_sources s
    WHERE s.work_item_id=w.id
  ),'[]'::jsonb),
  'executionResultIds',coalesce((
    SELECT jsonb_agg(r.id ORDER BY r.id)
    FROM atlas.work_execution_results r WHERE r.work_item_id=w.id
  ),'[]'::jsonb),
  'activeTimeContractIds',coalesce((
    SELECT jsonb_agg(t.id ORDER BY t.id)
    FROM atlas.work_time_contracts t
    WHERE t.work_item_id=w.id AND t.contract_state='active'
  ),'[]'::jsonb),
  'automaticUnwind',jsonb_build_object(
    'activeAllocationIds',coalesce((
      SELECT jsonb_agg(a.id ORDER BY a.id)
      FROM atlas.work_allocations a
      WHERE a.work_item_id=w.id AND a.state='active'
    ),'[]'::jsonb),
    'activePlanIds',coalesce((
      SELECT jsonb_agg(p.id ORDER BY p.id)
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.plan_state IN ('active','needs_replan')
    ),'[]'::jsonb),
    'activeAdapterIds',coalesce((
      SELECT jsonb_agg(a.id ORDER BY a.id)
      FROM atlas.work_execution_adapters a
      WHERE a.work_item_id=w.id AND a.state='active'
    ),'[]'::jsonb)
  ),
  'legacySource',CASE WHEN w.source_object_type IN ('legacy_task','legacy_task_slice')
    THEN (SELECT jsonb_build_object(
      'sourceTaskId',t.id,'sourceTaskStatus',t.status,
      'sourceTaskRemainsIndependent',true,
      'sameSourceWork',coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'workItemId',s.id,'sourceKind',s.source_object_type,
          'workState',s.work_state
        ) ORDER BY s.id)
        FROM atlas.work_items s
        WHERE s.organization_id=w.organization_id
          AND s.source_object_id=w.source_object_id AND s.id<>w.id
      ),'[]'::jsonb)
    ) FROM atlas.tasks t
      WHERE t.id=w.source_object_id AND t.organization_id=w.organization_id)
    ELSE NULL END
 )
 FROM atlas.work_items w WHERE w.id=p_work_item_id;
$fn$;
REVOKE ALL ON FUNCTION atlas.company_work_retirement_dependency_snapshot_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.company_work_retirement_preflight_self_api_v1(
 p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_org uuid;
 v_impact jsonb;
 v_blockers integer;
BEGIN
 IF auth.uid() IS NULL OR p_work_item_id IS NULL THEN
   RAISE EXCEPTION 'Authenticated owner and exact Work required' USING ERRCODE='42501';
 END IF;
 SELECT organization_id INTO v_org FROM atlas.work_items WHERE id=p_work_item_id;
 IF v_org IS NULL OR NOT atlas.is_effective_organization_owner_v1(v_org) THEN
   RAISE EXCEPTION 'Owner authority over the Work organization required' USING ERRCODE='42501';
 END IF;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(p_work_item_id);
 v_blockers:=jsonb_array_length(v_impact->'requirements')
   +jsonb_array_length(v_impact->'relations')
   +jsonb_array_length(v_impact->'pendingOfferIds')
   +jsonb_array_length(v_impact->'projectionIds')
   +jsonb_array_length(v_impact->'executionResultIds')
   +jsonb_array_length(v_impact->'activeTimeContractIds');
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','company_work_safe_retirement_v1',
   'impact',v_impact,'impactToken',md5(v_impact::text),
   'blockingDependencyCount',v_blockers,
   'retirableWithoutReconciliation',v_blockers=0
 );
END
$fn$;
REVOKE ALL ON FUNCTION atlas.company_work_retirement_preflight_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.company_work_retirement_preflight_self_api_v1(uuid)
 TO authenticated;

-- Cancelling through ANY code path must not silently strand an active
-- requirement, a pending handoff, projected Work, or a worker result.
-- Active allocations/plans/adapters are handled by the existing governed
-- 'not_relevant' adjudicator and are explicitly reported by preflight.
CREATE FUNCTION atlas.guard_company_work_cancel_dependencies_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_impact jsonb;
BEGIN
 IF old.work_state IS NOT DISTINCT FROM new.work_state
    OR new.work_state<>'cancelled' THEN RETURN new; END IF;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(old.id);
 IF jsonb_array_length(v_impact->'requirements')>0
    OR jsonb_array_length(v_impact->'relations')>0
    OR jsonb_array_length(v_impact->'pendingOfferIds')>0
    OR jsonb_array_length(v_impact->'projectionIds')>0
    OR jsonb_array_length(v_impact->'executionResultIds')>0
    OR jsonb_array_length(v_impact->'activeTimeContractIds')>0
 THEN
   RAISE EXCEPTION 'Company Work cancellation requires dependency reconciliation'
     USING ERRCODE='23514',
       DETAIL='Use owner preflight; preserve linked obligations, worker reporting and shared sources.';
 END IF;
 RETURN new;
END
$fn$;
REVOKE ALL ON FUNCTION atlas.guard_company_work_cancel_dependencies_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER guard_company_work_cancel_dependencies_v1
 BEFORE UPDATE OF work_state ON atlas.work_items
 FOR EACH ROW WHEN (old.work_state IS DISTINCT FROM new.work_state AND new.work_state='cancelled')
 EXECUTE FUNCTION atlas.guard_company_work_cancel_dependencies_v1();

-- An owner may redirect a 'resolves' requirement only to an open, same-unit
-- slice of the VERY SAME legacy source Task. No invented equivalence, no
-- automatic responsibility change, no deletion of source/provenance.
-- All other dependencies must be separately reconciled before retirement.
CREATE FUNCTION atlas.retire_company_work_with_reconciliation_self_api_v1(
 p_work_item_id uuid,p_impact_token text,p_reconciliation jsonb,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_impact jsonb;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
 v_transfer jsonb;
 v_link atlas.work_requirement_links%ROWTYPE;
 v_target atlas.work_items%ROWTYPE;
 v_time_contract atlas.work_time_contracts%ROWTYPE;
 v_requirement_transfers jsonb:=p_reconciliation->'requirementTransfers';
 v_cancel_time_contract_ids jsonb:=p_reconciliation->'cancelTimeContractIds';
 v_seen uuid[]:=ARRAY[]::uuid[];
 v_time_seen uuid[]:=ARRAY[]::uuid[];
 v_link_id uuid;
 v_target_id uuid;
 v_time_id uuid;
 v_time_json jsonb;
 v_count integer:=0;
 v_time_count integer:=0;
 v_receipt jsonb;
BEGIN
 IF auth.uid() IS NULL OR p_work_item_id IS NULL OR v_reason IS NULL
    OR length(v_reason) NOT BETWEEN 12 AND 1200
    OR p_impact_token IS NULL OR length(p_impact_token)<>32
    OR jsonb_typeof(p_reconciliation) IS DISTINCT FROM 'object'
    OR jsonb_typeof(v_requirement_transfers) IS DISTINCT FROM 'array'
    OR jsonb_typeof(v_cancel_time_contract_ids) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Owner, impact token, reconciliation array and reason required'
   USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.retirement:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR NOT atlas.is_effective_organization_owner_v1(v_work.organization_id)
 THEN RAISE EXCEPTION 'Owner Work authority required' USING ERRCODE='42501'; END IF;
 IF v_work.work_state='cancelled' THEN
   RETURN jsonb_build_object('ok',true,'state','already_cancelled',
     'workItemId',v_work.id,'newDecisionRecorded',false);
 END IF;
 IF v_work.work_state<>'open' THEN
   RAISE EXCEPTION 'Only open invalid Work can be retired' USING ERRCODE='23514';
 END IF;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
 IF md5(v_impact::text)<>p_impact_token THEN
   RAISE EXCEPTION 'Retirement impact changed; refresh owner preflight'
     USING ERRCODE='40001'; END IF;
 IF jsonb_array_length(v_requirement_transfers)>100 OR
    jsonb_array_length(v_requirement_transfers)<>
      jsonb_array_length(v_impact->'requirements') THEN
   RAISE EXCEPTION 'Exactly one explicit transfer per active requirement link required'
     USING ERRCODE='23514';
 END IF;
 IF jsonb_array_length(v_impact->'relations')>0
    OR jsonb_array_length(v_impact->'pendingOfferIds')>0
    OR jsonb_array_length(v_impact->'projectionIds')>0
    OR jsonb_array_length(v_impact->'executionResultIds')>0
 THEN RAISE EXCEPTION 'Other Work dependencies require separate reconciliation'
   USING ERRCODE='23514'; END IF;
 IF jsonb_array_length(v_cancel_time_contract_ids)>100 OR
    jsonb_array_length(v_cancel_time_contract_ids)<>
      jsonb_array_length(v_impact->'activeTimeContractIds') THEN
   RAISE EXCEPTION 'Every obsolete active time contract needs an exact owner decision'
     USING ERRCODE='23514';
 END IF;
 FOR v_transfer IN SELECT value FROM jsonb_array_elements(v_requirement_transfers)
 LOOP
   IF jsonb_typeof(v_transfer)<>'object'
     OR coalesce(v_transfer->>'linkId','') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     OR coalesce(v_transfer->>'replacementWorkItemId','') !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   THEN RAISE EXCEPTION 'Exact requirement link and replacement Work IDs required'
      USING ERRCODE='22023'; END IF;
   v_link_id:=(v_transfer->>'linkId')::uuid;
   v_target_id:=(v_transfer->>'replacementWorkItemId')::uuid;
   IF v_link_id=ANY(v_seen) THEN RAISE EXCEPTION 'Duplicate requirement disposition'
     USING ERRCODE='23514'; END IF;
   v_seen:=array_append(v_seen,v_link_id);
   SELECT * INTO v_link FROM atlas.work_requirement_links
    WHERE id=v_link_id AND work_item_id=v_work.id AND organization_id=v_work.organization_id
      AND active AND link_role='resolves' FOR UPDATE;
   IF v_link.id IS NULL THEN RAISE EXCEPTION 'Active resolves requirement link required'
     USING ERRCODE='23514'; END IF;
   SELECT * INTO v_target FROM atlas.work_items WHERE id=v_target_id
     AND organization_id=v_work.organization_id AND work_state='open' FOR KEY SHARE;
   IF v_target.id IS NULL OR v_target.id=v_work.id
     OR v_target.organization_unit_id IS DISTINCT FROM v_work.organization_unit_id
     OR v_work.source_object_type<>'legacy_task'
     OR v_target.source_object_type<>'legacy_task_slice'
     OR v_target.source_object_id IS DISTINCT FROM v_work.source_object_id
   THEN RAISE EXCEPTION 'Transfer requires open same-unit slice of exact source Task'
     USING ERRCODE='23514'; END IF;
   INSERT INTO atlas.work_requirement_links(
     organization_id,requirement_id,work_item_id,link_role,active,metadata
   ) VALUES(v_work.organization_id,v_link.requirement_id,v_target.id,
     'resolves',true,jsonb_build_object(
       'source','owner_company_work_retirement_reconciliation_v1',
       'transferredFromWorkItemId',v_work.id,'sourceLinkId',v_link.id,
       'ownerReason',v_reason))
   ON CONFLICT (requirement_id,work_item_id,link_role) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM atlas.work_requirement_links l
       WHERE l.requirement_id=v_link.requirement_id AND l.work_item_id=v_target.id
         AND l.link_role='resolves' AND l.active) THEN
     RAISE EXCEPTION 'Replacement requirement link not active' USING ERRCODE='23514';
   END IF;
   UPDATE atlas.work_requirement_links SET active=false,
     metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
       'reconciledByOwnerOnRetirement',true,
       'replacementWorkItemId',v_target.id,
       'retirementReason',v_reason)
     WHERE id=v_link.id AND active;
   IF NOT FOUND THEN RAISE EXCEPTION 'Requirement reconciliation lost active link'
       USING ERRCODE='40001'; END IF;
   INSERT INTO atlas.company_work_retirement_requirement_transfers_v1(
     organization_id,source_work_item_id,source_requirement_link_id,
     requirement_id,replacement_work_item_id,actor_user_id,reason
   ) VALUES(v_work.organization_id,v_work.id,v_link.id,
     v_link.requirement_id,v_target.id,auth.uid(),v_reason);
   v_count:=v_count+1;
 END LOOP;
 FOR v_time_json IN SELECT value FROM jsonb_array_elements(v_cancel_time_contract_ids)
 LOOP
   IF jsonb_typeof(v_time_json)<>'string'
     OR trim(both '"' from v_time_json::text) !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   THEN RAISE EXCEPTION 'Exact obsolete time contract ID required'
     USING ERRCODE='22023'; END IF;
   v_time_id:=(v_time_json #>> '{}')::uuid;
   IF v_time_id=ANY(v_time_seen) THEN
     RAISE EXCEPTION 'Duplicate time contract disposition' USING ERRCODE='23514';
   END IF;
   v_time_seen:=array_append(v_time_seen,v_time_id);
   SELECT * INTO v_time_contract FROM atlas.work_time_contracts t
     WHERE t.id=v_time_id AND t.work_item_id=v_work.id
       AND t.organization_id=v_work.organization_id AND t.contract_state='active'
     FOR UPDATE;
   IF v_time_contract.id IS NULL OR
     v_time_contract.source_kind IS DISTINCT FROM 'legacy_task' OR
     v_time_contract.source_id IS DISTINCT FROM v_work.source_object_id OR
     v_work.source_object_type<>'legacy_task'
   THEN RAISE EXCEPTION 'Only the parent legacy Task time contract may be cancelled here'
     USING ERRCODE='23514'; END IF;
   UPDATE atlas.work_time_contracts SET contract_state='cancelled',
     metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
       'cancelledForInvalidWorkRetirement',true,'ownerReason',v_reason),
     updated_at=now()
     WHERE id=v_time_id AND contract_state='active';
   IF NOT FOUND THEN RAISE EXCEPTION 'Time contract reconciliation lost authority'
     USING ERRCODE='40001'; END IF;
   INSERT INTO atlas.company_work_retirement_time_contract_cancellations_v1(
     organization_id,source_work_item_id,time_contract_id,actor_user_id,reason
   ) VALUES(v_work.organization_id,v_work.id,v_time_id,auth.uid(),v_reason);
   v_time_count:=v_time_count+1;
 END LOOP;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
 IF jsonb_array_length(v_impact->'requirements')>0 OR
    jsonb_array_length(v_impact->'activeTimeContractIds')>0 THEN
   RAISE EXCEPTION 'Unreconciled requirements or time contracts remain' USING ERRCODE='23514';
 END IF;
 -- The preexisting institutional adjudicator owns cancellation, allocation
 -- release, plan withdrawal and its idempotent management event.
 v_receipt:=atlas.organization_management_adjudicate_company_work_api_v1(
   v_work.id,'not_relevant',
   jsonb_build_object('retirementContract','company_work_safe_retirement_v1',
     'transferredRequirementCount',v_count,
     'cancelledObsoleteTimeContractCount',v_time_count,
     'sourceTaskPreserved',true),
   v_reason,NULL,'safe-retirement-v1:'||v_work.id::text);
 IF v_receipt->>'companyWorkState'<>'cancelled' THEN
   RAISE EXCEPTION 'Institutional cancellation receipt not proven'
     USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object(
   'ok',true,'state','retired','workItemId',v_work.id,
   'reconciledRequirementCount',v_count,
   'cancelledObsoleteTimeContractCount',v_time_count,
   'sourceTaskPreserved',true,'legacySourceStateUnchanged',true,
   'managerAdjudicationId',v_receipt->>'adjudicationId',
   'workerCompletionRecorded',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.retire_company_work_with_reconciliation_self_api_v1(uuid,text,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.retire_company_work_with_reconciliation_self_api_v1(uuid,text,jsonb,text)
 TO authenticated;

-- Explicit Data API surfaces: invoker transport, scoped definer implementation.
CREATE FUNCTION public.company_work_retirement_preflight_self_api_v1(
 p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.company_work_retirement_preflight_self_api_v1(p_work_item_id);
$fn$;
REVOKE ALL ON FUNCTION public.company_work_retirement_preflight_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.company_work_retirement_preflight_self_api_v1(uuid)
 TO authenticated;

CREATE FUNCTION public.retire_company_work_with_reconciliation_self_api_v1(
 p_work_item_id uuid,p_impact_token text,p_reconciliation jsonb,p_reason text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT atlas.retire_company_work_with_reconciliation_self_api_v1(
   p_work_item_id,p_impact_token,p_reconciliation,p_reason);
$fn$;
REVOKE ALL ON FUNCTION public.retire_company_work_with_reconciliation_self_api_v1(uuid,text,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.retire_company_work_with_reconciliation_self_api_v1(uuid,text,jsonb,text)
 TO authenticated;
COMMIT;
