-- Validation-only Principal created before the migration so clone validation
-- proves the migration backfills existing active Principals.

insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous)
values('55555555-5555-4555-8555-555555555555','authenticated','authenticated','connections-spread-fixture@example.invalid',now(),now(),false,false);

insert into atlas.principals(id,user_id,stable_key,name,status,metadata)
values('66666666-6666-4666-8666-666666666666','55555555-5555-4555-8555-555555555555','fixture-connections-spread','Connections Spread Fixture','active','{}'::jsonb);