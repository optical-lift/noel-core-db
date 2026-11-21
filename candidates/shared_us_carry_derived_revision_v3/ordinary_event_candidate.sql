-- HELD Us Carry v3 increment B: owner-checked ordinary event entrypoint.
-- Requires finance + Carry v1 + dated v2 + v3 privilege floor in that order.
-- Source candidate only. NEVER release without derived-adoption writer,
-- final read path and updated private FastAPI adapter.
BEGIN;

CREATE FUNCTION us.carry_append_ordinary_event_v3(
  p_owner_auth_user_id uuid,
  p_stream_id uuid,
  p_action_key text,
  p_event_type text,
  p_effective_on date,
  p_epistemic_class text,
  p_source_ref text,
  p_payload jsonb,
  p_expected_sequence bigint DEFAULT NULL
)
RETURNS TABLE(event_id uuid,event_sequence bigint,digest text,replayed boolean)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
  v_owner uuid;
BEGIN
  -- The trusted Us server MUST first authenticate the bearer through GoTrue
  -- and bind p_owner_auth_user_id to the verified server-side user ID.
  -- It must never accept this owner value from a request body or JWT metadata.
  IF p_owner_auth_user_id IS NULL OR p_stream_id IS NULL THEN
    RAISE EXCEPTION 'Private Carry stream unavailable' USING ERRCODE='42501';
  END IF;

  -- Not even a privileged app role may request an ordinary event that seals
  -- a caller-populated revision. The sole derived-adoption writer is separate.
  IF p_event_type IS NULL OR p_event_type='REVISION_SEALED' THEN
    RAISE EXCEPTION 'Revision sealing requires derived adoption'
      USING ERRCODE='42501';
  END IF;

  SELECT s.owner_auth_user_id INTO v_owner
  FROM us.carry_case_streams_v1 s
  WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_owner_auth_user_id
  FOR UPDATE;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Private Carry stream unavailable' USING ERRCODE='42501';
  END IF;

  -- Reuse the existing v1 immutable event, idempotency, ordering and
  -- dated-v2 admission rules. No direct service_role access to v1 is needed.
  RETURN QUERY SELECT a.event_id,a.event_sequence,a.digest,a.replayed
    FROM us.carry_append_event_v1(
      p_stream_id,p_action_key,p_event_type,p_effective_on,
      p_epistemic_class,p_source_ref,p_payload,p_expected_sequence
    ) a;
END;
$fn$;

REVOKE ALL ON FUNCTION us.carry_append_ordinary_event_v3(
  uuid,uuid,text,text,date,text,text,jsonb,bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION us.carry_append_ordinary_event_v3(
  uuid,uuid,text,text,date,text,text,jsonb,bigint)
  TO service_role;
COMMIT;
