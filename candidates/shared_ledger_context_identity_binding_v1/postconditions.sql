-- Phase-1 contract postconditions (disposable production-schema clone).
DO $check$
DECLARE
  v_att int;
  v_unique int;
  v_fk int;
  v_triggers int;
BEGIN
  SELECT count(*) INTO v_att
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid='ledger.ledgers'::regclass
    AND a.attname='canonical_context_entity_id'
    AND a.atttypid='uuid'::regtype
    AND NOT a.attisdropped;
  IF v_att<>1 THEN RAISE EXCEPTION 'Canonical Ledger context column missing'; END IF;

  SELECT count(*) INTO v_unique
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='ledger.ledgers'::regclass
    AND c.conname='ledger_ledgers_canonical_context_entity_unique'
    AND c.contype='u';

  SELECT count(*) INTO v_fk
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid='ledger.ledgers'::regclass
    AND c.conname='ledger_ledgers_canonical_context_entity_fk'
    AND c.contype='f'
    AND c.confrelid='reality.entities'::regclass;
  IF v_unique<>1 OR v_fk<>1 THEN
    RAISE EXCEPTION 'One-to-one Ledger context FK/unique contract missing';
  END IF;

  SELECT count(*) INTO v_triggers
  FROM pg_catalog.pg_trigger t
  WHERE NOT t.tgisinternal AND (
    (t.tgrelid='ledger.ledgers'::regclass
     AND t.tgname='ledger_canonical_context_identity_guard_v1')
    OR (t.tgrelid='reality.entities'::regclass
     AND t.tgname='reality_bound_ledger_context_kind_guard_v1')
  );
  IF v_triggers<>2 THEN RAISE EXCEPTION 'Identity guards missing'; END IF;
  IF EXISTS(SELECT 1 FROM ledger.ledgers
    WHERE canonical_context_entity_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Migration must not backfill any real Ledger identities';
  END IF;

  IF has_function_privilege('authenticated',
       'ledger.guard_canonical_context_identity_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'ledger.guard_canonical_context_identity_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('authenticated',
       'reality.guard_bound_ledger_context_kind_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'reality.guard_bound_ledger_context_kind_v1()'::regprocedure,'EXECUTE')
  THEN RAISE EXCEPTION 'Trigger helpers cannot be invoked as application functions'; END IF;

  IF has_table_privilege('authenticated','ledger.ledgers','UPDATE')
    OR has_table_privilege('anon','ledger.ledgers','UPDATE')
    OR has_table_privilege('authenticated','reality.entities','INSERT')
    OR has_table_privilege('anon','reality.entities','INSERT') THEN
    RAISE EXCEPTION 'Anonymous or authenticated identity mutation permission detected';
  END IF;
END
$check$;

-- NEGATIVE TESTS: these are procedural postconditions, not data-setup
-- fixtures. The clone harness applies postconditions AFTER candidate DDL.
-- This DO block must run only in the disposable clone validation path.
DO $test$
DECLARE
  v_ledger uuid := gen_random_uuid();
  v_second_ledger uuid := gen_random_uuid();
  v_kind_ledger uuid := gen_random_uuid();
  v_disputed_ledger uuid := gen_random_uuid();
  v_business uuid := gen_random_uuid();
  v_other_business uuid := gen_random_uuid();
  v_context uuid := gen_random_uuid();
  v_wrong_context uuid := gen_random_uuid();
  v_noncanonical uuid := gen_random_uuid();
  v_wrong_kind uuid := gen_random_uuid();
  v_rejected boolean;
BEGIN
  BEGIN
    INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state)
    VALUES
      (v_business,'test:owner:'||v_business::text,'business','Synthetic owner','canonical'),
      (v_other_business,'test:owner:'||v_other_business::text,'business','Synthetic second owner','canonical'),
      (v_context,'ledger_context:'||v_ledger::text,'ledger_context','Synthetic Ledger context','canonical'),
      (v_wrong_context,'ledger_context:'||v_second_ledger::text,'ledger_context','Synthetic other Ledger context','canonical'),
      (v_noncanonical,'ledger_context:'||v_disputed_ledger::text,'ledger_context','Synthetic disputed context','disputed'),
      (v_wrong_kind,'ledger_context:'||v_kind_ledger::text,'business','Synthetic wrong kind','canonical');

    CREATE TEMP TABLE _canonical_ledger_probe (
      id uuid PRIMARY KEY,
      subject_entity_id uuid NOT NULL,
      canonical_context_entity_id uuid UNIQUE
    ) ON COMMIT DROP;
    CREATE TRIGGER ledger_canonical_context_identity_guard_v1
      BEFORE INSERT OR UPDATE OF id,subject_entity_id,canonical_context_entity_id
      ON pg_temp._canonical_ledger_probe
      FOR EACH ROW EXECUTE FUNCTION ledger.guard_canonical_context_identity_v1();

    INSERT INTO pg_temp._canonical_ledger_probe
      (id,subject_entity_id,canonical_context_entity_id)
    VALUES (v_ledger,v_business,v_context);

    -- Attempt to attach a Ledger's context identity to a different Ledger.
    v_rejected := false;
    BEGIN
      INSERT INTO pg_temp._canonical_ledger_probe
        (id,subject_entity_id,canonical_context_entity_id)
      VALUES(v_second_ledger,v_business,v_context);
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Cross-Ledger context identity accepted'; END IF;

    -- Explicitly wrong canonical entity kind must not be accepted.
    v_rejected := false;
    BEGIN
      INSERT INTO pg_temp._canonical_ledger_probe
        (id,subject_entity_id,canonical_context_entity_id)
      VALUES(v_kind_ledger,v_business,v_wrong_kind);
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Wrong Reality entity kind accepted'; END IF;

    -- A disputed identity cannot be promoted as canonical just by binding.
    v_rejected := false;
    BEGIN
      INSERT INTO pg_temp._canonical_ledger_probe
        (id,subject_entity_id,canonical_context_entity_id)
      VALUES(v_disputed_ledger,v_business,v_noncanonical);
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Disputed Reality context accepted'; END IF;

    -- Canonical Ledger identity and owning business may not be the same.
    v_rejected := false;
    BEGIN
      INSERT INTO pg_temp._canonical_ledger_probe
        (id,subject_entity_id,canonical_context_entity_id)
      VALUES(v_second_ledger,v_wrong_context,v_wrong_context);
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Context-business identity alias accepted'; END IF;

    -- Once established, existing context/ownership cannot be silently moved.
    v_rejected := false;
    BEGIN
      UPDATE pg_temp._canonical_ledger_probe
        SET canonical_context_entity_id=v_wrong_context
      WHERE id=v_ledger;
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Rebinding accepted'; END IF;

    v_rejected := false;
    BEGIN
      UPDATE pg_temp._canonical_ledger_probe
        SET subject_entity_id=v_other_business
      WHERE id=v_ledger;
    EXCEPTION WHEN check_violation THEN v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Silent owning-business substitution accepted'; END IF;

    -- No actual data or temporary test objects survive this test.
    RAISE EXCEPTION 'Synthetic identity probe rolled back' USING ERRCODE='ZZ001';
  EXCEPTION WHEN SQLSTATE 'ZZ001' THEN
    NULL;
  END;
END
$test$;

-- The bound Reality stable-key trigger needs real Ledger bindings, which
-- are deliberately not created in this Phase-1 migration. That additional
-- proof stays held for the separate adjudication/binding stage.
