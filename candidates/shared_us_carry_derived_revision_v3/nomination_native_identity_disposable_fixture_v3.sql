-- DISPOSABLE POSTGRES TEST ONLY.
-- Minimal shape of actual 20260925014915 reality.entities,
-- reality.auth_person_bindings, and auth.users, solely for a Us financial-only
-- test cluster. Not part of, nor replacement for, the Noel shared identity
-- schema in protected clones or production. No genuine Auth people or data.
BEGIN;
CREATE SCHEMA auth;
CREATE SCHEMA reality;
CREATE TABLE auth.users(
 id uuid PRIMARY KEY,
 deleted_at timestamptz,
 is_anonymous boolean NOT NULL DEFAULT false,
 banned_until timestamptz
);
CREATE TABLE reality.entities(
 id uuid PRIMARY KEY,
 entity_kind text NOT NULL,
 identity_state text NOT NULL
   CHECK (identity_state IN ('canonical','disputed','retired'))
);
CREATE TABLE reality.auth_person_bindings(
 id uuid PRIMARY KEY,
 auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
 binding_state text NOT NULL CHECK(binding_state IN ('active','retired')),
 retired_at timestamptz
);
REVOKE ALL ON SCHEMA auth,reality FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
REVOKE ALL ON ALL TABLES IN SCHEMA auth,reality
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
COMMIT;
