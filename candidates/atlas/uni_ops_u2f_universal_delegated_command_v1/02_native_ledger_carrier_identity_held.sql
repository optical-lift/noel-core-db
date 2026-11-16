-- HELD U2F 02: identify an independently registered delegated carrier's
-- exact native Ledger seat and canonical Principal/Person binding.
-- SOURCE-ONLY PRIVATE READ. Not a root/worker authorization, not executable
-- Work, not a generic issuer, not a migration. No legacy Atlas Ledger/Task,
-- queue, campaign/clock/offer table or Root session may be substituted.
-- This uses the EXISTING delegated agent and native Ledger tables only.
CREATE FUNCTION atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(
  p_authorization_id uuid,
  p_native_ledger_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $native_identity$
DECLARE
  v_aligned boolean := false;
BEGIN
  IF p_authorization_id IS NOT NULL AND p_native_ledger_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1
      FROM atlas.delegated_agent_authorizations a
      JOIN atlas.delegated_agent_carriers c
        ON c.id=a.carrier_id
       AND c.status='active' AND c.retired_at IS NULL
      JOIN atlas.principals p
        ON p.id=a.principal_id
       AND p.status='active' AND p.person_id IS NOT NULL
      JOIN ledger.ledgers l
        ON l.id=a.ledger_id
       AND l.ledger_state='active' AND l.retired_at IS NULL
      JOIN ledger.seats s
        ON s.id=a.delegating_seat_id
       AND s.ledger_id=l.id
       AND s.person_entity_id=p.person_id
       AND s.seat_state='active'
       AND s.began_at<=pg_catalog.now()
       AND (s.ended_at IS NULL OR s.ended_at>pg_catalog.now())
      WHERE a.id=p_authorization_id
        AND a.ledger_id=p_native_ledger_id
        AND a.delegating_seat_id IS NOT NULL
        AND a.authorization_state='active'
        AND a.revoked_at IS NULL
        AND a.begins_at<=pg_catalog.now()
        AND (a.ends_at IS NULL OR a.ends_at>pg_catalog.now())
    ) INTO v_aligned;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'contractVersion','uni_ops_u2f_native_ledger_carrier_identity_held_v1',
    'identityAligned',v_aligned,
    'workIssuerAuthorized',false,
    'governingRootVerified',false,
    'workCandidateAccepted',false,
    'rulebookAndNeedVerified',false,
    'originalWorkCreated',false,
    'sourceOnly',true
  );
END
$native_identity$;

-- Private evaluator: no Data API route, no general agent-credential RPC,
-- no root-session impersonation. Only independently governed future source
-- may decide whether this narrow identity fact is a required input.
REVOKE ALL ON FUNCTION
 atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(uuid,uuid)
FROM PUBLIC,anon,authenticated,service_role;
