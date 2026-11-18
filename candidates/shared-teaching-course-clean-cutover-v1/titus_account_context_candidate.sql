-- HELD TITUS U1: one signed Person, one Auth credential, independently admitted
-- personal / institution account CONTEXTS. Clone-only source, NOT a migration.
-- No customer license, account, institution or Course is created by this source.
-- Instit. admission issuer/acceptance writer and signed protected proof are HELD.
-- Execute ONLY with app.shared_course_clone='approved' on network-isolated PG17.
DO $u1_preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
  OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
  OR to_regclass('ledger.ledgers') IS NULL
  OR to_regclass('reality.entities') IS NULL THEN
  RAISE EXCEPTION 'held Titus account-scope clone prerequisites not met'
   USING ERRCODE='42501';
 END IF;
END
$u1_preflight$;

-- A Titus-specific accepted participation record. It REFERENCES canonical
-- institutional identity; it is not another Person or organization registry.
-- There is deliberately NO public/authenticated issuance writer in U1.
-- Existing Atlas Ledger seats/memberships do NOT insert these records.
CREATE TABLE titus.institution_account_admissions_v1 (
 admission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 institution_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 issued_by_person_entity_id uuid NOT NULL
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 issue_receipt text NOT NULL UNIQUE CHECK(length(btrim(issue_receipt)) BETWEEN 8 AND 256),
 acceptance_receipt text NOT NULL UNIQUE CHECK(length(btrim(acceptance_receipt)) BETWEEN 8 AND 256),
 issued_at timestamptz NOT NULL,
 accepted_at timestamptz NOT NULL,
 CHECK(accepted_at >= issued_at),
 CHECK(person_entity_id <> institution_entity_id)
);
CREATE INDEX titus_institution_account_admission_person_scope_v1
 ON titus.institution_account_admissions_v1(person_entity_id,ledger_id);
CREATE TABLE titus.institution_account_admission_withdrawals_v1 (
 withdrawal_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 admission_id uuid NOT NULL UNIQUE REFERENCES
  titus.institution_account_admissions_v1(admission_id) ON DELETE RESTRICT,
 ended_by_person_entity_id uuid NOT NULL
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 withdrawal_receipt text NOT NULL UNIQUE
  CHECK(length(btrim(withdrawal_receipt)) BETWEEN 8 AND 256),
 ended_at timestamptz NOT NULL
);
ALTER TABLE titus.institution_account_admissions_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.institution_account_admission_withdrawals_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.institution_account_admissions_v1,
 titus.institution_account_admission_withdrawals_v1 FROM PUBLIC,anon,authenticated;

-- Immutable admission and withdrawal originals; withdrawal is a separate fact.
CREATE FUNCTION titus.reject_account_context_original_mutation_v1()
RETURNS trigger LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog
AS $original$
BEGIN
 RAISE EXCEPTION 'Titus context source original is immutable'
  USING ERRCODE='55000';
END
$original$;
CREATE TRIGGER titus_institution_account_admissions_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.institution_account_admissions_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();
CREATE TRIGGER titus_institution_account_withdrawals_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.institution_account_admission_withdrawals_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_account_context_original_mutation_v1();
REVOKE ALL ON FUNCTION titus.reject_account_context_original_mutation_v1()
 FROM PUBLIC,anon,authenticated;

-- This private helper proves context admission only. It does NOT prove a
-- license/seat/teacher appointment/Course agreement, and must never be used
-- as a shortcut for an operation-specific authorization decision.
CREATE FUNCTION titus.require_current_account_context_self_v1(
 p_kind text,p_ledger_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $context$
DECLARE v_person uuid; v_institution uuid; v_count bigint;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_kind='personal' AND p_ledger_id IS NULL THEN
  RETURN jsonb_build_object('kind','personal','personId',v_person);
 ELSIF p_kind='institution' AND p_ledger_id IS NOT NULL THEN
  SELECT count(*),min(a.institution_entity_id::text)::uuid
    INTO v_count,v_institution
  FROM titus.institution_account_admissions_v1 a
  JOIN ledger.ledgers l ON l.id=a.ledger_id
  JOIN reality.entities e ON e.id=a.institution_entity_id
  WHERE a.person_entity_id=v_person AND a.ledger_id=p_ledger_id
   AND l.subject_entity_id=a.institution_entity_id
   AND l.ledger_state='active' AND l.retired_at IS NULL
   AND e.entity_kind IN ('business','organization')
   AND e.identity_state='canonical'
   AND a.accepted_at<=clock_timestamp()
   AND NOT EXISTS(
    SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
    WHERE w.admission_id=a.admission_id AND w.ended_at<=clock_timestamp()
   );
  IF v_count=1 THEN
   RETURN jsonb_build_object('kind','institution','personId',v_person,
    'ledgerId',p_ledger_id,'institutionId',v_institution);
  END IF;
 END IF;
 RAISE EXCEPTION 'current Titus account context admission required'
  USING ERRCODE='42501';
END
$context$;
REVOKE ALL ON FUNCTION titus.require_current_account_context_self_v1(text,uuid)
 FROM PUBLIC,anon,authenticated;

-- Account selector read only. Personal scope is NOT a Titus license.
-- Institution scope is exposed only after exact, unique current admission.
-- Never return Course, bill, contact, roster, plan or private-source contents.
CREATE FUNCTION public.titus_account_contexts_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $list$
DECLARE v_person uuid; v_institutions jsonb;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT COALESCE(jsonb_agg(jsonb_build_object('kind','institution',
  'ledgerId',s.ledger_id,'institutionId',s.institution_entity_id)
  ORDER BY s.ledger_id),'[]'::jsonb) INTO v_institutions
 FROM (
  SELECT a.ledger_id,min(a.institution_entity_id::text)::uuid AS institution_entity_id
  FROM titus.institution_account_admissions_v1 a
  JOIN ledger.ledgers l ON l.id=a.ledger_id
  JOIN reality.entities e ON e.id=a.institution_entity_id
  WHERE a.person_entity_id=v_person
   AND l.subject_entity_id=a.institution_entity_id
   AND l.ledger_state='active' AND l.retired_at IS NULL
   AND e.entity_kind IN ('business','organization')
   AND e.identity_state='canonical'
   AND a.accepted_at<=clock_timestamp()
   AND NOT EXISTS (
    SELECT 1 FROM titus.institution_account_admission_withdrawals_v1 w
    WHERE w.admission_id=a.admission_id AND w.ended_at<=clock_timestamp()
   )
  GROUP BY a.ledger_id
  HAVING count(*)=1 AND count(DISTINCT a.institution_entity_id)=1
 ) s;
 RETURN jsonb_build_object('contractVersion','titus_account_contexts_v1',
  'personal',jsonb_build_object('kind','personal','personId',v_person),
  'institutions',v_institutions);
END
$list$;
REVOKE ALL ON FUNCTION public.titus_account_contexts_self_api_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_account_contexts_self_api_v1()
 TO authenticated;

-- Exact scope verification, still NOT a license or Course permission.
CREATE FUNCTION public.titus_account_context_check_self_api_v1(
 p_kind text,p_ledger_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $check$
BEGIN
 RETURN jsonb_build_object('contractVersion','titus_account_context_check_v1',
  'context',titus.require_current_account_context_self_v1(
   p_kind,p_ledger_id));
END
$check$;
REVOKE ALL ON FUNCTION public.titus_account_context_check_self_api_v1(text,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_account_context_check_self_api_v1(text,uuid)
 TO authenticated;
