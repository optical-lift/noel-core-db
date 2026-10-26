-- HOLD / SOURCE CANDIDATE — Noel #2255, Atlas #437.
-- Universal active individual Work read with exact native-Ledger scope.
-- The Work instruction is a separate disclosure decision: deliberately absent.
-- No farm-zone, crop, bed, event, source-object, metadata or history joins.
-- No new Work or grants; no production release without protected clone and
-- independently signed owner/worker/outsider/revoked-session acceptance.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.connected_person_authorized_ledger_work_self_api_v1(
  p_ledger_id uuid,
  p_limit integer DEFAULT 50,
  p_after_allocation_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $read$
DECLARE
  v_person_id uuid;
  v_auth jsonb;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_next uuid;
BEGIN
  IF p_ledger_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  -- Live GoTrue session, not just a cryptographically valid old JWT.
  v_auth := atlas.reality_access_self_api_v1();
  IF (v_auth->>'state') IS DISTINCT FROM 'ready'
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;
  v_person_id := atlas.current_person_id_v1();
  IF v_person_id IS NULL
     OR (v_auth->'person'->>'id') IS DISTINCT FROM v_person_id::text
     OR NOT EXISTS(
       SELECT 1 FROM ledger.ledgers nl
       JOIN ledger.seats s ON s.ledger_id=nl.id
       JOIN reality.entities e ON e.id=s.person_entity_id
       WHERE nl.id=p_ledger_id
         AND nl.ledger_state='active' AND nl.retired_at IS NULL
         AND s.person_entity_id=v_person_id
         AND s.seat_state='active' AND s.ended_at IS NULL
         AND e.entity_kind='person' AND e.identity_state='canonical'
     )
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  WITH eligible AS MATERIALIZED (
    SELECT
      a.id allocation_id,
      w.id work_item_id,
      w.title,
      w.work_state,
      w.result_contract_key,
      a.allocated_at
    FROM atlas.work_allocations a
    JOIN atlas.work_items w
      ON w.id=a.work_item_id AND w.organization_id=a.organization_id
    WHERE a.assignee_canonical_person_id=v_person_id
      AND a.assignee_membership_id IS NULL
      AND a.allocation_role='responsible'
      AND a.state='active'
      AND a.establishment_basis_kind IN (
         'person_connection_receiver_uptake',
         'delegated_under_standing_scope',
         'ledger_connection_direct_assignment'
      )
      AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
      AND w.work_state='open'
      AND (p_after_allocation_id IS NULL OR a.id>p_after_allocation_id)
      AND atlas.connected_person_work_field_currently_approved_v1(
        p_ledger_id,w.id,v_person_id,'title')
      AND atlas.person_has_native_ledger_connection_v1(
         w.organization_id,p_ledger_id,v_person_id
      )
      -- An allocation is not itself a grant of all institutional records.
      AND EXISTS (
        SELECT 1
        FROM atlas.company_work_native_ledger_relevance rel
        WHERE rel.organization_id=w.organization_id
          AND rel.work_item_id=w.id
          AND rel.ledger_id=p_ledger_id
          AND rel.attribution_state='active'
          AND (
            rel.evidence_kind IN ('owner_attested','participant_attested')
            OR (
              rel.evidence_kind='source_verified'
              AND EXISTS (
                SELECT 1
                FROM atlas.company_work_native_ledger_exact_source_v1(
                  w.id,p_ledger_id
                ) proof
                WHERE proof.source_schema=rel.source_schema
                  AND proof.source_table=rel.source_table
                  AND proof.source_id=rel.source_id
              )
            )
          )
      )
    ORDER BY a.id
    LIMIT p_limit+1
  ), ranked AS (
    SELECT e.*,row_number() OVER (ORDER BY allocation_id) AS rn
    FROM eligible e
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
       'workItemId',work_item_id,
       'allocationId',allocation_id,
       'ledgerId',p_ledger_id,
       'title',title,
       'workState',work_state,
       'canReportOrdinaryCompletion',
          result_contract_key='ordinary_company_work_worker_attestation_v1'
     ) ORDER BY allocation_id)
       FILTER (WHERE rn<=p_limit),'[]'::jsonb),
    COUNT(*)::integer,
    (array_agg(allocation_id ORDER BY rn) FILTER (WHERE rn=p_limit))[1]
  INTO v_items,v_count,v_next
  FROM ranked;

  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','connected_person_authorized_ledger_work_v1',
    'ledgerId',p_ledger_id,
    'personId',v_person_id,
    'items',v_items,
    'hasMore',v_count>p_limit,
    'nextAllocationId',CASE WHEN v_count>p_limit THEN v_next ELSE NULL END,
    'sourceScope','active_person_assigned_exact_ledger_relevant_work',
    'includesInstructions',false,
    'includesFarmSourceContext',false,
    'permissionAuditComplete',false
  );
END;
$read$;

REVOKE ALL ON FUNCTION
  atlas.connected_person_authorized_ledger_work_self_api_v1(uuid,integer,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.connected_person_authorized_ledger_work_self_api_v1(
  p_ledger_id uuid,
  p_limit integer DEFAULT 50,
  p_after_allocation_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $bridge$
 SELECT atlas.connected_person_authorized_ledger_work_self_api_v1(
    p_ledger_id,p_limit,p_after_allocation_id
 );
$bridge$;

REVOKE ALL ON FUNCTION
  public.connected_person_authorized_ledger_work_self_api_v1(uuid,integer,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
  public.connected_person_authorized_ledger_work_self_api_v1(uuid,integer,uuid)
  TO authenticated;

COMMIT;
