-- HELD U1.4 Shared source: initial institution-root establishment and succession.
-- Never deployed, imported, or released by inclusion in a candidate branch.
-- A signed Person must ALREADY hold Atlas's independent governing Principal
-- authority across the exact native Ledger and its unique governing organization.
-- No Ledger Seat, owner label, login, plan, invitation or Course by itself is root.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('titus.require_institution_root_manager_governor_self_v1(uuid,uuid,text)') IS NULL
 OR to_regclass('atlas.ledger_organization_participations') IS NULL
 OR to_regclass('compatibility.legacy_bindings') IS NULL
 THEN RAISE EXCEPTION 'held shared root requires independent Atlas governing source in approved clone'
 USING ERRCODE='42501'; END IF;
END $preflight$;

CREATE TABLE titus.institution_account_root_origins_v1(
 origin_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN ('bootstrap','succession')),
 institution_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 organization_id uuid NOT NULL,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recipient_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 previous_root_responsibility_id uuid REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 new_root_responsibility_id uuid NOT NULL UNIQUE REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 source_invitation_id uuid UNIQUE,
 source_evidence jsonb NOT NULL CHECK(jsonb_typeof(source_evidence)='object'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_person_entity_id,request_id)
);
CREATE TABLE titus.institution_account_root_transfer_invitations_v1(
 invitation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 institution_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 organization_id uuid NOT NULL,
 old_root_responsibility_id uuid NOT NULL REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 nominated_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recipient_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(nominated_by_person_entity_id,request_id),
 CHECK(nominated_by_person_entity_id<>recipient_person_entity_id)
);
ALTER TABLE titus.institution_account_root_origins_v1 ADD CONSTRAINT titus_root_origin_source_invite_fkey
 FOREIGN KEY(source_invitation_id) REFERENCES titus.institution_account_root_transfer_invitations_v1(invitation_id) ON DELETE RESTRICT;
CREATE TABLE titus.institution_account_root_endings_v1(
 ending_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 root_responsibility_id uuid NOT NULL UNIQUE REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 ending_kind text NOT NULL CHECK(ending_kind IN ('succession','relinquish')),
 successor_responsibility_id uuid REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_person_entity_id,request_id),
 CHECK((ending_kind='succession' AND successor_responsibility_id IS NOT NULL)
 OR (ending_kind='relinquish' AND successor_responsibility_id IS NULL))
);
CREATE TABLE titus.institution_account_root_transfer_cancellations_v1(
 cancellation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL UNIQUE REFERENCES titus.institution_account_root_transfer_invitations_v1(invitation_id) ON DELETE RESTRICT,
 cancelled_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(cancelled_by_person_entity_id,request_id)
);
ALTER TABLE titus.institution_account_root_origins_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.institution_account_root_transfer_invitations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.institution_account_root_endings_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.institution_account_root_transfer_cancellations_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.institution_account_root_origins_v1,
 titus.institution_account_root_transfer_invitations_v1,
 titus.institution_account_root_endings_v1,
 titus.institution_account_root_transfer_cancellations_v1 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER titus_root_origins_immutable_v1 BEFORE UPDATE OR DELETE
 ON titus.institution_account_root_origins_v1 FOR EACH ROW
 EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();
CREATE TRIGGER titus_root_invitations_immutable_v1 BEFORE UPDATE OR DELETE
 ON titus.institution_account_root_transfer_invitations_v1 FOR EACH ROW
 EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();
CREATE TRIGGER titus_root_endings_immutable_v1 BEFORE UPDATE OR DELETE
 ON titus.institution_account_root_endings_v1 FOR EACH ROW
 EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();
CREATE TRIGGER titus_root_cancellations_immutable_v1 BEFORE UPDATE OR DELETE
 ON titus.institution_account_root_transfer_cancellations_v1 FOR EACH ROW
 EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();

-- This helper proves a *real* canonical institution + exact uniquely
-- governing Atlas Organization and native Ledger, not a supplied org label.
CREATE FUNCTION titus.require_canonical_institution_organization_v1(
 p_ledger uuid,p_organization uuid
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $institution$
DECLARE v_entity uuid;v_count bigint;v_mapping_count bigint;v_mapped_entity uuid;
BEGIN
 IF p_ledger IS NULL OR p_organization IS NULL THEN
 RAISE EXCEPTION 'institution Ledger and Organization required' USING ERRCODE='42501'; END IF;
 SELECT l.subject_entity_id INTO v_entity FROM ledger.ledgers l
 JOIN reality.entities e ON e.id=l.subject_entity_id
 WHERE l.id=p_ledger AND l.ledger_state='active' AND l.retired_at IS NULL
 AND e.identity_state='canonical' AND e.entity_kind IN ('business','organization');
 IF v_entity IS NULL THEN
 RAISE EXCEPTION 'active canonical institution Entity required' USING ERRCODE='42501'; END IF;
 SELECT count(*) INTO v_count FROM atlas.ledger_organization_participations p
 JOIN atlas.organizations o ON o.id=p.organization_id
 JOIN atlas.ledgers al ON al.id=p.ledger_id
 WHERE p.ledger_id=p_ledger AND p.organization_id=p_organization
 AND p.status='active' AND p.ended_at IS NULL
 AND p.participation_kind='governing' AND p.is_compatibility_primary
 AND o.status='active' AND al.status='active';
 IF v_count<>1 OR
 (SELECT count(*) FROM atlas.ledger_organization_participations p
  WHERE p.ledger_id=p_ledger AND p.status='active' AND p.ended_at IS NULL
   AND p.participation_kind='governing' AND p.is_compatibility_primary)<>1
 THEN RAISE EXCEPTION 'one canonical governing institution-to-Ledger relationship required'
 USING ERRCODE='42501'; END IF;
 -- A native governing Organization is not automatically the same
 -- canonical Reality institution. Check an explicit, unique, current
 -- compatibility binding. Any absent, conflicting, duplicate or retired
 -- mapping blocks both root bootstrap and successor acceptance. Do not
 -- manufacture this bridge from a matching name or a Ledger Seat.
 SELECT count(*),min(lb.new_id::text)::uuid
 INTO v_mapping_count,v_mapped_entity
 FROM compatibility.legacy_bindings lb
 JOIN reality.entities mapped ON mapped.id=lb.new_id
 WHERE lb.legacy_schema='atlas'
   AND lb.legacy_table='organizations'
   AND lb.legacy_key=p_organization::text
   AND lb.disposition='maps_to'
   AND lb.new_schema='reality'
   AND lb.new_table='entities'
   AND mapped.identity_state='canonical'
   AND mapped.entity_kind IN ('business','organization');
 IF v_mapping_count IS DISTINCT FROM 1
 OR v_mapped_entity IS DISTINCT FROM v_entity
 THEN RAISE EXCEPTION 'explicit unique Atlas Organization to Reality institution mapping required'
 USING ERRCODE='42501'; END IF;
 RETURN v_entity;
END $institution$;
REVOKE ALL ON FUNCTION titus.require_canonical_institution_organization_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION titus.current_exact_root_for_ledger_v1(
 p_ledger uuid,p_institution uuid
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $current$
DECLARE v_roots uuid[];
BEGIN
 SELECT array_agg(r.id) INTO v_roots FROM reality.responsibility_relations r
 WHERE r.responsibility_key='titus_institution_account_root_governance'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=p_institution
 AND r.jurisdiction_domain IS NULL AND r.scope->>'ledgerId'=p_ledger::text
 AND r.relation_state='active' AND r.ended_at IS NULL
 AND r.began_at<=clock_timestamp();
 IF cardinality(v_roots)>1 THEN
 RAISE EXCEPTION 'ambiguous institution root requires source adjudication'
 USING ERRCODE='42501'; END IF;
 RETURN v_roots[1];
END $current$;
REVOKE ALL ON FUNCTION titus.current_exact_root_for_ledger_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

-- A real signed Atlas governing Principal takes an EXPLICIT action to
-- establish initial Titus root. This is not automatic upon Seat or ownership.
CREATE FUNCTION public.shared_titus_institution_root_bootstrap_self_api_v1(
 p_ledger_id uuid,p_organization_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $bootstrap$
DECLARE v_actor uuid;v_institution uuid;v_prior uuid;
 v_relation uuid;v_origin uuid;v_old titus.institution_account_root_origins_v1%ROWTYPE;
BEGIN
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'idempotent root origin request required'
 USING ERRCODE='22023'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 v_institution:=titus.require_canonical_institution_organization_v1(
  p_ledger_id,p_organization_id);
 -- Independent native+institution governing Principal verification. A seat
 -- alone, "owner" label, and merely knowing the organization ID do not pass.
 IF atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id)
   IS DISTINCT FROM v_actor THEN
 RAISE EXCEPTION 'independent canonical Atlas governing Principal required'
 USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM ledger.ledgers l WHERE l.id=p_ledger_id
  AND l.subject_entity_id=v_institution AND l.ledger_state='active'
  AND l.retired_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'institution Ledger retired'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.institution_account_root_origins_v1
 WHERE actor_person_entity_id=v_actor AND request_id=p_request_id;
 IF v_old.origin_id IS NOT NULL THEN
  IF v_old.action IS DISTINCT FROM 'bootstrap'
   OR v_old.institution_entity_id IS DISTINCT FROM v_institution
   OR v_old.ledger_id IS DISTINCT FROM p_ledger_id
   OR v_old.organization_id IS DISTINCT FROM p_organization_id
  THEN RAISE EXCEPTION 'conflicting root origin request' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','shared_titus_root_bootstrap_v1',
   'originId',v_old.origin_id,'alreadyExists',true);
 END IF;
 v_prior:=titus.current_exact_root_for_ledger_v1(p_ledger_id,v_institution);
 IF v_prior IS NOT NULL THEN
 RAISE EXCEPTION 'existing root requires succession or adjudication, not bootstrap'
 USING ERRCODE='42501'; END IF;
 -- Never bootstrap into an orphaned institution still controlled by an
 -- unresolved pre-existing Titus manager. Preserve source for adjudication.
 IF EXISTS(SELECT 1 FROM reality.responsibility_relations r
 WHERE r.responsibility_key='titus_institution_account_management'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=v_institution
 AND r.jurisdiction_domain IS NULL AND r.scope->>'ledgerId'=p_ledger_id::text
 AND r.relation_state='active' AND r.ended_at IS NULL)
 THEN RAISE EXCEPTION 'orphaned active manager requires protected reconciliation'
 USING ERRCODE='42501'; END IF;
 INSERT INTO reality.responsibility_relations(
 carrier_person_entity_id,responsibility_key,title,relation_state,
 jurisdiction_kind,jurisdiction_entity_id,jurisdiction_domain,permitted_operations,
 scope,establishment_kind,source_person_entity_id,establishment_basis,began_at)
 VALUES(v_actor,'titus_institution_account_root_governance',
  'Titus institution account root','active','entity',v_institution,NULL,
  ARRAY['appoint_manager','transfer_manager','revoke_manager',
        'nominate_successor','cancel_succession','relinquish_root']::text[],
  jsonb_build_object('ledgerId',p_ledger_id::text),
  'shared_titus_institution_native_and_governing_principal_v1',v_actor,
  jsonb_build_object('organizationId',p_organization_id::text,
   'ledgerId',p_ledger_id::text,'requestId',p_request_id::text,
   'sourceReader','atlas.company_work_native_ledger_owner_self_v1'),
  clock_timestamp()) RETURNING id INTO v_relation;
 INSERT INTO titus.institution_account_root_origins_v1(
 request_id,action,institution_entity_id,organization_id,ledger_id,
 actor_person_entity_id,recipient_person_entity_id,new_root_responsibility_id,
 source_evidence) VALUES(
 p_request_id,'bootstrap',v_institution,p_organization_id,p_ledger_id,
 v_actor,v_actor,v_relation,jsonb_build_object(
 'independentAtlasSource','atlas.company_work_native_ledger_owner_self_v1',
 'actorPersonId',v_actor::text))
 RETURNING origin_id INTO v_origin;
 RETURN jsonb_build_object('contractVersion','shared_titus_root_bootstrap_v1',
  'originId',v_origin,'alreadyExists',false);
END $bootstrap$;
REVOKE ALL ON FUNCTION public.shared_titus_institution_root_bootstrap_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_titus_institution_root_bootstrap_self_api_v1(
 uuid,uuid,uuid) TO authenticated;

-- Transfer is two-actor: root nominates, recipient signs acceptance. A
-- nomination alone creates no authority and no second Auth/Person.
CREATE FUNCTION public.shared_titus_institution_root_nominate_self_api_v1(
 p_ledger_id uuid,p_organization_id uuid,p_recipient_person_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $nominate$
DECLARE v_actor uuid;v_entity uuid;v_root uuid;v_id uuid;
 v_old titus.institution_account_root_transfer_invitations_v1%ROWTYPE;
BEGIN
 IF p_recipient_person_id IS NULL OR p_request_id IS NULL THEN
 RAISE EXCEPTION 'exact nominated Person and request required' USING ERRCODE='22023'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 v_entity:=titus.require_canonical_institution_organization_v1(p_ledger_id,p_organization_id);
 v_root:=titus.require_institution_root_manager_governor_self_v1(
 v_entity,p_ledger_id,'nominate_successor');
 IF p_recipient_person_id=v_actor OR NOT EXISTS(
 SELECT 1 FROM reality.entities e WHERE e.id=p_recipient_person_id
 AND e.entity_kind='person' AND e.identity_state='canonical') THEN
 RAISE EXCEPTION 'different canonical successor Person required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM ledger.ledgers WHERE id=p_ledger_id AND ledger_state='active'
 AND retired_at IS NULL FOR UPDATE;
 IF NOT FOUND OR titus.current_exact_root_for_ledger_v1(p_ledger_id,v_entity)
 IS DISTINCT FROM v_root THEN
 RAISE EXCEPTION 'exact current institutional root required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.institution_account_root_transfer_invitations_v1
 WHERE nominated_by_person_entity_id=v_actor AND request_id=p_request_id;
 IF v_old.invitation_id IS NOT NULL THEN
  IF v_old.ledger_id IS DISTINCT FROM p_ledger_id
   OR v_old.recipient_person_entity_id IS DISTINCT FROM p_recipient_person_id
   OR v_old.old_root_responsibility_id IS DISTINCT FROM v_root
  THEN RAISE EXCEPTION 'conflicting root nomination original' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','shared_titus_root_nominate_v1',
   'invitationId',v_old.invitation_id,'alreadyExists',true);
 END IF;
 IF EXISTS(SELECT 1 FROM titus.institution_account_root_transfer_invitations_v1 i
 WHERE i.old_root_responsibility_id=v_root
 AND NOT EXISTS(SELECT 1 FROM titus.institution_account_root_transfer_cancellations_v1 c
  WHERE c.invitation_id=i.invitation_id)
 AND NOT EXISTS(SELECT 1 FROM titus.institution_account_root_origins_v1 o
  WHERE o.source_invitation_id=i.invitation_id)) THEN
 RAISE EXCEPTION 'another root nomination remains pending' USING ERRCODE='42501'; END IF;
 INSERT INTO titus.institution_account_root_transfer_invitations_v1(
 ledger_id,institution_entity_id,organization_id,
 old_root_responsibility_id,nominated_by_person_entity_id,
 recipient_person_entity_id,request_id)
 VALUES(p_ledger_id,v_entity,p_organization_id,v_root,v_actor,
 p_recipient_person_id,p_request_id) RETURNING invitation_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','shared_titus_root_nominate_v1',
  'invitationId',v_id,'alreadyExists',false);
END $nominate$;
REVOKE ALL ON FUNCTION public.shared_titus_institution_root_nominate_self_api_v1(
 uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_titus_institution_root_nominate_self_api_v1(
 uuid,uuid,uuid,uuid) TO authenticated;

CREATE FUNCTION public.shared_titus_institution_root_accept_self_api_v1(
 p_invitation_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $accept$
DECLARE v_actor uuid;v_i titus.institution_account_root_transfer_invitations_v1%ROWTYPE;
 v_current uuid;v_new uuid;v_origin uuid;
 v_existing titus.institution_account_root_origins_v1%ROWTYPE;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL THEN
 RAISE EXCEPTION 'specific root nomination and acceptance receipt required'
 USING ERRCODE='22023'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_i FROM titus.institution_account_root_transfer_invitations_v1 i
 WHERE i.invitation_id=p_invitation_id AND i.recipient_person_entity_id=v_actor
 FOR UPDATE;
 IF v_i.invitation_id IS NULL OR EXISTS(
 SELECT 1 FROM titus.institution_account_root_transfer_cancellations_v1 c
 WHERE c.invitation_id=p_invitation_id) THEN
 RAISE EXCEPTION 'own uncancelled root nomination required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM ledger.ledgers l WHERE l.id=v_i.ledger_id
  AND l.subject_entity_id=v_i.institution_entity_id
  AND l.ledger_state='active' AND l.retired_at IS NULL FOR UPDATE;
 IF NOT FOUND OR titus.require_canonical_institution_organization_v1(
 v_i.ledger_id,v_i.organization_id) IS DISTINCT FROM v_i.institution_entity_id
 THEN RAISE EXCEPTION 'current exact canonical institution source required'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_existing FROM titus.institution_account_root_origins_v1
 WHERE source_invitation_id=p_invitation_id;
 IF v_existing.origin_id IS NOT NULL THEN
  IF v_existing.recipient_person_entity_id IS DISTINCT FROM v_actor
   OR v_existing.request_id IS DISTINCT FROM p_request_id
  THEN RAISE EXCEPTION 'root succession cannot be reissued'
   USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','shared_titus_root_accept_v1',
   'originId',v_existing.origin_id,'alreadyExists',true);
 END IF;
 v_current:=titus.current_exact_root_for_ledger_v1(
 v_i.ledger_id,v_i.institution_entity_id);
 IF v_current IS DISTINCT FROM v_i.old_root_responsibility_id
 OR NOT EXISTS(SELECT 1 FROM reality.responsibility_relations r
  WHERE r.id=v_current AND r.carrier_person_entity_id=v_i.nominated_by_person_entity_id
  AND r.relation_state='active' AND r.ended_at IS NULL
  AND 'nominate_successor'=ANY(r.permitted_operations))
 THEN RAISE EXCEPTION 'nominating institutional root no longer active'
 USING ERRCODE='42501'; END IF;
 -- Transfer becomes effective only by signed recipient acceptance.
 UPDATE reality.responsibility_relations SET relation_state='ended',
 ended_at=clock_timestamp() WHERE id=v_current AND relation_state='active'
 AND ended_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'root ended during transfer'
 USING ERRCODE='42501'; END IF;
 INSERT INTO reality.responsibility_relations(
 carrier_person_entity_id,responsibility_key,title,relation_state,
 jurisdiction_kind,jurisdiction_entity_id,jurisdiction_domain,permitted_operations,
 scope,establishment_kind,source_person_entity_id,establishment_basis,began_at)
 VALUES(v_actor,'titus_institution_account_root_governance',
 'Titus institution account successor root','active','entity',
 v_i.institution_entity_id,NULL,
 ARRAY['appoint_manager','transfer_manager','revoke_manager',
       'nominate_successor','cancel_succession','relinquish_root']::text[],
 jsonb_build_object('ledgerId',v_i.ledger_id::text),
 'shared_titus_signed_successor_acceptance_v1',v_i.nominated_by_person_entity_id,
 jsonb_build_object('sourceInvitationId',p_invitation_id::text,
 'oldRootResponsibilityId',v_current::text,
 'recipientAcceptRequestId',p_request_id::text),
 clock_timestamp()) RETURNING id INTO v_new;
 INSERT INTO titus.institution_account_root_origins_v1(
 request_id,action,institution_entity_id,organization_id,ledger_id,
 actor_person_entity_id,recipient_person_entity_id,
 previous_root_responsibility_id,new_root_responsibility_id,
 source_invitation_id,source_evidence)
 VALUES(p_request_id,'succession',v_i.institution_entity_id,v_i.organization_id,
 v_i.ledger_id,v_actor,v_actor,v_current,v_new,p_invitation_id,
 jsonb_build_object('signedRecipientAcceptance',true))
 RETURNING origin_id INTO v_origin;
 INSERT INTO titus.institution_account_root_endings_v1(
 root_responsibility_id,actor_person_entity_id,request_id,ending_kind,
 successor_responsibility_id)
 VALUES(v_current,v_actor,p_request_id,'succession',v_new);
 RETURN jsonb_build_object('contractVersion','shared_titus_root_accept_v1',
  'originId',v_origin,'alreadyExists',false);
END $accept$;
REVOKE ALL ON FUNCTION public.shared_titus_institution_root_accept_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_titus_institution_root_accept_self_api_v1(uuid,uuid)
 TO authenticated;

CREATE FUNCTION public.shared_titus_institution_root_cancel_self_api_v1(
 p_invitation_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $cancel$
DECLARE v_actor uuid;v_i titus.institution_account_root_transfer_invitations_v1%ROWTYPE;
 v_root uuid;v_old titus.institution_account_root_transfer_cancellations_v1%ROWTYPE;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL THEN
 RAISE EXCEPTION 'exact cancellation required' USING ERRCODE='22023'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_i FROM titus.institution_account_root_transfer_invitations_v1
 WHERE invitation_id=p_invitation_id FOR UPDATE;
 IF v_i.invitation_id IS NULL THEN
 RAISE EXCEPTION 'valid root nomination required' USING ERRCODE='42501'; END IF;
 v_root:=titus.require_institution_root_manager_governor_self_v1(
 v_i.institution_entity_id,v_i.ledger_id,'cancel_succession');
 IF v_root IS DISTINCT FROM v_i.old_root_responsibility_id
 OR v_actor IS DISTINCT FROM v_i.nominated_by_person_entity_id
 THEN RAISE EXCEPTION 'only nominating current root may cancel'
 USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM ledger.ledgers WHERE id=v_i.ledger_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM titus.institution_account_root_origins_v1
 WHERE source_invitation_id=p_invitation_id)
 THEN RAISE EXCEPTION 'accepted succession cannot be cancelled'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.institution_account_root_transfer_cancellations_v1
 WHERE invitation_id=p_invitation_id;
 IF v_old.cancellation_id IS NOT NULL THEN
  IF v_old.cancelled_by_person_entity_id IS DISTINCT FROM v_actor
   OR v_old.request_id IS DISTINCT FROM p_request_id THEN
  RAISE EXCEPTION 'conflicting cancellation original' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','shared_titus_root_cancel_v1',
  'alreadyExists',true);
 END IF;
 INSERT INTO titus.institution_account_root_transfer_cancellations_v1(
 invitation_id,cancelled_by_person_entity_id,request_id)
 VALUES(p_invitation_id,v_actor,p_request_id);
 RETURN jsonb_build_object('contractVersion','shared_titus_root_cancel_v1',
 'alreadyExists',false);
END $cancel$;
REVOKE ALL ON FUNCTION public.shared_titus_institution_root_cancel_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_titus_institution_root_cancel_self_api_v1(uuid,uuid)
 TO authenticated;

-- Explicit relinquishment makes NO new root. It is deliberately bounded:
-- a current root may step down, while independently credentialed Atlas
-- governing authority can rebootstrap thereafter. No automatic recovery.
CREATE FUNCTION public.shared_titus_institution_root_relinquish_self_api_v1(
 p_ledger_id uuid,p_organization_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $end$
DECLARE v_actor uuid;v_entity uuid;v_root uuid;
 v_old titus.institution_account_root_endings_v1%ROWTYPE;
BEGIN
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'receipt required' USING ERRCODE='22023'; END IF;
 v_actor:=atlas.current_person_for_private_course_v1();
 v_entity:=titus.require_canonical_institution_organization_v1(
 p_ledger_id,p_organization_id);
 v_root:=titus.require_institution_root_manager_governor_self_v1(
 v_entity,p_ledger_id,'relinquish_root');
 PERFORM 1 FROM ledger.ledgers WHERE id=p_ledger_id AND ledger_state='active'
 AND retired_at IS NULL FOR UPDATE;
 IF titus.current_exact_root_for_ledger_v1(p_ledger_id,v_entity)
 IS DISTINCT FROM v_root THEN
 RAISE EXCEPTION 'current single root required' USING ERRCODE='42501'; END IF;
 -- A root cannot relinquish authority while a manager remains active:
 -- that would leave a delegated writer without any supervising root.
 IF EXISTS(SELECT 1 FROM reality.responsibility_relations r
 WHERE r.responsibility_key='titus_institution_account_management'
 AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=v_entity
 AND r.jurisdiction_domain IS NULL AND r.scope->>'ledgerId'=p_ledger_id::text
 AND r.relation_state='active' AND r.ended_at IS NULL)
 THEN RAISE EXCEPTION 'revoke/transfer active manager before root relinquishment'
 USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM titus.institution_account_root_transfer_invitations_v1 i
 WHERE i.old_root_responsibility_id=v_root
 AND NOT EXISTS(SELECT 1 FROM titus.institution_account_root_transfer_cancellations_v1 c
  WHERE c.invitation_id=i.invitation_id)
 AND NOT EXISTS(SELECT 1 FROM titus.institution_account_root_origins_v1 o
  WHERE o.source_invitation_id=i.invitation_id))
 THEN RAISE EXCEPTION 'resolve pending root succession first'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.institution_account_root_endings_v1
 WHERE actor_person_entity_id=v_actor AND request_id=p_request_id;
 IF v_old.ending_id IS NOT NULL THEN
  IF v_old.root_responsibility_id IS DISTINCT FROM v_root
   OR v_old.ending_kind IS DISTINCT FROM 'relinquish' THEN
   RAISE EXCEPTION 'conflicting root ending original' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','shared_titus_root_relinquish_v1',
   'endingId',v_old.ending_id,'alreadyExists',true);
 END IF;
 UPDATE reality.responsibility_relations SET relation_state='ended',
 ended_at=clock_timestamp() WHERE id=v_root AND relation_state='active'
 AND ended_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'root source changed' USING ERRCODE='42501'; END IF;
 INSERT INTO titus.institution_account_root_endings_v1(
 root_responsibility_id,actor_person_entity_id,request_id,ending_kind)
 VALUES(v_root,v_actor,p_request_id,'relinquish') RETURNING ending_id INTO v_old.ending_id;
 RETURN jsonb_build_object('contractVersion','shared_titus_root_relinquish_v1',
 'endingId',v_old.ending_id,'alreadyExists',false);
END $end$;
REVOKE ALL ON FUNCTION public.shared_titus_institution_root_relinquish_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_titus_institution_root_relinquish_self_api_v1(
 uuid,uuid,uuid) TO authenticated;
