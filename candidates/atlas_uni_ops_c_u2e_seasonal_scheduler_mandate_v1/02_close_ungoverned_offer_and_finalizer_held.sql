-- U2E 1C/2C/3C ACCEPTANCE CUTOVER — HELD, APPLY LAST.
-- This is NOT a migration, not a credential and NOT production-authorized.
-- Requires U1A→U2E exact source composition, verified source permissions.
--
-- Owner decision 3C explicitly disallows an unapproved new campaign. Older
-- direct U2 root source-offer and root-finalize browser RPCs must not bypass
-- campaign custody or send a second candidate after an accepted Actual.
--
-- The new signed ROOT offer route always binds at most ONE source offer
-- to one root-approved, <=120-day campaign. The signed worker still
-- responds through the existing U2 source; no Work is created.
--
-- A separately authenticated scheduler finalizer WILL NEED A NEW,
-- independently reviewed and authorized native Principal/carrier seam.
-- Until that carrier seam exists, NO publicly callable original Work
-- finalizer remains. The protected private U2B writer remains source-only
-- and cannot be called by anonymous/authenticated or service_role.
DO $preflight$
BEGIN
 IF pg_catalog.to_regprocedure(
 'public.offer_next_governed_prework_candidate_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
 'public.finalize_accepted_governed_prework_self_api_v1(uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
 'public.offer_one_candidate_for_seasonal_campaign_self_api_v1(uuid,date,text,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
 'public.approve_pending_seasonal_scheduler_campaign_self_api_v1(uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)') IS NULL
 THEN RAISE EXCEPTION 'U2E needs exact earlier offer/finalizer source and new campaign custody';
 END IF;
END;
$preflight$;

REVOKE ALL ON FUNCTION public.offer_next_governed_prework_candidate_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.finalize_accepted_governed_prework_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON FUNCTION public.offer_next_governed_prework_candidate_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 IS 'U2E 3C HELD: direct noncampaign offer closed. One offer ONLY through signed campaign source after owner approved a new campaign.';
COMMENT ON FUNCTION public.finalize_accepted_governed_prework_self_api_v1(uuid)
 IS 'U2E 1C HELD: no human-root or proxy scheduler direct issuance. Await separately registered, verified and revocable scheduler carrier, and source-atomic accepted candidate bridge.';

-- No new scheduler API, service_role grant, session impersonation or
-- authenticated direct-original fallback is created here.
