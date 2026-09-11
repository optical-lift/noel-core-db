begin;

alter table atlas.communication_outbound_operations drop constraint communication_outbound_operations_operation_state_check;
alter table atlas.communication_outbound_operations add constraint communication_outbound_operations_operation_state_check check (operation_state in ('authorized','leased','accepted','partially_accepted','temporary_failure','transport_uncertain','failed','cancelled'));
alter table atlas.communication_outbound_attempts drop constraint communication_outbound_attempts_result_state_check;
alter table atlas.communication_outbound_attempts add constraint communication_outbound_attempts_result_state_check check (result_state in ('accepted','partially_accepted','temporary_failure','rejected','transport_error','unknown'));

create table atlas.communication_outbound_attempt_recipients (
  id uuid primary key default gen_random_uuid(),
  outbound_attempt_id uuid not null references atlas.communication_outbound_attempts(id) on delete cascade,
  outbound_operation_id uuid not null references atlas.communication_outbound_operations(id) on delete cascade,
  recipient_role text not null check (recipient_role in ('to','cc','bcc')),
  recipient_address text not null check (btrim(recipient_address)<>''),
  recipient_address_normalized text not null check (btrim(recipient_address_normalized)<>''),
  result_state text not null check (result_state in ('accepted','rejected','deferred','unknown')),
  provider_response jsonb not null default '{}'::jsonb check (jsonb_typeof(provider_response)='object'),
  created_at timestamptz not null default now(),
  unique(outbound_attempt_id,recipient_role,recipient_address_normalized)
);
create index communication_outbound_attempt_recipient_route_idx on atlas.communication_outbound_attempt_recipients(recipient_address_normalized,result_state,created_at desc,id);
comment on table atlas.communication_outbound_attempt_recipients is 'Per-recipient SMTP transport result evidence. Operation-level acceptance never erases rejected/deferred recipients and does not imply final delivery/read.';
create trigger communication_outbound_attempt_recipients_append_only_v1 before update or delete on atlas.communication_outbound_attempt_recipients for each row execute function atlas.prevent_communication_outbound_history_mutation_v1();

create or replace function atlas.guard_communication_outbound_attempt_recipient_v1() returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_attempt atlas.communication_outbound_attempts%rowtype;
begin
  select * into v_attempt from atlas.communication_outbound_attempts where id=new.outbound_attempt_id;
  if v_attempt.id is null or v_attempt.outbound_operation_id is distinct from new.outbound_operation_id then raise exception 'Outbound recipient result must belong to its transport attempt/operation.' using errcode='23514'; end if;
  new.recipient_address:=btrim(new.recipient_address);
  new.recipient_address_normalized:=atlas.normalize_external_party_identifier_v1('email',new.recipient_address);
  return new;
end;$function$;
create trigger communication_outbound_attempt_recipient_guard_v1 before insert on atlas.communication_outbound_attempt_recipients for each row execute function atlas.guard_communication_outbound_attempt_recipient_v1();

create or replace function atlas.record_communication_outbound_result_service_v2(
  p_outbound_operation_id uuid,p_lease_owner text,p_result_state text,p_provider_message_ref text,p_provider_response jsonb,p_recipient_results jsonb,p_canonical_event jsonb default null
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_op atlas.communication_outbound_operations%rowtype; v_result text:=lower(btrim(coalesce(p_result_state,''))); v_v1_state text; v_call_state text; v_receipt jsonb; v_attempt_id uuid; v_item jsonb; v_role text; v_address text; v_recipient_state text; v_accepted int:=0; v_rejected int:=0; v_deferred int:=0; v_unknown int:=0;
begin
  if jsonb_typeof(coalesce(p_recipient_results,'[]'::jsonb))<>'array' then raise exception 'Recipient results must be a JSON array.' using errcode='22023'; end if;
  if v_result not in ('accepted','partially_accepted','temporary_failure','rejected','transport_error','unknown') then raise exception 'Unsupported outbound transport result.' using errcode='22023'; end if;
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;

  -- v1 owns the atomic attempt/event/response transition. A partial provider acceptance
  -- follows the accepted path because at least one copy left Atlas; we restore the more
  -- precise operation/attempt state before returning.
  v_call_state:=case when v_result='partially_accepted' then 'accepted' else v_result end;
  v_receipt:=atlas.record_communication_outbound_result_service_v1(p_outbound_operation_id,p_lease_owner,v_call_state,p_provider_message_ref,p_provider_response,p_canonical_event);
  if v_receipt->>'state'='already_accepted' then
    return v_receipt||jsonb_build_object('contractVersion','communication_outbound_result_v2');
  end if;
  select id into v_attempt_id from atlas.communication_outbound_attempts where outbound_operation_id=p_outbound_operation_id order by attempt_number desc,id desc limit 1;
  if v_attempt_id is null then raise exception 'Outbound transport attempt was not recorded.' using errcode='55000'; end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_recipient_results,'[]'::jsonb)) loop
    v_role:=lower(btrim(coalesce(v_item->>'role',''))); v_address:=btrim(coalesce(v_item->>'address','')); v_recipient_state:=lower(btrim(coalesce(v_item->>'state','')));
    if v_role not in ('to','cc','bcc') or v_address='' or v_recipient_state not in ('accepted','rejected','deferred','unknown') then raise exception 'Every recipient transport result requires role, address, and a supported state.' using errcode='22023'; end if;
    insert into atlas.communication_outbound_attempt_recipients(outbound_attempt_id,outbound_operation_id,recipient_role,recipient_address,recipient_address_normalized,result_state,provider_response)
    values(v_attempt_id,p_outbound_operation_id,v_role,v_address,atlas.normalize_external_party_identifier_v1('email',v_address),v_recipient_state,coalesce(v_item->'providerResponse','{}'::jsonb));
    if v_recipient_state='accepted' then v_accepted:=v_accepted+1; elsif v_recipient_state='rejected' then v_rejected:=v_rejected+1; elsif v_recipient_state='deferred' then v_deferred:=v_deferred+1; else v_unknown:=v_unknown+1; end if;
  end loop;

  if v_result='partially_accepted' then
    if v_accepted<1 or (v_rejected+v_deferred+v_unknown)<1 then raise exception 'partially_accepted requires both accepted and non-accepted recipient results.' using errcode='23514'; end if;
    update atlas.communication_outbound_attempts set result_state='partially_accepted' where id=v_attempt_id;
    update atlas.communication_outbound_operations set operation_state='partially_accepted',metadata=metadata||jsonb_build_object('partialAcceptance',true,'acceptedRecipientCount',v_accepted,'nonAcceptedRecipientCount',v_rejected+v_deferred+v_unknown),updated_at=now() where id=p_outbound_operation_id;
  elsif v_result='accepted' and jsonb_array_length(coalesce(p_recipient_results,'[]'::jsonb))>0 and (v_rejected+v_deferred+v_unknown)>0 then
    raise exception 'accepted operation cannot contain non-accepted recipient results; use partially_accepted.' using errcode='23514';
  end if;

  return v_receipt||jsonb_build_object('contractVersion','communication_outbound_result_v2','operationState',v_result,'outboundAttemptId',v_attempt_id,'recipientResults',jsonb_build_object('accepted',v_accepted,'rejected',v_rejected,'deferred',v_deferred,'unknown',v_unknown),'deliveryProven',false,'readProven',false);
end;$function$;

alter table atlas.communication_outbound_attempt_recipients enable row level security;
revoke all on atlas.communication_outbound_attempt_recipients from public,anon,authenticated;
grant all on atlas.communication_outbound_attempt_recipients to service_role;
revoke all on function atlas.guard_communication_outbound_attempt_recipient_v1(),atlas.record_communication_outbound_result_service_v2(uuid,text,text,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.guard_communication_outbound_attempt_recipient_v1(),atlas.record_communication_outbound_result_service_v2(uuid,text,text,text,jsonb,jsonb,jsonb) to service_role;

commit;