begin;

create or replace function public.institutional_communications_home_self_api_v1()
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.institutional_communications_home_self_api_v1();
$function$;

create or replace function public.institutional_shared_inbox_self_v1(
  p_communication_endpoint_id uuid,
  p_limit integer default 200
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.institutional_shared_inbox_self_v1(
    p_communication_endpoint_id,
    p_limit
  );
$function$;

create or replace function public.institutional_conversation_detail_self_v1(
  p_institutional_conversation_id uuid
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.institutional_conversation_detail_self_v1(
    p_institutional_conversation_id
  );
$function$;

revoke all on function public.institutional_communications_home_self_api_v1()
  from public, anon;
revoke all on function public.institutional_shared_inbox_self_v1(uuid, integer)
  from public, anon;
revoke all on function public.institutional_conversation_detail_self_v1(uuid)
  from public, anon;

grant execute on function public.institutional_communications_home_self_api_v1()
  to authenticated, service_role;
grant execute on function public.institutional_shared_inbox_self_v1(uuid, integer)
  to authenticated, service_role;
grant execute on function public.institutional_conversation_detail_self_v1(uuid)
  to authenticated, service_role;

comment on function public.institutional_communications_home_self_api_v1() is
  'Browser API membrane for the authenticated institutional communications home projection. Adds no authority beyond the internal self-authorized Atlas function.';
comment on function public.institutional_shared_inbox_self_v1(uuid, integer) is
  'Browser API membrane for the authenticated institutional correspondence journal projection. Adds no authority beyond the internal self-authorized Atlas function.';
comment on function public.institutional_conversation_detail_self_v1(uuid) is
  'Browser API membrane for authenticated institutional conversation detail. Adds no authority beyond the internal self-authorized Atlas function.';

commit;
