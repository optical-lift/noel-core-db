BEGIN;

-- Canonical seat permits an individual Ledger view, NOT operational authority.
-- Operational source snapshots require a separately active and sufficient
-- farm membership. Legacy ledger/organization joins are routing-only.
CREATE OR REPLACE FUNCTION atlas.ledger_workspace_self_api_v1(p_ledger_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, atlas, auth, ledger, reality
AS $function$
DECLARE
  v_access jsonb;
  v_ledger ledger.ledgers%rowtype;
  v_subject_name text;
  v_farm_id uuid;
  v_farm_name text;
  v_kind text := 'native';
  v_actions jsonb := '[]'::jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_sales jsonb := '[]'::jsonb;
  v_demand jsonb := '[]'::jsonb;
  v_events jsonb := '[]'::jsonb;
  v_registrations jsonb := '[]'::jsonb;
BEGIN
  v_access := atlas.reality_access_self_api_v1();
  IF v_access->>'state' IS DISTINCT FROM 'ready'
     OR v_access->>'authenticated' IS DISTINCT FROM 'true'
     OR p_ledger_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(coalesce(v_access->'ledgerSeats','[]'::jsonb)) seat
       WHERE seat->>'ledgerId'=p_ledger_id::text
         AND seat->>'seatState'='active'
         AND seat->>'ledgerState'='active'
     )
  THEN
    RAISE EXCEPTION 'No current authorized Ledger seat' USING ERRCODE='42501';
  END IF;

  SELECT l.*, e.display_name INTO v_ledger, v_subject_name
  FROM ledger.ledgers l
  JOIN reality.entities e ON e.id=l.subject_entity_id AND e.identity_state='canonical'
  WHERE l.id=p_ledger_id AND l.ledger_state='active' AND l.retired_at IS NULL;
  IF v_ledger.id IS NULL THEN
    RAISE EXCEPTION 'Ledger is unavailable' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.occurred_at DESC,a.id DESC),'[]'::jsonb)
  INTO v_actions
  FROM (
    SELECT x.id, x.action_kind AS "kind", x.occurred_at AS "occurredAt",
      COALESCE(NULLIF(btrim(x.payload->>'title'),''),replace(x.action_kind,'_',' ')) AS "title",
      NULLIF(btrim(x.payload->>'detail'),'') AS "detail",
      x.payload->>'truthStatus' AS "truthStatus",
      x.payload->>'designationStatus' AS "designationStatus"
    FROM ledger.actions x WHERE x.ledger_id=p_ledger_id
    ORDER BY x.occurred_at DESC,x.id DESC LIMIT 100
  ) a;

  -- Exact pre-existing native-to-legacy Ledger ID + participation is a
  -- compatibility *route*, never an ownership/membership inference.
  -- A separate existing farm authorization must pass for source detail.
  IF v_ledger.stable_key IN ('elm-farm:flower','elm-farm:venue') THEN
    SELECT f.id,f.name INTO v_farm_id,v_farm_name
    FROM atlas.farms f
    JOIN atlas.ledger_organization_participations lop
      ON lop.organization_id=f.organization_id AND lop.ledger_id=p_ledger_id
      AND lop.status='active'
    JOIN atlas.ledgers ll ON ll.id=lop.ledger_id
    WHERE EXISTS (
      SELECT 1 FROM atlas.farm_memberships fm
      WHERE fm.farm_id=f.id AND fm.user_id=auth.uid()
        AND fm.active=true
        AND (fm.eligibility_begins_on IS NULL OR fm.eligibility_begins_on<=CURRENT_DATE)
        AND (fm.eligibility_ends_on IS NULL OR fm.eligibility_ends_on>=CURRENT_DATE)
        AND (
          fm.role IN ('owner','manager') OR
          fm.permissions->>'all_farm_data'='true' OR
          fm.permissions->>'farm_scope'='full'
        )
    )
    ORDER BY f.id LIMIT 1;
  END IF;

  IF v_farm_id IS NOT NULL AND v_ledger.stable_key='elm-farm:flower' THEN
    v_kind := 'flower';
    SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t."dueDate" NULLS LAST,t."title"),'[]'::jsonb)
    INTO v_tasks
    FROM (
      SELECT t.id,t.title,t.status,t.due_date AS "dueDate",t.priority,
        NULLIF(btrim(t.blocker_text),'') AS "blocker",
        NULLIF(btrim(t.note),'') AS "note",
        m.worker_key AS "assignedTo"
      FROM atlas.tasks t
      LEFT JOIN atlas.farm_memberships m ON m.id=t.assigned_membership_id AND m.farm_id=t.farm_id
      WHERE t.farm_id=v_farm_id AND t.status IN ('open','blocked')
      ORDER BY t.due_date NULLS LAST,t.title,t.id LIMIT 150
    ) t;

    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s."saleDate" DESC,s.id DESC),'[]'::jsonb)
    INTO v_sales
    FROM (
      SELECT o.id,o.customer_label AS "customer",o.sale_date AS "saleDate",
        o.sales_channel AS "channel",o.total_amount AS "totalAmount",
        o.currency,o.fulfillment_due_date AS "fulfillmentDue",
        o.fulfillment_mode AS "fulfillmentMode",
        (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'quantity',sl.quantity,'unit',sl.unit,'unitPrice',sl.unit_price,
            'lineTotal',sl.line_total,'inventoryKind',sl.inventory_kind
          ) ORDER BY sl.id),'[]'::jsonb)
         FROM atlas.flower_sale_order_lines sl WHERE sl.sale_order_id=o.id) AS lines
      FROM atlas.flower_sale_orders o WHERE o.farm_id=v_farm_id
      ORDER BY o.sale_date DESC,o.id DESC LIMIT 75
    ) s;

    SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d."requestedFor" DESC NULLS LAST,d.id DESC),'[]'::jsonb)
    INTO v_demand
    FROM (
      SELECT o.id,o.customer_label AS "customer",
        o.requested_for_date AS "requestedFor",o.demand_strength AS "demandStrength",
        o.sales_channel AS "channel",
        (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'product',dl.product_label,'quantity',dl.quantity,
            'unit',dl.unit,'targetUnitPrice',dl.target_unit_price
          ) ORDER BY dl.id),'[]'::jsonb)
         FROM atlas.flower_demand_order_lines dl WHERE dl.demand_order_id=o.id) AS lines
      FROM atlas.flower_demand_orders o WHERE o.farm_id=v_farm_id
      ORDER BY o.requested_for_date DESC NULLS LAST,o.id DESC LIMIT 75
    ) d;
  ELSIF v_farm_id IS NOT NULL AND v_ledger.stable_key='elm-farm:venue' THEN
    v_kind := 'venue';
    SELECT COALESCE(jsonb_agg(to_jsonb(ev) ORDER BY ev."eventDate",ev.id),'[]'::jsonb)
    INTO v_events
    FROM (
      SELECT e.id,e.title,e.event_date AS "eventDate",
        e.start_local_time AS "startsAt",e.end_local_time AS "endsAt",
        e.status,e.capacity
      FROM atlas.community_events e WHERE e.farm_id=v_farm_id
        AND e.event_date >= CURRENT_DATE - 30
      ORDER BY e.event_date,e.id LIMIT 100
    ) ev;

    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r."submittedAt" DESC NULLS LAST,r.id DESC),'[]'::jsonb)
    INTO v_registrations
    FROM (
      SELECT reg.id, reg.registration_number AS "number",reg.primary_name AS "registrant",
        reg.status,reg.submitted_at AS "submittedAt",
        o.id AS "offeringId",o.title AS "offering",o.event_id AS "eventId",
        (o.event_id IS NULL) AS "eventUnlinked"
      FROM atlas.community_registrations reg
      JOIN atlas.community_registration_offerings o ON o.id=reg.offering_id
      WHERE o.farm_id=v_farm_id
      ORDER BY reg.submitted_at DESC NULLS LAST,reg.id DESC LIMIT 100
    ) r;
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','ledger_workspace_self_v1',
    'ledger',jsonb_build_object('id',v_ledger.id,'name',v_ledger.name,
      'stableKey',v_ledger.stable_key,'subject',v_subject_name),
    'actions',v_actions,'operationalScope',v_kind,
    'farm',CASE WHEN v_farm_id IS NOT NULL THEN
      jsonb_build_object('id',v_farm_id,'name',v_farm_name)
      ELSE NULL END,
    'tasks',v_tasks,'sales',v_sales,'demand',v_demand,
    'events',v_events,'registrations',v_registrations,
    'truthBoundary',jsonb_build_object(
      'ledgerSeatGrantsWorkspaceReadOnly',true,
      'sourceRecordsRequireIndependentFarmAuthority',true,
      'nativeActionsAreNotEquivalentToOperationalSourceEvents',true,
      'legacyIdentityLinksAreRoutingOnly',true,
      'noRegistrationOrPaymentReconciliationAssumed',true
    )
  );
END;
$function$;

REVOKE ALL ON FUNCTION atlas.ledger_workspace_self_api_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.ledger_workspace_self_api_v1(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.ledger_workspace_self_api_v1(p_ledger_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog
AS $wrapper$
  SELECT atlas.ledger_workspace_self_api_v1(p_ledger_id);
$wrapper$;

REVOKE ALL ON FUNCTION public.ledger_workspace_self_api_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ledger_workspace_self_api_v1(uuid) TO authenticated;
COMMENT ON FUNCTION public.ledger_workspace_self_api_v1(uuid) IS
'Authenticated native-Ledger seat-scoped read; operational source detail separately gated by current farm authorization. No write, no ownership promotion.';

COMMIT;