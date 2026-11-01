-- DISPOSABLE GoTrue signed HTTP test ONLY.
-- GoTrue already provisioned its *real ephemeral* auth.users table.
-- Mirror just the two canonical Reality identity tables from the Noel
-- 20260925014915 native source; these are fixtures, never a release migration.
BEGIN;
CREATE SCHEMA reality;
CREATE TABLE reality.entities(
 id uuid PRIMARY KEY,
 entity_kind text NOT NULL,
 identity_state text NOT NULL CHECK(identity_state IN ('canonical','disputed','retired'))
);
CREATE TABLE reality.auth_person_bindings(
 id uuid PRIMARY KEY,
 auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 binding_state text NOT NULL CHECK(binding_state IN ('active','retired')),
 retired_at timestamptz
);
REVOKE ALL ON SCHEMA reality FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
REVOKE ALL ON ALL TABLES IN SCHEMA reality
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
COMMIT;
