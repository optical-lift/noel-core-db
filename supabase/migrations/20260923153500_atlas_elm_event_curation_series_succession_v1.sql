-- Atlas Elm-local event curation / series succession v1
-- Retire Elm-specific Shared Intelligence curation tables as authorities.
-- Curation becomes Organization-private purpose-context membership payload.
-- Event series become ordinary Organization-private purpose contexts with
-- explicit canonical occurrence memberships. Shared Intelligence remains the
-- sole occurrence identity authority.

do $$
declare
  v_org uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_calendar_context uuid;
  v_curation local_intel.elm_local_event_curations_v1%rowtype;
  v_rule local_intel.elm_local_event_series_rules_v1%rowtype;
  v_occurrence record;
  v_binding uuid;
  v_series_context uuid;
  v_existing_payload jsonb;
  v_existing_provenance jsonb;
  v_series_stable_key text;
begin
  select c.id
  into v_calendar_context
  from atlas.organization_purpose_contexts c
  where c.organization_id=v_org
    and c.stable_key='community_calendar'
    and c.context_state='active';

  if v_calendar_context is null then
    raise exception 'Elm Organization community_calendar context is missing.'
      using errcode='P0002';
  end if;

  -- Move legacy featured-event curation into the Organization-private
  -- community-calendar membership. Canonical occurrence identity is reused.
  for v_curation in
    select *
    from local_intel.elm_local_event_curations_v1
    order by source_system,source_stable_key
  loop
    select o.id
    into v_occurrence
    from local_intel.occurrences o
    where v_curation.source_system='local_intel'
      and o.stable_key=v_curation.source_stable_key;

    if v_occurrence.id is null then
      raise exception 'Legacy Elm curation occurrence % could not be resolved canonically.',
        v_curation.source_stable_key
        using errcode='P0002';
    end if;

    v_binding := (
      atlas.bind_canonical_occurrence_service_v1(
        v_org,
        v_occurrence.id,
        jsonb_build_object(
          'successionSource','local_intel.elm_local_event_curations_v1',
          'legacySourceStableKey',v_curation.source_stable_key
        ),
        null
      )->>'bindingId'
    )::uuid;

    select coalesce(m.payload,'{}'::jsonb),coalesce(m.provenance,'{}'::jsonb)
    into v_existing_payload,v_existing_provenance
    from atlas.organization_purpose_context_memberships m
    where m.organization_id=v_org
      and m.context_id=v_calendar_context
      and m.occurrence_binding_id=v_binding;

    perform atlas.add_occurrence_to_purpose_context_service_v1(
      v_org,
      v_calendar_context,
      v_binding,
      array['calendar_entry','featured'],
      coalesce(v_existing_payload,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
        'included',true,
        'featured',v_curation.featured,
        'featureRank',v_curation.feature_rank,
        'featureNote',v_curation.feature_note,
        'activeFrom',v_curation.active_from,
        'activeThrough',v_curation.active_through,
        'curationAuthority','atlas.organization_purpose_context_memberships'
      )),
      coalesce(v_existing_provenance,'{}'::jsonb) || jsonb_build_object(
        'successionBasis','legacy_elm_local_event_curation',
        'legacySourceSystem',v_curation.source_system,
        'legacySourceStableKey',v_curation.source_stable_key,
        'legacyUpdatedAt',v_curation.updated_at
      ),
      null
    );
  end loop;

  -- Each old display-series rule becomes a generic Organization-owned
  -- occurrence_series context. The legacy regex is used only once here to
  -- recover existing memberships; future membership is explicit.
  for v_rule in
    select *
    from local_intel.elm_local_event_series_rules_v1
    where active
    order by priority,series_key
  loop
    v_series_stable_key := case v_rule.series_key
      when 'elm-arise' then 'arise'
      when 'elm-family-ultimate' then 'family_ultimate'
      when 'elm-community-flower-mornings' then 'community_flower_mornings'
      else replace(v_rule.series_key,'-','_')
    end;

    v_series_context := (
      atlas.create_purpose_context_service_v1(
        v_org,
        v_series_stable_key,
        'occurrence_series',
        v_rule.series_title,
        v_rule.series_summary,
        jsonb_build_object(
          'priority',v_rule.priority,
          'seriesAuthority','atlas.organization_purpose_contexts',
          'legacyRule',jsonb_build_object(
            'sourceTable','local_intel.elm_local_event_series_rules_v1',
            'sourceSystem',v_rule.source_system,
            'stableKeyRegex',v_rule.stable_key_regex,
            'legacySeriesKey',v_rule.series_key,
            'legacyUpdatedAt',v_rule.updated_at
          )
        ),
        null
      )->>'contextId'
    )::uuid;

    if v_rule.source_system='local_intel' then
      for v_occurrence in
        select o.id,o.stable_key
        from local_intel.occurrences o
        where o.stable_key ~ v_rule.stable_key_regex
        order by o.start_at,o.id
      loop
        v_binding := (
          atlas.bind_canonical_occurrence_service_v1(
            v_org,
            v_occurrence.id,
            jsonb_build_object(
              'successionSource','local_intel.elm_local_event_series_rules_v1',
              'seriesContextId',v_series_context
            ),
            null
          )->>'bindingId'
        )::uuid;

        perform atlas.add_occurrence_to_purpose_context_service_v1(
          v_org,
          v_series_context,
          v_binding,
          array['series_occurrence'],
          jsonb_build_object(
            'seriesMembership','explicit',
            'seriesPriority',v_rule.priority,
            'seriesAuthority','atlas.organization_purpose_context_memberships'
          ),
          jsonb_build_object(
            'successionBasis','legacy_elm_local_event_series_rule',
            'legacySourceSystem',v_rule.source_system,
            'legacyStableKeyRegex',v_rule.stable_key_regex,
            'legacySeriesKey',v_rule.series_key
          ),
          null
        );
      end loop;

    elsif v_rule.source_system='atlas' then
      for v_occurrence in
        select distinct
          b.occurrence_id as id,
          ce.stable_key
        from atlas.community_events ce
        join atlas.organization_occurrence_bindings b
          on b.id=ce.occurrence_binding_id
         and b.organization_id=v_org
        where ce.stable_key ~ v_rule.stable_key_regex
        order by ce.stable_key,b.occurrence_id
      loop
        v_binding := (
          atlas.bind_canonical_occurrence_service_v1(
            v_org,
            v_occurrence.id,
            jsonb_build_object(
              'successionSource','local_intel.elm_local_event_series_rules_v1',
              'seriesContextId',v_series_context
            ),
            null
          )->>'bindingId'
        )::uuid;

        perform atlas.add_occurrence_to_purpose_context_service_v1(
          v_org,
          v_series_context,
          v_binding,
          array['series_occurrence'],
          jsonb_build_object(
            'seriesMembership','explicit',
            'seriesPriority',v_rule.priority,
            'seriesAuthority','atlas.organization_purpose_context_memberships'
          ),
          jsonb_build_object(
            'successionBasis','legacy_elm_local_event_series_rule',
            'legacySourceSystem',v_rule.source_system,
            'legacyStableKeyRegex',v_rule.stable_key_regex,
            'legacySeriesKey',v_rule.series_key
          ),
          null
        );
      end loop;
    else
      raise exception 'Unsupported legacy Elm series source system: %',v_rule.source_system
        using errcode='22023';
    end if;
  end loop;
end
$$;

create or replace function local_intel.reject_legacy_elm_event_projection_config_write_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  raise exception
    'Legacy Elm-specific event projection configuration is read-only. Use Atlas Organization purpose contexts and memberships.'
    using errcode='0A000';
end
$function$;

drop trigger if exists reject_legacy_elm_event_curations_write_v1
  on local_intel.elm_local_event_curations_v1;

create trigger reject_legacy_elm_event_curations_write_v1
before insert or update or delete
on local_intel.elm_local_event_curations_v1
for each row
execute function local_intel.reject_legacy_elm_event_projection_config_write_v1();

drop trigger if exists reject_legacy_elm_event_series_rules_write_v1
  on local_intel.elm_local_event_series_rules_v1;

create trigger reject_legacy_elm_event_series_rules_write_v1
before insert or update or delete
on local_intel.elm_local_event_series_rules_v1
for each row
execute function local_intel.reject_legacy_elm_event_projection_config_write_v1();

comment on table local_intel.elm_local_event_curations_v1 is
  'Legacy read-only compatibility table. Elm calendar curation is Organization-private Atlas purpose-context membership payload over canonical local_intel occurrences.';
comment on table local_intel.elm_local_event_series_rules_v1 is
  'Legacy read-only compatibility table. Event series are Organization-private Atlas occurrence_series purpose contexts with explicit canonical occurrence memberships; legacy regex rules are not an authority for new data.';
comment on function local_intel.reject_legacy_elm_event_projection_config_write_v1() is
  'Prevents new Elm-specific projection state from being written into Shared Intelligence after Atlas Organization-purpose succession.';
