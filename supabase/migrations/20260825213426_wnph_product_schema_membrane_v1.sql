create schema if not exists wnph authorization postgres;
create schema if not exists wnph_api authorization postgres;

comment on schema wnph is
  'Write Now Publishing House canonical publication custody. Private by default; application access must cross an explicit wnph_api boundary.';

comment on schema wnph_api is
  'Write Now Publishing House application API boundary. Objects are private by default and must be granted explicitly.';

-- Canonical publishing custody is never directly exposed to application roles.
revoke all on schema wnph from public, anon, authenticated, service_role;
revoke all on schema wnph_api from public, anon, authenticated, service_role;

-- Future objects created by the migration owner remain closed unless a later
-- migration explicitly grants a narrow application surface.
alter default privileges in schema wnph revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema wnph revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema wnph revoke all on functions from public, anon, authenticated, service_role;

alter default privileges in schema wnph_api revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema wnph_api revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema wnph_api revoke all on functions from public, anon, authenticated, service_role;

-- Fail the migration if the membrane is not actually closed.
do $$
declare
  role_name text;
begin
  foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
    if has_schema_privilege(role_name, 'wnph', 'USAGE')
       or has_schema_privilege(role_name, 'wnph', 'CREATE') then
      raise exception 'WNPH membrane violation: role % still has direct privilege on schema wnph', role_name;
    end if;

    if has_schema_privilege(role_name, 'wnph_api', 'USAGE')
       or has_schema_privilege(role_name, 'wnph_api', 'CREATE') then
      raise exception 'WNPH API membrane violation: role % has privilege before an explicit API grant exists', role_name;
    end if;
  end loop;
end
$$;
