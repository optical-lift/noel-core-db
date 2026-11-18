-- HELD U1.3 SHARED cross-domain source. No production migration or delegation.
-- Requires an INDEPENDENT canonical Reality institutional root responsibility
-- for the exact institution Entity AND Ledger. Never infer root from Ledger seat,
-- Course, teacher, invite, metadata, Atlas employee, or app owner.
-- Does NOT create source root; its independent establishment remains HELD.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('reality.responsibility_relations') IS NULL
 OR to_regclass('titus.institution_account_invitations_v1') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'held U1.3 shared manager governor requires approved clone'
 USING ERRCODE='42501'; END IF;
END $gate$;

-- One immutable governance original for an appointed manager, a transfer,
-- or an ending. The referenced Reality responsibility is the actual live
-- authority; this ledger records provenance and the independent root used.
CREATE TABLE titus.institution_account_manager_governance_v1 (
 governance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL,
 actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 root_responsibility_id uuid NOT NULL REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 institution_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 action text NOT NULL CHECK(action IN ('appoint','transfer','revoke')),
 previous_manager_person_entity_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
 new_manager_person_entity_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
 previous_responsibility_id uuid REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 new_responsibility_id uuid REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_person_entity_id,request_id),
 CHECK(
   (action='appoint' AND previous_manager_person_entity_id IS NULL
    AND previous_responsibility_id IS NULL
    AND new_manager_person_entity_id IS NOT NULL
    AND new_responsibility_id IS NOT NULL)
   OR (action='transfer' AND previous_manager_person_entity_id IS NOT NULL
    AND previous_responsibility_id IS NOT NULL
    AND new_manager_person_entity_id IS NOT NULL
    AND new_responsibility_id IS NOT NULL
    AND previous_manager_person_entity_id <> new_manager_person_entity_id)
   OR (action='revoke' AND previous_manager_person_entity_id IS NOT NULL
    AND previous_responsibility_id IS NOT NULL
    AND new_manager_person_entity_id IS NULL
    AND new_responsibility_id IS NULL)
 )
);
ALTER TABLE titus.institution_account_manager_governance_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.institution_account_manager_governance_v1
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER titus_institution_account_manager_governance_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.institution_account_manager_governance_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();

-- Private helper: returns the ONLY canonical current root responsible
-- for this exact entity + Ledger + command. Refuses ambiguity, stale rights,
-- invalid institution, and wrong Ledger even when both have same entity.
CREATE FUNCTION titus.require_institution_root_manager_governor_self_v1(
 p_institution uuid,p_ledger uuid,p_operation text
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $root$
DECLARE v_actor uuid;v_ids uuid[];v_canonical uuid;
BEGIN
 IF p_operation NOT IN ('appoint_manager','transfer_manager','revoke_manager')
 OR p_ledger IS NULL OR p_institution IS NULL
 THEN RAISE EXCEPTION 'exact Titus root operation required' USING ERRCODE='42501'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 IF NOT EXISTS(
 SELECT 1 FROM ledger.ledgers l JOIN reality.entities e ON e.id=l.subject_entity_id
 WHERE l.id=p_ledger AND l.subject_entity_id=p_institution
 AND l.ledger_state='active' AND l.retired_at IS NULL
 AND e.identity_state='canonical' AND e.entity_kind IN ('business','organization'))
 THEN RAISE EXCEPTION 'genuine active institution and Ledger required'
 USING ERRCODE='42501'; END IF;
 SELECT array_agg(r.id) INTO v_ids
 FROM reality.responsibility_relations r
 WHERE r.carrier_person_entity_id=v_actor
 AND r.responsibility_key='titus_institution_account_root_governance'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=p_institution
 AND r.jurisdiction_domain IS NULL
 AND r.scope->>'ledgerId'=p_ledger::text
 AND r.relation_state='active' AND r.ended_at IS NULL
 AND r.began_at<=clock_timestamp()
 AND p_operation=ANY(r.permitted_operations);
 IF cardinality(v_ids) IS DISTINCT FROM 1 THEN
 RAISE EXCEPTION 'exact independently established current Titus root required'
 USING ERRCODE='42501'; END IF;
 v_canonical:=reality.resolve_responsibility_relation_v1(
 v_actor,'titus_institution_account_root_governance',
 p_operation,'entity',p_institution,NULL,
 jsonb_build_object('ledgerId',p_ledger::text));
 IF v_canonical IS DISTINCT FROM v_ids[1] THEN
 RAISE EXCEPTION 'Reality root resolution mismatch'
 USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM reality.responsibility_relations r WHERE r.id=v_ids[1]
 AND r.carrier_person_entity_id=v_actor
 AND r.responsibility_key='titus_institution_account_root_governance'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=p_institution
 AND r.jurisdiction_domain IS NULL
 AND r.scope->>'ledgerId'=p_ledger::text
 AND r.relation_state='active' AND r.ended_at IS NULL
 AND r.began_at<=clock_timestamp()
 AND p_operation=ANY(r.permitted_operations) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reality root ended during command'
 USING ERRCODE='42501'; END IF;
 RETURN v_ids[1];
END $root$;
REVOKE ALL ON FUNCTION titus.require_institution_root_manager_governor_self_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated;

-- One signed-root command, one current exact-Ledger manager at a time.
-- "transfer" replaces manager atomically in a single transaction; it never
-- grants the new manager a license, account admission, Course or seat.
-- "revoke" leaves append-only governance evidence and ends the authority,
-- never deletes historical responsibility or the Person's login/Courses.
CREATE FUNCTION public.shared_titus_institution_manager_command_self_api_v1(
 p_ledger_id uuid,p_action text,p_prior_manager_person_id uuid,
 p_new_manager_person_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $command$
DECLARE v_actor uuid;v_institution uuid;v_root uuid;v_op text;
 v_prior reality.responsibility_relations%ROWTYPE;
 v_ids uuid[];v_new_relation_id uuid;v_event_id uuid;
 v_old titus.institution_account_manager_governance_v1%ROWTYPE;
BEGIN
 IF p_ledger_id IS NULL OR p_request_id IS NULL OR
 p_action NOT IN ('appoint','transfer','revoke')
 OR (p_action='appoint' AND (p_prior_manager_person_id IS NOT NULL
   OR p_new_manager_person_id IS NULL))
 OR (p_action='transfer' AND (p_prior_manager_person_id IS NULL
   OR p_new_manager_person_id IS NULL
   OR p_prior_manager_person_id=p_new_manager_person_id))
 OR (p_action='revoke' AND (p_prior_manager_person_id IS NULL
   OR p_new_manager_person_id IS NOT NULL))
 THEN RAISE EXCEPTION 'exact manager original action required'
 USING ERRCODE='22023'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT l.subject_entity_id INTO v_institution
 FROM ledger.ledgers l JOIN reality.entities e ON e.id=l.subject_entity_id
 WHERE l.id=p_ledger_id AND l.ledger_state='active' AND l.retired_at IS NULL
 AND e.entity_kind IN ('business','organization') AND e.identity_state='canonical';
 IF v_institution IS NULL THEN
 RAISE EXCEPTION 'canonical active institution required' USING ERRCODE='42501'; END IF;
 v_op:=CASE p_action WHEN 'appoint' THEN 'appoint_manager'
 WHEN 'transfer' THEN 'transfer_manager' ELSE 'revoke_manager' END;
 -- Require independent source standing BEFORE any replay acceptance.
 v_root:=titus.require_institution_root_manager_governor_self_v1(
 v_institution,p_ledger_id,v_op);
 -- Serialize all appointment/transfer/revoke commands per exact Ledger.
 PERFORM 1 FROM ledger.ledgers l
 WHERE l.id=p_ledger_id AND l.subject_entity_id=v_institution
 AND l.ledger_state='active' AND l.retired_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'institution Ledger retired during command'
 USING ERRCODE='42501'; END IF;

 SELECT * INTO v_old FROM titus.institution_account_manager_governance_v1 g
 WHERE g.actor_person_entity_id=v_actor AND g.request_id=p_request_id;
 IF v_old.governance_id IS NOT NULL THEN
  IF v_old.ledger_id IS DISTINCT FROM p_ledger_id
   OR v_old.action IS DISTINCT FROM p_action
   OR v_old.previous_manager_person_entity_id IS DISTINCT FROM p_prior_manager_person_id
   OR v_old.new_manager_person_entity_id IS DISTINCT FROM p_new_manager_person_id
   OR v_old.root_responsibility_id IS DISTINCT FROM v_root
  THEN RAISE EXCEPTION 'conflicting manager governance request'
   USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','shared_titus_manager_governance_v1',
   'governanceId',v_old.governance_id,'alreadyExists',true);
 END IF;

 SELECT array_agg(r.id) INTO v_ids FROM reality.responsibility_relations r
 WHERE r.responsibility_key='titus_institution_account_management'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=v_institution
 AND r.jurisdiction_domain IS NULL AND r.scope->>'ledgerId'=p_ledger_id::text
 AND r.relation_state='active' AND r.ended_at IS NULL
 AND r.began_at<=clock_timestamp();
 IF cardinality(v_ids)>1 THEN
 RAISE EXCEPTION 'ambiguous historical manager standing; source review required'
 USING ERRCODE='42501'; END IF;
 IF p_action='appoint' THEN
  IF cardinality(v_ids) IS NOT NULL THEN
   RAISE EXCEPTION 'current manager must be explicitly transferred or revoked'
   USING ERRCODE='42501'; END IF;
 ELSE
  IF cardinality(v_ids) IS DISTINCT FROM 1 THEN
   RAISE EXCEPTION 'exact current manager required for disposition'
   USING ERRCODE='42501'; END IF;
  SELECT * INTO v_prior FROM reality.responsibility_relations r
  WHERE r.id=v_ids[1] AND r.carrier_person_entity_id=p_prior_manager_person_id
   AND r.responsibility_key='titus_institution_account_management'
   AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=v_institution
   AND r.scope->>'ledgerId'=p_ledger_id::text AND r.relation_state='active'
   AND r.ended_at IS NULL FOR UPDATE;
  IF v_prior.id IS NULL OR NOT EXISTS(
    SELECT 1 FROM titus.institution_account_manager_governance_v1 g
    WHERE g.new_responsibility_id=v_prior.id
      AND g.action IN ('appoint','transfer'))
  THEN RAISE EXCEPTION 'unrecognized original manager; cannot rewrite history'
   USING ERRCODE='42501'; END IF;
 END IF;
 IF p_action IN ('appoint','transfer') THEN
  PERFORM 1 FROM reality.entities e
  WHERE e.id=p_new_manager_person_id AND e.entity_kind='person'
   AND e.identity_state='canonical' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'new manager must be real canonical Person'
   USING ERRCODE='42501'; END IF;
 END IF;
 IF p_action IN ('transfer','revoke') THEN
  UPDATE reality.responsibility_relations
   SET relation_state='ended',ended_at=clock_timestamp()
  WHERE id=v_prior.id AND relation_state='active' AND ended_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'manager standing changed during disposition'
   USING ERRCODE='42501'; END IF;
 END IF;
 IF p_action IN ('appoint','transfer') THEN
  INSERT INTO reality.responsibility_relations (
   carrier_person_entity_id,responsibility_key,title,relation_state,
   jurisdiction_kind,jurisdiction_entity_id,jurisdiction_domain,
   permitted_operations,scope,establishment_kind,source_person_entity_id,
   establishment_basis,began_at)
  VALUES (
   p_new_manager_person_id,'titus_institution_account_management',
   'Titus institution account manager','active','entity',v_institution,NULL,
   ARRAY['invite','withdraw','cancel']::text[],
   jsonb_build_object('ledgerId',p_ledger_id::text),
   'shared_titus_institution_root_appointment_v1',v_actor,
   jsonb_build_object('rootResponsibilityId',v_root::text,
    'requestId',p_request_id::text,'action',p_action),
   clock_timestamp()) RETURNING id INTO v_new_relation_id;
 END IF;
 INSERT INTO titus.institution_account_manager_governance_v1 (
 request_id,actor_person_entity_id,root_responsibility_id,
 institution_entity_id,ledger_id,action,previous_manager_person_entity_id,
 new_manager_person_entity_id,previous_responsibility_id,new_responsibility_id)
 VALUES(p_request_id,v_actor,v_root,v_institution,p_ledger_id,p_action,
  p_prior_manager_person_id,p_new_manager_person_id,
  v_prior.id,v_new_relation_id) RETURNING governance_id INTO v_event_id;
 RETURN jsonb_build_object('contractVersion','shared_titus_manager_governance_v1',
  'governanceId',v_event_id,'alreadyExists',false);
END $command$;
REVOKE ALL ON FUNCTION public.shared_titus_institution_manager_command_self_api_v1(
 uuid,text,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_titus_institution_manager_command_self_api_v1(
 uuid,text,uuid,uuid,uuid) TO authenticated;
