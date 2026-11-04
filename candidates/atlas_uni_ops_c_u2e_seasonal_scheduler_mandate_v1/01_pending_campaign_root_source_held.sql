-- UNI-OPS-01 Option C / U2E: HELD FIRST CAMPAIGN MANDATE, NOT A MIGRATION.
-- Owner choices: 1C separate authorized scheduler; 2C seasonal <=120 civil
-- days; 3C NOTHING repeats without a new owner-approved campaign.
-- Source owner: Noel native Ledger + Rulebook + accepted Person scope.
-- THIS DOES NOT REGISTER A CARRIER OR GRANT AUTOMATED WORK CREATION.
-- Depends on U1A, U1B, U2A/U2B, U2C and pinned R01/R02 source.
-- No calls to production, auth settings, service_role, cron or Clock.

CREATE TABLE atlas.governed_seasonal_scheduler_campaigns_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_rule_id uuid NOT NULL REFERENCES atlas.rhythm_rules(id) ON DELETE RESTRICT,
 accepted_standing_scope_id uuid NOT NULL
   REFERENCES atlas.company_work_standing_assignment_scopes(id) ON DELETE RESTRICT,
 target_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 approving_root_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 approving_root_principal_id uuid NOT NULL,
 season_start date NOT NULL,
 season_end date NOT NULL,
 approved_iso_weekdays smallint[] NOT NULL,
 timezone_name text NOT NULL CHECK (pg_catalog.length(timezone_name) BETWEEN 3 AND 80),
 purpose text NOT NULL CHECK (pg_catalog.length(btrim(purpose)) BETWEEN 12 AND 1500),
 decision_action_id uuid NOT NULL UNIQUE,
 -- 1C/2C/3C are frozen SOURCE decisions, not an inference from UI flags.
 issuance_mode text NOT NULL DEFAULT 'separately_authorized_scheduler'
   CHECK (issuance_mode='separately_authorized_scheduler'),
 repeat_mode text NOT NULL DEFAULT 'new_campaign_requires_root_approval'
   CHECK (repeat_mode='new_campaign_requires_root_approval'),
 original_limit integer NOT NULL DEFAULT 1 CHECK (original_limit=1),
 -- No bound carrier exists until separately inspected/approved by Source.
 carrier_state text NOT NULL DEFAULT 'unbound'
   CHECK (carrier_state='unbound'),
 approved_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CHECK (season_start<=season_end AND season_end<=season_start+119),
 CHECK (coalesce(pg_catalog.array_length(approved_iso_weekdays,1),0)
   BETWEEN 1 AND 7)
);
COMMENT ON TABLE atlas.governed_seasonal_scheduler_campaigns_v1 IS
 'U2E root-approved season boundary, not scheduler activation. One original/one independently accepted candidate only; no repeat without a NEW root-approved campaign.';
CREATE INDEX governed_seasonal_scheduler_ledger_lookup_v1
 ON atlas.governed_seasonal_scheduler_campaigns_v1(
 organization_id,ledger_id,farm_id,source_rule_id,season_end);

CREATE TABLE atlas.governed_seasonal_scheduler_revocations_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 campaign_id uuid NOT NULL UNIQUE
   REFERENCES atlas.governed_seasonal_scheduler_campaigns_v1(id) ON DELETE RESTRICT,
 revoked_by_root_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 revoked_by_principal_id uuid NOT NULL,
 revoke_action_id uuid NOT NULL UNIQUE,
 reason text NOT NULL CHECK (pg_catalog.length(btrim(reason)) BETWEEN 12 AND 800),
 revoked_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);
CREATE TABLE atlas.governed_seasonal_scheduler_campaign_offers_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 campaign_id uuid NOT NULL UNIQUE
   REFERENCES atlas.governed_seasonal_scheduler_campaigns_v1(id) ON DELETE RESTRICT,
 offer_id uuid NOT NULL UNIQUE
   REFERENCES atlas.governed_prework_candidate_offers_v1(id) ON DELETE RESTRICT,
 offered_action_id uuid NOT NULL UNIQUE,
 linked_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);
COMMENT ON TABLE atlas.governed_seasonal_scheduler_campaign_offers_v1 IS
 'One source-created offer per approved campaign. Its acceptance is necessary, never enough to grant the still-unbound automated carrier original Work authority.';

CREATE TRIGGER governed_seasonal_campaign_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.governed_seasonal_scheduler_campaigns_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1();
CREATE TRIGGER governed_seasonal_revocation_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.governed_seasonal_scheduler_revocations_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1();
CREATE TRIGGER governed_seasonal_offer_link_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.governed_seasonal_scheduler_campaign_offers_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1();

ALTER TABLE atlas.governed_seasonal_scheduler_campaigns_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.governed_seasonal_scheduler_revocations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.governed_seasonal_scheduler_campaign_offers_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.governed_seasonal_scheduler_campaigns_v1
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON atlas.governed_seasonal_scheduler_revocations_v1
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON atlas.governed_seasonal_scheduler_campaign_offers_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- Nothing here is an issuer credential. The private existence predicate
-- is safe only after callers separately prove their root/worker identity.
CREATE FUNCTION atlas.seasonal_scheduler_campaign_current_v1(
 p_campaign_id uuid
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $current$
DECLARE v atlas.governed_seasonal_scheduler_campaigns_v1%ROWTYPE;
BEGIN
 SELECT * INTO v FROM atlas.governed_seasonal_scheduler_campaigns_v1
 WHERE id=p_campaign_id;
 IF v.id IS NULL OR EXISTS(
  SELECT 1 FROM atlas.governed_seasonal_scheduler_revocations_v1 x
  WHERE x.campaign_id=v.id)
  OR (pg_catalog.now() AT TIME ZONE v.timezone_name)::date
     NOT BETWEEN v.season_start AND v.season_end
  OR NOT EXISTS(
   SELECT 1 FROM atlas.company_work_standing_assignment_scopes s
   WHERE s.id=v.accepted_standing_scope_id
     AND s.organization_id=v.organization_id AND s.ledger_id=v.ledger_id
     AND s.worker_person_id=v.target_person_id
     AND s.proposed_by_person_id=v.approving_root_person_id
     AND s.accepted_by_person_id=v.target_person_id
     AND s.accepted_at IS NOT NULL
     AND s.scope_state='active'
     AND s.coverage_mode='ledger_all_work'
     AND s.worker_membership_id IS NULL
     AND (s.valid_until IS NULL OR s.valid_until>pg_catalog.now()))
  OR NOT atlas.person_has_native_ledger_connection_v1(
      v.organization_id,v.ledger_id,v.target_person_id)
 THEN RETURN false; END IF;
 RETURN true;
END;
$current$;
REVOKE ALL ON FUNCTION atlas.seasonal_scheduler_campaign_current_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- The Principal explicitly authorizes the seasonal campaign, NOT an
-- unnamed scheduler. Root authority + real native source/Person scope
-- are independently required. A later principal registration, narrow
-- carrier bind and signed scheduler issuance proof are still absent.
CREATE FUNCTION atlas.approve_pending_seasonal_scheduler_campaign_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_accepted_standing_scope_id uuid,
 p_season_start date,p_season_end date,p_approved_iso_weekdays smallint[],
 p_timezone_name text,p_purpose text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $approve$
DECLARE
 v_root record;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_saved atlas.governed_seasonal_scheduler_campaigns_v1%ROWTYPE;
 v_now date;
 v_timezone text:=btrim(coalesce(p_timezone_name,''));
 v_purpose text:=btrim(coalesce(p_purpose,''));
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 IF p_action_id IS NULL OR p_accepted_standing_scope_id IS NULL
  OR p_season_start IS NULL OR p_season_end IS NULL
  OR p_season_end<p_season_start
  OR p_season_end>p_season_start+119
  OR p_approved_iso_weekdays IS NULL
  OR coalesce(pg_catalog.array_length(p_approved_iso_weekdays,1),0)
    NOT BETWEEN 1 AND 7
  OR p_approved_iso_weekdays IS DISTINCT FROM
    ARRAY(SELECT DISTINCT d FROM pg_catalog.unnest(p_approved_iso_weekdays)
       AS wd(d) ORDER BY d)::smallint[]
  OR EXISTS(SELECT 1 FROM pg_catalog.unnest(p_approved_iso_weekdays) wd(d)
    WHERE d IS NULL OR d NOT BETWEEN 1 AND 7)
  OR pg_catalog.length(v_purpose) NOT BETWEEN 12 AND 1500
  OR pg_catalog.length(v_timezone) NOT BETWEEN 3 AND 80
  OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names tz
    WHERE tz.name=v_timezone)
 THEN RAISE EXCEPTION 'Exact bounded 120-day seasonal source required'
  USING ERRCODE='22023'; END IF;
 v_now:=(pg_catalog.now() AT TIME ZONE v_timezone)::date;
 IF p_season_start<v_now OR p_season_end<v_now THEN
  RAISE EXCEPTION 'Cannot retroactively authorize a past season'
    USING ERRCODE='42501'; END IF;
 IF v_timezone IS DISTINCT FROM coalesce(
     nullif((SELECT r.metadata->>'timezoneName'
       FROM atlas.rhythm_rules r WHERE r.id=p_source_rule_id),''),'UTC')
 THEN RAISE EXCEPTION 'Native source timezone must be preserved'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=p_accepted_standing_scope_id
   AND s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id
   AND s.proposed_by_person_id=v_root.actor_person_id
   AND s.scope_state='active' AND s.coverage_mode='ledger_all_work'
   AND s.worker_membership_id IS NULL
   AND s.accepted_by_person_id=s.worker_person_id
   AND s.accepted_at IS NOT NULL
   AND (s.valid_until IS NULL OR s.valid_until>pg_catalog.now());
 IF v_scope.id IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN RAISE EXCEPTION 'Current accepted native worker relation required'
  USING ERRCODE='42501'; END IF;
 -- Every competing campaign approval for one source+Person shares one lock.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u2e:campaign:'||p_organization_id::text||':'||p_ledger_id::text||
    ':'||p_source_rule_id::text||':'||v_scope.worker_person_id::text,0));
 SELECT * INTO v_saved FROM atlas.governed_seasonal_scheduler_campaigns_v1
 WHERE decision_action_id=p_action_id;
 IF v_saved.id IS NOT NULL THEN
  IF v_saved.organization_id IS DISTINCT FROM p_organization_id
     OR v_saved.ledger_id IS DISTINCT FROM p_ledger_id
     OR v_saved.farm_id IS DISTINCT FROM p_farm_id
     OR v_saved.source_rule_id IS DISTINCT FROM p_source_rule_id
     OR v_saved.accepted_standing_scope_id IS DISTINCT FROM p_accepted_standing_scope_id
     OR v_saved.approving_root_person_id IS DISTINCT FROM v_root.actor_person_id
     OR v_saved.target_person_id IS DISTINCT FROM v_scope.worker_person_id
     OR v_saved.season_start IS DISTINCT FROM p_season_start
     OR v_saved.season_end IS DISTINCT FROM p_season_end
     OR v_saved.approved_iso_weekdays IS DISTINCT FROM p_approved_iso_weekdays
     OR v_saved.timezone_name IS DISTINCT FROM v_timezone
     OR v_saved.purpose IS DISTINCT FROM v_purpose
  THEN RAISE EXCEPTION 'Action ID is already bound to a different campaign'
    USING ERRCODE='23514'; END IF;
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','pending_seasonal_scheduler_campaign_v1',
   'replayed',true,'campaignId',v_saved.id,
   'workerPersonId',v_saved.target_person_id,
   'seasonStart',v_saved.season_start,'seasonEnd',v_saved.season_end,
   'carrierState','unbound','schedulerAuthorized',false,
   'offerCreated',false,'originalWorkCreated',false,
   'nextCampaignPreapproved',false);
 END IF;
 -- No silent overlap/extension of a still-current campaign. New campaigns
 -- require a DISTINCT signed root action and must not overlap the old one.
 IF EXISTS(
  SELECT 1 FROM atlas.governed_seasonal_scheduler_campaigns_v1 x
  WHERE x.organization_id=p_organization_id AND x.ledger_id=p_ledger_id
    AND x.farm_id=p_farm_id AND x.source_rule_id=p_source_rule_id
    AND x.target_person_id=v_scope.worker_person_id
    AND x.season_start<=p_season_end AND x.season_end>=p_season_start
    AND NOT EXISTS(
     SELECT 1 FROM atlas.governed_seasonal_scheduler_revocations_v1 r
     WHERE r.campaign_id=x.id))
 THEN RAISE EXCEPTION 'Existing active or unrevoked campaign overlaps'
  USING ERRCODE='23514'; END IF;
 INSERT INTO atlas.governed_seasonal_scheduler_campaigns_v1(
  organization_id,ledger_id,farm_id,source_rule_id,
  accepted_standing_scope_id,target_person_id,approving_root_person_id,
  approving_root_principal_id,season_start,season_end,
  approved_iso_weekdays,timezone_name,purpose,decision_action_id
 ) VALUES(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,
  p_accepted_standing_scope_id,v_scope.worker_person_id,
  v_root.actor_person_id,v_root.actor_principal_id,
  p_season_start,p_season_end,p_approved_iso_weekdays,v_timezone,
  v_purpose,p_action_id
 ) RETURNING * INTO v_saved;
 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','pending_seasonal_scheduler_campaign_v1',
  'replayed',false,'campaignId',v_saved.id,
  'workerPersonId',v_saved.target_person_id,
  'seasonStart',v_saved.season_start,'seasonEnd',v_saved.season_end,
  'maxOriginals',1,'repeatMode','new_campaign_requires_root_approval',
  'carrierState','unbound','schedulerAuthorized',false,
  'offerCreated',false,'originalWorkCreated',false,
  'nextCampaignPreapproved',false);
END;
$approve$;
REVOKE ALL ON FUNCTION atlas.approve_pending_seasonal_scheduler_campaign_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- One source-chosen offer for one campaign. This is an explicit signed
-- ROOT decision to begin the one candidate encounter; NOT scheduler choice.
-- It uses the already-held U2 source adapter, preserves consent, returns no
-- Work and is the ONLY proposed external offer entrypoint after cutover.
CREATE FUNCTION atlas.offer_one_candidate_for_seasonal_campaign_self_api_v1(
 p_campaign_id uuid,p_first_service_day date,p_reason text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $offer_campaign$
DECLARE
 v atlas.governed_seasonal_scheduler_campaigns_v1%ROWTYPE;
 v_root record;
 v_prior atlas.governed_seasonal_scheduler_campaign_offers_v1%ROWTYPE;
 v_source jsonb;
 v_offer_id uuid;
BEGIN
 IF p_campaign_id IS NULL OR p_action_id IS NULL OR p_first_service_day IS NULL
 THEN RAISE EXCEPTION 'Exact approved campaign and operation required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v FROM atlas.governed_seasonal_scheduler_campaigns_v1
 WHERE id=p_campaign_id;
 IF v.id IS NULL THEN RAISE EXCEPTION 'Unknown campaign' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
   v.organization_id,v.ledger_id,v.farm_id,v.source_rule_id);
 IF v_root.actor_person_id IS DISTINCT FROM v.approving_root_person_id
    OR NOT atlas.seasonal_scheduler_campaign_current_v1(v.id)
    OR p_first_service_day NOT BETWEEN v.season_start AND v.season_end
    OR NOT (EXTRACT(ISODOW FROM p_first_service_day)::smallint
       =ANY(v.approved_iso_weekdays))
 THEN RAISE EXCEPTION 'Campaign revoked, expired, changed or wrong day'
  USING ERRCODE='42501'; END IF;
 -- Root-only create and replay are protected by the same campaign lock.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u2e:one-offer:'||v.id::text,0));
 SELECT * INTO v_prior FROM atlas.governed_seasonal_scheduler_campaign_offers_v1
 WHERE campaign_id=v.id;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.offered_action_id IS DISTINCT FROM p_action_id THEN
   RAISE EXCEPTION 'Campaign is already bound to one source candidate'
     USING ERRCODE='23514'; END IF;
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','one_offer_seasonal_campaign_v1',
   'replayed',true,'campaignId',v.id,'offerId',v_prior.offer_id,
   'offerCreatedNow',false,'originalWorkCreated',false,
   'schedulerAuthorized',false,'nextCampaignPreapproved',false);
 END IF;
 v_source:=atlas.offer_next_governed_prework_candidate_self_api_v1(
  v.organization_id,v.ledger_id,v.farm_id,v.source_rule_id,
  v.accepted_standing_scope_id,p_first_service_day,v.season_end,
  v.approved_iso_weekdays,v.timezone_name,p_reason,p_action_id);
 IF v_source->>'ok' IS DISTINCT FROM 'true'
    OR v_source->>'contractVersion' IS DISTINCT FROM
       'governed_prework_candidate_offer_v1'
 THEN RAISE EXCEPTION 'One first-party source offer was not verified'
  USING ERRCODE='23514'; END IF;
 IF v_source->>'state'='no_source_eligible_candidate' THEN
  RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','one_offer_seasonal_campaign_v1',
   'state','no_source_eligible_candidate','campaignId',v.id,
   'offerCreatedNow',false,'originalWorkCreated',false,
   'schedulerAuthorized',false,'nextCampaignPreapproved',false);
 END IF;
 IF v_source->>'state'<>'offered'
    OR coalesce(v_source->>'offerId','') !~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR v_source->>'targetPersonId' IS DISTINCT FROM v.target_person_id::text
    OR v_source->>'originalWorkCreated' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'Source selection did not yield exactly one new prework offer'
  USING ERRCODE='23514'; END IF;
 v_offer_id:=(v_source->>'offerId')::uuid;
 INSERT INTO atlas.governed_seasonal_scheduler_campaign_offers_v1(
  campaign_id,offer_id,offered_action_id)
 VALUES(v.id,v_offer_id,p_action_id);
 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','one_offer_seasonal_campaign_v1',
  'state','offered','campaignId',v.id,'offerId',v_offer_id,
  'targetPersonId',v.target_person_id,
  'offerCreatedNow',true,'originalWorkCreated',false,
  'schedulerAuthorized',false,'nextCampaignPreapproved',false);
END;
$offer_campaign$;
REVOKE ALL ON FUNCTION atlas.offer_one_candidate_for_seasonal_campaign_self_api_v1(
 uuid,date,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Signed root may revoke without mutating any evidence. Revocation ends
-- future issuance; past legitimate Actuals remain historical.
CREATE FUNCTION atlas.revoke_pending_seasonal_scheduler_campaign_self_api_v1(
 p_campaign_id uuid,p_reason text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $revoke$
DECLARE v atlas.governed_seasonal_scheduler_campaigns_v1%ROWTYPE;
 v_prior atlas.governed_seasonal_scheduler_revocations_v1%ROWTYPE;
 v_root record;
BEGIN
 IF p_campaign_id IS NULL OR p_action_id IS NULL
  OR pg_catalog.length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 800
 THEN RAISE EXCEPTION 'Exact root revocation action and reason required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v FROM atlas.governed_seasonal_scheduler_campaigns_v1
 WHERE id=p_campaign_id;
 IF v.id IS NULL THEN RAISE EXCEPTION 'Campaign unavailable'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  v.organization_id,v.ledger_id,v.farm_id,v.source_rule_id);
 IF v_root.actor_person_id IS DISTINCT FROM v.approving_root_person_id THEN
  RAISE EXCEPTION 'Only the current source root may revoke this campaign'
   USING ERRCODE='42501'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u2e:one-offer:'||v.id::text,0));
 SELECT * INTO v_prior FROM atlas.governed_seasonal_scheduler_revocations_v1
 WHERE campaign_id=v.id;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.revoke_action_id IS DISTINCT FROM p_action_id THEN
   RAISE EXCEPTION 'Campaign already revoked by another root action'
    USING ERRCODE='23514'; END IF;
  RETURN pg_catalog.jsonb_build_object('ok',true,
   'contractVersion','governed_seasonal_campaign_revoked_v1',
   'replayed',true,'campaignId',v.id,'revoked',true,
   'futureIssuerAuthorized',false,'originalWorkCreated',false);
 END IF;
 INSERT INTO atlas.governed_seasonal_scheduler_revocations_v1(
  campaign_id,revoked_by_root_person_id,revoked_by_principal_id,
  revoke_action_id,reason)
 VALUES(v.id,v_root.actor_person_id,v_root.actor_principal_id,
  p_action_id,btrim(p_reason));
 RETURN pg_catalog.jsonb_build_object('ok',true,
  'contractVersion','governed_seasonal_campaign_revoked_v1',
  'replayed',false,'campaignId',v.id,'revoked',true,
  'futureIssuerAuthorized',false,'originalWorkCreated',false);
END;
$revoke$;
REVOKE ALL ON FUNCTION atlas.revoke_pending_seasonal_scheduler_campaign_self_api_v1(
 uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- The *only* public source operations are signed ROOT campaign approval,
-- ONE source offer, and revocation. No runner, agent or service_role write.
-- The worker's signed response uses the existing U2 source unchanged.
CREATE FUNCTION public.approve_pending_seasonal_scheduler_campaign_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_accepted_standing_scope_id uuid,
 p_season_start date,p_season_end date,p_approved_iso_weekdays smallint[],
 p_timezone_name text,p_purpose text,p_action_id uuid
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public_approve$
 SELECT atlas.approve_pending_seasonal_scheduler_campaign_self_api_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,
 p_accepted_standing_scope_id,p_season_start,p_season_end,
 p_approved_iso_weekdays,p_timezone_name,p_purpose,p_action_id);
$public_approve$;
REVOKE ALL ON FUNCTION public.approve_pending_seasonal_scheduler_campaign_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.approve_pending_seasonal_scheduler_campaign_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 TO authenticated;

CREATE FUNCTION public.offer_one_candidate_for_seasonal_campaign_self_api_v1(
 p_campaign_id uuid,p_first_service_day date,p_reason text,p_action_id uuid
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public_offer$
 SELECT atlas.offer_one_candidate_for_seasonal_campaign_self_api_v1(
  p_campaign_id,p_first_service_day,p_reason,p_action_id);
$public_offer$;
REVOKE ALL ON FUNCTION public.offer_one_candidate_for_seasonal_campaign_self_api_v1(
 uuid,date,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.offer_one_candidate_for_seasonal_campaign_self_api_v1(
 uuid,date,text,uuid) TO authenticated;

CREATE FUNCTION public.revoke_pending_seasonal_scheduler_campaign_self_api_v1(
 p_campaign_id uuid,p_reason text,p_action_id uuid
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public_revoke$
 SELECT atlas.revoke_pending_seasonal_scheduler_campaign_self_api_v1(
  p_campaign_id,p_reason,p_action_id);
$public_revoke$;
REVOKE ALL ON FUNCTION public.revoke_pending_seasonal_scheduler_campaign_self_api_v1(
 uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_pending_seasonal_scheduler_campaign_self_api_v1(
 uuid,text,uuid) TO authenticated;

-- END HELD U2E. Approved campaign is NOT a carrier grant.
