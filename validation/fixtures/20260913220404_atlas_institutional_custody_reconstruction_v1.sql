-- DML-only fixture for Atlas Institutional Custody Reconstruction v1.
-- Reproduces the production mixed-container identity with exact governing anchor IDs and
-- representative Elm, Waiting Room, owner-level, communication, and institutional rows.

insert into auth.users(id) values
  ('4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid),
  ('21436a28-40fd-4914-8015-a248d0dca14e'::uuid),
  ('f496b283-795e-4c3e-b2ea-677989c9a235'::uuid),
  ('b5e4014b-8fc6-4733-9c89-e158f9dcc341'::uuid);

insert into atlas.people(id,stable_key,display_name,status,metadata) values
  ('59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,'custody_fixture_lex','Lex','active','{"validation_fixture":true}'::jsonb),
  ('998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid,'custody_fixture_anna','Anna','active','{"validation_fixture":true}'::jsonb),
  ('6ab25390-b372-4b1b-aa9e-1976f0ec1ba3'::uuid,'custody_fixture_katie','Katie','active','{"validation_fixture":true}'::jsonb),
  ('3105e113-d73f-4f9f-b7e1-c112eb26e87b'::uuid,'custody_fixture_marshall','Marshall','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(person_id,auth_user_id,status,provenance) values
  ('59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,'4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,'active','{"validation_fixture":true}'::jsonb),
  ('998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid,'21436a28-40fd-4914-8015-a248d0dca14e'::uuid,'active','{"validation_fixture":true}'::jsonb),
  ('6ab25390-b372-4b1b-aa9e-1976f0ec1ba3'::uuid,'f496b283-795e-4c3e-b2ea-677989c9a235'::uuid,'active','{"validation_fixture":true}'::jsonb),
  ('3105e113-d73f-4f9f-b7e1-c112eb26e87b'::uuid,'b5e4014b-8fc6-4733-9c89-e158f9dcc341'::uuid,'active','{"validation_fixture":true}'::jsonb);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values (
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'feast_guild','Feast Guild','active',
  '{"validation_fixture":true,"created_from":"portfolio_foundation_v1","organization_kind":"farm_collective"}'::jsonb,
  'ready'
);

insert into atlas.ledgers(
  id,stable_key,name,organization_id,ledger_kind,status,metadata
) values (
  '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,
  'feast_guild','Feast Guild','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'organization_governing','active',
  '{"scope_state":"legacy_mixed_pending_adjudication","validation_fixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  '662620b8-5332-436c-8fc1-a08f8fb4c161'::uuid,
  '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'governing',true,'active','{"source":"fixture"}'::jsonb,
  '{"scopeState":"legacy_mixed_pending_adjudication"}'::jsonb
);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values (
  'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid,
  '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'lex','Lex','America/Chicago','active','{"validation_fixture":true}'::jsonb,
  '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  '77777777-7777-4777-8777-777777777701'::uuid,
  'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid,
  '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,
  'root_governing','active','legacy_principal_organization_compatibility','{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_units(
  id,organization_id,stable_key,name,unit_kind,status,metadata
) values
(
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'elm','Elm','operating_business','active','{"validation_fixture":true}'::jsonb
),
(
  '999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'waiting_room_farm','Waiting Room Farm','farm','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.farms(
  id,stable_key,name,status,notes,organization_id,organization_unit_id,metadata,north_star_text
) values
(
  '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,
  'elm_farm','Elm Farm','active','Production farm with venue income.',
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  '{"validation_fixture":true}'::jsonb,'Elm Farm canonical fixture'
),
(
  'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid,
  'waiting_room_farm','Waiting Room Farm','active','Test farm scope.',
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid,
  '{"validation_fixture":true}'::jsonb,'Waiting Room test fixture'
);

insert into atlas.identity_subjects(
  id,organization_id,state,creation_basis
) values
(
  '0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'active','{"basis":"owner-established institutional worker identity","validation_fixture":true}'::jsonb
),
(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'active','{"basis":"Elm external relationship fixture","validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,person_id,identity_subject_id,role,active,permissions
) values
(
  '427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
  '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
  null,'owner',true,'{"manage_projects":true,"validation_fixture":true}'::jsonb
),
(
  '4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '21436a28-40fd-4914-8015-a248d0dca14e'::uuid,
  '998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid,
  '0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid,
  'member',true,'{"validation_fixture":true}'::jsonb
),
(
  '8cc87ff8-f7d0-4dcc-86ae-ecc8cb84bc55'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'f496b283-795e-4c3e-b2ea-677989c9a235'::uuid,
  '6ab25390-b372-4b1b-aa9e-1976f0ec1ba3'::uuid,
  null,'consultant',false,'{"validation_fixture":true}'::jsonb
),
(
  'bbffdd69-39e4-4bcc-b1e7-ab728a6cb38c'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'b5e4014b-8fc6-4733-9c89-e158f9dcc341'::uuid,
  '3105e113-d73f-4f9f-b7e1-c112eb26e87b'::uuid,
  null,'member',false,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_employee_seats(
  id,organization_id,organization_membership_id,identity_subject_id,seat_class,status,billing_state,billing_unit_price_cents,metadata
) values (
  '74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid,
  '0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid,
  'employee','active','active',700,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_member_credentials(
  id,organization_id,organization_membership_id,employee_seat_id,identity_subject_id,
  credential_kind,auth_user_id,status,issued_by_organization_id,provenance
) values (
  '385673ab-cf4e-4dbe-8c1d-11cb244143f2'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid,
  '74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid,
  '0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid,
  'auth_user','21436a28-40fd-4914-8015-a248d0dca14e'::uuid,'active',
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '{"source":"atlas_employee_seat_identity_v1","validation_fixture":true}'::jsonb
);

insert into atlas.organization_positions(
  id,organization_id,organization_unit_id,stable_key,display_title,position_kind,status,metadata
) values (
  'badd2192-28a7-4913-aa90-e7076cb419f5'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  'operations_steward','Farm Steward','operations','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_position_appointments(
  id,organization_id,position_id,identity_subject_id,organization_membership_id,appointment_kind,status,metadata
) values (
  '1baf1031-cbe3-4520-9b5d-485bb5c9a59c'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'badd2192-28a7-4913-aa90-e7076cb419f5'::uuid,
  '0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid,
  '4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid,
  'primary','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_responsibilities(
  id,organization_id,stable_key,name,responsibility_kind,status,metadata
) values
('fd1ad1fb-7df6-4a76-82f8-de38468d41ec'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'production_stewardship','Production stewardship','stewardship','active','{"validation_fixture":true}'::jsonb),
('201dc58e-9647-46b3-a92b-003630e276ff'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'harvest_execution','Harvest execution','execution','active','{"validation_fixture":true}'::jsonb),
('0bdf4273-f69b-4a6d-b6d9-4c8eb70ac3d7'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'nursery_care','Nursery care','stewardship','active','{"validation_fixture":true}'::jsonb),
('0c95d93a-2dc2-46f6-864f-a222b7f9e85b'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'grounds_readiness','Grounds readiness','stewardship','active','{"validation_fixture":true}'::jsonb),
('d9a382c4-cbde-4b03-b8be-cf0465035bf4'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'venue_preparation','Venue preparation','execution','active','{"validation_fixture":true}'::jsonb);

insert into atlas.organization_responsibility_scopes(
  id,organization_id,responsibility_id,scope_kind,scope_id,relation_kind,metadata
) values
('bd3e662b-74d5-452a-b6bc-c7053b5a31db'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'fd1ad1fb-7df6-4a76-82f8-de38468d41ec'::uuid,'organization_unit','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','stewards','{"validation_fixture":true}'::jsonb),
('b0a139a0-a401-4a5b-941f-a64acd947b8d'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'201dc58e-9647-46b3-a92b-003630e276ff'::uuid,'organization_unit','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','stewards','{"validation_fixture":true}'::jsonb),
('2119e5ed-1281-4ee8-9a68-d59c21fd4252'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'0bdf4273-f69b-4a6d-b6d9-4c8eb70ac3d7'::uuid,'organization_unit','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','stewards','{"validation_fixture":true}'::jsonb),
('7b36de04-e752-41f9-a069-82e2120ffbc3'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'0c95d93a-2dc2-46f6-864f-a222b7f9e85b'::uuid,'organization_unit','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','stewards','{"validation_fixture":true}'::jsonb),
('7c7e95dd-ee10-4f7f-9cef-967fccd5111e'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'d9a382c4-cbde-4b03-b8be-cf0465035bf4'::uuid,'organization_unit','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','stewards','{"validation_fixture":true}'::jsonb);

-- Representative Elm institutional identity/customer relationship.
insert into atlas.external_relationships(
  id,organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
) values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa20'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10'::uuid,
  'custody_fixture_elm_relationship','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.communication_endpoints(
  id,organization_id,organization_unit_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata
) values (
  '7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  'email','hello@elmfarm.co','hello@elmfarm.co','Elm Farm','active','{"validation_fixture":true}'::jsonb
);

-- Exact source IDs and communication capabilities let postconditions prove custody movement
-- cannot enable/disable capture/send or mutate authorization state.
insert into atlas.connected_sources(
  id,custodian_organization_id,custodian_organization_unit_id,provider_key,provider_account_key,
  display_label,account_hint,authorization_state,granted_scopes,capabilities,last_sync_at,metadata
) values
(
  '188291ac-3b08-429b-8ea1-a2bf3f3833ef'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  'email','hello@elmfarm.co:live-relay','Elm Farm hello@ live inbound relay','DreamHost shell push relay',
  'connected',array['communication.capture']::text[],
  '{"communicationSend":false,"communicationCapture":true}'::jsonb,
  '2026-09-13 13:21:24+00'::timestamptz,'{"validation_fixture":true}'::jsonb
),
(
  '238df033-5704-4404-bf34-a509f4e4d1c1'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  'imap_smtp_email','hello@elmfarm.co','Elm Farm · hello@elmfarm.co','hello@elmfarm.co',
  'pending',array['mail.read','mail.send']::text[],
  '{"communicationSend":false,"communicationCapture":false}'::jsonb,
  null,'{"validation_fixture":true}'::jsonb
);

insert into atlas.user_profiles(
  user_id,display_name,default_farm_id,active,metadata,default_organization_id,onboarding_state
) values
('4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,'Lex','6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,true,'{"validation_fixture":true}'::jsonb,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'ready'),
('21436a28-40fd-4914-8015-a248d0dca14e'::uuid,'Anna','6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,false,'{"validation_fixture":true}'::jsonb,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'ready'),
('f496b283-795e-4c3e-b2ea-677989c9a235'::uuid,'Katie',null,false,'{"validation_fixture":true}'::jsonb,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'ready'),
('b5e4014b-8fc6-4733-9c89-e158f9dcc341'::uuid,'Marshall','6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,false,'{"validation_fixture":true}'::jsonb,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'ready');

-- Representative work classification: Elm moves, Waiting Room and root owner work archive in place.
insert into atlas.tasks(id,farm_id,title,status,organization_id,metadata) values
('aaaaaaaa-1000-4000-8000-aaaaaaaa0001'::uuid,'6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,'Elm fixture task','open','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'{"validation_fixture":true}'::jsonb),
('aaaaaaaa-1000-4000-8000-aaaaaaaa0002'::uuid,'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid,'Waiting Room fixture task','open','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'{"validation_fixture":true}'::jsonb),
('aaaaaaaa-1000-4000-8000-aaaaaaaa0003'::uuid,null,'Owner-level Camp Duffel fixture task','open','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'{"validation_fixture":true}'::jsonb);

insert into atlas.projects(id,farm_id,stable_key,title,status,organization_id,metadata) values
('bbbbbbbb-1000-4000-8000-bbbbbbbb0001'::uuid,'6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,'custody_fixture_elm_project','Elm fixture project','active','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'{"validation_fixture":true}'::jsonb),
('bbbbbbbb-1000-4000-8000-bbbbbbbb0002'::uuid,'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid,'custody_fixture_waiting_project','Waiting Room fixture project','active','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'{"validation_fixture":true}'::jsonb),
('bbbbbbbb-1000-4000-8000-bbbbbbbb0003'::uuid,null,'custody_fixture_owner_project','Nathan / Camp Duffel fixture project','active','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'{"validation_fixture":true}'::jsonb);

-- Six preserved Elm production Ledger entries with fixed revisions.
insert into atlas.organization_ledger_entries(
  id,organization_id,organization_unit_id,event_key,source_domain,semantic_type,occurred_at,
  title,payload,provenance,correlation,revision,ledger_id
) values
('cccccccc-1000-4000-8000-cccccccc0001'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'custody_fixture:berry_1','production','bed_preparation','2026-09-01T12:00:00Z','Berry Walk fixture 1','{}','{"validation_fixture":true}','{}',8101,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid),
('cccccccc-1000-4000-8000-cccccccc0002'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'custody_fixture:berry_2','production','bed_preparation','2026-09-02T12:00:00Z','Berry Walk fixture 2','{}','{"validation_fixture":true}','{}',8102,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid),
('cccccccc-1000-4000-8000-cccccccc0003'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'custody_fixture:berry_3','production','bed_preparation','2026-09-03T12:00:00Z','Berry Walk fixture 3','{}','{"validation_fixture":true}','{}',8103,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid),
('cccccccc-1000-4000-8000-cccccccc0004'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'custody_fixture:berry_4','production','bed_preparation','2026-09-04T12:00:00Z','Berry Walk fixture 4','{}','{"validation_fixture":true}','{}',8104,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid),
('cccccccc-1000-4000-8000-cccccccc0005'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'custody_fixture:berry_5','production','bed_preparation','2026-09-05T12:00:00Z','Berry Walk fixture 5','{}','{"validation_fixture":true}','{}',8105,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid),
('cccccccc-1000-4000-8000-cccccccc0006'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'custody_fixture:berry_6','production','bed_preparation','2026-09-06T12:00:00Z','Berry Walk fixture 6','{}','{"validation_fixture":true}','{}',8106,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid);
