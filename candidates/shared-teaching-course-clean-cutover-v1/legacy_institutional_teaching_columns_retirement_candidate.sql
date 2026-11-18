-- HELD M4.2: remove institutional-founder identity columns/old guards
-- from the SINGLE retained Person-authored Course, Version and Offering.
-- Requires M4.1 obsolete old RPCs retired, full original manifest and
-- proof there are NO existing legacy-provenance rows. RESTRICT only.
-- Clone migration candidate, NOT production SQL authorization.
DO $guard$
DECLARE v_bad text;
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('pg_temp.sk101_source_manifest_v1') IS NULL
 OR to_regclass('titus.courses') IS NOT NULL
 OR to_regclass('titus.customer_course_drafts_v1') IS NOT NULL
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_courses
    WHERE created_by_person_entity_id IS NOT NULL
      AND ledger_id IS NULL AND capability_activation_id IS NULL
      AND created_by_person_id IS NULL AND created_by_principal_id IS NULL)
 OR EXISTS(SELECT 1 FROM atlas.teaching_course_versions v
    WHERE v.published_by_person_entity_id IS NULL
       OR v.published_by_person_id IS NOT NULL OR v.published_by_principal_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM atlas.teaching_course_offerings o
    WHERE o.operating_proposal_id IS NULL
      OR o.created_by_person_entity_id IS NULL
      OR o.created_by_person_id IS NOT NULL OR o.created_by_principal_id IS NOT NULL)
 THEN RAISE EXCEPTION 'noncanonical Course, Version or Offering still owns old institutional identity'
  USING ERRCODE='23514';
 END IF;
 SELECT string_agg(p.proname,',') INTO v_bad
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname IN (
  'create_teaching_course_self_api_v1',
  'create_teaching_course_from_activation_self_api_v1',
  'teaching_courses_admin_self_api_v1',
  'teaching_course_admin_self_api_v1',
  'retire_teaching_course_self_api_v1',
  'publish_teaching_course_version_self_api_v1',
  'create_teaching_course_offering_self_api_v1',
  'transition_teaching_course_offering_self_api_v1',
  'teaching_offering_roster_admin_self_api_v1',
  'enroll_person_in_teaching_offering_self_api_v1',
  'withdraw_teaching_enrollment_self_api_v1',
  'teaching_enrollments_for_current_person_self_api_v1');
 IF v_bad IS NOT NULL THEN
  RAISE EXCEPTION 'old privileged Teaching RPCs must first be fully retired: %',v_bad
   USING ERRCODE='23514';
 END IF;
END $guard$;

-- Their original institutional principal identity has no remaining
-- permitted Course root meaning. DROP RESTRICT refuses unlisted dependencies.
-- Preserve Course.id, name, course_key, Person founder and every revision.
ALTER TABLE atlas.teaching_courses
 DROP COLUMN ledger_id RESTRICT,
 DROP COLUMN capability_activation_id RESTRICT,
 DROP COLUMN created_by_person_id RESTRICT,
 DROP COLUMN created_by_principal_id RESTRICT;

-- The original immutable Version remains the SAME id/revision sequence.
-- Its Person author is mandatory; old publisher aliases cannot be queried.
ALTER TABLE atlas.teaching_course_versions
 ALTER COLUMN published_by_person_entity_id SET NOT NULL,
 DROP COLUMN published_by_person_id RESTRICT,
 DROP COLUMN published_by_principal_id RESTRICT;

-- The old institutional mutable Offering guard depended on former legacy
-- creator columns. Canonical shared Offering's independent identity+open
-- issuer guards now own this unchanged original Offering table.
DROP TRIGGER teaching_course_offerings_update_guard_v1
 ON atlas.teaching_course_offerings RESTRICT;
DROP FUNCTION atlas.guard_teaching_course_offering_update_v1() RESTRICT;
ALTER TABLE atlas.teaching_course_offerings
 DROP CONSTRAINT shared_course_offering_creator_coherence RESTRICT,
 ALTER COLUMN created_by_person_entity_id SET NOT NULL,
 ALTER COLUMN operating_proposal_id SET NOT NULL,
 ALTER COLUMN creation_request_id SET NOT NULL,
 DROP COLUMN created_by_person_id RESTRICT,
 DROP COLUMN created_by_principal_id RESTRICT;

-- Guard against stray overloads, superseded nullability, or unanticipated
-- old identity columns in any of the three retained canonical carriers.
DO $verified$
DECLARE v_old text;
BEGIN
 SELECT string_agg(n.nspname||'.'||c.relname||'.'||a.attname,', ' ORDER BY c.relname,a.attname)
 INTO v_old
 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='atlas' AND c.relname IN (
  'teaching_courses','teaching_course_versions','teaching_course_offerings')
 AND a.attnum>0 AND NOT a.attisdropped AND
 ((c.relname='teaching_courses' AND a.attname IN (
  'ledger_id','capability_activation_id','created_by_person_id','created_by_principal_id'))
 OR (c.relname='teaching_course_versions' AND a.attname IN (
  'published_by_person_id','published_by_principal_id'))
 OR (c.relname='teaching_course_offerings' AND a.attname IN (
  'created_by_person_id','created_by_principal_id')));
 IF v_old IS NOT NULL THEN
  RAISE EXCEPTION 'obsolete institutional Course identity columns remain: %',v_old
   USING ERRCODE='23514';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname='guard_teaching_course_offering_update_v1')
 THEN RAISE EXCEPTION 'obsolete legacy Offering mutation guard survived'
   USING ERRCODE='23514';
 END IF;
END $verified$;
