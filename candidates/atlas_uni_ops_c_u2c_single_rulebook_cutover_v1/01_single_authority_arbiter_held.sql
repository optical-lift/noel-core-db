-- UNI-OPS-01 Option C / U2C SINGLE RULEBOOK AUTHORITY (HELD).
-- NOT A MIGRATION, NOT A RELEASE. Depends on exact U1A + U1B + U2A.
--
-- The physical SOURCE histories remain immutable and separate:
--   U1A foundry-reviewed, exact canonical Subject Rulebook decisions;
--   U1B already-recorded native farm-rule/property/class/Subject decisions.
-- ONE private arbiter is the authority for every U2 standing candidate.
-- If a latest nonretired U1A decision exists for the same canonical Subject,
-- U1B is NOT silently preferred: the Subject is held for adjudication.
-- No new policy interpretation or unreviewed source mapping is invented.
-- Both rule-version IDs are frozen before offers. Still no Work execution.

CREATE FUNCTION atlas.resolve_governed_canonical_farm_rule_authority_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_subject_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $arbiter$
DECLARE
 v_object atlas.growing_objects%ROWTYPE;
 v_parent atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
 v_effective atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
 v_u1a_disputed boolean;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_farm_id IS NULL OR p_source_rule_id IS NULL OR p_subject_id IS NULL
 THEN
   RETURN pg_catalog.jsonb_build_object(
    'ok',false,'state','unavailable','candidateOfferAdmissible',false,
    'policyExecutable',false);
 END IF;
 -- Verify actual canonical Subject, native source relationship, existing
 -- farm crop custody and governing Ledger. This is NOT a general Subject
 -- disclosure function; the caller must independently prove its actor.
 SELECT g.* INTO v_object FROM atlas.growing_objects g
 JOIN reality.entities re ON re.id=g.id AND re.identity_state='canonical'
   AND re.entity_kind='growing_object'
   AND re.metadata->>'subjectDomain'='spatial'
 WHERE g.id=p_subject_id AND g.farm_id=p_farm_id;
 IF v_object.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.farms f
   JOIN atlas.farm_crop_ledger_custody_v1 c ON c.farm_id=f.id
     AND c.ledger_id=p_ledger_id AND c.custody_state='active'
     AND c.ended_at IS NULL
   JOIN atlas.ledger_organization_participations lop
     ON lop.organization_id=f.organization_id AND lop.ledger_id=c.ledger_id
    AND lop.status='active' AND lop.ended_at IS NULL
    AND lop.participation_kind='governing'
    AND lop.is_compatibility_primary=true
   WHERE f.id=p_farm_id AND f.organization_id=p_organization_id
     AND f.status='active')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.rhythm_state s
      JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
        AND r.status='active' AND r.validity_interval_seconds>0
      JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
        AND b.organization_id=s.organization_id AND b.farm_id=s.farm_id
        AND b.rhythm_rule_id=s.rhythm_rule_id AND b.active
      WHERE s.organization_id=p_organization_id AND s.farm_id=p_farm_id
        AND s.subject_id=p_subject_id AND s.rhythm_rule_id=p_source_rule_id
        AND s.subject_kind='growing_object' AND s.state<>'paused'
        -- Only this R01 standing mowing source adapter is admitted so far.
        AND s.rhythm_key='mowing'
        AND EXISTS(SELECT 1 FROM atlas.mowing_area_state m
          WHERE m.object_id=s.subject_id AND m.farm_id=s.farm_id
            AND m.organization_id=s.organization_id AND m.status<>'closed'))
 THEN
   RETURN pg_catalog.jsonb_build_object('ok',false,
    'state','native_source_unavailable','candidateOfferAdmissible',false,
    'policyExecutable',false);
 END IF;

 -- A source decision is unresolved until its owning historical path
 -- explicitly retires it. Current Foundry custody revocation never makes
 -- a still-active U1A policy transferable to another source family.
 SELECT EXISTS (
  SELECT 1 FROM atlas.governed_rulebook_versions_v1 a
  WHERE a.organization_id=p_organization_id AND a.ledger_id=p_ledger_id
    AND a.subject_entity_id=p_subject_id
    AND a.rule_status<>'retired'
    AND NOT EXISTS (
      SELECT 1 FROM atlas.governed_rulebook_versions_v1 later
      WHERE later.organization_id=a.organization_id
        AND later.ledger_id=a.ledger_id
        AND later.rule_key=a.rule_key
        AND later.rule_version>a.rule_version)
 ) INTO v_u1a_disputed;
 IF v_u1a_disputed THEN
   RETURN pg_catalog.jsonb_build_object(
     'ok',true,'contractVersion','governed_single_rulebook_authority_v1',
     'state','held_cross_source_unreconciled',
     'authoritySource','none','candidateOfferAdmissible',false,
     'policyExecutable',false,'workCreated',false,
     'subjectId',p_subject_id,'sourceRuleId',p_source_rule_id,
     'reconciliationRequired',true);
 END IF;

 -- Latest property policy is always the umbrella. Pausing or retiring it
 -- suspends all child source choices; an older active cannot reappear.
 SELECT r.* INTO v_parent FROM atlas.governed_farm_rulebook_scope_versions_v1 r
 WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.farm_id=p_farm_id AND r.source_rule_id=p_source_rule_id
   AND r.scope_key='property'
 ORDER BY r.rule_version DESC LIMIT 1;
 IF v_parent.id IS NULL THEN
   RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_single_rulebook_authority_v1',
    'state','not_established','authoritySource','none',
    'candidateOfferAdmissible',false,'policyExecutable',false,
    'workCreated',false,'subjectId',p_subject_id,
    'sourceRuleId',p_source_rule_id);
 END IF;
 IF v_parent.rule_status<>'active' THEN
   RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_single_rulebook_authority_v1',
    'state','held_property_umbrella',
    'authoritySource','none','candidateOfferAdmissible',false,
    'policyExecutable',false,'workCreated',false,
    'subjectId',p_subject_id,'sourceRuleId',p_source_rule_id);
 END IF;

 SELECT r.* INTO v_effective
 FROM atlas.governed_farm_rulebook_scope_versions_v1 r
 WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.farm_id=p_farm_id AND r.source_rule_id=p_source_rule_id
   AND r.scope_key IN ('property','class:'||v_object.object_type,
                      'subject:'||p_subject_id::text)
   AND NOT EXISTS (
     SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 later
     WHERE later.organization_id=r.organization_id
       AND later.ledger_id=r.ledger_id AND later.farm_id=r.farm_id
       AND later.source_rule_id=r.source_rule_id
       AND later.scope_key=r.scope_key
       AND later.rule_version>r.rule_version)
 ORDER BY CASE r.scope_kind WHEN 'subject' THEN 1
     WHEN 'class' THEN 2 ELSE 3 END LIMIT 1;
 IF v_effective.id IS NULL OR v_effective.rule_status<>'active'
 THEN
   RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_single_rulebook_authority_v1',
    'state','held_effective_scope',
    'authoritySource','none','candidateOfferAdmissible',false,
    'policyExecutable',false,'workCreated',false,
    'subjectId',p_subject_id,'sourceRuleId',p_source_rule_id);
 END IF;

 -- Option C's first standing adapter does not resolve named seasons or
 -- corrective physical conditions. A clock NEVER proves observed weeds.
 IF v_parent.policy->>'eligibilityMode'<>'standing_stewardship'
    OR v_effective.policy->>'eligibilityMode'<>'standing_stewardship'
    OR pg_catalog.jsonb_typeof(coalesce(
      v_effective.policy->'seasonKeys','[]'::jsonb))<>'array'
    OR pg_catalog.jsonb_array_length(coalesce(
      v_effective.policy->'seasonKeys','[]'::jsonb))<>0
    OR pg_catalog.jsonb_typeof(coalesce(
      v_parent.policy->'seasonKeys','[]'::jsonb))<>'array'
    OR pg_catalog.jsonb_array_length(coalesce(
      v_parent.policy->'seasonKeys','[]'::jsonb))<>0
 THEN
   RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_single_rulebook_authority_v1',
    'state','held_evidence_or_season',
    'authoritySource','none','candidateOfferAdmissible',false,
    'policyExecutable',false,'workCreated',false,
    'subjectId',p_subject_id,'sourceRuleId',p_source_rule_id);
 END IF;

 RETURN pg_catalog.jsonb_build_object(
   'ok',true,'contractVersion','governed_single_rulebook_authority_v1',
   'state','native_source_admitted_for_offer',
   'authoritySource','native_farm_rulebook_v1',
   'sourceRuleId',p_source_rule_id,'subjectId',p_subject_id,
   'propertyRuleVersionId',v_parent.id,
   'effectiveRuleVersionId',v_effective.id,
   'effectiveScopeKind',v_effective.scope_kind,
   'sourceOnly',true,'crossSourceUncontested',true,
   'candidateOfferAdmissible',true,'policyExecutable',false,
   'workCreated',false,'physicalConditionAsserted',false);
END;
$arbiter$;
REVOKE ALL ON FUNCTION atlas.resolve_governed_canonical_farm_rule_authority_v1(
 uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Shared Subject-resolution lock: an U1A decision INSERT and an U2 offer/
-- acceptance/finalization cannot interleave after reading different policy
-- histories. Existing U1A append-only UPDATE/DELETE barriers are unchanged.
CREATE FUNCTION atlas.lock_governed_single_rulebook_u1a_insert_v1()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $lock$
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'uni-ops:canonical-subject:'||NEW.organization_id::text||':'||
     NEW.ledger_id::text||':'||NEW.subject_entity_id::text,0));
 RETURN NEW;
END;
$lock$;
REVOKE ALL ON FUNCTION atlas.lock_governed_single_rulebook_u1a_insert_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER governed_single_rulebook_u1a_source_lock_v1
 BEFORE INSERT ON atlas.governed_rulebook_versions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.lock_governed_single_rulebook_u1a_insert_v1();

-- Protect the existing U2 source writers without duplicating them. The same
-- immutable source IDs must still resolve to ONE current native authority
-- before a candidate offer can be created, accepted, or fulfilled.
-- A declined/withdrawn response remains permitted despite later revocation.
CREATE FUNCTION atlas.require_single_rulebook_on_prework_transition_v1()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $single$
DECLARE v_truth jsonb;
BEGIN
 IF NEW.offer_state IN ('offered','accepted','fulfilled') THEN
   PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
     'uni-ops:canonical-subject:'||NEW.organization_id::text||':'||
        NEW.ledger_id::text||':'||NEW.subject_id::text,0));
   v_truth:=atlas.resolve_governed_canonical_farm_rule_authority_v1(
     NEW.organization_id,NEW.ledger_id,NEW.farm_id,
     NEW.source_rule_id,NEW.subject_id);
   IF v_truth->>'state' IS DISTINCT FROM 'native_source_admitted_for_offer'
      OR v_truth->>'candidateOfferAdmissible' IS DISTINCT FROM 'true'
      OR v_truth->>'crossSourceUncontested' IS DISTINCT FROM 'true'
      OR v_truth->>'propertyRuleVersionId'
         IS DISTINCT FROM NEW.property_rule_version_id::text
      OR v_truth->>'effectiveRuleVersionId'
         IS DISTINCT FROM NEW.rule_version_id::text
   THEN
     RAISE EXCEPTION 'Canonical Rulebook authority for this Subject is held'
      USING ERRCODE='42501';
   END IF;
 END IF;
 RETURN NEW;
END;
$single$;
REVOKE ALL ON FUNCTION atlas.require_single_rulebook_on_prework_transition_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER governed_prework_canonical_rulebook_gate_v1
 BEFORE INSERT OR UPDATE OF offer_state,source_rule_id,
   subject_id,rule_version_id,property_rule_version_id
 ON atlas.governed_prework_candidate_offers_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.require_single_rulebook_on_prework_transition_v1();

-- A READ of the same arbiter is available to only the exact current native
-- root with per-Subject independent identity + condition disclosure. No
-- generic policy/Subject enumeration, permissions or Work exposure.
CREATE FUNCTION atlas.read_governed_canonical_rulebook_root_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_subject_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $read$
DECLARE v_root record;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 IF p_subject_id IS NULL
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',p_subject_id,'identity'),false)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',p_subject_id,'condition'),false)
 THEN
   RAISE EXCEPTION 'Exact current Subject disclosure required'
     USING ERRCODE='42501';
 END IF;
 RETURN atlas.resolve_governed_canonical_farm_rule_authority_v1(
  p_organization_id,p_ledger_id,p_farm_id,
  p_source_rule_id,p_subject_id);
END;
$read$;
REVOKE ALL ON FUNCTION atlas.read_governed_canonical_rulebook_root_self_api_v1(
 uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.read_governed_canonical_rulebook_root_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_subject_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public_read$
 SELECT atlas.read_governed_canonical_rulebook_root_self_api_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,p_subject_id);
$public_read$;
REVOKE ALL ON FUNCTION public.read_governed_canonical_rulebook_root_self_api_v1(
 uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_governed_canonical_rulebook_root_self_api_v1(
 uuid,uuid,uuid,uuid,uuid) TO authenticated;

-- No public Work writer or owner override added. This cutover is not an
-- acceptance gate until separately installed and signed-verified in a clone.
