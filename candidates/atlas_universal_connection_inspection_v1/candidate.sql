-- Atlas universal connection inspection: one read shape over EXISTING authorities.
-- Three independent source carriers; no new relationship or permission table.
-- Read-only; does NOT create connections or grant access to connected records.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.connection_inspection_self_api_v1(
  p_carrier_kind text,
  p_connection_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $source$
DECLARE
  v_access jsonb;
  v_person uuid;
  v_payload jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Signed-in Atlas Person required.'
      USING errcode = '42501';
  END IF;
  v_access := atlas.reality_access_self_api_v1();
  IF (v_access->>'state') IS DISTINCT FROM 'ready'
     OR (v_access->'person'->>'id') IS NULL THEN
    RAISE EXCEPTION 'Current Person Atlas required.'
      USING errcode = '42501';
  END IF;
  v_person := (v_access->'person'->>'id')::uuid;

  IF p_connection_id IS NULL OR p_carrier_kind IS NULL
    OR p_carrier_kind NOT IN (
      'ledger_person_seat','ledger_ledger_connection'
    ) THEN
    RAISE EXCEPTION 'Recognized connection source and identity required.'
      USING errcode = '22023';
  END IF;

  IF p_carrier_kind = 'ledger_person_seat' THEN
    -- This slice exposes only the actor's OWN seat. Another person's seat
    -- is not made visible merely because the actor shares their Ledger.
    SELECT pg_catalog.jsonb_build_object(
      'carrierKind',p_carrier_kind,
      'sourceId',s.id,
      'source',pg_catalog.jsonb_build_object('kind','ledger','id',s.ledger_id),
      'target',pg_catalog.jsonb_build_object('kind','person','id',s.person_entity_id),
      'relationshipKind','participates_in_ledger',
      'sourceState',s.seat_state,
      'beganAt',s.began_at,'endedAt',s.ended_at
    ) INTO v_payload
    FROM ledger.seats s
    JOIN ledger.ledgers l ON l.id=s.ledger_id
    JOIN reality.entities e ON e.id=s.person_entity_id
      AND e.entity_kind='person' AND e.identity_state='canonical'
    WHERE s.id=p_connection_id AND s.person_entity_id=v_person
      AND l.subject_entity_id IS NOT NULL
    LIMIT 1;

  ELSIF p_carrier_kind = 'ledger_ledger_connection' THEN
    -- Only a Person with currently active seats on BOTH ends may inspect
    -- this cross-Ledger carrier; no implication of source data exposure.
    SELECT pg_catalog.jsonb_build_object(
      'carrierKind',p_carrier_kind,
      'sourceId',c.id,
      'source',pg_catalog.jsonb_build_object('kind','ledger','id',c.source_ledger_id),
      'target',pg_catalog.jsonb_build_object('kind','ledger','id',c.observer_ledger_id),
      'relationshipKind',c.connection_kind,
      'sourceState',c.connection_state,
      'beganAt',c.began_at,'endedAt',c.ended_at
    ) INTO v_payload
    FROM ledger.connections c
    JOIN ledger.ledgers a ON a.id=c.source_ledger_id
      AND a.ledger_state='active' AND a.retired_at IS NULL
    JOIN ledger.ledgers b ON b.id=c.observer_ledger_id
      AND b.ledger_state='active' AND b.retired_at IS NULL
    WHERE c.id=p_connection_id
      AND EXISTS (
        SELECT 1 FROM ledger.seats sa
        WHERE sa.ledger_id=c.source_ledger_id
          AND sa.person_entity_id=v_person
          AND sa.seat_state='active' AND sa.ended_at IS NULL
      )
      AND EXISTS (
        SELECT 1 FROM ledger.seats sb
        WHERE sb.ledger_id=c.observer_ledger_id
          AND sb.person_entity_id=v_person
          AND sb.seat_state='active' AND sb.ended_at IS NULL
      )
    LIMIT 1;


  END IF;

  IF v_payload IS NULL THEN
    -- Identical absence shape for missing and unauthorized connection ID:
    -- do not reveal whether a third party's relationship exists.
    RETURN pg_catalog.jsonb_build_object(
      'ok',true,'contractVersion','atlas_connection_inspection_self_v1',
      'state','not_visible','connection',NULL,
      'boundary',pg_catalog.jsonb_build_object(
        'readOnly',true,'recordAccessNotGranted',true,
        'missingAndUnauthorizedIndistinguishable',true
      )
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok',true,'contractVersion','atlas_connection_inspection_self_v1',
    'state','ready','connection',v_payload,
    'boundary',pg_catalog.jsonb_build_object(
      'readOnly',true,'recordAccessNotGranted',true,
      'missingAndUnauthorizedIndistinguishable',true
    )
  );
END
$source$;

-- Public API is a narrow wrapper around the private, source-checked reader.
CREATE OR REPLACE FUNCTION public.connection_inspection_self_api_v1(
  p_carrier_kind text,
  p_connection_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $bridge$
  SELECT atlas.connection_inspection_self_api_v1(
    p_carrier_kind,p_connection_id
  );
$bridge$;

REVOKE ALL ON FUNCTION atlas.connection_inspection_self_api_v1(text,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.connection_inspection_self_api_v1(text,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.connection_inspection_self_api_v1(text,uuid)
  TO authenticated;

COMMIT;
