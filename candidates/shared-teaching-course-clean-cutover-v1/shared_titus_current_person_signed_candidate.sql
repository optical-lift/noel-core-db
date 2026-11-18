-- HELD U1.5 shared signed-Person source; disposable clone only.
-- Live atlas.current_person_id_v1() is a canonical binding reader, but this
-- distinct Titus-private adapter also proves the current GoTrue session.
-- Never make caller-provided Person IDs or JWT user_metadata authoritative.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
  OR to_regprocedure('atlas.current_person_id_v1()') IS NULL
  OR to_regclass('auth.sessions') IS NULL
  OR to_regclass('auth.users') IS NULL
  OR to_regclass('reality.auth_person_bindings') IS NULL
  OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NOT NULL
 THEN RAISE EXCEPTION 'held signed canonical Person source requires approved clone and absent target'
 USING ERRCODE='42501'; END IF;
END $gate$;

CREATE FUNCTION atlas.current_person_for_private_course_v1()
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $signed_person$
DECLARE v_auth uuid;v_session uuid;v_person uuid;v_count bigint;v_current uuid;
BEGIN
 v_auth:=auth.uid();
 BEGIN
   v_session:=nullif(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN
   v_session:=null;
 END;
 IF v_auth IS NULL OR v_session IS NULL
 OR NOT EXISTS(
  SELECT 1 FROM auth.sessions s
  JOIN auth.users u ON u.id=s.user_id
  WHERE s.id=v_session AND s.user_id=v_auth
    AND (s.not_after IS NULL OR s.not_after>clock_timestamp())
    AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
 )
 THEN RAISE EXCEPTION 'current signed GoTrue session required'
 USING ERRCODE='42501'; END IF;

 SELECT count(*),min(b.person_entity_id::text)::uuid
 INTO v_count,v_person
 FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
 WHERE b.auth_user_id=v_auth
   AND b.binding_state='active' AND b.retired_at IS NULL
   AND e.entity_kind='person' AND e.identity_state='canonical';
 IF v_count IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'one current canonical Reality Person binding required'
  USING ERRCODE='42501'; END IF;

 -- Match the already-live shared Atlas canonical Person resolver. This
 -- establishes parity, not a second identity or a second active login.
 v_current:=atlas.current_person_id_v1();
 IF v_current IS DISTINCT FROM v_person THEN
  RAISE EXCEPTION 'canonical Atlas/Reality Person disagreement'
  USING ERRCODE='42501'; END IF;
 RETURN v_person;
END $signed_person$;
REVOKE ALL ON FUNCTION atlas.current_person_for_private_course_v1()
 FROM PUBLIC,anon,authenticated;
