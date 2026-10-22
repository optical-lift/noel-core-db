-- Source-only candidate: PostgREST membrane for governed service-role recovery worker.
-- Nothing here authorizes anon or authenticated browser RPC.
BEGIN;

CREATE OR REPLACE FUNCTION public.service_person_email_recovery_candidates_v1(p_actor uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_person_email_recovery_candidates_v1(p_actor);
$fn$;
REVOKE ALL ON FUNCTION public.service_person_email_recovery_candidates_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_person_email_recovery_candidates_v1(uuid)
 TO service_role;

CREATE OR REPLACE FUNCTION public.service_begin_person_email_recovery_v1(p_actor uuid,p_person uuid,p_destination text,p_challenge_hash text,p_basis text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_begin_person_email_recovery_v1(p_actor,p_person,p_destination,p_challenge_hash,p_basis);
$fn$;
REVOKE ALL ON FUNCTION public.service_begin_person_email_recovery_v1(uuid,uuid,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_begin_person_email_recovery_v1(uuid,uuid,text,text,text)
 TO service_role;

CREATE OR REPLACE FUNCTION public.service_verify_person_email_recovery_v1(p_case uuid,p_code_hash text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_verify_person_email_recovery_v1(p_case,p_code_hash);
$fn$;
REVOKE ALL ON FUNCTION public.service_verify_person_email_recovery_v1(uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_verify_person_email_recovery_v1(uuid,text)
 TO service_role;

CREATE OR REPLACE FUNCTION public.service_approve_person_email_recovery_v1(p_case uuid,p_reviewer uuid,p_method text,p_basis text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_approve_person_email_recovery_v1(p_case,p_reviewer,p_method,p_basis);
$fn$;
REVOKE ALL ON FUNCTION public.service_approve_person_email_recovery_v1(uuid,uuid,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_approve_person_email_recovery_v1(uuid,uuid,text,text)
 TO service_role;

CREATE OR REPLACE FUNCTION public.service_prepare_person_email_recovery_v1(p_case uuid,p_reviewer uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_prepare_person_email_recovery_v1(p_case,p_reviewer);
$fn$;
REVOKE ALL ON FUNCTION public.service_prepare_person_email_recovery_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_prepare_person_email_recovery_v1(uuid,uuid)
 TO service_role;

CREATE OR REPLACE FUNCTION public.service_finish_person_email_recovery_v1(p_case uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_finish_person_email_recovery_v1(p_case);
$fn$;
REVOKE ALL ON FUNCTION public.service_finish_person_email_recovery_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_finish_person_email_recovery_v1(uuid)
 TO service_role;

CREATE OR REPLACE FUNCTION public.service_reject_person_email_recovery_v1(p_case uuid,p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
  SELECT atlas.service_reject_person_email_recovery_v1(p_case,p_reason);
$fn$;
REVOKE ALL ON FUNCTION public.service_reject_person_email_recovery_v1(uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.service_reject_person_email_recovery_v1(uuid,text)
 TO service_role;
COMMIT;