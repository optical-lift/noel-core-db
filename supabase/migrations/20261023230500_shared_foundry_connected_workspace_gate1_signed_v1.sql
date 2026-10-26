-- V3 validation-only, never deploy. Fix function statement termination.
-- Immutable source package for free GitHub protected disposable local clone.
-- Registry -> Foundry workspace target delegation -> human pending preparation.
BEGIN;
-- SOURCE CANDIDATE ONLY: no production release, migration history or data writes.
-- Foundry Connected Workspace Gate 1, reviewed against Noel main
-- 6ebde9a810152be9c5e51c674229df9f1483b004.
-- Keep existing foundry.events and foundry.snapshots, including all five
-- historical workspace streams, untouched. Legacy workspaces are not backfilled.
--
-- This is a private authority registry, NOT a second Person/Principal or
-- agent/delegation system. Delegated agent credentials and command authority
-- remain in atlas.delegated_agent_*.
CREATE TABLE foundry.workspace_authority_registry_v1 (
  workspace_id text PRIMARY KEY
    CHECK (length(btrim(workspace_id)) BETWEEN 1 AND 180),
  creation_request_id uuid NOT NULL,
  owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  protocol_version text NOT NULL DEFAULT '0.1'
    CHECK (protocol_version='0.1'),
  provisional_subject_label text NOT NULL
    CHECK (length(btrim(provisional_subject_label)) BETWEEN 1 AND 500),
  provisional_field text NOT NULL
    CHECK (length(btrim(provisional_field)) BETWEEN 1 AND 2000),
  -- A subject label never establishes or merges a canonical Person.
  -- A verified Person link needs a separate owning-domain identity command.
  subject_identity_state text NOT NULL DEFAULT 'unresolved'
    CHECK (subject_identity_state IN ('unresolved','provisional')),
  custody_scope_kind text NOT NULL
    CHECK (custody_scope_kind IN ('verified_self','documented_external')),
  -- The initial source-custody decision is explicitly pending. It is NOT
  -- authorized merely because the operator knows a name or has an AI transcript.
  custody_review_state text NOT NULL DEFAULT 'pending'
    CHECK (custody_review_state IN ('pending','reviewed','suspended','revoked')),
  custody_basis_refs text[] NOT NULL DEFAULT '{}'::text[],
  custody_reviewed_by_principal_id uuid REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  custody_reviewed_at timestamptz,
  custody_review_method text
    CHECK (custody_review_method IS NULL
      OR custody_review_method IN ('canonical_self','reviewed_source_authorization')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  suspended_at timestamptz,
  revoked_at timestamptz,
  CHECK (
    (custody_review_state='reviewed'
     AND cardinality(custody_basis_refs)>0
     AND custody_reviewed_by_principal_id IS NOT NULL
     AND custody_reviewed_at IS NOT NULL
     AND custody_review_method IS NOT NULL)
    OR
    (custody_review_state<>'reviewed')
  ),
  CHECK (
    (custody_scope_kind='verified_self'
      AND (custody_review_method IS NULL OR custody_review_method='canonical_self'))
    OR
    (custody_scope_kind='documented_external'
      AND (custody_review_method IS NULL OR custody_review_method='reviewed_source_authorization'))
  ),
  UNIQUE (owner_principal_id, creation_request_id),
  CHECK (custody_review_state<>'revoked' OR revoked_at IS NOT NULL),
  CHECK (custody_review_state<>'suspended' OR suspended_at IS NOT NULL)
);

-- Guarding private data at the table boundary is defense in depth.
-- NO direct client grants, public views, AI-written ownership or subject claims.
ALTER TABLE foundry.workspace_authority_registry_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON foundry.workspace_authority_registry_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- Deliberately no INSERT/UPDATE/DELETE public or service RPC, no policies,
-- no command catalog entries, no snapshot rewrites, no workspace backfill,
-- no delegated-agent scope expansion and no Atlas canonical Reality changes.
--
-- Before a guarded registrar/review command may be introduced, source must
-- prove canonical authenticated Principal derivation, subject custody proof,
-- exact workspace target authorization, revocation and safe event append.

-- SOURCE CANDIDATE ONLY. Requires private Foundry registry from PR #2093.
-- No migration release, no production DDL, no user-data mutations.
-- Versioned extension to Atlas's existing delegated-agent command authority.
-- Reuses live v1 evaluator bodies; only Foundry-specific checks are added.
-- Existing Ledger and personal command behavior is otherwise unchanged.
ALTER TABLE atlas.agent_command_definitions
  DROP CONSTRAINT agent_command_definitions_scope_kind_check;
ALTER TABLE atlas.agent_command_definitions
  ADD CONSTRAINT agent_command_definitions_scope_kind_check
  CHECK (scope_kind = ANY (ARRAY[
    'personal'::text,'ledger'::text,'either'::text,'foundry_workspace'::text
  ]));

CREATE OR REPLACE FUNCTION atlas.evaluate_delegated_agent_command_authority_v1(p_authorization_id uuid, p_command_key text, p_command_version integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'atlas', 'ledger', 'public', 'pg_temp'
AS $function$
declare
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_command atlas.agent_command_definitions%rowtype;
  v_carrier atlas.delegated_agent_carriers%rowtype;
  v_principal atlas.principals%rowtype;
  v_seat ledger.seats%rowtype;
  v_reasons jsonb := '[]'::jsonb;
  v_allowed boolean := true;
  v_confirmation_required boolean := false;
begin
  select * into v_auth from atlas.delegated_agent_authorizations where id=p_authorization_id;
  if not found then
    return jsonb_build_object('allowed',false,'reasons',jsonb_build_array('authorization_not_found'));
  end if;

  select * into v_carrier from atlas.delegated_agent_carriers where id=v_auth.carrier_id;
  select * into v_principal from atlas.principals where id=v_auth.principal_id;
  select * into v_command from atlas.agent_command_definitions
  where command_key=p_command_key and command_version=p_command_version;

  if v_carrier.id is null or v_carrier.status<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('carrier_not_active'); end if;
  if v_principal.id is null or v_principal.status<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('principal_not_active'); end if;
  if v_command.command_key is null or v_command.status<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('command_not_active'); end if;
  if v_auth.authorization_state<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('authorization_not_active'); end if;
  if now()<v_auth.begins_at or (v_auth.ends_at is not null and now()>=v_auth.ends_at) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('authorization_outside_time_window'); end if;

  if not (p_command_key = any(v_auth.allowed_command_keys)) then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('command_not_in_explicit_allowlist');
  end if;
  if p_command_key = any(v_auth.denied_command_keys) then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('command_denied');
  end if;
  if v_command.command_key is not null and atlas.execution_class_rank_v1(v_command.execution_class)>atlas.execution_class_rank_v1(v_auth.max_execution_class) then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('execution_class_exceeds_delegation');
  end if;

  if v_auth.ledger_id is not null then
    if not atlas.principal_has_ledger_authority_v1(v_auth.principal_id,v_auth.ledger_id) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('principal_lacks_ledger_authority'); end if;
    if v_command.command_key is not null and v_command.scope_kind='personal' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('personal_command_cannot_use_ledger_delegation'); end if;
    if v_command.command_key is not null and v_command.scope_kind='foundry_workspace' then
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_command_cannot_use_ledger_delegation');
    end if;
  elsif v_command.command_key is not null and v_command.scope_kind='ledger' then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('ledger_command_requires_ledger_delegation');
  end if;

  if v_auth.delegating_seat_id is not null then
    select * into v_seat from ledger.seats where id=v_auth.delegating_seat_id;
    if v_seat.id is null or v_seat.seat_state<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('delegating_seat_not_active');
    elsif v_auth.ledger_id is null or v_seat.ledger_id<>v_auth.ledger_id then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('delegating_seat_ledger_mismatch');
    elsif v_principal.person_id is not null and v_seat.person_entity_id<>v_principal.person_id then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('delegating_seat_not_held_by_principal'); end if;
  end if;

  if v_command.capability_key is not null then
    if not atlas.capability_definition_active_v1(v_command.capability_key,v_command.capability_version) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('required_capability_not_active');
    elsif v_auth.ledger_id is not null and not atlas.capability_entitlement_grant_live_v1(v_auth.ledger_id,v_command.capability_key,v_command.capability_version) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('ledger_not_entitled_for_capability'); end if;
  end if;

  v_confirmation_required:=v_command.command_key is not null and v_command.confirmation_requirement='principal_explicit';

  return jsonb_build_object(
    'allowed',v_allowed,
    'reasons',v_reasons,
    'authorizationId',v_auth.id,
    'carrierId',v_auth.carrier_id,
    'principalId',v_auth.principal_id,
    'ledgerId',v_auth.ledger_id,
    'delegatingSeatId',v_auth.delegating_seat_id,
    'commandKey',p_command_key,
    'commandVersion',p_command_version,
    'executionClass',v_command.execution_class,
    'confirmationRequired',v_confirmation_required,
    'handlerKey',v_command.handler_key,
    'scope',v_auth.scope,
    'authoritySource','delegated_agent_authorization_v1'
  );
end;
$function$;


CREATE OR REPLACE FUNCTION atlas.evaluate_delegated_agent_command_target_authority_v1(p_authorization_id uuid, p_command_key text, p_command_version integer, p_target jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'atlas', 'ledger', 'public', 'pg_temp'
AS $function$
declare
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_command atlas.agent_command_definitions%rowtype;
  v_base jsonb;
  v_allowed boolean;
  v_reasons jsonb;
  v_confirmation_required boolean;
  v_target_kind text := nullif(btrim(coalesce(p_target->>'kind','')), '');
  v_target_id text := nullif(btrim(coalesce(p_target->>'id','')), '');
  v_expected_kind text;
  v_force_all_commits boolean := false;
begin
  v_base := atlas.evaluate_delegated_agent_command_authority_v1(
    p_authorization_id,
    p_command_key,
    p_command_version
  );

  if not coalesce(v_base ? 'authorizationId', false) then
    return v_base;
  end if;

  select * into v_auth
  from atlas.delegated_agent_authorizations
  where id = p_authorization_id;

  select * into v_command
  from atlas.agent_command_definitions
  where command_key = p_command_key
    and command_version = p_command_version;

  v_allowed := coalesce((v_base->>'allowed')::boolean,false);
  v_reasons := coalesce(v_base->'reasons','[]'::jsonb);
  v_confirmation_required := coalesce((v_base->>'confirmationRequired')::boolean,false);
  v_expected_kind := nullif(btrim(coalesce(v_command.target_contract->>'kind','')), '');

  if v_target_kind is null then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('target_kind_required');
  end if;

  if v_target_id is null then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('target_id_required');
  end if;

  if v_expected_kind is not null
     and v_target_kind is distinct from v_expected_kind then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('target_kind_does_not_match_command_contract');
  end if;

  if v_auth.scope ? 'targetKinds' then
    if v_target_kind is null
       or not ((v_auth.scope->'targetKinds') ? v_target_kind) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('target_kind_outside_delegated_scope');
    end if;
  end if;

  if v_auth.scope ? 'targetIds' then
    if v_target_id is null
       or not ((v_auth.scope->'targetIds') ? v_target_id) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('target_id_outside_delegated_scope');
    end if;
  end if;

  v_force_all_commits := coalesce((v_auth.confirmation_policy->>'forceAllCommits')::boolean,false);
  if v_force_all_commits
     and coalesce(v_base->>'executionClass','') = 'commit' then
    v_confirmation_required := true;
  end if;

  if v_auth.confirmation_policy ? 'forceConfirmationCommandKeys'
     and (v_auth.confirmation_policy->'forceConfirmationCommandKeys') ? p_command_key then
    v_confirmation_required := true;
  end if;

  -- A non-Foundry command cannot tunnel through a generic target contract
  -- to a Foundry workspace just because an agent chooses that target kind.
  IF v_target_kind='foundry_workspace'
     AND v_command.scope_kind IS DISTINCT FROM 'foundry_workspace' THEN
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('non_foundry_command_cannot_target_workspace');
  END IF;

  -- Foundry is neither a Ledger nor a Personal Atlas command.
  -- A JSON target allowlist alone cannot establish Foundry jurisdiction.
  IF v_command.scope_kind='foundry_workspace' THEN
    IF v_target_kind IS DISTINCT FROM 'foundry_workspace'
       OR v_expected_kind IS DISTINCT FROM 'foundry_workspace' THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_target_kind_required');
    END IF;

    IF v_auth.ledger_id IS NOT NULL OR v_auth.delegating_seat_id IS NOT NULL THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_requires_pre_ledger_delegation');
    END IF;

    -- Require a literal workspace target in BOTH scope allowlists.
    -- Caller control of these arrays does not suffice; the private registry
    -- ownership and current source-custody review below are also mandatory.
    IF jsonb_typeof(v_auth.scope->'targetKinds') IS DISTINCT FROM 'array'
       OR NOT COALESCE((v_auth.scope->'targetKinds') ? 'foundry_workspace',false)
       OR jsonb_typeof(v_auth.scope->'targetIds') IS DISTINCT FROM 'array'
       OR NOT COALESCE((v_auth.scope->'targetIds') ? v_target_id,false) THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_workspace_not_explicitly_delegated');
    END IF;

    IF v_target_id IS NULL OR NOT EXISTS (
      SELECT 1
      FROM foundry.workspace_authority_registry_v1 w
      WHERE w.workspace_id=v_target_id
        AND w.owner_principal_id=v_auth.principal_id
        AND w.protocol_version='0.1'
        AND w.custody_review_state='reviewed'
        AND w.custody_reviewed_by_principal_id IS NOT NULL
        AND w.custody_reviewed_at IS NOT NULL
        AND cardinality(w.custody_basis_refs)>0
        AND w.suspended_at IS NULL
        AND w.revoked_at IS NULL
    ) THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_workspace_custody_not_authorized');
    END IF;
  END IF;

  return v_base || jsonb_build_object(
    'allowed',v_allowed,
    'reasons',v_reasons,
    'confirmationRequired',v_confirmation_required,
    'target',coalesce(p_target,'{}'::jsonb),
    'targetExpectedKind',v_expected_kind,
    'targetScopeEvaluated',true
  );
end;
$function$;


-- No Foundry commands are activated in this gate. Do not add a broad
-- allowlist, API/SQL invocation route, or direct table access.
-- The existing agent command executor remains the sole command bridge.
-- Source-custody state changes require a separately authorized human command.
-- SOURCE-ONLY: protected Foundry workspace preparation (no subject authority).
-- Depends on private workspace_authority_registry_v1 (PR #2093).
-- Not a production migration; test on disposable schema clone first.
-- Does NOT activate carrier delegation, external-subject custody, or Atlas Reality.
CREATE OR REPLACE FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  p_request_id uuid,
  p_subject_label text,
  p_provisional_field text,
  p_custody_scope_kind text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE
  v_actor_user_id uuid := auth.uid();
  v_owner atlas.principals%rowtype;
  v_auth_user auth.users%rowtype;
  v_session_id uuid;
  v_label text := NULLIF(BTRIM(p_subject_label),'');
  v_field text := NULLIF(BTRIM(p_provisional_field),'');
  v_existing foundry.workspace_authority_registry_v1%rowtype;
  v_workspace_id text;
  v_event_id text;
  v_append jsonb;
BEGIN
  IF v_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'verified Atlas sign-in required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_auth_user FROM auth.users WHERE id=v_actor_user_id;
  IF NOT FOUND OR v_auth_user.is_anonymous
     OR (v_auth_user.banned_until IS NOT NULL AND v_auth_user.banned_until>now())
  THEN
    RAISE EXCEPTION 'active non-anonymous verified Atlas authentication required' USING ERRCODE='42501';
  END IF;

  -- A genuine signed JWT must reference an active GoTrue session, and
  -- deleting that session must revoke this operation immediately even
  -- while the JWT itself has not yet expired.
  BEGIN
    v_session_id := NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'valid GoTrue signed session required' USING ERRCODE='42501';
  END;
  IF v_session_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions sess
    WHERE sess.id=v_session_id
      AND sess.user_id=v_actor_user_id
      AND (sess.not_after IS NULL OR sess.not_after>now())
  ) THEN
    RAISE EXCEPTION 'active GoTrue session required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_owner FROM atlas.principals
    WHERE user_id=v_actor_user_id AND status='active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active Atlas Principal required' USING ERRCODE='42501';
  END IF;

  IF p_request_id IS NULL THEN RAISE EXCEPTION 'stable request ID required'; END IF;
  IF v_label IS NULL OR length(v_label)>500 THEN
    RAISE EXCEPTION 'provisional subject label required within bounds';
  END IF;
  IF v_field IS NULL OR length(v_field)>2000 THEN
    RAISE EXCEPTION 'provisional field required within bounds';
  END IF;
  IF p_custody_scope_kind NOT IN ('verified_self','documented_external')
    OR p_custody_scope_kind IS NULL THEN
    RAISE EXCEPTION 'invalid requested source-custody classification';
  END IF;

  -- Serialize one human's same idempotent preparation request. A client
  -- can choose the request ID, never the owner Principal or workspace ID.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'foundry-prepare:'||v_owner.id::text||':'||p_request_id::text, 0
  ));

  SELECT * INTO v_existing FROM foundry.workspace_authority_registry_v1
    WHERE owner_principal_id=v_owner.id
      AND creation_request_id=p_request_id
    FOR UPDATE;
  IF FOUND THEN
    IF v_existing.provisional_subject_label IS DISTINCT FROM v_label
       OR v_existing.provisional_field IS DISTINCT FROM v_field
       OR v_existing.custody_scope_kind IS DISTINCT FROM p_custody_scope_kind THEN
      RAISE EXCEPTION 'request ID already used for different Foundry preparation';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'replayed',true,
      'workspaceId',v_existing.workspace_id,
      'custodyReviewState',v_existing.custody_review_state,
      'subjectIdentityState',v_existing.subject_identity_state,
      'canonicalAtlasMutation',false
    );
  END IF;

  v_workspace_id := 'foundry-' || gen_random_uuid()::text;
  v_event_id := 'foundry-event-' || gen_random_uuid()::text;

  INSERT INTO foundry.workspace_authority_registry_v1(
    workspace_id,creation_request_id,owner_principal_id,
    provisional_subject_label,provisional_field,
    subject_identity_state,custody_scope_kind,custody_review_state,
    custody_basis_refs,created_by_principal_id
  ) VALUES(
    v_workspace_id,p_request_id,v_owner.id,
    v_label,v_field,'unresolved',p_custody_scope_kind,
    'pending','{}'::text[],v_owner.id
  );

  -- Append and registry INSERT run in the same transaction.
  -- This is a provisional operator claim, NOT verified testimony or
  -- permission to access or act on the subject's private records.
  v_append := foundry.append_event(jsonb_build_object(
    'event_id',v_event_id,
    'workspace_id',v_workspace_id,
    'event_type','WORKSPACE_CREATED',
    'sequence',1,
    'payload',jsonb_build_object(
      'status','DISCOVERY',
      'owner_principal_id',v_owner.id,
      'provisional_subject',jsonb_build_object(
        'label',v_label,'subject_ref',NULL,'subject_kind',NULL
      ),
      'provisional_field',v_field,
      'boundary_status','UNRESOLVED',
      'custody_review_state','pending',
      'subject_identity_state','unresolved'
    ),
    'basis_refs','[]'::jsonb,
    'authority','authenticated_owner_preparation_only',
    'actor_kind','human',
    'recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC',
                         'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));

  IF v_append->>'status' IS DISTINCT FROM 'APPENDED' THEN
    RAISE EXCEPTION 'Foundry workspace initial event was not appended';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'replayed',false,
    'workspaceId',v_workspace_id,
    'custodyReviewState','pending',
    'subjectIdentityState','unresolved',
    'canonicalAtlasMutation',false
  );
END;
$fn$;

-- Self API authorizes only the authenticated, non-anonymous human owner
-- to create a PENDING custody container. It cannot approve third-party
-- consent, bind a canonical Person, or delegate an AI agent.
REVOKE ALL ON FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  uuid,text,text,text
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  uuid,text,text,text
) TO authenticated;

-- Narrow owner-only read of an unreviewed workspace's preparation state.
-- Does not expose testimony, source documents, candidate interpretation,
-- any legacy stream, or a claim that the subject has granted authority.
CREATE OR REPLACE FUNCTION atlas.get_foundry_workspace_preparation_self_api_v1(
  p_workspace_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'atlas','foundry','auth','pg_temp'
AS $read$
DECLARE
  v_user_id uuid:=auth.uid();
  v_session_id uuid;
  v_principal_id uuid;
  v_workspace foundry.workspace_authority_registry_v1%rowtype;
BEGIN
  IF v_user_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM auth.users u
    WHERE u.id=v_user_id AND u.is_anonymous=false
      AND (u.banned_until IS NULL OR u.banned_until<=now())
  ) THEN
    RAISE EXCEPTION 'verified human sign-in required' USING ERRCODE='42501';
  END IF;
  BEGIN
    v_session_id:=NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'valid GoTrue signed session required' USING ERRCODE='42501';
  END;
  IF v_session_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM auth.sessions s
    WHERE s.id=v_session_id AND s.user_id=v_user_id
      AND (s.not_after IS NULL OR s.not_after>now())
  ) THEN
    RAISE EXCEPTION 'active GoTrue session required' USING ERRCODE='42501';
  END IF;
  SELECT p.id INTO v_principal_id FROM atlas.principals p
    WHERE p.user_id=v_user_id AND p.status='active';
  IF v_principal_id IS NULL THEN
    RAISE EXCEPTION 'active Atlas Principal required' USING ERRCODE='42501';
  END IF;
  IF NULLIF(BTRIM(p_workspace_id),'') IS NULL THEN
    RAISE EXCEPTION 'workspace ID required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_workspace
  FROM foundry.workspace_authority_registry_v1 w
  WHERE w.workspace_id=p_workspace_id
    AND w.owner_principal_id=v_principal_id;
  IF NOT FOUND THEN
    -- Foreign workspace IDs are indistinguishable from nonexistent IDs.
    RAISE EXCEPTION 'workspace not accessible' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'workspaceId',v_workspace.workspace_id,
    'custodyReviewState',v_workspace.custody_review_state,
    'subjectIdentityState',v_workspace.subject_identity_state,
    'provisionalSubjectLabel',v_workspace.provisional_subject_label,
    'provisionalField',v_workspace.provisional_field,
    'protocolVersion',v_workspace.protocol_version,
    'canonicalAtlasMutation',false
  );
END;
$read$;
REVOKE ALL ON FUNCTION atlas.get_foundry_workspace_preparation_self_api_v1(
  text
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.get_foundry_workspace_preparation_self_api_v1(
  text
) TO authenticated;
COMMIT;
