BEGIN;

-- Atlas owns the grant. Identity is the existing canonical reality person
-- established by Atlas; Titus does not create a parallel Person or login.
CREATE TABLE atlas.titus_constellation_viewer_grants (
  grant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
  access_level text NOT NULL DEFAULT 'read_only' CHECK (access_level='read_only'),
  grant_state text NOT NULL CHECK (grant_state IN ('active','revoked')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  reviewed_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
  authority_basis text NOT NULL CHECK (length(btrim(authority_basis)) >= 12),
  established_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK ((grant_state='active' AND revoked_at IS NULL)
      OR (grant_state='revoked' AND revoked_at IS NOT NULL))
);
CREATE INDEX titus_constellation_viewer_grants_person_live_idx
 ON atlas.titus_constellation_viewer_grants(person_entity_id,grant_state,valid_from,valid_until);

-- No implicit enrollment, no browser DML, and no owner shortcut.
ALTER TABLE atlas.titus_constellation_viewer_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.titus_constellation_viewer_grants FROM PUBLIC,anon,authenticated;
GRANT SELECT ON atlas.titus_constellation_viewer_grants TO service_role;

-- A service-only fresh authorization decision, bound to a real, non-expired,
-- OAuth-client-scoped Supabase Auth session and a non-retired Atlas Person.
-- This does NOT mint identities, sessions, permissions, or tokens.
CREATE OR REPLACE FUNCTION public.titus_constellation_viewer_allowed_v1(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_oauth_client_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $body$
SELECT COALESCE(EXISTS (
 SELECT 1
 FROM auth.sessions sess
 JOIN auth.oauth_clients client
   ON client.id=sess.oauth_client_id AND client.deleted_at IS NULL
 JOIN reality.auth_person_bindings binding
   ON binding.auth_user_id=sess.user_id
  AND binding.binding_state='active'
  AND binding.retired_at IS NULL
 JOIN reality.entities person
   ON person.id=binding.person_entity_id
  AND person.entity_kind='person'
  AND person.identity_state='canonical'
 JOIN atlas.titus_constellation_viewer_grants grant_record
   ON grant_record.person_entity_id=person.id
  AND grant_record.access_level='read_only'
  AND grant_record.grant_state='active'
  AND grant_record.valid_from<=now()
  AND (grant_record.valid_until IS NULL OR grant_record.valid_until>now())
  AND grant_record.revoked_at IS NULL
 WHERE sess.id=p_session_id AND sess.user_id=p_auth_user_id
   AND sess.oauth_client_id=p_oauth_client_id
   AND (sess.not_after IS NULL OR sess.not_after>now())
),false);
$body$;
REVOKE ALL ON FUNCTION public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)
 TO service_role;


-- Atlas-native access uses the same Person and grant, but an ordinary Atlas
-- login session is NOT an OAuth-client session. Do not misuse the standalone
-- Titus OAuth function or invent a second account/grant.
CREATE OR REPLACE FUNCTION public.titus_constellation_atlas_native_allowed_v1(
  p_auth_user_id uuid,
  p_session_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $atlas$
SELECT COALESCE(EXISTS (
 SELECT 1
 FROM auth.sessions sess
 JOIN reality.auth_person_bindings binding
   ON binding.auth_user_id=sess.user_id
  AND binding.binding_state='active'
  AND binding.retired_at IS NULL
 JOIN reality.entities person
   ON person.id=binding.person_entity_id
  AND person.entity_kind='person'
  AND person.identity_state='canonical'
 JOIN atlas.titus_constellation_viewer_grants grant_record
   ON grant_record.person_entity_id=person.id
  AND grant_record.access_level='read_only'
  AND grant_record.grant_state='active'
  AND grant_record.valid_from<=now()
  AND (grant_record.valid_until IS NULL OR grant_record.valid_until>now())
  AND grant_record.revoked_at IS NULL
 WHERE sess.id=p_session_id AND sess.user_id=p_auth_user_id
   AND sess.oauth_client_id IS NULL
   AND (sess.not_after IS NULL OR sess.not_after>now())
),false);
$atlas$;
REVOKE ALL ON FUNCTION public.titus_constellation_atlas_native_allowed_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.titus_constellation_atlas_native_allowed_v1(uuid,uuid)
 TO service_role;

COMMIT;
