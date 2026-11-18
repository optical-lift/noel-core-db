-- HELD U1.2: recipient-only pending invitations and current admissions,
-- sufficient for self-acceptance/withdrawal in the one-login Titus UI.
-- No manager roster, contact lookup, license or institution Course rights.
-- Clone-only, synthetic verification, no production migration.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('titus.institution_account_invitations_v1') IS NULL
 OR to_regclass('titus.institution_account_admissions_v1') IS NULL
 OR to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'held U1.2 self-service preflight not met'
 USING ERRCODE='42501'; END IF;
END $gate$;

CREATE FUNCTION public.titus_institution_account_self_service_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $self_service$
DECLARE v_person uuid; v_pending jsonb;v_active jsonb;
BEGIN
 -- Current live Atlas-Reality Auth session + unique canonical Person;
 -- never use a caller-supplied Person ID, email or institutional context.
 v_person:=atlas.current_person_for_private_course_v1();

 -- Pending invitation is a RECIPIENT-private invitation, NOT admission.
 -- Hide stale/cancelled/accepted invitations, and recheck the same source
 -- responsibility that originally issued it through canonical Reality.
 SELECT COALESCE(jsonb_agg(
  jsonb_build_object('invitationId',i.invitation_id,
   'ledgerId',i.ledger_id,'institutionId',i.institution_entity_id)
  ORDER BY i.issued_at,i.invitation_id),'[]'::jsonb)
 INTO v_pending FROM titus.institution_account_invitations_v1 i
 JOIN ledger.ledgers l ON l.id=i.ledger_id
 JOIN reality.entities e ON e.id=i.institution_entity_id
 WHERE i.recipient_person_entity_id=v_person
  AND l.subject_entity_id=i.institution_entity_id
  AND l.ledger_state='active' AND l.retired_at IS NULL
  AND e.entity_kind IN ('organization','business') AND e.identity_state='canonical'
  AND reality.resolve_responsibility_relation_v1(
    i.issuer_person_entity_id,'titus_institution_account_management',
    'invite','entity',i.institution_entity_id,NULL,
    jsonb_build_object('ledgerId',i.ledger_id::text)
  ) IS NOT DISTINCT FROM i.issuer_responsibility_id
  AND NOT EXISTS(SELECT 1 FROM titus.institution_account_invitation_cancellations_v1 c
   WHERE c.invitation_id=i.invitation_id)
  AND NOT EXISTS(SELECT 1 FROM titus.institution_account_admissions_v1 a
   WHERE a.source_invitation_id=i.invitation_id);

 -- Accepted admission IDs are returned ONLY to the admitted Person, and
 -- only while they still form a unique currently admitted institution scope.
 -- This ID is required for the independently authorized self-withdrawal RPC.
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'admissionId',a.admission_id,'ledgerId',a.ledger_id,
   'institutionId',a.institution_entity_id) ORDER BY a.ledger_id),
   '[]'::jsonb)
 INTO v_active FROM titus.institution_account_admissions_v1 a
 JOIN ledger.ledgers l ON l.id=a.ledger_id
 JOIN reality.entities e ON e.id=a.institution_entity_id
 WHERE a.person_entity_id=v_person
  AND l.subject_entity_id=a.institution_entity_id
  AND l.ledger_state='active' AND l.retired_at IS NULL
  AND e.entity_kind IN ('organization','business') AND e.identity_state='canonical'
  AND a.accepted_at<=clock_timestamp()
  AND NOT EXISTS(SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
   WHERE w.admission_id=a.admission_id AND w.ended_at<=clock_timestamp())
  AND (
   SELECT count(*) FROM titus.institution_account_admissions_v1 other
   WHERE other.person_entity_id=v_person AND other.ledger_id=a.ledger_id
    AND other.accepted_at<=clock_timestamp()
    AND NOT EXISTS(SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 ow
     WHERE ow.admission_id=other.admission_id AND ow.ended_at<=clock_timestamp())
  )=1;
 IF jsonb_array_length(v_pending)>50 OR jsonb_array_length(v_active)>50 THEN
  RAISE EXCEPTION 'account self-service requires bounded recipient review'
   USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'contractVersion','titus_institution_account_self_service_v1',
  'pending',v_pending,'active',v_active);
END $self_service$;
REVOKE ALL ON FUNCTION public.titus_institution_account_self_service_self_api_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_institution_account_self_service_self_api_v1()
 TO authenticated;
