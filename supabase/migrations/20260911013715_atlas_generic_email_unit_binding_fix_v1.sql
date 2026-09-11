begin;

create or replace function atlas.configure_generic_email_endpoint_self_api_v1(
  p_organization_id uuid,p_organization_unit_id uuid,p_email_address text,p_display_name text,
  p_imap_host text,p_imap_port integer,p_imap_security text,
  p_smtp_host text,p_smtp_port integer,p_smtp_security text,
  p_username text,p_password text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_endpoint_result jsonb; v_endpoint_id uuid; v_source_result jsonb; v_source_id uuid; v_member atlas.organization_memberships%rowtype; v_metadata jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=p_organization_id and user_id=auth.uid() and active and role='owner' order by created_at limit 1;
  if v_member.id is null then raise exception 'Organization owner authority required.' using errcode='42501'; end if;
  if btrim(coalesce(p_email_address,''))='' or btrim(coalesce(p_imap_host,''))='' or btrim(coalesce(p_smtp_host,''))='' or btrim(coalesce(p_username,''))='' or coalesce(p_password,'')='' then raise exception 'Email address, IMAP/SMTP hosts, username, and password are required.' using errcode='22023'; end if;
  if p_imap_port<1 or p_imap_port>65535 or p_smtp_port<1 or p_smtp_port>65535 then raise exception 'Mail transport ports are invalid.' using errcode='22023'; end if;
  if lower(btrim(coalesce(p_imap_security,''))) not in ('tls','ssl','starttls') or lower(btrim(coalesce(p_smtp_security,''))) not in ('tls','ssl','starttls') then raise exception 'Mail transport security must be TLS/SSL/STARTTLS.' using errcode='22023'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units u where u.organization_id=p_organization_id and u.id=p_organization_unit_id) then raise exception 'Organization unit is outside organization.' using errcode='23514'; end if;
  v_endpoint_result:=atlas.upsert_communication_endpoint_self_api_v1(p_organization_id,p_organization_unit_id,'email',p_email_address,p_display_name,jsonb_build_object('transportClass','generic_imap_smtp'));
  v_endpoint_id:=(v_endpoint_result->>'communicationEndpointId')::uuid;
  v_metadata:=jsonb_build_object('transportClass','generic_imap_smtp','imap',jsonb_build_object('host',btrim(p_imap_host),'port',p_imap_port,'security',lower(btrim(p_imap_security))),'smtp',jsonb_build_object('host',btrim(p_smtp_host),'port',p_smtp_port,'security',lower(btrim(p_smtp_security))),'username',btrim(p_username));
  v_source_result:=atlas.register_organization_connected_source_self_api_v1(p_organization_id,'imap_smtp_email',atlas.normalize_communication_endpoint_address_v1('email',p_email_address),coalesce(nullif(btrim(p_display_name),''),p_email_address),p_email_address,'pending',array['mail.read','mail.send'],jsonb_build_object('communicationCapture',false,'communicationSend',false),v_metadata);
  v_source_id:=(v_source_result->>'sourceId')::uuid;
  if p_organization_unit_id is not null then perform atlas.bind_connected_source_organization_unit_service_v1(v_source_id,p_organization_unit_id); end if;
  perform atlas.store_connected_source_secret_service_v1(v_source_id,'mailbox_password',p_password,'Generic IMAP/SMTP mailbox password');
  perform atlas.bind_communication_endpoint_source_self_api_v1(v_endpoint_id,v_source_id,'send_receive',v_metadata);
  return jsonb_build_object('contractVersion','generic_email_endpoint_setup_v2','communicationEndpointId',v_endpoint_id,'connectedSourceId',v_source_id,'organizationUnitId',p_organization_unit_id,'authorizationState','pending','credentialStored',true,'transport',v_metadata);
end;$function$;

commit;