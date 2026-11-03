\set ON_ERROR_STOP on
-- Runs ONLY in empty disposable PostgreSQL after the existing B2A/B2B
-- fictional setup and B2B postconditions. NO REAL LEARNER DATA.
SELECT set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000102',false);

DO $test$
DECLARE
  v_response uuid := '00000000-0000-4000-8000-000000000501';
BEGIN
  -- The legacy B2B probe deliberately matches three fictional receipts.
  IF titus.formation_review_evidence_match_v1(v_response) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'fixture precondition failed: three synthetic refs must structurally match';
  END IF;
  -- This must NEVER be interpreted as an issued source grant.
  IF titus.formation_review_source_issuance_verified_v1(v_response) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'unverified fictional receipt became reviewer authority';
  END IF;
  IF titus.formation_review_source_issuance_verified_v1(NULL::uuid) IS DISTINCT FROM false
     OR titus.formation_review_source_issuance_verified_v1(
       '00000000-0000-4000-8000-000000000503'::uuid
     ) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'null / wrong response failed to deny';
  END IF;
  IF titus.formation_response_work_authority_gate_v1() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'B2A writer gate accidentally opened';
  END IF;
  IF has_function_privilege('anon',
     'titus.formation_review_source_issuance_verified_v1(uuid)','EXECUTE')
    OR has_function_privilege('authenticated',
     'titus.formation_review_source_issuance_verified_v1(uuid)','EXECUTE')
  THEN
    RAISE EXCEPTION 'browser role gained issuance-verifier EXECUTE';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='titus.formation_review_source_issuance_verified_v1(uuid)'::regprocedure
      AND NOT p.prosecdef
  ) THEN
    RAISE EXCEPTION 'issuance verifier must be SECURITY INVOKER';
  END IF;
END;
$test$;

-- Fabricate different plausible-looking source references (not authentic).
-- The older coherence matcher still says true; the issuance boundary stays
-- false. These UPDATEs are exclusively inside disposable fixture storage.
UPDATE titus.formation_review_edition_evidence_v1
SET educational_review_source_ref='00000000-0000-4000-8000-000000000821',
    source_rights_source_ref='00000000-0000-4000-8000-000000000822',
    release_decision_source_ref='00000000-0000-4000-8000-000000000823'
WHERE teaching_release_ref='00000000-0000-4000-8000-000000000601';
UPDATE titus.formation_review_disclosure_evidence_v1
SET consent_source_ref='00000000-0000-4000-8000-000000000824'
WHERE disclosure_evidence_id='00000000-0000-4000-8000-000000000701';
UPDATE titus.formation_review_mandate_evidence_v1
SET mandate_source_ref='00000000-0000-4000-8000-000000000825'
WHERE mandate_evidence_id='00000000-0000-4000-8000-000000000702';

DO $check$
BEGIN
 IF titus.formation_review_evidence_match_v1(
   '00000000-0000-4000-8000-000000000501'::uuid
 ) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'fictional structural coherence incorrectly changed';
 END IF;
 IF titus.formation_review_source_issuance_verified_v1(
   '00000000-0000-4000-8000-000000000501'::uuid
 ) IS DISTINCT FROM false THEN
   RAISE EXCEPTION 'fictional source reference forged issuance';
 END IF;
 IF EXISTS(
   SELECT 1 FROM titus.formation_responses
   WHERE formation_response_id='00000000-0000-4000-8000-000000000501'
     AND raw_text <> 'Original learner text stays in the existing original record'
 ) THEN
   RAISE EXCEPTION 'existing original text mutated';
 END IF;
END;
$check$;

-- A different acting Person, or no Person, can never make a source issue real.
SELECT set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000103',false);
DO $check$
BEGIN
 IF titus.formation_review_source_issuance_verified_v1(
    '00000000-0000-4000-8000-000000000501'::uuid
 ) IS DISTINCT FROM false THEN RAISE EXCEPTION 'wrong Person passed'; END IF;
END;
$check$;
SELECT set_config('titus.b2b_fixture_current_person','',false);
DO $check$
BEGIN
 IF titus.formation_review_source_issuance_verified_v1(
    '00000000-0000-4000-8000-000000000501'::uuid
 ) IS DISTINCT FROM false THEN RAISE EXCEPTION 'no Person passed'; END IF;
END;
$check$;

SELECT 'PASS: structural match is NOT issued reviewer authority; gate remains closed'
  AS fictional_verification_only;
