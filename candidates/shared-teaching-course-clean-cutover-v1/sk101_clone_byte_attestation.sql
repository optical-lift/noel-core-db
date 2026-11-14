-- HELD M2 independent clone attestation (POST adoption, PRE legacy deletion).
-- Reads the restored SK101 originals and adopted single canonical source.
-- Raises generic no-text exceptions. Does not print UUIDs, bodies, hashes or
-- Person Auth IDs. Not a releasable migration or full backup-restore receipt.
-- MUST execute inside owner-isolated, disposable PG17 clone transaction.
DO $byte_attestation$
DECLARE v_issues integer;
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'protected clone marker required' USING ERRCODE='42501';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_drafts_v1)<>1 OR
    (SELECT count(*) FROM atlas.teaching_courses)<>1 OR
    (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>1 OR
    (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions)<>1 OR
    (SELECT count(*) FROM titus.customer_course_units_v1)<>2 OR
    (SELECT count(*) FROM atlas.teaching_course_units)<>2 OR
    (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)<>3 OR
    (SELECT count(*) FROM atlas.teaching_course_unit_revisions)<>3 THEN
  RAISE EXCEPTION 'Course original/history count mismatch'
   USING ERRCODE='23514';
 END IF;
 SELECT count(*) INTO v_issues
 FROM titus.customer_course_drafts_v1 s
 FULL JOIN atlas.teaching_courses t ON t.id=s.course_id
 WHERE s.course_id IS NULL OR t.id IS NULL
 OR s.create_request_id IS DISTINCT FROM t.create_request_id
 OR s.created_at IS DISTINCT FROM t.created_at
 OR s.created_by_auth_user_id IS DISTINCT FROM t.created_by_auth_user_id
 OR convert_to(s.title,'UTF8') IS DISTINCT FROM convert_to(t.name,'UTF8')
 OR t.ledger_id IS NOT NULL OR t.created_by_principal_id IS NOT NULL;
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'Course ID/custody/title byte mismatch'
   USING ERRCODE='23514';
 END IF;

 SELECT count(*) INTO v_issues
 FROM titus.customer_course_material_revisions_v1 s
 FULL JOIN atlas.teaching_course_manuscript_revisions t
 ON t.revision_id=s.revision_id
 WHERE s.revision_id IS NULL OR t.revision_id IS NULL
 OR s.course_id IS DISTINCT FROM t.course_id
 OR s.edit_request_id IS DISTINCT FROM t.edit_request_id
 OR s.based_on_revision IS DISTINCT FROM t.based_on_revision
 OR s.revision_number IS DISTINCT FROM t.revision_number
 OR s.recorded_at IS DISTINCT FROM t.recorded_at
 OR s.recorded_by_auth_user_id IS DISTINCT FROM t.recorded_by_auth_user_id
 OR convert_to(s.body_text,'UTF8') IS DISTINCT FROM
    convert_to(t.body_text,'UTF8');
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'founding manuscript revision/custody UTF8 byte mismatch'
   USING ERRCODE='23514';
 END IF;

 SELECT count(*) INTO v_issues
 FROM titus.customer_course_units_v1 s
 FULL JOIN atlas.teaching_course_units t ON t.unit_id=s.unit_id
 WHERE s.unit_id IS NULL OR t.unit_id IS NULL
 OR s.course_id IS DISTINCT FROM t.course_id
 OR s.create_request_id IS DISTINCT FROM t.create_request_id
 OR s.created_at IS DISTINCT FROM t.created_at
 OR s.created_by_auth_user_id IS DISTINCT FROM t.created_by_auth_user_id
 OR s.display_position IS DISTINCT FROM t.display_position
 OR convert_to(s.kind,'UTF8') IS DISTINCT FROM
    convert_to(t.kind,'UTF8')
 OR convert_to(s.title,'UTF8') IS DISTINCT FROM
    convert_to(t.title,'UTF8');
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'Class/Homework identity/order/title byte mismatch'
   USING ERRCODE='23514';
 END IF;

 SELECT count(*) INTO v_issues
 FROM titus.customer_course_unit_revisions_v1 s
 FULL JOIN atlas.teaching_course_unit_revisions t
 ON t.revision_id=s.revision_id
 WHERE s.revision_id IS NULL OR t.revision_id IS NULL
 OR s.unit_id IS DISTINCT FROM t.unit_id
 OR s.edit_request_id IS DISTINCT FROM t.edit_request_id
 OR s.based_on_revision IS DISTINCT FROM t.based_on_revision
 OR s.revision_number IS DISTINCT FROM t.revision_number
 OR s.recorded_at IS DISTINCT FROM t.recorded_at
 OR s.recorded_by_auth_user_id IS DISTINCT FROM t.recorded_by_auth_user_id
 OR convert_to(s.body_text,'UTF8') IS DISTINCT FROM
    convert_to(t.body_text,'UTF8');
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'Class/Homework revision/custody UTF8 byte mismatch'
   USING ERRCODE='23514';
 END IF;

 SELECT count(*) INTO v_issues
 FROM titus.customer_workspace_entitlements_v1 s
 FULL JOIN titus.course_authoring_access_grants t
 ON t.grant_source_auth_user_id=s.owner_auth_user_id
 WHERE s.owner_auth_user_id IS NULL OR t.grant_source_auth_user_id IS NULL
 OR convert_to(s.grant_source_receipt,'UTF8') IS DISTINCT FROM
    convert_to(t.grant_source_receipt,'UTF8')
 OR s.grant_kind IS DISTINCT FROM t.grant_kind
 OR s.state IS DISTINCT FROM t.state
 OR s.granted_at IS DISTINCT FROM t.granted_at
 OR s.valid_until IS DISTINCT FROM t.valid_until;
 IF v_issues<>0 THEN
  RAISE EXCEPTION 'source Titus authoring grant migration mismatch'
   USING ERRCODE='23514';
 END IF;
END
$byte_attestation$;
