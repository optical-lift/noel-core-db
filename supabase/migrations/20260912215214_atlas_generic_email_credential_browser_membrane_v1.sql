begin;

create or replace function public.set_generic_email_mailbox_credential_self_api_v1(
  p_connected_source_id uuid,
  p_password text
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.set_generic_email_mailbox_credential_self_api_v1(
    p_connected_source_id,
    p_password
  );
$function$;

revoke all on function public.set_generic_email_mailbox_credential_self_api_v1(uuid,text) from public, anon;
grant execute on function public.set_generic_email_mailbox_credential_self_api_v1(uuid,text) to authenticated, service_role;

comment on function public.set_generic_email_mailbox_credential_self_api_v1(uuid,text) is
  'Browser API membrane for an authenticated organization owner to store a generic IMAP/SMTP mailbox credential through the internal owner-authorized Atlas function. This wrapper adds no authority and does not poll, send, or enable communication capture.';

commit;