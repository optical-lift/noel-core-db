-- UNI-OPS-01 universal COMMON source preflight. HELD SOURCE ONLY.
-- No migration number, production approval, identity link, data backfill,
-- domain adapter, independent Foundry review, Rulebook adoption or Work action.
-- A PASS HERE IS *NOT* a policy, Subject-domain admission or issuance grant.
-- Canonical source ownership: Noel. No public API, no new identity registry.
BEGIN;

CREATE FUNCTION atlas.universal_rulebook_common_source_preflight_internal_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_requirement_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $common_source$
DECLARE
  v_person_id uuid;
  v_principal_id uuid;
  v_requirement atlas.work_requirements%ROWTYPE;
  v_subject reality.entities%ROWTYPE;
  v_domain text;
  v_need_key text;
BEGIN
  IF p_organization_id IS NULL
     OR p_ledger_id IS NULL
     OR p_requirement_id IS NULL THEN
    RAISE EXCEPTION 'Exact native source required' USING ERRCODE='42501';
  END IF;

  -- Current first-party authenticated session, NOT supplied actor claims.
  v_principal_id := atlas.foundry_current_signed_principal_v1();
  v_person_id := atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  IF v_principal_id IS NULL OR v_person_id IS NULL
     OR v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1() THEN
    RAISE EXCEPTION 'Current native root unavailable' USING ERRCODE='42501';
  END IF;

  -- Exactly the current governing primary Ledger, never membership by proximity.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.ledger_organization_participations lp
    WHERE lp.organization_id=p_organization_id
      AND lp.ledger_id=p_ledger_id
      AND lp.status='active'
      AND lp.ended_at IS NULL
      AND lp.participation_kind='governing'
      AND lp.is_compatibility_primary=true
  ) THEN
    RAISE EXCEPTION 'Current governing Ledger unavailable'
      USING ERRCODE='42501';
  END IF;

  -- An existing, explicitly source-linked Need. Neither old tasks nor labels
  -- acquire canonical status from resemblance or a guessed stable key.
  SELECT * INTO v_requirement
  FROM atlas.work_requirements w
  WHERE w.id=p_requirement_id
    AND w.organization_id=p_organization_id
    AND w.state='active'
    AND w.source_object_type='reality_entity'
    AND w.source_object_id IS NOT NULL;
  v_need_key := nullif(btrim(v_requirement.metadata->>'needKey'),'');
  IF v_requirement.id IS NULL
     OR v_need_key IS NULL
     OR length(v_need_key) NOT BETWEEN 2 AND 120 THEN
    RAISE EXCEPTION 'Canonical Requirement source unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Domain-neutral canonical Subject: no fixed farm, person, house, school,
  -- event or finance kind. A declared domain is NOT evidence of its authority.
  SELECT * INTO v_subject
  FROM reality.entities e
  WHERE e.id=v_requirement.source_object_id
    AND e.identity_state='canonical';
  v_domain := nullif(btrim(v_subject.metadata->>'subjectDomain'),'');
  IF v_subject.id IS NULL
     OR nullif(btrim(v_subject.entity_kind),'') IS NULL
     OR v_domain IS NULL
     OR length(v_domain)>120 THEN
    RAISE EXCEPTION 'Canonical Subject source unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Both independently current information-type disclosures are needed.
  -- Do not inherit subject information from a Ledger seat or a policy label.
  IF NOT coalesce(atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person_id,v_domain,
       v_subject.entity_kind,v_subject.id,'identity'),false)
     OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person_id,v_domain,
       v_subject.entity_kind,v_subject.id,'condition'),false) THEN
    RAISE EXCEPTION 'Current Subject disclosure unavailable'
      USING ERRCODE='42501';
  END IF;

  -- This is only the COMMON layer. A separately source-reviewed domain
  -- adapter must prove the actual Subject/source-family jurisdiction, and
  -- a genuine independently reviewed Foundry source must still qualify the
  -- specific authored policy. No truth is manufactured by this preflight.
  RETURN jsonb_build_object(
    'ok',true,
    'state','common_checks_only_not_admitted',
    'requirementId',v_requirement.id,
    'subjectEntityId',v_subject.id,
    'declaredSubjectDomain',v_domain,
    'subjectKind',v_subject.entity_kind,
    'needKey',v_need_key,
    'domainAdapterAccepted',false,
    'independentSourceReviewAccepted',false,
    'policyAdoptable',false,
    'policyExecutable',false,
    'workCreated',false,
    'clockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$common_source$;

-- No callable public wrapper. Only later source-reviewed private domain
-- adapters may compose this generic result into an independent authorization.
REVOKE ALL ON FUNCTION
  atlas.universal_rulebook_common_source_preflight_internal_v1(
    uuid,uuid,uuid
  ) FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
