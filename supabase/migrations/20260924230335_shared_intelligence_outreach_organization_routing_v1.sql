-- Route the Organization-private subset of the retired mixed-custody carrier.

do $block$
declare
  v_organization_id uuid;
  v_entity_id uuid;
  v_subject_id uuid;
  v_entity_city text;
begin
  select id into v_organization_id
  from atlas.organizations
  where stable_key='elm_farm' and status='active';

  select id,city into v_entity_id,v_entity_city
  from local_intel.entities
  where stable_key='marshfield-community-theatre'
    and name='Marshfield Community Theatre'
    and status='active'
    and verification_state='official_verified';

  select i.subject_id into v_subject_id
  from atlas.identity_subject_external_identifiers i
  join atlas.identity_subject_projections p
    on p.subject_id=i.subject_id
   and p.organization_id=i.organization_id
  where i.organization_id=v_organization_id
    and i.identifier_type='legacy_relationship_key'
    and i.identifier_value='marshfield_community_theatre'
    and i.is_current
    and p.display_name='Marshfield Community Theatre'
    and exists (
      select 1
      from atlas.external_relationships r
      where r.organization_id=v_organization_id
        and r.subject_id=i.subject_id
        and lower(coalesce(r.metadata->>'city',''))=lower(coalesce(v_entity_city,''))
    )
  order by i.created_at,i.id
  limit 1;

  if v_organization_id is null or v_entity_id is null or v_subject_id is null then
    raise exception 'Marshfield Community Theatre legacy identity proof did not resolve; refusing convenience binding.';
  end if;

  if exists (
    select 1
    from atlas.identity_subject_external_identifiers i
    where i.organization_id=v_organization_id
      and i.provider_key='local_intel'
      and i.identifier_type='entity_id'
      and i.identifier_normalized=v_entity_id::text
      and i.is_current
      and i.subject_id<>v_subject_id
  ) then
    raise exception 'Canonical Marshfield Community Theatre entity is already bound to another Elm subject.';
  end if;

  if not exists (
    select 1
    from atlas.identity_subject_external_identifiers i
    where i.organization_id=v_organization_id
      and i.subject_id=v_subject_id
      and i.provider_key='local_intel'
      and i.identifier_type='entity_id'
      and i.identifier_normalized=v_entity_id::text
      and i.is_current
  ) then
    insert into atlas.identity_subject_external_identifiers(
      organization_id,subject_id,provider_key,identifier_type,
      identifier_value,identifier_normalized,is_current,priority,metadata
    ) values (
      v_organization_id,v_subject_id,'local_intel','entity_id',
      v_entity_id::text,v_entity_id::text,true,1,
      jsonb_build_object(
        'migration','shared_intelligence_outreach_organization_routing_v1',
        'adjudication','legacy_exact_name_and_location_to_official_canonical_entity',
        'canonicalStableKey','marshfield-community-theatre',
        'legacyRelationshipKey','marshfield_community_theatre'
      )
    );
  end if;
end
$block$;

do $block$
declare
  v_organization_id uuid;
  v_row record;
  v_result jsonb;
  v_context_key text;
  v_context_kind text;
  v_context_title text;
  v_context_description text;
  v_role_keys text[];
begin
  select id into v_organization_id
  from atlas.organizations
  where stable_key='elm_farm' and status='active';

  if v_organization_id is null then
    raise exception 'Elm Farm organization not found; cannot migrate Organization-private concepts.';
  end if;

  for v_row in
    select *
    from local_intel.legacy_outreach_targets_archive_v1
    where target_kind in (
      'september_elm_host',
      'september_internal_audience_host',
      'october_market_partner',
      'community_nonprofit_partner',
      'provider_referral_source',
      'september_distribution_partner'
    )
    order by id
  loop
    case v_row.target_kind
      when 'september_elm_host' then
        v_context_key := 'event_host_candidates';
        v_context_kind := 'outreach_set';
        v_context_title := 'Elm Event Host Candidates';
        v_context_description := 'Private Elm candidates for hosting or producing an event at Elm. Candidate status is Elm intent, not canonical entity truth.';
        v_role_keys := array['host_candidate'];
      when 'september_internal_audience_host' then
        v_context_key := 'audience_host_candidates';
        v_context_kind := 'outreach_set';
        v_context_title := 'Elm Audience Host Candidates';
        v_context_description := 'Private Elm candidates whose existing community or audience could support an Elm gathering. Candidate status is Elm intent, not canonical entity truth.';
        v_role_keys := array['audience_host_candidate'];
      when 'october_market_partner' then
        v_context_key := 'holiday_market_partners_2026';
        v_context_kind := 'campaign';
        v_context_title := 'Elm 2026 Holiday Market Partner Candidates';
        v_context_description := 'Private Elm holiday-market partnership candidates for the 2026 season.';
        v_role_keys := array['market_partner_candidate'];
      when 'community_nonprofit_partner' then
        v_context_key := 'community_partner_candidates';
        v_context_kind := 'outreach_set';
        v_context_title := 'Elm Community Partner Candidates';
        v_context_description := 'Private Elm community or mission partnership candidates.';
        v_role_keys := array['community_partner_candidate'];
      when 'provider_referral_source' then
        v_context_key := 'provider_referral_sources';
        v_context_kind := 'outreach_set';
        v_context_title := 'Elm Provider Referral Sources';
        v_context_description := 'Private Elm candidates who may refer existing providers, instructors, or partners.';
        v_role_keys := array['referral_source_candidate'];
      when 'september_distribution_partner' then
        v_context_key := 'distribution_partner_candidates';
        v_context_kind := 'outreach_set';
        v_context_title := 'Elm Distribution Partner Candidates';
        v_context_description := 'Private Elm candidates for audience, distribution, or visitor-flow collaboration.';
        v_role_keys := array['distribution_partner_candidate'];
      else
        raise exception 'Unexpected Organization-private legacy target kind %',v_row.target_kind;
    end case;

    v_result := atlas.record_entity_purpose_concept_service_v1(
      p_organization_id=>v_organization_id,
      p_entity_id=>v_row.entity_id,
      p_context_stable_key=>v_context_key,
      p_context_kind=>v_context_kind,
      p_context_title=>v_context_title,
      p_context_description=>v_context_description,
      p_concept_role_keys=>v_role_keys,
      p_payload=>jsonb_strip_nulls(jsonb_build_object(
        'conceptKind',v_row.target_kind,
        'legacyStatus',v_row.status,
        'priority',v_row.priority,
        'rationale',v_row.rationale,
        'proposedFormat',v_row.proposed_format,
        'proposedWindow',case when v_row.proposed_window is null then null else v_row.proposed_window::text end,
        'notes',v_row.notes,
        'preferredPersonEntityId',v_row.person_entity_id,
        'preferredContactPointId',v_row.contact_point_id,
        'legacyMetadata',v_row.metadata
      )),
      p_provenance=>jsonb_strip_nulls(jsonb_build_object(
        'sourceSchema','local_intel',
        'sourceTable','legacy_outreach_targets_archive_v1',
        'legacyOutreachTargetId',v_row.id,
        'sourceId',v_row.source_id,
        'migration','shared_intelligence_outreach_organization_routing_v1'
      ))
    );

    insert into atlas.legacy_local_intel_outreach_target_mappings(
      legacy_outreach_target_id,disposition,organization_id,external_relationship_id,
      purpose_context_id,purpose_context_membership_id,metadata
    ) values (
      v_row.id,
      'organization_purpose_context',
      v_organization_id,
      nullif(v_result->>'externalRelationshipId','')::uuid,
      nullif(v_result->>'contextId','')::uuid,
      nullif(v_result->>'membershipId','')::uuid,
      jsonb_build_object(
        'legacyTargetKind',v_row.target_kind,
        'migration','shared_intelligence_outreach_organization_routing_v1'
      )
    )
    on conflict (legacy_outreach_target_id) do nothing;
  end loop;
end
$block$;

do $block$
declare
  v_archive_count integer;
  v_mapping_count integer;
begin
  select count(*) into v_archive_count
  from local_intel.legacy_outreach_targets_archive_v1;

  select count(*) into v_mapping_count
  from atlas.legacy_local_intel_outreach_target_mappings;

  if v_archive_count<>v_mapping_count then
    raise exception 'Outreach custody routing incomplete: archive %, mapped %.',
      v_archive_count,v_mapping_count;
  end if;
end
$block$;
