-- Clone-only postconditions. Never execute on the live database.
-- This candidate is a signed READ membrane only; it never creates a Ledger.
DO $check$
DECLARE
  v_internal regprocedure := to_regprocedure(
    'atlas.native_ledger_activation_preflight_self_api_v1(uuid)'
  );
  v_public regprocedure := to_regprocedure(
    'public.native_ledger_activation_preflight_self_api_v1(uuid)'
  );
  v_internal_oid oid;
  v_public_oid oid;
  v_result jsonb;
  v_before_ledgers bigint;
  v_before_contexts bigint;
  v_before_seats bigint;
BEGIN
  IF v_internal IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Signed native Ledger preflight contract is absent';
  END IF;
  SELECT p.oid INTO v_internal_oid FROM pg_proc p WHERE p.oid=v_internal::oid;
  SELECT p.oid INTO v_public_oid FROM pg_proc p WHERE p.oid=v_public::oid;
  IF NOT (SELECT p.prosecdef AND p.provolatile='s'
          FROM pg_proc p WHERE p.oid=v_internal_oid)
     OR NOT (SELECT p.prosecdef AND p.provolatile='s'
             FROM pg_proc p WHERE p.oid=v_public_oid) THEN
    RAISE EXCEPTION 'Signed preflight must remain stable and definer-gated';
  END IF;
  IF has_function_privilege('anon',v_public_oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_public_oid,'EXECUTE')
     OR has_function_privilege('authenticated',v_internal_oid,'EXECUTE')
     OR has_function_privilege('anon',v_internal_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Signed private/public RPC execution privileges are unsafe';
  END IF;
  IF has_table_privilege('authenticated','ledger.ledgers','INSERT')
     OR has_table_privilege('authenticated','ledger.onboarding_cases','INSERT')
     OR has_table_privilege('authenticated','reality.entities','INSERT') THEN
    RAISE EXCEPTION 'Authenticated user received unexpected canonical write grants';
  END IF;

  SELECT count(*) INTO v_before_ledgers FROM ledger.ledgers;
  SELECT count(*) INTO v_before_contexts
  FROM reality.entities WHERE entity_kind='ledger_context';
  SELECT count(*) INTO v_before_seats FROM ledger.seats;

  -- This probe has no JWT identity. It must fail closed before case discovery.
  v_result:=public.native_ledger_activation_preflight_self_api_v1(
    gen_random_uuid()
  );
  IF v_result->>'ok'<>'false'
     OR v_result->>'code'<>'practitioner_authority_required' THEN
    RAISE EXCEPTION 'Unsigned activation preflight was not rejected';
  END IF;

  IF (SELECT count(*) FROM ledger.ledgers)<>v_before_ledgers
     OR (SELECT count(*) FROM reality.entities
         WHERE entity_kind='ledger_context')<>v_before_contexts
     OR (SELECT count(*) FROM ledger.seats)<>v_before_seats THEN
    RAISE EXCEPTION 'Read-only preflight mutated canonical records';
  END IF;

  IF position('canActivate' in pg_get_functiondef(v_internal_oid))=0
     OR position('runtime_proof_not_verified' in
                 pg_get_functiondef(v_internal_oid))=0
     OR position('signed_native_activation_command_not_released' in
                 pg_get_functiondef(v_internal_oid))=0 THEN
    RAISE EXCEPTION 'Preview lost its fail-closed incomplete-proof boundary';
  END IF;
END
$check$;
