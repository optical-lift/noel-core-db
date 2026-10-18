-- Owner's released People reader exposes exact canonical Person +
-- Position appointment, not private membership IDs. Resolve on server only.
BEGIN;
CREATE FUNCTION atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_person_id uuid,
 p_appointment_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_worker_membership uuid;
 v_position uuid;
 v_person uuid;
 v_count integer;
 v_result jsonb;
BEGIN
 IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_worker_person_id IS NULL OR p_appointment_id IS NULL THEN
   RAISE EXCEPTION 'Authenticated exact Ledger, Person and appointment required'
     USING ERRCODE='42501';
 END IF;
 -- Must prove owner authority before even resolving the worker's private
 -- membership from their canonical Person and the visible Position appointment.
 v_person:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 SELECT count(*)::integer,
   (array_agg(m.id ORDER BY m.created_at,m.id))[1],
   (array_agg(a.position_id ORDER BY m.created_at,m.id))[1]
 INTO v_count,v_worker_membership,v_position
 FROM atlas.organization_position_appointments a
 JOIN atlas.organization_memberships m
    ON m.id=a.organization_membership_id AND m.organization_id=a.organization_id
 JOIN atlas.organization_positions p
    ON p.id=a.position_id AND p.organization_id=a.organization_id
 WHERE a.id=p_appointment_id AND a.organization_id=p_organization_id
   AND m.person_id=p_worker_person_id AND m.person_id IS DISTINCT FROM v_person
   AND a.status='active' AND a.begins_at<=now() AND a.ends_at IS NULL
   AND p.status='active'
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now());
 IF v_count<>1 THEN
   RAISE EXCEPTION 'Exactly one canonical current Person/Position membership required'
     USING ERRCODE='23514';
 END IF;
 v_result:=atlas.propose_company_work_standing_scope_self_api_v1(
   p_organization_id,p_ledger_id,v_worker_membership,v_position,p_terms,p_valid_until);
 IF v_result->>'organizationId'<>p_organization_id::text OR
    v_result->>'nativeLedgerId'<>p_ledger_id::text OR
    v_result->>'workerPersonId'<>p_worker_person_id::text OR
    v_result->>'positionId'<>v_position::text OR
    v_result->>'state'<>'proposed' THEN
   RAISE EXCEPTION 'Source confirmation of exact worker scope failed' USING ERRCODE='23514';
 END IF;
 RETURN v_result||jsonb_build_object(
   'sourceAppointmentId',p_appointment_id,'requestedWorkerPersonId',p_worker_person_id);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz) TO authenticated;
CREATE FUNCTION public.propose_company_work_standing_scope_by_appointment_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_person_id uuid,
 p_appointment_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.propose_company_work_standing_scope_by_appointment_self_api_v1(
 p_organization_id,p_ledger_id,p_worker_person_id,p_appointment_id,p_terms,p_valid_until);
$fn$;
REVOKE ALL ON FUNCTION public.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.propose_company_work_standing_scope_by_appointment_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz) TO authenticated;
COMMIT;
