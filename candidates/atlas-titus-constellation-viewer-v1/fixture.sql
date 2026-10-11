-- Disposable production-schema-clone fixture ONLY. No real users, grants, or emails.
INSERT INTO auth.users(id,aud,role,created_at,updated_at)
VALUES
 ('10000000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now()),
 ('10000000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now());

INSERT INTO auth.oauth_clients(
 id,registration_type,redirect_uris,grant_types,client_name,client_type,token_endpoint_auth_method
) VALUES
 ('10000000-0000-4000-8000-000000000101','manual','["https://titus.test.invalid/auth/callback"]',
 '["authorization_code"]','Titus fixture public','public','none'),
 ('10000000-0000-4000-8000-000000000102','manual','["https://other.test.invalid/auth/callback"]',
 '["authorization_code"]','Unrelated fixture public','public','none');

INSERT INTO auth.sessions(id,user_id,created_at,updated_at,not_after,oauth_client_id)
VALUES
 ('10000000-0000-4000-8000-000000000201','10000000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 day',NULL),
 ('10000000-0000-4000-8000-000000000202','10000000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 day','10000000-0000-4000-8000-000000000101'),
 ('10000000-0000-4000-8000-000000000203','10000000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 day',NULL),
 ('10000000-0000-4000-8000-000000000204','10000000-0000-4000-8000-000000000001',now(),now(),now()-interval '1 minute',NULL);

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state)
VALUES
 ('10000000-0000-4000-8000-000000000301','test-titus-person-1','person','Titus Fixture Person 1','canonical'),
 ('10000000-0000-4000-8000-000000000302','test-titus-person-2','person','Titus Fixture Person 2','canonical');

INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis)
VALUES
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000301','active','{"fixture":true}'),
 ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000302','active','{"fixture":true}');

INSERT INTO atlas.principals(id,user_id,stable_key,name)
VALUES('10000000-0000-4000-8000-000000000401',
'10000000-0000-4000-8000-000000000001','titus-fixture-reviewer','Titus Fixture Reviewer');
