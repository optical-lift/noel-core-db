-- Disposable PostgreSQL 17 fixture: synthetic IDs only; no real people, records or credentials.
CREATE SCHEMA atlas;
CREATE SCHEMA ledger;
CREATE TABLE atlas.organizations(
 id uuid PRIMARY KEY,stable_key text NOT NULL UNIQUE,name text NOT NULL,
 status text NOT NULL,onboarding_state text NOT NULL,created_at timestamptz NOT NULL,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE atlas.ledgers(
 id uuid PRIMARY KEY, stable_key text NOT NULL UNIQUE,name text NOT NULL,
 status text NOT NULL,ledger_kind text NOT NULL,organization_id uuid REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL,metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE atlas.ledger_organization_participations(
 id uuid PRIMARY KEY,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 participation_kind text NOT NULL,is_compatibility_primary boolean NOT NULL,
 status text NOT NULL,ended_at timestamptz
);
CREATE TABLE atlas.principal_ledger_authorities(
 id uuid PRIMARY KEY,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 authority_kind text NOT NULL,status text NOT NULL,ended_at timestamptz
);
CREATE TABLE atlas.farms(id uuid PRIMARY KEY,organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT);
CREATE TABLE atlas.nonfk_seat_probe(id uuid PRIMARY KEY,organization_id uuid NOT NULL);
CREATE TABLE atlas.organization_ledger_subjects(subject_id text NOT NULL);
CREATE TABLE ledger.ledgers(id uuid PRIMARY KEY);
CREATE TABLE ledger.onboarding_cases(onboarding_basis jsonb NOT NULL);
INSERT INTO atlas.organizations(id,stable_key,name,status,onboarding_state,created_at,metadata) VALUES
('10000000-0000-4000-8000-000000000001','feast_guild','Feast Guild','active','new','2026-09-14 00:42:45+00','{"canonicalInstitution":"Feast Guild"}'),
('10000000-0000-4000-8000-000000000002','elm_farm','Elm Farm','active','completed','2026-09-14 00:42:45+00','{"canonicalInstitution":"Elm Farm"}');
INSERT INTO atlas.ledgers(id,stable_key,name,status,ledger_kind,organization_id,created_at,metadata) VALUES
('20000000-0000-4000-8000-000000000001','feast_guild','Feast Guild','active','governed_reality',null,'2026-09-14 00:42:45+00','{"canonicalEndeavor":"Feast Guild"}'),
('20000000-0000-4000-8000-000000000002','elm_farm','Elm Farm','active','governed_reality',null,'2026-09-14 00:42:45+00','{"canonicalEndeavor":"Elm Farm"}');
INSERT INTO atlas.ledger_organization_participations VALUES
('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000001','governing',true,'active',null),
('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',
 '10000000-0000-4000-8000-000000000002','governing',true,'active',null);
INSERT INTO atlas.principal_ledger_authorities VALUES
('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','root_governing','active',null),
('40000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','root_governing','active',null);
