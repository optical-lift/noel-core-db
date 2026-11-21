-- U2F fictional test-only HTTP bridge source shape; NEVER live data.
-- Uses existing isolated PG17 synthetic tables plus fabricated C1 UUID values.
\ir root_lifecycle_fixture.sql
CREATE TABLE auth.users (id uuid PRIMARY KEY);
INSERT INTO auth.users (id) VALUES
 ('e5200000-0000-4000-8000-000000000001'),
 ('e5200000-0000-4000-8000-000000000002'),
 ('e5200000-0000-4000-8000-000000000003'),
 ('e5200000-0000-4000-8000-000000000004');

INSERT INTO atlas.principals (id,status,person_id,user_id) VALUES
 ('e5200000-0000-4000-8000-000000000111','active',
  'e5200000-0000-4000-8000-000000000101',
  'e5200000-0000-4000-8000-000000000001'),
 ('e5200000-0000-4000-8000-000000000112','active',
  'e5200000-0000-4000-8000-000000000102',
  'e5200000-0000-4000-8000-000000000002');

INSERT INTO atlas.ledgers (id,status) VALUES
 ('e5200000-0000-4000-8000-000000000401','active'),
 ('e5200000-0000-4000-8000-000000000402','active');
INSERT INTO ledger.ledgers (id,subject_entity_id,ledger_state,retired_at) VALUES
 ('e5200000-0000-4000-8000-000000000401',
  'e5200000-0000-4000-8000-000000000201','active',NULL),
 ('e5200000-0000-4000-8000-000000000402',
  'e5200000-0000-4000-8000-000000000201','active',NULL);
INSERT INTO ledger.seats (
 id,ledger_id,person_entity_id,seat_state,began_at,ended_at,seat_basis
) VALUES
 ('e5200000-0000-4000-8000-000000000501',
  'e5200000-0000-4000-8000-000000000401',
  'e5200000-0000-4000-8000-000000000101','active',
  now()-interval '1 day',NULL,'{"synthetic":true}'::jsonb),
 ('e5200000-0000-4000-8000-000000000504',
  'e5200000-0000-4000-8000-000000000402',
  'e5200000-0000-4000-8000-000000000102','active',
  now()-interval '1 day',NULL,'{"synthetic":true}'::jsonb);
INSERT INTO atlas.principal_ledger_authorities (
 id,principal_id,ledger_id,authority_kind,status,basis,established_at,ended_at
) VALUES
 ('e5200000-0000-4000-8000-000000000601',
  'e5200000-0000-4000-8000-000000000111',
  'e5200000-0000-4000-8000-000000000401',
  'root_governing','active','fictional-origin-A',now()-interval '10 days',NULL),
 ('e5200000-0000-4000-8000-000000000602',
  'e5200000-0000-4000-8000-000000000112',
  'e5200000-0000-4000-8000-000000000402',
  'root_governing','active','fictional-origin-B',now()-interval '10 days',NULL);
INSERT INTO auth.sessions (id,user_id,not_after) VALUES
 ('e5200000-0000-4000-8000-000000000011',
  'e5200000-0000-4000-8000-000000000001',now()+interval '1 day'),
 ('e5200000-0000-4000-8000-000000000012',
  'e5200000-0000-4000-8000-000000000002',now()+interval '1 day');
