-- U1.10 DISPOSABLE SYNTHETIC HISTORY POSTCONDITIONS ONLY.
-- Must be run after the U1.10 fictional legacy fixture and the six-source
-- U1 held candidate on a production-SCHEMA-ONLY local clone. Never production.
-- This is fictional record retention, NOT real historic customer-data restore.
DO $titus_u110_historical_history$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 THEN RAISE EXCEPTION 'U1.10 test requires approved disposable clone'
  USING ERRCODE='42501'; END IF;
 IF (SELECT count(*) FROM titus.customer_workspaces_v1) <> 1 THEN
  RAISE EXCEPTION 'U1.10 fictional titus.customer_workspaces_v1 row-count changed' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_workspace_entitlements_v1) <> 1 THEN
  RAISE EXCEPTION 'U1.10 fictional titus.customer_workspace_entitlements_v1 row-count changed' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_drafts_v1) <> 1 THEN
  RAISE EXCEPTION 'U1.10 fictional titus.customer_course_drafts_v1 row-count changed' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_material_revisions_v1) <> 2 THEN
  RAISE EXCEPTION 'U1.10 fictional titus.customer_course_material_revisions_v1 row-count changed' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_units_v1) <> 2 THEN
  RAISE EXCEPTION 'U1.10 fictional titus.customer_course_units_v1 row-count changed' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_unit_revisions_v1) <> 3 THEN
  RAISE EXCEPTION 'U1.10 fictional titus.customer_course_unit_revisions_v1 row-count changed' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id='f0000000-0000-4000-8000-000000000001' AND 
    email='u110-fictional-history@example.invalid' AND 
    created_at='2022-04-05 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional author identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_workspaces_v1 WHERE workspace_id='f0000000-0000-4000-8000-000000000002' AND 
    owner_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    title='Fictional University' AND 
    state='active' AND 
    created_at='2022-04-05 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional workspace identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_workspace_entitlements_v1 WHERE owner_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    grant_kind='private_pilot' AND 
    grant_source_receipt='fictional-u110-receipt-only' AND 
    state='active' AND 
    granted_at='2022-04-05 12:34:56.123456+00'::timestamptz AND 
    valid_until IS NULL) THEN
  RAISE EXCEPTION 'U1.10 fictional entitlement identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_drafts_v1 WHERE course_id='f0000000-0000-4000-8000-000000000003' AND 
    workspace_id='f0000000-0000-4000-8000-000000000002' AND 
    created_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    create_request_id='f0000000-0000-4000-8000-00000000000c' AND 
    title='Fictional Legacy Course' AND 
    state='draft' AND 
    created_at='2022-04-05 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional course identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_material_revisions_v1 WHERE revision_id='f0000000-0000-4000-8000-000000000006' AND 
    course_id='f0000000-0000-4000-8000-000000000003' AND 
    edit_request_id='f0000000-0000-4000-8000-00000000000f' AND 
    based_on_revision=0 AND 
    revision_number=1 AND 
    convert_to(body_text,'UTF8') = convert_to(E'Fictional manuscript — first line\r\nSecond line','UTF8') AND 
    recorded_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    recorded_at='2022-04-05 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional manuscript revision 1 identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_material_revisions_v1 WHERE revision_id='f0000000-0000-4000-8000-000000000007' AND 
    course_id='f0000000-0000-4000-8000-000000000003' AND 
    edit_request_id='f0000000-0000-4000-8000-000000000010' AND 
    based_on_revision=1 AND 
    revision_number=2 AND 
    convert_to(body_text,'UTF8') = convert_to(E'Fictional manuscript — first line\r\nSecond line; final 🌾','UTF8') AND 
    recorded_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    recorded_at='2022-04-06 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional manuscript revision 2 identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_units_v1 WHERE unit_id='f0000000-0000-4000-8000-000000000004' AND 
    course_id='f0000000-0000-4000-8000-000000000003' AND 
    create_request_id='f0000000-0000-4000-8000-00000000000d' AND 
    kind='lesson' AND 
    title='Fictional Class' AND 
    display_position=1 AND 
    created_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    created_at='2022-04-05 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional lesson unit identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_units_v1 WHERE unit_id='f0000000-0000-4000-8000-000000000005' AND 
    course_id='f0000000-0000-4000-8000-000000000003' AND 
    create_request_id='f0000000-0000-4000-8000-00000000000e' AND 
    kind='assignment' AND 
    title='Fictional Homework' AND 
    display_position=2 AND 
    created_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    created_at='2022-04-06 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional assignment unit identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_unit_revisions_v1 WHERE revision_id='f0000000-0000-4000-8000-000000000008' AND 
    unit_id='f0000000-0000-4000-8000-000000000004' AND 
    edit_request_id='f0000000-0000-4000-8000-000000000011' AND 
    based_on_revision=0 AND 
    revision_number=1 AND 
    convert_to(body_text,'UTF8') = convert_to(E'Class note — one\nLine two','UTF8') AND 
    recorded_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    recorded_at='2022-04-05 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional unit revision 08 identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_unit_revisions_v1 WHERE revision_id='f0000000-0000-4000-8000-000000000009' AND 
    unit_id='f0000000-0000-4000-8000-000000000004' AND 
    edit_request_id='f0000000-0000-4000-8000-000000000012' AND 
    based_on_revision=1 AND 
    revision_number=2 AND 
    convert_to(body_text,'UTF8') = convert_to(E'Class note — one\nLine two + edit','UTF8') AND 
    recorded_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    recorded_at='2022-04-06 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional unit revision 09 identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM titus.customer_course_unit_revisions_v1 WHERE revision_id='f0000000-0000-4000-8000-00000000000a' AND 
    unit_id='f0000000-0000-4000-8000-000000000005' AND 
    edit_request_id='f0000000-0000-4000-8000-000000000013' AND 
    based_on_revision=0 AND 
    revision_number=1 AND 
    convert_to(body_text,'UTF8') = convert_to(E'Homework prompt — answer privately','UTF8') AND 
    recorded_by_auth_user_id='f0000000-0000-4000-8000-000000000001' AND 
    recorded_at='2022-04-07 12:34:56.123456+00'::timestamptz) THEN
  RAISE EXCEPTION 'U1.10 fictional unit revision 0a identity/history/bytes lost' USING ERRCODE='23514';
 END IF;

 RAISE NOTICE 'PASS U1.10 fictional legacy workspace/Course/Unit row identity, original authority, immutable receipts, positions, timestamps, and UTF8 bytes survived held U1; NOT actual customer-data restore';
END $titus_u110_historical_history$;
