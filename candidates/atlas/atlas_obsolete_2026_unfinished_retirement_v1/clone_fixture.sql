-- HELD clone-only synthetic 2026 unfinished retirement fixture.
-- Only the opaque source UUIDs, queue family/position/state, and original
-- planned-occurrence status identities reproduce the exact held hash guards.
-- Other business data is FICTIONAL: no live names, crop payload, personal
-- info, signed Result, true physical observation or live credentials.
-- DML ONLY, disposable schema-clone; not a production data copy.
-- This data is intentionally not a new task engine or enduring fixture.

INSERT INTO atlas.organizations(id,stable_key,name,status,onboarding_state) VALUES
('f9200000-0000-4000-8000-000000000001','held-queue-retirement-org-2026','Fictional Historical Queue Org','active','ready');
INSERT INTO atlas.farms(id,organization_id,stable_key,name,status) VALUES
('f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000001','held-queue-retirement-farm-2026','Fictional Historical Farm','active');
-- Mirror the existence, not private contents, of this farm's original
-- release settings. This prevents the legacy terminal release trigger from
-- inserting a new unrelated settings row after the no-loss baseline.
INSERT INTO atlas.farm_task_release_settings(farm_id)
VALUES ('f9200000-0000-4000-8000-000000000002');

INSERT INTO atlas.work_definitions(id,farm_id,stable_key,title_template,task_type,active) VALUES
('f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000002','held-2026-queue-definition','Fictional obsolete queue task','general',false);
INSERT INTO atlas.work_release_policies(id,farm_id,work_definition_id,stable_key,gate_type,active) VALUES
('f9200000-0000-4000-8000-000000000004','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','held-2026-queue-policy','manual',false);

-- Exactly 95 historical linked occurrence IDs; only the ID and state
-- mirror the authoritative source. Names, rules, payloads, gates are invented
-- fictional clone controls and must not be read as actual source history.
INSERT INTO atlas.planned_work_occurrences(id,farm_id,work_definition_id,release_policy_id,occurrence_key,title,state) VALUES
('00c929b8-f76f-4320-b400-6a72fd939004','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-001','Fictional historical test occurrence','planned'),
('02e67997-238b-4bbb-84ea-16c8a42f5712','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-002','Fictional historical test occurrence','planned'),
('0611f96a-7819-4334-a802-0007593b3a18','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-003','Fictional historical test occurrence','planned'),
('08ca7394-895b-4699-8ddf-5402d91e20f7','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-004','Fictional historical test occurrence','planned'),
('0a17a406-b06e-4a64-89ea-4680cdbe28dd','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-005','Fictional historical test occurrence','completed'),
('0a307bad-7ad6-4b7f-a9af-cf5fd7bb7a4b','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-006','Fictional historical test occurrence','planned'),
('0ef83d10-fdde-4412-b319-ad3f9fea8549','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-007','Fictional historical test occurrence','completed'),
('0ff2aaee-3369-415f-a941-faa3756450e7','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-008','Fictional historical test occurrence','completed'),
('159047a7-01f8-4ef2-964d-b48a3e2ea5f6','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-009','Fictional historical test occurrence','planned'),
('1718c8d9-2457-4523-9f5c-1d40a510ebfc','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-010','Fictional historical test occurrence','completed'),
('1a52763e-591e-4b1c-a0c7-61715fd91a6d','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-011','Fictional historical test occurrence','planned'),
('1dd7d4ef-d9bd-486a-a682-49d7fab7e3a1','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-012','Fictional historical test occurrence','planned'),
('22629802-9ffe-4f4d-81b5-3c8a239bd9e2','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-013','Fictional historical test occurrence','planned'),
('2332ad66-e9d1-48bb-ad1c-69982f28bb81','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-014','Fictional historical test occurrence','planned'),
('2382df25-d101-46fe-9a58-68c7b619f609','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-015','Fictional historical test occurrence','planned'),
('24b48113-18dc-4c16-83bf-eee72cc5ced8','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-016','Fictional historical test occurrence','cancelled'),
('2601deca-65ab-4fb6-b418-22e7867791a4','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-017','Fictional historical test occurrence','planned'),
('351df645-bd66-43cc-ab82-3e1998e64930','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-018','Fictional historical test occurrence','cancelled'),
('3633c00d-fa7d-4af7-b086-46d9cc9d470b','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-019','Fictional historical test occurrence','planned'),
('3a49f953-2baf-4ca0-9ce1-c231173ff67c','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-020','Fictional historical test occurrence','planned'),
('3bf9f21a-e60a-4abb-85e9-15ecc715f10e','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-021','Fictional historical test occurrence','planned'),
('3d3d8c51-efc5-4b4f-bf51-e45a2409611e','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-022','Fictional historical test occurrence','completed'),
('3dc281d4-0b0f-400b-9200-d3dc7848cd1b','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-023','Fictional historical test occurrence','planned'),
('4062bc17-dae5-4a13-918b-fe11cd89f91e','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-024','Fictional historical test occurrence','planned'),
('4123b60e-1c48-4f83-96ef-eed305bdd3d4','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-025','Fictional historical test occurrence','planned'),
('45982595-43ec-4426-b59d-2a168c9bfc38','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-026','Fictional historical test occurrence','cancelled'),
('45c02ef3-1b9b-496e-99de-23cb14bf1980','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-027','Fictional historical test occurrence','planned'),
('47d1b521-db03-45fd-bf0c-3ed951c2b949','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-028','Fictional historical test occurrence','cancelled'),
('4c6733d8-e324-4b66-9337-b8a8c957316d','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-029','Fictional historical test occurrence','planned'),
('4d45b653-0ac7-40ee-b604-38976a18ee7b','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-030','Fictional historical test occurrence','planned'),
('4e607155-d7e4-4def-aee1-e4433454e606','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-031','Fictional historical test occurrence','planned'),
('4f39bad5-e516-48f8-accd-00509da7c89e','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-032','Fictional historical test occurrence','completed'),
('5017f3e5-f6ca-46cf-b46e-4b0cda5473e1','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-033','Fictional historical test occurrence','planned'),
('5194c0f3-200d-4ee8-be8d-ec6fac318e75','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-034','Fictional historical test occurrence','planned'),
('58c99190-e9e6-4cfa-83fe-1d7321b0094d','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-035','Fictional historical test occurrence','planned'),
('5d6123f4-ba5d-43c6-9185-816143bcc754','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-036','Fictional historical test occurrence','released'),
('5ddd9890-20b7-4611-932a-6d9fb100b1c7','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-037','Fictional historical test occurrence','completed'),
('5f9cb3e3-cae1-4649-8137-69d3fd9f72e8','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-038','Fictional historical test occurrence','planned'),
('62c88e8e-c89a-44e0-995d-8dfb0fe968f2','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-039','Fictional historical test occurrence','cancelled'),
('69ebb995-a33e-4b53-8f62-a6c0d90a055f','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-040','Fictional historical test occurrence','completed'),
('6cac32c5-4dae-476e-8e70-c5513da58b40','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-041','Fictional historical test occurrence','planned'),
('6e012007-8cee-49f0-b61d-7b02d5b26577','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-042','Fictional historical test occurrence','planned'),
('70909d03-21f8-4d22-975c-bff8a428f8be','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-043','Fictional historical test occurrence','released'),
('71ef03fa-36ff-4a54-bdad-dfe5336014c9','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-044','Fictional historical test occurrence','planned'),
('7408958e-ff6a-40ac-a3ac-04d4f21da355','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-045','Fictional historical test occurrence','planned'),
('77838bce-21d4-4833-8d50-fe52b6a9cdb6','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-046','Fictional historical test occurrence','completed'),
('7b80119c-cb2f-4357-9fbe-b387c112e03e','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-047','Fictional historical test occurrence','planned'),
('8308a4a3-6424-45a6-a9f1-50dd95dd1b44','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-048','Fictional historical test occurrence','planned'),
('8476fd15-0afe-4635-83aa-9eedc102c3ea','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-049','Fictional historical test occurrence','planned'),
('84f460f2-a0f3-4e3d-a2b4-dee711ceb326','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-050','Fictional historical test occurrence','planned'),
('87243036-5759-4faf-925f-184cf6e26ef8','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-051','Fictional historical test occurrence','planned'),
('8b6718bd-a1ea-4583-b0c3-79a72ff04afa','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-052','Fictional historical test occurrence','planned'),
('8c1f33b2-1608-4991-b2df-53769d082213','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-053','Fictional historical test occurrence','planned'),
('9007f67e-2c6a-4582-ace4-69b896a8a832','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-054','Fictional historical test occurrence','completed'),
('93c0e843-d95a-4633-9e03-37a8aad60ddb','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-055','Fictional historical test occurrence','completed'),
('9493e0d2-405b-44bb-8876-e41c41ea43f5','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-056','Fictional historical test occurrence','completed'),
('95791562-d68a-4d88-a2e3-8a436969a8ba','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-057','Fictional historical test occurrence','planned'),
('96804067-4e13-40e9-98b7-6baf219605d2','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-058','Fictional historical test occurrence','completed'),
('96cf7742-872d-4c74-9c55-8f32a38aa540','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-059','Fictional historical test occurrence','completed'),
('9ec64d6a-d2f0-4f1f-82d5-0206d1735d6f','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-060','Fictional historical test occurrence','planned'),
('a2455fc1-73d4-4c67-915a-94c519d88d8d','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-061','Fictional historical test occurrence','planned'),
('a25d4e4f-175c-4166-987f-36928a27c3c0','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-062','Fictional historical test occurrence','planned'),
('a3dd16bd-719c-4f8b-a346-656e49a2d9d3','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-063','Fictional historical test occurrence','planned'),
('a86376ea-73c2-48f2-b0d2-efe5fc4d7ff2','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-064','Fictional historical test occurrence','planned'),
('af608649-9ccb-48f3-b4f0-c728922482a3','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-065','Fictional historical test occurrence','completed'),
('b1b57adf-9ff6-4a9b-a127-18ec2c2b0309','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-066','Fictional historical test occurrence','cancelled'),
('b32496c0-26ae-43cf-8e80-218638e0e3a4','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-067','Fictional historical test occurrence','planned'),
('b7093241-d4fd-4fc6-a055-568a7b7332ce','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-068','Fictional historical test occurrence','planned'),
('b72e782d-00db-41c2-a3f5-72054697833c','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-069','Fictional historical test occurrence','eligible'),
('b7381545-9bac-41cb-92c0-9fc03174e9fd','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-070','Fictional historical test occurrence','cancelled'),
('b86f8bd8-0702-4631-9665-24f6bfec807f','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-071','Fictional historical test occurrence','planned'),
('bc0fd5b6-de6f-454e-9714-1bc09feb273a','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-072','Fictional historical test occurrence','planned'),
('bcd610fb-f340-4cab-ab30-b669345474d3','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-073','Fictional historical test occurrence','planned'),
('bd5bcdfa-b43e-46df-85f3-9a9889026dec','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-074','Fictional historical test occurrence','completed'),
('c2dadb6e-1a01-4bcd-969b-d45a100f9206','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-075','Fictional historical test occurrence','completed'),
('c3c7b4d7-03fc-4dda-9957-5be22dbc765a','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-076','Fictional historical test occurrence','planned'),
('c8220427-8986-4f5c-8c7f-44e530f27116','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-077','Fictional historical test occurrence','planned'),
('ca38f851-d8a3-4ec0-a70e-3c0ad9ae2d62','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-078','Fictional historical test occurrence','planned'),
('cd8543ab-1c3a-4c6c-a151-6d5255d36d10','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-079','Fictional historical test occurrence','planned'),
('ce028b29-d46f-4f7e-a802-0e4862e701c8','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-080','Fictional historical test occurrence','planned'),
('d3d412de-9d30-4d2a-b17d-57a33c7b6e2c','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-081','Fictional historical test occurrence','planned'),
('d82778d9-634e-4770-9bb3-fec2808460e2','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-082','Fictional historical test occurrence','completed'),
('d99dcf33-c0c5-4182-b56c-731dca45f6d4','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-083','Fictional historical test occurrence','planned'),
('da414681-303a-4d71-8578-afb6d562a5c2','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-084','Fictional historical test occurrence','planned'),
('da49b391-30a2-4983-a171-08e13acc724d','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-085','Fictional historical test occurrence','completed'),
('e2a18027-2045-4c9b-ad34-c8cfe49082ea','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-086','Fictional historical test occurrence','planned'),
('e9fd45e3-4a2c-48f5-801c-2339b5d20ab4','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-087','Fictional historical test occurrence','planned'),
('ee4b0dc7-9744-4afa-bbb0-d68a22a69100','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-088','Fictional historical test occurrence','planned'),
('f07002a0-7cc0-4f02-8710-8802086a32af','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-089','Fictional historical test occurrence','planned'),
('f0769bf3-a450-4558-9e96-2aab0e3a90a0','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-090','Fictional historical test occurrence','completed'),
('f209991c-f637-4ca9-9d85-b60f7dd37b8f','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-091','Fictional historical test occurrence','cancelled'),
('f53c9419-ff98-46e7-b33e-5340723f14d3','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-092','Fictional historical test occurrence','completed'),
('f56b1cb8-a1eb-4aed-88cc-c8a5de5fbf8b','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-093','Fictional historical test occurrence','eligible'),
('fb0efbd5-5905-4147-8daf-1764cd79b7a8','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-094','Fictional historical test occurrence','planned'),
('ff986624-8549-408e-a811-bb083fd16098','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000003','f9200000-0000-4000-8000-000000000004','held-source-095','Fictional historical test occurrence','planned');

-- Three previously owner-adjudicated source Task IDs. No 'Done' status
-- or physical completion is manufactured by this fixture.
INSERT INTO atlas.tasks(id,farm_id,organization_id,title,task_scope,task_type,status,visibility_scope,metadata,planned_occurrence_id,release_policy_id,released_at) VALUES
('d1bb49af-667f-47e6-b03b-06d75c6e93e6','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000001','Fictional retired historical Task','farm_operation','general','open','owner',jsonb_build_object('release_queue_key','owner_venue_marketing_queue','heldFixture',true),'70909d03-21f8-4d22-975c-bff8a428f8be','f9200000-0000-4000-8000-000000000004',now()),
('e05f3870-7c74-47d5-9998-483aa238f115','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000001','Fictional retired historical Task','farm_operation','general','open','owner',jsonb_build_object('release_queue_key','owner_social_content_queue','heldFixture',true),'5d6123f4-ba5d-43c6-9185-816143bcc754','f9200000-0000-4000-8000-000000000004',now()),
('63ade0e9-28bc-4543-805f-d2c82d678315','f9200000-0000-4000-8000-000000000002','f9200000-0000-4000-8000-000000000001','Fictional retired historical Task','farm_operation','general','blocked','owner',jsonb_build_object('release_queue_key','owner_venue_marketing_queue','heldFixture',true),'71ef03fa-36ff-4a54-bdad-dfe5336014c9','f9200000-0000-4000-8000-000000000004',now());

-- Original Task/occurrence association from the source is preserved
-- after synthetic Task insert, respecting the two released-Task FKs.
-- Third Task is linked to a planned occurrence but not released by that plan.
UPDATE atlas.planned_work_occurrences
   SET released_task_id=CASE id
     WHEN '70909d03-21f8-4d22-975c-bff8a428f8be'::uuid
       THEN 'd1bb49af-667f-47e6-b03b-06d75c6e93e6'::uuid
     WHEN '5d6123f4-ba5d-43c6-9185-816143bcc754'::uuid
       THEN 'e05f3870-7c74-47d5-9998-483aa238f115'::uuid
     ELSE released_task_id END
 WHERE id IN (
   '70909d03-21f8-4d22-975c-bff8a428f8be'::uuid,
   '5d6123f4-ba5d-43c6-9185-816143bcc754'::uuid
 );

-- Exactly 97 original opaque queue row identities; known seven
-- family keys and queue positions/states, but no true live person or crop data.
-- Historical initial_batch=true is retained ONLY for the two original\n-- parallel active field-row queue members, required by the original\n-- partial unique index. All other old queue members use false.\n-- Only three original still-open historical task pointers are set; the other
-- historical Task-linked pointers are omitted in this synthetic fixture.
INSERT INTO atlas.task_release_queue_items(id,farm_id,queue_key,position,state,planned_occurrence_id,task_id,initial_batch) VALUES
('0074d2e6-3b75-428c-aab6-a927c44fe89e','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',2,'completed','96804067-4e13-40e9-98b7-6baf219605d2',NULL,false),
('01f8927c-b4e9-45c2-9945-c39d5769cc71','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',8,'queued','3d3d8c51-efc5-4b4f-bf51-e45a2409611e',NULL,false),
('030b1bca-f425-4113-9ac8-c6c2eeebcdf7','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',18,'queued','02e67997-238b-4bbb-84ea-16c8a42f5712',NULL,false),
('055e9353-cf38-4b5d-ac85-7b3f967b3543','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',1,'active','70909d03-21f8-4d22-975c-bff8a428f8be','d1bb49af-667f-47e6-b03b-06d75c6e93e6',false),
('07f1f91e-c534-4f4b-8e92-4257763f921d','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',32,'queued','8b6718bd-a1ea-4583-b0c3-79a72ff04afa',NULL,false),
('0b9d82e8-8a14-4466-972b-47fed076b5c2','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',35,'skipped','b1b57adf-9ff6-4a9b-a127-18ec2c2b0309',NULL,false),
('0ba1ca9c-246b-4b47-a7a0-bff389a8e16a','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',12,'queued','58c99190-e9e6-4cfa-83fe-1d7321b0094d',NULL,false),
('0c770614-4af9-4616-bbe5-88fcb8d91f3b','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',17,'skipped','45982595-43ec-4426-b59d-2a168c9bfc38',NULL,false),
('0d00ae1f-9e51-4c09-a5e9-fb7d535c4b79','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',19,'queued','4d45b653-0ac7-40ee-b604-38976a18ee7b',NULL,false),
('162cafef-251a-49f1-bc52-f9be9cfa614b','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',3,'queued','9ec64d6a-d2f0-4f1f-82d5-0206d1735d6f',NULL,false),
('236d675e-e7e0-416d-91b1-1b91d309c0a6','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',34,'queued','a3dd16bd-719c-4f8b-a346-656e49a2d9d3',NULL,false),
('272bf6b6-5a04-486c-bdb8-4e84e52272e6','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',30,'queued','2332ad66-e9d1-48bb-ad1c-69982f28bb81',NULL,false),
('27488f48-364a-466d-b236-bd87c8dc9fd4','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',1,'completed','bd5bcdfa-b43e-46df-85f3-9a9889026dec',NULL,false),
('2a601792-6cfe-4c75-9cf7-fc1a96aa1234','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',5,'queued','a2455fc1-73d4-4c67-915a-94c519d88d8d',NULL,false),
('2b4aad53-8da5-4178-a0f6-95714f785b62','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',32,'queued','2601deca-65ab-4fb6-b418-22e7867791a4',NULL,false),
('2f705132-26ee-4fcd-b537-bd5296c4dbfc','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',4,'completed','0ff2aaee-3369-415f-a941-faa3756450e7',NULL,false),
('30f11e37-7f43-4473-8a4a-8af29821c839','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',35,'queued','c3c7b4d7-03fc-4dda-9957-5be22dbc765a',NULL,false),
('318996b5-4c9a-459c-a952-aa7a69528d17','f9200000-0000-4000-8000-000000000002','field_rows_weeding_rotation',1,'completed',NULL,NULL,false),
('323a0600-56b6-4bc7-b213-a5384178a1fa','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',36,'queued','a86376ea-73c2-48f2-b0d2-efe5fc4d7ff2',NULL,false),
('34a4b327-777b-4b51-90f5-59dbb87889ee','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',6,'completed','0ef83d10-fdde-4412-b319-ad3f9fea8549',NULL,false),
('393c3245-fbe1-4a0f-866a-fc56dbbe6b14','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',22,'queued','cd8543ab-1c3a-4c6c-a151-6d5255d36d10',NULL,false),
('3d31bc69-7497-41f5-b8eb-cce7b18a8b0c','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',5,'completed','5ddd9890-20b7-4611-932a-6d9fb100b1c7',NULL,false),
('3f262302-e57d-4d63-afb0-95bdfdabe218','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',23,'queued','08ca7394-895b-4699-8ddf-5402d91e20f7',NULL,false),
('407dc501-06ba-49c9-90a7-ee39ff145563','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',16,'queued','b7381545-9bac-41cb-92c0-9fc03174e9fd',NULL,false),
('43f579aa-85ea-466d-9b6b-49d4c06f12a1','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',4,'completed','d82778d9-634e-4770-9bb3-fec2808460e2',NULL,false),
('444b01d6-5d9c-44f8-9d57-3f5e5003da55','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',10,'queued','4c6733d8-e324-4b66-9337-b8a8c957316d',NULL,false),
('47e15f20-f8d5-4f8d-9dc7-66e8953fdd45','f9200000-0000-4000-8000-000000000002','anna_gentle_pressure_wash_aug_2026',5,'queued','6cac32c5-4dae-476e-8e70-c5513da58b40',NULL,false),
('4ad3a385-6372-44f8-b571-19d37e5a7b6b','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',26,'queued','7b80119c-cb2f-4357-9fbe-b387c112e03e',NULL,false),
('4bf4f850-0097-4aa7-96d3-298b1a9502ab','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',7,'queued','a25d4e4f-175c-4166-987f-36928a27c3c0',NULL,false),
('4d50a290-1e34-4940-9f14-e8cf4cfbaa9c','f9200000-0000-4000-8000-000000000002','field_rows_weeding_rotation',3,'active','77838bce-21d4-4833-8d50-fe52b6a9cdb6',NULL,true),
('51a684e4-f6bf-4741-a7d7-7ef0943b2872','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',6,'queued','b7093241-d4fd-4fc6-a055-568a7b7332ce',NULL,false),
('526edcd6-8f2a-4e3c-9738-32add3a58714','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',12,'queued','1a52763e-591e-4b1c-a0c7-61715fd91a6d',NULL,false),
('56d72939-0df1-460a-a9fa-61ccb139b780','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',3,'completed','f53c9419-ff98-46e7-b33e-5340723f14d3',NULL,false),
('58945ad1-e520-489e-85ff-9ddf30bd2880','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',29,'queued','fb0efbd5-5905-4147-8daf-1764cd79b7a8',NULL,false),
('59fb0574-18d3-4df7-ac4d-ddaefe27ff0a','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',31,'queued','22629802-9ffe-4f4d-81b5-3c8a239bd9e2',NULL,false),
('5d9491c6-b483-48a9-bd19-0552f6ec532e','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',24,'skipped','62c88e8e-c89a-44e0-995d-8dfb0fe968f2',NULL,false),
('5e2265b6-9954-4311-b1da-1273beb629b3','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',15,'skipped','24b48113-18dc-4c16-83bf-eee72cc5ced8',NULL,false),
('5fbdbcdd-c9a0-4951-9a87-048435f4ee20','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',36,'queued','8c1f33b2-1608-4991-b2df-53769d082213',NULL,false),
('63b47686-70c1-47bf-bacb-95ff1fe8091a','f9200000-0000-4000-8000-000000000002','anna_gentle_pressure_wash_aug_2026',2,'queued','ff986624-8549-408e-a811-bb083fd16098',NULL,false),
('72c5128f-ab79-42ec-8420-9c791693862b','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',29,'queued','bc0fd5b6-de6f-454e-9714-1bc09feb273a',NULL,false),
('73ccca91-b025-4f99-a943-aa515a3eefbd','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',20,'queued','5f9cb3e3-cae1-4649-8137-69d3fd9f72e8',NULL,false),
('74cfdcbe-63b7-4105-9b37-05bcd8dc4f49','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',4,'queued','0a307bad-7ad6-4b7f-a9af-cf5fd7bb7a4b',NULL,false),
('76db9b6a-d588-4197-80e5-b5e6c1df5f4f','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',19,'queued','87243036-5759-4faf-925f-184cf6e26ef8',NULL,false),
('7744121c-397d-4fc3-980d-8cdd87367691','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',24,'queued','4e607155-d7e4-4def-aee1-e4433454e606',NULL,false),
('78684714-9737-4f1d-9a56-f1d790039f59','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',4,'queued','00c929b8-f76f-4320-b400-6a72fd939004',NULL,false),
('814231c3-998a-4015-8468-729873743acb','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',33,'queued','bcd610fb-f340-4cab-ab30-b669345474d3',NULL,false),
('8266da3f-f0cc-4997-bf75-742faeed5186','f9200000-0000-4000-8000-000000000002','anna_gentle_pressure_wash_aug_2026',4,'queued','1dd7d4ef-d9bd-486a-a682-49d7fab7e3a1',NULL,false),
('859d82dd-b814-4805-a587-2a8b4b2097f5','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',6,'queued','8308a4a3-6424-45a6-a9f1-50dd95dd1b44',NULL,false),
('86db8f38-4240-4ec5-9e86-ebab5b676703','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',22,'queued','b32496c0-26ae-43cf-8e80-218638e0e3a4',NULL,false),
('8acc2cfb-4a5c-47cb-ad75-613d483d6488','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',7,'queued','af608649-9ccb-48f3-b4f0-c728922482a3',NULL,false),
('8f1ff45b-cb6b-4b90-8a3d-be880a128e75','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',7,'active','0a17a406-b06e-4a64-89ea-4680cdbe28dd',NULL,false),
('9557a17a-91cf-4424-b1f3-33ad3d460606','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',2,'completed','f0769bf3-a450-4558-9e96-2aab0e3a90a0',NULL,false),
('96f9f059-1884-4154-8a09-ce77f49d966c','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',3,'completed','1718c8d9-2457-4523-9f5c-1d40a510ebfc',NULL,false),
('97a1a9ef-68a2-467b-9ff4-647d9f50170f','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',14,'queued','f56b1cb8-a1eb-4aed-88cc-c8a5de5fbf8b',NULL,false),
('9a0ef8b8-6523-40a8-9691-8eac49242f3d','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',16,'queued','ee4b0dc7-9744-4afa-bbb0-d68a22a69100',NULL,false),
('9d70ad32-e836-4167-b162-253119e0eb21','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',6,'completed','93c0e843-d95a-4633-9e03-37a8aad60ddb',NULL,false),
('9e83e9e0-9505-41b4-b971-b3db6e81d777','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',18,'queued','3bf9f21a-e60a-4abb-85e9-15ecc715f10e',NULL,false),
('9f6d8626-232e-494e-ae28-1b4e54dfda0e','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',33,'queued','7408958e-ff6a-40ac-a3ac-04d4f21da355',NULL,false),
('9fef9171-bee1-4216-9b7f-3000a659efd7','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',17,'queued','d3d412de-9d30-4d2a-b17d-57a33c7b6e2c',NULL,false),
('a21c97bf-6662-4333-a0a5-c122f814f5bc','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',5,'skipped','f209991c-f637-4ca9-9d85-b60f7dd37b8f',NULL,false),
('a2386057-559e-495a-8851-3629ec99556f','f9200000-0000-4000-8000-000000000002','anna_soil_block_1_5_sequence',2,'queued','e9fd45e3-4a2c-48f5-801c-2339b5d20ab4',NULL,false),
('a2c0883e-4b4f-4491-8f5e-394501cfed16','f9200000-0000-4000-8000-000000000002','field_rows_weeding_rotation',2,'active','69ebb995-a33e-4b53-8f62-a6c0d90a055f',NULL,true),
('a31a9f67-b7eb-4448-87ce-4bb006ca86f7','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',25,'queued','8476fd15-0afe-4635-83aa-9eedc102c3ea',NULL,false),
('a3ef88a8-f630-464e-8810-b9f11e712100','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',13,'queued','5017f3e5-f6ca-46cf-b46e-4b0cda5473e1',NULL,false),
('a421bfb2-228a-4409-83c1-65bcbd5571a8','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',8,'queued','b86f8bd8-0702-4631-9665-24f6bfec807f',NULL,false),
('a8d6cabe-473a-46f9-b6d0-0a1ae33c40cc','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',5,'queued','3dc281d4-0b0f-400b-9200-d3dc7848cd1b',NULL,false),
('aaeaa977-43d5-4d49-8938-b4a17bd9a805','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',9,'completed','c2dadb6e-1a01-4bcd-969b-d45a100f9206',NULL,false),
('ac321fef-5914-40d8-8a1f-7ac47507844b','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',31,'queued','5194c0f3-200d-4ee8-be8d-ec6fac318e75',NULL,false),
('b0e12dc1-80df-4191-b952-7483368e997e','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',27,'queued','84f460f2-a0f3-4e3d-a2b4-dee711ceb326',NULL,false),
('b1bc5632-3cd7-4f50-8051-af8c08c9c88c','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',15,'queued','c8220427-8986-4f5c-8c7f-44e530f27116',NULL,false),
('b1e53137-39bc-46a6-bb38-7212f7a7655b','f9200000-0000-4000-8000-000000000002','anna_gentle_pressure_wash_aug_2026',1,'active','47d1b521-db03-45fd-bf0c-3ed951c2b949',NULL,false),
('b210503c-b790-4e69-bed3-1c0ef1d35125','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',7,'queued','d99dcf33-c0c5-4182-b56c-731dca45f6d4',NULL,false),
('b4d31cc8-d538-487e-af43-35b7a6d00fc4','f9200000-0000-4000-8000-000000000002','anna_gentle_pressure_wash_aug_2026',3,'queued','6e012007-8cee-49f0-b61d-7b02d5b26577',NULL,false),
('b5470a31-3117-426a-b1fe-b5a9c3269bcc','f9200000-0000-4000-8000-000000000002','anna_pot_up_serial',9,'queued','da49b391-30a2-4983-a171-08e13acc724d',NULL,false),
('b7fea409-d9c1-46e6-8c0c-747b31c564b4','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',34,'skipped','96cf7742-872d-4c74-9c55-8f32a38aa540',NULL,false),
('b944b0dc-d696-498f-bfb9-03ab7c0791a0','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',21,'skipped','351df645-bd66-43cc-ab82-3e1998e64930',NULL,false),
('b964d62c-bc09-4380-bf67-e08a0167acee','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',26,'queued','da414681-303a-4d71-8578-afb6d562a5c2',NULL,false),
('bc652547-bc58-47be-82cf-8b09a41de970','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',13,'queued','3633c00d-fa7d-4af7-b086-46d9cc9d470b',NULL,false),
('bd5c0951-3ee3-4a62-813d-80559b89b0b4','f9200000-0000-4000-8000-000000000002','field_rows_weeding_rotation',5,'completed',NULL,NULL,false),
('bd6959c5-3bfc-41bb-b71b-74105e1c0586','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',10,'queued','b72e782d-00db-41c2-a3f5-72054697833c',NULL,false),
('c47efa60-2ea4-4d1a-8c75-0f390bc98e44','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',2,'active','5d6123f4-ba5d-43c6-9185-816143bcc754','e05f3870-7c74-47d5-9998-483aa238f115',false),
('c8e3c86a-fe8f-42ce-90e2-5c13ebef0b8b','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',3,'queued','0611f96a-7819-4334-a802-0007593b3a18',NULL,false),
('caf03b04-9c7b-4268-b6d4-e9e0340e9353','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',14,'queued','159047a7-01f8-4ef2-964d-b48a3e2ea5f6',NULL,false),
('cbe98a4b-b495-4059-840e-6f5a56fe80df','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',28,'queued','2382df25-d101-46fe-9a58-68c7b619f609',NULL,false),
('cf4eef95-779b-4240-82c1-0ab0960147db','f9200000-0000-4000-8000-000000000002','anna_soil_block_1_5_sequence',1,'active','4f39bad5-e516-48f8-accd-00509da7c89e',NULL,false),
('e0394754-02a9-41e7-9811-d2ae86648775','f9200000-0000-4000-8000-000000000002','owner_venue_marketing_queue',2,'queued','71ef03fa-36ff-4a54-bdad-dfe5336014c9','63ade0e9-28bc-4543-805f-d2c82d678315',false),
('e03f7f5f-eda1-4505-b359-2c614b98ab83','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',28,'queued','45c02ef3-1b9b-496e-99de-23cb14bf1980',NULL,false),
('eb71f510-5677-4c97-85db-39796e6f29ab','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',23,'queued','95791562-d68a-4d88-a2e3-8a436969a8ba',NULL,false),
('eb8d94e8-fa6e-4772-a6ff-9cc39f69ae84','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',1,'completed','9493e0d2-405b-44bb-8876-e41c41ea43f5',NULL,false),
('ed8a3581-d2d2-44fa-b7f5-39cceb03bacd','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',9,'queued','e2a18027-2045-4c9b-ad34-c8cfe49082ea',NULL,false),
('ee79e1db-5ed0-4be3-838b-f1bfa141c870','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',8,'queued','ca38f851-d8a3-4ec0-a70e-3c0ad9ae2d62',NULL,false),
('f34c3bb0-99d5-41e2-a4e1-dffe6d0f61a2','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',21,'queued','3a49f953-2baf-4ca0-9ce1-c231173ff67c',NULL,false),
('f3d0f746-cd22-4df8-af9b-069098d2c4d8','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',11,'queued','4123b60e-1c48-4f83-96ef-eed305bdd3d4',NULL,false),
('f5eda2f1-7060-436d-a8b8-6ac031d2b90f','f9200000-0000-4000-8000-000000000002','anna_weeding_rotation',30,'queued','4062bc17-dae5-4a13-918b-fe11cd89f91e',NULL,false),
('faad9d75-bdcb-49b4-ae2c-027f6fa52f1f','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',27,'queued','ce028b29-d46f-4f7e-a802-0e4862e701c8',NULL,false),
('fed45925-a79f-4178-9625-56160d6c4bd2','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',11,'queued','f07002a0-7cc0-4f02-8710-8802086a32af',NULL,false),
('ffb39773-9bb5-4b7d-9209-87f93e7875d8','f9200000-0000-4000-8000-000000000002','owner_social_content_queue',1,'completed','9007f67e-2c6a-4582-ace4-69b896a8a832',NULL,false);
