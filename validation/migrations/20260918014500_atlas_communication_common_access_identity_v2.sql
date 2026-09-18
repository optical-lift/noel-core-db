begin;

do $validation$
declare
  v_function regprocedure;
  v_definition text;
begin
  v_function:=to_regprocedure('atlas.organization_correspondence_access_self_api_v2(uuid)');
  if v_function is null then
    raise exception 'Common Correspondence access v2 is missing.';
  end if;

  select lower(pg_get_functiondef(v_function)) into v_definition;

  if position('organization_correspondence_access_self_api_v1' in v_definition)=0
     or position('correspondence_identity_endpoint_bindings' in v_definition)=0
     or position('correspondenceidentity' in replace(v_definition,'_',''))=0
     or position('communication_endpoint' in v_definition)=0 then
    raise exception 'Common Correspondence access v2 lost Endpoint-rooted Correspondence Identity enrichment.';
  end if;

  if position('institutional_communications_home' in v_definition)>0
     or position('institutional_shared_inbox' in v_definition)>0
     or position('institutional_conversation' in v_definition)>0 then
    raise exception 'Common Correspondence access v2 may not restore Institutional communications reads.';
  end if;

  if has_function_privilege('public',v_function,'EXECUTE')
     or has_function_privilege('anon',v_function,'EXECUTE') then
    raise exception 'Public/anon may not execute common Correspondence access v2.';
  end if;

  if not has_function_privilege('authenticated',v_function,'EXECUTE') then
    raise exception 'Authenticated role cannot execute common Correspondence access v2.';
  end if;
end;
$validation$;

rollback;
