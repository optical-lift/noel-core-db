-- Atlas community-event canonical occurrence succession bridge v1
-- Existing atlas.community_events rows become operational/program carriers bound
-- to Organization-private bindings over canonical local_intel.occurrences.

alter table atlas.community_events
  add column if not exists occurrence_binding_id uuid null
  references atlas.organization_occurrence_bindings(id) on delete restrict;

comment on column atlas.community_events.occurrence_binding_id is
  'Organization-private binding to the canonical local_intel occurrence this operational/program row describes. atlas.community_events is not occurrence identity authority.';

create index if not exists community_events_occurrence_binding_idx
  on atlas.community_events(occurrence_binding_id)
  where occurrence_binding_id is not null;

create or replace function atlas.enforce_community_event_occurrence_binding_org_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_farm_org uuid;
  v_binding_org uuid;
begin
  if new.occurrence_binding_id is null then
    return new;
  end if;

  select f.organization_id into v_farm_org
  from atlas.farms f
  where f.id=new.farm_id;

  select b.organization_id into v_binding_org
  from atlas.organization_occurrence_bindings b
  where b.id=new.occurrence_binding_id;

  if v_farm_org is null then
    raise exception 'Community event farm is missing.' using errcode='23503';
  end if;

  if v_binding_org is null then
    raise exception 'Occurrence binding is missing.' using errcode='23503';
  end if;

  if v_farm_org <> v_binding_org then
    raise exception 'Community event occurrence binding belongs to another Organization.' using errcode='23514';
  end if;

  return new;
end
$function$;

drop trigger if exists enforce_community_event_occurrence_binding_org_v1
  on atlas.community_events;

create trigger enforce_community_event_occurrence_binding_org_v1
before insert or update of farm_id, occurrence_binding_id
on atlas.community_events
for each row
execute function atlas.enforce_community_event_occurrence_binding_org_v1();

-- Two pre-existing Shared Intelligence occurrences already represent the
-- September 3 and September 17 Elm flower-farming mornings. Reuse them.
update local_intel.occurrences o
set metadata = coalesce(o.metadata,'{}'::jsonb) || jsonb_build_object(
      'atlasCommunityEventId',
        case o.stable_key
          when 'elm-community-flower-day-2026-09-03' then 'e3a78c77-ca48-496c-9c98-7e9b1d9c582d'
          when 'elm-community-flower-day-2026-09-17' then 'ac314e2f-d39c-46e4-a1e3-dd7cd0c83ac9'
        end,
      'atlasCommunityEventStableKey',
        case o.stable_key
          when 'elm-community-flower-day-2026-09-03' then 'thursdays_at_elm_2026_09_03_morning'
          when 'elm-community-flower-day-2026-09-17' then 'thursdays_at_elm_2026_09_17_morning'
        end,
      'successionBridgeVersion','atlas_community_event_occurrence_v1'
    ),
    updated_at=now()
where o.stable_key in (
  'elm-community-flower-day-2026-09-03',
  'elm-community-flower-day-2026-09-17'
);

-- Every other legacy Atlas community event receives one canonical Shared
-- Intelligence occurrence. The UUID-derived stable key is deterministic and
-- intentionally marks this as legacy succession provenance rather than a new
-- public naming convention.
with elm_entity as (
  select e.*
  from local_intel.entities e
  where e.id='de584041-a636-424d-b8f5-2ff90ba3685e'
),
legacy_events as (
  select c.*
  from atlas.community_events c
  where c.id not in (
    'e3a78c77-ca48-496c-9c98-7e9b1d9c582d'::uuid,
    'ac314e2f-d39c-46e4-a1e3-dd7cd0c83ac9'::uuid
  )
)
insert into local_intel.occurrences(
  stable_key,
  entity_id,
  title,
  occurrence_type,
  start_at,
  end_at,
  venue_name,
  address_line1,
  city,
  state,
  postal_code,
  status,
  metadata
)
select
  'atlas-community-event-'||c.id::text,
  e.id,
  c.title,
  c.event_kind,
  (c.event_date + c.start_local_time) at time zone c.timezone_name,
  (c.event_date + c.end_local_time) at time zone c.timezone_name,
  e.name,
  e.address_line1,
  e.city,
  e.state,
  e.postal_code,
  c.status,
  jsonb_build_object(
    'canonicalizedFrom','atlas.community_events',
    'atlasCommunityEventId',c.id,
    'atlasCommunityEventStableKey',c.stable_key,
    'atlasProgramId',c.program_id,
    'successionBridgeVersion','atlas_community_event_occurrence_v1',
    'operationalStatusAtSuccession',c.status
  )
from legacy_events c
cross join elm_entity e
on conflict (stable_key) do update
set metadata=local_intel.occurrences.metadata || excluded.metadata,
    updated_at=now();

-- Bind every community event's canonical occurrence to the Organization that
-- owns the farm/program operational row.
with resolved as (
  select
    c.id as community_event_id,
    f.organization_id,
    case
      when c.id='e3a78c77-ca48-496c-9c98-7e9b1d9c582d'::uuid
        then (select id from local_intel.occurrences where stable_key='elm-community-flower-day-2026-09-03')
      when c.id='ac314e2f-d39c-46e4-a1e3-dd7cd0c83ac9'::uuid
        then (select id from local_intel.occurrences where stable_key='elm-community-flower-day-2026-09-17')
      else (select id from local_intel.occurrences where stable_key='atlas-community-event-'||c.id::text)
    end as occurrence_id
  from atlas.community_events c
  join atlas.farms f on f.id=c.farm_id
),
bound as (
  insert into atlas.organization_occurrence_bindings(
    organization_id,occurrence_id,binding_state,metadata
  )
  select
    r.organization_id,
    r.occurrence_id,
    'active',
    jsonb_build_object(
      'communityEventId',r.community_event_id,
      'successionBridgeVersion','atlas_community_event_occurrence_v1'
    )
  from resolved r
  where r.occurrence_id is not null
  on conflict (organization_id,occurrence_id) do update
  set binding_state='active',
      metadata=atlas.organization_occurrence_bindings.metadata || excluded.metadata,
      updated_at=now()
  returning id,organization_id,occurrence_id
)
update atlas.community_events c
set occurrence_binding_id=b.id,
    updated_at=now()
from atlas.farms f,
     atlas.organization_occurrence_bindings b
where f.id=c.farm_id
  and b.organization_id=f.organization_id
  and b.occurrence_id = case
    when c.id='e3a78c77-ca48-496c-9c98-7e9b1d9c582d'::uuid
      then (select id from local_intel.occurrences where stable_key='elm-community-flower-day-2026-09-03')
    when c.id='ac314e2f-d39c-46e4-a1e3-dd7cd0c83ac9'::uuid
      then (select id from local_intel.occurrences where stable_key='elm-community-flower-day-2026-09-17')
    else (select id from local_intel.occurrences where stable_key='atlas-community-event-'||c.id::text)
  end;

create or replace function atlas.community_event_occurrence_overlay_service_v1(
  p_organization_id uuid,
  p_community_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_event atlas.community_events%rowtype;
  v_farm atlas.farms%rowtype;
  v_binding atlas.organization_occurrence_bindings%rowtype;
  v_occurrence local_intel.occurrences%rowtype;
begin
  select c.* into v_event
  from atlas.community_events c
  where c.id=p_community_event_id;

  if v_event.id is null then
    raise exception 'Community event not found.' using errcode='P0002';
  end if;

  select f.* into v_farm
  from atlas.farms f
  where f.id=v_event.farm_id;

  if v_farm.organization_id is distinct from p_organization_id then
    raise exception 'Community event is outside Organization.' using errcode='42501';
  end if;

  if v_event.occurrence_binding_id is null then
    raise exception 'Community event has no canonical occurrence binding.' using errcode='23514';
  end if;

  select b.* into v_binding
  from atlas.organization_occurrence_bindings b
  where b.id=v_event.occurrence_binding_id
    and b.organization_id=p_organization_id;

  if v_binding.id is null then
    raise exception 'Canonical occurrence binding is outside Organization or missing.' using errcode='42501';
  end if;

  select o.* into v_occurrence
  from local_intel.occurrences o
  where o.id=v_binding.occurrence_id;

  if v_occurrence.id is null then
    raise exception 'Canonical occurrence is missing.' using errcode='23503';
  end if;

  return jsonb_build_object(
    'contractVersion','community_event_occurrence_overlay_v1',
    'organizationId',p_organization_id,
    'communityEventId',v_event.id,
    'occurrenceBindingId',v_binding.id,
    'canonicalOccurrenceId',v_occurrence.id,
    'canonicalOccurrence',jsonb_build_object(
      'title',v_occurrence.title,
      'occurrenceType',v_occurrence.occurrence_type,
      'startAt',v_occurrence.start_at,
      'endAt',v_occurrence.end_at,
      'status',v_occurrence.status,
      'venueName',v_occurrence.venue_name,
      'entityId',v_occurrence.entity_id
    ),
    'operationalOverlay',jsonb_build_object(
      'programId',v_event.program_id,
      'eventKind',v_event.event_kind,
      'status',v_event.status,
      'visibilityScope',v_event.visibility_scope,
      'capacity',v_event.capacity,
      'metadata',v_event.metadata
    )
  );
end
$function$;

revoke all on function atlas.community_event_occurrence_overlay_service_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.community_event_occurrence_overlay_service_v1(uuid,uuid)
  to service_role;

comment on function atlas.community_event_occurrence_overlay_service_v1(uuid,uuid) is
  'Composes one canonical Shared Intelligence occurrence with the requesting Organization community-program operational overlay. atlas.community_events is not canonical event identity.';
