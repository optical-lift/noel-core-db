-- UNI-OPS-01 U1A -- HELD SOURCE ONLY. NO PRODUCTION MIGRATION.
-- Noel-owned, bounded ORGANIZATION/Ledger-root rulebook adoption.
-- Derived from owner-supplied October 28 Build 3, adapted to real native
-- Ledger root/Subject/Foundry authority. Does not run Build 3's raw SQL.
-- No Work/assignment/plan/Result/Clock/legacy-task writes. No Household grant.
-- Must be installed only in an isolated production-shaped rollback clone
-- together with all existing native source dependencies, never live Supabase.

CREATE TABLE atlas.governed_rulebook_versions_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
  requirement_id uuid NOT NULL REFERENCES atlas.work_requirements(id) ON DELETE RESTRICT,
  subject_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  need_key text NOT NULL CHECK (length(btrim(need_key)) BETWEEN 2 AND 120),
  rule_key text NOT NULL CHECK (length(btrim(rule_key)) BETWEEN 2 AND 120),
  rule_version integer NOT NULL CHECK (rule_version BETWEEN 1 AND 100000),
  rule_status text NOT NULL CHECK (rule_status IN ('active','paused','retired')),
  policy jsonb NOT NULL CHECK (jsonb_typeof(policy)='object'),
  source_basis jsonb NOT NULL CHECK (jsonb_typeof(source_basis)='object'),
  previous_version_id uuid REFERENCES atlas.governed_rulebook_versions_v1(id) ON DELETE RESTRICT,
  actor_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  actor_principal_id uuid NOT NULL,
  decision_action_id uuid NOT NULL UNIQUE,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id,ledger_id,rule_key,rule_version)
);
COMMENT ON TABLE atlas.governed_rulebook_versions_v1 IS
  'U1A append-only owner-approved Rulebook decision history, not a Work generator or a grant to another Ledger. Held until signed clone and protected release.';
CREATE INDEX governed_rulebook_versions_scope_lookup_v1
  ON atlas.governed_rulebook_versions_v1
  (organization_id,ledger_id,requirement_id,rule_key,rule_version DESC);

CREATE TABLE atlas.governed_rulebook_bindings_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  rule_version_id uuid NOT NULL UNIQUE
    REFERENCES atlas.governed_rulebook_versions_v1(id) ON DELETE RESTRICT,
  inheritance_layer text NOT NULL DEFAULT 'subject_override'
    CHECK (inheritance_layer='subject_override'),
  match_kind text NOT NULL DEFAULT 'subject' CHECK (match_kind='subject'),
  match_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  priority integer NOT NULL DEFAULT 0 CHECK (priority BETWEEN -1000 AND 1000),
  season_keys jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(season_keys)='array'
      AND jsonb_array_length(season_keys)<=24),
  source_basis jsonb NOT NULL CHECK (jsonb_typeof(source_basis)='object'),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE atlas.governed_rulebook_bindings_v1 IS
  'U1A only proves exact canonical Subject binding. Classes, zone inheritance and Household adapters are separately held; do not infer them from this table.';

CREATE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Rulebook evidence is append-only; propose a new signed version'
  USING ERRCODE='42501';
END;
$immutable$;
CREATE TRIGGER governed_rulebook_versions_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.governed_rulebook_versions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1();
CREATE TRIGGER governed_rulebook_bindings_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.governed_rulebook_bindings_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1();

ALTER TABLE atlas.governed_rulebook_versions_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.governed_rulebook_bindings_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.governed_rulebook_versions_v1
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON atlas.governed_rulebook_bindings_v1
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.block_governed_rulebook_evidence_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- Do not use a Foundry workspace as Ledger governance. Two separately
-- current authorities are required: signed non-anonymous unrevoked session
-- and native institutional Ledger root. The Subject identity and condition
-- disclosure decisions are independently current (not implied by root).
-- This helper is private to the source writer and root-only read membrane.
CREATE FUNCTION atlas.require_governed_rulebook_root_source_v1(
  p_organization_id uuid,p_ledger_id uuid,p_requirement_id uuid
) RETURNS TABLE (
 actor_person_id uuid,actor_principal_id uuid,
 subject_entity_id uuid,need_key text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $authority$
DECLARE
 v_person uuid;
 v_principal uuid;
 v_need atlas.work_requirements%ROWTYPE;
 v_subject reality.entities%ROWTYPE;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_requirement_id IS NULL THEN
   RAISE EXCEPTION 'Exact Rulebook native source required' USING ERRCODE='42501';
 END IF;
 -- First-party signed session gate; includes live auth.sessions validation.
 v_principal:=atlas.foundry_current_signed_principal_v1();
 v_person:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 IF v_person IS NULL OR v_principal IS NULL
    OR v_principal IS DISTINCT FROM atlas.current_principal_id_v1() THEN
   RAISE EXCEPTION 'Native root authority unavailable' USING ERRCODE='42501';
 END IF;
 -- U1A takes only the organization's one explicitly governing primary Ledger,
 -- not arbitrary operating-Ledger proximity or a connected worker's Seat.
 IF NOT EXISTS (
   SELECT 1 FROM atlas.ledger_organization_participations lop
   WHERE lop.organization_id=p_organization_id
     AND lop.ledger_id=p_ledger_id
     AND lop.status='active' AND lop.ended_at IS NULL
     AND lop.participation_kind='governing'
     AND lop.is_compatibility_primary=true
 ) THEN
   RAISE EXCEPTION 'Native governing source unavailable' USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_need FROM atlas.work_requirements w
 WHERE w.id=p_requirement_id
   AND w.organization_id=p_organization_id
   AND w.state='active'
   AND w.source_object_type='reality_entity'
   AND w.source_object_id IS NOT NULL
   AND nullif(btrim(w.metadata->>'needKey'),'') IS NOT NULL;
 IF v_need.id IS NULL OR length(v_need.metadata->>'needKey') NOT BETWEEN 2 AND 120 THEN
   RAISE EXCEPTION 'Native Requirement unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_subject FROM reality.entities s
 WHERE s.id=v_need.source_object_id
   AND s.identity_state='canonical'
   AND s.entity_kind NOT IN ('person','organization','household')
   AND nullif(btrim(s.metadata->>'subjectDomain'),'') IS NOT NULL;
 IF v_subject.id IS NULL THEN
   RAISE EXCEPTION 'Canonical Subject unavailable' USING ERRCODE='42501';
 END IF;
 IF NOT coalesce(atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person,v_subject.metadata->>'subjectDomain',
       v_subject.entity_kind,v_subject.id,'identity'),false)
    OR NOT coalesce(atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person,v_subject.metadata->>'subjectDomain',
       v_subject.entity_kind,v_subject.id,'condition'),false) THEN
    RAISE EXCEPTION 'Subject disclosure unavailable' USING ERRCODE='42501';
 END IF;
 actor_person_id:=v_person;
 actor_principal_id:=v_principal;
 subject_entity_id:=v_subject.id;
 need_key:=v_need.metadata->>'needKey';
 RETURN NEXT;
END;
$authority$;
REVOKE ALL ON FUNCTION atlas.require_governed_rulebook_root_source_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- U1A authoring: one source-quoted operating instruction, exactly one native
-- active Requirement and canonical Subject, exactly one subject binding.
-- This writer does not "teach" or activate work execution by itself.
CREATE FUNCTION atlas.adopt_governed_rulebook_version_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_requirement_id uuid,
 p_rule_key text,p_policy jsonb,
 p_workspace_id text,p_entry_id text,p_segment_index integer,
 p_decision text,p_expected_previous_version_id uuid,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $adopt$
DECLARE
 v_root record;
 v_source foundry.events%ROWTYPE;
 v_segment jsonb;
 v_literal text;
 v_basis jsonb;
 v_prior atlas.governed_rulebook_versions_v1%ROWTYPE;
 v_replay atlas.governed_rulebook_versions_v1%ROWTYPE;
 v_saved atlas.governed_rulebook_versions_v1%ROWTYPE;
 v_seasons jsonb;
 v_priority integer;
 v_next integer;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_rulebook_root_source_v1(
   p_organization_id,p_ledger_id,p_requirement_id);
 IF v_root.actor_person_id IS NULL THEN
   RAISE EXCEPTION 'Native Rulebook root unavailable' USING ERRCODE='42501';
 END IF;

 IF p_action_id IS NULL OR p_rule_key IS NULL
    OR length(btrim(p_rule_key)) NOT BETWEEN 2 AND 120
    OR coalesce(p_decision,'') NOT IN ('active','paused','retired')
    OR p_policy IS NULL OR jsonb_typeof(p_policy)<>'object'
    OR octet_length(p_policy::text)>8192
    OR coalesce(p_policy->>'eligibilityMode','') NOT IN ('standing_stewardship','condition_triggered')
    OR length(btrim(coalesce(p_policy->>'desiredOutcome',''))) NOT BETWEEN 4 AND 600
    OR p_workspace_id IS NULL OR length(p_workspace_id)>180
    OR nullif(btrim(p_workspace_id),'') IS NULL
    OR p_entry_id IS NULL OR nullif(btrim(p_entry_id),'') IS NULL
    OR p_segment_index IS NULL OR p_segment_index NOT BETWEEN 0 AND 23 THEN
   RAISE EXCEPTION 'Explicit bounded policy and source decision required'
     USING ERRCODE='22023';
 END IF;
 IF p_policy->>'eligibilityMode'='condition_triggered' AND
    (coalesce(p_policy->>'triggerMode','') NOT IN ('condition_only','condition_and_window')
     OR coalesce(p_policy->>'strategyDisposition','') NOT IN
       ('allow_action','hold','review_required')
     OR nullif(p_policy->>'maxObservationAgeSeconds','') IS NULL
     OR (p_policy->>'maxObservationAgeSeconds')::integer NOT BETWEEN 60 AND 2592000) THEN
   RAISE EXCEPTION 'A corrective rule requires bounded evidence policy'
     USING ERRCODE='22023';
 END IF;
 IF p_policy->>'eligibilityMode'='standing_stewardship' AND
   length(btrim(coalesce(p_policy->>'standingPurpose',''))) NOT BETWEEN 4 AND 600 THEN
   RAISE EXCEPTION 'A standing rule requires an approved visit purpose'
     USING ERRCODE='22023';
 END IF;
 v_seasons:=coalesce(p_policy->'seasonKeys','[]'::jsonb);
 IF jsonb_typeof(v_seasons)<>'array' OR jsonb_array_length(v_seasons)>24
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_seasons) x(value)
      WHERE jsonb_typeof(x.value)<>'string'
        OR length(btrim(x.value #>> '{}')) NOT BETWEEN 1 AND 80
    ) THEN
   RAISE EXCEPTION 'Exact bounded named seasons required' USING ERRCODE='22023';
 END IF;
 IF p_policy ? 'priority' THEN
   v_priority:=(p_policy->>'priority')::integer;
 ELSE
   v_priority:=0;
 END IF;
 IF v_priority IS NULL OR v_priority NOT BETWEEN -1000 AND 1000 THEN
   RAISE EXCEPTION 'Bounded rule priority required' USING ERRCODE='22023';
 END IF;

 -- Verify original immutable Foundry evidence, current human principal,
 -- exact quoted segment and non-delegated source kind. An AI carrier, user-
 -- supplied "proof" object or an unrelated workspace is not authorization.
 SELECT e INTO v_source FROM foundry.events e
 JOIN foundry.workspace_authority_registry_v1 w
   ON w.workspace_id=e.workspace_id
 WHERE e.workspace_id=p_workspace_id AND e.event_id=p_entry_id
   AND e.event_type='foundry_reality_input_v1'
   AND w.owner_principal_id=v_root.actor_principal_id
   AND w.revoked_at IS NULL AND w.suspended_at IS NULL
   AND w.custody_review_state NOT IN ('revoked','suspended')
   AND e.envelope->'payload'->>'author_principal_id'=
     v_root.actor_principal_id::text
   AND e.envelope->'payload'->>'source_kind' IN
     ('operator_statement','firsthand_observation');
 IF v_source.event_id IS NULL THEN
   RAISE EXCEPTION 'Foundry original source unavailable' USING ERRCODE='42501';
 END IF;
 IF jsonb_typeof(v_source.envelope->'payload'->'segments')<>'array'
    OR p_segment_index>=jsonb_array_length(
      v_source.envelope->'payload'->'segments') THEN
   RAISE EXCEPTION 'Foundry source segment unavailable' USING ERRCODE='42501';
 END IF;
 v_segment:=v_source.envelope->'payload'->'segments'->p_segment_index;
 v_literal:=v_segment->>'text';
 IF coalesce(v_segment->>'kind','') NOT IN ('operating_instruction','work')
    OR nullif(btrim(v_literal),'') IS NULL
    OR strpos(coalesce(v_source.envelope->'payload'->>'original_text',''),
              v_literal)=0 THEN
   RAISE EXCEPTION 'Original operating instruction unavailable' USING ERRCODE='42501';
 END IF;
 v_basis:=jsonb_build_object(
  'contractVersion','foundry_governed_rulebook_adoption_v1',
  'workspaceId',p_workspace_id,'entryId',p_entry_id,
  'segmentIndex',p_segment_index,'sourceLiteral',v_literal,
  'sourceKind',v_source.envelope->'payload'->>'source_kind',
  'approverPrincipalId',v_root.actor_principal_id);

 -- Serialize the ENTIRE rule lineage. All replays still recheck current
 -- source/actor/disclosure; the action UUID alone never grants access.
 PERFORM pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'u1a:'||p_organization_id::text||':'||p_ledger_id::text||':'||
   btrim(p_rule_key),0));

 SELECT * INTO v_replay FROM atlas.governed_rulebook_versions_v1 r
 WHERE r.decision_action_id=p_action_id;
 IF v_replay.id IS NOT NULL THEN
   IF v_replay.organization_id IS DISTINCT FROM p_organization_id
     OR v_replay.ledger_id IS DISTINCT FROM p_ledger_id
     OR v_replay.requirement_id IS DISTINCT FROM p_requirement_id
     OR v_replay.subject_entity_id IS DISTINCT FROM v_root.subject_entity_id
     OR v_replay.actor_person_id IS DISTINCT FROM v_root.actor_person_id
     OR v_replay.actor_principal_id IS DISTINCT FROM v_root.actor_principal_id
     OR v_replay.rule_key IS DISTINCT FROM btrim(p_rule_key)
     OR v_replay.rule_status IS DISTINCT FROM p_decision
     OR v_replay.policy IS DISTINCT FROM p_policy
     OR v_replay.source_basis IS DISTINCT FROM v_basis
     OR v_replay.previous_version_id IS DISTINCT FROM p_expected_previous_version_id
   THEN
     RAISE EXCEPTION 'Action ID already used for a different rule decision'
       USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'replayed',true,
      'ruleVersionId',v_replay.id,'ruleVersion',v_replay.rule_version,
      'ruleStatus',v_replay.rule_status,'requirementId',p_requirement_id,
      'subjectEntityId',v_root.subject_entity_id,
      'sourceLinked',true,'workCreated',false,'clockAdmitted',false,
      'policyExecutable',false);
 END IF;

 SELECT * INTO v_prior FROM atlas.governed_rulebook_versions_v1 r
 WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.rule_key=btrim(p_rule_key)
 ORDER BY r.rule_version DESC LIMIT 1 FOR UPDATE;
 IF v_prior.id IS NULL THEN
   IF p_expected_previous_version_id IS NOT NULL OR p_decision<>'active' THEN
     RAISE EXCEPTION 'Initial policy requires an explicit active adoption'
       USING ERRCODE='42501';
   END IF;
   v_next:=1;
 ELSE
   IF p_expected_previous_version_id IS DISTINCT FROM v_prior.id
      OR v_prior.requirement_id IS DISTINCT FROM p_requirement_id
      OR v_prior.subject_entity_id IS DISTINCT FROM v_root.subject_entity_id
      OR v_prior.need_key IS DISTINCT FROM v_root.need_key
      OR v_prior.rule_status='retired'
      OR v_prior.rule_version>=100000 THEN
     RAISE EXCEPTION 'Stale, retired or unrelated version cannot be revised'
       USING ERRCODE='42501';
   END IF;
   IF p_decision IN ('paused','retired') AND p_policy IS DISTINCT FROM v_prior.policy THEN
     RAISE EXCEPTION 'Pause/retire cannot silently rewrite an approved policy'
       USING ERRCODE='42501';
   END IF;
   v_next:=v_prior.rule_version+1;
 END IF;

 INSERT INTO atlas.governed_rulebook_versions_v1 (
   organization_id,ledger_id,requirement_id,subject_entity_id,need_key,
   rule_key,rule_version,rule_status,policy,source_basis,previous_version_id,
   actor_person_id,actor_principal_id,decision_action_id
 ) VALUES (
   p_organization_id,p_ledger_id,p_requirement_id,v_root.subject_entity_id,
   v_root.need_key,btrim(p_rule_key),v_next,p_decision,p_policy,v_basis,
   p_expected_previous_version_id,v_root.actor_person_id,
   v_root.actor_principal_id,p_action_id
 ) RETURNING * INTO v_saved;

 INSERT INTO atlas.governed_rulebook_bindings_v1 (
   rule_version_id,inheritance_layer,match_kind,match_id,priority,season_keys,
   source_basis
 ) VALUES (
   v_saved.id,'subject_override','subject',v_root.subject_entity_id,
   v_priority,v_seasons,v_basis
 );
 RETURN jsonb_build_object('ok',true,'replayed',false,
   'ruleVersionId',v_saved.id,'ruleVersion',v_saved.rule_version,
   'ruleStatus',v_saved.rule_status,'requirementId',p_requirement_id,
   'subjectEntityId',v_root.subject_entity_id,'previousVersionId',
   p_expected_previous_version_id,'sourceLinked',true,
   'workCreated',false,'clockAdmitted',false,'policyExecutable',false);
END;
$adopt$;
REVOKE ALL ON FUNCTION atlas.adopt_governed_rulebook_version_self_api_v1(
 uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Only a signed, CURRENT, exact root can retrieve the latest approved
-- decision for the one native Requirement; no roster, other Subject or count.
CREATE FUNCTION atlas.read_governed_rulebook_current_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_requirement_id uuid,
 p_rule_key text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $read$
DECLARE
 v_root record;
 v_saved atlas.governed_rulebook_versions_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_root FROM atlas.require_governed_rulebook_root_source_v1(
   p_organization_id,p_ledger_id,p_requirement_id);
 IF nullif(btrim(coalesce(p_rule_key,'')),'') IS NULL
    OR length(btrim(p_rule_key))>120 THEN
   RAISE EXCEPTION 'Exact root Rulebook source required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_saved FROM atlas.governed_rulebook_versions_v1 r
 WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.requirement_id=p_requirement_id
   AND r.subject_entity_id=v_root.subject_entity_id
   AND r.rule_key=btrim(p_rule_key)
 ORDER BY r.rule_version DESC LIMIT 1;
 IF v_saved.id IS NULL THEN
   RETURN jsonb_build_object('ok',true,'state','not_established',
     'workCreated',false,'clockAdmitted',false);
 END IF;
 RETURN jsonb_build_object('ok',true,'state','established',
   'ruleVersionId',v_saved.id,'ruleVersion',v_saved.rule_version,
   'ruleStatus',v_saved.rule_status,'policy',v_saved.policy,
   'sourceBasis',v_saved.source_basis,
   'requirementId',v_saved.requirement_id,
   'subjectEntityId',v_saved.subject_entity_id,
   'previousVersionId',v_saved.previous_version_id,
   'recordedAt',v_saved.recorded_at,
   'workCreated',false,'clockAdmitted',false,'policyExecutable',false);
END;
$read$;
REVOKE ALL ON FUNCTION atlas.read_governed_rulebook_current_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- Public transport exposes *only* source-rechecking signed domain functions.
-- SECURITY DEFINER is necessary because the source tables and internal
-- functions have no client grants. It NEVER uses a client-selected root id.
CREATE FUNCTION public.adopt_governed_rulebook_version_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_requirement_id uuid,
 p_rule_key text,p_policy jsonb,
 p_workspace_id text,p_entry_id text,p_segment_index integer,
 p_decision text,p_expected_previous_version_id uuid,p_action_id uuid
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public_adopt$
 SELECT atlas.adopt_governed_rulebook_version_self_api_v1(
  p_organization_id,p_ledger_id,p_requirement_id,p_rule_key,p_policy,
  p_workspace_id,p_entry_id,p_segment_index,p_decision,
  p_expected_previous_version_id,p_action_id);
$public_adopt$;
REVOKE ALL ON FUNCTION public.adopt_governed_rulebook_version_self_api_v1(
 uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.adopt_governed_rulebook_version_self_api_v1(
 uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)
 TO authenticated;

CREATE FUNCTION public.read_governed_rulebook_current_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_requirement_id uuid,
 p_rule_key text
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public_read$
 SELECT atlas.read_governed_rulebook_current_self_api_v1(
   p_organization_id,p_ledger_id,p_requirement_id,p_rule_key);
$public_read$;
REVOKE ALL ON FUNCTION public.read_governed_rulebook_current_self_api_v1(
 uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_governed_rulebook_current_self_api_v1(
 uuid,uuid,uuid,text) TO authenticated;

-- END U1A SOURCE CANDIDATE. No migration COMMIT by design.