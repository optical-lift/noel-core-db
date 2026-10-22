-- Atlas Build 5: owner Delete task / secluded Trash for unwanted canonical Company Work.
-- No hard DELETE. This is not worker completion, nor a replacement obligation.
-- Migration is a reviewed source candidate; release through the existing guarded DB workflow.
BEGIN;

CREATE TABLE atlas.company_work_trash_decisions_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL UNIQUE REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL,
  actor_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  original_work_snapshot jsonb NOT NULL,
  original_impact_snapshot jsonb NOT NULL,
  unlinked_requirement_link_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
  cancelled_requirement_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
  cancelled_time_contract_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
  withdrawn_initial_offer_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
  withdrawn_participation_offer_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
  withdrawn_transfer_offer_ids uuid[] NOT NULL DEFAULT ARRAY[]::uuid[],
  management_adjudication_id uuid NOT NULL,
  trashed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE atlas.company_work_trash_decisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.company_work_trash_decisions_v1
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE atlas.company_work_trash_decisions_v1 TO service_role;

-- A deleted source cannot silently generate a replacement canonical Work.
-- It remains possible to address a genuinely new source or a distinct task.
CREATE OR REPLACE FUNCTION atlas.guard_trashed_company_work_reappearance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF TG_OP='UPDATE' THEN
    IF old.work_state='cancelled'
       AND old.metadata->>'deletedFromActiveViews'='true'
       AND new.work_state<>'cancelled' THEN
      RAISE EXCEPTION 'Deleted Work cannot silently return to active work'
        USING ERRCODE='23514';
    END IF;
  END IF;
  IF new.source_object_type IS NOT NULL AND new.source_object_id IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM atlas.company_work_trash_decisions_v1 d
       JOIN atlas.work_items w ON w.id=d.work_item_id
       WHERE w.id<>new.id
         AND w.source_object_type=new.source_object_type
         AND w.source_object_id=new.source_object_id
     ) THEN
    RAISE EXCEPTION 'Source already belongs to deleted canonical Work; no replacement may be created'
      USING ERRCODE='23514';
  END IF;
  RETURN new;
END;
$fn$;
CREATE TRIGGER guard_trashed_company_work_reappearance_v1
  BEFORE INSERT OR UPDATE OF source_object_type,source_object_id,work_state
  ON atlas.work_items FOR EACH ROW
  EXECUTE FUNCTION atlas.guard_trashed_company_work_reappearance_v1();

CREATE OR REPLACE FUNCTION atlas.delete_company_work_owner_self_api_v1(
  p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_actor_person uuid;
  v_impact jsonb;
  v_link record;
  v_contract record;
  v_offer record;
  v_receipt jsonb;
  v_decision_id uuid;
  v_now timestamptz := now();
  v_reason text := 'Deleted from active work by organization owner';
  v_link_ids uuid[] := ARRAY[]::uuid[];
  v_req_ids uuid[] := ARRAY[]::uuid[];
  v_contract_ids uuid[] := ARRAY[]::uuid[];
  v_initial_ids uuid[] := ARRAY[]::uuid[];
  v_participation_ids uuid[] := ARRAY[]::uuid[];
  v_transfer_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF auth.uid() IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Sign in and select an exact task' USING ERRCODE='42501';
  END IF;
  -- Serializes with existing receiver acceptance of an initial Work offer.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR NOT atlas.is_effective_organization_owner_v1(v_work.organization_id) THEN
    RAISE EXCEPTION 'Organization owner authority required' USING ERRCODE='42501';
  END IF;
  v_actor_person := atlas.current_person_id_v1();
  IF v_actor_person IS NULL THEN
    RAISE EXCEPTION 'Canonical Person required' USING ERRCODE='42501';
  END IF;
  SELECT id INTO v_decision_id FROM atlas.company_work_trash_decisions_v1
    WHERE work_item_id=v_work.id;
  IF v_decision_id IS NOT NULL THEN
    IF v_work.work_state<>'cancelled' THEN
      RAISE EXCEPTION 'Trash record and Work state disagree' USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object('ok',true,'contractVersion','company_work_trash_v1',
      'state','already_trashed','workItemId',v_work.id,'trashDecisionId',v_decision_id);
  END IF;
  IF v_work.work_state<>'open' THEN
    RAISE EXCEPTION 'Only open Work can be deleted from active lists' USING ERRCODE='23514';
  END IF;
  v_impact := atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
  -- Result, relation, and worker projection evidence must never be silently erased.
  IF jsonb_array_length(v_impact->'relations')>0 OR
     jsonb_array_length(v_impact->'projectionIds')>0 OR
     jsonb_array_length(v_impact->'executionResultIds')>0 THEN
    RAISE EXCEPTION 'This Work has shared dependencies or worker results; owner review is required'
      USING ERRCODE='23514';
  END IF;

  -- An offer is not accepted responsibility. Withdraw it so the recipient's
  -- Today cannot continue to offer Work that its owner has removed.
  UPDATE atlas.company_work_initial_responsibility_offers o
    SET offer_state='withdrawn',resolved_at=v_now,resolution_reason=v_reason
    WHERE o.work_item_id=v_work.id AND o.offer_state='offered';
  SELECT coalesce(array_agg(id ORDER BY id),ARRAY[]::uuid[]) INTO v_initial_ids
    FROM atlas.company_work_initial_responsibility_offers
    WHERE work_item_id=v_work.id AND offer_state='withdrawn' AND resolved_at=v_now
      AND resolution_reason=v_reason;

  -- Preserve the rule that only a responsible offerer can withdraw an
  -- accepted-work participation or transfer proposal.
  IF EXISTS (SELECT 1 FROM atlas.company_work_participation_offers
       WHERE work_item_id=v_work.id AND offer_state='offered'
         AND offered_by_person_entity_id<>v_actor_person)
    OR EXISTS (SELECT 1 FROM atlas.company_work_responsibility_transfer_offers
       WHERE work_item_id=v_work.id AND offer_state='offered'
         AND offered_by_person_entity_id<>v_actor_person) THEN
    RAISE EXCEPTION 'An active responsible Person must withdraw their offer first'
      USING ERRCODE='23514';
  END IF;
  UPDATE atlas.company_work_participation_offers
    SET offer_state='withdrawn',resolved_at=v_now,
        resolved_by_person_entity_id=v_actor_person,
        resolved_by_membership_id_compatibility=offered_by_membership_id_compatibility,
        resolution_reason=v_reason
    WHERE work_item_id=v_work.id AND offer_state='offered';
  SELECT coalesce(array_agg(id ORDER BY id),ARRAY[]::uuid[]) INTO v_participation_ids
    FROM atlas.company_work_participation_offers
    WHERE work_item_id=v_work.id AND offer_state='withdrawn'
      AND resolved_at=v_now AND resolution_reason=v_reason;
  UPDATE atlas.company_work_responsibility_transfer_offers
    SET offer_state='withdrawn',resolved_at=v_now,
        resolved_by_person_entity_id=v_actor_person,
        resolved_by_membership_id_compatibility=offered_by_membership_id_compatibility,
        resolution_reason=v_reason
    WHERE work_item_id=v_work.id AND offer_state='offered';
  SELECT coalesce(array_agg(id ORDER BY id),ARRAY[]::uuid[]) INTO v_transfer_ids
    FROM atlas.company_work_responsibility_transfer_offers
    WHERE work_item_id=v_work.id AND offer_state='withdrawn'
      AND resolved_at=v_now AND resolution_reason=v_reason;

  -- Unlink this Work without cancelling any requirement that is still
  -- independently served by another open Work item.
  FOR v_link IN
    SELECT l.id AS link_id,l.requirement_id,l.link_role,
           r.state AS requirement_state,r.source_object_type AS source_kind,
           r.source_object_id AS source_id
    FROM atlas.work_requirement_links l
    JOIN atlas.work_requirements r ON r.id=l.requirement_id
    WHERE l.work_item_id=v_work.id AND l.active
    ORDER BY l.id FOR UPDATE OF l,r
  LOOP
    IF v_link.link_role<>'resolves' THEN
      RAISE EXCEPTION 'Non-resolution requirement link needs separate owner review'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM atlas.work_requirement_links other
      WHERE other.requirement_id=v_link.requirement_id
        AND other.work_item_id<>v_work.id AND other.active
    ) THEN
      IF v_link.requirement_state<>'active'
         OR v_link.source_kind IS DISTINCT FROM v_work.source_object_type
         OR v_link.source_id IS DISTINCT FROM v_work.source_object_id
         OR v_work.source_object_id IS NULL THEN
        RAISE EXCEPTION 'An independent requirement still needs an owner decision'
          USING ERRCODE='23514';
      END IF;
      UPDATE atlas.work_requirements SET state='cancelled',cancelled_at=v_now,
        metadata=coalesce(metadata,'{}'::jsonb)||
          jsonb_build_object('cancelledByCompanyWorkTrashV1',true,'sourceWorkItemId',v_work.id),
        updated_at=v_now
        WHERE id=v_link.requirement_id AND state='active';
      v_req_ids:=array_append(v_req_ids,v_link.requirement_id);
    END IF;
    UPDATE atlas.work_requirement_links SET active=false,
      metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_build_object('unlinkedByCompanyWorkTrashV1',true,'sourceWorkItemId',v_work.id)
      WHERE id=v_link.link_id;
    v_link_ids:=array_append(v_link_ids,v_link.link_id);
  END LOOP;

  FOR v_contract IN SELECT id,source_kind,source_id
    FROM atlas.work_time_contracts
    WHERE work_item_id=v_work.id AND contract_state='active'
    ORDER BY id FOR UPDATE
  LOOP
    IF NOT ((v_contract.source_kind IS NOT DISTINCT FROM v_work.source_object_type
          AND v_contract.source_id IS NOT DISTINCT FROM v_work.source_object_id
          AND v_work.source_object_id IS NOT NULL)
       OR (v_contract.source_kind='work_item' AND v_contract.source_id=v_work.id)) THEN
      RAISE EXCEPTION 'Independent date agreement needs a separate owner decision'
        USING ERRCODE='23514';
    END IF;
    UPDATE atlas.work_time_contracts
      SET contract_state='cancelled',updated_at=v_now,
        metadata=coalesce(metadata,'{}'::jsonb)||
          jsonb_build_object('cancelledByCompanyWorkTrashV1',true,'sourceWorkItemId',v_work.id)
      WHERE id=v_contract.id AND contract_state='active';
    v_contract_ids:=array_append(v_contract_ids,v_contract.id);
  END LOOP;

  v_receipt:=atlas.organization_management_adjudicate_company_work_api_v1(
    v_work.id,'not_relevant',
    jsonb_build_object('decision','owner_deleted_unwanted_work',
      'previousSourcePreserved',true,'taskTrashContract','company_work_trash_v1'),
    v_reason,NULL,'owner-work-trash-v1:'||v_work.id::text);
  IF v_receipt->>'companyWorkState'<>'cancelled' THEN
    RAISE EXCEPTION 'Work cancellation was not confirmed' USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.company_work_trash_decisions_v1(
    organization_id,work_item_id,actor_user_id,actor_person_id,
    original_work_snapshot,original_impact_snapshot,
    unlinked_requirement_link_ids,cancelled_requirement_ids,
    cancelled_time_contract_ids,withdrawn_initial_offer_ids,
    withdrawn_participation_offer_ids,withdrawn_transfer_offer_ids,
    management_adjudication_id
  ) VALUES (
    v_work.organization_id,v_work.id,auth.uid(),v_actor_person,
    to_jsonb(v_work),v_impact,v_link_ids,v_req_ids,v_contract_ids,
    v_initial_ids,v_participation_ids,v_transfer_ids,(v_receipt->>'adjudicationId')::uuid
  ) RETURNING id INTO v_decision_id;
  UPDATE atlas.work_items SET metadata=coalesce(metadata,'{}'::jsonb)||
    jsonb_build_object('deletedFromActiveViews',true,'trashContract','company_work_trash_v1',
      'trashDecisionId',v_decision_id,'trashedAt',v_now),
    updated_at=v_now WHERE id=v_work.id AND work_state='cancelled';

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','company_work_trash_v1','state','trashed',
    'workItemId',v_work.id,'trashDecisionId',v_decision_id,
    'workState','cancelled','workerCompletionRecorded',false,
    'sourceEvidencePreserved',true,'newWorkCreated',false);
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.delete_company_work_owner_self_api_v1(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.delete_company_work_owner_self_api_v1(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.company_work_trash_owner_self_api_v1(
  p_organization_id uuid,p_limit integer DEFAULT 100
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR
     NOT atlas.is_effective_organization_owner_v1(p_organization_id) THEN
    RAISE EXCEPTION 'Organization owner authority required' USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit<1 OR p_limit>100 THEN
    RAISE EXCEPTION 'Trash page limit must be between 1 and 100' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','company_work_trash_v1',
    'organizationId',p_organization_id,
    'items',coalesce((SELECT jsonb_agg(row_data ORDER BY trashed_at DESC,work_item_id)
      FROM (SELECT d.work_item_id,d.trashed_at,
        jsonb_build_object('workItemId',d.work_item_id,'title',w.title,
          'trashedAt',d.trashed_at,'workState',w.work_state,
          'sourceType',w.source_object_type,'sourceEvidencePreserved',true) row_data
        FROM atlas.company_work_trash_decisions_v1 d
        JOIN atlas.work_items w ON w.id=d.work_item_id
        WHERE d.organization_id=p_organization_id
        ORDER BY d.trashed_at DESC,d.work_item_id LIMIT p_limit) x
    ),'[]'::jsonb));
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.company_work_trash_owner_self_api_v1(uuid,integer)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.company_work_trash_owner_self_api_v1(uuid,integer)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_company_work_owner_self_api_v1(
  p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.delete_company_work_owner_self_api_v1(p_work_item_id); $fn$;
REVOKE ALL ON FUNCTION public.delete_company_work_owner_self_api_v1(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.delete_company_work_owner_self_api_v1(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.company_work_trash_owner_self_api_v1(
  p_organization_id uuid,p_limit integer DEFAULT 100
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.company_work_trash_owner_self_api_v1(p_organization_id,p_limit); $fn$;
REVOKE ALL ON FUNCTION public.company_work_trash_owner_self_api_v1(uuid,integer)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.company_work_trash_owner_self_api_v1(uuid,integer)
  TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;