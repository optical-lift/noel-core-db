-- M4 fictional retirement fixture; network-isolated PG17 only.
-- A reduced relational shape, NOT a production-schema clone or restore proof.
-- Reusable teacher, packet and Song data is represented as separate originals.
CREATE TABLE titus.programs(program_id uuid PRIMARY KEY);
CREATE TABLE titus.courses(course_id uuid PRIMARY KEY);
CREATE TABLE titus.customer_workspaces_v1(workspace_id uuid PRIMARY KEY);
CREATE TABLE titus.course_slots(slot_id uuid PRIMARY KEY,course_id uuid REFERENCES titus.courses);
CREATE TABLE titus.course_teachers(id uuid PRIMARY KEY,course_id uuid REFERENCES titus.courses);
CREATE TABLE titus.course_lesson_placements(id uuid PRIMARY KEY,course_id uuid REFERENCES titus.courses);
CREATE TABLE titus.course_lesson_prerequisites(id uuid PRIMARY KEY,course_id uuid REFERENCES titus.courses);
CREATE TABLE titus.program_course_placements(id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs,course_id uuid REFERENCES titus.courses);
CREATE TABLE titus.curriculum_slot_placements(id uuid PRIMARY KEY,slot_id uuid REFERENCES titus.course_slots);
CREATE TABLE titus.slot_canon_briefs(id uuid PRIMARY KEY,slot_id uuid REFERENCES titus.course_slots);
CREATE TABLE titus.canon_brief_items(id uuid PRIMARY KEY,brief_id uuid REFERENCES titus.slot_canon_briefs);
CREATE TABLE titus.slot_song_scopes(id uuid PRIMARY KEY,slot_id uuid REFERENCES titus.course_slots);
CREATE TABLE titus.slot_teacher_source_candidates(id uuid PRIMARY KEY,slot_id uuid REFERENCES titus.course_slots);
CREATE TABLE titus.course_slot_activity_log(id uuid PRIMARY KEY,slot_id uuid REFERENCES titus.course_slots);
CREATE TABLE titus.workspace_state(id uuid PRIMARY KEY);
CREATE TABLE titus.program_teachers(id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.curriculum_versions(curriculum_version_id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.curriculum_decisions(id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.curriculum_findings(id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.canon_claims(canon_claim_id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.canon_structures(canon_structure_id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.formation_units(formation_unit_id uuid PRIMARY KEY,program_id uuid REFERENCES titus.programs);
CREATE TABLE titus.formation_questions(id uuid PRIMARY KEY,formation_unit_id uuid REFERENCES titus.formation_units);
CREATE TABLE titus.formation_unit_sections(id uuid PRIMARY KEY,formation_unit_id uuid REFERENCES titus.formation_units);
CREATE TABLE titus.formation_unit_inputs(id uuid PRIMARY KEY,formation_unit_id uuid REFERENCES titus.formation_units);
CREATE TABLE titus.formation_transfer_cases(formation_transfer_case_id uuid PRIMARY KEY,formation_unit_id uuid REFERENCES titus.formation_units);
CREATE TABLE titus.formation_responses(id uuid PRIMARY KEY,formation_unit_id uuid REFERENCES titus.formation_units);
CREATE TABLE titus.formation_articulations(id uuid PRIMARY KEY,formation_unit_id uuid REFERENCES titus.formation_units);
CREATE TABLE titus.formation_transfer_attempts(id uuid PRIMARY KEY,formation_transfer_case_id uuid REFERENCES titus.formation_transfer_cases);
CREATE TABLE titus.teacher_source_adjudications(adjudication_id uuid PRIMARY KEY,curriculum_version_id uuid REFERENCES titus.curriculum_versions);
CREATE TABLE titus.teacher_source_adjudication_targets(id uuid PRIMARY KEY,adjudication_id uuid REFERENCES titus.teacher_source_adjudications,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.teacher_term_sense_targets(id uuid PRIMARY KEY,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.teacher_pattern_claim_links(id uuid PRIMARY KEY,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.canon_structure_edges(id uuid PRIMARY KEY,canon_structure_id uuid REFERENCES titus.canon_structures);
CREATE TABLE titus.canon_structure_nodes(id uuid PRIMARY KEY,canon_structure_id uuid REFERENCES titus.canon_structures);
CREATE TABLE titus.canon_claim_truth_links(id uuid PRIMARY KEY,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.canon_claim_evidence(id uuid PRIMARY KEY,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.lesson_script_segment_claims(id uuid PRIMARY KEY,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.lesson_claim_links(id uuid PRIMARY KEY,canon_claim_id uuid REFERENCES titus.canon_claims);
CREATE TABLE titus.lesson_structure_links(id uuid PRIMARY KEY,canon_structure_id uuid REFERENCES titus.canon_structures);
CREATE TABLE titus.teacher_source_units(id uuid PRIMARY KEY,body_text text NOT NULL);
CREATE TABLE titus.lesson_packets(id uuid PRIMARY KEY,body_text text NOT NULL);
-- When the program's adjudication is removed, its reference in independently
-- authored lesson work is NULLed; the lesson original itself must persist.
CREATE TABLE titus.lesson_teacher_source_links(
 id uuid PRIMARY KEY,packet_id uuid REFERENCES titus.lesson_packets,
 adjudication_id uuid REFERENCES titus.teacher_source_adjudications ON DELETE SET NULL
);
INSERT INTO titus.programs VALUES ('aaaaaaaa-0000-4000-8000-000000000001');
INSERT INTO titus.courses SELECT gen_random_uuid() FROM generate_series(1,15);
INSERT INTO titus.customer_workspaces_v1 VALUES ('aaaaaaaa-0000-4000-8000-000000000002');
INSERT INTO titus.course_slots SELECT gen_random_uuid(),(SELECT course_id FROM titus.courses LIMIT 1) FROM generate_series(1,33);
INSERT INTO titus.course_teachers SELECT gen_random_uuid(),(SELECT course_id FROM titus.courses LIMIT 1) FROM generate_series(1,9);
INSERT INTO titus.course_lesson_placements SELECT gen_random_uuid(),(SELECT course_id FROM titus.courses LIMIT 1);
INSERT INTO titus.program_course_placements SELECT gen_random_uuid(),p.program_id,(SELECT course_id FROM titus.courses LIMIT 1) FROM titus.programs p,generate_series(1,18);
INSERT INTO titus.curriculum_slot_placements SELECT gen_random_uuid(),(SELECT slot_id FROM titus.course_slots LIMIT 1) FROM generate_series(1,30);
INSERT INTO titus.slot_canon_briefs SELECT gen_random_uuid(),(SELECT slot_id FROM titus.course_slots LIMIT 1) FROM generate_series(1,4);
INSERT INTO titus.canon_brief_items SELECT gen_random_uuid(),(SELECT id FROM titus.slot_canon_briefs LIMIT 1) FROM generate_series(1,60);
INSERT INTO titus.slot_song_scopes SELECT gen_random_uuid(),(SELECT slot_id FROM titus.course_slots LIMIT 1) FROM generate_series(1,15);
INSERT INTO titus.workspace_state VALUES (gen_random_uuid());
INSERT INTO titus.program_teachers SELECT gen_random_uuid(),program_id FROM titus.programs;
INSERT INTO titus.curriculum_versions SELECT gen_random_uuid(),program_id FROM titus.programs,generate_series(1,2);
INSERT INTO titus.curriculum_decisions SELECT gen_random_uuid(),program_id FROM titus.programs,generate_series(1,15);
INSERT INTO titus.curriculum_findings SELECT gen_random_uuid(),program_id FROM titus.programs,generate_series(1,40);
INSERT INTO titus.canon_claims SELECT gen_random_uuid(),program_id FROM titus.programs,generate_series(1,26);
INSERT INTO titus.canon_structures SELECT gen_random_uuid(),program_id FROM titus.programs,generate_series(1,5);
INSERT INTO titus.formation_units SELECT gen_random_uuid(),program_id FROM titus.programs,generate_series(1,3);
INSERT INTO titus.formation_questions SELECT gen_random_uuid(),(SELECT formation_unit_id FROM titus.formation_units LIMIT 1) FROM generate_series(1,12);
INSERT INTO titus.formation_unit_sections SELECT gen_random_uuid(),(SELECT formation_unit_id FROM titus.formation_units LIMIT 1) FROM generate_series(1,18);
INSERT INTO titus.formation_unit_inputs SELECT gen_random_uuid(),(SELECT formation_unit_id FROM titus.formation_units LIMIT 1) FROM generate_series(1,45);
INSERT INTO titus.formation_transfer_cases SELECT gen_random_uuid(),(SELECT formation_unit_id FROM titus.formation_units LIMIT 1) FROM generate_series(1,3);
INSERT INTO titus.teacher_source_adjudications SELECT gen_random_uuid(),(SELECT curriculum_version_id FROM titus.curriculum_versions LIMIT 1) FROM generate_series(1,49);
INSERT INTO titus.teacher_source_adjudication_targets SELECT gen_random_uuid(),(SELECT adjudication_id FROM titus.teacher_source_adjudications LIMIT 1),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,30);
INSERT INTO titus.teacher_term_sense_targets SELECT gen_random_uuid(),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,15);
INSERT INTO titus.teacher_pattern_claim_links SELECT gen_random_uuid(),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,25);
INSERT INTO titus.canon_structure_edges SELECT gen_random_uuid(),(SELECT canon_structure_id FROM titus.canon_structures LIMIT 1) FROM generate_series(1,63);
INSERT INTO titus.canon_structure_nodes SELECT gen_random_uuid(),(SELECT canon_structure_id FROM titus.canon_structures LIMIT 1) FROM generate_series(1,59);
INSERT INTO titus.canon_claim_truth_links SELECT gen_random_uuid(),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,46);
INSERT INTO titus.canon_claim_evidence SELECT gen_random_uuid(),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,73);
INSERT INTO titus.lesson_script_segment_claims SELECT gen_random_uuid(),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,30);
INSERT INTO titus.lesson_claim_links SELECT gen_random_uuid(),(SELECT canon_claim_id FROM titus.canon_claims LIMIT 1) FROM generate_series(1,27);
INSERT INTO titus.lesson_structure_links SELECT gen_random_uuid(),(SELECT canon_structure_id FROM titus.canon_structures LIMIT 1) FROM generate_series(1,5);
INSERT INTO titus.teacher_source_units VALUES (gen_random_uuid(),'Fictional original source, retain');
INSERT INTO titus.lesson_packets VALUES ('aaaaaaaa-0000-4000-8000-000000000003','Fictional independent lesson, retain');
INSERT INTO titus.lesson_teacher_source_links SELECT gen_random_uuid(),'aaaaaaaa-0000-4000-8000-000000000003',(SELECT adjudication_id FROM titus.teacher_source_adjudications LIMIT 1);
CREATE VIEW public.titus_courses_v1 AS SELECT course_id FROM titus.courses;\nCREATE VIEW public.titus_course_prerequisites_v1 AS SELECT id FROM titus.course_lesson_prerequisites;\n-- Retiring this OLD exposure must not remove its independent lesson source.\nCREATE VIEW public.titus_course_word_pattern_boards_v1 AS SELECT id,body_text FROM titus.lesson_packets;
CREATE VIEW public.titus_course_slots_v1 AS SELECT slot_id FROM titus.course_slots;
-- All actual private legacy functions are represented by nonfunctional
-- placeholders: this test inspects retirement mechanics, never their behavior.
DO $stubs$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'public.titus_customer_catalog_self_api_v1()',
 'public.titus_customer_create_course_self_api_v1(uuid,text)',
 'public.titus_customer_start_workspace_self_api_v1(text)',
 'public.titus_customer_material_read_self_api_v1(uuid)',
 'public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)',
 'public.titus_customer_outline_read_self_api_v1(uuid)',
 'public.titus_customer_unit_create_self_api_v1(uuid,uuid,text,text)',
 'public.titus_customer_unit_move_self_api_v1(uuid,uuid,text)',
 'public.titus_customer_unit_read_self_api_v1(uuid)',
 'public.titus_customer_unit_save_self_api_v1(uuid,uuid,integer,text)',
 'titus.customer_owned_course_for_units_v1(uuid)',
 'titus.customer_current_auth_user_v1()'
 ] LOOP
  EXECUTE 'CREATE FUNCTION '||signature||' RETURNS void LANGUAGE plpgsql AS $stub_body$BEGIN RETURN; END$stub_body$';
 END LOOP;
END
$stubs$;
