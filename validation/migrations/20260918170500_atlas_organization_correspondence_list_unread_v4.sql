begin;

do $validation$
begin
  if to_regprocedure('atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)') is null then
    raise exception 'organization_correspondence_list_self_api_v4 is missing.';
  end if;

  if has_function_privilege('anon','atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)','EXECUTE') then
    raise exception 'anon may not execute organization_correspondence_list_self_api_v4.';
  end if;

  if not has_function_privilege('authenticated','atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)','EXECUTE') then
    raise exception 'authenticated must execute organization_correspondence_list_self_api_v4.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='organization_correspondence_list_self_api_v4'
      and p.prosrc ilike '%communication_attention_events%'
      and p.prosrc ilike '%openedByMe%'
      and p.prosrc ilike '%latestAttentionKind%'
      and p.prosrc ilike '%organization_correspondence_list_self_api_v3%'
  ) then
    raise exception 'Correspondence list v4 lost common-list or exact Event attention dependency.';
  end if;
end;
$validation$;

rollback;
