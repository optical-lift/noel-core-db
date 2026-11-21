-- Disposable synthetic-only PostgreSQL 17 fixtures.
-- Fake identities; none copied from the current Supabase project.
CREATE SCHEMA atlas;
CREATE SCHEMA ledger;
CREATE SCHEMA reality;

CREATE TABLE atlas.ledgers (id uuid PRIMARY KEY,status text NOT NULL);
CREATE TABLE atlas.organizations (id uuid PRIMARY KEY,status text NOT NULL);
CREATE TABLE atlas.ledger_organization_participations (
 ledger_id uuid,organization_id uuid,participation_kind text,
 is_compatibility_primary boolean,status text,ended_at timestamptz
);
CREATE TABLE atlas.principals (
 id uuid PRIMARY KEY,person_id uuid,status text
);
CREATE TABLE atlas.principal_ledger_authorities (
 id uuid PRIMARY KEY,principal_id uuid,ledger_id uuid,authority_kind text,
 status text,ended_at timestamptz
);
CREATE TABLE reality.entities (
 id uuid PRIMARY KEY,entity_kind text,identity_state text
);
CREATE TABLE ledger.onboarding_cases (
 id uuid PRIMARY KEY,case_kind text,onboarding_basis jsonb,
 onboarding_state text,subject_entity_id uuid
);
CREATE TABLE ledger.ledgers (
 id uuid PRIMARY KEY,ledger_state text,retired_at timestamptz,
 onboarding_case_id uuid
);
CREATE TABLE ledger.seats (
 id uuid PRIMARY KEY,ledger_id uuid,person_entity_id uuid,
 seat_state text,began_at timestamptz,ended_at timestamptz
);

INSERT INTO atlas.ledgers VALUES
 ('11111111-1111-4111-8111-111111111111','active');
INSERT INTO atlas.organizations VALUES
 ('22222222-2222-4222-8222-222222222222','active');
INSERT INTO atlas.ledger_organization_participations VALUES
 ('11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'governing',true,'active',NULL);
INSERT INTO atlas.principals VALUES
 ('33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444','active');
INSERT INTO atlas.principal_ledger_authorities VALUES
 ('55555555-5555-4555-8555-555555555555',
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'root_governing','active',NULL);
