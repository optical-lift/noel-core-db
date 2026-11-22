-- Reuse the existing shared-listening isolated PG17 Auth/source subset.
-- No parallel schema or test environment. All identities are FICTIONAL;
-- claim GUCs remain UNSIGNED and never constitute cryptographic proof.
-- Existing generated_production_fixture.sql owns auth schema, auth.uid(),
-- auth.jwt(), auth.users/sessions and workspace_memberships.
ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false;
ALTER TABLE transcript_core.delivery_profiles ALTER COLUMN id SET DEFAULT gen_random_uuid();
-- Earlier listening fixture intentionally models only fields used by its
-- original proof; extend it with these existing LIVE profile fields.
ALTER TABLE transcript_core.delivery_profiles
  ADD COLUMN profile_key text NOT NULL DEFAULT 'fixture-default',
  ADD COLUMN display_name text NOT NULL DEFAULT 'fixture-default';
ALTER TABLE transcript_core.delivery_profiles
  ADD CONSTRAINT delivery_profiles_workspace_id_profile_key_rule_version_key
  UNIQUE (workspace_id,profile_key,rule_version);
REVOKE ALL ON transcript_core.delivery_profiles FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE transcript_core.delivery_profiles ENABLE ROW LEVEL SECURITY;
INSERT INTO transcript_core.workspaces(id) VALUES
 ('00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000002');
INSERT INTO auth.users (id,email_confirmed_at) VALUES
 ('00000000-0000-0000-0000-000000001101',clock_timestamp()),
 ('00000000-0000-0000-0000-000000001102',clock_timestamp()),
 ('00000000-0000-0000-0000-000000001103',clock_timestamp()),
 ('00000000-0000-0000-0000-000000001104',clock_timestamp());
INSERT INTO auth.sessions (id,user_id,not_after) VALUES
 ('00000000-0000-0000-0000-000000002101',
  '00000000-0000-0000-0000-000000001101',clock_timestamp()+interval '1 hour'),
 ('00000000-0000-0000-0000-000000002102',
  '00000000-0000-0000-0000-000000001102',clock_timestamp()+interval '1 hour'),
 ('00000000-0000-0000-0000-000000002103',
  '00000000-0000-0000-0000-000000001103',clock_timestamp()+interval '1 hour'),
 ('00000000-0000-0000-0000-000000002104',
  '00000000-0000-0000-0000-000000001104',clock_timestamp()+interval '1 hour');
INSERT INTO transcript_core.workspace_memberships(workspace_id,user_id,role) VALUES
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000001101','owner'),
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000001102','editor'),
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000001103','viewer'),
 ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000001101','owner');
