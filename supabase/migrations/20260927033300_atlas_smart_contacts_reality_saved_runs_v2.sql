-- Smart Contacts saved-run Reality cutover v2.
-- Saved audiences may contain canonical Reality entities with or without Local Intelligence
-- provenance. Unresolved research contacts may remain in a run, but downstream fundraising must
-- require reality_entity_id.

alter table atlas.smart_contact_saved_search_run_items
  alter column entity_id drop not null;

alter table atlas.smart_contact_saved_search_run_items
  add constraint smart_contact_saved_search_run_item_identity_path_v2
  check (entity_id is not null or reality_entity_id is not null);

alter table atlas.smart_contact_saved_search_run_deltas
  alter column entity_id drop not null,
  add column if not exists reality_entity_id uuid references reality.entities(id) on delete restrict;

alter table atlas.smart_contact_saved_search_run_deltas
  add constraint smart_contact_saved_search_run_delta_identity_path_v2
  check (entity_id is not null or reality_entity_id is not null);

create unique index if not exists smart_contact_saved_search_run_delta_reality_uq
  on atlas.smart_contact_saved_search_run_deltas(run_id,reality_entity_id,change_kind)
  where reality_entity_id is not null;

alter table atlas.contact_selection_packet_items
  alter column entity_id drop not null;

alter table atlas.contact_selection_packet_items
  add constraint contact_selection_packet_item_identity_path_v2
  check (entity_id is not null or reality_entity_id is not null);

create unique index if not exists contact_selection_packet_items_packet_reality_uq
  on atlas.contact_selection_packet_items(packet_id,reality_entity_id)
  where reality_entity_id is not null;

create or replace function atlas.run_smart_contact_saved_search_service_v2(
  p_saved_search_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_search atlas.smart_contact_saved_searches%rowtype;
  v_previous atlas.smart_contact_saved_search_runs%rowtype;
  v_run atlas.smart_contact_saved_search_runs%rowtype;
  v_payload jsonb;
  v_item jsonb;
  v_source_entity_id uuid;
  v_reality_entity_id uuid;
  v_ordinal integer:=0;
  v_new integer:=0;
  v_updated integer:=0;
  v_removed integer:=0;
begin
  select * into v_search
  from atlas.smart_contact_saved_searches
  where id=p_saved_search_id
  for update;

  if v_search.id is null then
    raise exception 'Saved search not found.' using errcode='P0002';
  end if;
  if v_search.search_state='archived' then
    raise exception 'Archived saved searches cannot run.' using errcode='23514';
  end if;

  select * into v_previous
  from atlas.smart_contact_saved_search_runs
  where saved_search_id=v_search.id and run_state='completed'
  order by run_number desc
  limit 1;

  insert into atlas.smart_contact_saved_search_runs(
    saved_search_id,organization_id,run_number,previous_run_id,search_revision,
    run_state,query_snapshot,query_fingerprint,metadata
  ) values (
    v_search.id,v_search.organization_id,coalesce(v_previous.run_number,0)+1,
    v_previous.id,v_search.revision,'running',v_search.smart_contacts_query,v_search.query_fingerprint,
    jsonb_build_object('identityContractVersion','reality_v2')
  )
  returning * into v_run;

  v_payload:=atlas.smart_contacts_search_service_v2(
    v_search.organization_id,v_search.smart_contacts_query,v_search.max_results
  );

  for v_item in
    select value from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb))
  loop
    begin v_source_entity_id:=nullif(v_item->>'sourceEntityId','')::uuid;
    exception when others then v_source_entity_id:=null; end;
    begin v_reality_entity_id:=nullif(v_item->>'realityEntityId','')::uuid;
    exception when others then v_reality_entity_id:=null; end;

    if v_source_entity_id is null and v_reality_entity_id is null then
      raise exception 'Smart Contacts V2 item has neither source nor Reality identity.' using errcode='23514';
    end if;

    if v_reality_entity_id is not null and exists(
      select 1 from atlas.smart_contact_saved_search_run_items i
      where i.run_id=v_run.id and i.reality_entity_id=v_reality_entity_id
    ) then
      continue;
    end if;

    v_ordinal:=v_ordinal+1;
    insert into atlas.smart_contact_saved_search_run_items(
      run_id,entity_id,reality_entity_id,ordinal,relevance_score,smart_contact_snapshot,snapshot_fingerprint
    ) values (
      v_run.id,v_source_entity_id,v_reality_entity_id,v_ordinal,
      nullif(v_item#>>'{match,relevanceScore}','')::integer,
      v_item,md5(v_item::text)
    );
  end loop;

  insert into atlas.smart_contact_saved_search_run_deltas(
    run_id,previous_run_id,entity_id,reality_entity_id,change_kind,current_item_id,previous_item_id,change_summary
  )
  select
    v_run.id,v_previous.id,c.entity_id,c.reality_entity_id,'new',c.id,null,
    jsonb_build_object('currentOrdinal',c.ordinal,'currentScore',c.relevance_score,
                       'identityContractVersion','reality_v2')
  from atlas.smart_contact_saved_search_run_items c
  where c.run_id=v_run.id
    and (
      v_previous.id is null
      or not exists(
        select 1
        from atlas.smart_contact_saved_search_run_items p
        where p.run_id=v_previous.id
          and coalesce('reality:'||p.reality_entity_id::text,'source:'||p.entity_id::text)
              =coalesce('reality:'||c.reality_entity_id::text,'source:'||c.entity_id::text)
      )
    );

  get diagnostics v_new=row_count;

  if v_previous.id is not null then
    insert into atlas.smart_contact_saved_search_run_deltas(
      run_id,previous_run_id,entity_id,reality_entity_id,change_kind,current_item_id,previous_item_id,change_summary
    )
    select
      v_run.id,v_previous.id,c.entity_id,c.reality_entity_id,'updated',c.id,p.id,
      jsonb_build_object(
        'priorOrdinal',p.ordinal,
        'currentOrdinal',c.ordinal,
        'priorScore',p.relevance_score,
        'currentScore',c.relevance_score,
        'searchDefinitionChanged',v_run.search_revision<>v_previous.search_revision,
        'identityContractVersion','reality_v2'
      )
    from atlas.smart_contact_saved_search_run_items c
    join atlas.smart_contact_saved_search_run_items p
      on p.run_id=v_previous.id
     and coalesce('reality:'||p.reality_entity_id::text,'source:'||p.entity_id::text)
         =coalesce('reality:'||c.reality_entity_id::text,'source:'||c.entity_id::text)
    where c.run_id=v_run.id
      and c.snapshot_fingerprint<>p.snapshot_fingerprint;

    get diagnostics v_updated=row_count;

    insert into atlas.smart_contact_saved_search_run_deltas(
      run_id,previous_run_id,entity_id,reality_entity_id,change_kind,current_item_id,previous_item_id,change_summary
    )
    select
      v_run.id,v_previous.id,p.entity_id,p.reality_entity_id,'removed',null,p.id,
      jsonb_build_object(
        'priorOrdinal',p.ordinal,
        'priorScore',p.relevance_score,
        'searchDefinitionChanged',v_run.search_revision<>v_previous.search_revision,
        'identityContractVersion','reality_v2'
      )
    from atlas.smart_contact_saved_search_run_items p
    where p.run_id=v_previous.id
      and not exists(
        select 1
        from atlas.smart_contact_saved_search_run_items c
        where c.run_id=v_run.id
          and coalesce('reality:'||c.reality_entity_id::text,'source:'||c.entity_id::text)
              =coalesce('reality:'||p.reality_entity_id::text,'source:'||p.entity_id::text)
      );

    get diagnostics v_removed=row_count;
  end if;

  update atlas.smart_contact_saved_search_runs
  set
    run_state='completed',
    result_count=v_ordinal,
    new_count=v_new,
    updated_count=v_updated,
    removed_count=v_removed,
    completed_at=now(),
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'identityContractVersion','reality_v2',
      'canonicalCount',(select count(*) from atlas.smart_contact_saved_search_run_items i where i.run_id=v_run.id and i.reality_entity_id is not null),
      'unresolvedCount',(select count(*) from atlas.smart_contact_saved_search_run_items i where i.run_id=v_run.id and i.reality_entity_id is null),
      'searchDefinitionChanged',v_previous.id is not null and v_run.search_revision<>v_previous.search_revision
    )
  where id=v_run.id
  returning * into v_run;

  update atlas.smart_contact_saved_searches
  set last_run_at=v_run.completed_at,updated_at=now()
  where id=v_search.id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','smart_contact_saved_search_run_reality_v2',
    'savedSearchId',v_search.id,
    'runId',v_run.id,
    'runNumber',v_run.run_number,
    'searchRevision',v_run.search_revision,
    'resultCount',v_run.result_count,
    'canonicalCount',v_run.metadata->'canonicalCount',
    'unresolvedCount',v_run.metadata->'unresolvedCount',
    'changes',jsonb_build_object('new',v_run.new_count,'updated',v_run.updated_count,'removed',v_run.removed_count),
    'currentAudienceIsLatestCompletedRun',true,
    'truthBoundary',jsonb_build_object(
      'canonicalIdentityUsesRealityEntityId',true,
      'unresolvedResearchRowsMayRemainForReview',true,
      'fundraisingAndCommunicationMustRequireRealityEntityId',true
    )
  );
end;
$$;

revoke all on function atlas.run_smart_contact_saved_search_service_v2(uuid)
  from public,anon,authenticated;
grant execute on function atlas.run_smart_contact_saved_search_service_v2(uuid)
  to service_role;

create or replace function atlas.run_smart_contact_saved_search_self_api_v2(
  p_saved_search_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_org uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select organization_id into v_org
  from atlas.smart_contact_saved_searches
  where id=p_saved_search_id;
  if v_org is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;
  if atlas.current_effective_organization_membership_v1(v_org) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.run_smart_contact_saved_search_service_v2(p_saved_search_id);
end;
$$;

revoke all on function atlas.run_smart_contact_saved_search_self_api_v2(uuid) from public,anon;
grant execute on function atlas.run_smart_contact_saved_search_self_api_v2(uuid) to authenticated;
