-- U2A owner queue read, HELD. Exact native root, known farm+source rule.
-- This is not the Work roster, and never returns a Person address or private
-- notebook. Includes stale candidate states for root disposition review.
CREATE FUNCTION atlas.read_governed_prework_owner_queue_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_limit integer DEFAULT 20,
 p_after_offer_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $queue$
DECLARE v_root record;v_items jsonb;v_more boolean;v_next uuid;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 THEN
  RAISE EXCEPTION 'Bounded current source queue requested'
   USING ERRCODE='22023';
 END IF;
 WITH offers AS (
  SELECT o.* FROM atlas.governed_prework_candidate_offers_v1 o
  WHERE o.organization_id=p_organization_id AND o.ledger_id=p_ledger_id
   AND o.farm_id=p_farm_id AND o.source_rule_id=p_source_rule_id
   AND o.offered_by_person_id=v_root.actor_person_id
   AND o.offer_state IN ('offered','accepted')
   AND (p_after_offer_id IS NULL OR o.id>p_after_offer_id)
  ORDER BY o.id LIMIT p_limit+1
 ), ranked AS (
  SELECT o.*,row_number() OVER(ORDER BY o.id) AS position
  FROM offers o
 )
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
  'offerId',o.id,'state',o.offer_state,
  'candidateId',o.source_candidate_id,
  'sourceRuleId',o.source_rule_id,
  'targetPersonId',o.target_person_id,
  'firstServiceDay',o.first_service_day,
  'timezoneName',o.timezone_name,'reason',o.reason,
  'currentlyAdmissible',atlas.governed_prework_offer_still_admissible_v1(o.id),
  'workCreated',false
 ) ORDER BY o.id) FILTER(WHERE o.position<=p_limit),'[]'::jsonb),
 coalesce(bool_or(o.position>p_limit),false),
 (max(o.id::text) FILTER(WHERE o.position<=p_limit))::uuid
 INTO v_items,v_more,v_next FROM ranked o;
 RETURN pg_catalog.jsonb_build_object('ok',true,
  'contractVersion','governed_prework_owner_queue_v1',
  'organizationId',p_organization_id,'ledgerId',p_ledger_id,
  'farmId',p_farm_id,'sourceRuleId',p_source_rule_id,
  'items',v_items,'hasMore',v_more,
  'nextAfterOfferId',CASE WHEN v_more THEN v_next ELSE NULL END,
  'noWorkMutation',true,'notACompleteWorkRoster',true);
END;
$queue$;
REVOKE ALL ON FUNCTION atlas.read_governed_prework_owner_queue_self_api_v1(
 uuid,uuid,uuid,uuid,integer,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_governed_prework_owner_queue_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_limit integer DEFAULT 20,
 p_after_offer_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.read_governed_prework_owner_queue_self_api_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,
 p_limit,p_after_offer_id);
$transport$;
REVOKE ALL ON FUNCTION public.read_governed_prework_owner_queue_self_api_v1(
 uuid,uuid,uuid,uuid,integer,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_governed_prework_owner_queue_self_api_v1(
 uuid,uuid,uuid,uuid,integer,uuid) TO authenticated;
