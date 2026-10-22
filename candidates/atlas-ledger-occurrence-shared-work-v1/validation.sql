-- Schema-only postconditions, no protected person/event data.
DO $proof$
DECLARE
  v_pair text;
  v_kind text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_pair
    FROM pg_constraint c
    WHERE c.conrelid='atlas.work_item_context_links'::regclass
      AND c.conname='work_item_context_links_subject_pair_v1';
  IF v_pair IS NULL OR position('temporal' in v_pair)=0
     OR position('occurrence' in v_pair)=0 THEN
    RAISE EXCEPTION 'Event context pair not admitted';
  END IF;
  SELECT acceptance_mode INTO v_kind
    FROM atlas.work_result_contract_policies
    WHERE contract_key='ledger_occurrence_shared_confirmation_v1'
      AND source_domain='organization' AND active;
  IF v_kind IS DISTINCT FROM 'domain_adapter' THEN
    RAISE EXCEPTION 'Shared checklist confirmation policy missing/mismatched';
  END IF;
  IF to_regprocedure('atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)') IS NULL
     OR to_regprocedure('atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Required source operation was not created';
  END IF;
  IF has_function_privilege('anon','atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)','EXECUTE')
     OR has_function_privilege('anon','atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Source boundary leaked privileged function access';
  END IF;
  IF NOT has_function_privilege('authenticated','atlas.ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Authenticated source operations missing';
  END IF;
END
$proof$;
