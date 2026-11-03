\set ON_ERROR_STOP on
-- B2B is a STRUCTURAL evidence matching test, not real signed permission.
CREATE OR REPLACE FUNCTION pg_temp.expect_match(
  p_expected boolean,p_label text
) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_actual boolean;
BEGIN
  SELECT titus.formation_review_evidence_match_v1(
    '00000000-0000-4000-8000-000000000501'::uuid
  ) INTO v_actual;
  IF v_actual IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'B2B % expected %, actual %',p_label,p_expected,v_actual;
  END IF;
END;
$f$;

SELECT set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000102',false);
SELECT pg_temp.expect_match(false,'no source-asserted evidence');

INSERT INTO titus.formation_review_edition_evidence_v1 (
 teaching_release_ref,program_id,curriculum_version_id,formation_unit_id,
 learner_person_entity_id,edition_fingerprint,educational_review_source_ref,
 source_rights_source_ref,release_decision_source_ref,issuer_person_entity_id,
 effective_at,expires_at
) VALUES (
 '00000000-0000-4000-8000-000000000601',
 '00000000-0000-4000-8000-000000000201',
 '00000000-0000-4000-8000-000000000602',
 '00000000-0000-4000-8000-000000000301',
 '00000000-0000-4000-8000-000000000101',
 repeat('a',64),
 '00000000-0000-4000-8000-000000000801',
 '00000000-0000-4000-8000-000000000802',
 '00000000-0000-4000-8000-000000000803',
 '00000000-0000-4000-8000-000000000103',
 now()-interval '1 day',now()+interval '1 day'
);
SELECT pg_temp.expect_match(false,'edition alone insufficient');

INSERT INTO titus.formation_review_disclosure_evidence_v1 (
 disclosure_evidence_id,teaching_release_ref,formation_response_id,
 learner_person_entity_id,reviewer_person_entity_id,consent_source_ref,
 consent_issuer_person_entity_id,effective_at,expires_at
) VALUES (
 '00000000-0000-4000-8000-000000000701',
 '00000000-0000-4000-8000-000000000601',
 '00000000-0000-4000-8000-000000000501',
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000102',
 '00000000-0000-4000-8000-000000000804',
 '00000000-0000-4000-8000-000000000101',
 now()-interval '1 day',now()+interval '1 day'
);
SELECT pg_temp.expect_match(false,'edition and learner consent without reviewer mandate');

INSERT INTO titus.formation_review_mandate_evidence_v1 (
 mandate_evidence_id,teaching_release_ref,formation_unit_id,
 learner_person_entity_id,reviewer_person_entity_id,mandate_source_ref,
 issuer_person_entity_id,mandate_operation,effective_at,expires_at
) VALUES (
 '00000000-0000-4000-8000-000000000702',
 '00000000-0000-4000-8000-000000000601',
 '00000000-0000-4000-8000-000000000301',
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000102',
 '00000000-0000-4000-8000-000000000805',
 '00000000-0000-4000-8000-000000000103',
 'review_learner_response',
 now()-interval '1 day',now()+interval '1 day'
);
-- The sole fixture success: all THREE ASSERTED sources match. Real authority,
-- issuer truth, actual consent and a live signed session remain UNPROVEN.
SELECT pg_temp.expect_match(true,'three fictional evidence receipts match');

SELECT set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000101',false);
SELECT pg_temp.expect_match(false,'learner cannot review own response');
SELECT set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000103',false);
SELECT pg_temp.expect_match(false,'unrelated Person cannot read evidence');
SELECT set_config('titus.b2b_fixture_current_person','',false);
SELECT pg_temp.expect_match(false,'no current Person');
SELECT set_config('titus.b2b_fixture_current_person',
  '00000000-0000-4000-8000-000000000102',false);

UPDATE titus.formation_review_mandate_evidence_v1 SET revoked_at=now();
SELECT pg_temp.expect_match(false,'revoked reviewer mandate');
UPDATE titus.formation_review_mandate_evidence_v1 SET revoked_at=NULL;
SELECT pg_temp.expect_match(true,'restored fixture mandate');

UPDATE titus.formation_review_disclosure_evidence_v1 SET withdrawn_at=now();
SELECT pg_temp.expect_match(false,'withdrawn learner consent');
UPDATE titus.formation_review_disclosure_evidence_v1 SET withdrawn_at=NULL;

UPDATE titus.formation_review_edition_evidence_v1 SET withdrawn_at=now();
SELECT pg_temp.expect_match(false,'withdrawn teaching edition');
UPDATE titus.formation_review_edition_evidence_v1 SET withdrawn_at=NULL;

UPDATE titus.formation_review_mandate_evidence_v1
  SET expires_at=now()-interval '1 minute';
SELECT pg_temp.expect_match(false,'expired reviewer mandate');
UPDATE titus.formation_review_mandate_evidence_v1
  SET expires_at=now()+interval '1 day';

UPDATE titus.formation_review_disclosure_evidence_v1
  SET expires_at=now()-interval '1 minute';
SELECT pg_temp.expect_match(false,'expired response disclosure');
UPDATE titus.formation_review_disclosure_evidence_v1
  SET expires_at=now()+interval '1 day';

UPDATE titus.formation_review_edition_evidence_v1
  SET expires_at=now()-interval '1 minute';
SELECT pg_temp.expect_match(false,'expired edition release');
UPDATE titus.formation_review_edition_evidence_v1
  SET expires_at=now()+interval '1 day';

UPDATE titus.formation_review_mandate_evidence_v1
 SET reviewer_person_entity_id='00000000-0000-4000-8000-000000000103';
SELECT pg_temp.expect_match(false,'wrong reviewer');
UPDATE titus.formation_review_mandate_evidence_v1
 SET reviewer_person_entity_id='00000000-0000-4000-8000-000000000102';

UPDATE titus.formation_review_disclosure_evidence_v1
 SET formation_response_id='00000000-0000-4000-8000-000000000502';
SELECT pg_temp.expect_match(false,'consent to a different response');
UPDATE titus.formation_review_disclosure_evidence_v1
 SET formation_response_id='00000000-0000-4000-8000-000000000501';

UPDATE titus.formation_review_mandate_evidence_v1
 SET formation_unit_id='00000000-0000-4000-8000-000000000302';
SELECT pg_temp.expect_match(false,'wrong unit reviewer mandate');
UPDATE titus.formation_review_mandate_evidence_v1
 SET formation_unit_id='00000000-0000-4000-8000-000000000301';

UPDATE titus.curriculum_versions SET version_status='draft'
 WHERE curriculum_version_id='00000000-0000-4000-8000-000000000602';
SELECT pg_temp.expect_match(false,'draft curriculum version not released');
UPDATE titus.curriculum_versions SET version_status='frozen'
 WHERE curriculum_version_id='00000000-0000-4000-8000-000000000602';

UPDATE titus.curriculum_versions SET program_id='00000000-0000-4000-8000-000000000202'
 WHERE curriculum_version_id='00000000-0000-4000-8000-000000000602';
SELECT pg_temp.expect_match(false,'wrong program version');
UPDATE titus.curriculum_versions SET program_id='00000000-0000-4000-8000-000000000201'
 WHERE curriculum_version_id='00000000-0000-4000-8000-000000000602';

UPDATE titus.formation_units SET review_state='needs_review'
 WHERE formation_unit_id='00000000-0000-4000-8000-000000000301';
SELECT pg_temp.expect_match(false,'stale unit');
UPDATE titus.formation_units SET review_state='current'
 WHERE formation_unit_id='00000000-0000-4000-8000-000000000301';

UPDATE titus.formation_responses SET response_status='reviewed'
 WHERE formation_response_id='00000000-0000-4000-8000-000000000501';
SELECT pg_temp.expect_match(false,'not-submitted original');
UPDATE titus.formation_responses SET response_status='submitted'
 WHERE formation_response_id='00000000-0000-4000-8000-000000000501';

UPDATE titus.teacher_person_bindings SET binding_state='retired',retired_at=now()
 WHERE person_entity_id='00000000-0000-4000-8000-000000000101';
SELECT pg_temp.expect_match(false,'withdrawn active learner binding');
UPDATE titus.teacher_person_bindings SET binding_state='active',retired_at=NULL
 WHERE person_entity_id='00000000-0000-4000-8000-000000000101';

SELECT pg_temp.expect_match(true,'final fictional source coherence restored');

DO $assert$
BEGIN
 IF EXISTS (
  SELECT 1 FROM (VALUES
   ('titus.formation_review_edition_evidence_v1'),
   ('titus.formation_review_disclosure_evidence_v1'),
   ('titus.formation_review_mandate_evidence_v1')
  ) x(rel) WHERE NOT (
   SELECT c.relrowsecurity FROM pg_class c WHERE c.oid=x.rel::regclass
  )
 ) THEN RAISE EXCEPTION 'missing private-table RLS'; END IF;
 IF has_table_privilege('authenticated',
     'titus.formation_review_edition_evidence_v1','SELECT')
  OR has_table_privilege('authenticated',
     'titus.formation_review_disclosure_evidence_v1','INSERT')
  OR has_table_privilege('anon',
     'titus.formation_review_mandate_evidence_v1','SELECT')
  OR has_function_privilege('authenticated',
     'titus.formation_review_evidence_match_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'unexpected public/browser authority'; END IF;
 IF titus.formation_response_work_authority_gate_v1() THEN
   RAISE EXCEPTION 'B2A writer gate accidentally opened'; END IF;
END;
$assert$;
SELECT 'B2B fictional evidence coherence PASS; real issuance/auth NOT established' AS verdict;
