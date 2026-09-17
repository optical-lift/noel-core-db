-- Validation for Package 7 Communications convergence Stage 5 common draft read.

begin;

do $validation$
declare
  v_proc regprocedure;
  v_definition text;
  v_acl aclitem[];
begin
  v_proc:=to_regprocedure('atlas.organization_correspondence_drafts_self_api_v1(uuid,uuid,uuid,integer)');
  if v_proc is null then
    raise exception 'Common Correspondence draft read is missing.';
  end if;

  select lower(pg_get_functiondef(v_proc)),p.proacl
  into v_definition,v_acl
  from pg_proc p
  where p.oid=v_proc;

  if position('communication_email_draft' in v_definition)=0
     or position('communication_conversation_id' in v_definition)=0
     or position('institutionalcompatibilityid' in replace(v_definition,'_',''))=0
     or position('communication_outbound_attachments' in v_definition)=0
     or position('communication_endpoint_membership_has_capability_v1' in v_definition)=0 then
    raise exception 'Common draft read lost Draft/Conversation/Endpoint custody or attachment metadata.';
  end if;

  if has_function_privilege('anon',v_proc,'EXECUTE') then
    raise exception 'Anonymous role may not execute the common Correspondence draft read.';
  end if;
  if not has_function_privilege('authenticated',v_proc,'EXECUTE') then
    raise exception 'Authenticated role cannot execute the common Correspondence draft read.';
  end if;
end;
$validation$;

rollback;
