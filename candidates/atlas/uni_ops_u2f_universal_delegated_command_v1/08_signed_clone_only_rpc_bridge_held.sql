-- U2F 08: DISPOSABLE-CLONE-ONLY HTTP bridge SOURCE. DO NOT INSTALL.
-- FOR A SEPARATELY OWNER-AUTHORIZED CURRENT-SCHEMA/ROLES-ONLY CLONE TEST.
-- This is not a migration, production RPC, new Work writer, or governing grant.
--
-- Requires an authorized external harness to prove the exact loopback-only
-- Supabase/GoTrue/PostgREST deployment and immutable source authorization.
-- No workflow / deployment / RLS / production permission changes may be
-- inferred from the existence of this file. Do not use psql against Noel live.
--
-- A SQL setting or fake fixture ID is NOT evidence of an isolated system.
-- The checks below are additional barriers only, not replacements for the
-- owner-protected environment gate. This file never runs in ordinary CI.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='20s';
DO $local_u2f$
BEGIN
  IF current_database() <> 'postgres'
    OR current_setting('uniops.disposable_signed',true)
         IS DISTINCT FROM 'u2f_owner_authorized_clone_only_v1'
    OR (SELECT count(*) FROM atlas.principal_ledger_authorities r
         WHERE r.id='e5200000-0000-4000-8000-000000000601'::uuid
           AND r.authority_kind='root_governing'
           AND r.status='active')<>1
    OR (SELECT count(*) FROM atlas.principal_ledger_authorities r
         WHERE r.id='e5200000-0000-4000-8000-000000000602'::uuid
           AND r.authority_kind='root_governing'
           AND r.status='active')<>1
    OR (SELECT count(*) FROM auth.users u WHERE u.id IN
         ('e5200000-0000-4000-8000-000000000001'::uuid,
          'e5200000-0000-4000-8000-000000000002'::uuid,
          'e5200000-0000-4000-8000-000000000003'::uuid,
          'e5200000-0000-4000-8000-000000000004'::uuid))<>4
    OR pg_catalog.to_regprocedure('atlas.uni_ops_u2f_root_reaffirm_held_v1(uuid,uuid,text)') IS NULL
    OR pg_catalog.to_regprocedure('atlas.uni_ops_u2f_root_revoke_held_v1(uuid,text)') IS NULL
  THEN
    RAISE EXCEPTION 'U2F signed clone only: exact authorized disposable fixture not proven'
      USING ERRCODE='42501';
  END IF;
END
$local_u2f$;

-- Private implementation remains hidden in atlas; this bridge is a narrowly
-- scoped disposable test transport ONLY. SECURITY DEFINER under privileged
-- local Postgres is necessary here because a private atlas schema is not
-- exposed by PostgREST. auth.uid/auth.jwt must still come from the *actual*
-- signed PostgREST token. SECURITY DEFINER is NEVER blanket authority.
CREATE FUNCTION public.uni_ops_u2f_signed_clone_reaffirm_v1(
  p_original_root_id uuid,p_native_ledger_id uuid,p_explicit_attestation text
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER
SET search_path TO ''
AS $bridge$
  SELECT atlas.uni_ops_u2f_root_reaffirm_held_v1($1,$2,$3);
$bridge$;

CREATE FUNCTION public.uni_ops_u2f_signed_clone_revoke_v1(
  p_native_responsibility_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER
SET search_path TO ''
AS $bridge$
  SELECT atlas.uni_ops_u2f_root_revoke_held_v1($1,$2);
$bridge$;

REVOKE ALL ON FUNCTION
 public.uni_ops_u2f_signed_clone_reaffirm_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
 public.uni_ops_u2f_signed_clone_revoke_v1(uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
-- Disposable clone only: signed authenticated test actors can reach the
-- source-owned invariant checks; no table permission or service access given.
GRANT EXECUTE ON FUNCTION
 public.uni_ops_u2f_signed_clone_reaffirm_v1(uuid,uuid,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION
 public.uni_ops_u2f_signed_clone_revoke_v1(uuid,text)
 TO authenticated;
COMMIT;
