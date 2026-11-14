-- HELD M4 — retire the ONE old McMillan program's exclusive descendants.
-- REQUIRES protected restored clone, verified independent full backup,
-- SK101 same-ID adoption, and separate old Course-shell removal.
-- This is data retirement only: source library TABLES remain reusable.
-- Teacher source units, lesson packets, Song objects, canonical Person,
-- original SK101 and independent lesson/source links are NEVER deleted.
-- Orchestrator owns transaction. No CASCADE and NO production execution.

DO $guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('pg_temp.sk101_source_manifest_v1') IS NULL
 OR to_regclass('titus.courses') IS NOT NULL
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM titus.programs)<>1
 OR (SELECT count(*) FROM titus.curriculum_versions)<>2
 OR (SELECT count(*) FROM titus.canon_claims)<>26
 OR (SELECT count(*) FROM titus.canon_structures)<>5
 OR (SELECT count(*) FROM titus.formation_units)<>3
 OR (SELECT count(*) FROM titus.teacher_source_adjudications)<>49
 OR (SELECT count(*) FROM titus.teacher_source_adjudications a
     JOIN titus.curriculum_versions v
       ON v.curriculum_version_id=a.curriculum_version_id
     JOIN titus.programs p ON p.program_id=v.program_id)<>49
 THEN RAISE EXCEPTION 'old McMillan program not the inventoried exclusive source'
   USING ERRCODE='23514';
 END IF;
END
$guard$;

-- Removes **relations to** old claims/Formation, not independently-authored
-- lesson packets, teacher source units or the canonical Song research library.
-- Old Program/Formation graph is one disposed lineage, verified by backup.
DELETE FROM titus.formation_articulations
 WHERE formation_unit_id IN (
  SELECT formation_unit_id FROM titus.formation_units
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.formation_transfer_attempts
 WHERE formation_transfer_case_id IN (
  SELECT tc.formation_transfer_case_id
  FROM titus.formation_transfer_cases tc
  JOIN titus.formation_units u USING(formation_unit_id)
  WHERE u.program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.formation_responses
 WHERE formation_unit_id IN (
  SELECT formation_unit_id FROM titus.formation_units
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.formation_questions
 WHERE formation_unit_id IN (
  SELECT formation_unit_id FROM titus.formation_units
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.formation_transfer_cases
 WHERE formation_unit_id IN (
  SELECT formation_unit_id FROM titus.formation_units
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.formation_unit_sections
 WHERE formation_unit_id IN (
  SELECT formation_unit_id FROM titus.formation_units
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.formation_unit_inputs
 WHERE formation_unit_id IN (
  SELECT formation_unit_id FROM titus.formation_units
  WHERE program_id IN (SELECT program_id FROM titus.programs));

-- Now remove exclusive curriculum relationships to old adjudications.
-- Independent lesson_teacher_source_links are retained: their
-- adjudication_id FK is ON DELETE SET NULL, not a DELETE CASCADE.
DELETE FROM titus.teacher_source_adjudication_targets
 WHERE adjudication_id IN (
  SELECT a.adjudication_id FROM titus.teacher_source_adjudications a
  JOIN titus.curriculum_versions v
   ON v.curriculum_version_id=a.curriculum_version_id
  WHERE v.program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.teacher_source_adjudications
 WHERE curriculum_version_id IN (
  SELECT curriculum_version_id FROM titus.curriculum_versions
  WHERE program_id IN (SELECT program_id FROM titus.programs));

-- References to old claims and structures are removed from lesson packets,
-- not the original lesson packet or teacher source unit itself.
DELETE FROM titus.lesson_script_segment_claims
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.lesson_claim_links
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.lesson_structure_links
 WHERE canon_structure_id IN (
  SELECT canon_structure_id FROM titus.canon_structures
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.teacher_pattern_claim_links
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.teacher_term_sense_targets
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.teacher_source_adjudication_targets
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));

DELETE FROM titus.canon_structure_edges
 WHERE canon_structure_id IN (
  SELECT canon_structure_id FROM titus.canon_structures
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.canon_structure_nodes
 WHERE canon_structure_id IN (
  SELECT canon_structure_id FROM titus.canon_structures
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.canon_claim_truth_links
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));
DELETE FROM titus.canon_claim_evidence
 WHERE canon_claim_id IN (
  SELECT canon_claim_id FROM titus.canon_claims
  WHERE program_id IN (SELECT program_id FROM titus.programs));

DELETE FROM titus.formation_units
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.canon_structures
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.canon_claims
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.curriculum_decisions
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.curriculum_findings
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.curriculum_versions
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.program_teachers
 WHERE program_id IN (SELECT program_id FROM titus.programs);
DELETE FROM titus.programs;

-- These tables retain reusable schema; the old program ROW has no successor.
-- No new Course is minted and no old program pointer remains active.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/sk101_clone_postretirement_manifest_attestation.sql

DO $post$
BEGIN
 IF EXISTS (SELECT 1 FROM titus.programs)
 OR EXISTS (SELECT 1 FROM titus.curriculum_versions)
 OR EXISTS (SELECT 1 FROM titus.canon_claims)
 OR EXISTS (SELECT 1 FROM titus.canon_structures)
 OR EXISTS (SELECT 1 FROM titus.formation_units)
 OR EXISTS (SELECT 1 FROM titus.teacher_source_adjudications)
 THEN RAISE EXCEPTION 'legacy McMillan program lineage not retired'
 USING ERRCODE='23514';
 END IF;
END
$post$;
