-- UNI-OPS-01 U5: existing ORIGINAL Household Work reference only.
-- HELD, READ-ONLY, no Work writer. The shared atlas.work_items table
-- already enforces exactly one of Household OR Organization custody.
-- Current live Household Work protection is specifically Laundry v1:
-- do not widen guard_original_household_work_v1 or invent generalized Work.
BEGIN;
CREATE FUNCTION atlas.uni_ops_existing_household_original_work_reference_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_native_need_occurrence_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $existing_work$
DECLARE
  v_need jsonb;
  v_original_need_current boolean := false;
  v_work_id uuid;
  v_result_contract_key text;
  v_kernel_key text;
  v_any_claimed_work_id uuid;
BEGIN
  -- This exact source method authenticates the signed current Household
  -- governor and checks its native original observed, still-open Need.
  v_need:=atlas.uni_ops_original_household_need_receipt_internal_v1(
    p_household_id,p_kernel_instance_id,p_native_need_occurrence_id
  );
  IF (v_need->>'contractVersion') IS DISTINCT FROM
     'uni_ops_household_original_need_receipt_v1' THEN
    RAISE EXCEPTION 'Expected source-owned original Household Need receipt'
      USING ERRCODE='42501';
  END IF;
  v_original_need_current:=coalesce(
    (v_need->>'currentOriginalNeedVerified')::boolean,false);

  IF v_original_need_current THEN
    -- Capture any native original's claimed Work link, even if it is
    -- invalid. Never repair or silently substitute another original.
    SELECT n.current_work_item_id,k.kernel_key
      INTO v_any_claimed_work_id,v_kernel_key
    FROM atlas.household_need_occurrences_v1 n
    JOIN atlas.household_kernel_instances k ON k.id=n.instance_id
      AND k.household_id=n.household_id
    WHERE n.id=p_native_need_occurrence_id
      AND n.household_id=p_household_id
      AND n.instance_id=p_kernel_instance_id
      AND n.state='open';

    -- The existing shared Work kernel has a real household branch.
    -- Only the CURRENT Laundry v1 result contract and native source are
    -- supported by existing household original Work guards.
    IF v_any_claimed_work_id IS NOT NULL
       AND v_kernel_key='household.laundry'
    THEN
      SELECT w.id,w.result_contract_key
        INTO v_work_id,v_result_contract_key
      FROM atlas.work_items w
      WHERE w.id=v_any_claimed_work_id
        AND w.household_id=p_household_id
        AND w.organization_id IS NULL
        AND w.organization_unit_id IS NULL
        AND w.work_definition_id IS NULL
        AND w.source_object_type='household_need_occurrence'
        AND w.source_object_id=p_native_need_occurrence_id
        AND w.result_contract_key='household_laundry_begin_cycle_v1'
        AND w.work_state IN ('open','completed','cancelled','superseded');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_existing_household_original_work_reference_v1',
    'state',CASE
      WHEN NOT v_original_need_current
      THEN 'original_household_need_not_current'
      WHEN v_any_claimed_work_id IS NULL
      THEN 'original_need_without_work_reference'
      WHEN v_work_id IS NULL
      THEN 'source_work_reference_mismatch_or_unsupported_kernel'
      ELSE 'one_existing_native_original_work_reference_only'
    END,
    'originalNeedCurrent',v_original_need_current,
    'sourceClaimsWork',v_any_claimed_work_id IS NOT NULL,
    'sameNativeOriginalWorkReferenceVerified',v_work_id IS NOT NULL,
    'originalWorkId',v_work_id,
    'nativeWorkCustody','household',
    'originalWorkTable','atlas.work_items',
    'existingResultContractKey',v_result_contract_key,
    'currentWorkGuardGeneralizedBeyondLaundry',false,
    'workRequirementRowCreated',false,
    'newOriginalWorkCreated',false,
    'assignmentOrOfferCreated',false,
    'policyAdoptable',false,
    'clockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$existing_work$;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_existing_household_original_work_reference_internal_v1(
    uuid,uuid,uuid
  ) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
