-- Schema-clone postconditions for Option C sender/endpoint preflight.
-- Read-only: no fabricated mail, sender grant, identity, relationship or Work.

do $verify$
declare
  v_private regprocedure :=
    to_regprocedure('atlas.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(uuid,uuid,uuid)');
  v_public regprocedure :=
    to_regprocedure('public.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(uuid,uuid,uuid)');
  v_definition text;
begin
  if v_private is null or v_public is null then
    raise exception 'Person inquiry sender endpoint preflight functions absent';
  end if;

  if not exists (
    select 1 from pg_proc p where p.oid=v_private
      and p.prosecdef and p.provolatile='s'
  ) or not exists (
    select 1 from pg_proc p where p.oid=v_public
      and not p.prosecdef and p.provolatile='s'
  ) then
    raise exception 'Private owner gate / invoker transport / read-only stability invalid';
  end if;

  if has_function_privilege('anon',v_private,'EXECUTE')
     or has_function_privilege('anon',v_public,'EXECUTE')
     or not has_function_privilege('authenticated',v_public,'EXECUTE') then
    raise exception 'Incorrect public/anonymous preflight grants';
  end if;

  v_definition := pg_get_functiondef(v_private::oid);
  if position('person_contact_inquiry_intent_owner_self_api_v1' in v_definition)=0
     or position('person_contact_inquiry_owner_address_reviews' in v_definition)=0
     or position('owner_withdrew_inquiry' in v_definition)=0
     or position('ep.organization_id=v_ledger.organization_id' in v_definition)=0
     or position('ep.principal_id=v_principal' in v_definition)=0
     or position('correspondence_identity_endpoint_bindings' in v_definition)=0
     or position('communication_endpoint_source_bindings' in v_definition)=0
     or position('s.authorization_state=' in v_definition)=0
     or position('resolve_institutional_communication_operation_self_v1' in v_definition)=0
     or position('message.send' in v_definition)=0
     or position('canSend' in v_definition)=0
     or position('messageSent' in v_definition)=0
     or position('recipientSuppressionState' in v_definition)=0
     or position('not_reviewed' in v_definition)=0
     or position('relationshipEstablished' in v_definition)=0 then
    raise exception 'Owner/sender/cross-Ledger/no-send boundary missing';
  end if;

  if v_definition ~* '\m(insert|update|delete|execute|perform)\s+.*\m(send_email|dispatch_mail|create_invitation)\M'
     or v_definition ~* '\minsert\s+into\M'
     or v_definition ~* '\mdelete\s+from\M' then
    raise exception 'Read-only preflight contains outbound or mutating SQL';
  end if;
end $verify$;

select
  'atlas_person_inquiry_sender_endpoint_preflight_v1' as contract,
  'schema_only_no_messages_no_identity_or_relationship_effects' as consequence,
  false as can_send,
  false as sent_mail,
  false as person_identified,
  false as relationship_established;
