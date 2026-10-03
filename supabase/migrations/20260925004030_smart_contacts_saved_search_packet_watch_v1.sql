create or replace function atlas.update_smart_contact_saved_search_self_api_v1(
  p_saved_search_id uuid,
  p_expected_revision integer,
  p_name text default null,
  p_description text default null,
  p_smart_contacts_query jsonb default null,
  p_max_results integer default null,
  p_watch_enabled boolean default null,
  p_watch_cadence text default null,
  p_watch_policy jsonb default null,
  p_search_state text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_org uuid;
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  select organization_id into v_org from atlas.smart_contact_saved_searches where id=p_saved_search_id;
  if v_org is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(v_org);
  if v_membership_id is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.update_smart_contact_saved_search_service_v1(
    p_saved_search_id,p_expected_revision,p_name,p_description,p_smart_contacts_query,
    p_max_results,p_watch_enabled,p_watch_cadence,p_watch_policy,p_search_state,v_membership_id
  );
end
$function$;

create or replace function atlas.smart_contact_saved_search_watch_queue_service_v1(
  p_as_of timestamptz default now(),
  p_limit integer default 100
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'savedSearchId',q.id,'organizationId',q.organization_id,'stableKey',q.stable_key,
    'name',q.name,'watchCadence',q.watch_cadence,'lastRunAt',q.last_run_at,
    'dueAt',q.due_at,'watchPolicy',q.watch_policy
  ) order by q.due_at nulls first,q.organization_id,q.name),'[]'::jsonb)
  from (
    select s.*,
      case s.watch_cadence
        when 'hourly' then coalesce(s.last_run_at,s.created_at) + interval '1 hour'
        when 'daily' then coalesce(s.last_run_at,s.created_at) + interval '1 day'
        when 'weekly' then coalesce(s.last_run_at,s.created_at) + interval '7 days'
        else null
      end as due_at
    from atlas.smart_contact_saved_searches s
    where s.search_state='active'
      and s.watch_enabled
      and s.watch_cadence<>'manual'
      and case s.watch_cadence
        when 'hourly' then coalesce(s.last_run_at,s.created_at) + interval '1 hour' <= p_as_of
        when 'daily' then coalesce(s.last_run_at,s.created_at) + interval '1 day' <= p_as_of
        when 'weekly' then coalesce(s.last_run_at,s.created_at) + interval '7 days' <= p_as_of
        else false
      end
    order by due_at nulls first,s.organization_id,s.name
    limit greatest(1,least(coalesce(p_limit,100),500))
  ) q;
$function$;

create or replace function atlas.create_contact_selection_packet_from_saved_search_run_service_v1(
  p_request_id uuid,
  p_run_id uuid,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_request atlas.contact_set_intent_requests%rowtype;
  v_run atlas.smart_contact_saved_search_runs%rowtype;
  v_search atlas.smart_contact_saved_searches%rowtype;
  v_existing atlas.contact_selection_packets%rowtype;
  v_packet atlas.contact_selection_packets%rowtype;
  v_requested integer;
  v_count integer;
  v_version integer;
begin
  select * into v_request from atlas.contact_set_intent_requests where id=p_request_id;
  if v_request.id is null or v_request.request_state<>'ready' then
    raise exception 'Ready contact-set intent request is required.' using errcode='23514';
  end if;

  select * into v_run
  from atlas.smart_contact_saved_search_runs
  where id=p_run_id and run_state='completed';
  if v_run.id is null then raise exception 'Completed saved-search run not found.' using errcode='P0002'; end if;

  select * into v_search from atlas.smart_contact_saved_searches where id=v_run.saved_search_id;

  if v_request.organization_id<>v_run.organization_id then
    raise exception 'Saved-search run and contact-set request belong to different Organizations.' using errcode='42501';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_created_by_membership_id and m.organization_id=v_request.organization_id and m.active
  ) then raise exception 'Creating membership does not belong to the Organization.' using errcode='42501'; end if;

  select * into v_existing
  from atlas.contact_selection_packets
  where request_id=v_request.id and packet_state in ('proposed','confirmed','handed_off')
  order by packet_version desc limit 1;
  if v_existing.id is not null then
    raise exception 'An active selection packet already exists for this request.' using errcode='23505';
  end if;

  begin
    v_requested:=nullif(v_request.interpretation#>>'{population,desiredCount}','')::integer;
  exception when invalid_text_representation then
    raise exception 'Contact-set desired count is invalid.' using errcode='23514';
  end;
  if v_requested is not null and v_requested<=0 then
    raise exception 'Contact-set desired count must be positive.' using errcode='23514';
  end if;

  select count(*)::integer into v_count
  from atlas.smart_contact_saved_search_run_items where run_id=v_run.id;

  select coalesce(max(packet_version),0)+1 into v_version
  from atlas.contact_selection_packets where request_id=v_request.id;

  insert into atlas.contact_selection_packets(
    request_id,organization_id,organization_unit_id,packet_version,packet_state,
    smart_contacts_query,search_snapshot,query_fingerprint,requested_count,
    candidate_count,selected_count,revision,created_by_membership_id
  ) values (
    v_request.id,v_request.organization_id,v_request.organization_unit_id,v_version,'proposed',
    v_run.query_snapshot,
    jsonb_build_object(
      'contractVersion','smart_contact_saved_search_run_snapshot_v1',
      'savedSearchId',v_search.id,'savedSearchName',v_search.name,'runId',v_run.id,
      'runNumber',v_run.run_number,'completedAt',v_run.completed_at,'resultCount',v_run.result_count,
      'items',coalesce((
        select jsonb_agg(i.smart_contact_snapshot order by i.ordinal)
        from atlas.smart_contact_saved_search_run_items i where i.run_id=v_run.id
      ),'[]'::jsonb)
    ),
    v_run.query_fingerprint,v_requested,v_count,least(coalesce(v_requested,v_count),v_count),
    1,p_created_by_membership_id
  ) returning * into v_packet;

  insert into atlas.contact_selection_packet_items(
    packet_id,entity_id,ordinal,selection_state,smart_contact_snapshot,reason_snapshot
  )
  select v_packet.id,i.entity_id,i.ordinal,
         case when v_requested is null or i.ordinal<=v_requested then 'selected' else 'alternate' end,
         i.smart_contact_snapshot,
         jsonb_build_object(
           'source','saved_search_run','savedSearchId',v_search.id,'savedSearchRunId',v_run.id,
           'match',coalesce(i.smart_contact_snapshot->'match','{}'::jsonb),
           'peopleState',i.smart_contact_snapshot#>>'{people,state}',
           'contactabilityState',i.smart_contact_snapshot#>>'{contactability,state}',
           'freshnessState',i.smart_contact_snapshot#>>'{freshness,state}',
           'researchGaps',coalesce(i.smart_contact_snapshot->'researchGaps','[]'::jsonb)
         )
  from atlas.smart_contact_saved_search_run_items i
  where i.run_id=v_run.id
  order by i.ordinal;

  insert into atlas.contact_selection_packet_events(
    packet_id,organization_id,event_kind,event_payload,actor_membership_id
  ) values (
    v_packet.id,v_packet.organization_id,'created',
    jsonb_build_object(
      'requestId',v_packet.request_id,'source','saved_search_run',
      'savedSearchId',v_search.id,'savedSearchRunId',v_run.id,
      'requestedCount',v_packet.requested_count,'candidateCount',v_packet.candidate_count,
      'selectedCount',v_packet.selected_count
    ),
    p_created_by_membership_id
  );

  return jsonb_build_object(
    'ok',true,'contractVersion','contact_selection_packet_from_saved_search_run_v1',
    'packetId',v_packet.id,'savedSearchId',v_search.id,'savedSearchRunId',v_run.id,
    'candidateCount',v_packet.candidate_count,'selectedCount',v_packet.selected_count,
    'revision',v_packet.revision,
    'truthBoundary',jsonb_build_object(
      'reranSmartContacts',false,'usedFrozenSavedSearchRun',true,
      'organizationRelationshipCreated',false,'communicationAuthorized',false
    )
  );
end
$function$;

create or replace function atlas.create_contact_selection_packet_from_saved_search_run_self_api_v1(
  p_request_id uuid,
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_org uuid;
  v_run_org uuid;
  v_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select organization_id into v_org from atlas.contact_set_intent_requests where id=p_request_id;
  select organization_id into v_run_org
  from atlas.smart_contact_saved_search_runs where id=p_run_id and run_state='completed';
  if v_org is null or v_run_org is null then
    raise exception 'Request or completed saved-search run not found.' using errcode='P0002';
  end if;
  if v_org<>v_run_org then
    raise exception 'Request and saved-search run belong to different Organizations.' using errcode='42501';
  end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(v_org);
  if v_membership_id is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.create_contact_selection_packet_from_saved_search_run_service_v1(
    p_request_id,p_run_id,v_membership_id
  );
end
$function$;

revoke all on function atlas.update_smart_contact_saved_search_self_api_v1(uuid,integer,text,text,jsonb,integer,boolean,text,jsonb,text)
  from public,anon;
grant execute on function atlas.update_smart_contact_saved_search_self_api_v1(uuid,integer,text,text,jsonb,integer,boolean,text,jsonb,text)
  to authenticated;
revoke all on function atlas.smart_contact_saved_search_watch_queue_service_v1(timestamptz,integer)
  from public,anon,authenticated;
grant execute on function atlas.smart_contact_saved_search_watch_queue_service_v1(timestamptz,integer)
  to service_role;
revoke all on function atlas.create_contact_selection_packet_from_saved_search_run_service_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.create_contact_selection_packet_from_saved_search_run_service_v1(uuid,uuid,uuid)
  to service_role;
revoke all on function atlas.create_contact_selection_packet_from_saved_search_run_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function atlas.create_contact_selection_packet_from_saved_search_run_self_api_v1(uuid,uuid)
  to authenticated;
