-- HELD source-only: two exact private Transcript Core receipt callbacks.
-- No production migration, login, credential, HTTP host or publication.
-- The real signed host MUST verify GoTrue /auth/v1/user, current session and
-- private Storage bytes, then set only the server-verified claims as LOCAL
-- transaction GUCs. Existing invoker functions recheck source/session under
-- their own locks. This executor role deliberately has NOLOGIN.
--
-- This privileged wrapper is acceptable only inside the UNEXPOSED
-- transcript_core schema, never public, with exact role-only EXECUTE.
-- The host's future credential custody and independent approval are
-- separate prerequisites to any live release.
BEGIN;

DO $preflight$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='transcript_core_private_callback_executor_v1')
  THEN RAISE EXCEPTION 'Private callback executor role already exists: reconcile custody first';
  END IF;
  IF to_regprocedure('transcript_core.register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)') IS NULL
     OR to_regprocedure('transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'Released native original and completion functions required';
  END IF;
END $preflight$;

CREATE ROLE transcript_core_private_callback_executor_v1
  NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS;

-- This is the EXISTING private native source schema, not a Data API route.
-- Only these exact two wrappers are granted; no tables, auth schema, or
-- underlying invoker function permissions are granted to the role.
GRANT USAGE ON SCHEMA transcript_core
  TO transcript_core_private_callback_executor_v1;

CREATE FUNCTION transcript_core.private_register_verified_manuscript_original_v1(
  p_workspace_id uuid,p_object_id uuid,p_object_version text,
  p_original_sha256 text,p_original_byte_size bigint,p_original_format text
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog AS $private_original$
  SELECT transcript_core.register_verified_manuscript_original_v1(
    p_workspace_id,p_object_id,p_object_version,
    p_original_sha256,p_original_byte_size,p_original_format)
$private_original$;

CREATE FUNCTION transcript_core.private_complete_verified_listening_production_v1(
  p_production_id uuid,p_manuscript_revision_id uuid,p_master_ordinal integer,
  p_delivery_profile_id uuid,p_profile_rule_version text,
  p_profile_configuration jsonb,p_timeline_manifest jsonb,p_evidence jsonb
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog AS $private_completion$
  SELECT transcript_core.complete_verified_listening_production_v1(
    p_production_id,p_manuscript_revision_id,p_master_ordinal,
    p_delivery_profile_id,p_profile_rule_version,p_profile_configuration,
    p_timeline_manifest,p_evidence)
$private_completion$;

REVOKE ALL ON FUNCTION
  transcript_core.private_register_verified_manuscript_original_v1(
    uuid,uuid,text,text,bigint,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  transcript_core.private_complete_verified_listening_production_v1(
    uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION
  transcript_core.private_register_verified_manuscript_original_v1(
    uuid,uuid,text,text,bigint,text)
  TO transcript_core_private_callback_executor_v1;
GRANT EXECUTE ON FUNCTION
  transcript_core.private_complete_verified_listening_production_v1(
    uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)
  TO transcript_core_private_callback_executor_v1;

COMMENT ON ROLE transcript_core_private_callback_executor_v1 IS
  'HELD private listening fixed-function callback only; NOLOGIN; external credential custody/release separately governed';
COMMENT ON FUNCTION transcript_core.private_register_verified_manuscript_original_v1(
  uuid,uuid,text,text,bigint,text) IS
  'Fixed SECURITY DEFINER wrapper for signed private original only; no public access or independent authorization';
COMMENT ON FUNCTION transcript_core.private_complete_verified_listening_production_v1(
  uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb) IS
  'Fixed SECURITY DEFINER wrapper for signed private completion only; never publisher or listener authority';

COMMIT;
