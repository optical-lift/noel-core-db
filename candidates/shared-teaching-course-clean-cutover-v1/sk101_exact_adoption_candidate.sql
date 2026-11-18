-- M2 HELD — SAME ORIGINAL SK101. CLONE ONLY, NEVER RUN ON LIVE.
-- Uses existing source rows in a protected restored PG clone. No founder
-- text or UUID values are committed in this source or emitted in logs.
-- Requires M1 canonical Person-first schema (not an official migration).
-- Clone orchestrator starts a transaction, sets app.shared_course_clone,
-- applies M1 and this source, validates equality, then ROLLBACKs.
DO $preflight$
DECLARE
 v_drafts integer;
 v_bad integer;
BEGIN
 IF current_setting('app.shared_course_clone', true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'clone-only candidate — not live SQL' USING ERRCODE='42501';
 END IF;
 SELECT count(*) INTO v_drafts FROM titus.customer_course_drafts_v1;
 IF v_drafts <> 1 THEN
  RAISE EXCEPTION 'source Course count drift' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_material_revisions_v1) <> 1
 OR (SELECT count(*) FROM titus.customer_course_units_v1) <> 2
 OR (SELECT count(*) FROM titus.customer_course_unit_revisions_v1) <> 3 THEN
  RAISE EXCEPTION 'source revision counts drift' USING ERRCODE='23514';
 END IF;
 IF EXISTS (SELECT 1 FROM titus.customer_course_drafts_v1 d
  JOIN atlas.teaching_courses c ON c.id=d.course_id) THEN
  RAISE EXCEPTION 'Course identity already present — do not create duplicate' USING ERRCODE='23505';
 END IF;
 -- Each original author and historical editor must map to exactly one
 -- *currently established* canonical Person. Never infer from a username.
 WITH actors AS (
  SELECT created_by_auth_user_id AS auth_id FROM titus.customer_course_drafts_v1
  UNION SELECT created_by_auth_user_id FROM titus.customer_course_units_v1
  UNION SELECT recorded_by_auth_user_id FROM titus.customer_course_material_revisions_v1
  UNION SELECT recorded_by_auth_user_id FROM titus.customer_course_unit_revisions_v1
 ), fitness AS (
  SELECT a.auth_id,(
   SELECT count(*) FROM reality.auth_person_bindings b
   JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
   WHERE b.auth_user_id=a.auth_id AND b.binding_state='active' AND b.retired_at IS NULL
  ) AS n FROM actors a
 )
 SELECT count(*) INTO v_bad FROM fitness WHERE n<>1;
 IF v_bad<>0 THEN
  RAISE EXCEPTION 'unresolved historical Person binding' USING ERRCODE='42501';
 END IF;
 -- The old private-pilot product access is Person-bound in the target,
 -- not silently discarded when the legacy Auth-owned workspace disappears.
 IF EXISTS (
  SELECT 1 FROM titus.customer_workspace_entitlements_v1 g
  WHERE (SELECT count(*) FROM reality.auth_person_bindings b
    JOIN reality.entities e ON e.id=b.person_entity_id
      AND e.entity_kind='person' AND e.identity_state='canonical'
    WHERE b.auth_user_id=g.owner_auth_user_id
      AND b.binding_state='active' AND b.retired_at IS NULL)<>1
 ) THEN
  RAISE EXCEPTION 'Titus access grant Person unresolved' USING ERRCODE='42501';
 END IF;
 IF EXISTS (
  SELECT b.person_entity_id
  FROM titus.customer_workspace_entitlements_v1 g
  JOIN reality.auth_person_bindings b
    ON b.auth_user_id=g.owner_auth_user_id AND b.binding_state='active' AND b.retired_at IS NULL
  GROUP BY b.person_entity_id HAVING count(*)>1
 ) THEN
  RAISE EXCEPTION 'colliding legacy grants on a canonical Person'
   USING ERRCODE='23505';
 END IF;
 IF EXISTS(SELECT 1 FROM titus.customer_course_units_v1
           WHERE kind NOT IN ('lesson','assignment')) THEN
  RAISE EXCEPTION 'unexpected Unit kind' USING ERRCODE='23514';
 END IF;
END
$preflight$;

-- Adopt exact existing Course UUID (no UUID generation, no second Course).
INSERT INTO atlas.teaching_courses (
 id,course_key,name,status,created_at,updated_at,
 created_by_person_entity_id,created_by_auth_user_id,create_request_id
)
SELECT d.course_id,d.course_id::text,d.title,'active',d.created_at,d.created_at,
 b.person_entity_id,d.created_by_auth_user_id,d.create_request_id
FROM titus.customer_course_drafts_v1 d
JOIN reality.auth_person_bindings b ON b.auth_user_id=d.created_by_auth_user_id
 AND b.binding_state='active' AND b.retired_at IS NULL
JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical';

INSERT INTO atlas.teaching_course_manuscript_revisions(
 revision_id,course_id,edit_request_id,based_on_revision,revision_number,
 body_text,recorded_by_person_entity_id,recorded_by_auth_user_id,recorded_at
)
SELECT r.revision_id,r.course_id,r.edit_request_id,r.based_on_revision,
 r.revision_number,r.body_text,b.person_entity_id,
 r.recorded_by_auth_user_id,r.recorded_at
FROM titus.customer_course_material_revisions_v1 r
JOIN reality.auth_person_bindings b ON b.auth_user_id=r.recorded_by_auth_user_id
 AND b.binding_state='active' AND b.retired_at IS NULL
JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical';

INSERT INTO atlas.teaching_course_units(
 unit_id,course_id,create_request_id,kind,title,display_position,
 created_by_person_entity_id,created_by_auth_user_id,created_at
)
SELECT u.unit_id,u.course_id,u.create_request_id,u.kind,u.title,u.display_position,
 b.person_entity_id,u.created_by_auth_user_id,u.created_at
FROM titus.customer_course_units_v1 u
JOIN reality.auth_person_bindings b ON b.auth_user_id=u.created_by_auth_user_id
 AND b.binding_state='active' AND b.retired_at IS NULL
JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical';

INSERT INTO atlas.teaching_course_unit_revisions(
 revision_id,unit_id,edit_request_id,based_on_revision,revision_number,
 body_text,recorded_by_person_entity_id,recorded_by_auth_user_id,recorded_at
)
SELECT r.revision_id,r.unit_id,r.edit_request_id,r.based_on_revision,
 r.revision_number,r.body_text,b.person_entity_id,
 r.recorded_by_auth_user_id,r.recorded_at
FROM titus.customer_course_unit_revisions_v1 r
JOIN reality.auth_person_bindings b ON b.auth_user_id=r.recorded_by_auth_user_id
 AND b.binding_state='active' AND b.retired_at IS NULL
JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical';

-- Preserve genuine source-issued Titus pilot/purchase grants on People;
-- the canonical shared Course creator itself does not require a Titus license.
INSERT INTO titus.course_authoring_access_grants(
 person_entity_id,grant_source_auth_user_id,grant_kind,
 grant_source_receipt,state,granted_at,valid_until
)
SELECT b.person_entity_id,g.owner_auth_user_id,g.grant_kind,
 g.grant_source_receipt,g.state,g.granted_at,g.valid_until
FROM titus.customer_workspace_entitlements_v1 g
JOIN reality.auth_person_bindings b ON b.auth_user_id=g.owner_auth_user_id
 AND b.binding_state='active' AND b.retired_at IS NULL
JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical';

-- Structural and exact UTF-8 BYTE equality (not locale-collated text equality).
-- Historical source and target content is converted to bytea for comparisons.
-- No UUID or manuscript bytes are printed; mismatch raises a generic denial.
DO $compare$
DECLARE v_bad integer;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses) <> 1
 OR (SELECT count(*) FROM atlas.teaching_course_manuscript_revisions) <> 1
 OR (SELECT count(*) FROM atlas.teaching_course_units) <> 2
 OR (SELECT count(*) FROM atlas.teaching_course_unit_revisions) <> 3 THEN
  RAISE EXCEPTION 'adoption cardinality mismatch' USING ERRCODE='23514';
 END IF;

 SELECT count(*) INTO v_bad
 FROM (
  (SELECT d.course_id,d.create_request_id,convert_to(d.title,'UTF8') AS title_bytes,d.created_by_auth_user_id,d.created_at
   FROM titus.customer_course_drafts_v1 d
   EXCEPT
   SELECT c.id,c.create_request_id,convert_to(c.name,'UTF8') AS title_bytes,c.created_by_auth_user_id,c.created_at
   FROM atlas.teaching_courses c)
  UNION ALL
  (SELECT c.id,c.create_request_id,convert_to(c.name,'UTF8') AS title_bytes,c.created_by_auth_user_id,c.created_at
   FROM atlas.teaching_courses c
   EXCEPT
   SELECT d.course_id,d.create_request_id,convert_to(d.title,'UTF8') AS title_bytes,d.created_by_auth_user_id,d.created_at
   FROM titus.customer_course_drafts_v1 d)
 ) mismatch;
 IF v_bad<>0 THEN RAISE EXCEPTION 'Course original not preserved' USING ERRCODE='23514'; END IF;

 SELECT count(*) INTO v_bad FROM (
  (SELECT revision_id,course_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM titus.customer_course_material_revisions_v1
   EXCEPT
   SELECT revision_id,course_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM atlas.teaching_course_manuscript_revisions)
  UNION ALL
  (SELECT revision_id,course_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM atlas.teaching_course_manuscript_revisions
   EXCEPT
   SELECT revision_id,course_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM titus.customer_course_material_revisions_v1)
 ) mismatch;
 IF v_bad<>0 THEN RAISE EXCEPTION 'founding manuscript revision difference' USING ERRCODE='23514'; END IF;

 SELECT count(*) INTO v_bad FROM (
  (SELECT unit_id,course_id,create_request_id,convert_to(kind,'UTF8') AS kind_bytes,convert_to(title,'UTF8') AS title_bytes,display_position,
    created_by_auth_user_id,created_at
   FROM titus.customer_course_units_v1
   EXCEPT
   SELECT unit_id,course_id,create_request_id,convert_to(kind,'UTF8') AS kind_bytes,convert_to(title,'UTF8') AS title_bytes,display_position,
    created_by_auth_user_id,created_at
   FROM atlas.teaching_course_units)
  UNION ALL
  (SELECT unit_id,course_id,create_request_id,convert_to(kind,'UTF8') AS kind_bytes,convert_to(title,'UTF8') AS title_bytes,display_position,
    created_by_auth_user_id,created_at
   FROM atlas.teaching_course_units
   EXCEPT
   SELECT unit_id,course_id,create_request_id,convert_to(kind,'UTF8') AS kind_bytes,convert_to(title,'UTF8') AS title_bytes,display_position,
    created_by_auth_user_id,created_at
   FROM titus.customer_course_units_v1)
 ) mismatch;
 IF v_bad<>0 THEN RAISE EXCEPTION 'Unit original difference' USING ERRCODE='23514'; END IF;

 SELECT count(*) INTO v_bad FROM (
  (SELECT revision_id,unit_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM titus.customer_course_unit_revisions_v1
   EXCEPT
   SELECT revision_id,unit_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM atlas.teaching_course_unit_revisions)
  UNION ALL
  (SELECT revision_id,unit_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM atlas.teaching_course_unit_revisions
   EXCEPT
   SELECT revision_id,unit_id,edit_request_id,based_on_revision,revision_number,
    convert_to(body_text,'UTF8') AS body_bytes,recorded_by_auth_user_id,recorded_at
   FROM titus.customer_course_unit_revisions_v1)
 ) mismatch;
 IF v_bad<>0 THEN RAISE EXCEPTION 'Unit revision history difference' USING ERRCODE='23514'; END IF;

 SELECT count(*) INTO v_bad FROM (
  (SELECT g.owner_auth_user_id,g.grant_kind,g.grant_source_receipt,
     g.state,g.granted_at,g.valid_until
   FROM titus.customer_workspace_entitlements_v1 g
   EXCEPT
   SELECT c.grant_source_auth_user_id,c.grant_kind,c.grant_source_receipt,
     c.state,c.granted_at,c.valid_until
   FROM titus.course_authoring_access_grants c)
  UNION ALL
  (SELECT c.grant_source_auth_user_id,c.grant_kind,c.grant_source_receipt,
     c.state,c.granted_at,c.valid_until
   FROM titus.course_authoring_access_grants c
   EXCEPT
   SELECT g.owner_auth_user_id,g.grant_kind,g.grant_source_receipt,
     g.state,g.granted_at,g.valid_until
   FROM titus.customer_workspace_entitlements_v1 g)
 ) mismatch;
 IF v_bad<>0 THEN
  RAISE EXCEPTION 'original Titus product grant was not preserved'
   USING ERRCODE='23514';
 END IF;
END
$compare$;
