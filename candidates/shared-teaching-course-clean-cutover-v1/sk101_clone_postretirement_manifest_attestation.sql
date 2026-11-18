-- M4 HELD: compare canonical SK101 against private temporary manifest.
-- Works both before and AFTER deletion of the four old private Course
-- source tables, provided the protected clone transaction retains pg_temp.
-- Does not inspect unrelated 15 Course shells or authorize their deletion.
-- No actual production data/logs/artifacts; no deletion performed by this file.
DO $manifest_compare$
DECLARE v_issues integer;
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'protected clone marker required' USING ERRCODE='42501';
 END IF;
 IF to_regclass('pg_temp.sk101_source_manifest_v1') IS NULL OR
    to_regclass('pg_temp.sk101_source_grant_manifest_v1') IS NULL THEN
  RAISE EXCEPTION 'private source manifest missing; refusal to attest'
   USING ERRCODE='23514';
 END IF;

 WITH actual(family,original_id,parent_id,request_id,actor_auth_id,
  based_on_revision,revision_number,display_position,kind,
  original_at,original_bytes) AS (
  SELECT 'course',id,NULL::uuid,create_request_id,created_by_auth_user_id,
   NULL::integer,NULL::integer,NULL::integer,'course',
   created_at,convert_to(name,'UTF8')
  FROM atlas.teaching_courses
  UNION ALL
  SELECT 'manuscript',revision_id,course_id,edit_request_id,recorded_by_auth_user_id,
   based_on_revision,revision_number,NULL::integer,'manuscript',
   recorded_at,convert_to(body_text,'UTF8')
  FROM atlas.teaching_course_manuscript_revisions
  UNION ALL
  SELECT 'unit',unit_id,course_id,create_request_id,created_by_auth_user_id,
   NULL::integer,NULL::integer,display_position,kind,
   created_at,convert_to(title,'UTF8')
  FROM atlas.teaching_course_units
  UNION ALL
  SELECT 'unit_revision',revision_id,unit_id,edit_request_id,recorded_by_auth_user_id,
   based_on_revision,revision_number,NULL::integer,'unit_revision',
   recorded_at,convert_to(body_text,'UTF8')
  FROM atlas.teaching_course_unit_revisions
 )
 SELECT count(*) INTO v_issues
 FROM pg_temp.sk101_source_manifest_v1 expected
 FULL JOIN actual observed USING(family,original_id)
 WHERE expected.original_id IS NULL OR observed.original_id IS NULL
 OR expected.parent_id IS DISTINCT FROM observed.parent_id
 OR expected.request_id IS DISTINCT FROM observed.request_id
 OR expected.actor_auth_id IS DISTINCT FROM observed.actor_auth_id
 OR expected.based_on_revision IS DISTINCT FROM observed.based_on_revision
 OR expected.revision_number IS DISTINCT FROM observed.revision_number
 OR expected.display_position IS DISTINCT FROM observed.display_position
 OR convert_to(expected.kind,'UTF8') IS DISTINCT FROM
    convert_to(observed.kind,'UTF8')
 OR expected.original_at IS DISTINCT FROM observed.original_at
 OR expected.original_bytes IS DISTINCT FROM observed.original_bytes;
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'original SK101 preservation manifest mismatch'
   USING ERRCODE='23514';
 END IF;

 SELECT count(*) INTO v_issues
 FROM pg_temp.sk101_source_grant_manifest_v1 expected
 FULL JOIN titus.course_authoring_access_grants observed
 ON observed.grant_source_auth_user_id=expected.original_auth_id
 WHERE expected.original_auth_id IS NULL OR observed.grant_source_auth_user_id IS NULL
 OR expected.kind IS DISTINCT FROM observed.grant_kind
 OR expected.receipt_bytes IS DISTINCT FROM
    convert_to(observed.grant_source_receipt,'UTF8')
 OR expected.grant_state IS DISTINCT FROM observed.state
 OR expected.granted_at IS DISTINCT FROM observed.granted_at
 OR expected.valid_until IS DISTINCT FROM observed.valid_until;
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'original Titus authoring grant preservation mismatch'
   USING ERRCODE='23514';
 END IF;

 IF (SELECT count(*) FROM atlas.teaching_courses)<>1 OR
    (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>1 OR
    (SELECT count(*) FROM atlas.teaching_course_units)<>2 OR
    (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>3 THEN
  RAISE EXCEPTION 'canonical SK101 retained-history count mismatch'
   USING ERRCODE='23514';
 END IF;
END
$manifest_compare$;
