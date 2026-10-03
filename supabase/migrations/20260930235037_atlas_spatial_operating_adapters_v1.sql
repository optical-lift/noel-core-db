-- Atlas Spatial Operating Adapters v1
-- Wires the shared spatial kernel into Principal Clock, Company Work, Ledger,
-- responsibilities, jurisdiction, observations, and organization footprints.

create or replace function atlas.spatial_subject_exists_v1(p_subject_kind text,p_subject_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if p_subject_kind='work_item' then return exists(select 1 from atlas.work_items where id=p_subject_id); end if;
  if p_subject_kind='work_requirement' then return exists(select 1 from atlas.work_requirements where id=p_subject_id); end if;
  if p_subject_kind='planned_work_occurrence' then return exists(select 1 from atlas.planned_work_occurrences where id=p_subject_id); end if;
  if p_subject_kind='organization_responsibility' then return exists(select 1 from atlas.organization_responsibilities where id=p_subject_id); end if;
  if p_subject_kind='ledger' then return exists(select 1 from atlas.ledgers where id=p_subject_id); end if;
  if p_subject_kind='principal_capacity_block' then return exists(select 1 from atlas.principal_capacity_blocks where id=p_subject_id); end if;
  if p_subject_kind='owner_obligation' then return exists(select 1 from atlas.owner_obligations where id=p_subject_id); end if;
  if p_subject_kind='household_event' then return exists(select 1 from atlas.household_events where id=p_subject_id); end if;
  if p_subject_kind='household_rhythm' then return exists(select 1 from atlas.household_rhythms where id=p_subject_id); end if;
  if p_subject_kind='operational_escalation' then return exists(select 1 from atlas.operational_escalations where id=p_subject_id); end if;
  if p_subject_kind='organization_ledger_entry' then return exists(select 1 from atlas.organization_ledger_entries where id=p_subject_id); end if;
  if p_subject_kind='communication_event' then return exists(select 1 from atlas.communication_events where id=p_subject_id); end if;
  if p_subject_kind='community_event' then return exists(select 1 from atlas.community_events where id=p_subject_id); end if;
  if p_subject_kind='object_activity_event' then return exists(select 1 from atlas.object_activity_events where id=p_subject_id); end if;
  if p_subject_kind='resource_event' then return exists(select 1 from atlas.resource_events where id=p_subject_id); end if;
  return false;
end
$function$;

create or replace function atlas.clock_source_spatial_subject_kind_v1(p_source_type text)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select case p_source_type
    when 'owner_obligation' then 'owner_obligation'
    when 'household_event' then 'household_event'
    when 'household_rhythm' then 'household_rhythm'
    when 'operational_escalation' then 'operational_escalation'
    when 'capacity_block' then 'principal_capacity_block'
    else null
  end;
$function$;

create or replace function atlas.principal_clock_spatial_overlay_v1(
  p_principal_id uuid,p_day date,p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','reality','geography'
as $function$
declare
  v_timezone text;
  v_candidates jsonb;
  v_transitions jsonb;
  v_place_count integer;
begin
  select home_timezone into v_timezone from atlas.principals where id=p_principal_id and status='active';
  if v_timezone is null then v_timezone:='UTC'; end if;

  with c as (
    select a.*,atlas.clock_source_spatial_subject_kind_v1(a.source_type) as subject_kind
    from atlas.principal_clock_arbitration_v1(p_principal_id,p_day,p_as_of) a
  ), enriched as (
    select c.*,sc.id as context_id,sc.context_kind,sc.place_entity_id,sc.presence_mode,sc.distance_limit_meters,e.display_name as place_name
    from c
    left join lateral (
      select x.* from atlas.spatial_contexts x
      where x.subject_kind=c.subject_kind and x.subject_id=c.source_id and x.context_state='active'
        and (x.valid_from is null or x.valid_from<=p_as_of) and (x.valid_until is null or p_as_of<x.valid_until)
      order by case x.context_kind when 'required_at' then 1 when 'occurs_at' then 2 when 'destination' then 3 when 'base_at' then 4 when 'preferred_near' then 5 when 'service_area' then 6 when 'location_flexibility' then 7 else 8 end,x.created_at
      limit 1
    ) sc on c.subject_kind is not null
    left join reality.entities e on e.id=sc.place_entity_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'arbitrationRank',arbitration_rank,'sourceType',source_type,'sourceId',source_id,'title',title,
    'contextKind',context_kind,'placeEntityId',place_entity_id,'placeName',place_name,
    'presenceMode',presence_mode,'distanceLimitMeters',distance_limit_meters,
    'spatialState',case when subject_kind is null then 'source_not_spatially_addressable' when context_id is null then 'spatial_context_unknown' when context_kind='location_flexibility' then 'location_flexible' else 'spatial_context_known' end
  ) order by arbitration_rank),'[]'::jsonb),
  count(distinct place_entity_id) filter(where place_entity_id is not null)::integer
  into v_candidates,v_place_count
  from enriched;

  with c as (
    select a.*,atlas.clock_source_spatial_subject_kind_v1(a.source_type) as subject_kind
    from atlas.principal_clock_arbitration_v1(p_principal_id,p_day,p_as_of) a
    where a.fixed_start is not null and (a.fixed_start at time zone v_timezone)::date=p_day
  ), fixed as (
    select c.*,
      sc.place_entity_id,sc.context_kind,e.display_name as place_name,
      lag(c.source_type) over(order by c.fixed_start,c.source_id) as prev_source_type,
      lag(c.source_id) over(order by c.fixed_start,c.source_id) as prev_source_id,
      lag(c.title) over(order by c.fixed_start,c.source_id) as prev_title,
      lag(c.window_end) over(order by c.fixed_start,c.source_id) as prev_window_end,
      lag(sc.place_entity_id) over(order by c.fixed_start,c.source_id) as prev_place_entity_id,
      lag(e.display_name) over(order by c.fixed_start,c.source_id) as prev_place_name
    from c
    left join lateral (
      select x.* from atlas.spatial_contexts x
      where x.subject_kind=c.subject_kind and x.subject_id=c.source_id and x.context_state='active' and x.place_entity_id is not null
        and x.context_kind in ('required_at','occurs_at','destination','base_at')
        and (x.valid_from is null or x.valid_from<=p_as_of) and (x.valid_until is null or p_as_of<x.valid_until)
      order by case x.context_kind when 'required_at' then 1 when 'occurs_at' then 2 when 'destination' then 3 else 4 end,x.created_at limit 1
    ) sc on c.subject_kind is not null
    left join reality.entities e on e.id=sc.place_entity_id
  ), pairs as (
    select f.*,
      case when f.prev_place_entity_id is not null and f.place_entity_id is not null then geography.place_distance_service_v1(f.prev_place_entity_id,f.place_entity_id) else null end as distance_receipt
    from fixed f where f.prev_source_id is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'from',jsonb_build_object('sourceType',prev_source_type,'sourceId',prev_source_id,'title',prev_title,'placeEntityId',prev_place_entity_id,'placeName',prev_place_name,'endsAt',prev_window_end),
    'to',jsonb_build_object('sourceType',source_type,'sourceId',source_id,'title',title,'placeEntityId',place_entity_id,'placeName',place_name,'startsAt',fixed_start),
    'gapMinutes',case when prev_window_end is null then null else extract(epoch from (fixed_start-prev_window_end))/60.0 end,
    'distance',distance_receipt,
    'feasibilityState',case
      when prev_place_entity_id is null or place_entity_id is null then 'spatial_context_incomplete'
      when prev_place_entity_id=place_entity_id then 'same_place'
      when prev_window_end is not null and fixed_start<prev_window_end then 'temporal_overlap_distinct_places'
      else 'routing_required_to_evaluate'
    end
  ) order by fixed_start,source_id),'[]'::jsonb) into v_transitions
  from pairs;

  return jsonb_build_object(
    'contractVersion','principal_clock_spatial_overlay_v1','serviceDate',p_day,'timezone',v_timezone,
    'distinctKnownPlaceCount',coalesce(v_place_count,0),'candidates',v_candidates,'fixedTransitions',v_transitions,
    'truthBoundary',jsonb_build_object(
      'geodesicDistanceIsNotTravelTime',true,
      'routingSourceRequiredForTravelFeasibility',true,
      'missingSpatialContextRemainsUnknown',true,
      'absenceOfContextDoesNotMeanRemote',true
    )
  );
end
$function$;

create or replace function atlas.principal_clock_spatial_api_v1(p_day date default current_date,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_principal_id uuid; v_clock jsonb; v_spatial jsonb;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  v_clock:=atlas.principal_clock_api_v1(p_day,p_as_of);
  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then return v_clock || jsonb_build_object('spatial',null,'spatialState','principal_required'); end if;
  v_spatial:=atlas.principal_clock_spatial_overlay_v1(v_principal_id,p_day,p_as_of);
  return v_clock || jsonb_build_object('contractVersion','principal_clock_spatial_api_v1','spatial',v_spatial);
end
$function$;

create or replace function atlas.responsibility_spatial_state_service_v1(p_responsibility_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if not exists(select 1 from atlas.organization_responsibilities where id=p_responsibility_id) then raise exception 'Organization responsibility not found.' using errcode='P0002'; end if;
  return jsonb_build_object(
    'responsibilityId',p_responsibility_id,
    'contexts',atlas.spatial_contexts_for_subject_service_v1('organization_responsibility',p_responsibility_id,p_as_of),
    'contractVersion','responsibility_spatial_state_v1'
  );
end
$function$;

create or replace function atlas.organization_operating_footprint_service_v1(p_entity_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','reality'
as $function$
declare v_entity reality.entities%rowtype; v_places jsonb;
begin
  select * into v_entity from reality.entities where id=p_entity_id and identity_state='canonical';
  if v_entity.id is null then raise exception 'Canonical Reality Entity required.' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'placeEntityId',x.place_entity_id,'placeName',x.place_name,'placeKind',x.place_kind,
    'presenceEntityId',x.presence_entity_id,'operatingDepth',x.operating_depth,'spatialDepth',x.spatial_depth,
    'operatingPathEntityIds',x.operating_path_entity_ids,'spatialPathEntityIds',x.spatial_path_entity_ids
  ) order by x.operating_depth,x.spatial_depth,x.place_name,x.place_entity_id),'[]'::jsonb) into v_places
  from reality.entity_spatial_presence_service_v1(p_entity_id,8,8,p_as_of) x;
  return jsonb_build_object('entityId',v_entity.id,'displayName',v_entity.display_name,'entityKind',v_entity.entity_kind,'places',v_places,'contractVersion','organization_operating_footprint_v1');
end
$function$;

create or replace function atlas.place_jurisdiction_chain_service_v1(p_place_entity_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','geography'
as $function$
declare v_chain jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('placeEntityId',x.place_entity_id,'displayName',x.display_name,'placeKind',x.place_kind,'depth',x.depth) order by x.depth,x.display_name),'[]'::jsonb)
  into v_chain from geography.place_ancestors_service_v1(p_place_entity_id,16,p_as_of) x;
  return jsonb_build_object('placeEntityId',p_place_entity_id,'jurisdictionChain',v_chain,'contractVersion','place_jurisdiction_chain_v1');
end
$function$;

create or replace function atlas.record_spatial_observation_context_service_v1(
  p_stable_key text,p_subject_kind text,p_subject_id uuid,p_place_entity_id uuid,p_organization_id uuid default null,p_basis jsonb default '{}'::jsonb,p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if p_subject_kind not in ('communication_event','community_event','object_activity_event','resource_event','organization_ledger_entry') then
    raise exception 'Subject kind is not an observation-capable event carrier.' using errcode='22023';
  end if;
  return atlas.put_spatial_context_service_v1(p_stable_key,p_subject_kind,p_subject_id,'observed_at',p_place_entity_id,'physical',null,null,null,p_organization_id,p_basis,p_metadata);
end
$function$;

create or replace function atlas.ledger_spatial_summary_service_v1(p_ledger_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','reality'
as $function$
declare v_direct jsonb; v_entries jsonb; v_entities jsonb;
begin
  if not exists(select 1 from atlas.ledgers where id=p_ledger_id and status='active') then raise exception 'Active Ledger required.' using errcode='P0002'; end if;
  v_direct:=atlas.spatial_contexts_for_subject_service_v1('ledger',p_ledger_id,p_as_of);

  select coalesce(jsonb_agg(jsonb_build_object(
    'ledgerEntryId',le.id,'title',le.title,'occurredAt',le.occurred_at,'contexts',atlas.spatial_contexts_for_subject_service_v1('organization_ledger_entry',le.id,p_as_of)
  ) order by le.occurred_at desc,le.id) filter(where atlas.spatial_contexts_for_subject_service_v1('organization_ledger_entry',le.id,p_as_of)<>'[]'::jsonb),'[]'::jsonb)
  into v_entries
  from atlas.organization_ledger_entries le where le.ledger_id=p_ledger_id;

  with entity_subjects as (
    select distinct ols.subject_id::uuid as entity_id
    from atlas.organization_ledger_entries le
    join atlas.organization_ledger_subjects ols on ols.ledger_entry_id=le.id
    where le.ledger_id=p_ledger_id and ols.subject_domain='reality' and ols.subject_kind='entity' and ols.subject_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and exists(select 1 from reality.entities e where e.id=ols.subject_id::uuid and e.identity_state='canonical')
  )
  select coalesce(jsonb_agg(atlas.organization_operating_footprint_service_v1(es.entity_id,p_as_of) order by es.entity_id),'[]'::jsonb) into v_entities from entity_subjects es;

  return jsonb_build_object(
    'ledgerId',p_ledger_id,'directContexts',v_direct,'spatialLedgerEntries',v_entries,'entityFootprints',v_entities,
    'contractVersion','ledger_spatial_summary_v1',
    'truthBoundary',jsonb_build_object('ledgerDoesNotInventEntityLocation',true,'entityFootprintComesFromCanonicalReality',true,'eventLocationRequiresExplicitSpatialContext',true)
  );
end
$function$;

create or replace function atlas.ledger_spatial_summary_self_api_v1(p_ledger_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_principal_id uuid;
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null or not atlas.principal_has_ledger_authority_v1(v_principal_id,p_ledger_id) then raise exception 'Ledger authority required.' using errcode='42501'; end if;
  return atlas.ledger_spatial_summary_service_v1(p_ledger_id,p_as_of);
end
$function$;

create or replace function atlas.work_item_spatial_state_service_v1(p_work_item_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare v_contexts jsonb; v_has_flex boolean; v_has_hard boolean;
begin
  if not exists(select 1 from atlas.work_items where id=p_work_item_id) then raise exception 'Work item not found.' using errcode='P0002'; end if;
  v_contexts:=atlas.spatial_contexts_for_subject_service_v1('work_item',p_work_item_id,p_as_of);
  select exists(select 1 from atlas.spatial_contexts where subject_kind='work_item' and subject_id=p_work_item_id and context_state='active' and context_kind='location_flexibility' and (valid_from is null or valid_from<=p_as_of) and (valid_until is null or p_as_of<valid_until)),
         exists(select 1 from atlas.spatial_contexts where subject_kind='work_item' and subject_id=p_work_item_id and context_state='active' and context_kind in ('required_at','occurs_at','destination') and (valid_from is null or valid_from<=p_as_of) and (valid_until is null or p_as_of<valid_until))
  into v_has_flex,v_has_hard;
  return jsonb_build_object(
    'workItemId',p_work_item_id,'contexts',v_contexts,
    'locationState',case when v_has_hard then 'place_required' when v_has_flex then 'location_flexible' when v_contexts<>'[]'::jsonb then 'spatial_context_known' else 'spatial_context_unknown' end,
    'contractVersion','work_item_spatial_state_v1'
  );
end
$function$;

revoke all on function atlas.clock_source_spatial_subject_kind_v1(text) from public,anon,authenticated;
revoke all on function atlas.principal_clock_spatial_overlay_v1(uuid,date,timestamptz) from public,anon,authenticated;
revoke all on function atlas.principal_clock_spatial_api_v1(date,timestamptz) from public,anon;
revoke all on function atlas.responsibility_spatial_state_service_v1(uuid,timestamptz) from public,anon,authenticated;
revoke all on function atlas.organization_operating_footprint_service_v1(uuid,timestamptz) from public,anon,authenticated;
revoke all on function atlas.place_jurisdiction_chain_service_v1(uuid,timestamptz) from public,anon,authenticated;
revoke all on function atlas.record_spatial_observation_context_service_v1(text,text,uuid,uuid,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function atlas.ledger_spatial_summary_service_v1(uuid,timestamptz) from public,anon,authenticated;
revoke all on function atlas.ledger_spatial_summary_self_api_v1(uuid,timestamptz) from public,anon;
revoke all on function atlas.work_item_spatial_state_service_v1(uuid,timestamptz) from public,anon,authenticated;

grant execute on function atlas.clock_source_spatial_subject_kind_v1(text) to service_role;
grant execute on function atlas.principal_clock_spatial_overlay_v1(uuid,date,timestamptz) to service_role;
grant execute on function atlas.principal_clock_spatial_api_v1(date,timestamptz) to authenticated,service_role;
grant execute on function atlas.responsibility_spatial_state_service_v1(uuid,timestamptz) to service_role;
grant execute on function atlas.organization_operating_footprint_service_v1(uuid,timestamptz) to service_role;
grant execute on function atlas.place_jurisdiction_chain_service_v1(uuid,timestamptz) to service_role;
grant execute on function atlas.record_spatial_observation_context_service_v1(text,text,uuid,uuid,uuid,jsonb,jsonb) to service_role;
grant execute on function atlas.ledger_spatial_summary_service_v1(uuid,timestamptz) to service_role;
grant execute on function atlas.ledger_spatial_summary_self_api_v1(uuid,timestamptz) to authenticated,service_role;
grant execute on function atlas.work_item_spatial_state_service_v1(uuid,timestamptz) to service_role;
