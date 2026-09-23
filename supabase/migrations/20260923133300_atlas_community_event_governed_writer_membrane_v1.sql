-- Atlas community-event governed writer membrane v1
-- Repair the two remaining legacy direct writers by canonicalizing their
-- inserts before atlas.community_events is allowed to persist an unbound row.

create or replace function atlas.enforce_community_event_occurrence_binding_org_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_farm atlas.farms%rowtype;
  v_binding atlas.organization_occurrence_bindings%rowtype;
  v_occurrence_id uuid;
  v_occurrence_key text;
  v_elm_entity local_intel.entities%rowtype;
  v_is_system_fixture boolean:=false;
begin
  select * into v_farm
  from atlas.farms f
  where f.id=new.farm_id;

  if v_farm.id is null then
    raise exception 'Community event farm is missing.' using errcode='23503';
  end if;

  v_is_system_fixture :=
    lower(coalesce(v_farm.metadata->>'system_fixture','false'))='true'
    and lower(coalesce(new.metadata->>'system_fixture','false'))='true';

  if new.occurrence_binding_id is null then

    -- Legacy writer 1:
    -- atlas.record_network_outreach_result_v1
    -- It is an Elm-specific booking flow. Establish canonical occurrence
    -- first, then return the Organization occurrence binding to the row.
    if coalesce(new.metadata->>'source','')='network_outreach' then
      if v_farm.stable_key <> 'elm_farm' then
        raise exception 'Network-outreach community events require an explicit canonical occurrence binding outside Elm Farm.'
          using errcode='23514';
      end if;

      select * into v_elm_entity
      from local_intel.entities e
      where e.stable_key='elm-farm'
        and e.status='active';

      if v_elm_entity.id is null then
        raise exception 'Canonical Elm Farm Shared Intelligence entity is unavailable.'
          using errcode='P0002';
      end if;

      v_occurrence_key :=
        'atlas-network-outreach-' ||
        coalesce(nullif(new.metadata->>'source_task_id',''),new.id::text);

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
      ) values (
        v_occurrence_key,
        v_elm_entity.id,
        new.title,
        new.event_kind,
        (new.event_date + new.start_local_time) at time zone new.timezone_name,
        (new.event_date + new.end_local_time) at time zone new.timezone_name,
        v_elm_entity.name,
        v_elm_entity.address_line1,
        v_elm_entity.city,
        v_elm_entity.state,
        v_elm_entity.postal_code,
        new.status,
        jsonb_build_object(
          'atlasWriterAuthority','network_outreach',
          'atlasCommunityEventId',new.id,
          'atlasCommunityEventStableKey',new.stable_key,
          'sourceTaskId',new.metadata->>'source_task_id',
          'canonicalizedBy','community_event_writer_membrane_v1'
        )
      )
      on conflict (stable_key) do update
      set entity_id=excluded.entity_id,
          title=excluded.title,
          occurrence_type=excluded.occurrence_type,
          start_at=excluded.start_at,
          end_at=excluded.end_at,
          venue_name=excluded.venue_name,
          address_line1=excluded.address_line1,
          city=excluded.city,
          state=excluded.state,
          postal_code=excluded.postal_code,
          status=excluded.status,
          metadata=local_intel.occurrences.metadata || excluded.metadata,
          updated_at=now()
      returning id into v_occurrence_id;

      insert into atlas.organization_occurrence_bindings(
        organization_id,occurrence_id,binding_state,metadata
      ) values (
        v_farm.organization_id,
        v_occurrence_id,
        'active',
        jsonb_build_object(
          'writerAuthority','network_outreach',
          'communityEventId',new.id,
          'canonicalizedBy','community_event_writer_membrane_v1'
        )
      )
      on conflict (organization_id,occurrence_id) do update
      set binding_state='active',
          metadata=atlas.organization_occurrence_bindings.metadata || excluded.metadata,
          updated_at=now()
      returning id into new.occurrence_binding_id;

    -- Legacy writer 2:
    -- atlas.run_reference_company_capability_hold_and_event_lifetime_v1
    -- This is rollback-only system-fixture reality. Give it an ephemeral
    -- canonical occurrence/binding inside the fixture transaction so it obeys
    -- the same contract without manufacturing durable external-world truth.
    elsif v_is_system_fixture then
      v_occurrence_key := 'atlas-system-fixture-community-event-' || new.id::text;

      insert into local_intel.occurrences(
        stable_key,
        entity_id,
        title,
        occurrence_type,
        start_at,
        end_at,
        venue_name,
        status,
        metadata
      ) values (
        v_occurrence_key,
        null,
        new.title,
        new.event_kind,
        (new.event_date + new.start_local_time) at time zone new.timezone_name,
        (new.event_date + new.end_local_time) at time zone new.timezone_name,
        v_farm.name,
        new.status,
        jsonb_build_object(
          'systemFixture',true,
          'atlasWriterAuthority','system_fixture',
          'atlasCommunityEventId',new.id,
          'atlasCommunityEventStableKey',new.stable_key,
          'canonicalizedBy','community_event_writer_membrane_v1'
        )
      )
      on conflict (stable_key) do update
      set title=excluded.title,
          occurrence_type=excluded.occurrence_type,
          start_at=excluded.start_at,
          end_at=excluded.end_at,
          venue_name=excluded.venue_name,
          status=excluded.status,
          metadata=local_intel.occurrences.metadata || excluded.metadata,
          updated_at=now()
      returning id into v_occurrence_id;

      insert into atlas.organization_occurrence_bindings(
        organization_id,occurrence_id,binding_state,metadata
      ) values (
        v_farm.organization_id,
        v_occurrence_id,
        'active',
        jsonb_build_object(
          'systemFixture',true,
          'writerAuthority','system_fixture',
          'communityEventId',new.id,
          'canonicalizedBy','community_event_writer_membrane_v1'
        )
      )
      on conflict (organization_id,occurrence_id) do update
      set binding_state='active',
          metadata=atlas.organization_occurrence_bindings.metadata || excluded.metadata,
          updated_at=now()
      returning id into new.occurrence_binding_id;

    else
      raise exception
        'Canonical occurrence binding is required before a community event may be written.'
        using errcode='23514';
    end if;
  end if;

  select * into v_binding
  from atlas.organization_occurrence_bindings b
  where b.id=new.occurrence_binding_id;

  if v_binding.id is null then
    raise exception 'Occurrence binding is missing.' using errcode='23503';
  end if;

  if v_binding.organization_id <> v_farm.organization_id then
    raise exception 'Community event occurrence binding belongs to another Organization.'
      using errcode='23514';
  end if;

  -- Keep the two compatibility writers coherent with the canonical occurrence
  -- when they reschedule/cancel/update the operational row.
  if tg_op='UPDATE' then
    update local_intel.occurrences o
    set title=new.title,
        start_at=(new.event_date + new.start_local_time) at time zone new.timezone_name,
        end_at=(new.event_date + new.end_local_time) at time zone new.timezone_name,
        status=new.status,
        metadata=o.metadata || jsonb_build_object(
          'lastOperationalSyncAt',now(),
          'atlasCommunityEventId',new.id
        ),
        updated_at=now()
    where o.id=v_binding.occurrence_id
      and o.metadata->>'atlasWriterAuthority' in ('network_outreach','system_fixture');
  end if;

  return new;
end
$function$;

drop trigger if exists enforce_community_event_occurrence_binding_org_v1
  on atlas.community_events;

create trigger enforce_community_event_occurrence_binding_org_v1
before insert or update
on atlas.community_events
for each row
execute function atlas.enforce_community_event_occurrence_binding_org_v1();

do $$
begin
  if exists(
    select 1
    from atlas.community_events
    where occurrence_binding_id is null
  ) then
    raise exception 'Cannot enforce canonical occurrence binding: unbound community events remain.'
      using errcode='23514';
  end if;
end
$$;

alter table atlas.community_events
  alter column occurrence_binding_id set not null;

comment on function atlas.enforce_community_event_occurrence_binding_org_v1() is
  'Governed write membrane for atlas.community_events. Unbound writes are rejected except the two known legacy writers, which are canonicalized first: Elm network-outreach bookings and rollback-only Reference Company fixture events. Organization consistency is enforced for every row.';
