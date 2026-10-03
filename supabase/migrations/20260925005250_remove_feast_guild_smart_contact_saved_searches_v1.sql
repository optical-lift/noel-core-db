do $$
declare
  v_org uuid;
  v_packet_refs integer;
begin
  select id into v_org
  from atlas.organizations
  where stable_key='feast_guild';

  if v_org is null then
    return;
  end if;

  select count(*) into v_packet_refs
  from atlas.contact_selection_packets p
  where p.organization_id=v_org
    and (
      p.search_snapshot->>'savedSearchId' in (
        select s.id::text
        from atlas.smart_contact_saved_searches s
        where s.organization_id=v_org
      )
      or p.search_snapshot->>'runId' in (
        select r.id::text
        from atlas.smart_contact_saved_search_runs r
        join atlas.smart_contact_saved_searches s on s.id=r.saved_search_id
        where s.organization_id=v_org
      )
    );

  if v_packet_refs > 0 then
    raise exception 'Cannot remove Feast Guild saved searches: % downstream selection packets reference their runs.', v_packet_refs;
  end if;

  delete from atlas.smart_contact_saved_searches
  where organization_id=v_org;
end $$;
