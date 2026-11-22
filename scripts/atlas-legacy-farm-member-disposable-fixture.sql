-- TEST ONLY: synthetic farm actors in the existing disposable PG17 clone.
-- Load the immutable canonical C1 synthetic Auth fixture first.
-- Never load/copy production user, member, invite, Work or Task rows.
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

DO $local_farm_fixture$
BEGIN
 IF (SELECT count(*) FROM atlas.farm_memberships WHERE id::text LIKE 'e5200000-0000-4000-8000-00000000086%') != 4
  OR (SELECT count(*) FROM atlas.farm_membership_invites) != 0 THEN
   RAISE EXCEPTION 'Synthetic member or empty invitation source setup failed';
 END IF;
END $local_farm_fixture$;
