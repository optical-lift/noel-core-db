-- HELD Us Carry v3 increment E: independent backend database principal and
-- owner-scoped bounded history. NOT a production migration.
-- The standalone Us service verifies the actual user bearer with GoTrue.
-- It passes that verified principal as p_owner_auth_user_id, never a request
-- body-supplied UUID. This function additionally enforces exact stream scope.
-- A stolen server DB credential must not be shipped to any client; SQL itself
-- cannot authenticate a bearer token supplied as an arbitrary UUID.
BEGIN;

DO $role$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
                WHERE rolname='us_carry_backend') THEN
  CREATE ROLE us_carry_backend NOLOGIN NOINHERIT NOSUPERUSER
       NOCREATEDB NOCREATEROLE NOBYPASSRLS;
 ELSE
  IF EXISTS (
     SELECT 1 FROM pg_catalog.pg_roles
     WHERE rolname='us_carry_backend'
       AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls)
  ) OR pg_catalog.pg_has_role('us_carry_backend','service_role','MEMBER') THEN
   RAISE EXCEPTION 'Us backend role is unexpectedly privileged'
      USING ERRCODE='42501';
  END IF;
 END IF;
END $role$;

CREATE FUNCTION us.carry_read_owned_history_v3(
 p_owner_auth_user_id uuid, p_stream_id uuid,
 p_after_sequence bigint DEFAULT 0, p_page_size integer DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_stream us.carry_case_streams_v1%ROWTYPE;
 v_events jsonb;
 v_last bigint;
 v_next boolean;
BEGIN
 IF p_owner_auth_user_id IS NULL OR p_stream_id IS NULL
    OR p_after_sequence IS NULL OR p_after_sequence < 0
    OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50 THEN
   RAISE EXCEPTION 'Invalid private Carry read request'
     USING ERRCODE='22023';
 END IF;

 SELECT * INTO v_stream FROM us.carry_case_streams_v1 s
 WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_owner_auth_user_id;
 IF v_stream.id IS NULL THEN
  RAISE EXCEPTION 'Private Carry stream unavailable' USING ERRCODE='42501';
 END IF;

 SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'stream_id',e.stream_id::text,
          'stream_sequence',e.stream_sequence,
          'event_schema_version',e.event_schema_version,
          'event_type',e.event_type,
          'payload',e.payload,
          'source_ref',e.source_ref,
          'epistemic_class',e.epistemic_class,
          'effective_on',e.effective_on,
          'recorded_at',e.recorded_at,
          'previous_event_digest',e.previous_event_digest,
          'event_digest',e.event_digest)
        ORDER BY e.stream_sequence),'[]'::jsonb),
        max(e.stream_sequence)
 INTO v_events,v_last
 FROM (
   SELECT ev.* FROM us.carry_case_events_v1 ev
   WHERE ev.stream_id=v_stream.id
     AND ev.owner_auth_user_id=p_owner_auth_user_id
     AND ev.stream_sequence>p_after_sequence
   ORDER BY ev.stream_sequence
   LIMIT p_page_size
 ) e;
 v_last:=coalesce(v_last,p_after_sequence);
 SELECT EXISTS (
   SELECT 1 FROM us.carry_case_events_v1 ev
   WHERE ev.stream_id=v_stream.id
     AND ev.owner_auth_user_id=p_owner_auth_user_id
     AND ev.stream_sequence>v_last
 ) INTO v_next;

 RETURN jsonb_build_object(
   'stream_id',v_stream.id::text,
   'subject_kind',v_stream.subject_kind,
   'after_sequence',p_after_sequence,
   'next_after_sequence',v_last,
   'has_more',v_next,
   'events',v_events);
END $fn$;

REVOKE ALL ON FUNCTION us.carry_read_owned_history_v3(uuid,uuid,bigint,integer)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT USAGE ON SCHEMA us TO us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_read_owned_history_v3(
 uuid,uuid,bigint,integer) TO us_carry_backend;

-- No table SELECT, INSERT or UPDATE; no append, review or adoption privilege.
-- A later separate release must provision a login/credential and authorize
-- each additional operation one by one, never grant blanket schema access.
COMMIT;
