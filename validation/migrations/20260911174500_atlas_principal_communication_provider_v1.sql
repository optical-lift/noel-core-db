-- Validation for provider-independent Principal communication + personal provider seam.
-- Run only after candidate migrations in disposable/production-schema clone validation.

begin;

do $validation$
begin
  if exists(select 1 from atlas.communication_endpoints where (principal_id is null)=(organization_id is null)) then
    raise exception 'Communication Endpoint custody is not exactly one Principal or Organization.';
  end if;
  if exists(select 1 from atlas.communication_endpoints where principal_id is not null and organization_unit_id is not null) then
    raise exception 'Principal endpoint has Organization Unit custody.';
  end if;
end;$validation$;

do $validation$
declare v_institutional bigint; v_roots bigint;
begin
  select count(*) into v_institutional from atlas.institutional_conversations;
  select count(*) into v_roots from atlas.institutional_conversation_roots;
  if v_institutional<>v_roots then raise exception 'Institutional compatibility root mismatch: % vs %',v_institutional,v_roots; end if;
end;$validation$;

do $validation$
begin
  if to_regclass('atlas.communication_conversation_events') is null then raise exception 'Common conversation event bridge missing.'; end if;
  if to_regclass('atlas.communication_source_sync_states') is null then raise exception 'Provider-neutral sync state missing.'; end if;
  if exists(select 1 from information_schema.columns where table_schema='atlas' and table_name='communication_source_sync_states' and column_name in ('gmail_history_id','google_refresh_token','microsoft_delta_token','imap_uid')) then
    raise exception 'Provider-specific state leaked into generic sync-state schema.';
  end if;
end;$validation$;

-- Validate the exact 174500 contract. Public PostgREST wrappers are introduced by
-- the later 174700 public-membrane migration and must not be required here.
do $validation$
begin
  if not has_function_privilege('authenticated','atlas.register_principal_connected_source_self_api_v1(text,text,text,text,text[],jsonb,jsonb)','EXECUTE') then raise exception 'Principal source registration seam unavailable.'; end if;
  if not has_function_privilege('authenticated','atlas.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb)','EXECUTE') then raise exception 'Principal endpoint upsert seam unavailable.'; end if;
  if not has_function_privilege('authenticated','atlas.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb)','EXECUTE') then raise exception 'Principal endpoint binding seam unavailable.'; end if;
  if not has_function_privilege('authenticated','atlas.principal_communication_conversations_self_api_v1(uuid,integer)','EXECUTE') then raise exception 'Principal conversation list seam unavailable.'; end if;
  if not has_function_privilege('authenticated','atlas.principal_communication_conversation_detail_self_api_v1(uuid)','EXECUTE') then raise exception 'Principal conversation detail seam unavailable.'; end if;
  if has_function_privilege('authenticated','atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)','EXECUTE') then raise exception 'Browser may execute provider ingest service seam.'; end if;
  if not has_function_privilege('service_role','atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)','EXECUTE') then raise exception 'Service provider ingest seam unavailable.'; end if;
end;$validation$;

-- Direct browser access to new internal tables stays closed.
do $validation$
declare v_table text;
begin
  foreach v_table in array array['communication_conversations','communication_conversation_source_threads','communication_conversation_endpoints','communication_conversation_events','communication_source_sync_states','communication_actionability_assessments'] loop
    if has_table_privilege('authenticated','atlas.'||v_table,'SELECT') or has_table_privilege('authenticated','atlas.'||v_table,'INSERT') or has_table_privilege('authenticated','atlas.'||v_table,'UPDATE') or has_table_privilege('authenticated','atlas.'||v_table,'DELETE') then
      raise exception 'Authenticated direct table privilege leaked on atlas.%',v_table;
    end if;
  end loop;
end;$validation$;

-- Existing institutional responsibility behavior must not be silently cut over.
do $validation$
declare v_definition text;
begin
  select pg_get_functiondef(p.oid) into v_definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='atlas' and p.proname='ensure_institutional_response_case_for_event_service_v1' order by p.oid desc limit 1;
  if v_definition is null then raise exception 'Institutional response-case opener missing.'; end if;
  if position('communication_event_actionability_v1' in v_definition)>0 or position('communication_actionability_assessments' in v_definition)>0 then raise exception 'Provider foundation unexpectedly changed institutional responsibility admission.'; end if;
end;$validation$;

-- Registering a personal provider is not a relay shortcut.
do $validation$
declare v_definition text;
begin
  select pg_get_functiondef(p.oid) into v_definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='atlas' and p.proname='register_principal_connected_source_self_api_v1';
  if v_definition is null then raise exception 'Principal Connected Source registration missing.'; end if;
  if position('communication_relay_credentials' in v_definition)>0 then raise exception 'Generic Principal provider registration improperly creates relay credentials.'; end if;
end;$validation$;

rollback;
