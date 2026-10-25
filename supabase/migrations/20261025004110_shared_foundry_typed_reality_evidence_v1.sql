-- Canonical-source candidate ONLY: no direct production DDL.
-- Foundry stage 1: signed human source/evidence capture with typed, unresolved
-- segments. Deliberately does NOT establish Person, Place, Work, prices,
-- operating knowledge, source permission, or AI carrier access.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.capture_foundry_reality_input_self_api_v1(
  p_workspace_id text,
  p_request_id uuid,
  p_original_text text,
  p_segments jsonb DEFAULT '[]'::jsonb,
  p_source_kind text DEFAULT 'operator_statement',
  p_observed_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $function$
DECLARE
  v_actor uuid := atlas.foundry_current_signed_principal_v1();
  v_workspace foundry.workspace_authority_registry_v1%rowtype;
  v_old foundry.events%rowtype;
  v_sequence bigint;
  v_event_id text;
  v_piece jsonb;
  v_text text;
  v_kind text;
  v_result jsonb;
  v_content text := p_original_text;
BEGIN
  IF p_workspace_id IS NULL OR length(p_workspace_id)>180
     OR p_request_id IS NULL THEN
    RAISE EXCEPTION 'Valid workspace and stable request IDs required' USING ERRCODE='22023';
  END IF;
  IF v_content IS NULL OR length(btrim(v_content))<1
     OR length(v_content)>20000 THEN
    RAISE EXCEPTION 'Original evidence must contain 1 to 20000 characters' USING ERRCODE='22023';
  END IF;
  IF p_source_kind IS NULL OR p_source_kind NOT IN
     ('operator_statement','firsthand_observation','authorized_source_reference') THEN
    RAISE EXCEPTION 'Unsupported source category' USING ERRCODE='22023';
  END IF;
  IF p_segments IS NULL OR jsonb_typeof(p_segments)<>'array'
     OR jsonb_array_length(p_segments)<1
     OR jsonb_array_length(p_segments)>24 THEN
    RAISE EXCEPTION 'Between 1 and 24 typed source segments required' USING ERRCODE='22023';
  END IF;

  -- Actual human owns this provisional workspace; mere Ledger proximity
  -- cannot expose someone else's Foundry evidence.
  SELECT * INTO v_workspace FROM foundry.workspace_authority_registry_v1 w
  WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=v_actor;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501';
  END IF;
  IF v_workspace.revoked_at IS NOT NULL OR v_workspace.suspended_at IS NOT NULL
     OR v_workspace.custody_review_state IN ('revoked','suspended') THEN
    RAISE EXCEPTION 'Workspace cannot accept new evidence' USING ERRCODE='42501';
  END IF;

  FOR v_piece IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
    IF jsonb_typeof(v_piece)<>'object' THEN
      RAISE EXCEPTION 'Each segment must be an object' USING ERRCODE='22023';
    END IF;
    v_text := v_piece->>'text';
    v_kind := v_piece->>'kind';
    IF v_text IS NULL OR length(btrim(v_text))<1
       OR length(v_text)>4000 OR strpos(v_content,v_text)=0 THEN
      RAISE EXCEPTION 'Each segment must quote the preserved original text' USING ERRCODE='22023';
    END IF;
    IF v_kind IS NULL OR v_kind NOT IN
       ('place','recurrence','commercial','operating_instruction',
        'work','observation','relationship','unresolved') THEN
      RAISE EXCEPTION 'Unknown segment interpretation kind' USING ERRCODE='22023';
    END IF;
    -- Unknown or future semantics are always unresolved evidence, never
    -- a user-asserted establishment or unverified foreign source grant.
    IF (v_piece - 'text' - 'kind') <> '{}'::jsonb THEN
      RAISE EXCEPTION 'Only literal segment and suggested kind are admitted' USING ERRCODE='22023';
    END IF;
  END LOOP;

  -- Serialize competing appends with foundry.append_event's own workspace
  -- lock. A browser-supplied request UUID is idempotency, not identity.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace_id,0));
  v_event_id := 'foundry-reality-intake-'||p_request_id::text;
  SELECT * INTO v_old FROM foundry.events WHERE event_id=v_event_id;
  IF FOUND THEN
    IF v_old.workspace_id<>p_workspace_id
      OR v_old.event_type<>'foundry_reality_input_v1'
      OR v_old.envelope->'payload'->>'original_text' IS DISTINCT FROM v_content
      OR v_old.envelope->'payload'->'segments' IS DISTINCT FROM p_segments
      OR v_old.envelope->'payload'->>'source_kind' IS DISTINCT FROM p_source_kind
      OR (v_old.envelope->'payload'->>'observed_at') IS DISTINCT FROM
          to_char(p_observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    THEN
      RAISE EXCEPTION 'Request ID already used for different evidence' USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'replayed',true,
      'entryId',v_old.event_id,'workspaceId',p_workspace_id,
      'sequence',v_old.sequence,'canonicalMutation',false,'aiCarrierAccess',false);
  END IF;

  SELECT coalesce(max(e.sequence),0)+1 INTO v_sequence
  FROM foundry.events e WHERE e.workspace_id=p_workspace_id;

  v_result := foundry.append_event(jsonb_build_object(
    'event_id',v_event_id,'workspace_id',p_workspace_id,
    'event_type','foundry_reality_input_v1',
    'sequence',v_sequence,
    'payload',jsonb_build_object(
      'original_text',v_content,
      'source_kind',p_source_kind,
      'observed_at',to_char(p_observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'segments',p_segments,
      'segment_status','unresolved',
      'subject_label',v_workspace.provisional_subject_label,
      'subject_identity_state',v_workspace.subject_identity_state,
      'author_principal_id',v_actor,
      'author_user_id',auth.uid(),
      'canonical_mutation',false
    ),
    'basis_refs','[]'::jsonb,
    'authority','signed_workspace_owner_unresolved_evidence',
    'actor_kind','human',
    'recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  IF v_result->>'status' <> 'APPENDED' THEN
    RAISE EXCEPTION 'Could not append source evidence' USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('ok',true,'replayed',false,
    'entryId',v_event_id,'workspaceId',p_workspace_id,
    'sequence',v_sequence,'canonicalMutation',false,'aiCarrierAccess',false);
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.list_foundry_reality_inputs_self_api_v1(
  p_workspace_id text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $function$
DECLARE v_actor uuid := atlas.foundry_current_signed_principal_v1();
        v_items jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM foundry.workspace_authority_registry_v1 w
    WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=v_actor
      AND w.revoked_at IS NULL AND w.custody_review_state<>'revoked'
  ) THEN
    RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'entryId',e.event_id,'workspaceId',e.workspace_id,
    'sequence',e.sequence,
    'originalText',e.envelope->'payload'->>'original_text',
    'sourceKind',e.envelope->'payload'->>'source_kind',
    'observedAt',e.envelope->'payload'->>'observed_at',
    'recordedAt',e.envelope->>'recorded_at',
    'segments',e.envelope->'payload'->'segments',
    'segmentStatus','unresolved',
    'subjectLabel',e.envelope->'payload'->>'subject_label',
    'authorPrincipalId',e.envelope->'payload'->>'author_principal_id',
    'canonicalMutation',false
  ) ORDER BY e.sequence),'[]'::jsonb) INTO v_items
  FROM (
    SELECT * FROM foundry.events e
    WHERE e.workspace_id=p_workspace_id
      AND e.event_type='foundry_reality_input_v1'
    ORDER BY e.sequence DESC LIMIT 100
  ) e;
  RETURN jsonb_build_object('ok',true,'workspaceId',p_workspace_id,
    'contractVersion','foundry_reality_input_v1','items',v_items,
    'canonicalMutation',false,'aiCarrierAccess',false);
END;
$function$;

-- Exposed wrappers reuse the internal signed-actor proof. They cannot be
-- called by anon, PUBLIC, or service_role and expose no direct table rights.
CREATE OR REPLACE FUNCTION public.capture_foundry_reality_input_self_api_v1(
 p_workspace_id text,p_request_id uuid,p_original_text text,
 p_segments jsonb DEFAULT '[]'::jsonb,
 p_source_kind text DEFAULT 'operator_statement',
 p_observed_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas','public'
AS $$
 SELECT atlas.capture_foundry_reality_input_self_api_v1($1,$2,$3,$4,$5,$6)
$$;

CREATE OR REPLACE FUNCTION public.list_foundry_reality_inputs_self_api_v1(
 p_workspace_id text
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas','public'
AS $$
 SELECT atlas.list_foundry_reality_inputs_self_api_v1($1)
$$;

REVOKE ALL ON FUNCTION atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.list_foundry_reality_inputs_self_api_v1(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.list_foundry_reality_inputs_self_api_v1(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.list_foundry_reality_inputs_self_api_v1(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_foundry_reality_inputs_self_api_v1(text) TO authenticated;

COMMIT;
