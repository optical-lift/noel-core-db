-- SYNTHETIC LOCAL SOURCE-SHAPE EXTENSION ONLY.
-- NOT production DDL, NOT a migration, NOT evidence of canonical clone.
-- Execute after signed_local_fixture.sql to exercise a positive clone-mode
-- adapter path locally, without copying the real production schema.
CREATE TABLE atlas.organizations (
  id uuid PRIMARY KEY, stable_key text NOT NULL UNIQUE,
  name text NOT NULL, status text NOT NULL DEFAULT 'active'
);
CREATE TABLE atlas.organization_ledger_entries(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
  ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
  event_key text NOT NULL,
  source_domain text NOT NULL,
  semantic_type text NOT NULL,
  occurred_at timestamptz NOT NULL,
  title text NOT NULL,
  UNIQUE (organization_id,event_key)
);
ALTER TABLE atlas.ledgers
 ADD COLUMN organization_id uuid REFERENCES atlas.organizations(id) ON DELETE RESTRICT;
-- Presence of these relations only satisfies the narrow shape preflight.
-- It intentionally does not emulate all Noel organization, historical,
-- authority, trigger, policy or published/source constraints.
