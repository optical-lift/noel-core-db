-- Fictional five-root source migration SHAPE only. No real source IDs or users.
-- Two of five original roots share one Person/subject but govern different Ledgers.
CREATE SCHEMA atlas;
CREATE SCHEMA ledger;
CREATE TABLE atlas.principals (id uuid PRIMARY KEY, status text NOT NULL, person_id uuid);
CREATE TABLE atlas.ledgers (id uuid PRIMARY KEY, status text NOT NULL);
CREATE TABLE atlas.principal_ledger_authorities (
 id uuid PRIMARY KEY, principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
 authority_kind text NOT NULL, status text NOT NULL,
 basis text NOT NULL, established_at timestamptz NOT NULL, ended_at timestamptz
);
CREATE TABLE ledger.ledgers (
 id uuid PRIMARY KEY, subject_entity_id uuid NOT NULL, ledger_state text NOT NULL, retired_at timestamptz
);
CREATE TABLE ledger.seats (
 id uuid PRIMARY KEY, ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 person_entity_id uuid NOT NULL, seat_state text NOT NULL, began_at timestamptz NOT NULL,
 ended_at timestamptz,seat_basis jsonb NOT NULL
);
CREATE UNIQUE INDEX one_active_person_ledger ON ledger.seats(ledger_id,person_entity_id) WHERE seat_state='active';
CREATE TABLE ledger.seat_responsibilities (
 id uuid PRIMARY KEY,seat_id uuid NOT NULL REFERENCES ledger.seats(id),
 responsibility_key text NOT NULL, responsibility_state text NOT NULL
);

INSERT INTO atlas.principals VALUES ('00000000-0000-4000-8000-000000000101','active','00000000-0000-4000-8000-000000000201');
INSERT INTO atlas.principals VALUES ('00000000-0000-4000-8000-000000000102','active','00000000-0000-4000-8000-000000000202');
INSERT INTO atlas.principals VALUES ('00000000-0000-4000-8000-000000000103','active','00000000-0000-4000-8000-000000000203');
INSERT INTO atlas.principals VALUES ('00000000-0000-4000-8000-000000000104','active','00000000-0000-4000-8000-000000000204');
INSERT INTO atlas.ledgers VALUES ('00000000-0000-4000-8000-000000000301','active');
INSERT INTO ledger.ledgers VALUES ('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000401','active',NULL);
INSERT INTO atlas.principal_ledger_authorities VALUES ('00000000-0000-4000-8000-000000000501','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000301','root_governing','active','legacy_source_1',now()-interval '60 days',NULL);
INSERT INTO ledger.seats VALUES ('00000000-0000-4000-8000-000000000601','00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000201','active',now()-interval '2 days',NULL,'{"legacyLedgerAuthorityEvidenceId":"00000000-0000-4000-8000-000000000501"}'::jsonb);
INSERT INTO atlas.ledgers VALUES ('00000000-0000-4000-8000-000000000302','active');
INSERT INTO ledger.ledgers VALUES ('00000000-0000-4000-8000-000000000302','00000000-0000-4000-8000-000000000401','active',NULL);
INSERT INTO atlas.principal_ledger_authorities VALUES ('00000000-0000-4000-8000-000000000502','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000302','root_governing','active','legacy_source_2',now()-interval '60 days',NULL);
INSERT INTO ledger.seats VALUES ('00000000-0000-4000-8000-000000000602','00000000-0000-4000-8000-000000000302','00000000-0000-4000-8000-000000000201','active',now()-interval '2 days',NULL,'{"legacyLedgerAuthorityEvidenceId":"00000000-0000-4000-8000-000000000502"}'::jsonb);
INSERT INTO atlas.ledgers VALUES ('00000000-0000-4000-8000-000000000303','active');
INSERT INTO ledger.ledgers VALUES ('00000000-0000-4000-8000-000000000303','00000000-0000-4000-8000-000000000402','active',NULL);
INSERT INTO atlas.principal_ledger_authorities VALUES ('00000000-0000-4000-8000-000000000503','00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000303','root_governing','active','legacy_source_3',now()-interval '60 days',NULL);
INSERT INTO ledger.seats VALUES ('00000000-0000-4000-8000-000000000603','00000000-0000-4000-8000-000000000303','00000000-0000-4000-8000-000000000202','active',now()-interval '2 days',NULL,'{"legacyLedgerAuthorityEvidenceId":"00000000-0000-4000-8000-000000000503"}'::jsonb);
INSERT INTO atlas.ledgers VALUES ('00000000-0000-4000-8000-000000000304','active');
INSERT INTO ledger.ledgers VALUES ('00000000-0000-4000-8000-000000000304','00000000-0000-4000-8000-000000000403','active',NULL);
INSERT INTO atlas.principal_ledger_authorities VALUES ('00000000-0000-4000-8000-000000000504','00000000-0000-4000-8000-000000000103','00000000-0000-4000-8000-000000000304','root_governing','active','legacy_source_4',now()-interval '60 days',NULL);
INSERT INTO ledger.seats VALUES ('00000000-0000-4000-8000-000000000604','00000000-0000-4000-8000-000000000304','00000000-0000-4000-8000-000000000203','active',now()-interval '2 days',NULL,'{}'::jsonb);
INSERT INTO atlas.ledgers VALUES ('00000000-0000-4000-8000-000000000305','active');
INSERT INTO ledger.ledgers VALUES ('00000000-0000-4000-8000-000000000305','00000000-0000-4000-8000-000000000404','active',NULL);
INSERT INTO atlas.principal_ledger_authorities VALUES ('00000000-0000-4000-8000-000000000505','00000000-0000-4000-8000-000000000104','00000000-0000-4000-8000-000000000305','root_governing','active','legacy_source_5',now()-interval '60 days',NULL);
INSERT INTO ledger.seats VALUES ('00000000-0000-4000-8000-000000000605','00000000-0000-4000-8000-000000000305','00000000-0000-4000-8000-000000000204','active',now()-interval '2 days',NULL,'{}'::jsonb);
INSERT INTO atlas.principal_ledger_authorities VALUES ('00000000-0000-4000-8000-000000000506','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000301','root_governing','ended','historical_ended_source',now()-interval '100 days',now()-interval '70 days');
