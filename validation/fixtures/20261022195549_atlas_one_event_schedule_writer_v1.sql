-- DISPOSABLE DATABASE CLONE ONLY. Never apply synthetic principals to production.
-- All identities, addresses, labels, and occurrences are artificial.

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
VALUES
 ('f5210000-0000-4000-8000-000000000001','atlas-date-proof-org-f521','organization','Synthetic Date Institution'),
 ('f5210000-0000-4000-8000-000000000002','atlas-date-proof-included-f521','person','Synthetic Authorized Person'),
 ('f5210000-0000-4000-8000-000000000003','atlas-date-proof-outsider-f521','person','Synthetic Unconnected Person'),
 ('f5210000-0000-4000-8000-000000000004','atlas-date-proof-governor-f521','person','Synthetic Root Governor');

INSERT INTO atlas.organizations(id,stable_key,name)
VALUES ('f5210000-0000-4000-8000-000000000010','atlas-date-proof-organization-f521','Synthetic Date Institution');

INSERT INTO atlas.farms(id,stable_key,name,organization_id)
VALUES ('f5210000-0000-4000-8000-000000000011','atlas-date-proof-farm-f521','Synthetic Farm',
  'f5210000-0000-4000-8000-000000000010');

INSERT INTO atlas.community_programs(id,farm_id,stable_key,title)
VALUES ('f5210000-0000-4000-8000-000000000012','f5210000-0000-4000-8000-000000000011',
  'atlas-date-proof-program-f521','Synthetic Program');

INSERT INTO ledger.onboarding_cases(id,subject_entity_id,practitioner_person_entity_id,desired_ledger_name,onboarding_state)
VALUES ('f5210000-0000-4000-8000-000000000013','f5210000-0000-4000-8000-000000000001',
  'f5210000-0000-4000-8000-000000000002','Synthetic Date Ledger','ready_to_activate');

INSERT INTO ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name)
VALUES ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000001',
  'f5210000-0000-4000-8000-000000000013','atlas-date-proof-ledger-f521','Synthetic Date Ledger');

INSERT INTO atlas.ledgers(id,stable_key,organization_id,name)
VALUES ('f5210000-0000-4000-8000-000000000014','atlas-date-proof-ledger-f521',
  'f5210000-0000-4000-8000-000000000010','Synthetic Date Ledger');

INSERT INTO atlas.ledger_organization_participations(ledger_id,organization_id,participation_kind,status)
VALUES ('f5210000-0000-4000-8000-000000000014',
  'f5210000-0000-4000-8000-000000000010','operating','active');

-- Two independent occurrences have the SAME local date; third is canonically
-- dated later but its operational overlay asserts the requested local date.
INSERT INTO local_intel.occurrences(id,stable_key,title,occurrence_type,start_at,end_at,status)
VALUES
 ('f5210000-0000-4000-8000-000000000101','atlas-date-proof-occurrence-a-f521',
  'Synthetic Harvest Gathering','community_event','2030-10-30 23:00+00','2030-10-31 01:00+00','scheduled'),
 ('f5210000-0000-4000-8000-000000000102','atlas-date-proof-occurrence-b-f521',
  'Synthetic Early Movement','community_event','2030-10-30 13:00+00','2030-10-30 14:00+00','scheduled'),
 ('f5210000-0000-4000-8000-000000000103','atlas-date-proof-occurrence-c-f521',
  'Synthetic Later Gathering','community_event','2030-11-01 16:00+00',NULL,'planned');

INSERT INTO ledger.occurrence_calendar_bindings(ledger_id,occurrence_id,binding_state)
VALUES
 ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000101','active'),
 ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000102','active'),
 ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000103','active');

INSERT INTO atlas.organization_occurrence_bindings(id,organization_id,occurrence_id,binding_state)
VALUES
 ('f5210000-0000-4000-8000-000000000201','f5210000-0000-4000-8000-000000000010',
   'f5210000-0000-4000-8000-000000000101','active'),
 ('f5210000-0000-4000-8000-000000000202','f5210000-0000-4000-8000-000000000010',
   'f5210000-0000-4000-8000-000000000102','active'),
 ('f5210000-0000-4000-8000-000000000203','f5210000-0000-4000-8000-000000000010',
   'f5210000-0000-4000-8000-000000000103','active');

INSERT INTO atlas.community_events(
 id,farm_id,program_id,stable_key,title,event_kind,event_date,
 start_local_time,end_local_time,timezone_name,status,occurrence_binding_id)
VALUES
 ('f5210000-0000-4000-8000-000000000301',
  'f5210000-0000-4000-8000-000000000011','f5210000-0000-4000-8000-000000000012',
  'atlas-date-proof-community-a-f521','Synthetic Bonfire Evening','community_event',
  '2030-10-30','16:00','20:00','America/Chicago','planned',
  'f5210000-0000-4000-8000-000000000201'),
 ('f5210000-0000-4000-8000-000000000302',
  'f5210000-0000-4000-8000-000000000011','f5210000-0000-4000-8000-000000000012',
  'atlas-date-proof-community-b-f521','Synthetic Early Movement','community_event',
  '2030-10-30','08:00','09:00','America/Chicago','scheduled',
  'f5210000-0000-4000-8000-000000000202'),
 ('f5210000-0000-4000-8000-000000000303',
  'f5210000-0000-4000-8000-000000000011','f5210000-0000-4000-8000-000000000012',
  'atlas-date-proof-community-c-f521','Synthetic Later Gathering','community_event',
  '2030-10-30','11:00','12:00','America/Chicago','planned',
  'f5210000-0000-4000-8000-000000000203');

-- Same canonical Occurrence, but this extra Organization assertion is owner-only.
-- An authenticated ordinary Ledger seat must not see its title or its existence.
INSERT INTO atlas.community_events(
 id,farm_id,program_id,stable_key,title,event_kind,event_date,
 start_local_time,end_local_time,timezone_name,status,visibility_scope,occurrence_binding_id)
VALUES (
 'f5210000-0000-4000-8000-000000000304',
 'f5210000-0000-4000-8000-000000000011',
 'f5210000-0000-4000-8000-000000000012',
 'atlas-date-proof-restricted-a-f521','Synthetic Restricted Owner Planning',
 'community_event','2030-10-30','14:00','15:00','America/Chicago','planned','owner',
 'f5210000-0000-4000-8000-000000000201');

INSERT INTO auth.users(id,instance_id,aud,role,email,created_at,updated_at)
VALUES
 ('f5210000-0000-4000-8000-000000000401','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-date-proof-1@example.invalid',now(),now()),
 ('f5210000-0000-4000-8000-000000000402','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-date-proof-2@example.invalid',now(),now()),
 ('f5210000-0000-4000-8000-000000000403','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-date-proof-3@example.invalid',now(),now());

INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
VALUES
 ('f5210000-0000-4000-8000-000000000411','f5210000-0000-4000-8000-000000000401',now(),now()),
 ('f5210000-0000-4000-8000-000000000412','f5210000-0000-4000-8000-000000000402',now(),now()),
 ('f5210000-0000-4000-8000-000000000413','f5210000-0000-4000-8000-000000000403',now(),now());

INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state)
VALUES
 ('f5210000-0000-4000-8000-000000000401','f5210000-0000-4000-8000-000000000002','active'),
 ('f5210000-0000-4000-8000-000000000402','f5210000-0000-4000-8000-000000000003','active'),
 ('f5210000-0000-4000-8000-000000000403','f5210000-0000-4000-8000-000000000004','active');

-- Identity admission can establish a Personal Atlas first.
-- Insert a synthetic native Atlas only for a Person without one.
-- This remains ordinary fixture data setup, not schema/privilege logic.
INSERT INTO personal.atlases(person_entity_id,atlas_state,native)
SELECT seeded.person_entity_id, 'active', true
FROM (VALUES
 ('f5210000-0000-4000-8000-000000000002'::uuid),
 ('f5210000-0000-4000-8000-000000000003'::uuid),
 ('f5210000-0000-4000-8000-000000000004'::uuid)
) AS seeded(person_entity_id)
WHERE NOT EXISTS (
 SELECT 1 FROM personal.atlases existing
 WHERE existing.person_entity_id=seeded.person_entity_id
);

-- Only first Person gets the Ledger relationship; second has valid synthetic
-- session and Atlas, but is NOT authorized to read the Event.
INSERT INTO ledger.seats(ledger_id,person_entity_id,seat_state)
VALUES
 ('f5210000-0000-4000-8000-000000000014',
  'f5210000-0000-4000-8000-000000000002','active'),
 ('f5210000-0000-4000-8000-000000000014',
  'f5210000-0000-4000-8000-000000000004','active');

-- An unrelated native participant is the ordinary member; the third Person
-- has the *distinct* root_governing authority over this exact Ledger.
-- stable_key is GENERATED ALWAYS as 'person:' || id by the canonical
-- schema. Supply only the source-owned person identity and display name.
INSERT INTO atlas.people(id,display_name)
SELECT 'f5210000-0000-4000-8000-000000000004'::uuid,
  'Synthetic Root Governor'
WHERE NOT EXISTS (
 SELECT 1 FROM atlas.people p
 WHERE p.id='f5210000-0000-4000-8000-000000000004'::uuid
);

-- The canonical reality.auth_person_bindings identity does not itself
-- populate legacy atlas.person_auth_credentials. The Principal compatibility
-- trigger resolves that separate bridge and otherwise allocates a second Person.
-- Preserve ONE exact synthetic Person across both already-governed relations.
INSERT INTO atlas.person_auth_credentials(
  person_id,credential_kind,auth_user_id,status,provenance
)
SELECT 'f5210000-0000-4000-8000-000000000004'::uuid,
       'supabase_auth_user',
       'f5210000-0000-4000-8000-000000000403'::uuid,
       'active',
       '{"basis":"disposable_schedule_preflight_canonical_compatibility"}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM atlas.person_auth_credentials c
  WHERE c.auth_user_id='f5210000-0000-4000-8000-000000000403'::uuid
);

INSERT INTO atlas.principals(user_id,person_id,stable_key,name)
SELECT 'f5210000-0000-4000-8000-000000000403'::uuid,
  'f5210000-0000-4000-8000-000000000004'::uuid,
  'atlas-date-proof-root-principal-f521','Synthetic Root Governor'
WHERE NOT EXISTS (
 SELECT 1 FROM atlas.principals p
 WHERE p.user_id='f5210000-0000-4000-8000-000000000403'::uuid
);

INSERT INTO atlas.principal_ledger_authorities(
 principal_id,ledger_id,authority_kind,status,basis
)
SELECT p.id,'f5210000-0000-4000-8000-000000000014'::uuid,
 'root_governing','active','disposable schedule-correction root authorization proof'
FROM atlas.principals p
WHERE p.person_id='f5210000-0000-4000-8000-000000000004'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM atlas.principal_ledger_authorities a
    WHERE a.principal_id=p.id AND
      a.ledger_id='f5210000-0000-4000-8000-000000000014'::uuid
      AND a.status='active'
  );

-- This confirmed Resource claim proves root-only impact visibility while
-- an ordinary authenticated Ledger Person must see NULL, not zero.
INSERT INTO reality.resources(id,owner_entity_id,stable_key,label,resource_kind,
  capacity_mode,timezone_name)
VALUES (
 'f5210000-0000-4000-8000-000000000601',
 'f5210000-0000-4000-8000-000000000001',
 'atlas-date-proof-resource-f521','Synthetic Shared Space',
 'space','shared','America/Chicago');

INSERT INTO ledger.occurrence_resource_claims(
 ledger_id,occurrence_id,resource_id,claim_kind,claim_state,
 starts_at,ends_at,provenance
)
VALUES (
 'f5210000-0000-4000-8000-000000000014',
 'f5210000-0000-4000-8000-000000000101',
 'f5210000-0000-4000-8000-000000000601',
 'shared','confirmed',
 '2030-10-30 21:00+00','2030-10-31 01:00+00',
 '{"source":"disposable_schedule_preflight_fixture"}'::jsonb);

-- This synthetic canonical Event has richer public details than its linked
-- program carrier. Retiming must keep those details and exact subject ID.
UPDATE local_intel.occurrences
SET metadata='{"publicEventLocalTime":"6:00 PM–8:00 PM","vendorInvitationScope":"synthetic visitors","candyStandard":"dye-free","outreachStatus":"invitation planned","keepMe":"original"}'::jsonb
WHERE id='f5210000-0000-4000-8000-000000000101'::uuid;

-- A separate canonical Event on the same date stays a separate identity.
-- Existing confirmed site hold is 4-8 PM, independent from public schedule.
