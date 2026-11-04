-- Local-only creation of sample classroom roots, never source issuance.
-- Before/after proving hard-false root gate, temporary test override only.
DO $closed$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO titus.classroom_threads_v1(
      thread_id,source_kind,course_ref,unit_ref,opened_by_person_entity_id)
    VALUES('00000000-0000-4000-8000-000000000100','fixture','song',
           'song-01','00000000-0000-4000-8000-000000000204');
  EXCEPTION WHEN OTHERS THEN
    denied:=position('no authorized classroom thread writer' in SQLERRM)>0;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: source root guard not closed'; END IF;
END;$closed$;
CREATE OR REPLACE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT true$$;
INSERT INTO titus.classroom_threads_v1(
  thread_id,source_kind,course_ref,unit_ref,opened_by_person_entity_id,
  teaching_release_ref)
VALUES
 ('00000000-0000-4000-8000-000000000100','fixture','song','song-01',
  '00000000-0000-4000-8000-000000000204',NULL),
 ('00000000-0000-4000-8000-000000000101','fixture','song','song-02',
  '00000000-0000-4000-8000-000000000204',NULL),
 ('00000000-0000-4000-8000-000000000102','approved_edition',
  'formation','unit-11','00000000-0000-4000-8000-000000000204',
  '00000000-0000-4000-8000-000000000399');
CREATE OR REPLACE FUNCTION titus.classroom_authority_gate_v1()
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT false$$;
