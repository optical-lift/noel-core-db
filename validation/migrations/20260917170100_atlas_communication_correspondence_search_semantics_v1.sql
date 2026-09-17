-- Validation for Stage 2 canonical Correspondence search semantics.
-- Run only after 20260917170000 + this correction in a disposable schema.

begin;

do $validation$
declare
  v_definition text;
  v_volatility "char";
begin
  if to_regprocedure('atlas.organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer)') is null then
    raise exception 'Canonical Organization Correspondence search is missing.';
  end if;

  select lower(pg_get_functiondef(p.oid)),p.provolatile
  into v_definition,v_volatility
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='organization_correspondence_search_self_api_v1'
    and pg_get_function_identity_arguments(p.oid)='p_query text, p_organization_id uuid, p_communication_endpoint_id uuid, p_filters jsonb, p_limit integer';

  if v_volatility<>'s' then
    raise exception 'Canonical Correspondence search is not STABLE.';
  end if;

  if position('communication_conversations' in v_definition)=0
     or position('communication_conversation_events' in v_definition)=0
     or position('organization_correspondence_read_authorized_self_v1' in v_definition)=0 then
    raise exception 'Canonical Correspondence search no longer uses the common Conversation read membrane.';
  end if;

  if position('bool_or(exists(' in v_definition)=0 then
    raise exception 'Attachment presence is not derived from actual attachment existence.';
  end if;

  if position('true as has_attachment' in v_definition)>0 then
    raise exception 'Attachment presence still depends on aggregate row existence.';
  end if;

  if v_definition ~ E'\\m(insert|update|delete|merge|truncate)\\M[[:space:]]+(into|atlas\\.|from|table)' then
    raise exception 'Canonical Correspondence search contains a direct mutation statement.';
  end if;
end;
$validation$;

rollback;
