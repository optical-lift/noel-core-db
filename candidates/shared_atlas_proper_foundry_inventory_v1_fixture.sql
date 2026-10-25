-- DML-only; synthetic users in an isolated local clone.
INSERT INTO auth.users(id,aud,role,created_at,updated_at,is_anonymous)
VALUES
('f1900000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now(),false);

INSERT INTO atlas.principals(id,user_id,stable_key,name,status)
VALUES ('f1900000-0000-4000-8000-000000000202',
'f1900000-0000-4000-8000-000000000002',
'fictional-non-practitioner-20261025','Fictional Personal Principal','active');

INSERT INTO atlas.implementation_practitioners(human_user_id,status,authorization_basis)
VALUES ('f1900000-0000-4000-8000-000000000001','active',
jsonb_build_object('synthetic','signed-discovery-fixture'));
