-- Shared Ledger-context identity birth: one governed activation transaction.
-- Source candidate ONLY. Do not apply directly to production.
-- Prerequisite: shared_ledger_context_identity_binding_v1 (20261023030213).
--
-- On INSERT, the existing ledger_activation_guard_v1 verifies and locks the
-- approved onboarding case. Alphabetical BEFORE-trigger order is intentional:
-- activation_guard (a) -> binding_context (b) -> canonical_context (c).
-- Identity birth happens AFTER onboarding authority is checked and BEFORE the
-- existing immutable identity guard verifies the resulting canonical endpoint.
BEGIN;

CREATE FUNCTION ledger.establish_context_identity_on_activation_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $identity$
BEGIN
  IF NEW.id IS NULL THEN
    RAISE EXCEPTION 'Ledger identity must be fixed before context establishment'
      USING errcode = '23514';
  END IF;

  -- No caller may substitute another Ledger's context or invent its own
  -- identity binding. Governed historic reconciliation is a SEPARATE path.
  IF NEW.canonical_context_entity_id IS NOT NULL THEN
    RAISE EXCEPTION 'New Ledger context identity is established by the activation transaction, not supplied by caller'
      USING errcode = '23514';
  END IF;

  -- The context identity is technical addressability for THIS Ledger.
  -- It does not replace the owning business, represent a Person, or grant
  -- any Person a Connection, seat, consent or private record access.
  -- Generic display name avoids projecting private Ledger names into Reality.
  INSERT INTO reality.entities
    (id, stable_key, entity_kind, display_name, identity_state)
  VALUES
    (gen_random_uuid(), 'ledger_context:' || NEW.id::text,
     'ledger_context', 'Ledger context', 'canonical')
  RETURNING id INTO NEW.canonical_context_entity_id;

  RETURN NEW;
END;
$identity$;

-- PostgreSQL fires triggers of the same kind/event in alphabetical name order.
-- Naming matters: activation authority first; context birth second;
-- canonical binding guard third, before the Ledger row is admitted.
CREATE TRIGGER ledger_binding_context_identity_on_activation_v1
BEFORE INSERT ON ledger.ledgers
FOR EACH ROW
EXECUTE FUNCTION ledger.establish_context_identity_on_activation_v1();

REVOKE ALL ON FUNCTION ledger.establish_context_identity_on_activation_v1()
  FROM PUBLIC, anon, authenticated;

-- No new RLS, GRANT, direct application RPC, relationship kind, seats,
-- source-history migration, manual backfill, or personal disclosure.
-- Any failed Ledger activation rolls back the Reality insert in the same
-- PostgreSQL transaction.
COMMIT;
