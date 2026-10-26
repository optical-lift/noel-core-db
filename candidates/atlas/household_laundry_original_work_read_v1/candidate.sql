BEGIN;
-- Governor's original Laundry notebook; signed actor-only Work Focus by UUID.
-- No private Household data is inferred through Ledger or farm membership.
CREATE OR REPLACE FUNCTION atlas.household_laundry_current_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_household uuid;v_kernel atlas.household_kernel_instances%rowtype;
 v_condition text;v_observation uuid;v_need atlas.household_need_occurrences_v1%rowtype;
 v_work atlas.work_items%rowtype;v_allocation atlas.work_allocations%rowtype;
BEGIN
 v_household:=atlas.principal_current_household_id_v1();
 IF v_household IS NULL THEN
  RAISE EXCEPTION 'Original Household unavailable.' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_household_governor_self_v1(v_household);
 SELECT * INTO v_kernel FROM atlas.household_kernel_instances
 WHERE household_id=v_household AND kernel_key='household.laundry'
 ORDER BY created_at DESC LIMIT 1;
 IF v_kernel.id IS NOT NULL THEN
  SELECT condition_state,last_observation_id INTO v_condition,v_observation
  FROM atlas.care_current_state
  WHERE scope_kind='household' AND scope_id=v_household
   AND subject_domain='household' AND subject_kind='household_kernel_instance'
   AND subject_id=v_kernel.id::text;
  SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
  WHERE household_id=v_household AND instance_id=v_kernel.id
  ORDER BY (state='open') DESC,created_at DESC,id DESC LIMIT 1;
  IF v_need.id IS NOT NULL THEN
    SELECT * INTO v_work FROM atlas.work_items w WHERE w.id=v_need.current_work_item_id
       AND w.household_id=v_household;
    SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.household_id=v_household AND a.work_item_id=v_work.id
      AND a.allocation_role='responsible' AND a.state='active'
    ORDER BY a.allocated_at DESC LIMIT 1;
  END IF;
 END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','household_laundry_current_v1',
  'householdId',v_household,
  'instanceId',v_kernel.id,
  'instanceState',v_kernel.state,
  'currentCondition',v_condition,
  'lastObservationId',v_observation,
  'needOccurrenceId',v_need.id,
  'needState',v_need.state,
  'workItemId',v_work.id,
  'workTitle',v_work.title,
  'workState',v_work.work_state,
  'carrierAllocationId',v_allocation.id,
  'assignedCanonicalPersonId',v_allocation.assignee_canonical_person_id,
  'assignedHouseholdMemberId',v_allocation.assignee_household_member_id,
  'workOnDate',NULL,
  'clockAdmitted',false,
  'wholeLaundryDone',false,
  'oneOriginalWork',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_laundry_current_self_api_v1()
 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.household_laundry_current_self_api_v1()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.household_laundry_current_self_api_v1();
$function$;
REVOKE ALL ON FUNCTION public.household_laundry_current_self_api_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_laundry_current_self_api_v1()
 TO authenticated;

CREATE OR REPLACE FUNCTION atlas.household_original_work_focus_self_api_v1(
 p_household_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_governor boolean:=false;
 v_work atlas.work_items%rowtype;v_need atlas.household_need_occurrences_v1%rowtype;
 v_allocation atlas.work_allocations%rowtype;
 v_accepted atlas.work_result_acceptances%rowtype;
 v_result atlas.work_execution_results%rowtype;
BEGIN
 v_person:=atlas.household_work_actor_v1(p_household_id);
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND household_id=p_household_id
  AND organization_id IS NULL AND source_object_type='household_need_occurrence';
 IF v_work.id IS NULL THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 n
 WHERE n.id=v_work.source_object_id AND n.household_id=p_household_id
   AND n.current_work_item_id=v_work.id;
 IF v_need.id IS NULL THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT EXISTS(
  SELECT 1 FROM atlas.households h JOIN atlas.principals p ON p.id=h.principal_id
  WHERE h.id=p_household_id AND p.status='active' AND p.user_id=auth.uid()
    AND p.person_id=v_person
 ) INTO v_governor;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.household_id=p_household_id AND a.work_item_id=v_work.id
  AND a.allocation_role='responsible' AND a.state='active'
 ORDER BY a.allocated_at DESC LIMIT 1;
 IF NOT v_governor AND NOT (
   v_allocation.assignee_canonical_person_id=v_person OR EXISTS(
    SELECT 1 FROM atlas.household_members hm
    WHERE hm.id=v_allocation.assignee_household_member_id AND hm.active
     AND hm.household_id=p_household_id AND hm.user_id=auth.uid()
     AND hm.person_id=v_person)
 ) THEN
  RAISE EXCEPTION 'Original Household Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.household_id=p_household_id AND r.work_item_id=v_work.id
 ORDER BY r.reported_at DESC,r.id DESC LIMIT 1;
 IF v_result.id IS NOT NULL THEN
  SELECT * INTO v_accepted FROM atlas.work_result_acceptances a
   WHERE a.execution_result_id=v_result.id
    AND a.household_id=p_household_id AND a.decision='accepted';
 END IF;
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','household_original_work_focus_v1',
  'householdId',p_household_id,'workItemId',v_work.id,
  'subjectDomain','household','subjectKind','kernel_instance',
  'subjectId',v_need.instance_id,'needOccurrenceId',v_need.id,
  'needState',v_need.state,
  'title',v_work.title,'instructions',v_work.instructions,
  'workState',v_work.work_state,
  'allocationId',v_allocation.id,
  'assignedCanonicalPersonId',v_allocation.assignee_canonical_person_id,
  'resultContractKey',v_work.result_contract_key,
  'latestReportKind',v_result.result_kind,
  'acceptedResultKind',CASE WHEN v_accepted.id IS NOT NULL
   THEN v_result.result_kind ELSE NULL END,
  'canReportPhysicalActual',v_work.work_state='open' AND v_need.state='open'
   AND (v_governor OR v_allocation.id IS NOT NULL),
  'isSignedHouseholdPerson',true,'isCompany',false
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_original_work_focus_self_api_v1(
 uuid,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.household_original_work_focus_self_api_v1(
 p_household_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.household_original_work_focus_self_api_v1(
 p_household_id,p_work_item_id);
$function$;
REVOKE ALL ON FUNCTION public.household_original_work_focus_self_api_v1(
 uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_original_work_focus_self_api_v1(
 uuid,uuid) TO authenticated;
COMMIT;
