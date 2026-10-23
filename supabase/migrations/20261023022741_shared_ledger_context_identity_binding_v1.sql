-- Shared structural contract: Ledger context becomes an independently
-- addressable canonical Reality entity. Not a relationship or access grant.
-- Existing Ledgers remain unbound until separately adjudicated and backfilled.
BEGIN;

ALTER TABLE ledger.ledgers
  ADD COLUMN canonical_context_entity_id uuid;

ALTER TABLE ledger.ledgers
  ADD CONSTRAINT ledger_ledgers_canonical_context_entity_fk
  FOREIGN KEY (canonical_context_entity_id)
  REFERENCES reality.entities(id) ON DELETE RESTRICT;

ALTER TABLE ledger.ledgers
  ADD CONSTRAINT ledger_ledgers_canonical_context_entity_unique
  UNIQUE (canonical_context_entity_id);

-- The stable key is an opaque, original-Ledger-specific identity anchor.
-- No business display name or personal health content is embedded in it.
CREATE FUNCTION ledger.guard_canonical_context_identity_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $guard$
DECLARE
  v_kind text;
  v_state text;
  v_stable_key text;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.canonical_context_entity_id IS NOT NULL
     AND (
       NEW.canonical_context_entity_id IS DISTINCT FROM OLD.canonical_context_entity_id
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.subject_entity_id IS DISTINCT FROM OLD.subject_entity_id
     )
  THEN
    RAISE EXCEPTION 'Canonical Ledger context binding is immutable pending governed reconciliation'
      USING errcode='23514';
  END IF;

  IF NEW.canonical_context_entity_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.canonical_context_entity_id = NEW.subject_entity_id THEN
    RAISE EXCEPTION 'Ledger context identity cannot equal owning business identity'
      USING errcode='23514';
  END IF;

  SELECT e.entity_kind,e.identity_state,e.stable_key
  INTO v_kind,v_state,v_stable_key
  FROM reality.entities e
  WHERE e.id=NEW.canonical_context_entity_id;

  IF v_kind IS DISTINCT FROM 'ledger_context'
     OR v_state IS DISTINCT FROM 'canonical'
     OR v_stable_key IS DISTINCT FROM
       ('ledger_context:' || NEW.id::text) THEN
    RAISE EXCEPTION 'Canonical context entity must match the exact Ledger and be independently canonical'
      USING errcode='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER ledger_canonical_context_identity_guard_v1
BEFORE INSERT OR UPDATE OF id,subject_entity_id,canonical_context_entity_id
ON ledger.ledgers
FOR EACH ROW
EXECUTE FUNCTION ledger.guard_canonical_context_identity_v1();

-- Guard the underlying Reality kind and stable identity once bound.
-- Dispute/retirement remains a separate Reality identity-state decision;
-- a future relationship command must refuse noncanonical endpoints.
CREATE FUNCTION reality.guard_bound_ledger_context_kind_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $guard$
BEGIN
  IF (NEW.entity_kind IS DISTINCT FROM OLD.entity_kind
      OR NEW.stable_key IS DISTINCT FROM OLD.stable_key)
     AND EXISTS (
       SELECT 1 FROM ledger.ledgers l
       WHERE l.canonical_context_entity_id=OLD.id
     )
  THEN
    RAISE EXCEPTION 'Bound Ledger context kind and identity are immutable'
      USING errcode='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER reality_bound_ledger_context_kind_guard_v1
BEFORE UPDATE OF entity_kind,stable_key
ON reality.entities
FOR EACH ROW
EXECUTE FUNCTION reality.guard_bound_ledger_context_kind_v1();

-- Trigger functions are never standalone application APIs.
REVOKE ALL ON FUNCTION ledger.guard_canonical_context_identity_v1()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION reality.guard_bound_ledger_context_kind_v1()
  FROM PUBLIC, anon, authenticated;

-- Deliberately no Ledger row UPDATE, Reality entity INSERT, relationship
-- establishment, public RPC, RLS policy or expanded role grant.
COMMIT;
