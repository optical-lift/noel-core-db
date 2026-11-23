-- TEST ONLY: minimal DML-only Farm/member identities for held Worker Day projection.
-- Load the unchanged, independently hash-pinned C1 Auth/Person/Organization
-- fixture FIRST. Never load production member identities or Farm source rows.
-- This intentionally does NOT reference the physically retired
-- atlas.farm_membership_invites table, and contains no DO/DDL/grant/privileges.
INSERT INTO atlas.farms(id,stable_key,name,status,organization_id) VALUES
('e5200000-0000-4000-8000-000000000851','held-retirement-farm-a',
 'Fictional Farm A','active','e5200000-0000-4000-8000-000000000801'),
('e5200000-0000-4000-8000-000000000852','held-retirement-farm-b',
 'Fictional Farm B','active','e5200000-0000-4000-8000-000000000801');

INSERT INTO atlas.farm_memberships(id,user_id,farm_id,role,active,permissions) VALUES
('e5200000-0000-4000-8000-000000000861',
 'e5200000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000851','owner',true,'{}'),
('e5200000-0000-4000-8000-000000000862',
 'e5200000-0000-4000-8000-000000000002',
 'e5200000-0000-4000-8000-000000000851','farm_hand',true,'{}'),
('e5200000-0000-4000-8000-000000000863',
 'e5200000-0000-4000-8000-000000000003',
 'e5200000-0000-4000-8000-000000000852','owner',true,'{}'),
('e5200000-0000-4000-8000-000000000864',
 'e5200000-0000-4000-8000-000000000004',
 'e5200000-0000-4000-8000-000000000851','owner',false,'{}');
