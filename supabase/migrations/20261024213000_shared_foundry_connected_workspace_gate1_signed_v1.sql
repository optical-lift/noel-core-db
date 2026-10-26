-- SOURCE ONLY: retire alternative membership-derived Foundry Person authority.
BEGIN;

-- Native Person connection proves relationship only; not an employee,
-- consultant, subscription, or blanket Ledger content-read grant.
CREATE OR REPLACE FUNCTION atlas.persons_share_active_native_ledger_v1(
  p_first_person_id uuid,p_second_person_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT p_first_person_id IS NOT NULL AND p_second_person_id IS NOT NULL
 AND p_first_person_id<>p_second_person_id AND EXISTS(
  SELECT 1 FROM ledger.seats first_seat
  JOIN ledger.seats second_seat ON second_seat.ledger_id=first_seat.ledger_id
    AND second_seat.person_entity_id=p_second_person_id
    AND second_seat.seat_state='active' AND second_seat.ended_at IS NULL
  JOIN reality.entities first_person ON first_person.id=first_seat.person_entity_id
    AND first_person.entity_kind='person' AND first_person.identity_state='canonical'
  JOIN reality.entities second_person ON second_person.id=second_seat.person_entity_id
    AND second_person.entity_kind='person' AND second_person.identity_state='canonical'
  JOIN ledger.ledgers native_ledger ON native_ledger.id=first_seat.ledger_id
    AND native_ledger.ledger_state='active' AND native_ledger.retired_at IS NULL
  JOIN atlas.ledgers atlas_ledger ON atlas_ledger.id=native_ledger.id
    AND atlas_ledger.status='active'
  WHERE first_seat.person_entity_id=p_first_person_id
    AND first_seat.seat_state='active' AND first_seat.ended_at IS NULL
 );
$fn$;
REVOKE ALL ON FUNCTION atlas.persons_share_active_native_ledger_v1(uuid,uuid)
FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.list_foundry_source_custody_reviewers_self_api_v1(p_workspace_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'foundry', 'auth', 'pg_temp'
AS $function$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_items jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM foundry.workspace_authority_registry_v1 w
    WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=v_actor
      AND w.custody_review_state='pending'
      AND w.revoked_at IS NULL AND w.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Workspace inaccessible for human custody review'
      USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'principalId',r.id,'canonicalPersonId',r.person_id,
    'displayName',r.name,'readiness','signed_human_reviewer'
  ) ORDER BY r.name,r.id),'[]'::jsonb) INTO v_items
  FROM (
    SELECT DISTINCT p.id,p.person_id,p.name
    FROM atlas.principals operator
    JOIN atlas.principals p ON p.id<>operator.id AND p.status='active'
    JOIN auth.users au ON au.id=p.user_id
      AND au.is_anonymous=false
      AND (au.banned_until IS NULL OR au.banned_until<=now())
    WHERE operator.id=v_actor AND operator.status='active'
      AND atlas.persons_share_active_native_ledger_v1(operator.person_id,p.person_id)
  ) r;
  RETURN jsonb_build_object('ok',true,'workspaceId',p_workspace_id,
    'reviewers',v_items,'selectionBasis','shared_active_canonical_ledger_connection',
    'aiCarrierAccess',false);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(p_workspace_id text, p_request_id uuid, p_reviewer_principal_id uuid, p_claim_basis_kind text, p_source_refs text[], p_permitted_human_actions text[], p_scope_description text, p_claimed_authority_basis text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'foundry', 'auth', 'pg_temp'
AS $function$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_ws foundry.workspace_authority_registry_v1%rowtype;
        v_existing foundry.source_custody_review_cases_v1%rowtype;
        v_case_id uuid;
        v_seq bigint;
        v_source text;
BEGIN
  IF p_request_id IS NULL OR p_reviewer_principal_id IS NULL
     OR NULLIF(btrim(p_workspace_id),'') IS NULL THEN
    RAISE EXCEPTION 'Workspace, stable request, and human reviewer required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_ws FROM foundry.workspace_authority_registry_v1
   WHERE workspace_id=p_workspace_id AND owner_principal_id=v_actor
   FOR UPDATE;
  IF NOT FOUND OR v_ws.custody_review_state<>'pending'
    OR v_ws.revoked_at IS NOT NULL OR v_ws.suspended_at IS NOT NULL THEN
    RAISE EXCEPTION 'Workspace inaccessible or not in pending human custody' USING ERRCODE='42501';
  END IF;
  IF p_reviewer_principal_id=v_actor OR NOT EXISTS (
    SELECT 1 FROM atlas.principals p
    WHERE p.id=p_reviewer_principal_id AND p.status='active'
      AND p.user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A distinct active human reviewer is required' USING ERRCODE='22023';
  END IF;
  -- The writer independently verifies canonical Ledger participation;
  -- browser-selected Principal IDs and organization membership give no grant.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.principals operator
    JOIN atlas.principals reviewer ON reviewer.id=p_reviewer_principal_id
      AND reviewer.status='active'
    JOIN auth.users reviewer_user ON reviewer_user.id=reviewer.user_id
      AND reviewer_user.is_anonymous=false
      AND (reviewer_user.banned_until IS NULL OR reviewer_user.banned_until<=now())
    WHERE operator.id=v_actor AND operator.status='active'
      AND atlas.persons_share_active_native_ledger_v1(
        operator.person_id,reviewer.person_id)
  ) THEN
    RAISE EXCEPTION 'Reviewer lacks a verified canonical Person-to-Ledger connection'
      USING ERRCODE='42501';
  END IF;
  IF p_claim_basis_kind IS NULL OR p_claim_basis_kind NOT IN (
      'first_party','public_source','subject_authorization','custodian_authorization')
     OR coalesce(cardinality(p_source_refs),0) NOT BETWEEN 1 AND 12
     OR coalesce(cardinality(p_permitted_human_actions),0) NOT BETWEEN 1 AND 4
     OR p_permitted_human_actions <@ ARRAY['catalog','preserve','transcribe','analyze']::text[] IS NOT TRUE
     OR NULLIF(btrim(p_scope_description),'') IS NULL
     OR length(btrim(p_scope_description)) NOT BETWEEN 15 AND 2000
     OR NULLIF(btrim(p_claimed_authority_basis),'') IS NULL
     OR length(btrim(p_claimed_authority_basis)) NOT BETWEEN 20 AND 3000
  THEN RAISE EXCEPTION 'Precise source scope and basis required' USING ERRCODE='22023'; END IF;
  FOREACH v_source IN ARRAY p_source_refs LOOP
    IF v_source IS NULL OR length(btrim(v_source)) NOT BETWEEN 3 AND 300
    THEN RAISE EXCEPTION 'Every source reference must be bounded and nonempty' USING ERRCODE='22023'; END IF;
  END LOOP;

  -- Serializes retries and Foundry sequence against existing append_event lock.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace_id,0));
  SELECT * INTO v_existing FROM foundry.source_custody_review_cases_v1
    WHERE owner_principal_id=v_actor AND request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.workspace_id IS DISTINCT FROM p_workspace_id
      OR v_existing.reviewer_principal_id IS DISTINCT FROM p_reviewer_principal_id
      OR v_existing.claim_basis_kind IS DISTINCT FROM p_claim_basis_kind
      OR v_existing.source_refs IS DISTINCT FROM p_source_refs
      OR v_existing.permitted_human_actions IS DISTINCT FROM p_permitted_human_actions
      OR v_existing.scope_description IS DISTINCT FROM btrim(p_scope_description)
      OR v_existing.claimed_authority_basis IS DISTINCT FROM btrim(p_claimed_authority_basis)
    THEN RAISE EXCEPTION 'Changed payload for previously used source-custody request' USING ERRCODE='22023'; END IF;
    RETURN jsonb_build_object('ok',true,'caseId',v_existing.case_id,
      'reviewState',v_existing.review_state,'replayed',true,'aiCarrierAccess',false);
  END IF;
  INSERT INTO foundry.source_custody_review_cases_v1(
    workspace_id,request_id,owner_principal_id,reviewer_principal_id,
    claim_basis_kind,source_refs,permitted_human_actions,
    scope_description,claimed_authority_basis
  ) VALUES(
    p_workspace_id,p_request_id,v_actor,p_reviewer_principal_id,
    p_claim_basis_kind,p_source_refs,p_permitted_human_actions,
    btrim(p_scope_description),btrim(p_claimed_authority_basis)
  ) RETURNING case_id INTO v_case_id;

  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=p_workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',p_workspace_id,'event_type','SOURCE_CUSTODY_REVIEW_REQUESTED',
    'sequence',v_seq,'payload',jsonb_build_object(
      'case_id',v_case_id,'scope_description',btrim(p_scope_description),
      'source_refs',to_jsonb(p_source_refs),'permitted_human_actions',to_jsonb(p_permitted_human_actions),
      'claimed_authority_basis',btrim(p_claimed_authority_basis),'claim_basis_kind',p_claim_basis_kind,'review_state','pending',
      'ai_carrier_access',false),
    'basis_refs',to_jsonb(p_source_refs),
    'authority','authenticated_owner_attestation_unreviewed',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',v_case_id,
    'reviewState','pending','replayed',false,'aiCarrierAccess',false);
END
$function$;

-- Schema-clone restores can rehydrate default PUBLIC EXECUTE on RPC wrappers.
-- Reassert the public-to-private membrane whenever source-review functions
-- are redefined. Never permit anon or service_role invocation here.
REVOKE ALL ON FUNCTION public.list_foundry_source_custody_reviewers_self_api_v1(text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.list_foundry_source_custody_reviewers_self_api_v1(text)
 TO authenticated;
REVOKE ALL ON FUNCTION public.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)
 TO authenticated;
COMMIT;
