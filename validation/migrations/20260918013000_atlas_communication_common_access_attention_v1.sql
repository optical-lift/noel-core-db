begin;

do $validation$
declare
  v_access regprocedure;
  v_attention regprocedure;
  v_access_definition text;
  v_attention_definition text;
begin
  v_access:=to_regprocedure('atlas.organization_correspondence_access_self_api_v1(uuid)');
  v_attention:=to_regprocedure('atlas.organization_correspondence_attention_summary_self_api_v1(uuid)');

  if v_access is null or v_attention is null then
    raise exception 'Common Correspondence access or attention summary API is missing.';
  end if;

  select lower(pg_get_functiondef(v_access)) into v_access_definition;
  select lower(pg_get_functiondef(v_attention)) into v_attention_definition;

  if position('effective_communication_endpoint_organization_v1' in v_access_definition)=0
     or position('communication_endpoint_membership_has_capability_v1' in v_access_definition)=0
     or position('sourcecapabilities' in replace(v_access_definition,'_',''))=0
     or position('members' in v_access_definition)=0
     or position('communication_endpoint' in v_access_definition)=0 then
    raise exception 'Common Correspondence access lost Endpoint authority/source/member semantics.';
  end if;

  if position('institutional_communications_home' in v_access_definition)>0
     or position('institutional_shared_inbox' in v_access_definition)>0 then
    raise exception 'Common Correspondence access may not wrap Institutional product reads.';
  end if;

  if position('organization_correspondence_read_authorized_self_v1' in v_attention_definition)=0
     or position('communication_conversations' in v_attention_definition)=0
     or position('communication_conversation_events' in v_attention_definition)=0
     or position('unique_common_conversations' in v_attention_definition)=0 then
    raise exception 'Common Correspondence attention summary lost common Conversation custody.';
  end if;

  if position('institutional_communications_home' in v_attention_definition)>0
     or position('institutional_shared_inbox' in v_attention_definition)>0
     or position('v_institutional_shared_inbox' in v_attention_definition)>0 then
    raise exception 'Common Correspondence attention summary may not use Institutional inbox/home reads.';
  end if;

  if has_function_privilege('public',v_access,'EXECUTE')
     or has_function_privilege('anon',v_access,'EXECUTE')
     or has_function_privilege('public',v_attention,'EXECUTE')
     or has_function_privilege('anon',v_attention,'EXECUTE') then
    raise exception 'Public/anon may not execute common Correspondence access/attention APIs.';
  end if;

  if not has_function_privilege('authenticated',v_access,'EXECUTE')
     or not has_function_privilege('authenticated',v_attention,'EXECUTE') then
    raise exception 'Authenticated role cannot execute common Correspondence access/attention APIs.';
  end if;
end;
$validation$;

rollback;
