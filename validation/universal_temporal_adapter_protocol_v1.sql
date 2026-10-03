-- Universal Temporal Adapter Protocol v1 acceptance.
-- Read-only validation. Assumes the candidate migration has been applied.

do $$
declare
  v_missing text[];
begin
  select array_agg(required_name order by required_name)
    into v_missing
  from (
    values
      ('atlas.organization_context_temporal_overlay_adapter_v1'),
      ('atlas.canonical_occurrence_temporal_adapter_v1'),
      ('atlas.canonical_temporal_marker_temporal_adapter_v1'),
      ('atlas.organization_context_temporal_composer_service_v1'),
      ('atlas.organization_context_temporal_composer_self_api_v1')
  ) required(required_name)
  where not exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname=split_part(required_name,'.',1)
      and p.proname=split_part(required_name,'.',2)
  );

  if v_missing is not null then
    raise exception 'Temporal adapter functions missing: %',array_to_string(v_missing,', ');
  end if;
end
$$;

do $$
begin
  if has_function_privilege('anon','atlas.organization_context_temporal_overlay_adapter_v1(uuid,uuid,integer)','execute')
     or has_function_privilege('authenticated','atlas.organization_context_temporal_overlay_adapter_v1(uuid,uuid,integer)','execute') then
    raise exception 'Context overlay adapter must remain internal.';
  end if;

  if has_function_privilege('anon','atlas.canonical_occurrence_temporal_adapter_v1(uuid[],date,date,text,integer)','execute')
     or has_function_privilege('authenticated','atlas.canonical_occurrence_temporal_adapter_v1(uuid[],date,date,text,integer)','execute') then
    raise exception 'Occurrence adapter must remain internal.';
  end if;

  if has_function_privilege('anon','atlas.canonical_temporal_marker_temporal_adapter_v1(uuid[],date,date,integer)','execute')
     or has_function_privilege('authenticated','atlas.canonical_temporal_marker_temporal_adapter_v1(uuid[],date,date,integer)','execute') then
    raise exception 'Temporal marker adapter must remain internal.';
  end if;

  if has_function_privilege('anon','atlas.organization_context_temporal_composer_service_v1(uuid,uuid,date,date,text,integer)','execute')
     or has_function_privilege('authenticated','atlas.organization_context_temporal_composer_service_v1(uuid,uuid,date,date,text,integer)','execute') then
    raise exception 'Temporal composer service must remain internal.';
  end if;

  if has_function_privilege('anon','atlas.organization_context_temporal_composer_self_api_v1(uuid,uuid,date,date,text,integer)','execute')
     or not has_function_privilege('authenticated','atlas.organization_context_temporal_composer_self_api_v1(uuid,uuid,date,date,text,integer)','execute') then
    raise exception 'Authenticated Temporal composer membrane ACL is incorrect.';
  end if;
end
$$;

do $$
begin
  if to_regclass('atlas.temporal_field') is not null
     or to_regclass('atlas.temporal_fields') is not null
     or to_regclass('atlas.temporal_contributions') is not null
     or to_regclass('atlas.calendar_events') is not null then
    raise exception 'Adapter-first Temporal Field must not create persisted catch-all temporal state.';
  end if;
end
$$;

do $$
declare
  v_new jsonb;
  v_old jsonb;
  v_total integer;
  v_occurrences integer;
  v_markers integer;
  v_distinct integer;
  v_bad_context integer;
  v_bad_standing integer;
  v_old_only_count integer;
  v_bad_old_only integer;
  v_extra_in_new integer;
begin
  v_new:=atlas.organization_context_temporal_composer_service_v1(
    'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
    'f546bc48-b915-42a5-8c64-72b58b038142'::uuid,
    date '2026-10-01',
    date '2026-11-30',
    'America/Chicago',
    5000
  );

  v_old:=atlas.organization_context_temporal_projection_service_v2(
    'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
    'f546bc48-b915-42a5-8c64-72b58b038142'::uuid,
    date '2026-10-01',
    date '2026-11-30',
    'America/Chicago',
    5000
  );

  select count(*),
         count(*) filter(where c#>>'{sourceRef,kind}'='occurrence'),
         count(*) filter(where c#>>'{sourceRef,kind}'='temporal_marker'),
         count(distinct c->>'projectionKey'),
         count(*) filter(where jsonb_array_length(c->'contexts')<>1 or c#>>'{contexts,0,stableKey}'<>'community_calendar'),
         count(*) filter(where
           (c#>>'{sourceRef,kind}'='occurrence' and c->>'standing'<>'scheduled')
           or
           (c#>>'{sourceRef,kind}'='temporal_marker' and c->>'standing'<>'meaning_bearing')
         )
    into v_total,v_occurrences,v_markers,v_distinct,v_bad_context,v_bad_standing
  from jsonb_array_elements(v_new->'contributions') as x(c);

  if v_total<>26 or v_occurrences<>24 or v_markers<>2 or v_distinct<>26 then
    raise exception 'Elm adapter proof counts changed: total %, occurrences %, markers %, distinct %',
      v_total,v_occurrences,v_markers,v_distinct;
  end if;

  if v_bad_context<>0 then
    raise exception 'Elm private context did not attach exactly once to every admitted canonical contribution.';
  end if;

  if v_bad_standing<>0 then
    raise exception 'Source adapter Temporal Standing mapping is incorrect.';
  end if;

  if coalesce((v_new#>>'{coverage,partial}')::boolean,false) is not true
     or coalesce((v_new#>>'{coverage,truncated}')::boolean,false) is true
     or coalesce((v_new#>>'{coverage,unsupportedActiveMemberships}')::integer,0)<>2 then
    raise exception 'Elm coverage must report exactly two unsupported recurrence memberships without truncation.';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v_new#>'{coverage,unsupportedMemberKinds}') as x(item)
    where item->>'memberKind'='recurrence_rule'
      and (item->>'count')::integer=2
  ) then
    raise exception 'Elm coverage must identify recurrence_rule as the unsupported source family.';
  end if;

  with old_rows as (
    select
      item,
      item->>'itemType' as item_type,
      case when item->>'itemType'='temporal_marker' then 'temporal_marker' else 'occurrence' end as source_kind,
      coalesce(
        nullif(item#>>'{canonicalTemporalMarker,temporalMarkerId}',''),
        nullif(item#>>'{canonicalOccurrence,occurrenceId}','')
      )::uuid as source_id
    from jsonb_array_elements(v_old->'items') as x(item)
    where coalesce(
      nullif(item#>>'{canonicalTemporalMarker,temporalMarkerId}',''),
      nullif(item#>>'{canonicalOccurrence,occurrenceId}','')
    ) is not null
  ), old_refs as (
    select distinct source_kind,source_id from old_rows
  ), new_refs as (
    select distinct c#>>'{sourceRef,kind}' as source_kind,(c#>>'{sourceRef,id}')::uuid as source_id
    from jsonb_array_elements(v_new->'contributions') as x(c)
  ), old_only as (
    select o.* from old_refs o left join new_refs n using(source_kind,source_id) where n.source_id is null
  )
  select count(*) into v_old_only_count from old_only;

  if v_old_only_count<>1 then
    raise exception 'Expected exactly one old-only recurrence-routed referent, found %',v_old_only_count;
  end if;

  with old_rows as (
    select
      item,
      item->>'itemType' as item_type,
      case when item->>'itemType'='temporal_marker' then 'temporal_marker' else 'occurrence' end as source_kind,
      coalesce(
        nullif(item#>>'{canonicalTemporalMarker,temporalMarkerId}',''),
        nullif(item#>>'{canonicalOccurrence,occurrenceId}','')
      )::uuid as source_id
    from jsonb_array_elements(v_old->'items') as x(item)
    where coalesce(
      nullif(item#>>'{canonicalTemporalMarker,temporalMarkerId}',''),
      nullif(item#>>'{canonicalOccurrence,occurrenceId}','')
    ) is not null
  ), new_refs as (
    select distinct c#>>'{sourceRef,kind}' as source_kind,(c#>>'{sourceRef,id}')::uuid as source_id
    from jsonb_array_elements(v_new->'contributions') as x(c)
  ), old_only_rows as (
    select r.* from old_rows r left join new_refs n using(source_kind,source_id) where n.source_id is null
  )
  select count(*) into v_bad_old_only
  from old_only_rows r
  where not (
    r.item_type='recurrence_instance'
    and r.item#>>'{recurrenceInstance,scheduleState}'='skipped'
    and r.item#>>'{recurrenceInstance,realizationState}'='cancelled'
    and not exists (
      select 1
      from atlas.organization_occurrence_bindings ob
      join atlas.organization_purpose_context_memberships m
        on m.organization_id=ob.organization_id
       and m.context_id='f546bc48-b915-42a5-8c64-72b58b038142'::uuid
       and m.member_kind='occurrence_binding'
       and m.occurrence_binding_id=ob.id
       and m.membership_state='active'
      where ob.organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
        and ob.occurrence_id=r.source_id
        and ob.binding_state='active'
    )
  );

  if v_bad_old_only<>0 then
    raise exception 'Old-only temporal referent is not explained by unsupported cancelled recurrence-only routing.';
  end if;

  with old_refs as (
    select distinct
      case when item->>'itemType'='temporal_marker' then 'temporal_marker' else 'occurrence' end as source_kind,
      coalesce(
        nullif(item#>>'{canonicalTemporalMarker,temporalMarkerId}',''),
        nullif(item#>>'{canonicalOccurrence,occurrenceId}','')
      )::uuid as source_id
    from jsonb_array_elements(v_old->'items') as x(item)
    where coalesce(
      nullif(item#>>'{canonicalTemporalMarker,temporalMarkerId}',''),
      nullif(item#>>'{canonicalOccurrence,occurrenceId}','')
    ) is not null
  ), new_refs as (
    select distinct c#>>'{sourceRef,kind}' as source_kind,(c#>>'{sourceRef,id}')::uuid as source_id
    from jsonb_array_elements(v_new->'contributions') as x(c)
  )
  select count(*) into v_extra_in_new
  from (select * from new_refs except select * from old_refs) d;

  if v_extra_in_new<>0 then
    raise exception 'Adapter composer introduced canonical referents not present in the established Elm projection: %',v_extra_in_new;
  end if;
end
$$;

select jsonb_build_object(
  'contractVersion','universal_temporal_adapter_protocol_acceptance_v1',
  'status','pass',
  'persistedTemporalField',false,
  'canonicalCalendarEventTable',false,
  'elmProof',jsonb_build_object(
    'context','community_calendar',
    'window','2026-10-01/2026-11-30',
    'directlyAdmittedCanonicalOccurrences',24,
    'canonicalTemporalMarkers',2,
    'explainedRecurrenceOnlyCancelledOccurrences',1,
    'unsupportedRecurrenceMemberships',2
  )
) as acceptance;
