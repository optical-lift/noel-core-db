-- HOLD: source-owned, governor-only Work field decisions for native Ledger Persons.
-- Noel #2255 / draft #2263. This is NOT a deployable migration.
-- Install as a single component on a protected full-schema clone ONLY;
-- run before candidate.sql (governor review) and signed acceptance tests.
-- No employee-seat or organization-membership grants, crop/bed joins,
-- source records, existing Work or historical result records are changed.
--
-- Invariant: native Ledger Seat + original Work assignment + verified exact
-- Work->Ledger relevance are required, but NOT sufficient to show a field.
-- A signed root governor explicitly approves the current field VALUE by hash.
-- Source updates, scope withdrawal, terminal revocation or GoTrue logout
-- immediately prevent further reading; no cached field snapshots.
BEGIN;

CREATE TABLE atlas.connected_person_work_field_decision_events_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE,
  ledger_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  work_item_id uuid NOT NULL,
  recipient_person_entity_id uuid NOT NULL,
  field_key text NOT NULL CHECK (field_key IN ('title','instructions')),
  decision text NOT NULL CHECK (decision IN ('allow','deny')),
  approved_value_sha256 text,
  valid_until timestamptz,
  governor_principal_id uuid NOT NULL,
  governor_auth_user_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 12 AND 1200),
  decided_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CONSTRAINT exact_work_field_positive_fingerprint
    CHECK (
      (decision='allow' AND approved_value_sha256 ~ '^[0-9a-f]{64}$')
      OR
      (decision='deny' AND approved_value_sha256 IS NULL AND valid_until IS NULL)
    ),
  CONSTRAINT future_approved_work_field_expiry
    CHECK (decision<>'allow' OR valid_until IS NULL OR valid_until>decided_at)
);
CREATE INDEX connected_person_work_field_decisions_latest_v1
ON atlas.connected_person_work_field_decision_events_v1
(ledger_id,organization_id,recipient_person_entity_id,work_item_id,field_key,
 decided_at DESC,id DESC);
ALTER TABLE atlas.connected_person_work_field_decision_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.connected_person_work_field_decision_events_v1
  FROM PUBLIC,anon,authenticated;

-- Explicit authority predicate used for BOTH deciding and reading.
-- This does not rely on the legacy organization membership or the
-- existence of a native Ledger Seat alone.
CREATE OR REPLACE FUNCTION atlas.connected_person_work_field_source_eligible_v1(
 p_ledger_id uuid,p_work_item_id uuid,p_person_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $eligible$
 SELECT EXISTS (
  SELECT 1
  FROM atlas.work_items w
  JOIN atlas.work_allocations a
    ON a.work_item_id=w.id AND a.organization_id=w.organization_id
  WHERE w.id=p_work_item_id
    AND w.work_state IN ('open','completed')
    AND a.assignee_canonical_person_id=p_person_id
    AND a.assignee_membership_id IS NULL
    AND a.allocation_role='responsible'
    AND (a.state='active' AND w.work_state='open'
      OR a.state='completed' AND w.work_state='completed')
    AND a.establishment_basis_kind IN
      ('person_connection_receiver_uptake',
       'delegated_under_standing_scope',
       'ledger_connection_direct_assignment')
    AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    AND atlas.person_has_native_ledger_connection_v1(
      w.organization_id,p_ledger_id,p_person_id)
    AND EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=w.id
        AND rel.organization_id=w.organization_id
        AND rel.ledger_id=p_ledger_id
        AND rel.attribution_state='active'
        AND (
          rel.evidence_kind IN ('owner_attested','participant_attested')
          OR (rel.evidence_kind='source_verified' AND EXISTS (
            SELECT 1
            FROM atlas.company_work_native_ledger_exact_source_v1(
              w.id,p_ledger_id) proof
            WHERE proof.source_schema=rel.source_schema
              AND proof.source_table=rel.source_table
              AND proof.source_id=rel.source_id
          ))
        )
    )
 )
$eligible$;
REVOKE ALL ON FUNCTION
 atlas.connected_person_work_field_source_eligible_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated;

-- Private source predicate used by existing My Work, Today and dated
-- Work readers. This is not a broad Ledger read or a presentation check.
CREATE OR REPLACE FUNCTION atlas.connected_person_work_field_currently_approved_v1(
 p_ledger_id uuid,p_work_item_id uuid,p_person_id uuid,p_field_key text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $approved$
 SELECT EXISTS (
  SELECT 1
  FROM atlas.connected_person_work_field_decision_events_v1 d
  JOIN atlas.work_items w ON w.id=d.work_item_id
    AND w.organization_id=d.organization_id
  WHERE d.ledger_id=p_ledger_id
    AND d.work_item_id=p_work_item_id
    AND d.recipient_person_entity_id=p_person_id
    AND d.field_key=p_field_key
    AND d.decision='allow'
    AND (d.valid_until IS NULL OR d.valid_until>statement_timestamp())
    AND d.id=(
      SELECT e.id
      FROM atlas.connected_person_work_field_decision_events_v1 e
      WHERE e.ledger_id=d.ledger_id AND e.organization_id=d.organization_id
        AND e.work_item_id=d.work_item_id
        AND e.recipient_person_entity_id=d.recipient_person_entity_id
        AND e.field_key=d.field_key
      ORDER BY e.decided_at DESC,e.id DESC LIMIT 1
    )
    AND d.approved_value_sha256=pg_catalog.encode(pg_catalog.sha256(
      pg_catalog.convert_to(
        CASE p_field_key
          WHEN 'title' THEN w.title
          WHEN 'instructions' THEN w.instructions END,
        'UTF8')),'hex')
    AND atlas.connected_person_work_field_source_eligible_v1(
      p_ledger_id,p_work_item_id,p_person_id)
 )
$approved$;
REVOKE ALL ON FUNCTION
 atlas.connected_person_work_field_currently_approved_v1(uuid,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated;

-- Signed native root-governor decision. All approvals are exact-field,
-- exact-source-hash and exact recipient. Denial appends a revocation
-- event that takes precedence over an older approval. No text snapshots.
CREATE OR REPLACE FUNCTION atlas.governor_decide_connected_person_work_field_self_api_v1(
 p_ledger_id uuid,p_work_item_id uuid,p_person_entity_id uuid,
 p_field_key text,p_decision text,p_reason text,
 p_request_id uuid,p_expected_value_sha256 text DEFAULT NULL,
 p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $decide$
DECLARE
 v_access jsonb;
 v_governor uuid;
 v_org uuid;
 v_field_value text;
 v_hash text;
 v_event atlas.connected_person_work_field_decision_events_v1%rowtype;
 v_existing atlas.connected_person_work_field_decision_events_v1%rowtype;
BEGIN
 IF auth.uid() IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL
   OR p_person_entity_id IS NULL OR p_request_id IS NULL
   OR p_field_key IS NULL OR p_field_key NOT IN ('title','instructions')
   OR p_decision IS NULL OR p_decision NOT IN ('allow','deny')
   OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1200
   OR (p_decision='deny' AND (p_valid_until IS NOT NULL OR
       p_expected_value_sha256 IS NOT NULL))
   OR (p_decision='allow' AND (p_expected_value_sha256 IS NULL OR
       p_expected_value_sha256 !~ '^[0-9a-f]{64}$'))
   OR (p_decision='allow' AND p_valid_until IS NOT NULL
       AND p_valid_until<=statement_timestamp())
 THEN
  RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 v_access:=atlas.reality_access_self_api_v1();
 v_governor:=atlas.current_principal_id_v1();
 IF v_access->>'state' IS DISTINCT FROM 'ready'
   OR v_access->>'authenticated' IS DISTINCT FROM 'true'
   OR v_access->'person'->>'id'
      IS DISTINCT FROM atlas.current_person_id_v1()::text
   OR v_governor IS NULL
   OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
        v_governor,p_ledger_id),false)
 THEN
   RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 -- Prevent two signed governors racing grants/revocations of the same field
 -- or a reused request_id being replayed into an altered permission.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.native_work_field:'||p_ledger_id::text||':'||
   p_person_entity_id::text||':'||p_work_item_id::text||':'||p_field_key,0));
 SELECT * INTO v_existing
 FROM atlas.connected_person_work_field_decision_events_v1 e
 WHERE e.request_id=p_request_id;
 IF FOUND THEN
   IF v_existing.ledger_id=p_ledger_id
    AND v_existing.work_item_id=p_work_item_id
    AND v_existing.recipient_person_entity_id=p_person_entity_id
    AND v_existing.field_key=p_field_key
    AND v_existing.decision=p_decision
    AND v_existing.reason=p_reason
    AND v_existing.valid_until IS NOT DISTINCT FROM p_valid_until
    AND v_existing.approved_value_sha256 IS NOT DISTINCT FROM p_expected_value_sha256
    AND v_existing.governor_principal_id=v_governor
   THEN
     RETURN jsonb_build_object('ok',true,
       'contractVersion','connected_person_work_field_decision_v1',
       'decisionId',v_existing.id,'idempotent',true,
       'decision',v_existing.decision,'fieldKey',v_existing.field_key,
       'workItemId',v_existing.work_item_id);
   END IF;
   RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 SELECT w.organization_id,
   CASE p_field_key WHEN 'title' THEN w.title
                    WHEN 'instructions' THEN w.instructions END
 INTO v_org,v_field_value
 FROM atlas.work_items w WHERE w.id=p_work_item_id;
 IF v_org IS NULL THEN
   RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 IF p_decision='allow' AND (
   v_field_value IS NULL OR btrim(v_field_value)=''
   OR NOT atlas.connected_person_work_field_source_eligible_v1(
       p_ledger_id,p_work_item_id,p_person_entity_id))
 THEN
   RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 -- A root governor can revoke a previously issued decision even after the
 -- person's Seat, Work allocation or relevance has ended. Such a revoked
 -- source can never be newly approved without renewed source eligibility.
 IF p_decision='deny'
   AND NOT atlas.connected_person_work_field_source_eligible_v1(
        p_ledger_id,p_work_item_id,p_person_entity_id)
   AND NOT EXISTS (
      SELECT 1 FROM atlas.connected_person_work_field_decision_events_v1 e
      WHERE e.ledger_id=p_ledger_id AND e.organization_id=v_org
        AND e.work_item_id=p_work_item_id
        AND e.recipient_person_entity_id=p_person_entity_id
        AND e.field_key=p_field_key
   )
 THEN
   RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 IF p_decision='allow' THEN
   v_hash:=pg_catalog.encode(pg_catalog.sha256(
     pg_catalog.convert_to(v_field_value,'UTF8')),'hex');
   IF v_hash IS DISTINCT FROM p_expected_value_sha256 THEN
     RETURN jsonb_build_object('ok',false,'code','not_found');
   END IF;
 END IF;
 INSERT INTO atlas.connected_person_work_field_decision_events_v1 (
   request_id,ledger_id,organization_id,work_item_id,
   recipient_person_entity_id,field_key,decision,
   approved_value_sha256,valid_until,governor_principal_id,
   governor_auth_user_id,reason
 ) VALUES (
   p_request_id,p_ledger_id,v_org,p_work_item_id,
   p_person_entity_id,p_field_key,p_decision,
   v_hash,p_valid_until,v_governor,auth.uid(),p_reason
 ) RETURNING * INTO v_event;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','connected_person_work_field_decision_v1',
   'decisionId',v_event.id,'idempotent',false,
   'decision',v_event.decision,'fieldKey',v_event.field_key,
   'workItemId',v_event.work_item_id);
END;
$decide$;
REVOKE ALL ON FUNCTION
 atlas.governor_decide_connected_person_work_field_self_api_v1(
 uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.governor_decide_connected_person_work_field_self_api_v1(
 p_ledger_id uuid,p_work_item_id uuid,p_person_entity_id uuid,
 p_field_key text,p_decision text,p_reason text,
 p_request_id uuid,p_expected_value_sha256 text DEFAULT NULL,
 p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO ''
AS $bridge$
 SELECT atlas.governor_decide_connected_person_work_field_self_api_v1(
  p_ledger_id,p_work_item_id,p_person_entity_id,p_field_key,
  p_decision,p_reason,p_request_id,p_expected_value_sha256,p_valid_until)
$bridge$;
REVOKE ALL ON FUNCTION
 public.governor_decide_connected_person_work_field_self_api_v1(
 uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.governor_decide_connected_person_work_field_self_api_v1(
 uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)
 TO authenticated;

-- Executed by a signed canonical connected Person using ONLY their own
-- identity and exact Work/Native Ledger source. No caller-chosen Person.
-- Return approved fields alone. This does not grant Work list access,
-- historical results, object inspection, crop records or source history.
CREATE OR REPLACE FUNCTION atlas.connected_person_work_approved_fields_self_api_v1(
 p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $read$
DECLARE
 v_access jsonb;
 v_self uuid;
 v_org uuid;
 v_title text;
 v_instructions text;
 v_fields jsonb:='{}'::jsonb;
 v_decision record;
 v_current_hash text;
BEGIN
 IF auth.uid() IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL
 THEN RETURN jsonb_build_object('ok',false,'code','not_found'); END IF;
 v_access:=atlas.reality_access_self_api_v1();
 v_self:=atlas.current_person_id_v1();
 IF v_access->>'state' IS DISTINCT FROM 'ready'
   OR v_access->>'authenticated' IS DISTINCT FROM 'true'
   OR v_access->'person'->>'id' IS DISTINCT FROM v_self::text
   OR v_self IS NULL
   OR NOT atlas.connected_person_work_field_source_eligible_v1(
     p_ledger_id,p_work_item_id,v_self)
 THEN
   RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 SELECT w.organization_id,w.title,w.instructions
 INTO v_org,v_title,v_instructions
 FROM atlas.work_items w WHERE w.id=p_work_item_id;
 IF v_org IS NULL THEN
  RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 FOR v_decision IN
  SELECT DISTINCT ON (e.field_key) e.field_key,e.decision,
   e.approved_value_sha256,e.valid_until
  FROM atlas.connected_person_work_field_decision_events_v1 e
  WHERE e.ledger_id=p_ledger_id
    AND e.organization_id=v_org
    AND e.work_item_id=p_work_item_id
    AND e.recipient_person_entity_id=v_self
  ORDER BY e.field_key,e.decided_at DESC,e.id DESC
 LOOP
  IF v_decision.decision<>'allow' OR
    (v_decision.valid_until IS NOT NULL AND
     v_decision.valid_until<=statement_timestamp())
  THEN CONTINUE; END IF;
  IF v_decision.field_key='title' THEN
    v_current_hash:=pg_catalog.encode(pg_catalog.sha256(
      pg_catalog.convert_to(v_title,'UTF8')),'hex');
    IF v_decision.approved_value_sha256=v_current_hash THEN
      v_fields:=v_fields||jsonb_build_object('title',v_title);
    END IF;
  ELSIF v_decision.field_key='instructions' AND v_instructions IS NOT NULL THEN
    v_current_hash:=pg_catalog.encode(pg_catalog.sha256(
      pg_catalog.convert_to(v_instructions,'UTF8')),'hex');
    IF v_decision.approved_value_sha256=v_current_hash THEN
      v_fields:=v_fields||jsonb_build_object('instructions',v_instructions);
    END IF;
  END IF;
 END LOOP;
 IF v_fields='{}'::jsonb THEN
  RETURN jsonb_build_object('ok',false,'code','not_found');
 END IF;
 RETURN jsonb_build_object('ok',true,
  'contractVersion','connected_person_work_approved_fields_v1',
  'workItemId',p_work_item_id,'ledgerId',p_ledger_id,
  'fields',v_fields,'sourceFieldDecisionsEnforced',true,
  'otherLedgerOrWorkAccessInferred',false);
END;
$read$;
REVOKE ALL ON FUNCTION
 atlas.connected_person_work_approved_fields_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.connected_person_work_approved_fields_self_api_v1(
 p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $bridge$
 SELECT atlas.connected_person_work_approved_fields_self_api_v1(
  p_ledger_id,p_work_item_id)
$bridge$;
REVOKE ALL ON FUNCTION
 public.connected_person_work_approved_fields_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.connected_person_work_approved_fields_self_api_v1(uuid,uuid)
 TO authenticated;
COMMIT;
