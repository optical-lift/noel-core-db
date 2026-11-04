-- U2E exact known-campaign root-only READ, HELD.
-- A root can recover the authorized season without scanning a roster,
-- guessing a carrier identity, or treating a prior receipt as current.
CREATE FUNCTION atlas.read_pending_seasonal_scheduler_campaign_self_api_v1(
 p_campaign_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $read$
DECLARE
 v atlas.governed_seasonal_scheduler_campaigns_v1%ROWTYPE;
 v_root record;
 v_offer atlas.governed_seasonal_scheduler_campaign_offers_v1%ROWTYPE;
 v_offer_state text;
 v_revoked boolean;
 v_today date;
 v_state text;
BEGIN
 IF p_campaign_id IS NULL THEN
  RAISE EXCEPTION 'Known campaign is required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v FROM atlas.governed_seasonal_scheduler_campaigns_v1
 WHERE id=p_campaign_id;
 IF v.id IS NULL THEN
  RAISE EXCEPTION 'Campaign unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  v.organization_id,v.ledger_id,v.farm_id,v.source_rule_id);
 IF v_root.actor_person_id IS DISTINCT FROM v.approving_root_person_id
  OR v_root.actor_principal_id IS DISTINCT FROM v.approving_root_principal_id
 THEN RAISE EXCEPTION 'Current original native root required'
  USING ERRCODE='42501'; END IF;
 v_today:=(pg_catalog.now() AT TIME ZONE v.timezone_name)::date;
 SELECT EXISTS(
  SELECT 1 FROM atlas.governed_seasonal_scheduler_revocations_v1 r
  WHERE r.campaign_id=v.id) INTO v_revoked;
 SELECT * INTO v_offer FROM atlas.governed_seasonal_scheduler_campaign_offers_v1
 WHERE campaign_id=v.id;
 IF v_offer.id IS NOT NULL THEN
  SELECT o.offer_state INTO v_offer_state
  FROM atlas.governed_prework_candidate_offers_v1 o
  WHERE o.id=v_offer.offer_id;
 END IF;
 IF v_revoked THEN v_state:='revoked';
 ELSIF v_today<v.season_start THEN v_state:='pending_window';
 ELSIF v_today>v.season_end THEN v_state:='expired';
 ELSE v_state:='active_unbound';
 END IF;
 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','seasonal_scheduler_campaign_current_v1',
  'campaignId',v.id,'state',v_state,'revoked',v_revoked,
  'organizationId',v.organization_id,'ledgerId',v.ledger_id,
  'farmId',v.farm_id,'sourceRuleId',v.source_rule_id,
  'targetPersonId',v.target_person_id,'acceptedStandingScopeId',v.accepted_standing_scope_id,
  'seasonStart',v.season_start,'seasonEnd',v.season_end,
  'approvedIsoWeekdays',v.approved_iso_weekdays,'timezoneName',v.timezone_name,
  'maxOriginals',1,'repeatMode','new_campaign_requires_root_approval',
  'offerId',v_offer.offer_id,'offerState',v_offer_state,
  'carrierState','unbound','schedulerAuthorized',false,
  'nextCampaignPreapproved',false,'originalWorkCreatedByThisRead',false);
END;
$read$;
REVOKE ALL ON FUNCTION atlas.read_pending_seasonal_scheduler_campaign_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.read_pending_seasonal_scheduler_campaign_self_api_v1(
 p_campaign_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public_read$
 SELECT atlas.read_pending_seasonal_scheduler_campaign_self_api_v1(p_campaign_id);
$public_read$;
REVOKE ALL ON FUNCTION public.read_pending_seasonal_scheduler_campaign_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pending_seasonal_scheduler_campaign_self_api_v1(uuid)
 TO authenticated;
