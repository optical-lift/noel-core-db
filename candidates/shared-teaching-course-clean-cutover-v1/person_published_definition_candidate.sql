-- HELD M3.9: one immutable definition METADATA version, on existing Course.
-- Author retains root custody. A Version is NOT manuscript or Unit release.
-- Clone-only; no direct DB grants or institutional Course-operation grant.
DO $source_guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)')
    IS NULL
 OR to_regclass('atlas.teaching_course_versions') IS NULL THEN
  RAISE EXCEPTION 'held Course definition source prerequisites missing'
    USING ERRCODE='42501';
 END IF;
END $source_guard$;

-- The old institutional definition writer required a legacy atlas Person AND
-- Principal. A canonical Person-origin Course must have no such dependency.
-- Existing immutable Version originals (if any) are never rewritten.
ALTER TABLE atlas.teaching_course_versions
 ALTER COLUMN published_by_person_id DROP NOT NULL,
 ALTER COLUMN published_by_principal_id DROP NOT NULL,
 ADD COLUMN published_by_person_entity_id uuid
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN publication_request_id uuid,
 ADD COLUMN publication_scope text NOT NULL DEFAULT 'definition_metadata_only'
   CHECK(publication_scope='definition_metadata_only'),
 ADD CONSTRAINT teaching_course_version_exact_request_uq
   UNIQUE(course_id,publication_request_id);

ALTER TABLE atlas.teaching_course_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_versions FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.shared_teaching_course_definition_publish_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_title text,p_summary text,p_outcomes text[]
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $publish$
DECLARE
 v_course uuid;
 v_person uuid;
 v_title text:=btrim(coalesce(p_title,''));
 v_summary text:=nullif(btrim(coalesce(p_summary,'')),'');
 v_outcomes text[]:=coalesce(p_outcomes,ARRAY[]::text[]);
 v_old atlas.teaching_course_versions%ROWTYPE;
 v_new atlas.teaching_course_versions%ROWTYPE;
 v_no integer;
BEGIN
 IF p_request_id IS NULL OR length(v_title) NOT BETWEEN 1 AND 150
 OR length(coalesce(v_summary,''))>2000
 OR cardinality(v_outcomes)>30 OR EXISTS(
  SELECT 1 FROM unnest(v_outcomes) o
  WHERE o IS NULL OR length(btrim(o)) NOT BETWEEN 1 AND 500
 ) THEN
  RAISE EXCEPTION 'valid version metadata and request required'
    USING ERRCODE='22023';
 END IF;
 -- Locks actual active Course and verifies signed current Reality Person.
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();

 SELECT * INTO v_old FROM atlas.teaching_course_versions
 WHERE course_id=v_course AND publication_request_id=p_request_id;
 IF v_old.id IS NOT NULL THEN
  IF v_old.published_by_person_entity_id IS DISTINCT FROM v_person
  OR v_old.title IS DISTINCT FROM v_title
  OR v_old.summary IS DISTINCT FROM v_summary
  OR v_old.learning_outcomes IS DISTINCT FROM v_outcomes
  OR v_old.publication_scope<>'definition_metadata_only' THEN
   RAISE EXCEPTION 'changed immutable Course Version request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_definition_publish_v1',
   'courseId',v_course,'courseVersionId',v_old.id,
   'versionNo',v_old.version_no,'publicationScope',v_old.publication_scope,
   'alreadyExists',true,'institutionCanUse',false);
 END IF;

 SELECT coalesce(max(version_no),0)+1 INTO v_no
 FROM atlas.teaching_course_versions WHERE course_id=v_course;
 INSERT INTO atlas.teaching_course_versions(
  course_id,version_no,title,summary,learning_outcomes,
  published_by_person_id,published_by_principal_id,
  published_by_person_entity_id,publication_request_id,publication_scope
 ) VALUES (
  v_course,v_no,v_title,v_summary,v_outcomes,
  NULL,NULL,v_person,p_request_id,'definition_metadata_only'
 ) RETURNING * INTO v_new;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_definition_publish_v1',
  'courseId',v_course,'courseVersionId',v_new.id,
  'versionNo',v_new.version_no,'publicationScope',v_new.publication_scope,
  'alreadyExists',false,'institutionCanUse',false);
END $publish$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])
 TO authenticated;

-- Deliberately no institutional Version reader or Offering writer here.
-- Version immutability relies on the existing BEFORE UPDATE OR DELETE
-- atlas.reject_teaching_course_version_mutation_v1 trigger (verified in clone).
