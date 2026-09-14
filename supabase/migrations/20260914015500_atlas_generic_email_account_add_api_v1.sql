begin;

-- Atlas generic email account add API v1
--
-- The owner-authorized setup contract already exists inside the governed Atlas
-- schema. This migration exposes that exact contract through the public API
-- membrane used by the browser client. It does not activate capture or send;
-- the underlying setup function deliberately creates the source pending with
-- both communication capabilities disabled.

create or replace function public.configure_generic_email_endpoint_self_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_email_address text,
  p_display_name text,
  p_imap_host text,
  p_imap_port integer,
  p_imap_security text,
  p_smtp_host text,
  p_smtp_port integer,
  p_smtp_security text,
  p_username text,
  p_password text
) returns jsonb
language sql
set search_path to pg_catalog,atlas,public
as $function$
  select atlas.configure_generic_email_endpoint_self_api_v1(
    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12
  );
$function$;

revoke all on function atlas.configure_generic_email_endpoint_self_api_v1(
  uuid,uuid,text,text,text,integer,text,text,integer,text,text,text
) from public,anon;
grant execute on function atlas.configure_generic_email_endpoint_self_api_v1(
  uuid,uuid,text,text,text,integer,text,text,integer,text,text,text
) to authenticated,service_role;

revoke all on function public.configure_generic_email_endpoint_self_api_v1(
  uuid,uuid,text,text,text,integer,text,text,integer,text,text,text
) from public,anon;
grant execute on function public.configure_generic_email_endpoint_self_api_v1(
  uuid,uuid,text,text,text,integer,text,text,integer,text,text,text
) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
) values (
  'atlas.configure_generic_email_endpoint_self_api_v1(p_organization_id uuid, p_organization_unit_id uuid, p_email_address text, p_display_name text, p_imap_host text, p_imap_port integer, p_imap_security text, p_smtp_host text, p_smtp_port integer, p_smtp_security text, p_username text, p_password text)',
  'owner_admin_endpoint','verified','active',true,false,true,true,1,0,
  jsonb_build_object(
    'purpose','Owner-authorized creation of a pending generic IMAP/SMTP email endpoint and connected source',
    'migration','20260914015500',
    'activationBoundary','capture and send remain disabled until separate transport activation'
  ),now(),now()
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at;

commit;
