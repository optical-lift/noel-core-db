-- Canonical Reality contact selection packet v2.
-- Converts a completed V2 Smart Contacts saved run into a frozen candidate packet containing
-- canonical Reality entities only. Unresolved research contacts remain visible in the saved run
-- but cannot become communication/fundraising candidates through this membrane.

create or replace function atlas.create_reality_contact_packet_from_saved_run_service_v2(
  p_request_id uuid,
  p_run_id uuid,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_request atlas.contact_set_intent_requests%rowtype;
  v_run atlas.smart_contact_saved_search_runs%rowtype;
  v_search atlas.smart_contact_saved_searches%rowtype;
  v_existing atlas.contact_selection_packets%rowtype;
  v_packet atlas.contact_selection_packets%rowtype;
  v_requested integer;
  v_count integer;
  v_unresolved integer;
  v_version integer;
begin
  select * into v_request
  from atlas.contact_set_intent_requests
  where id=p_request_id;
  if v_request.id is null or v_request.request_state<>'ready' then
    raise exception 'Ready contact-set intent request is required.' using errcode='23514';
  end if;

  select * into v_run
  from atlas.smart_contact_saved_search_runs
  where id=p_run_id and run_state='completed';
  if v_run.id is null then raise exception 'Completed saved-search run not found.' using errcode='P0002'; end if;
  if coalesce(v_run.metadata->>'identityContractVersion','')<>'reality_v2' then
    raise exception 'Reality V2 saved-search run required.' using errcode='23514';
  end if;

  select * into v_search
  from atlas.smart_contact_saved_searches
  where id=v_run.saved_search_id;

  if v_request.organization_id<>v_run.organization_id then
    raise exception 'Saved-search run and contact-set request belong to different Organizations.' using errcode='42501';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_created_by_membership_id
      and m.organization_id=v_request.organization_id
      and m.active
  ) then
    raise exception 'Creating membership does not belong to the Organization.' using errcode='42501';
  end if;

  select * into v_existing
  from atlas.contact_selection_packets
  where request_id=v_request.id
    and packet_state in ('proposed','confirmed','handed_off')
  order by packet_version desc
  limit 1;
  if v_existing.id is not null then
    raise exception 'An active selection packet already exists for this request.' using errcode='23505';
  end if;

  begin v_requested:=nullif(v_request.interpretation#>>'{population,desiredCount}','')::integer;
  exception when invalid_text_representation then
    raise exception 'Contact-set desired count is invalid.' using errcode='23514';
  end;
  if v_requested is not null and v_requested<=0 then
    raise exception 'Contact-set desired count must be positive.' using errcode='23514';
  end if;

  select count(*)::integer,
         count(*) filter(where reality_entity_id is null)::integer
  into v_count,v_unresolved
  from atlas.smart_contact_saved_search_run_items
  where run_id=v_run.id;

  v_count:=v_count-v_unresolved;

  select coalesce(max(packet_version),0)+1 into v_version
  from atlas.contact_selection_packets
  where request_id=v_request.id;

  insert into atlas.contact_selection_packets(
    request_id,organization_id,organization_unit_id,packet_version,packet_state,
    smart_contacts_query,search_snapshot,query_fingerprint,requested_count,
    candidate_count,selected_count,revision,created_by_membership_id
  ) values (
    v_request.id,v_request.organization_id,v_request.organization_unit_id,v_version,'proposed',
    v_run.query_snapshot,
    jsonb_build_object(
      'contractVersion','smart_contact_saved_search_run_reality_snapshot_v2',
      'savedSearchId',v_search.id,
      'savedSearchName',v_search.name,
      'runId',v_run.id,
      'runNumber',v_run.run_number,
      'completedAt',v_run.completed_at,
      'canonicalResultCount',v_count,
      'unresolvedExcludedCount',v_unresolved,
      'items',coalesce((
        select jsonb_agg(i.smart_contact_snapshot order by i.ordinal)
        from atlas.smart_contact_saved_search_run_items i
        where i.run_id=v_run.id and i.reality_entity_id is not null
      ),'[]'::jsonb)
    ),
    v_run.query_fingerprint,v_requested,v_count,
    least(coalesce(v_requested,v_count),v_count),1,p_created_by_membership_id
  ) returning * into v_packet;

  insert into atlas.contact_selection_packet_items(
    packet_id,entity_id,reality_entity_id,ordinal,selection_state,smart_contact_snapshot,reason_snapshot
  )
  select
    v_packet.id,
    ranked.entity_id,
    ranked.reality_entity_id,
    ranked.canonical_ordinal,
    case when v_requested is null or ranked.canonical_ordinal<=v_requested then 'selected' else 'alternate' end,
    ranked.smart_contact_snapshot,
    jsonb_build_object(
      'source','saved_search_run_reality_v2',
      'savedSearchId',v_search.id,
      'savedSearchRunId',v_run.id,
      'realityEntityId',ranked.reality_entity_id,
      'match',coalesce(ranked.smart_contact_snapshot->'match','{}'::jsonb),
      'canonicalState',ranked.smart_contact_snapshot->>'canonicalState',
      'contactabilityState',ranked.smart_contact_snapshot#>>'{contactability,state}',
      'researchGaps',coalesce(ranked.smart_contact_snapshot->'researchGaps','[]'::jsonb)
    )
  from (
    select i.*,row_number() over(order by i.ordinal)::integer as canonical_ordinal
    from atlas.smart_contact_saved_search_run_items i
    where i.run_id=v_run.id and i.reality_entity_id is not null
  ) ranked
  order by ranked.canonical_ordinal;

  insert into atlas.contact_selection_packet_events(
    packet_id,organization_id,event_kind,event_payload,actor_membership_id
  ) values (
    v_packet.id,v_packet.organization_id,'created',
    jsonb_build_object(
      'requestId',v_packet.request_id,
      'source','saved_search_run_reality_v2',
      'savedSearchId',v_search.id,
      'savedSearchRunId',v_run.id,
      'requestedCount',v_packet.requested_count,
      'canonicalCandidateCount',v_packet.candidate_count,
      'unresolvedExcludedCount',v_unresolved,
      'selectedCount',v_packet.selected_count
    ),p_created_by_membership_id
  );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','contact_selection_packet_reality_v2',
    'packetId',v_packet.id,
    'savedSearchId',v_search.id,
    'savedSearchRunId',v_run.id,
    'candidateCount',v_packet.candidate_count,
    'unresolvedExcludedCount',v_unresolved,
    'selectedCount',v_packet.selected_count,
    'revision',v_packet.revision,
    'truthBoundary',jsonb_build_object(
      'canonicalRealityEntitiesOnly',true,
      'unresolvedResearchContactsExcluded',true,
      'organizationRelationshipCreated',false,
      'communicationAuthorized',false
    )
  );
end;
$$;

revoke all on function atlas.create_reality_contact_packet_from_saved_run_service_v2(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.create_reality_contact_packet_from_saved_run_service_v2(uuid,uuid,uuid)
  to service_role;

create or replace function atlas.create_reality_contact_packet_from_saved_run_self_api_v2(
  p_request_id uuid,
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_org uuid;
  v_membership uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select organization_id into v_org
  from atlas.contact_set_intent_requests
  where id=p_request_id;
  if v_org is null then raise exception 'Contact-set request not found.' using errcode='P0002'; end if;
  v_membership:=atlas.current_effective_organization_membership_v1(v_org);
  if v_membership is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.create_reality_contact_packet_from_saved_run_service_v2(p_request_id,p_run_id,v_membership);
end;
$$;

revoke all on function atlas.create_reality_contact_packet_from_saved_run_self_api_v2(uuid,uuid)
  from public,anon;
grant execute on function atlas.create_reality_contact_packet_from_saved_run_self_api_v2(uuid,uuid)
  to authenticated;
