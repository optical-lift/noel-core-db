-- HELD U1.1: explicit institution account manager -> invitee self-accept
-- -> durable scope admission -> exact self/manager withdrawal.
-- This file NEVER establishes organization governance, paid seats or licenses.
-- Only isolated synthetic schema clone; NOT a migration or production issuer.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('reality.responsibility_relations') IS NULL
 OR to_regclass('titus.institution_account_admissions_v1') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 THEN RAISE EXCEPTION 'held U1.1 admission source clone prerequisites missing'
 USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM titus.institution_account_admissions_v1) THEN
  RAISE EXCEPTION 'admissions exist; protected historical disposition required'
  USING ERRCODE='42501'; END IF;
END $gate$;

-- Issuance is separate from personal admission. The invitation explicitly
-- addresses an already-verified canonical Person. Organization seat CODES
-- under purchased license (L2D) are NOT these institutional invitations.
CREATE TABLE titus.institution_account_invitations_v1(
 invitation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 recipient_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 institution_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 issuer_responsibility_id uuid NOT NULL REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 issue_request_id uuid NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(issuer_person_entity_id,issue_request_id)
);
CREATE TABLE titus.institution_account_invitation_cancellations_v1(
 cancellation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL UNIQUE REFERENCES titus.institution_account_invitations_v1(invitation_id) ON DELETE RESTRICT,
 cancelled_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 manager_responsibility_id uuid NOT NULL REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 cancellation_request_id uuid NOT NULL,
 cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(cancelled_by_person_entity_id,cancellation_request_id)
);
ALTER TABLE titus.institution_account_admissions_v1
 ADD COLUMN source_invitation_id uuid NOT NULL UNIQUE
 REFERENCES titus.institution_account_invitations_v1(invitation_id) ON DELETE RESTRICT;
ALTER TABLE titus.institution_account_invitations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.institution_account_invitation_cancellations_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.institution_account_invitations_v1,
 titus.institution_account_invitation_cancellations_v1
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER titus_institution_account_invitations_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.institution_account_invitations_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();
CREATE TRIGGER titus_institution_account_invitation_cancellations_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.institution_account_invitation_cancellations_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();

-- An exact institution-targeted, current canonical Reality responsibility.
-- Distinct from any shared Atlas Ledger Seat, employee membership,
-- platform-wide pilot issuer, or Course coauthor/appointed teacher.
CREATE FUNCTION titus.require_current_institution_account_manager_self_v1(
 p_institution_entity_id uuid,p_ledger_id uuid,p_operation text
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $manager$
DECLARE v_person uuid;v_authorities uuid[];
BEGIN
 IF p_operation NOT IN ('invite','withdraw','cancel') OR
 p_ledger_id IS NULL OR p_institution_entity_id IS NULL
 THEN RAISE EXCEPTION 'exact Titus institution account manager scope required'
 USING ERRCODE='42501'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 IF NOT EXISTS(
  SELECT 1 FROM ledger.ledgers l JOIN reality.entities e ON e.id=l.subject_entity_id
  WHERE l.id=p_ledger_id AND l.subject_entity_id=p_institution_entity_id
   AND l.ledger_state='active' AND l.retired_at IS NULL
   AND e.identity_state='canonical' AND e.entity_kind IN ('business','organization')
 ) THEN RAISE EXCEPTION 'canonical institution scope required'
 USING ERRCODE='42501'; END IF;
 -- SHARE lock synchronizes permission check against authorized source ending.
 SELECT array_agg(r.id) INTO v_authorities
 FROM reality.responsibility_relations r
 WHERE r.carrier_person_entity_id=v_person
  AND r.responsibility_key='titus_institution_account_management'
  AND r.jurisdiction_kind='entity'
  AND r.jurisdiction_entity_id=p_institution_entity_id
  AND r.jurisdiction_domain IS NULL
  AND r.relation_state='active'
  AND r.began_at<=clock_timestamp()
  AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
  AND p_operation=ANY(r.permitted_operations);
 IF cardinality(v_authorities) IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'exact current institution account management authority required'
  USING ERRCODE='42501'; END IF;
 -- Recheck selected authority under row lock; no stale positive decision.
 PERFORM 1 FROM reality.responsibility_relations r
 WHERE r.id=v_authorities[1] AND r.carrier_person_entity_id=v_person
  AND r.responsibility_key='titus_institution_account_management'
  AND r.jurisdiction_kind='entity'
  AND r.jurisdiction_entity_id=p_institution_entity_id
  AND r.jurisdiction_domain IS NULL AND r.relation_state='active'
  AND r.began_at<=clock_timestamp()
  AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
  AND p_operation=ANY(r.permitted_operations)
 FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'institution manager standing changed'
 USING ERRCODE='42501'; END IF;
 RETURN v_authorities[1];
END $manager$;
REVOKE ALL ON FUNCTION titus.require_current_institution_account_manager_self_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated;

-- Manager issues an addressed invitation. This cannot create the admission,
-- confer a license, enroll a student or make a person a platform issuer.
CREATE FUNCTION public.titus_institution_account_invite_self_api_v1(
 p_ledger_id uuid,p_recipient_person_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $invite$
DECLARE v_manager uuid;v_person uuid;v_institution uuid;
 v_old titus.institution_account_invitations_v1%ROWTYPE;v_id uuid;
BEGIN
 IF p_ledger_id IS NULL OR p_recipient_person_id IS NULL OR p_request_id IS NULL
 THEN RAISE EXCEPTION 'specific account invitation required' USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT l.subject_entity_id INTO v_institution
 FROM ledger.ledgers l JOIN reality.entities e ON e.id=l.subject_entity_id
 WHERE l.id=p_ledger_id AND l.ledger_state='active' AND l.retired_at IS NULL
 AND e.entity_kind IN ('business','organization') AND e.identity_state='canonical';
 IF v_institution IS NULL THEN
 RAISE EXCEPTION 'recognized institution required' USING ERRCODE='42501'; END IF;
 v_manager:=titus.require_current_institution_account_manager_self_v1(
 v_institution,p_ledger_id,'invite');
 IF NOT EXISTS(SELECT 1 FROM reality.entities e
  WHERE e.id=p_recipient_person_id AND e.entity_kind='person'
    AND e.identity_state='canonical')
 THEN RAISE EXCEPTION 'canonical recipient Person required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.institution_account_invitations_v1 i
 WHERE i.issuer_person_entity_id=v_person AND i.issue_request_id=p_request_id;
 IF v_old.invitation_id IS NOT NULL THEN
  IF v_old.recipient_person_entity_id IS DISTINCT FROM p_recipient_person_id
   OR v_old.ledger_id IS DISTINCT FROM p_ledger_id
   OR v_old.issuer_responsibility_id IS DISTINCT FROM v_manager THEN
   RAISE EXCEPTION 'conflicting invitation request' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_institution_invite_v1',
   'invitationId',v_old.invitation_id,'alreadyExists',true);
 END IF;
 INSERT INTO titus.institution_account_invitations_v1(
 recipient_person_entity_id,institution_entity_id,ledger_id,
 issuer_person_entity_id,issuer_responsibility_id,issue_request_id)
 VALUES(p_recipient_person_id,v_institution,p_ledger_id,v_person,v_manager,p_request_id)
 RETURNING invitation_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','titus_institution_invite_v1',
 'invitationId',v_id,'alreadyExists',false);
END $invite$;
REVOKE ALL ON FUNCTION public.titus_institution_account_invite_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_institution_account_invite_self_api_v1(uuid,uuid,uuid)
 TO authenticated;

-- Only the independently signed named recipient can accept. An issuer or
-- third party cannot generate consent. A stale manager cannot admit anyone.
CREATE FUNCTION public.titus_institution_account_accept_self_api_v1(
 p_invitation_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $accept$
DECLARE v_person uuid;v_inv titus.institution_account_invitations_v1%ROWTYPE;
 v_old titus.institution_account_admissions_v1%ROWTYPE;
 v_admission_id uuid;v_count bigint;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL
 THEN RAISE EXCEPTION 'exact invitation and acceptance receipt required'
 USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_inv FROM titus.institution_account_invitations_v1 i
 WHERE i.invitation_id=p_invitation_id AND i.recipient_person_entity_id=v_person
 FOR UPDATE;
 IF v_inv.invitation_id IS NULL OR EXISTS(
  SELECT 1 FROM titus.institution_account_invitation_cancellations_v1 c
  WHERE c.invitation_id=p_invitation_id)
 THEN RAISE EXCEPTION 'available invitation for this Person required'
 USING ERRCODE='42501'; END IF;
 -- The original issuer must still possess precisely the same live authority.
 PERFORM 1 FROM reality.responsibility_relations r
 WHERE r.id=v_inv.issuer_responsibility_id
 AND r.carrier_person_entity_id=v_inv.issuer_person_entity_id
 AND r.responsibility_key='titus_institution_account_management'
 AND r.jurisdiction_kind='entity'
 AND r.jurisdiction_entity_id=v_inv.institution_entity_id
 AND r.jurisdiction_domain IS NULL AND r.relation_state='active'
 AND r.began_at<=clock_timestamp()
 AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
 AND 'invite'=ANY(r.permitted_operations)
 FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(
 SELECT 1 FROM ledger.ledgers l JOIN reality.entities e ON e.id=l.subject_entity_id
 WHERE l.id=v_inv.ledger_id AND l.subject_entity_id=v_inv.institution_entity_id
 AND l.ledger_state='active' AND l.retired_at IS NULL
 AND e.entity_kind IN ('business','organization') AND e.identity_state='canonical')
 THEN RAISE EXCEPTION 'institution invitation no longer authorized'
 USING ERRCODE='42501'; END IF;
 -- Serialize competing invitations for one recipient on canonical Person row.
 PERFORM 1 FROM reality.entities e WHERE e.id=v_person
 AND e.entity_kind='person' AND e.identity_state='canonical' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'current canonical recipient required'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.institution_account_admissions_v1 a
 WHERE a.source_invitation_id=p_invitation_id;
 IF v_old.admission_id IS NOT NULL THEN
  IF v_old.person_entity_id IS DISTINCT FROM v_person
  OR v_old.acceptance_receipt IS DISTINCT FROM ('u1-accept:'||p_request_id::text)
  OR EXISTS(SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
   WHERE w.admission_id=v_old.admission_id)
  THEN RAISE EXCEPTION 'prior invitation admission cannot be reassigned or revived'
   USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_institution_accept_v1',
   'admissionId',v_old.admission_id,'alreadyExists',true);
 END IF;
 SELECT count(*) INTO v_count FROM titus.institution_account_admissions_v1 a
 WHERE a.person_entity_id=v_person AND a.ledger_id=v_inv.ledger_id
 AND NOT EXISTS(SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
  WHERE w.admission_id=a.admission_id);
 IF v_count<>0 THEN RAISE EXCEPTION 'already admitted to this institution'
 USING ERRCODE='42501'; END IF;
 INSERT INTO titus.institution_account_admissions_v1(
 person_entity_id,institution_entity_id,ledger_id,issued_by_person_entity_id,
 issue_receipt,acceptance_receipt,issued_at,accepted_at,source_invitation_id)
 VALUES(v_person,v_inv.institution_entity_id,v_inv.ledger_id,
 v_inv.issuer_person_entity_id,'u1-invite:'||v_inv.invitation_id::text,
 'u1-accept:'||p_request_id::text,v_inv.issued_at,clock_timestamp(),
 v_inv.invitation_id) RETURNING admission_id INTO v_admission_id;
 RETURN jsonb_build_object('contractVersion','titus_institution_accept_v1',
  'admissionId',v_admission_id,'alreadyExists',false);
END $accept$;
REVOKE ALL ON FUNCTION public.titus_institution_account_accept_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_institution_account_accept_self_api_v1(uuid,uuid)
 TO authenticated;

-- Withdrawal is distinct from license cancellation. Recipient may self-
-- withdraw; another Person needs separate CURRENT exact institution manage
-- authority. Never let a manager edit another Person's historical originals.
CREATE FUNCTION public.titus_institution_account_withdraw_self_api_v1(
 p_admission_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $withdraw$
DECLARE v_person uuid;v_adm titus.institution_account_admissions_v1%ROWTYPE;
 v_old titus.institution_account_admission_withdrawals_v1%ROWTYPE;
 v_manager uuid;
BEGIN
 IF p_admission_id IS NULL OR p_request_id IS NULL
 THEN RAISE EXCEPTION 'exact withdrawal request required' USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_adm FROM titus.institution_account_admissions_v1 a
 WHERE a.admission_id=p_admission_id FOR UPDATE;
 IF v_adm.admission_id IS NULL THEN
 RAISE EXCEPTION 'active admission required' USING ERRCODE='42501'; END IF;
 IF v_adm.person_entity_id<>v_person THEN
 v_manager:=titus.require_current_institution_account_manager_self_v1(
 v_adm.institution_entity_id,v_adm.ledger_id,'withdraw'); END IF;
 SELECT * INTO v_old FROM titus.institution_account_admission_withdrawals_v1
 WHERE admission_id=p_admission_id;
 IF v_old.withdrawal_id IS NOT NULL THEN
 IF v_old.ended_by_person_entity_id IS DISTINCT FROM v_person
 OR v_old.withdrawal_receipt IS DISTINCT FROM ('u1-withdraw:'||p_request_id::text)
 THEN RAISE EXCEPTION 'withdrawal already issued by another actor'
 USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','titus_institution_withdraw_v1',
 'alreadyExists',true,'ended',true);
 END IF;
 INSERT INTO titus.institution_account_admission_withdrawals_v1(
 admission_id,ended_by_person_entity_id,withdrawal_receipt,ended_at)
 VALUES(p_admission_id,v_person,'u1-withdraw:'||p_request_id::text,clock_timestamp());
 RETURN jsonb_build_object('contractVersion','titus_institution_withdraw_v1',
 'alreadyExists',false,'ended',true);
END $withdraw$;
REVOKE ALL ON FUNCTION public.titus_institution_account_withdraw_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_institution_account_withdraw_self_api_v1(uuid,uuid)
 TO authenticated;

-- Only an exact currently authorized manager can cancel unaccepted invites.
CREATE FUNCTION public.titus_institution_account_cancel_invite_self_api_v1(
 p_invitation_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $cancel$
DECLARE v_person uuid;v_inv titus.institution_account_invitations_v1%ROWTYPE;
 v_manager uuid;v_old titus.institution_account_invitation_cancellations_v1%ROWTYPE;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL
 THEN RAISE EXCEPTION 'exact cancellation request required' USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_inv FROM titus.institution_account_invitations_v1
 WHERE invitation_id=p_invitation_id FOR UPDATE;
 IF v_inv.invitation_id IS NULL THEN
 RAISE EXCEPTION 'available institution invite required' USING ERRCODE='42501'; END IF;
 v_manager:=titus.require_current_institution_account_manager_self_v1(
 v_inv.institution_entity_id,v_inv.ledger_id,'cancel');
 SELECT * INTO v_old FROM titus.institution_account_invitation_cancellations_v1
 WHERE invitation_id=p_invitation_id;
 IF v_old.cancellation_id IS NOT NULL THEN
 IF v_old.cancelled_by_person_entity_id IS DISTINCT FROM v_person
 OR v_old.cancellation_request_id IS DISTINCT FROM p_request_id
 THEN RAISE EXCEPTION 'conflicting cancellation' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','titus_institution_invite_cancel_v1',
 'alreadyExists',true);
 END IF;
 IF EXISTS(SELECT 1 FROM titus.institution_account_admissions_v1
 WHERE source_invitation_id=p_invitation_id) THEN
 RAISE EXCEPTION 'accepted admission requires withdrawal, not invite cancellation'
 USING ERRCODE='42501'; END IF;
 INSERT INTO titus.institution_account_invitation_cancellations_v1(
 invitation_id,cancelled_by_person_entity_id,manager_responsibility_id,
 cancellation_request_id) VALUES(p_invitation_id,v_person,v_manager,p_request_id);
 RETURN jsonb_build_object('contractVersion','titus_institution_invite_cancel_v1',
 'alreadyExists',false);
END $cancel$;
REVOKE ALL ON FUNCTION public.titus_institution_account_cancel_invite_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_institution_account_cancel_invite_self_api_v1(uuid,uuid)
 TO authenticated;
