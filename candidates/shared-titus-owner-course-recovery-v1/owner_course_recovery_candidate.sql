-- Source candidate only. No owner identities, source texts, or data seeds.
-- Existing, explicitly established Titus owner responsibility carries authoring;
-- recover a single signed owner's legacy draft into the same canonical UUID.
BEGIN;
CREATE OR REPLACE FUNCTION titus.authoring_grant_current_active_v1(p_person uuid)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $effective_access$
 SELECT p_person IS NOT NULL AND (
 (SELECT count(*) FROM reality.responsibility_relations r
  WHERE r.carrier_person_entity_id=p_person
   AND r.responsibility_key='titus_private_pilot_issuance'
   AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
   AND r.relation_state='active' AND r.began_at<=clock_timestamp()
   AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
   AND 'author_course_as_owner'=ANY(r.permitted_operations))=1
 OR EXISTS(
  SELECT 1 FROM titus.course_authoring_access_grants g
  WHERE g.person_entity_id=p_person AND g.granted_at<=clock_timestamp()
   AND (g.valid_until IS NULL OR g.valid_until>clock_timestamp())
   AND COALESCE((SELECT e.next_state FROM titus.course_authoring_access_status_events e
    WHERE e.person_entity_id=g.person_entity_id ORDER BY e.event_seq DESC LIMIT 1),g.state)='active'
 ));
$effective_access$;
REVOKE ALL ON FUNCTION titus.authoring_grant_current_active_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Prevent a second writer from changing a historical carrier after adoption.
-- The original remains in place; only an adopted Person-origin UUID is frozen.
CREATE FUNCTION titus.guard_adopted_customer_course_history_v1()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $freeze$
DECLARE v_row jsonb; v_course uuid;
BEGIN
 FOR v_row IN SELECT x FROM unnest(ARRAY[
  CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,
  CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END]) x
  WHERE x IS NOT NULL
 LOOP
  IF TG_TABLE_NAME='customer_course_unit_revisions_v1' THEN
   SELECT course_id INTO v_course FROM titus.customer_course_units_v1
    WHERE unit_id=(v_row->>'unit_id')::uuid;
  ELSE v_course:=(v_row->>'course_id')::uuid;
  END IF;
  IF EXISTS(SELECT 1 FROM atlas.teaching_courses c WHERE c.id=v_course
    AND c.created_by_person_entity_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Course history adopted; use canonical authoring' USING ERRCODE='55000';
  END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END
$freeze$;
REVOKE ALL ON FUNCTION titus.guard_adopted_customer_course_history_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER adopted_customer_course_history_v1 BEFORE INSERT OR UPDATE OR DELETE ON titus.customer_course_drafts_v1
 FOR EACH ROW EXECUTE FUNCTION titus.guard_adopted_customer_course_history_v1();
CREATE TRIGGER adopted_customer_course_history_v1 BEFORE INSERT OR UPDATE OR DELETE ON titus.customer_course_material_revisions_v1
 FOR EACH ROW EXECUTE FUNCTION titus.guard_adopted_customer_course_history_v1();
CREATE TRIGGER adopted_customer_course_history_v1 BEFORE INSERT OR UPDATE OR DELETE ON titus.customer_course_units_v1
 FOR EACH ROW EXECUTE FUNCTION titus.guard_adopted_customer_course_history_v1();
CREATE TRIGGER adopted_customer_course_history_v1 BEFORE INSERT OR UPDATE OR DELETE ON titus.customer_course_unit_revisions_v1
 FOR EACH ROW EXECUTE FUNCTION titus.guard_adopted_customer_course_history_v1();

CREATE FUNCTION public.shared_teaching_course_adopt_self_api_v1(p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $adopt$
DECLARE v_person uuid; v_auth uuid:=auth.uid(); v_draft titus.customer_course_drafts_v1%ROWTYPE;
 v_existing atlas.teaching_courses%ROWTYPE; v_units integer; v_manuscripts integer; v_revisions integer;
BEGIN
 v_person:=titus.require_authoring_access_v1();
 PERFORM titus.require_current_pilot_issuer_self_v1('issue_pilot_code');
 IF (SELECT count(*) FROM reality.responsibility_relations r
  WHERE r.carrier_person_entity_id=v_person AND r.responsibility_key='titus_private_pilot_issuance'
   AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
   AND r.relation_state='active' AND r.began_at<=clock_timestamp()
   AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
   AND 'author_course_as_owner'=ANY(r.permitted_operations))<>1 THEN
  RAISE EXCEPTION 'Titus owner recovery required' USING ERRCODE='42501';
 END IF;
 -- Bounded administrative recovery; fail/retry if historical writes are active.
 LOCK TABLE titus.customer_course_drafts_v1,titus.customer_course_material_revisions_v1,
  titus.customer_course_units_v1,titus.customer_course_unit_revisions_v1 IN SHARE ROW EXCLUSIVE MODE NOWAIT;
 SELECT * INTO v_draft FROM titus.customer_course_drafts_v1
  WHERE course_id=p_course_id AND created_by_auth_user_id=v_auth AND state='draft';
 IF NOT FOUND THEN RAISE EXCEPTION 'owned historical draft required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM reality.entities WHERE id=v_person FOR UPDATE;
 SELECT * INTO v_existing FROM atlas.teaching_courses WHERE id=p_course_id;
 IF FOUND THEN
  IF v_existing.created_by_person_entity_id IS DISTINCT FROM v_person
   OR v_existing.created_by_auth_user_id IS DISTINCT FROM v_auth
   OR v_existing.create_request_id IS DISTINCT FROM v_draft.create_request_id
   OR v_existing.created_at IS DISTINCT FROM v_draft.created_at THEN
   RAISE EXCEPTION 'Course original collision' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_course_adopt_self_v1','courseId',p_course_id,'alreadyExists',true);
 END IF;
 -- Every restored historical act must belong to the same verified signed
 -- owner. Multi-author or unbound originals require their own adjudication.
 IF EXISTS(SELECT 1 FROM titus.customer_course_units_v1 u WHERE u.course_id=p_course_id
     AND u.created_by_auth_user_id IS DISTINCT FROM v_auth)
  OR EXISTS(SELECT 1 FROM titus.customer_course_material_revisions_v1 r WHERE r.course_id=p_course_id
     AND r.recorded_by_auth_user_id IS DISTINCT FROM v_auth)
  OR EXISTS(SELECT 1 FROM titus.customer_course_unit_revisions_v1 r
     JOIN titus.customer_course_units_v1 u ON u.unit_id=r.unit_id WHERE u.course_id=p_course_id
     AND r.recorded_by_auth_user_id IS DISTINCT FROM v_auth) THEN
  RAISE EXCEPTION 'unresolved historical author' USING ERRCODE='42501';
 END IF;
 INSERT INTO atlas.teaching_courses(id,course_key,name,status,created_at,updated_at,
   created_by_person_entity_id,created_by_auth_user_id,create_request_id)
 VALUES(v_draft.course_id,v_draft.course_id::text,v_draft.title,'active',v_draft.created_at,v_draft.created_at,
   v_person,v_auth,v_draft.create_request_id);
 INSERT INTO atlas.teaching_course_manuscript_revisions(revision_id,course_id,edit_request_id,based_on_revision,
    revision_number,body_text,recorded_by_person_entity_id,recorded_by_auth_user_id,recorded_at)
 SELECT revision_id,course_id,edit_request_id,based_on_revision,revision_number,body_text,v_person,recorded_by_auth_user_id,recorded_at
 FROM titus.customer_course_material_revisions_v1 WHERE course_id=p_course_id;
 GET DIAGNOSTICS v_manuscripts=ROW_COUNT;
 INSERT INTO atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,
    created_by_person_entity_id,created_by_auth_user_id,created_at)
 SELECT unit_id,course_id,create_request_id,kind,title,display_position,v_person,created_by_auth_user_id,created_at
 FROM titus.customer_course_units_v1 WHERE course_id=p_course_id;
 GET DIAGNOSTICS v_units=ROW_COUNT;
 INSERT INTO atlas.teaching_course_unit_revisions(revision_id,unit_id,edit_request_id,based_on_revision,
    revision_number,body_text,recorded_by_person_entity_id,recorded_by_auth_user_id,recorded_at)
 SELECT r.revision_id,r.unit_id,r.edit_request_id,r.based_on_revision,r.revision_number,r.body_text,v_person,r.recorded_by_auth_user_id,r.recorded_at
 FROM titus.customer_course_unit_revisions_v1 r JOIN titus.customer_course_units_v1 u ON u.unit_id=r.unit_id
 WHERE u.course_id=p_course_id;
 GET DIAGNOSTICS v_revisions=ROW_COUNT;
 IF EXISTS(SELECT 1 FROM titus.customer_course_material_revisions_v1 r
  LEFT JOIN atlas.teaching_course_manuscript_revisions m ON m.revision_id=r.revision_id
  WHERE r.course_id=p_course_id AND (m.revision_id IS NULL OR
   convert_to(m.body_text,'UTF8') IS DISTINCT FROM convert_to(r.body_text,'UTF8')))
 OR EXISTS(SELECT 1 FROM titus.customer_course_unit_revisions_v1 r
  JOIN titus.customer_course_units_v1 u ON u.unit_id=r.unit_id
  LEFT JOIN atlas.teaching_course_unit_revisions m ON m.revision_id=r.revision_id
  WHERE u.course_id=p_course_id AND (m.revision_id IS NULL OR
   convert_to(m.body_text,'UTF8') IS DISTINCT FROM convert_to(r.body_text,'UTF8'))) THEN
  RAISE EXCEPTION 'historical manuscript mismatch' USING ERRCODE='23514';
 END IF;
 RETURN jsonb_build_object('contractVersion','shared_course_adopt_self_v1','courseId',p_course_id,
  'alreadyExists',false,'manuscriptRevisions',v_manuscripts,'units',v_units,'unitRevisions',v_revisions);
END
$adopt$;
REVOKE ALL ON FUNCTION public.shared_teaching_course_adopt_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_course_adopt_self_api_v1(uuid) TO authenticated;
COMMIT;
