-- Build 5: separately admit a source-backed legacy task slice to the existing
-- organization-owned, manager-acceptance result contract. Never assigns Work,
-- records a worker result, completes a task, or places it in a worker's Day.
BEGIN;

-- An immutable snapshot of the slice's originating task and delivery identity.
-- No FK to atlas.tasks: retiring the legacy parent must not erase slice proof.
CREATE TABLE atlas.company_work_legacy_slice_contract_provenance_v1 (
  binding_id uuid PRIMARY KEY
    REFERENCES atlas.company_work_result_contract_bindings_v1(id) ON DELETE RESTRICT,
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL UNIQUE,
  source_task_id uuid NOT NULL,
  work_stable_key text NOT NULL CHECK (length(btrim(work_stable_key)) BETWEEN 1 AND 256),
  delivery_key text NOT NULL CHECK (length(btrim(delivery_key)) BETWEEN 1 AND 256),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_work_legacy_slice_provenance_org_work_fk
    FOREIGN KEY (organization_id,work_item_id)
    REFERENCES atlas.work_items(organization_id,id) ON DELETE RESTRICT
);
ALTER TABLE atlas.company_work_legacy_slice_contract_provenance_v1
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.company_work_legacy_slice_contract_provenance_v1
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE atlas.company_work_legacy_slice_contract_provenance_v1
  TO service_role;

CREATE FUNCTION atlas.bind_legacy_task_slice_result_contract_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_owner_person uuid;
  v_owner_membership uuid;
  v_work atlas.work_items%ROWTYPE;
  v_binding atlas.company_work_result_contract_bindings_v1%ROWTYPE;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_delivery_key text;
  v_key constant text:='ordinary_company_work_manager_acceptance_v1';
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1200 THEN
    RAISE EXCEPTION 'Exact native Ledger Work and binding purpose required'
      USING ERRCODE='22023';
  END IF;
  v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_owner_membership:=atlas.current_effective_organization_membership_v1(p_organization_id);
  IF NOT EXISTS(
    SELECT 1 FROM atlas.organization_memberships member
    WHERE member.id=v_owner_membership AND member.organization_id=p_organization_id
      AND member.person_id=v_owner_person AND member.role='owner' AND member.active
  ) THEN
    RAISE EXCEPTION 'Authenticated institutional owner membership required'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.work_state<>'open' THEN
    RAISE EXCEPTION 'Exactly one open Company Work slice required'
      USING ERRCODE='23514';
  END IF;
  IF v_work.source_object_type<>'legacy_task_slice'
    OR v_work.source_object_id IS NULL
    OR nullif(btrim(coalesce(v_work.stable_key,'')),'') IS NULL
    OR length(btrim(v_work.stable_key))>256
    OR v_work.metadata->>'sliceOfLegacyTask' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Verified legacy task slice identity required'
      USING ERRCODE='23514';
  END IF;
  v_delivery_key:=nullif(btrim(coalesce(v_work.metadata->>'deliveryKey','')),'');
  IF v_delivery_key IS NULL OR length(v_delivery_key)>256 THEN
    RAISE EXCEPTION 'Exact legacy task slice delivery identity required'
      USING ERRCODE='23514';
  END IF;
  -- A slice's source is the actual Atlas task in the same institution.
  -- Its current task status is not the slice's state: obsolete parents
  -- may be retired separately through governed reconciliation.
  IF NOT EXISTS(
    SELECT 1 FROM atlas.tasks src
    WHERE src.id=v_work.source_object_id
      AND src.organization_id=p_organization_id
  ) THEN
    RAISE EXCEPTION 'Institution-scoped source task for slice not found'
      USING ERRCODE='23514';
  END IF;
  -- Prevent ambiguity if an active or completed sibling repeats one
  -- delivery key for the same originating task.
  IF EXISTS(
    SELECT 1 FROM atlas.work_items sibling
    WHERE sibling.organization_id=p_organization_id
      AND sibling.id<>v_work.id
      AND sibling.source_object_type='legacy_task_slice'
      AND sibling.source_object_id=v_work.source_object_id
      AND sibling.metadata->>'deliveryKey'=v_delivery_key
      AND sibling.work_state<>'cancelled'
  ) THEN
    RAISE EXCEPTION 'Legacy task slice delivery identity is not unique'
      USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance relevance
    WHERE relevance.organization_id=v_work.organization_id
      AND relevance.work_item_id=v_work.id
      AND relevance.ledger_id=p_ledger_id
      AND relevance.attribution_state='active'
      AND (relevance.evidence_kind='owner_attested' OR
        (relevance.evidence_kind='source_verified' AND EXISTS(
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          WHERE proof.source_schema=relevance.source_schema
            AND proof.source_table=relevance.source_table
            AND proof.source_id=relevance.source_id)))
  ) THEN
    RAISE EXCEPTION 'Exact native Ledger attribution required for result contract'
      USING ERRCODE='23514';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies policy
    WHERE policy.contract_key=v_key AND policy.active
      AND policy.acceptance_mode='manager_acceptance'
      AND policy.source_domain='organization'
  ) THEN
    RAISE EXCEPTION 'The manager-acceptance policy is unavailable'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS(
    SELECT 1 FROM atlas.work_execution_results result
    WHERE result.organization_id=v_work.organization_id
      AND result.work_item_id=v_work.id
  ) THEN
    RAISE EXCEPTION 'Existing worker results cannot be re-contracted retroactively'
      USING ERRCODE='23514';
  END IF;
  IF v_work.result_contract_key IS NOT NULL THEN
    IF v_work.result_contract_key<>v_key OR NOT EXISTS(
      SELECT 1 FROM atlas.company_work_result_contract_bindings_v1 binding
      JOIN atlas.company_work_legacy_slice_contract_provenance_v1 provenance
        ON provenance.binding_id=binding.id
      WHERE binding.work_item_id=v_work.id
        AND binding.organization_id=p_organization_id
        AND binding.ledger_id=p_ledger_id
        AND binding.contract_key=v_key
        AND provenance.work_item_id=v_work.id
        AND provenance.organization_id=p_organization_id
        AND provenance.source_task_id=v_work.source_object_id
        AND provenance.work_stable_key=v_work.stable_key
        AND provenance.delivery_key=v_delivery_key
    ) THEN
      RAISE EXCEPTION 'Existing contract or provenance cannot be overwritten'
        USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object('ok',true,
      'contractVersion','company_work_legacy_slice_result_contract_v1',
      'state','existing_contract_unchanged','workItemId',v_work.id,
      'resultContractKey',v_key,'workerResultCreated',false,
      'completionRecorded',false,'workerDayPlacementProven',false);
  END IF;

  INSERT INTO atlas.company_work_result_contract_bindings_v1(
    organization_id,ledger_id,work_item_id,actor_person_id,actor_membership_id,
    contract_key,reason
  ) VALUES(p_organization_id,p_ledger_id,v_work.id,v_owner_person,
    v_owner_membership,v_key,v_reason)
  RETURNING * INTO v_binding;
  INSERT INTO atlas.company_work_legacy_slice_contract_provenance_v1(
    binding_id,organization_id,work_item_id,source_task_id,work_stable_key,delivery_key
  ) VALUES(
    v_binding.id,p_organization_id,v_work.id,v_work.source_object_id,
    v_work.stable_key,v_delivery_key
  );
  UPDATE atlas.work_items SET result_contract_key=v_key,updated_at=now()
  WHERE id=v_work.id AND organization_id=v_work.organization_id
    AND work_state='open' AND result_contract_key IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Open slice contract binding lost its eligibility'
      USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','company_work_legacy_slice_result_contract_v1',
    'state','bound','bindingId',v_binding.id,'workItemId',v_work.id,
    'ledgerId',p_ledger_id,'sourceTaskId',v_work.source_object_id,
    'resultContractKey',v_key,'acceptanceMode','manager_acceptance',
    'workerResultCreated',false,'completionRecorded',false,
    'workerDayPlacementProven',false);
END
$function$;

REVOKE ALL ON FUNCTION atlas.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)
  TO authenticated;
CREATE FUNCTION public.bind_legacy_task_slice_result_contract_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
  SELECT atlas.bind_legacy_task_slice_result_contract_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_reason);
$fn$;
REVOKE ALL ON FUNCTION public.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bind_legacy_task_slice_result_contract_self_api_v1(uuid,uuid,uuid,text)
  TO authenticated;

COMMIT;
