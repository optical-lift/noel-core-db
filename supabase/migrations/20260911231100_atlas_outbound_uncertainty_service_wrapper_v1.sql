begin;

create or replace function public.mark_expired_communication_outbound_leases_uncertain_service_v1(p_connected_source_id uuid)
returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.mark_expired_communication_outbound_leases_uncertain_service_v1(p_connected_source_id);
$function$;
revoke all on function public.mark_expired_communication_outbound_leases_uncertain_service_v1(uuid) from public,anon,authenticated;
grant execute on function public.mark_expired_communication_outbound_leases_uncertain_service_v1(uuid) to service_role;

commit;
