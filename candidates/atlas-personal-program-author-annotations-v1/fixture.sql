-- Disposable production-schema clone ONLY. No DO/ROLE/JWT impersonation.
-- Reuses the established fictional GoTrue Program v2 identities so the
-- source-specific signed note proof can obtain genuine local JWT sessions.
-- Never use this file against production or with real human records.
-- Disposable production-schema clone ONLY. Fictional Principal identities.
-- Source-owned signed Program author proof, no production or private user facts.
INSERT INTO auth.users(id,aud,role,created_at,updated_at) VALUES
 ('a1580000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now()),
 ('a1580000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now()),
 ('a1580000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now());

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state) VALUES
 ('a1580000-0000-4000-8000-000000000101','program-proof-author','person','Synthetic Program Author','canonical'),
 ('a1580000-0000-4000-8000-000000000102','program-proof-other','person','Synthetic Program Other','canonical');

INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) VALUES
 ('a1580000-0000-4000-8000-000000000001','a1580000-0000-4000-8000-000000000101','active','{"synthetic":true}'),
 ('a1580000-0000-4000-8000-000000000002','a1580000-0000-4000-8000-000000000102','active','{"synthetic":true}');

INSERT INTO atlas.people(id,display_name,status) VALUES
 ('a1580000-0000-4000-8000-000000000101','Synthetic Program Author','active'),
 ('a1580000-0000-4000-8000-000000000102','Synthetic Program Other','active');

INSERT INTO atlas.person_auth_credentials(person_id,credential_kind,auth_user_id,status,provenance) VALUES
 ('a1580000-0000-4000-8000-000000000101','supabase_auth_user','a1580000-0000-4000-8000-000000000001','active','{"synthetic":true}'),
 ('a1580000-0000-4000-8000-000000000102','supabase_auth_user','a1580000-0000-4000-8000-000000000002','active','{"synthetic":true}');

INSERT INTO atlas.principals(id,user_id,person_id,stable_key,name,status) VALUES
 ('a1580000-0000-4000-8000-000000000201','a1580000-0000-4000-8000-000000000001','a1580000-0000-4000-8000-000000000101','program-proof-principal-author','Synthetic Program Author','active'),
 ('a1580000-0000-4000-8000-000000000202','a1580000-0000-4000-8000-000000000002','a1580000-0000-4000-8000-000000000102','program-proof-principal-other','Synthetic Program Other','active');

INSERT INTO atlas.personal_atlas_access_grants(id,principal_id,grant_kind,state,basis) VALUES
 ('a1580000-0000-4000-8000-000000000301','a1580000-0000-4000-8000-000000000201','test_fixture','active','{"synthetic":true}'),
 ('a1580000-0000-4000-8000-000000000302','a1580000-0000-4000-8000-000000000202','test_fixture','active','{"synthetic":true}');
