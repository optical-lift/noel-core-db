-- Disposable clone ONLY; not part of production migration.
-- Demonstrate exact live Ledger onboarding and Reality identity birth in one
-- transaction, including negatives. Synthetic DML is rolled back.
DO $assert_structure$
DECLARE
  v_trigger_count int;
BEGIN
  SELECT count(*) INTO v_trigger_count
  FROM pg_catalog.pg_trigger
  WHERE tgrelid='ledger.ledgers'::regclass
    AND tgname IN (
      'ledger_activation_guard_v1',
      'ledger_binding_context_identity_on_activation_v1',
      'ledger_canonical_context_identity_guard_v1'
    )
    AND NOT tgisinternal
    AND tgenabled='O';

  IF v_trigger_count <> 3 THEN
    RAISE EXCEPTION 'Activation/birth/canonical verification trigger chain incomplete';
  END IF;

  -- Trigger order is lexical. A future rename is a behavioral change.
  IF NOT (
    'ledger_activation_guard_v1' < 'ledger_binding_context_identity_on_activation_v1'
    AND 'ledger_binding_context_identity_on_activation_v1' < 'ledger_canonical_context_identity_guard_v1'
  ) THEN
    RAISE EXCEPTION 'Trigger order contract violated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid='ledger.establish_context_identity_on_activation_v1()'::regprocedure
      AND NOT p.prosecdef
  ) THEN
    RAISE EXCEPTION 'Identity birth must remain SECURITY INVOKER';
  END IF;

  IF has_function_privilege('anon','ledger.establish_context_identity_on_activation_v1()'::regprocedure,'EXECUTE')
    OR has_function_privilege('authenticated','ledger.establish_context_identity_on_activation_v1()'::regprocedure,'EXECUTE')
    OR has_table_privilege('anon','reality.entities','INSERT')
    OR has_table_privilege('authenticated','reality.entities','INSERT')
    OR has_table_privilege('anon','ledger.ledgers','INSERT')
    OR has_table_privilege('authenticated','ledger.ledgers','INSERT') THEN
    RAISE EXCEPTION 'Application role direct identity birth permission detected';
  END IF;
END
$assert_structure$;

DO $prove_atomic_birth$
DECLARE
  v_owner uuid := gen_random_uuid();
  v_practitioner uuid := gen_random_uuid();
  v_ledger1 uuid := gen_random_uuid();
  v_ledger2 uuid := gen_random_uuid();
  v_ledger_denied uuid := gen_random_uuid();
  v_ledger_spoof uuid := gen_random_uuid();
  v_case1 uuid := gen_random_uuid();
  v_case2 uuid := gen_random_uuid();
  v_case_denied uuid := gen_random_uuid();
  v_case_spoof uuid := gen_random_uuid();
  v_context1 uuid;
  v_context2 uuid;
  v_rejected boolean;
BEGIN
  -- The internal exception subtransaction discards ALL synthetic rows
  -- including the real Ledger and Reality rows after the checks complete.
  BEGIN
    INSERT INTO reality.entities (id,stable_key,entity_kind,display_name)
    VALUES
      (v_owner,'synthetic:ledger-owner:'||v_owner::text,'business','Synthetic owner'),
      (v_practitioner,'synthetic:practitioner:'||v_practitioner::text,'person','Synthetic practitioner');

    INSERT INTO ledger.onboarding_cases
      (id,subject_entity_id,desired_ledger_name,onboarding_state,
       case_kind,practitioner_person_entity_id)
    VALUES
      (v_case1,v_owner,'Synthetic Flower Ledger','ready_to_activate',
       'practitioner_onboarding',v_practitioner),
      (v_case2,v_owner,'Synthetic Venue Ledger','ready_to_activate',
       'practitioner_onboarding',v_practitioner),
      (v_case_denied,v_owner,'Synthetic Not Ready Ledger','requested',
       'practitioner_onboarding',v_practitioner),
      (v_case_spoof,v_owner,'Synthetic Spoofed Ledger','ready_to_activate',
       'practitioner_onboarding',v_practitioner);

    INSERT INTO ledger.ledgers
      (id,subject_entity_id,onboarding_case_id,stable_key,name)
    VALUES
      (v_ledger1,v_owner,v_case1,'synthetic:ledger:'||v_ledger1::text,'Synthetic Flower Ledger')
    RETURNING canonical_context_entity_id INTO v_context1;

    INSERT INTO ledger.ledgers
      (id,subject_entity_id,onboarding_case_id,stable_key,name)
    VALUES
      (v_ledger2,v_owner,v_case2,'synthetic:ledger:'||v_ledger2::text,'Synthetic Venue Ledger')
    RETURNING canonical_context_entity_id INTO v_context2;

    IF v_context1 IS NULL OR v_context2 IS NULL OR v_context1=v_context2
      OR v_context1=v_owner OR v_context2=v_owner THEN
      RAISE EXCEPTION 'Each Ledger must acquire its own distinct Reality context';
    END IF;

    IF (SELECT count(*)
        FROM reality.entities
        WHERE id IN (v_context1,v_context2)
          AND entity_kind='ledger_context'
          AND identity_state='canonical'
          AND display_name='Ledger context') <> 2 THEN
      RAISE EXCEPTION 'Missing or privacy-unsafe context identities';
    END IF;

    IF (SELECT stable_key FROM reality.entities WHERE id=v_context1)
         IS DISTINCT FROM ('ledger_context:' || v_ledger1::text)
      OR (SELECT stable_key FROM reality.entities WHERE id=v_context2)
         IS DISTINCT FROM ('ledger_context:' || v_ledger2::text) THEN
      RAISE EXCEPTION 'Context stable keys must match source Ledger UUID';
    END IF;

    IF (SELECT count(*) FROM ledger.onboarding_cases
        WHERE id IN (v_case1,v_case2)
          AND onboarding_state='completed') <> 2 THEN
      RAISE EXCEPTION 'Original onboarding completion did not run';
    END IF;

    -- A refused Ledger must not manufacture a Reality context identity.
    v_rejected := false;
    BEGIN
      INSERT INTO ledger.ledgers
        (id,subject_entity_id,onboarding_case_id,stable_key,name)
      VALUES
        (v_ledger_denied,v_owner,v_case_denied,
         'synthetic:ledger:'||v_ledger_denied::text,'Synthetic Not Ready Ledger');
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN
      RAISE EXCEPTION 'Unready onboarding was accepted';
    END IF;
    IF EXISTS (
      SELECT 1 FROM reality.entities
      WHERE stable_key='ledger_context:'||v_ledger_denied::text
    ) THEN
      RAISE EXCEPTION 'Unready onboarding leaked an identity';
    END IF;

    -- Caller cannot choose or alias a context binding during activation.
    v_rejected := false;
    BEGIN
      INSERT INTO ledger.ledgers
        (id,subject_entity_id,onboarding_case_id,stable_key,name,
         canonical_context_entity_id)
      VALUES
        (v_ledger_spoof,v_owner,v_case_spoof,
         'synthetic:ledger:'||v_ledger_spoof::text,
         'Synthetic Spoofed Ledger',v_context1);
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN
      RAISE EXCEPTION 'Caller-supplied context binding was accepted';
    END IF;
    IF EXISTS (
      SELECT 1 FROM reality.entities
      WHERE stable_key='ledger_context:'||v_ledger_spoof::text
    ) THEN
      RAISE EXCEPTION 'Spoof attempt leaked a second identity';
    END IF;

    -- Force rollback of the successful positive cases as well.
    RAISE EXCEPTION 'Discard all synthetic onboarding and contexts'
      USING ERRCODE='ZX901';
  EXCEPTION WHEN SQLSTATE 'ZX901' THEN
    NULL;
  END;

  IF EXISTS (
    SELECT 1 FROM reality.entities WHERE id IN (v_owner,v_practitioner,v_context1,v_context2)
  ) OR EXISTS (
    SELECT 1 FROM ledger.ledgers WHERE id IN (v_ledger1,v_ledger2)
  ) OR EXISTS (
    SELECT 1 FROM ledger.onboarding_cases WHERE id IN
      (v_case1,v_case2,v_case_denied,v_case_spoof)
  ) THEN
    RAISE EXCEPTION 'Disposable validation left synthetic data behind';
  END IF;
END
$prove_atomic_birth$;

-- Intentionally no write or repair for any pre-existing real Ledger.
