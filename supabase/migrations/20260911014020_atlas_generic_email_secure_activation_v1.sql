begin;

create or replace function atlas.set_generic_email_mailbox_credential_self_api_v1(p_connected_source_id uuid,p_password text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_source atlas.connected_sources%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null for update;
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_owner(v_source.custodian_organization_id) then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if coalesce(p_password,'')='' then raise exception 'Mailbox password is required.' using errcode='22023'; end if;
  perform atlas.store_connected_source_secret_service_v1(v_source.id,'mailbox_password',p_password,'Generic IMAP/SMTP mailbox password');
  update atlas.connected_sources set authorization_state='pending',capabilities=capabilities||jsonb_build_object('communicationCapture',false,'communicationSend',false),metadata=metadata||jsonb_build_object('credentialUpdatedAt',now()),updated_at=now() where id=v_source.id;
  return jsonb_build_object('contractVersion','generic_email_mailbox_credential_v1','connectedSourceId',v_source.id,'credentialStored',true,'authorizationState','pending');
end;$function$;

create or replace function atlas.generic_email_connection_status_self_v1(p_connected_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_source atlas.connected_sources%rowtype; v_endpoint atlas.communication_endpoints%rowtype; v_last atlas.communication_gateway_heartbeats%rowtype; v_has_secret boolean;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and provider_key='imap_smtp_email' and custodian_organization_id is not null;
  if v_source.id is null then raise exception 'Generic institutional email source not found.' using errcode='P0002'; end if;
  if not atlas.is_organization_member(v_source.custodian_organization_id) then raise exception 'Organization membership required.' using errcode='42501'; end if;
  select ep.* into v_endpoint from atlas.communication_endpoint_source_bindings b join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id where b.connected_source_id=v_source.id and b.binding_state='active' order by b.created_at limit 1;
  select * into v_last from atlas.communication_gateway_heartbeats h where h.connected_source_id=v_source.id order by h.observed_at desc,h.id desc limit 1;
  select exists(select 1 from atlas.connected_source_secret_refs r where r.connected_source_id=v_source.id and r.credential_kind='mailbox_password') into v_has_secret;
  return jsonb_build_object('contractVersion','generic_email_connection_status_v1','connectedSourceId',v_source.id,'communicationEndpointId',v_endpoint.id,'address',v_endpoint.address,'authorizationState',v_source.authorization_state,'capabilities',v_source.capabilities,'credentialPresent',v_has_secret,'lastSyncAt',v_source.last_sync_at,'gatewayState',v_last.state,'gatewayObservedAt',v_last.observed_at,'gatewayDetail',v_last.detail,'historyPolicy',coalesce(v_source.metadata->'communicationHistoryPolicy',jsonb_build_object('mode','from_now')));
end;$function$;

revoke all on function atlas.set_generic_email_mailbox_credential_self_api_v1(uuid,text),atlas.generic_email_connection_status_self_v1(uuid) from public,anon;
grant execute on function atlas.set_generic_email_mailbox_credential_self_api_v1(uuid,text),atlas.generic_email_connection_status_self_v1(uuid) to authenticated,service_role;

commit;