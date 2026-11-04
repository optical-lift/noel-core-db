-- UNI-OPS-01 Option C / U1B, HELD SOURCE ONLY. NOT A MIGRATION.
-- Extends held U1A (#2465) without widening its exact-Subject writer.
-- One native first-party rhythm rule may receive independently signed,
-- immutable property (farm), class (native growing_object.object_type), and
-- exact Subject decisions. A class does NOT grant Subject disclosure.
-- No policy evaluation, autonomous Work, offer, Actual or Clock writes.
-- Installation requires U1A source + real native custody dependencies.

CREATE TABLE atlas.governed_farm_rulebook_scope_versions_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_rule_id uuid NOT NULL REFERENCES atlas.rhythm_rules(id) ON DELETE RESTRICT,
 scope_kind text NOT NULL CHECK (scope_kind IN ('property','class','subject')),
 scope_key text NOT NULL CHECK (length(scope_key) BETWEEN 8 AND 140),
 scope_ref text NOT NULL CHECK (length(scope_ref) BETWEEN 1 AND 100),
 rule_version integer NOT NULL CHECK (rule_version BETWEEN 1 AND 100000),
 rule_status text NOT NULL CHECK (rule_status IN ('active','paused','retired')),
 policy jsonb NOT NULL CHECK (jsonb_typeof(policy)='object'),
 source_basis jsonb NOT NULL CHECK (jsonb_typeof(source_basis)='object'),
 previous_version_id uuid REFERENCES atlas.governed_farm_rulebook_scope_versions_v1(id)
   ON DELETE RESTRICT,
 actor_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 actor_principal_id uuid NOT NULL,
 decision_action_id uuid NOT NULL UNIQUE,
 recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 UNIQUE (organization_id,ledger_id,farm_id,source_rule_id,scope_key,rule_version),
 CHECK (
   (scope_kind='property' AND scope_ref='property' AND scope_key='property')
   OR (scope_kind='class' AND scope_key='class:'||scope_ref)
   OR (scope_kind='subject' AND scope_key='subject:'||scope_ref)
 )
);
COMMENT ON TABLE atlas.governed_farm_rulebook_scope_versions_v1 IS
 'Held U1B native first-party farm-rule approvals only. Latest scoped version wins even when paused, so older active decisions never silently reactivate. No executable Work.';

CREATE INDEX governed_farm_rulebook_latest_scope_v1
 ON atlas.governed_farm_rulebook_scope_versions_v1(
 organization_id,ledger_id,farm_id,source_rule_id,scope_key,rule_version DESC);

CREATE TRIGGER governed_farm_rulebook_versions_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.governed_farm_rulebook_scope_versions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1();

ALTER TABLE atlas.governed_farm_rulebook_scope_versions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.governed_farm_rulebook_scope_versions_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- Same current native signed Person and governing root as U1A, with an
-- independent explicit farm→Ledger custody and active first-party source Rule.
CREATE FUNCTION atlas.require_governed_farm_rulebook_root_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,p_source_rule_id uuid
) RETURNS TABLE(actor_person_id uuid,actor_principal_id uuid,source_label text,
 cadence_seconds bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $root$
DECLARE
 v_actor uuid;
 v_principal uuid;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_farm_id IS NULL
    OR p_source_rule_id IS NULL THEN
  RAISE EXCEPTION 'Exact farm source is required' USING ERRCODE='42501';
 END IF;
 v_principal:=atlas.foundry_current_signed_principal_v1();
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(
  p_organization_id,p_ledger_id);
 IF v_principal IS NULL OR v_actor IS NULL
    OR v_principal IS DISTINCT FROM atlas.current_principal_id_v1()
    OR NOT EXISTS(
      SELECT 1 FROM atlas.ledger_organization_participations l
      WHERE l.organization_id=p_organization_id AND l.ledger_id=p_ledger_id
       AND l.status='active' AND l.ended_at IS NULL
       AND l.participation_kind='governing'
       AND l.is_compatibility_primary=true)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms f
      JOIN atlas.farm_crop_ledger_custody_v1 c ON c.farm_id=f.id
       AND c.ledger_id=p_ledger_id AND c.custody_state='active'
       AND c.ended_at IS NULL
      WHERE f.id=p_farm_id AND f.organization_id=p_organization_id
       AND f.status='active')
 THEN
  RAISE EXCEPTION 'Current exact root/farm custody unavailable'
    USING ERRCODE='42501';
 END IF;
 SELECT r.label,r.validity_interval_seconds INTO source_label,cadence_seconds
 FROM atlas.rhythm_rules r
 WHERE r.id=p_source_rule_id AND r.status='active'
   AND r.validity_interval_seconds>0
   AND EXISTS(SELECT 1 FROM atlas.rhythm_bindings b
     WHERE b.rhythm_rule_id=r.id AND b.farm_id=p_farm_id
       AND b.organization_id=p_organization_id AND b.active);
 IF source_label IS NULL THEN
  RAISE EXCEPTION 'Original first-party rhythm source unavailable'
   USING ERRCODE='42501';
 END IF;
 actor_person_id:=v_actor;
 actor_principal_id:=v_principal;
 RETURN NEXT;
END;
$root$;
REVOKE ALL ON FUNCTION atlas.require_governed_farm_rulebook_root_v1(
 uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Strictly source-reconstructed approval. Reuse a genuinely recorded native
-- source rule; do not re-interview or manufacture a Foundry event for old work.
-- Each property/class/exact Subject action must be approved individually.
CREATE FUNCTION atlas.adopt_governed_farm_rulebook_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_scope_kind text,p_scope_ref text,
 p_policy jsonb,p_decision text,p_expected_previous_version_id uuid,
 p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $adopt$
DECLARE
 v_root record;
 v_scope_key text;
 v_ref text:=btrim(coalesce(p_scope_ref,''));
 v_prior atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
 v_replay atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
 v_created atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
 v_subject_id uuid;
 v_next integer;
 v_basis jsonb;
 v_seasons jsonb;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 IF p_action_id IS NULL OR coalesce(p_scope_kind,'') NOT IN ('property','class','subject')
   OR coalesce(p_decision,'') NOT IN ('active','paused','retired')
   OR length(v_ref) NOT BETWEEN 1 AND 100
   OR p_policy IS NULL OR pg_catalog.jsonb_typeof(p_policy)<>'object'
   OR pg_catalog.octet_length(p_policy::text)>8192
   OR coalesce(p_policy->>'eligibilityMode','') NOT IN
     ('standing_stewardship','condition_triggered')
   OR length(btrim(coalesce(p_policy->>'desiredOutcome',''))) NOT BETWEEN 4 AND 600
   OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_object_keys(p_policy) AS k(key)
     WHERE k.key NOT IN ('eligibilityMode','desiredOutcome','standingPurpose',
       'triggerMode','strategyDisposition','maxObservationAgeSeconds',
       'seasonKeys','priority'))
 THEN
  RAISE EXCEPTION 'Bounded source-specific Rulebook decision required'
   USING ERRCODE='22023';
 END IF;
 IF (p_policy->>'eligibilityMode'='standing_stewardship'
      AND length(btrim(coalesce(p_policy->>'standingPurpose',''))) NOT BETWEEN 4 AND 600)
   OR (p_policy->>'eligibilityMode'='condition_triggered'
      AND (coalesce(p_policy->>'triggerMode','') NOT IN
         ('condition_only','condition_and_window')
        OR coalesce(p_policy->>'strategyDisposition','') NOT IN
         ('allow_action','hold','review_required')
        OR coalesce(p_policy->>'maxObservationAgeSeconds','') !~ '^[0-9]{1,7}$'
        OR (p_policy->>'maxObservationAgeSeconds')::integer NOT BETWEEN 60 AND 2592000))
 THEN
  RAISE EXCEPTION 'Typed standing or evidenced corrective rule required'
   USING ERRCODE='22023';
 END IF;
 IF p_policy ? 'priority' AND
    (coalesce(p_policy->>'priority','') !~ '^[-]?[0-9]{1,4}$'
     OR (p_policy->>'priority')::integer NOT BETWEEN -1000 AND 1000) THEN
  RAISE EXCEPTION 'Bounded priority required' USING ERRCODE='22023';
 END IF;
 v_seasons:=coalesce(p_policy->'seasonKeys','[]'::jsonb);
 IF pg_catalog.jsonb_typeof(v_seasons)<>'array'
    OR pg_catalog.jsonb_array_length(v_seasons)>24
    OR EXISTS(SELECT 1 FROM pg_catalog.jsonb_array_elements(v_seasons) AS s(value)
      WHERE pg_catalog.jsonb_typeof(s.value)<>'string'
       OR length(btrim(s.value #>> '{}')) NOT BETWEEN 1 AND 80) THEN
  RAISE EXCEPTION 'Explicit bounded season names required' USING ERRCODE='22023';
 END IF;

 CASE p_scope_kind
 WHEN 'property' THEN
  IF v_ref<>'property' THEN
   RAISE EXCEPTION 'Property uses exact farm source' USING ERRCODE='42501';
  END IF;
  v_scope_key:='property';
 WHEN 'class' THEN
  IF NOT EXISTS(SELECT 1 FROM atlas.growing_objects g
    JOIN atlas.rhythm_state s ON s.subject_id=g.id
      AND s.farm_id=g.farm_id AND s.organization_id=p_organization_id
      AND s.rhythm_rule_id=p_source_rule_id
    WHERE g.farm_id=p_farm_id AND g.object_type=v_ref) THEN
   RAISE EXCEPTION 'A real native source class is required' USING ERRCODE='42501';
  END IF;
  v_scope_key:='class:'||v_ref;
 WHEN 'subject' THEN
  IF v_ref !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'Canonical exact Subject required' USING ERRCODE='42501';
  END IF;
  v_subject_id:=v_ref::uuid;
  v_ref:=v_subject_id::text;
  IF NOT EXISTS(SELECT 1 FROM atlas.growing_objects g
    JOIN reality.entities re ON re.id=g.id
     AND re.identity_state='canonical' AND re.entity_kind='growing_object'
     AND re.metadata->>'subjectDomain'='spatial'
    JOIN atlas.rhythm_state s ON s.subject_id=g.id
      AND s.farm_id=g.farm_id AND s.organization_id=p_organization_id
      AND s.rhythm_rule_id=p_source_rule_id
    WHERE g.id=v_subject_id AND g.farm_id=p_farm_id)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',v_subject_id,'identity'),false)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',v_subject_id,'condition'),false) THEN
   RAISE EXCEPTION 'Current exact native Subject authority unavailable'
    USING ERRCODE='42501';
  END IF;
  v_scope_key:='subject:'||v_subject_id::text;
 END CASE;

 -- Serialize the property umbrella first, including every child exception,
 -- so a concurrent property pause cannot race a new active class decision.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u1b:'||p_organization_id::text||':'||p_ledger_id::text||':'||
  p_farm_id::text||':'||p_source_rule_id::text||':property',0));

 -- A class or Subject exception needs an explicitly active umbrella for
 -- this same first-party rule; no parallel self-authorized namespace.
 IF p_scope_kind<>'property' AND NOT EXISTS(
   SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 parent
   WHERE parent.organization_id=p_organization_id AND parent.ledger_id=p_ledger_id
     AND parent.farm_id=p_farm_id AND parent.source_rule_id=p_source_rule_id
     AND parent.scope_key='property' AND parent.rule_status='active'
     AND NOT EXISTS(SELECT 1
       FROM atlas.governed_farm_rulebook_scope_versions_v1 later
       WHERE later.organization_id=parent.organization_id
         AND later.ledger_id=parent.ledger_id
         AND later.farm_id=parent.farm_id AND later.source_rule_id=parent.source_rule_id
         AND later.scope_key=parent.scope_key
         AND later.rule_version>parent.rule_version)
 ) THEN
  RAISE EXCEPTION 'Active approved property umbrella is required'
   USING ERRCODE='42501';
 END IF;

 v_basis:=pg_catalog.jsonb_build_object(
  'contractVersion','governed_native_farm_rulebook_scope_v1',
  'sourceKind','legacy_native_rhythm_rule',
  'sourceRuleId',p_source_rule_id,'sourceRuleLabel',v_root.source_label,
  'sourceCadenceSeconds',v_root.cadence_seconds,
  'farmId',p_farm_id,'scopeKind',p_scope_kind,'scopeKey',v_scope_key,
  'sourceActorPrincipalId',v_root.actor_principal_id,
  'recordedSourceReusedWithoutNewInterview',true);

 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u1b:'||p_organization_id::text||':'||p_ledger_id::text||':'||
  p_farm_id::text||':'||p_source_rule_id::text||':'||v_scope_key,0));

 SELECT * INTO v_replay FROM atlas.governed_farm_rulebook_scope_versions_v1
 WHERE decision_action_id=p_action_id;
 IF v_replay.id IS NOT NULL THEN
  IF v_replay.organization_id IS DISTINCT FROM p_organization_id
    OR v_replay.ledger_id IS DISTINCT FROM p_ledger_id
    OR v_replay.farm_id IS DISTINCT FROM p_farm_id
    OR v_replay.source_rule_id IS DISTINCT FROM p_source_rule_id
    OR v_replay.scope_key IS DISTINCT FROM v_scope_key
    OR v_replay.rule_status IS DISTINCT FROM p_decision
    OR v_replay.policy IS DISTINCT FROM p_policy
    OR v_replay.source_basis IS DISTINCT FROM v_basis
    OR v_replay.actor_person_id IS DISTINCT FROM v_root.actor_person_id
    OR v_replay.actor_principal_id IS DISTINCT FROM v_root.actor_principal_id
    OR v_replay.previous_version_id IS DISTINCT FROM p_expected_previous_version_id THEN
   RAISE EXCEPTION 'Rulebook source action mismatch' USING ERRCODE='23505';
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok',true,'replayed',true,
   'contractVersion','governed_native_farm_rulebook_scope_v1',
   'ruleVersionId',v_replay.id,'ruleVersion',v_replay.rule_version,
   'ruleStatus',v_replay.rule_status,
   'sourceRuleId',p_source_rule_id,'scopeKey',v_scope_key,
   'policyExecutable',false,'workCreated',false);
 END IF;
 SELECT * INTO v_prior FROM atlas.governed_farm_rulebook_scope_versions_v1 r
 WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.farm_id=p_farm_id AND r.source_rule_id=p_source_rule_id
   AND r.scope_key=v_scope_key ORDER BY r.rule_version DESC LIMIT 1 FOR UPDATE;
 IF v_prior.id IS NULL THEN
  IF p_expected_previous_version_id IS NOT NULL OR p_decision<>'active' THEN
   RAISE EXCEPTION 'Initial scoped adoption must be active' USING ERRCODE='42501';
  END IF;
  v_next:=1;
 ELSE
  IF v_prior.id IS DISTINCT FROM p_expected_previous_version_id
    OR v_prior.rule_status='retired'
    OR v_prior.rule_version>=100000
    OR (p_decision IN ('paused','retired') AND p_policy IS DISTINCT FROM v_prior.policy)
  THEN
   RAISE EXCEPTION 'Stale, retired, or policy-changing pause/retire denied'
    USING ERRCODE='42501';
  END IF;
  v_next:=v_prior.rule_version+1;
 END IF;
 INSERT INTO atlas.governed_farm_rulebook_scope_versions_v1(
  organization_id,ledger_id,farm_id,source_rule_id,scope_kind,scope_key,
  scope_ref,rule_version,rule_status,policy,source_basis,previous_version_id,
  actor_person_id,actor_principal_id,decision_action_id
 ) VALUES(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,p_scope_kind,
  v_scope_key,v_ref,v_next,p_decision,p_policy,v_basis,
  p_expected_previous_version_id,v_root.actor_person_id,
  v_root.actor_principal_id,p_action_id
 ) RETURNING * INTO v_created;
 RETURN pg_catalog.jsonb_build_object('ok',true,'replayed',false,
   'contractVersion','governed_native_farm_rulebook_scope_v1',
   'ruleVersionId',v_created.id,'ruleVersion',v_created.rule_version,
   'ruleStatus',v_created.rule_status,
   'sourceRuleId',p_source_rule_id,'scopeKey',v_scope_key,
   'policyExecutable',false,'workCreated',false);
END;
$adopt$;
REVOKE ALL ON FUNCTION atlas.adopt_governed_farm_rulebook_scope_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Authorized root effective inspection for ONE known native Subject, not a
-- Ledger roster. Latest version per scope always wins; an explicit paused
-- class/Subject overrides an older active parent and does not fall back.
CREATE FUNCTION atlas.read_governed_farm_rulebook_effective_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_subject_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $effective$
DECLARE
 v_root record;v_object atlas.growing_objects%ROWTYPE;
 v_selected atlas.governed_farm_rulebook_scope_versions_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
  p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id);
 SELECT g.* INTO v_object FROM atlas.growing_objects g
 JOIN reality.entities e ON e.id=g.id
  AND e.identity_state='canonical' AND e.entity_kind='growing_object'
  AND e.metadata->>'subjectDomain'='spatial'
 WHERE g.id=p_subject_id AND g.farm_id=p_farm_id;
 IF v_object.id IS NULL
    OR NOT EXISTS(SELECT 1 FROM atlas.rhythm_state s
       WHERE s.subject_id=v_object.id AND s.farm_id=p_farm_id
         AND s.organization_id=p_organization_id
         AND s.rhythm_rule_id=p_source_rule_id)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',p_subject_id,'identity'),false)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_root.actor_person_id,
      'spatial','growing_object',p_subject_id,'condition'),false) THEN
  RAISE EXCEPTION 'Exact Subject Rulebook read unavailable'
   USING ERRCODE='42501';
 END IF;
 SELECT r.* INTO v_selected
 FROM atlas.governed_farm_rulebook_scope_versions_v1 r
 WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.farm_id=p_farm_id AND r.source_rule_id=p_source_rule_id
   AND r.scope_key IN ('property','class:'||v_object.object_type,
                      'subject:'||v_object.id::text)
   AND NOT EXISTS(SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 x
    WHERE x.organization_id=r.organization_id AND x.ledger_id=r.ledger_id
      AND x.farm_id=r.farm_id AND x.source_rule_id=r.source_rule_id
      AND x.scope_key=r.scope_key AND x.rule_version>r.rule_version)
 ORDER BY CASE r.scope_kind WHEN 'subject' THEN 1 WHEN 'class' THEN 2 ELSE 3 END
 LIMIT 1;
 IF v_selected.id IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_native_farm_rulebook_effective_v1',
    'state','not_established','subjectId',p_subject_id,
    'sourceRuleId',p_source_rule_id,'policyExecutable',false);
 END IF;
 RETURN pg_catalog.jsonb_build_object('ok',true,
   'contractVersion','governed_native_farm_rulebook_effective_v1',
   'state','established',
   'ruleVersionId',v_selected.id,'ruleVersion',v_selected.rule_version,
   'ruleStatus',v_selected.rule_status,'scopeKind',v_selected.scope_kind,
   'scopeKey',v_selected.scope_key,'sourceRuleId',p_source_rule_id,
   'subjectId',p_subject_id,'policy',v_selected.policy,
   'sourceBasis',v_selected.source_basis,'recordedAt',v_selected.recorded_at,
   'requiresSeasonEvidence',true,'policyExecutable',false,
   'offerCreated',false,'workCreated',false);
END;
$effective$;
REVOKE ALL ON FUNCTION atlas.read_governed_farm_rulebook_effective_self_api_v1(
 uuid,uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.adopt_governed_farm_rulebook_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_scope_kind text,p_scope_ref text,
 p_policy jsonb,p_decision text,p_expected_previous_version_id uuid,
 p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.adopt_governed_farm_rulebook_scope_self_api_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,p_scope_kind,
 p_scope_ref,p_policy,p_decision,p_expected_previous_version_id,p_action_id);
$transport$;
REVOKE ALL ON FUNCTION public.adopt_governed_farm_rulebook_scope_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.adopt_governed_farm_rulebook_scope_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid) TO authenticated;

CREATE FUNCTION public.read_governed_farm_rulebook_effective_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid,
 p_source_rule_id uuid,p_subject_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $transport_read$
 SELECT atlas.read_governed_farm_rulebook_effective_self_api_v1(
 p_organization_id,p_ledger_id,p_farm_id,p_source_rule_id,p_subject_id);
$transport_read$;
REVOKE ALL ON FUNCTION public.read_governed_farm_rulebook_effective_self_api_v1(
 uuid,uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_governed_farm_rulebook_effective_self_api_v1(
 uuid,uuid,uuid,uuid,uuid) TO authenticated;

-- END held U1B farm adapter. Never install without owner-approved release.
