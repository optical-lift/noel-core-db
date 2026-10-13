-- Verify the separately authored public PostgREST membrane only after
-- 20260911174500 installs the canonical internal provider functions.
begin;

-- Client seams must be callable only where deliberately intended.
do $validation$
begin
  if not has_function_privilege('authenticated','public.register_principal_connected_source_self_api_v1(text,text,text,text,text[],jsonb,jsonb)','EXECUTE') then raise exception 'Principal source registration wrapper unavailable.'; end if;
  if not has_function_privilege('authenticated','public.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb)','EXECUTE') then raise exception 'Principal endpoint upsert wrapper unavailable.'; end if;
  if not has_function_privilege('authenticated','public.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb)','EXECUTE') then raise exception 'Principal endpoint binding wrapper unavailable.'; end if;
  if not has_function_privilege('authenticated','public.principal_communication_conversations_self_api_v1(uuid,integer)','EXECUTE') then raise exception 'Principal conversation list wrapper unavailable.'; end if;
  if not has_function_privilege('authenticated','public.principal_communication_conversation_detail_self_api_v1(uuid)','EXECUTE') then raise exception 'Principal conversation detail wrapper unavailable.'; end if;
  if has_function_privilege('authenticated','public.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)','EXECUTE') then raise exception 'Browser may execute provider ingest service seam.'; end if;
  if has_function_privilege('authenticated','public.store_connected_source_secret_service_v1(uuid,text,text,text)','EXECUTE') or has_function_privilege('authenticated','public.read_connected_source_secret_service_v1(uuid,text)','EXECUTE') then raise exception 'Browser may access provider credential custody.'; end if;
  if not has_function_privilege('service_role','public.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)','EXECUTE') then raise exception 'Service provider ingest wrapper unavailable.'; end if;
  if not has_function_privilege('service_role','public.store_connected_source_secret_service_v1(uuid,text,text,text)','EXECUTE') or not has_function_privilege('service_role','public.read_connected_source_secret_service_v1(uuid,text)','EXECUTE') then raise exception 'Service credential custody wrapper unavailable.'; end if;
end;$validation$;

rollback;
