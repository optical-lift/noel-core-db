-- HELD Radio institutional publishing standing probe. No grant issuer,
-- license, publication, rights, customer record, migration or public RPC.
-- This is one prerequisite to a future signed publish transaction, not
-- sufficient authorization to issue an Edition/Holding or circulate bytes.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('titus.require_current_account_context_self_v1(text,uuid)') IS NULL
 OR to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'held publishing standing probe prerequisites missing' USING ERRCODE='42501'; END IF;
END $preflight$;

CREATE FUNCTION titus.require_current_institution_publisher_self_v1(p_ledger_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path TO pg_catalog AS $publisher$
DECLARE v_context jsonb; v_person uuid; v_institution uuid;
 v_admissions uuid[]; v_responsibilities uuid[]; v_resolved uuid;
BEGIN
 IF p_ledger_id IS NULL THEN
  RAISE EXCEPTION 'exact institutional publishing scope required' USING ERRCODE='42501';
 END IF;
 -- Same native Ledger and current Person context as U1. No supplied actor.
 v_context:=titus.require_current_account_context_self_v1('institution',p_ledger_id);
 v_person:=(v_context->>'personId')::uuid;
 v_institution:=(v_context->>'institutionId')::uuid;
 -- Lock Ledger first, then admission (withdrawal locks admission), then
 -- operation-specific responsibility. Final integrated concurrency proof
 -- must include all grant/rights/withdrawal writers, not just this probe.
 PERFORM 1 FROM ledger.ledgers l
 WHERE l.id=p_ledger_id AND l.subject_entity_id=v_institution
 AND l.ledger_state='active' AND l.retired_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active publication Ledger required' USING ERRCODE='42501'; END IF;
 SELECT array_agg(x.admission_id) INTO v_admissions FROM (
  SELECT a.admission_id FROM titus.institution_account_admissions_v1 a
  WHERE a.person_entity_id=v_person AND a.ledger_id=p_ledger_id
  AND a.institution_entity_id=v_institution AND a.accepted_at<=clock_timestamp()
  AND NOT EXISTS (SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
    WHERE w.admission_id=a.admission_id AND w.ended_at<=clock_timestamp())
  FOR UPDATE
 ) x;
 IF cardinality(v_admissions) IS DISTINCT FROM 1
 OR titus.require_current_account_context_self_v1('institution',p_ledger_id) IS DISTINCT FROM v_context
 THEN RAISE EXCEPTION 'institutional admission changed' USING ERRCODE='42501'; END IF;
 -- Proposed neutral responsibility key; source issuance is not implemented.
 SELECT array_agg(x.id) INTO v_responsibilities FROM (
  SELECT r.id FROM reality.responsibility_relations r
  WHERE r.carrier_person_entity_id=v_person
   AND r.responsibility_key='institution_publication_management'
   AND r.jurisdiction_kind='entity' AND r.jurisdiction_entity_id=v_institution
   AND r.jurisdiction_domain IS NULL
   AND r.scope=jsonb_build_object('ledgerId',p_ledger_id::text)
   AND r.relation_state='active' AND r.ended_at IS NULL
   AND r.began_at<=clock_timestamp() AND 'publish'=ANY(r.permitted_operations)
  FOR SHARE
 ) x;
 IF cardinality(v_responsibilities) IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'exact current publishing responsibility required' USING ERRCODE='42501';
 END IF;
 v_resolved:=reality.resolve_responsibility_relation_v1(
  v_person,'institution_publication_management','publish','entity',v_institution,
  NULL,jsonb_build_object('ledgerId',p_ledger_id::text));
 IF v_resolved IS DISTINCT FROM v_responsibilities[1] THEN
  RAISE EXCEPTION 'canonical publishing responsibility mismatch' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('contractVersion','institution_publishing_standing_probe_v1',
  'personId',v_person,'institutionId',v_institution,'ledgerId',p_ledger_id,
  'admissionId',v_admissions[1],'responsibilityId',v_resolved,
  'publicationApproved',false);
END $publisher$;
REVOKE ALL ON FUNCTION titus.require_current_institution_publisher_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;
DO $acl$
BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
  EXECUTE 'REVOKE ALL ON FUNCTION titus.require_current_institution_publisher_self_v1(uuid) FROM service_role';
 END IF;
END $acl$;
