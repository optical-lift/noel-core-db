-- Employee-seat physical retirement: clone postconditions.
-- Do not accept silent CASCADE removal, loss of credentials, or a live route
-- still requiring paid employee-seat data.
DO $check$
DECLARE v_count integer;
BEGIN
 IF to_regclass('atlas.organization_employee_seats') IS NOT NULL THEN
   RAISE EXCEPTION 'Legacy employee-seat table must be physically absent';
 END IF;
 SELECT count(*) INTO v_count FROM information_schema.columns
 WHERE table_schema='atlas' AND column_name='employee_seat_id'
   AND table_name IN ('organization_member_credentials',
     'organization_member_exposure_grants','company_work_standing_assignment_scopes');
 IF v_count<>0 THEN RAISE EXCEPTION 'Legacy employee-seat columns must be absent: %',v_count; END IF;
 SELECT count(*) INTO v_count FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.prokind='f' AND (
   pg_get_functiondef(p.oid) LIKE '%atlas.organization_employee_seats%'
   OR pg_get_functiondef(p.oid) LIKE '%.employee_seat_id%'
   OR pg_get_functiondef(p.oid) LIKE '%atlas.organization_employee_seats%ROWTYPE%');
 IF v_count<>0 THEN RAISE EXCEPTION 'Executable Atlas functions still refer to physically retired table/field: %',v_count;END IF;
 IF to_regprocedure('atlas.guard_institutional_person_seat_bridge_v1()') IS NOT NULL THEN
   RAISE EXCEPTION 'Obsolete physical-seat bridge trigger function remains';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.organization_member_credentials c
   JOIN atlas.organization_memberships m ON m.id=c.organization_membership_id
     AND m.organization_id=c.organization_id
     AND m.identity_subject_id=c.identity_subject_id
     AND m.user_id=c.auth_user_id
   JOIN reality.auth_person_bindings b ON b.auth_user_id=c.auth_user_id
     AND b.binding_state='active' AND b.retired_at IS NULL
   JOIN atlas.principals p ON p.person_id=b.person_entity_id AND p.status='active'
   WHERE c.credential_kind='auth_user' AND c.status='active'
     AND c.provenance ? 'retiredEmployeeSeatEvidenceV1'
     AND jsonb_typeof(c.provenance->'retiredEmployeeSeatEvidenceV1'->'originalSeatRecord')='object'
 ) THEN
   RAISE EXCEPTION 'Active original credential and seat audit evidence not preserved';
 END IF;
 IF (SELECT count(*) FROM atlas.work_allocations
      WHERE state='active' AND assignee_membership_id IS NOT NULL)=0 THEN
   RAISE EXCEPTION 'Historical membership-based Work allocations disappeared';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.organization_position_appointments WHERE status='active') THEN
   RAISE EXCEPTION 'Existing institutional Position appointments disappeared';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_proc p
   WHERE p.oid='atlas.organization_access_physical_compatibility_internal_v1()'::regprocedure
     AND pg_get_functiondef(p.oid) LIKE '%verified_organization_member_credential%'
 ) THEN
   RAISE EXCEPTION 'Legacy employee notebook lacks independently verified credential access';
 END IF;
 IF NOT has_function_privilege('authenticated','public.organization_access_self_api_v1()','EXECUTE')
   OR has_function_privilege('anon','public.native_ledger_standing_scopes_self_api_v1()','EXECUTE') THEN
   RAISE EXCEPTION 'Public login/Person Ledger API grants altered by seat retirement';
 END IF;
END
$check$;
