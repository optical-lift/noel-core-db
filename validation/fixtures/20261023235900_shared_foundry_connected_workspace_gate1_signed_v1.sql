-- DML-only synthetic users for actual signed GoTrue + PostgREST local test.
-- This file is applied exclusively to a disposable full production-schema clone.
-- No real user, live session, or external subject is included.
insert into auth.users(id,aud,role,created_at,updated_at,is_anonymous)
values
('f1900000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now(),false);

insert into atlas.principals(id,user_id,stable_key,name,status)
values
('f1900000-0000-4000-8000-000000000201','f1900000-0000-4000-8000-000000000001','foundry-local-signed-owner','Fictional Foundry owner','active'),
('f1900000-0000-4000-8000-000000000202','f1900000-0000-4000-8000-000000000002','foundry-local-signed-other','Fictional unrelated Principal','active');

-- A separate genuinely signed outsider with misleading user-editable metadata.
insert into auth.users(id,aud,role,created_at,updated_at,is_anonymous)
values('f1900000-0000-4000-8000-000000000004','authenticated','authenticated',now(),now(),false);
insert into atlas.principals(id,user_id,stable_key,name,status)
values('f1900000-0000-4000-8000-000000000204','f1900000-0000-4000-8000-000000000004','foundry-local-signed-outsider','Fictional unassigned reviewer outsider','active');
