-- U2E HELD SOURCE POSTCONDITIONS. USE ONLY on a production-shaped
-- disposable PostgreSQL clone WITH signed root/worker/outsider probes.
-- These structural checks are necessary but NEVER sufficient to release.
DO $check$
DECLARE v_src text;
BEGIN
 IF pg_catalog.to_regclass(
  'atlas.governed_seasonal_scheduler_campaigns_v1') IS NULL
 OR pg_catalog.to_regclass(
  'atlas.governed_seasonal_scheduler_revocations_v1') IS NULL
 OR pg_catalog.to_regclass(
  'atlas.governed_seasonal_scheduler_campaign_offers_v1') IS NULL
 THEN RAISE EXCEPTION 'One-season governing custody evidence missing';
 END IF;
 IF pg_catalog.to_regprocedure(
 'public.approve_pending_seasonal_scheduler_campaign_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
 'public.offer_one_candidate_for_seasonal_campaign_self_api_v1(uuid,date,text,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
 'public.revoke_pending_seasonal_scheduler_campaign_self_api_v1(uuid,text,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
 'public.read_pending_seasonal_scheduler_campaign_self_api_v1(uuid)') IS NULL
 THEN RAISE EXCEPTION 'Signed root campaign contract missing';
 END IF;

 IF EXISTS(
  SELECT 1 FROM pg_catalog.pg_class t
  JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='atlas'
    AND t.relname IN (
     'governed_seasonal_scheduler_campaigns_v1',
     'governed_seasonal_scheduler_revocations_v1',
     'governed_seasonal_scheduler_campaign_offers_v1')
    AND NOT t.relrowsecurity)
 THEN RAISE EXCEPTION 'Campaign source must retain private RLS';
 END IF;
 IF (
 SELECT count(*) FROM pg_catalog.pg_trigger t
 WHERE t.tgname IN (
  'governed_seasonal_campaign_immutable_v1',
  'governed_seasonal_revocation_immutable_v1',
  'governed_seasonal_offer_link_immutable_v1')
 AND NOT t.tgisinternal
 )<>3
 THEN RAISE EXCEPTION 'Append-only owner campaign / revoke evidence is mutable';
 END IF;

 IF pg_catalog.has_function_privilege('anon',
  'public.approve_pending_seasonal_scheduler_campaign_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)',
  'EXECUTE')
 OR pg_catalog.has_function_privilege('anon',
  'public.offer_one_candidate_for_seasonal_campaign_self_api_v1(uuid,date,text,uuid)',
  'EXECUTE')
 OR NOT pg_catalog.has_function_privilege('authenticated',
  'public.approve_pending_seasonal_scheduler_campaign_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)',
  'EXECUTE')
 OR NOT pg_catalog.has_function_privilege('authenticated',
  'public.read_pending_seasonal_scheduler_campaign_self_api_v1(uuid)',
  'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
  'atlas.seasonal_scheduler_campaign_current_v1(uuid)',
  'EXECUTE')
 THEN RAISE EXCEPTION 'Public root transport/private campaign guard ACL drift';
 END IF;

 -- Owner 1C + 3C: no root-finalize Work RPC and no original direct
 -- noncampaign offer, despite historical function definitions existing.
 IF pg_catalog.has_function_privilege('authenticated',
  'public.finalize_accepted_governed_prework_self_api_v1(uuid)',
  'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
  'public.offer_next_governed_prework_candidate_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)',
  'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
  'public.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)',
  'EXECUTE')
 OR pg_catalog.has_function_privilege('service_role',
  'public.finalize_accepted_governed_prework_self_api_v1(uuid)',
  'EXECUTE')
 THEN RAISE EXCEPTION 'Direct original issuance or noncampaign offer still exposed';
 END IF;

 SELECT pg_catalog.pg_get_functiondef(
  'atlas.offer_one_candidate_for_seasonal_campaign_self_api_v1(uuid,date,text,uuid)'
    ::pg_catalog.regprocedure) INTO v_src;
 IF v_src IS NULL OR pg_catalog.strpos(
     v_src,'governed_seasonal_scheduler_campaign_offers_v1')=0
    OR pg_catalog.strpos(
     v_src,'seasonal_scheduler_campaign_current_v1')=0
    OR pg_catalog.strpos(
     v_src,'offer_next_governed_prework_candidate_self_api_v1')=0
 THEN RAISE EXCEPTION 'One-offer campaign source was bypassed';
 END IF;
 IF EXISTS(
   SELECT 1 FROM atlas.governed_seasonal_scheduler_campaigns_v1 c
   WHERE c.original_limit<>1
      OR c.issuance_mode<>'separately_authorized_scheduler'
      OR c.repeat_mode<>'new_campaign_requires_root_approval'
      OR c.carrier_state<>'unbound'
      OR c.season_end>c.season_start+119)
 THEN RAISE EXCEPTION 'Seasonal 1C/2C/3C record violates owner decisions';
 END IF;
END;
$check$;
-- NOT EXECUTED. Negative tests must still prove revoked/expired/
-- non-root/worker-cross-identity, duplicate offer, simultaneous writes,
-- current Rulebook, 3-open cap, accepted Actual and no-repeat behavior.
