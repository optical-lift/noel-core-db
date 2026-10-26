-- Full production-schema disposable clone only; NOT a live SQL command.
DO $proof$
DECLARE
  v_write regprocedure := to_regprocedure(
    'public.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)'
  );
  v_read regprocedure := to_regprocedure(
    'public.work_growing_object_context_review_self_api_v1(uuid,uuid)'
  );
  v_internal regprocedure := to_regprocedure(
    'atlas.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)'
  );
  v_rows bigint;
  v_response jsonb;
  v_source text;
BEGIN
  IF v_write IS NULL OR v_read IS NULL OR v_internal IS NULL THEN
    RAISE EXCEPTION 'Missing governed Work/growing-object contract';
  END IF;
  IF has_function_privilege('anon',v_write,'EXECUTE')
    OR has_function_privilege('anon',v_read,'EXECUTE')
    OR has_function_privilege('authenticated',v_internal,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_write,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_read,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Public/private RPC privileges are unsafe';
  END IF;
  IF has_table_privilege('authenticated','atlas.work_item_context_links','INSERT')
     OR has_table_privilege('authenticated','atlas.work_item_context_links','SELECT')
     OR has_table_privilege('authenticated','atlas.growing_objects','UPDATE')
  THEN
    RAISE EXCEPTION 'User received a direct canonical Work/physical mutation grant';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint
    WHERE conrelid='atlas.work_item_context_links'::regclass
      AND conname='work_item_context_links_subject_pair_v1'
      AND position('growing_object' in pg_get_constraintdef(oid))>0
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid='atlas.work_item_context_links'::regclass
      AND tgname='work_growing_object_context_guard_v1'
  ) THEN
    RAISE EXCEPTION 'Canonical growing-object link was not admitted/guarded';
  END IF;


  IF to_regprocedure(
      'public.establish_farm_crop_ledger_custody_self_api_v1(uuid,uuid,jsonb)'
    ) IS NULL OR to_regprocedure(
      'public.end_farm_crop_ledger_custody_self_api_v1(uuid,uuid)'
    ) IS NULL OR has_table_privilege(
      'authenticated','atlas.farm_crop_ledger_custody_v1','SELECT'
    ) OR has_table_privilege(
      'authenticated','atlas.farm_crop_ledger_custody_v1','INSERT'
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_class c
      WHERE c.oid='atlas.farm_crop_ledger_custody_v1'::regclass
        AND c.relrowsecurity
    )
  THEN
    RAISE EXCEPTION 'Farm crop to Ledger custody must be private, signed, explicit';
  END IF;
  IF EXISTS (
    SELECT farm_id FROM atlas.farm_crop_ledger_custody_v1
    WHERE custody_state='active' GROUP BY farm_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION 'Ambiguous farm crop custody';
  END IF;
  v_response:=public.establish_farm_crop_ledger_custody_self_api_v1(
    gen_random_uuid(),gen_random_uuid(),
    '{"cropLedgerBoundaryReviewed":true,"authorityDomain":"farm_crop_operations"}'::jsonb
  );
  IF v_response->>'ok' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Unsigned crop custody admission succeeded';
  END IF;
  v_response:=public.end_farm_crop_ledger_custody_self_api_v1(
    gen_random_uuid(),gen_random_uuid()
  );
  IF v_response->>'ok' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Unsigned crop custody retirement succeeded';
  END IF;

  SELECT count(*) INTO v_rows
    FROM atlas.work_item_context_links;
  -- Unauthenticated caller must receive no view into existing scope and
  -- must not establish any physical link.
  v_response := public.work_growing_object_context_review_self_api_v1(
    gen_random_uuid(),gen_random_uuid()
  );
  IF v_response->>'ok' IS DISTINCT FROM 'false'
    OR v_response ? 'candidates' THEN
    RAISE EXCEPTION 'Unsigned physical candidate discovery leak';
  END IF;

  v_response:=public.establish_work_growing_object_context_self_api_v1(
    gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
    jsonb_build_object('humanConfirmed',true)
  );
  IF v_response->>'ok' IS DISTINCT FROM 'false'
    OR v_response ? 'contextId' THEN
    RAISE EXCEPTION 'Unsigned physical-link mutation not denied';
  END IF;
  IF (SELECT count(*) FROM atlas.work_item_context_links)<>v_rows THEN
    RAISE EXCEPTION 'Unauthenticated candidate mutated work links';
  END IF;

  SELECT pg_get_functiondef(v_internal::oid) INTO v_source;
  IF position('principal_has_ledger_authority_v1' in v_source)=0
     OR position('confersAccess' in v_source)=0
     OR position('humanConfirmed' in v_source)=0 THEN
    RAISE EXCEPTION 'Signed governor and non-grant source law is missing';
  END IF;
END
$proof$;
