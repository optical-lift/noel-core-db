-- SRC-ONLY TEST FIXTURE, PostgreSQL 17 disposable synthetic DB.
-- NO user information, credentials, current schema dumps or production access.
-- Schema is intentionally limited to relations consumed by the U2F 02 helper;
-- NOT evidence of passing against the authentic installed Noel schema.
CREATE SCHEMA atlas;
CREATE SCHEMA ledger;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE u2f_synthetic_reader NOLOGIN;

CREATE TABLE atlas.delegated_agent_carriers (
 id uuid PRIMARY KEY,
 status text NOT NULL,
 retired_at timestamptz
);
CREATE TABLE atlas.principals (
 id uuid PRIMARY KEY,
 status text NOT NULL,
 person_id uuid
);
CREATE TABLE ledger.ledgers (
 id uuid PRIMARY KEY,
 ledger_state text NOT NULL,
 retired_at timestamptz
);
CREATE TABLE ledger.seats (
 id uuid PRIMARY KEY,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 person_entity_id uuid NOT NULL,
 seat_state text NOT NULL,
 began_at timestamptz NOT NULL,
 ended_at timestamptz
);
CREATE TABLE atlas.delegated_agent_authorizations (
 id uuid PRIMARY KEY,
 carrier_id uuid NOT NULL REFERENCES atlas.delegated_agent_carriers(id),
 principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 delegating_seat_id uuid REFERENCES ledger.seats(id),
 authorization_state text NOT NULL,
 revoked_at timestamptz,
 begins_at timestamptz NOT NULL,
 ends_at timestamptz
);

-- Fake fixture IDs, not copied from any installation.
INSERT INTO atlas.delegated_agent_carriers VALUES
 ('11111111-1111-4111-8111-111111111111','active',NULL);
INSERT INTO atlas.principals VALUES
 ('22222222-2222-4222-8222-222222222222','active','33333333-3333-4333-8333-333333333333');
INSERT INTO ledger.ledgers VALUES
 ('44444444-4444-4444-8444-444444444444','active',NULL);
INSERT INTO ledger.seats VALUES
 ('55555555-5555-4555-8555-555555555555',
  '44444444-4444-4444-8444-444444444444',
  '33333333-3333-4333-8333-333333333333',
  'active',now()-interval '1 day',NULL);
INSERT INTO atlas.delegated_agent_authorizations VALUES
 ('66666666-6666-4666-8666-666666666666',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  'active',NULL,now()-interval '1 hour',now()+interval '1 day');
