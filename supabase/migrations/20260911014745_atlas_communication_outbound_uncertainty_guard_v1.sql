begin;

alter table atlas.communication_outbound_operations drop constraint communication_outbound_operations_operation_state_check;
alter table atlas.communication_outbound_operations add constraint communication_outbound_operations_operation_state_check check (operation_state in ('authorized','leased','accepted','temporary_failure','transport_uncertain','failed','cancelled'));

create or replace function atlas.lease_communication_outbound_operations_service_v1(p_connected_source_id uuid,p_lease_owner text,p_limit integer default 20,p_lease_seconds integer default 120)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_items jsonb;
begin
  if btrim(coalesce(p_lease_owner,''))='' or p_limit<1 or p_limit>100 or p_lease_seconds<30 or p_lease_seconds>600 then raise exception 'Valid lease owner, limit, and lease seconds are required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.connected_sources s where s.id=p_connected_source_id and s.authorization_state='connected' and s.custodian_organization_id is not null and (s.capabilities @> '{"communicationSend":true}'::jsonb)) then raise exception 'Connected institutional send source required.' using errcode='42501'; end if;
  with candidates as (
    select id from atlas.communication_outbound_operations where connected_source_id=p_connected_source_id and operation_state='authorized' order by created_at,id for update skip locked limit p_limit
  ), leased as (
    update atlas.communication_outbound_operations o set operation_state='leased',lease_owner=p_lease_owner,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),updated_at=now() from candidates c where o.id=c.id returning o.*
  ) select coalesce(jsonb_agg(to_jsonb(leased) order by created_at,id),'[]'::jsonb) into v_items from leased;
  return jsonb_build_object('contractVersion','communication_outbound_transport_lease_v2','connectedSourceId',p_connected_source_id,'leaseOwner',p_lease_owner,'items',v_items,'expiredLeasesAutoRetried',false);
end;$function$;

create or replace function atlas.mark_expired_communication_outbound_leases_uncertain_service_v1(p_connected_source_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_count int;
begin
  update atlas.communication_outbound_operations
  set operation_state='transport_uncertain',metadata=metadata||jsonb_build_object('uncertaintyReason','transport_lease_expired_without_committed_result','uncertaintyRecordedAt',now()),updated_at=now()
  where connected_source_id=p_connected_source_id and operation_state='leased' and lease_expires_at<now();
  get diagnostics v_count=row_count;
  return jsonb_build_object('contractVersion','communication_outbound_expired_lease_reconciliation_v1','connectedSourceId',p_connected_source_id,'markedTransportUncertain',v_count,'automaticResendPermitted',false);
end;$function$;

create or replace function atlas.communication_reply_transport_context_service_v1(p_communication_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_event atlas.communication_events%rowtype; v_message_id text; v_in_reply_to text; v_refs jsonb; v_thread_ref text;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  v_message_id:=nullif(btrim(v_event.canonical_event#>>'{sourcePayload,messageId}'),'');
  v_in_reply_to:=nullif(btrim(v_event.canonical_event#>>'{sourcePayload,inReplyTo}'),'');
  v_refs:=coalesce(v_event.canonical_event#>'{sourcePayload,references}','[]'::jsonb);
  v_thread_ref:=nullif(btrim(v_event.canonical_event#>>'{source,threadRef}'),'');
  return jsonb_build_object('contractVersion','communication_reply_transport_context_v1','communicationEventId',v_event.id,'connectedSourceId',v_event.connected_source_id,'messageId',v_message_id,'inReplyTo',v_in_reply_to,'references',v_refs,'sourceThreadRef',v_thread_ref,'subject',coalesce(v_event.canonical_event->>'subject',v_event.canonical_event#>>'{sourcePayload,subject}'));
end;$function$;

revoke all on function atlas.mark_expired_communication_outbound_leases_uncertain_service_v1(uuid),atlas.communication_reply_transport_context_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.mark_expired_communication_outbound_leases_uncertain_service_v1(uuid),atlas.communication_reply_transport_context_service_v1(uuid) to service_role;

comment on function atlas.lease_communication_outbound_operations_service_v1(uuid,text,integer,integer) is 'Leases only never-submitted authorized outbound operations. Expired leases are not automatically recycled because SMTP submission may have succeeded before a worker crash; duplicate consequential sends fail closed into transport_uncertain reconciliation.';

commit;