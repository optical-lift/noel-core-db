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

  IF has_table_privilege('authenticated','ledger.ledgers','UPDATE')
    OR has_table_privilege('anon','ledger.ledgers','UPDATE')
    OR has_table_privilege('authenticated','reality.entities','INSERT')
    OR has_table_privilege('anon','reality.entities','INSERT') THEN
    RAISE EXCEPTION 'Anonymous or authenticated identity mutation permission detected';
  END IF;
END
$check$;

-- Forensic negative checks are separately required on the protected clone:
-- wrong entity kind, wrong Ledger key, business-equals-context,
-- multiple Ledgers sharing one context ID, attempted rebinding or changing
-- the bound Reality stable key. Do not run those mutations on production.
