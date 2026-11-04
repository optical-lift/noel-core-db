-- UNI-OPS-01 Option C / U2A HELD SOURCE, NOT A MIGRATION.
-- Pre-original candidate offer, signed worker response, ZERO Work.
-- Depends on held U1B farm scope approvals and existing R01 native sources.
-- A candidate and worker willingness are NOT a Need verdict, allocation, Work,
-- scheduling authority, physical observation, Actual, or Clock obligation.

CREATE TABLE atlas.governed_prework_candidate_offers_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_rule_id uuid NOT NULL REFERENCES atlas.rhythm_rules(id) ON DELETE RESTRICT,
 source_candidate_id uuid NOT NULL REFERENCES atlas.rhythm_state(id) ON DELETE RESTRICT,
 subject_id uuid NOT NULL REFERENCES atlas.growing_objects(id) ON DELETE RESTRICT,
 rule_version_id uuid NOT NULL
  REFERENCES atlas.governed_farm_rulebook_scope_versions_v1(id) ON DELETE RESTRICT,
 property_rule_version_id uuid NOT NULL
  REFERENCES atlas.governed_farm_rulebook_scope_versions_v1(id) ON DELETE RESTRICT,
 accepted_standing_scope_id uuid NOT NULL
  REFERENCES atlas.company_work_standing_assignment_scopes(id) ON DELETE RESTRICT,
 target_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 offered_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 first_service_day date NOT NULL,
 campaign_end_date date NOT NULL,
 approved_iso_weekdays smallint[] NOT NULL,
 timezone_name text NOT NULL CHECK (length(timezone_name) BETWEEN 3 AND 80),
 reason text NOT NULL CHECK (length(reason) BETWEEN 12 AND 1500),
 source_basis jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(source_basis)='object'),
 offer_state text NOT NULL DEFAULT 'offered'
  CHECK (offer_state IN ('offered','accepted','declined','withdrawn','fulfilled')),
 original_work_item_id uuid REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 offered_action_id uuid NOT NULL UNIQUE,
 response_action_id uuid UNIQUE,
 responding_principal_id uuid,
 responded_at timestamptz,
 offered_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CHECK (campaign_end_date>=first_service_day
        AND campaign_end_date<=first_service_day+120),
 CHECK (coalesce(pg_catalog.array_length(approved_iso_weekdays,1),0) BETWEEN 1 AND 7),
 CHECK (
  (offer_state='offered' AND response_action_id IS NULL AND responded_at IS NULL
    AND responding_principal_id IS NULL AND original_work_item_id IS NULL)
  OR (offer_state IN ('accepted','declined') AND response_action_id IS NOT NULL
      AND responded_at IS NOT NULL AND responding_principal_id IS NOT NULL
      AND original_work_item_id IS NULL)
  OR (offer_state='withdrawn' AND original_work_item_id IS NULL)
  OR (offer_state='fulfilled' AND response_action_id IS NOT NULL
      AND responded_at IS NOT NULL AND original_work_item_id IS NOT NULL)
 )
);
CREATE UNIQUE INDEX governed_prework_one_active_candidate_v1
 ON atlas.governed_prework_candidate_offers_v1(
  organization_id,ledger_id,source_candidate_id)
 WHERE offer_state IN ('offered','accepted');
CREATE UNIQUE INDEX governed_prework_one_outstanding_worker_v1
 ON atlas.governed_prework_candidate_offers_v1(target_person_id)
 WHERE offer_state IN ('offered','accepted');
CREATE UNIQUE INDEX governed_prework_one_original_work_v1
 ON atlas.governed_prework_candidate_offers_v1(original_work_item_id)
 WHERE original_work_item_id IS NOT NULL;
ALTER TABLE atlas.governed_prework_candidate_offers_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.governed_prework_candidate_offers_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- Current source gate, callable ONLY by private signed human entrypoints.
-- Rechecks canonical source, the exact latest property umbrella, strongest
-- class/Subject override, accepted Person scope and BOTH disclosures.
-- Historical due_at is NOT evidence of weeds or physical condition.
CREATE FUNCTION atlas.governed_prework_offer_still_admissible_v1(
 p_offer_id uuid
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $verify$
DECLARE
 v atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_current_version uuid;
 v_property_status text;
 v_current_property_version uuid;
 v_open_count integer;
BEGIN
 SELECT * INTO v FROM atlas.governed_prework_candidate_offers_v1
 WHERE id=p_offer_id;
 IF v.id IS NULL OR v.offer_state NOT IN ('offered','accepted')
    OR (pg_catalog.now() AT TIME ZONE v.timezone_name)::date>v.first_service_day
    OR (pg_catalog.now() AT TIME ZONE v.timezone_name)::date>v.campaign_end_date
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms f
      JOIN atlas.farm_crop_ledger_custody_v1 c
        ON c.farm_id=f.id AND c.ledger_id=v.ledger_id
       AND c.custody_state='active' AND c.ended_at IS NULL
      WHERE f.id=v.farm_id AND f.organization_id=v.organization_id
        AND f.status='active')
    OR NOT EXISTS(SELECT 1 FROM atlas.ledger_organization_participations lop
      WHERE lop.organization_id=v.organization_id AND lop.ledger_id=v.ledger_id
        AND lop.status='active' AND lop.ended_at IS NULL
        AND lop.participation_kind='governing' AND lop.is_compatibility_primary=true)
    OR NOT atlas.person_has_native_ledger_connection_v1(
      v.organization_id,v.ledger_id,v.target_person_id)
 THEN RETURN false; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM atlas.company_work_standing_assignment_scopes ss
   WHERE ss.id=v.accepted_standing_scope_id
     AND ss.organization_id=v.organization_id AND ss.ledger_id=v.ledger_id
     AND ss.worker_person_id=v.target_person_id
     AND ss.scope_state='active' AND ss.coverage_mode='ledger_all_work'
     AND ss.worker_membership_id IS NULL
     AND ss.proposed_by_person_id=v.offered_by_person_id
     AND ss.accepted_by_person_id=v.target_person_id
     AND ss.accepted_at IS NOT NULL
     AND (ss.valid_until IS NULL OR ss.valid_until>pg_catalog.now())
 ) THEN RETURN false; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM atlas.rhythm_state s
   JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
     AND b.farm_id=s.farm_id AND b.organization_id=s.organization_id
     AND b.rhythm_rule_id=s.rhythm_rule_id AND b.active
   JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
     AND r.status='active' AND r.validity_interval_seconds>0
   JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=s.farm_id
   JOIN reality.entities e ON e.id=g.id AND e.identity_state='canonical'
     AND e.entity_kind='growing_object'
     AND e.metadata->>'subjectDomain'='spatial'
   WHERE s.id=v.source_candidate_id
     AND s.farm_id=v.farm_id AND s.organization_id=v.organization_id
     AND s.rhythm_rule_id=v.source_rule_id
     AND s.subject_id=v.subject_id AND s.state<>'paused'
     AND s.rhythm_key='mowing'
     AND EXISTS(SELECT 1 FROM atlas.mowing_area_state m
        WHERE m.object_id=s.subject_id AND m.farm_id=s.farm_id
          AND m.organization_id=v.organization_id AND m.status<>'closed')
 ) OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      v.ledger_id,v.target_person_id,
      'spatial','growing_object',v.subject_id,'identity'),false)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      v.ledger_id,v.target_person_id,
      'spatial','growing_object',v.subject_id,'condition'),false)
 THEN RETURN false; END IF;

 -- Preserve all source families' duplicate Work boundary. The legacy farm
 -- store remains a collision source, never an alternative original writer.
 IF EXISTS(SELECT 1 FROM atlas.work_items w
    WHERE w.organization_id=v.organization_id
      AND w.source_object_type='rhythm_state'
      AND w.source_object_id=v.source_candidate_id AND w.work_state='open')
    OR EXISTS(SELECT 1 FROM atlas.tasks t
      LEFT JOIN atlas.planned_work_occurrences p
       ON p.id=t.planned_occurrence_id
      WHERE t.farm_id=v.farm_id AND t.status IN ('open','blocked')
       AND (t.metadata->>'rhythm_state_id'=v.source_candidate_id::text
        OR (p.source_kind='rhythm_state'
           AND p.source_id=v.source_candidate_id)))
 THEN RETURN false; END IF;

 SELECT r.id,r.rule_status INTO v_current_property_version,v_property_status
 FROM atlas.governed_farm_rulebook_scope_versions_v1 r
 WHERE r.organization_id=v.organization_id AND r.ledger_id=v.ledger_id
   AND r.farm_id=v.farm_id AND r.source_rule_id=v.source_rule_id
   AND r.scope_key='property' ORDER BY r.rule_version DESC LIMIT 1;
 IF v_property_status IS DISTINCT FROM 'active'
   OR v_current_property_version IS DISTINCT FROM v.property_rule_version_id
 THEN RETURN false; END IF;

 SELECT r.id INTO v_current_version
 FROM atlas.governed_farm_rulebook_scope_versions_v1 r
 JOIN atlas.growing_objects g ON g.id=v.subject_id
 WHERE r.organization_id=v.organization_id AND r.ledger_id=v.ledger_id
  AND r.farm_id=v.farm_id AND r.source_rule_id=v.source_rule_id
  AND r.scope_key IN ('property','class:'||g.object_type,
                      'subject:'||g.id::text)
  AND NOT EXISTS(SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 later
    WHERE later.organization_id=r.organization_id AND later.ledger_id=r.ledger_id
     AND later.farm_id=r.farm_id AND later.source_rule_id=r.source_rule_id
     AND later.scope_key=r.scope_key AND later.rule_version>r.rule_version)
 ORDER BY CASE r.scope_kind WHEN 'subject' THEN 1
     WHEN 'class' THEN 2 ELSE 3 END LIMIT 1;
 IF v_current_version IS DISTINCT FROM v.rule_version_id THEN RETURN false; END IF;

 -- The chosen policy has only standing eligibility and NO unresolved
 -- seasonal conditions. An observed-corrective policy must enter its
 -- genuine typed physical-condition adapter, not this basic first offer.
 IF NOT EXISTS(SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 r
    WHERE r.id=v.rule_version_id AND r.rule_status='active'
     AND r.policy->>'eligibilityMode'='standing_stewardship'
     AND pg_catalog.jsonb_array_length(
      coalesce(r.policy->'seasonKeys','[]'::jsonb))=0)
 THEN RETURN false; END IF;

 -- Anna's chosen 3-open-original ceiling is an explicit per-offer cap,
 -- applied conservatively across every active institution allocation.
 SELECT count(DISTINCT w.id) INTO v_open_count
 FROM atlas.work_allocations a JOIN atlas.work_items w ON w.id=a.work_item_id
 WHERE w.work_state='open' AND a.state='active'
   AND a.allocation_role='responsible'
   AND (a.assignee_canonical_person_id=v.target_person_id
      OR EXISTS(SELECT 1 FROM atlas.organization_memberships m
       WHERE m.id=a.assignee_membership_id
         AND m.person_id=v.target_person_id AND m.active));
 RETURN v_open_count<3;
END;
$verify$;
REVOKE ALL ON FUNCTION atlas.governed_prework_offer_still_admissible_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Bounded autonomous *selection*: current root authorizes a single service
-- day/recipient scope; the source chooses the first eligible candidate.
-- No client may select Bed IDs or claim physical need.
CREATE FUNCTION atlas.offer_next_governed_prework_candidate_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_accepted_standing_scope_id uuid,
 p_first_service_day date,p_campaign_end_date date,
 p_approved_iso_weekdays smallint[],p_timezone_name text,
 p_reason text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $offer$
DECLARE
 v_root record;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_existing atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_created atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_subject_id uuid;v_candidate_id uuid;v_rule_version_id uuid;
 v_property_version_id uuid;
 v_reason text:=btrim(coalesce(p_reason,''));
 v_day_count integer;v_unique_count integer;
 v_timezone text:=btrim(coalesce(p_timezone_name,''));
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 IF p_action_id IS NULL OR p_first_service_day IS NULL
   OR p_campaign_end_date IS NULL OR p_first_service_day>p_campaign_end_date
   OR p_campaign_end_date>p_first_service_day+120
   OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1500
   OR v_timezone IS NULL OR length(v_timezone) NOT BETWEEN 3 AND 80
   OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names tz
       WHERE tz.name=v_timezone)
   OR p_first_service_day<(pg_catalog.now() AT TIME ZONE v_timezone)::date
   OR p_approved_iso_weekdays IS NULL
   OR coalesce(pg_catalog.array_length(p_approved_iso_weekdays,1),0) NOT BETWEEN 1 AND 7
   OR NOT (EXTRACT(ISODOW FROM p_first_service_day)::smallint
      = ANY(p_approved_iso_weekdays))
 THEN
  RAISE EXCEPTION 'Source-approved service day, timezone and bounded workdays required'
   USING ERRCODE='22023';
 END IF;
 SELECT count(*),count(DISTINCT d) INTO v_day_count,v_unique_count
 FROM pg_catalog.unnest(p_approved_iso_weekdays) AS days(d);
 IF p_approved_iso_weekdays IS DISTINCT FROM
    ARRAY(SELECT DISTINCT d FROM pg_catalog.unnest(p_approved_iso_weekdays) AS days(d)
      ORDER BY d)::smallint[]
    OR v_day_count<>v_unique_count OR EXISTS(
   SELECT 1 FROM pg_catalog.unnest(p_approved_iso_weekdays) AS days(d)
     WHERE d IS NULL OR d NOT BETWEEN 1 AND 7)
 THEN RAISE EXCEPTION 'Distinct ISO weekdays required' USING ERRCODE='22023'; END IF;

 -- R01's original writer uses the Rule's source timezone, not a client
 -- timezone claim, and admits only a short explicit human-selected horizon.
 IF v_timezone IS DISTINCT FROM coalesce(
       nullif((SELECT r.metadata->>'timezoneName'
         FROM atlas.rhythm_rules r WHERE r.id=p_source_rule_id),''),'UTC')
    OR p_first_service_day>(pg_catalog.now() AT TIME ZONE v_timezone)::date+14 THEN
  RAISE EXCEPTION 'Native rule timezone and bounded R01 service horizon required'
    USING ERRCODE='22023';
 END IF;

 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=p_accepted_standing_scope_id
   AND s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id
   AND s.scope_state='active' AND s.coverage_mode='ledger_all_work'
   AND s.worker_membership_id IS NULL
   AND s.proposed_by_person_id=v_root.actor_person_id
   AND s.accepted_by_person_id=s.worker_person_id
   AND s.accepted_at IS NOT NULL
   AND (s.valid_until IS NULL OR s.valid_until>pg_catalog.now());
 IF v_scope.id IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN RAISE EXCEPTION 'Accepted native Person scope not current'
   USING ERRCODE='42501'; END IF;

 -- Share the property umbrella lock with U1B; a paused property cannot
 -- race an accepted candidate or a new candidate selection.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u1b:'||p_organization_id::text||':'||p_ledger_id::text||':'||
  p_farm_id::text||':'||p_source_rule_id::text||':property',0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u2:offer:'||p_organization_id::text||':'||p_ledger_id::text||':'||
  p_farm_id::text||':'||p_source_rule_id::text,0));
 SELECT * INTO v_existing FROM atlas.governed_prework_candidate_offers_v1
 WHERE offered_action_id=p_action_id;
 IF v_existing.id IS NOT NULL THEN
  IF v_existing.organization_id IS DISTINCT FROM p_organization_id
     OR v_existing.ledger_id IS DISTINCT FROM p_ledger_id
     OR v_existing.farm_id IS DISTINCT FROM p_farm_id
     OR v_existing.source_rule_id IS DISTINCT FROM p_source_rule_id
     OR v_existing.accepted_standing_scope_id IS DISTINCT FROM p_accepted_standing_scope_id
     OR v_existing.target_person_id IS DISTINCT FROM v_scope.worker_person_id
     OR v_existing.first_service_day IS DISTINCT FROM p_first_service_day
     OR v_existing.campaign_end_date IS DISTINCT FROM p_campaign_end_date
     OR v_existing.approved_iso_weekdays IS DISTINCT FROM p_approved_iso_weekdays
     OR v_existing.timezone_name IS DISTINCT FROM v_timezone
     OR v_existing.reason IS DISTINCT FROM v_reason
     OR v_existing.offered_by_person_id IS DISTINCT FROM v_root.actor_person_id
     OR NOT atlas.governed_prework_offer_still_admissible_v1(v_existing.id)
  THEN RAISE EXCEPTION 'Offer replay not current or changed'
    USING ERRCODE='42501'; END IF;
  RETURN pg_catalog.jsonb_build_object('ok',true,'replayed',true,
   'contractVersion','governed_prework_candidate_offer_v1',
   'offerId',v_existing.id,'state',v_existing.offer_state,
   'candidateId',v_existing.source_candidate_id,
   'targetPersonId',v_existing.target_person_id,
   'originalWorkCreated',false,'responsibilityCreated',false);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.governed_prework_candidate_offers_v1 o
    WHERE o.target_person_id=v_scope.worker_person_id
      AND o.offer_state IN ('offered','accepted')) THEN
  RAISE EXCEPTION 'One unresolved offer already exists for this Person'
   USING ERRCODE='23514';
 END IF;

 -- Freeze the exact governing umbrella version; even an ACTIVE revision is
 -- a new authority decision and must not silently transfer an old offer.
 SELECT p.id INTO v_property_version_id
 FROM atlas.governed_farm_rulebook_scope_versions_v1 p
 WHERE p.organization_id=p_organization_id AND p.ledger_id=p_ledger_id
   AND p.farm_id=p_farm_id AND p.source_rule_id=p_source_rule_id
   AND p.scope_key='property' AND p.rule_status='active'
 ORDER BY p.rule_version DESC LIMIT 1;
 IF v_property_version_id IS NULL OR EXISTS(
   SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 later
   WHERE later.organization_id=p_organization_id
    AND later.ledger_id=p_ledger_id AND later.farm_id=p_farm_id
    AND later.source_rule_id=p_source_rule_id AND later.scope_key='property'
    AND later.rule_status<>'active'
    AND later.rule_version>(
     SELECT p.rule_version FROM atlas.governed_farm_rulebook_scope_versions_v1 p
     WHERE p.id=v_property_version_id)
 ) THEN
   RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_prework_candidate_offer_v1',
    'state','no_source_eligible_candidate','offerCreated',false,
    'originalWorkCreated',false,'responsibilityCreated',false,
    'notAnAllNeedsCensus',true);
 END IF;

 -- Same active first-party R01 source, but read-only selection instead of
 -- the old governor-direct original writer. Latest selected scope version
 -- must be active, standing, and free of unknown seasonal activation.
 SELECT s.id,s.subject_id,rp.id
 INTO v_candidate_id,v_subject_id,v_rule_version_id
 FROM atlas.rhythm_state s
 JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
   AND b.farm_id=s.farm_id AND b.organization_id=s.organization_id
   AND b.rhythm_rule_id=s.rhythm_rule_id AND b.active
 JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
   AND r.status='active' AND r.validity_interval_seconds>0
 JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=s.farm_id
 JOIN reality.entities re ON re.id=g.id AND re.identity_state='canonical'
   AND re.entity_kind='growing_object'
   AND re.metadata->>'subjectDomain'='spatial'
 JOIN LATERAL (
   SELECT v.id,v.rule_status,v.policy,v.scope_kind
   FROM atlas.governed_farm_rulebook_scope_versions_v1 v
   WHERE v.organization_id=p_organization_id AND v.ledger_id=p_ledger_id
     AND v.farm_id=p_farm_id AND v.source_rule_id=p_source_rule_id
     AND v.scope_key IN ('property','class:'||g.object_type,
                          'subject:'||g.id::text)
     AND NOT EXISTS(SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 later
       WHERE later.organization_id=v.organization_id
        AND later.ledger_id=v.ledger_id AND later.farm_id=v.farm_id
        AND later.source_rule_id=v.source_rule_id AND later.scope_key=v.scope_key
        AND later.rule_version>v.rule_version)
   ORDER BY CASE v.scope_kind WHEN 'subject' THEN 1
     WHEN 'class' THEN 2 ELSE 3 END LIMIT 1
 ) rp ON true
 WHERE s.farm_id=p_farm_id AND s.organization_id=p_organization_id
   AND s.rhythm_rule_id=p_source_rule_id AND s.state<>'paused'
   -- This first source adapter is intentionally mowing stewardship only;
   -- weed-restoration requires separately witnessed current physical condition.
   AND s.rhythm_key='mowing'
   AND EXISTS(SELECT 1 FROM atlas.mowing_area_state m
       WHERE m.object_id=s.subject_id AND m.farm_id=s.farm_id
        AND m.organization_id=p_organization_id AND m.status<>'closed')
   AND rp.rule_status='active'
   AND rp.policy->>'eligibilityMode'='standing_stewardship'
   AND pg_catalog.jsonb_array_length(
      coalesce(rp.policy->'seasonKeys','[]'::jsonb))=0
   AND EXISTS(SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 umbrella
     WHERE umbrella.organization_id=p_organization_id
       AND umbrella.ledger_id=p_ledger_id AND umbrella.farm_id=p_farm_id
       AND umbrella.source_rule_id=p_source_rule_id AND umbrella.scope_key='property'
       AND umbrella.rule_status='active'
       AND NOT EXISTS(SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 later
        WHERE later.organization_id=umbrella.organization_id
         AND later.ledger_id=umbrella.ledger_id AND later.farm_id=umbrella.farm_id
         AND later.source_rule_id=umbrella.source_rule_id
         AND later.scope_key='property' AND later.rule_version>umbrella.rule_version))
   AND atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_scope.worker_person_id,
      'spatial','growing_object',s.subject_id,'identity')
   AND atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_scope.worker_person_id,
      'spatial','growing_object',s.subject_id,'condition')
   AND atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',s.subject_id,'identity')
   AND atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',s.subject_id,'condition')
   AND NOT EXISTS(SELECT 1 FROM atlas.governed_prework_candidate_offers_v1 o
      WHERE o.source_candidate_id=s.id AND o.offer_state IN ('offered','accepted'))
   AND NOT EXISTS(SELECT 1 FROM atlas.work_items w
      WHERE w.organization_id=p_organization_id
       AND w.source_object_type='rhythm_state'
       AND w.source_object_id=s.id AND w.work_state='open')
   AND NOT EXISTS(SELECT 1 FROM atlas.tasks t
      LEFT JOIN atlas.planned_work_occurrences p
       ON p.id=t.planned_occurrence_id
      WHERE t.farm_id=p_farm_id AND t.status IN ('open','blocked')
       AND (t.metadata->>'rhythm_state_id'=s.id::text
          OR (p.source_kind='rhythm_state' AND p.source_id=s.id)))
 ORDER BY s.due_at NULLS LAST,s.id LIMIT 1;
 IF v_candidate_id IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok',true,
   'contractVersion','governed_prework_candidate_offer_v1',
   'state','no_source_eligible_candidate','offerCreated',false,
   'originalWorkCreated',false,'responsibilityCreated',false,
   'notAnAllNeedsCensus',true);
 END IF;
 INSERT INTO atlas.governed_prework_candidate_offers_v1(
  organization_id,ledger_id,farm_id,source_rule_id,source_candidate_id,
  subject_id,rule_version_id,property_rule_version_id,accepted_standing_scope_id,target_person_id,
  offered_by_person_id,first_service_day,campaign_end_date,
  approved_iso_weekdays,timezone_name,reason,source_basis,offered_action_id
 ) VALUES(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,v_candidate_id,
  v_subject_id,v_rule_version_id,v_property_version_id,p_accepted_standing_scope_id,
  v_scope.worker_person_id,v_root.actor_person_id,
  p_first_service_day,p_campaign_end_date,p_approved_iso_weekdays,
  v_timezone,v_reason,
  pg_catalog.jsonb_build_object('contractVersion','governed_prework_candidate_offer_v1',
   'ruleVersionId',v_rule_version_id,'propertyRuleVersionId',v_property_version_id,
   'sourceCandidateId',v_candidate_id,
   'sourceKind','native_rhythm_state','physicalConditionAsserted',false,
   'workerConsentRecorded',false,'rootPersonId',v_root.actor_person_id),
  p_action_id
 ) RETURNING * INTO v_created;
 IF NOT atlas.governed_prework_offer_still_admissible_v1(v_created.id) THEN
  RAISE EXCEPTION 'Candidate no longer admissible; offer rolled back'
   USING ERRCODE='42501';
 END IF;
 RETURN pg_catalog.jsonb_build_object('ok',true,
   'contractVersion','governed_prework_candidate_offer_v1',
   'state','offered','replayed',false,'offerId',v_created.id,
   'candidateId',v_created.source_candidate_id,
   'ruleVersionId',v_rule_version_id,
   'propertyRuleVersionId',v_property_version_id,
   'targetPersonId',v_created.target_person_id,
   'firstServiceDay',p_first_service_day,
   'physicalConditionAsserted',false,
   'originalWorkCreated',false,'responsibilityCreated',false);
END;
$offer$;
REVOKE ALL ON FUNCTION atlas.offer_next_governed_prework_candidate_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.respond_governed_prework_candidate_self_api_v1(
 p_offer_id uuid,p_decision text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $respond$
DECLARE
 v_actor uuid;v_principal uuid;
 v atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_state text:=lower(btrim(coalesce(p_decision,'')));
BEGIN
 v_principal:=atlas.foundry_current_signed_principal_v1();
 v_actor:=atlas.current_person_id_v1();
 IF v_principal IS NULL OR v_principal IS DISTINCT FROM atlas.current_principal_id_v1()
    OR v_actor IS NULL OR p_offer_id IS NULL OR p_action_id IS NULL
    OR v_state NOT IN ('accepted','declined') THEN
  RAISE EXCEPTION 'Signed exact Person and offer response required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v FROM atlas.governed_prework_candidate_offers_v1
 WHERE id=p_offer_id FOR UPDATE;
 IF v.id IS NULL OR v.target_person_id IS DISTINCT FROM v_actor THEN
  RAISE EXCEPTION 'Candidate offer unavailable to signed Person'
   USING ERRCODE='42501';
 END IF;
 IF v.offer_state=v_state AND v.response_action_id=p_action_id
    AND v.responding_principal_id=v_principal THEN
  RETURN pg_catalog.jsonb_build_object('ok',true,'replayed',true,
   'contractVersion','governed_prework_candidate_response_v1',
   'offerId',v.id,'state',v.offer_state,
   'originalWorkCreated',false,'responsibilityCreated',false);
 END IF;
 IF v.offer_state<>'offered' THEN
  RAISE EXCEPTION 'Offer already resolved, cannot change response'
   USING ERRCODE='23514';
 END IF;
 -- A decline is allowed without newly disclosing changed private source.
 -- Accept requires fresh rule, Subject disclosure, native connection,
 -- candidate collision, workday and capacity checks.
 IF v_state='accepted'
    AND NOT atlas.governed_prework_offer_still_admissible_v1(v.id)
 THEN
  RAISE EXCEPTION 'Current source no longer permits this candidate'
   USING ERRCODE='42501';
 END IF;
 UPDATE atlas.governed_prework_candidate_offers_v1
 SET offer_state=v_state,response_action_id=p_action_id,
   responding_principal_id=v_principal,responded_at=pg_catalog.clock_timestamp()
 WHERE id=v.id;
 RETURN pg_catalog.jsonb_build_object('ok',true,'replayed',false,
  'contractVersion','governed_prework_candidate_response_v1',
  'offerId',v.id,'state',v_state,
  'acceptanceIsNotAssignment',true,'originalWorkCreated',false,
  'responsibilityCreated',false,'workerSourcePermissionUnchanged',true);
END;
$respond$;
REVOKE ALL ON FUNCTION atlas.respond_governed_prework_candidate_self_api_v1(
 uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.read_governed_prework_candidate_inbox_self_api_v1()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $inbox$
DECLARE v_actor uuid;v_principal uuid;v_items jsonb;
BEGIN
 v_principal:=atlas.foundry_current_signed_principal_v1();
 v_actor:=atlas.current_person_id_v1();
 IF v_principal IS NULL OR v_actor IS NULL
    OR v_principal IS DISTINCT FROM atlas.current_principal_id_v1() THEN
  RAISE EXCEPTION 'Signed exact recipient required' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
  'offerId',o.id,'state',o.offer_state,'organizationId',o.organization_id,
  'ledgerId',o.ledger_id,'firstServiceDay',o.first_service_day,
  'campaignEndDate',o.campaign_end_date,'timezoneName',o.timezone_name,
  'reason',o.reason,
  'sourceRuleLabel',(SELECT r.label FROM atlas.rhythm_rules r
      WHERE r.id=o.source_rule_id),
  'subjectLabel',(SELECT g.label FROM atlas.growing_objects g
      WHERE g.id=o.subject_id),
  'sourceCandidateIdentityDisclosed',true,
  'originalWorkCreated',false,
  'acceptanceIsNotAssignment',true
 ) ORDER BY o.offered_at,o.id),'[]'::jsonb) INTO v_items
 FROM atlas.governed_prework_candidate_offers_v1 o
 WHERE o.target_person_id=v_actor AND o.offer_state='offered'
   AND atlas.governed_prework_offer_still_admissible_v1(o.id);
 RETURN pg_catalog.jsonb_build_object('ok',true,
  'contractVersion','governed_prework_candidate_inbox_v1',
  'items',v_items,'hasMore',false,
  'notACompleteWorkList',true,'originalWorkCreated',false);
END;
$inbox$;
REVOKE ALL ON FUNCTION atlas.read_governed_prework_candidate_inbox_self_api_v1()
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.offer_next_governed_prework_candidate_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_accepted_standing_scope_id uuid,
 p_first_service_day date,p_campaign_end_date date,
 p_approved_iso_weekdays smallint[],p_timezone_name text,
 p_reason text,p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.offer_next_governed_prework_candidate_self_api_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,
 p_accepted_standing_scope_id,p_first_service_day,p_campaign_end_date,
 p_approved_iso_weekdays,p_timezone_name,p_reason,p_action_id);
$transport$;
REVOKE ALL ON FUNCTION public.offer_next_governed_prework_candidate_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.offer_next_governed_prework_candidate_self_api_v1(
 uuid,uuid,uuid,uuid,uuid,date,date,smallint[],text,text,uuid)
 TO authenticated;

CREATE FUNCTION public.respond_governed_prework_candidate_self_api_v1(
 p_offer_id uuid,p_decision text,p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.respond_governed_prework_candidate_self_api_v1(
  p_offer_id,p_decision,p_action_id);
$transport$;
REVOKE ALL ON FUNCTION public.respond_governed_prework_candidate_self_api_v1(
 uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.respond_governed_prework_candidate_self_api_v1(
 uuid,text,uuid) TO authenticated;

CREATE FUNCTION public.read_governed_prework_candidate_inbox_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.read_governed_prework_candidate_inbox_self_api_v1();
$transport$;
REVOKE ALL ON FUNCTION public.read_governed_prework_candidate_inbox_self_api_v1()
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_governed_prework_candidate_inbox_self_api_v1()
 TO authenticated;

-- Deliberately NO fulfilled/Work writer here. It must consume one accepted
-- offer under a fresh native source-qualified original writer and capacity
-- lock in U2B. No client or test harness may set offer_state='fulfilled'.
