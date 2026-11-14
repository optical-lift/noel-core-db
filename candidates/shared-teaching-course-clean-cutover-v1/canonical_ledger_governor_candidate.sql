-- HELD M3.6: verify a current governor of an EXACT canonical native Ledger.
-- This is an INTERNAL identity/authority prerequisite, not Course operation.
-- No Course disclosure, no standing acceptance, no Version/Offering rights.
-- It cannot be invoked by authenticated/anon clients; a later source-owned
-- Teaching issuer must independently verify an active Teaching entitlement,
-- source scope and explicit separate author/institution acceptance.
DO $clone_guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'clone-only canonical Ledger governor source'
   USING ERRCODE='42501';
 END IF;
 IF to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('atlas.capability_root_authority_context_self_v1(uuid)') IS NULL THEN
  RAISE EXCEPTION 'current Person / existing signed root authority prerequisites missing'
   USING ERRCODE='23514';
 END IF;
END
$clone_guard$;

CREATE FUNCTION atlas.require_shared_course_native_ledger_governor_self_v1(
 p_ledger_id uuid
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog
AS $governor$
DECLARE
 v_person uuid;
 v_authority_person uuid;
 v_principal uuid;
 v_root uuid;
BEGIN
 -- Checks auth.uid, CURRENT auth.sessions, Reality readiness, and EXACTLY
 -- one active auth-to-canonical-Person binding. Never use a caller Person ID.
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_ledger_id IS NULL THEN
  RAISE EXCEPTION 'current governed Ledger required' USING ERRCODE='42501';
 END IF;

 -- Identity reconcile is by THE SAME verified UUID, never name, seat,
 -- organization label, the browser's claim or an inferred mapping. The
 -- legacy carrier remains explicitly checked only as the released source
 -- of root-governing authority while exact native Ledger governance moves.
 IF NOT EXISTS (
  SELECT 1
  FROM ledger.ledgers nl
  JOIN reality.entities subject ON subject.id=nl.subject_entity_id
   AND subject.identity_state='canonical'
   AND subject.entity_kind IN ('business','institution')
  JOIN atlas.ledgers carrier ON carrier.id=nl.id
   AND carrier.status='active'
  JOIN atlas.ledger_organization_participations participation
    ON participation.ledger_id=nl.id
   AND participation.status='active'
   AND participation.ended_at IS NULL
   AND participation.participation_kind='governing'
  JOIN atlas.organizations org ON org.id=participation.organization_id
   AND org.status='active'
  WHERE nl.id=p_ledger_id AND nl.ledger_state='active'
   AND nl.retired_at IS NULL
 ) THEN
  RAISE EXCEPTION 'exact current native governing Ledger source required'
   USING ERRCODE='42501';
 END IF;

 -- Released source requires root_governing authority of a CURRENT
 -- Principal; a native seat or employee/position record cannot satisfy it.
 SELECT a.person_id,a.principal_id,a.principal_ledger_authority_id
 INTO v_authority_person,v_principal,v_root
 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id) a;
 IF v_authority_person IS DISTINCT FROM v_person
 OR v_principal IS NULL OR v_root IS NULL THEN
  RAISE EXCEPTION 'current source-governed principal and Person mismatch'
   USING ERRCODE='42501';
 END IF;
 RETURN v_person;
END
$governor$;

REVOKE ALL ON FUNCTION
 atlas.require_shared_course_native_ledger_governor_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;

-- Deliberate: no public wrapper, browser EXECUTE grant, operating acceptance
-- function, data read, Course identity conversion, or Teaching grant.
