-- HELD: Atlas service-only transport facade. No carrier, credential or grant rows.
BEGIN;
CREATE FUNCTION public.shared_delegated_course_prepare_service_v1(p_token_hash text,p_course uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog
AS $prepare$ SELECT atlas.prepare_course_authoring_proposal_service_v1(p_token_hash,p_course,p_proposal); $prepare$;
CREATE FUNCTION public.shared_delegated_course_apply_service_v1(p_token_hash text,p_invocation uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog
AS $apply$ SELECT atlas.apply_course_authoring_proposal_service_v1(p_token_hash,p_invocation,p_proposal); $apply$;
REVOKE ALL ON FUNCTION public.shared_delegated_course_prepare_service_v1(text,uuid,jsonb), public.shared_delegated_course_apply_service_v1(text,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_prepare_service_v1(text,uuid,jsonb), public.shared_delegated_course_apply_service_v1(text,uuid,jsonb) TO service_role;
COMMIT;
