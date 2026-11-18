-- Disposable PostgreSQL 17 fixture for U2F 04 source-provenance inspection.
-- ALL identifiers and rows are fictional, no production copy or privileges.
CREATE SCHEMA atlas;
CREATE SCHEMA ledger;
CREATE SCHEMA reality;
CREATE TABLE atlas.principals (
  id uuid PRIMARY KEY, status text NOT NULL, person_id uuid
);
CREATE TABLE atlas.ledgers (
  id uuid PRIMARY KEY, status text NOT NULL
);
CREATE TABLE atlas.principal_ledger_authorities (
  id uuid PRIMARY KEY, principal_id uuid NOT NULL REFERENCES atlas.principals(id),
  ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
  authority_kind text NOT NULL, status text NOT NULL, ended_at timestamptz
);
CREATE TABLE ledger.ledgers (
  id uuid PRIMARY KEY, subject_entity_id uuid NOT NULL,
  ledger_state text NOT NULL, retired_at timestamptz
);
CREATE TABLE ledger.seats (
  id uuid PRIMARY KEY, ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
  person_entity_id uuid NOT NULL, seat_state text NOT NULL,
  began_at timestamptz NOT NULL, ended_at timestamptz, seat_basis jsonb NOT NULL
);
CREATE TABLE reality.responsibility_relations (
  id uuid PRIMARY KEY, carrier_person_entity_id uuid NOT NULL,
  jurisdiction_kind text NOT NULL, jurisdiction_entity_id uuid,
  relation_state text NOT NULL, began_at timestamptz NOT NULL, ended_at timestamptz
);
INSERT INTO atlas.principals VALUES
 ('22222222-2222-4222-8222-222222222222','active','33333333-3333-4333-8333-333333333333');
INSERT INTO atlas.ledgers VALUES
 ('44444444-4444-4444-8444-444444444444','active');
INSERT INTO atlas.principal_ledger_authorities VALUES
 ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',
  '44444444-4444-4444-8444-444444444444','root_governing','active',NULL);
INSERT INTO ledger.ledgers VALUES
 ('44444444-4444-4444-8444-444444444444','66666666-6666-4666-8666-666666666666','active',NULL);
INSERT INTO ledger.seats VALUES
 ('55555555-5555-4555-8555-555555555555','44444444-4444-4444-8444-444444444444',
  '33333333-3333-4333-8333-333333333333','active',now()-interval '1 day',NULL,
  '{"legacyLedgerAuthorityEvidenceId":"11111111-1111-4111-8111-111111111111"}'::jsonb);
INSERT INTO reality.responsibility_relations VALUES
 ('77777777-7777-4777-8777-777777777777','33333333-3333-4333-8333-333333333333',
  'entity','66666666-6666-4666-8666-666666666666','active',now()-interval '1 day',NULL);
