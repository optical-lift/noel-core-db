-- Validation for Package 7 / Stage 5 common collaboration, attention, and disposition.

begin;

do $validation$
declare
  v_detail regprocedure;
  v_disposition regprocedure;
  v_detail_definition text;
  v_disposition_definition text;
begin
  v_detail:=to_regprocedure('atlas.organization_correspondence_conversation_self_api_v3(uuid)');
  v_disposition:=to_regprocedure('atlas.set_communication_conversation_endpoint_disposition_self_api_v1(uuid,uuid,text,text)');

  if v_detail is null then
    raise exception 'Common Correspondence detail v3 is missing.';
  end if;
  if v_disposition is null then
    raise exception 'Common endpoint-scoped disposition command is missing.';
  end if;

  select lower(pg_get_functiondef(v_detail))
  into v_detail_definition;

  if position('organization_correspondence_conversation_self_api_v2' in v_detail_definition)=0
     or position('communication_attention_events' in v_detail_definition)=0
     or position('responsecollaborators' in replace(v_detail_definition,'_',''))=0
     or position('institutional_conversation_disposition_events' in v_detail_definition)=0
     or position('communication_endpoint_membership_has_capability_v1' in v_detail_definition)=0
     or position('identityroot' in replace(v_detail_definition,'_',''))=0
     or position('communication_conversation' in v_detail_definition)=0 then
    raise exception 'Common detail v3 lost Conversation/Event/Endpoint custody or collaboration/attention/disposition projection.';
  end if;

  select lower(pg_get_functiondef(v_disposition))
  into v_disposition_definition;

  if position('communication_conversation_endpoints' in v_disposition_definition)=0
     or position('p_communication_endpoint_id' in v_disposition_definition)=0
     or position('institutional_conversation_disposition_events' in v_disposition_definition)=0
     or position('communication_endpoint_sender_rules' in v_disposition_definition)=0
     or position('communication_endpoint_membership_has_capability_v1' in v_disposition_definition)=0
     or position('communicationcommandroot' in replace(v_disposition_definition,'_',''))=0
     or position('communication_conversation' in v_disposition_definition)=0 then
    raise exception 'Common disposition command lost explicit Endpoint custody, mailbox side effects, or authorization.';
  end if;

  if has_function_privilege('anon',v_detail,'EXECUTE')
     or has_function_privilege('anon',v_disposition,'EXECUTE') then
    raise exception 'Anonymous role may not execute Stage 5 common Correspondence contracts.';
  end if;

  if not has_function_privilege('authenticated',v_detail,'EXECUTE')
     or not has_function_privilege('authenticated',v_disposition,'EXECUTE') then
    raise exception 'Authenticated role cannot execute Stage 5 common Correspondence contracts.';
  end if;
end;
$validation$;

rollback;
