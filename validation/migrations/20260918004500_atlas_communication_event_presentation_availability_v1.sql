begin;

do $validation$
declare
  v_function regprocedure;
  v_definition text;
begin
  v_function:=to_regprocedure('atlas.organization_correspondence_conversation_self_api_v4(uuid)');
  if v_function is null then
    raise exception 'Common Correspondence detail v4 is missing.';
  end if;

  select lower(pg_get_functiondef(v_function))
  into v_definition;

  if position('organization_correspondence_conversation_self_api_v3' in v_definition)=0
     or position('communication_raw_message_custody' in v_definition)=0
     or position('presentationavailable' in replace(v_definition,'_',''))=0
     or position('custody_state=''stored''' in v_definition)=0
     or position('identityroot' in replace(v_definition,'_',''))=0
     or position('communication_conversation' in v_definition)=0 then
    raise exception 'Common detail v4 lost Conversation custody or bounded presentation availability semantics.';
  end if;

  if position('storageLocator' in pg_get_functiondef(v_function))>0
     or position('rawMimeSha256' in pg_get_functiondef(v_function))>0 then
    raise exception 'Common detail v4 must not expose raw-message storage locator or hash.';
  end if;

  if has_function_privilege('public',v_function,'EXECUTE')
     or has_function_privilege('anon',v_function,'EXECUTE') then
    raise exception 'Public/anon may not execute common Correspondence detail v4.';
  end if;

  if not has_function_privilege('authenticated',v_function,'EXECUTE') then
    raise exception 'Authenticated role cannot execute common Correspondence detail v4.';
  end if;
end;
$validation$;

rollback;
