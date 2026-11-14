-- M0 HELD: private current-transaction preservation manifest, CLONE ONLY.
-- Snapshot original source IDs, custody, revisions, timestamps and literal
-- UTF-8 bytes BEFORE adopting SK101 or deleting the old private Course tables.
-- Data lives solely in the isolated session's pg_temp and is dropped at
-- transaction end. Never send this table, its rows or SHA values to Git/logs.
-- A restore of ACTUAL private production data must still be owner-authorized.
DO $manifest_guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'protected clone marker required' USING ERRCODE='42501';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_drafts_v1)<>1 OR
    (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>1 OR
    (SELECT count(*) FROM titus.customer_course_units_v1)<>2 OR
    (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)<>3 OR
    (SELECT count(*) FROM titus.customer_workspace_entitlements_v1)<>1 THEN
  RAISE EXCEPTION 'SK101 original set drift; private manifest not created'
   USING ERRCODE='23514';
 END IF;
END
$manifest_guard$;

CREATE TEMP TABLE sk101_source_manifest_v1(
 family text NOT NULL CHECK(family IN ('course','manuscript','unit','unit_revision')),
 original_id uuid NOT NULL,
 parent_id uuid,
 request_id uuid NOT NULL,
 actor_auth_id uuid NOT NULL,
 based_on_revision integer,
 revision_number integer,
 display_position integer,
 kind text,
 original_at timestamptz NOT NULL,
 original_bytes bytea NOT NULL,
 PRIMARY KEY(family,original_id)
) ON COMMIT DROP;

INSERT INTO pg_temp.sk101_source_manifest_v1
SELECT 'course',d.course_id,NULL::uuid,d.create_request_id,
 d.created_by_auth_user_id,NULL::integer,NULL::integer,NULL::integer,
 'course',d.created_at,convert_to(d.title,'UTF8')
FROM titus.customer_course_drafts_v1 d;

INSERT INTO pg_temp.sk101_source_manifest_v1
SELECT 'manuscript',r.revision_id,r.course_id,r.edit_request_id,
 r.recorded_by_auth_user_id,r.based_on_revision,r.revision_number,NULL::integer,
 'manuscript',r.recorded_at,convert_to(r.body_text,'UTF8')
FROM titus.customer_course_material_revisions_v1 r;

INSERT INTO pg_temp.sk101_source_manifest_v1
SELECT 'unit',u.unit_id,u.course_id,u.create_request_id,
 u.created_by_auth_user_id,NULL::integer,NULL::integer,
 u.display_position,u.kind,u.created_at,convert_to(u.title,'UTF8')
FROM titus.customer_course_units_v1 u;

INSERT INTO pg_temp.sk101_source_manifest_v1
SELECT 'unit_revision',r.revision_id,r.unit_id,r.edit_request_id,
 r.recorded_by_auth_user_id,r.based_on_revision,r.revision_number,NULL::integer,
 'unit_revision',r.recorded_at,convert_to(r.body_text,'UTF8')
FROM titus.customer_course_unit_revisions_v1 r;

CREATE TEMP TABLE sk101_source_grant_manifest_v1(
 original_auth_id uuid PRIMARY KEY,
 kind text NOT NULL,
 receipt_bytes bytea NOT NULL,
 grant_state text NOT NULL,
 granted_at timestamptz NOT NULL,
 valid_until timestamptz
) ON COMMIT DROP;
INSERT INTO pg_temp.sk101_source_grant_manifest_v1
SELECT owner_auth_user_id,grant_kind,
 convert_to(grant_source_receipt,'UTF8'),
 state,granted_at,valid_until
FROM titus.customer_workspace_entitlements_v1;

DO $manifest_exact$
BEGIN
 IF (SELECT count(*) FROM pg_temp.sk101_source_manifest_v1)<>7 OR
    (SELECT count(*) FROM pg_temp.sk101_source_grant_manifest_v1)<>1 THEN
  RAISE EXCEPTION 'temporary preserved SK101 manifest incomplete'
   USING ERRCODE='23514';
 END IF;
END
$manifest_exact$;
