-- Atlas Build 5: canonical Person-to-Ledger access foundation.
-- Governed source candidate. No live mutation, identity merge, ledger grant,
-- task, account, membership, or legacy employee-seat deletion here.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.native_connected_ledger_access_self_api_v1()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
 v_user uuid:=auth.uid();
 v_person uuid;
 v_principal uuid;
 v_connections jsonb:='[]'::jsonb;
BEGIN
 IF v_user IS NULL THEN
   RETURN jsonb_build_object(
     'ok',true,'authenticated',false,'contractVersion',
     'native_person_ledger_access_v1','connections','[]'::jsonb);
 END IF;
 -- A credential is authentication; neither an employee subscription
 -- nor an institutional membership may establish Ledger participation.
 v_person:=atlas.current_person_id_v1();
 v_principal:=atlas.current_principal_id_v1();
 IF v_person IS NULL OR v_principal IS NULL OR
   NOT EXISTS (SELECT 1 FROM atlas.principals p
      WHERE p.id=v_principal AND p.person_id=v_person AND p.status='active') THEN
   RETURN jsonb_build_object(
     'ok',true,'authenticated',true,'canonicalIdentityReady',false,
     'contractVersion','native_person_ledger_access_v1','connections','[]'::jsonb);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'organizationId',connected.organization_id,
   'organizationName',connected.organization_name,
   'ledgerId',connected.ledger_id,
   'ledgerName',connected.ledger_name,
   'nativeLedgerConnectionId',connected.connection_id,
   'connectionState','active',
   'managementAuthorityInferred',false,
   'taskResponsibilityInferred',false,
   'institutionalBillingInferred',false)
   ORDER BY connected.organization_name,connected.ledger_name,connected.ledger_id),
   '[]'::jsonb)
 INTO v_connections
 FROM (
   SELECT DISTINCT ON (lop.organization_id,nl.id)
     lop.organization_id,o.name organization_name,
     nl.id ledger_id,nl.name ledger_name,s.id connection_id
   FROM ledger.seats s
   JOIN reality.entities e ON e.id=s.person_entity_id
     AND e.entity_kind='person' AND e.identity_state='canonical'
   JOIN ledger.ledgers nl ON nl.id=s.ledger_id
     AND nl.ledger_state='active' AND nl.retired_at IS NULL
   JOIN atlas.ledgers al ON al.id=nl.id AND al.status='active'
   JOIN atlas.ledger_organization_participations lop ON lop.ledger_id=nl.id
     AND lop.status='active' AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
   JOIN atlas.organizations o ON o.id=lop.organization_id AND o.status='active'
   WHERE e.id=v_person AND s.seat_state='active' AND s.ended_at IS NULL
   ORDER BY lop.organization_id,nl.id,s.began_at DESC,s.id
 ) connected;
 RETURN jsonb_build_object(
   'ok',true,'authenticated',true,'canonicalIdentityReady',true,
   'contractVersion','native_person_ledger_access_v1',
   'canonicalPersonId',v_person,
   'connections',v_connections,
   'connectionIsNotManagementAuthority',true,
   'connectionIsNotTaskAssignment',true,
   'credentialIsNotEmployment',true);
END
$function$;

REVOKE ALL ON FUNCTION atlas.native_connected_ledger_access_self_api_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION atlas.native_connected_ledger_access_self_api_v1() TO authenticated;

COMMIT;
