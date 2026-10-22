-- Source-only candidate: PostgREST membrane for governed service-role recovery worker.
-- Nothing here authorizes anon or authenticated browser RPC.
BEGIN;

-- Reconcile reviewer jurisdiction to the canonical institutional Person relation.
-- Historical organization_memberships is an optional credential seat, not a
-- necessary condition of belonging to a Ledger or organization.
CREATE OR REPLACE FUNCTION atlas.service_person_email_recovery_reviewer_v1(
 p_actor uuid,p_person uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog' AS $fn$
 SELECT p_actor IS NOT NULL AND p_person IS NOT NULL AND
   EXISTS (SELECT 1 FROM atlas.principals pr
           WHERE pr.user_id=p_actor AND pr.status='active') AND
   EXISTS (
     SELECT 1
     FROM atlas.institutional_person_records subject
     JOIN atlas.organizations o ON o.id=subject.organization_id
       AND o.status='active'
     JOIN atlas.organization_memberships owner
       ON owner.organization_id=subject.organization_id
     WHERE subject.person_id=p_person AND subject.status='active'
       AND owner.user_id=p_actor AND owner.active AND owner.role='owner'
       AND owner.person_id IS DISTINCT FROM p_person
   );
$fn$;

CREATE OR REPLACE FUNCTION atlas.service_person_email_recovery_candidates_v1(
 p_actor uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog' AS $fn$
 SELECT jsonb_build_object(
   'ok',true,'contractVersion','person_email_recovery_candidates_v1',
   'people',coalesce(jsonb_agg(jsonb_build_object(
     'personId',eligible.id,'displayName',eligible.display_name,
     'organizationName',eligible.organization_name,
     'hasLegacyCredential',true)
     ORDER BY eligible.display_name,eligible.organization_name),'[]'::jsonb)
 )
 FROM (
   SELECT DISTINCT ON (p.id,o.id) p.id,p.display_name,
      o.name AS organization_name
   FROM atlas.people p
   JOIN atlas.institutional_person_records ipr ON ipr.person_id=p.id
     AND ipr.status='active'
   JOIN atlas.organizations o ON o.id=ipr.organization_id
     AND o.status='active'
   JOIN atlas.organization_memberships owner ON owner.organization_id=o.id
     AND owner.user_id=p_actor AND owner.active AND owner.role='owner'
   JOIN atlas.person_auth_credentials credential ON credential.person_id=p.id
     AND credential.credential_kind='supabase_auth_user'
     AND credential.status='active' AND credential.retired_at IS NULL
   WHERE p.status='active' AND
     EXISTS (SELECT 1 FROM atlas.principals pr
       WHERE pr.user_id=p_actor AND pr.status='active')
     AND NOT EXISTS (SELECT 1 FROM atlas.principals old
       WHERE old.person_id=p.id AND old.status='active')
   ORDER BY p.id,o.id LIMIT 100
 ) eligible;
$fn$;


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