create or replace function atlas.record_communication_outbound_result_service_v2(
  p_outbound_operation_id uuid,
  p_lease_owner text,
  p_result_state text,
  p_provider_message_ref text,
  p_provider_response jsonb,
  p_recipient_results jsonb,
  p_canonical_event jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_op atlas.communication_outbound_operations%rowtype;
  v_result text:=lower(btrim(coalesce(p_result_state,'')));
  v_call_state text;
  v_receipt jsonb;
  v_attempt_id uuid;
  v_item jsonb;
  v_role text;
  v_address text;
  v_norm text;
  v_recipient_state text;
  v_accepted int:=0;
  v_rejected int:=0;
  v_deferred int:=0;
  v_unknown int:=0;
  v_expected int:=0;
  v_seen text[]:='{}'::text[];
begin
  if jsonb_typeof(coalesce(p_recipient_results,'[]'::jsonb))<>'array' then
    raise exception 'Recipient results must be a JSON array.' using errcode='22023';
  end if;
  if v_result not in ('accepted','partially_accepted','temporary_failure','rejected','transport_error','unknown') then
    raise exception 'Unsupported outbound transport result.' using errcode='22023';
  end if;
  select * into v_op from atlas.communication_outbound_operations where id=p_outbound_operation_id;
  if v_op.id is null then raise exception 'Outbound operation not found.' using errcode='P0002'; end if;

  select count(*) into v_expected
  from (
    select 'to'::text role, atlas.normalize_external_party_identifier_v1('email',x->>'address') norm from jsonb_array_elements(coalesce(v_op.to_recipients,'[]'::jsonb)) x
    union all
    select 'cc', atlas.normalize_external_party_identifier_v1('email',x->>'address') from jsonb_array_elements(coalesce(v_op.cc_recipients,'[]'::jsonb)) x
    union all
    select 'bcc', atlas.normalize_external_party_identifier_v1('email',x->>'address') from jsonb_array_elements(coalesce(v_op.bcc_recipients,'[]'::jsonb)) x
  ) expected
  where norm is not null;

  for v_item in select value from jsonb_array_elements(coalesce(p_recipient_results,'[]'::jsonb)) loop
    v_role:=lower(btrim(coalesce(v_item->>'role','')));
    v_address:=btrim(coalesce(v_item->>'address',''));
    v_norm:=atlas.normalize_external_party_identifier_v1('email',v_address);
    v_recipient_state:=lower(btrim(coalesce(v_item->>'state','')));
    if v_role not in ('to','cc','bcc') or v_address='' or v_norm is null or v_recipient_state not in ('accepted','rejected','deferred','unknown') then
      raise exception 'Every recipient transport result requires role, address, and a supported state.' using errcode='22023';
    end if;
    if (v_role||'|'||v_norm)=any(v_seen) then
      raise exception 'Duplicate recipient transport result.' using errcode='23514';
    end if;
    v_seen:=array_append(v_seen,v_role||'|'||v_norm);
    if not exists (
      select 1 from (
        select 'to'::text role, atlas.normalize_external_party_identifier_v1('email',x->>'address') norm from jsonb_array_elements(coalesce(v_op.to_recipients,'[]'::jsonb)) x
        union all
        select 'cc', atlas.normalize_external_party_identifier_v1('email',x->>'address') from jsonb_array_elements(coalesce(v_op.cc_recipients,'[]'::jsonb)) x
        union all
        select 'bcc', atlas.normalize_external_party_identifier_v1('email',x->>'address') from jsonb_array_elements(coalesce(v_op.bcc_recipients,'[]'::jsonb)) x
      ) expected where expected.role=v_role and expected.norm=v_norm
    ) then
      raise exception 'Recipient transport result is outside the authorized outbound operation.' using errcode='42501';
    end if;
  end loop;

  if v_result in ('accepted','partially_accepted','rejected') and coalesce(jsonb_array_length(p_recipient_results),0)<>v_expected then
    raise exception 'Final recipient transport result must account for every authorized recipient.' using errcode='23514';
  end if;

  v_call_state:=case when v_result='partially_accepted' then 'accepted' else v_result end;
  v_receipt:=atlas.record_communication_outbound_result_service_v1(p_outbound_operation_id,p_lease_owner,v_call_state,p_provider_message_ref,p_provider_response,p_canonical_event);
  if v_receipt->>'state'='already_accepted' then
    return v_receipt||jsonb_build_object('contractVersion','communication_outbound_result_v2');
  end if;
  select id into v_attempt_id from atlas.communication_outbound_attempts where outbound_operation_id=p_outbound_operation_id order by attempt_number desc,id desc limit 1;
  if v_attempt_id is null then raise exception 'Outbound transport attempt was not recorded.' using errcode='55000'; end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_recipient_results,'[]'::jsonb)) loop
    v_role:=lower(btrim(coalesce(v_item->>'role','')));
    v_address:=btrim(coalesce(v_item->>'address',''));
    v_recipient_state:=lower(btrim(coalesce(v_item->>'state','')));
    insert into atlas.communication_outbound_attempt_recipients(outbound_attempt_id,outbound_operation_id,recipient_role,recipient_address,recipient_address_normalized,result_state,provider_response)
    values(v_attempt_id,p_outbound_operation_id,v_role,v_address,atlas.normalize_external_party_identifier_v1('email',v_address),v_recipient_state,coalesce(v_item->'providerResponse','{}'::jsonb));
    if v_recipient_state='accepted' then v_accepted:=v_accepted+1;
    elsif v_recipient_state='rejected' then v_rejected:=v_rejected+1;
    elsif v_recipient_state='deferred' then v_deferred:=v_deferred+1;
    else v_unknown:=v_unknown+1;
    end if;
  end loop;

  if v_result='partially_accepted' then
    if v_accepted<1 or (v_rejected+v_deferred+v_unknown)<1 then raise exception 'partially_accepted requires both accepted and non-accepted recipient results.' using errcode='23514'; end if;
    update atlas.communication_outbound_operations set operation_state='partially_accepted',metadata=metadata||jsonb_build_object('partialAcceptance',true,'acceptedRecipientCount',v_accepted,'nonAcceptedRecipientCount',v_rejected+v_deferred+v_unknown),updated_at=now() where id=p_outbound_operation_id;
  elsif v_result='accepted' and (v_rejected+v_deferred+v_unknown)>0 then
    raise exception 'accepted operation cannot contain non-accepted recipient results; use partially_accepted.' using errcode='23514';
  end if;

  return v_receipt||jsonb_build_object(
    'contractVersion','communication_outbound_result_v2',
    'operationState',v_result,
    'outboundAttemptId',v_attempt_id,
    'attemptTransportState',case when v_result='partially_accepted' then 'accepted' else v_result end,
    'recipientResults',jsonb_build_object('accepted',v_accepted,'rejected',v_rejected,'deferred',v_deferred,'unknown',v_unknown),
    'deliveryProven',false,
    'readProven',false
  );
end;
$function$;

revoke all on function atlas.record_communication_outbound_result_service_v2(uuid,text,text,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_communication_outbound_result_service_v2(uuid,text,text,text,jsonb,jsonb,jsonb) to service_role;