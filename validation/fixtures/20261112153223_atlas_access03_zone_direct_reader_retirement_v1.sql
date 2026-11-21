-- Fictional C1 local full-schema clone only, appended to original Work fixture.
SELECT 1 / CASE WHEN
 (SELECT count(*) FROM atlas.farms WHERE id='e5200000-0000-4000-8000-000000000b01'::uuid)=1
 AND (SELECT count(*) FROM atlas.farm_memberships
 WHERE id='e5200000-0000-4000-8000-000000000b06'::uuid
 AND role='farm_hand' AND active)=1
 THEN 1 ELSE 0 END AS access03_prerequisite;
UPDATE atlas.farm_memberships SET role='manager'
WHERE id='e5200000-0000-4000-8000-000000000b06'::uuid
 AND user_id='e5200000-0000-4000-8000-000000000002'::uuid
 AND farm_id='e5200000-0000-4000-8000-000000000b01'::uuid;
INSERT INTO atlas.zones(id,farm_id,stable_key,label,metadata) VALUES
('e5200000-0000-4000-8000-000000000b21'::uuid,
 'e5200000-0000-4000-8000-000000000b01'::uuid,
 'fictional-zone-a','Fictional Zone A',
 '{"privateMemo":"synthetic-private-zone"}'::jsonb);
INSERT INTO atlas.crop_cycles(
 id,farm_id,object_id,crop_cycle_key,crop_label,cycle_state,
 lifecycle_status,sown_date,metadata) VALUES
('e5200000-0000-4000-8000-000000000b22'::uuid,
 'e5200000-0000-4000-8000-000000000b01'::uuid,
 'e5200000-0000-4000-8000-000000000b03'::uuid,
 'fictional-cycle-a','Fictional crop A','growing','active',
 '2026-09-01'::date,'{"privateMemo":"synthetic-private-crop"}'::jsonb);
SELECT 1 / CASE WHEN
 (SELECT count(*) FROM atlas.zones
 WHERE id='e5200000-0000-4000-8000-000000000b21'::uuid)=1
 AND (SELECT count(*) FROM atlas.crop_cycles
 WHERE id='e5200000-0000-4000-8000-000000000b22'::uuid)=1
 AND (SELECT count(*) FROM atlas.farm_memberships
 WHERE id='e5200000-0000-4000-8000-000000000b06'::uuid AND role='manager')=1
 THEN 1 ELSE 0 END AS access03_fixture;
