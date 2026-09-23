-- Atlas legacy campaign writer compatibility membrane v1
-- Any write to an Organization-owned legacy local_intel campaign contact now
-- writes the Organization-private purpose membership / relationship interaction
-- in the same transaction. The local_intel row remains a compatibility mirror,
-- not the Ledger authority.

create or replace function atlas.sync_legacy_campaign_contact_to_organization_context_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_campaign_map atlas.legacy_local_intel_campaign_context_mappings%rowtype;
  v_contact_map atlas.legacy_local_intel_campaign_contact_membership_mappings%rowtype;
  v_membership atlas.organization_purpose_context_memberships%rowtype;
  v_attach jsonb;
  v_relationship_id uuid;
  v_membership_id uuid;
  v_interaction jsonb;
  v_interaction_id uuid;
  v_channel text;
  v_outcome text;
  v_contact_label text;
  v_note text;
  v_activity_key text;
  v_existing_interaction_id uuid;
  v_task_id uuid;
begin
  select *
  into v_campaign_map
  from atlas.legacy_local_intel_campaign_context_mappings m
  where m.local_intel_campaign_id=new.campaign_id;

  -- Shared Intelligence campaigns with no Organization successor remain
  -- untouched by this compatibility membrane.
  if v_campaign_map.local_intel_campaign_id is null then
    return new;
  end if;

  if new.entity_id is null then
    raise exception
      'Organization-owned legacy campaign contact requires a canonical Shared Intelligence entity.'
      using errcode='23514';
  end if;

  select *
  into v_contact_map
  from atlas.legacy_local_intel_campaign_contact_membership_mappings m
  where m.local_intel_campaign_contact_id=new.id;

  if v_contact_map.local_intel_campaign_contact_id is null then
    v_attach := atlas.attach_shared_directory_entity_service_v1(
      v_campaign_map.organization_id,
      new.entity_id,
      'contact',
      null
    );

    v_relationship_id := nullif(v_attach->>'externalRelationshipId','')::uuid;

    if v_relationship_id is null then
      raise exception
        'Canonical entity requires identity review before it can enter the Organization campaign.'
        using errcode='23514';
    end if;

    v_membership_id := (
      atlas.add_external_relationship_to_purpose_context_service_v1(
        v_campaign_map.organization_id,
        v_campaign_map.purpose_context_id,
        v_relationship_id,
        array['outreach_target'],
        jsonb_strip_nulls(jsonb_build_object(
          'campaignState',new.state,
          'lastActionAt',new.last_action_at,
          'selectedContactPointId',new.contact_point_id,
          'campaignTargetId',new.campaign_target_id,
          'campaignAssetId',new.campaign_asset_id,
          'legacyCampaignContactId',new.id,
          'legacyMetadata',coalesce(new.metadata,'{}'::jsonb),
          'operationalAuthority','atlas.organization_purpose_context_memberships'
        )),
        jsonb_build_object(
          'basis','legacy_local_intel_campaign_writer_membrane_v1',
          'canonicalEntityId',new.entity_id,
          'legacyCampaignId',new.campaign_id,
          'legacyCampaignContactId',new.id
        ),
        null
      )->>'membershipId'
    )::uuid;

    insert into atlas.legacy_local_intel_campaign_contact_membership_mappings(
      organization_id,
      local_intel_campaign_contact_id,
      purpose_context_membership_id
    ) values (
      v_campaign_map.organization_id,
      new.id,
      v_membership_id
    )
    on conflict (local_intel_campaign_contact_id) do update
    set organization_id=excluded.organization_id,
        purpose_context_membership_id=excluded.purpose_context_membership_id;

    select *
    into v_membership
    from atlas.organization_purpose_context_memberships m
    where m.id=v_membership_id;
  else
    select *
    into v_membership
    from atlas.organization_purpose_context_memberships m
    where m.id=v_contact_map.purpose_context_membership_id
      and m.organization_id=v_campaign_map.organization_id
      and m.context_id=v_campaign_map.purpose_context_id
      and m.member_kind='external_relationship';

    if v_membership.id is null then
      raise exception
        'Legacy campaign contact mapping does not resolve to the Organization campaign membership.'
        using errcode='23514';
    end if;

    update atlas.organization_purpose_context_memberships m
    set membership_state='active',
        payload=coalesce(m.payload,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'campaignState',new.state,
          'lastActionAt',new.last_action_at,
          'selectedContactPointId',new.contact_point_id,
          'campaignTargetId',new.campaign_target_id,
          'campaignAssetId',new.campaign_asset_id,
          'legacyCampaignContactId',new.id,
          'lastContactResult',coalesce(
            new.metadata->>'last_contact_result',
            new.metadata#>>'{last_phone_outreach_result,contact_result}'
          ),
          'lastReachedName',coalesce(
            new.metadata->>'last_reached_name',
            new.metadata#>>'{last_phone_outreach_result,reached_name}'
          ),
          'lastContactNotes',coalesce(
            new.metadata->>'last_contact_notes',
            new.metadata#>>'{last_phone_outreach_result,notes}'
          ),
          'operationalAuthority','atlas.organization_purpose_context_memberships',
          'legacyCompatibilityMirror','local_intel.campaign_contacts'
        )),
        updated_at=now()
    where m.id=v_membership.id
    returning * into v_membership;
  end if;

  -- An insert establishes membership but is not itself a completed outreach
  -- interaction. Updates that change outreach state/action become durable
  -- Organization-private relationship interactions.
  if tg_op='UPDATE'
     and (
       new.state is distinct from old.state
       or new.last_action_at is distinct from old.last_action_at
       or new.metadata->>'last_contact_result' is distinct from old.metadata->>'last_contact_result'
       or new.metadata->'last_phone_outreach_result' is distinct from old.metadata->'last_phone_outreach_result'
     ) then

    select cp.contact_type
    into v_channel
    from local_intel.contact_points cp
    where cp.id=new.contact_point_id;

    if v_channel is null then
      select c.channel
      into v_channel
      from local_intel.campaigns c
      where c.id=new.campaign_id;
    end if;

    v_outcome := coalesce(
      nullif(new.metadata->>'last_contact_result',''),
      nullif(new.metadata#>>'{last_phone_outreach_result,contact_result}',''),
      new.state
    );

    v_contact_label := coalesce(
      nullif(new.metadata->>'last_reached_name',''),
      nullif(new.metadata#>>'{last_phone_outreach_result,reached_name}','')
    );

    v_note := coalesce(
      nullif(new.metadata->>'last_contact_notes',''),
      nullif(new.metadata#>>'{last_phone_outreach_result,notes}','')
    );

    v_activity_key := nullif(new.metadata->>'last_phone_outreach_idempotency_key','');

    if v_activity_key is not null then
      select i.id
      into v_existing_interaction_id
      from atlas.external_relationship_interactions i
      where i.organization_id=v_campaign_map.organization_id
        and i.external_relationship_id=v_membership.external_relationship_id
        and i.metadata->>'campaignContextMembershipId'=v_membership.id::text
        and i.metadata->>'campaignActivityKey'=v_activity_key
      order by i.created_at desc
      limit 1;
    end if;

    if v_existing_interaction_id is null then
      v_interaction := atlas.record_shared_directory_interaction_service_v1(
        v_campaign_map.organization_id,
        v_membership.external_relationship_id,
        'campaign_outreach',
        coalesce(new.last_action_at,now()),
        v_channel,
        v_outcome,
        v_contact_label,
        null,
        v_note,
        jsonb_strip_nulls(jsonb_build_object(
          'campaignContextId',v_campaign_map.purpose_context_id,
          'campaignContextMembershipId',v_membership.id,
          'legacyCampaignId',new.campaign_id,
          'legacyCampaignContactId',new.id,
          'campaignActivityKey',v_activity_key,
          'canonicalEntityId',new.entity_id,
          'compatibilityBridge','legacy_campaign_writer_membrane_v1'
        ))
      );

      v_interaction_id := nullif(v_interaction->>'interactionId','')::uuid;
    else
      v_interaction_id := v_existing_interaction_id;
    end if;

    update atlas.organization_purpose_context_memberships m
    set payload=coalesce(m.payload,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'campaignState',new.state,
          'lastActionAt',coalesce(new.last_action_at,now()),
          'lastContactResult',v_outcome,
          'lastReachedName',v_contact_label,
          'lastContactNotes',v_note,
          'lastInteractionId',v_interaction_id,
          'operationalAuthority','atlas.organization_purpose_context_memberships',
          'interactionAuthority','atlas.external_relationship_interactions',
          'legacyCompatibilityMirror','local_intel.campaign_contacts'
        )),
        updated_at=now()
    where m.id=v_membership.id;

    -- Repair the old phone-outreach task metadata so it no longer claims the
    -- Shared Intelligence compatibility row is the result authority.
    if coalesce(new.metadata->>'last_atlas_task_id','') ~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_task_id := (new.metadata->>'last_atlas_task_id')::uuid;

      update atlas.tasks t
      set metadata=coalesce(t.metadata,'{}'::jsonb) || jsonb_build_object(
            'result_storage','atlas.organization_purpose_context_memberships+atlas.external_relationship_interactions',
            'legacy_result_mirror','local_intel.campaign_contacts',
            'campaign_context_membership_id',v_membership.id,
            'external_relationship_id',v_membership.external_relationship_id,
            'external_relationship_interaction_id',v_interaction_id
          ),
          updated_at=now()
      where t.id=v_task_id;
    end if;
  end if;

  return new;
end
$function$;

drop trigger if exists sync_legacy_campaign_contact_to_organization_context_v1
  on local_intel.campaign_contacts;

create trigger sync_legacy_campaign_contact_to_organization_context_v1
after insert or update
on local_intel.campaign_contacts
for each row
execute function atlas.sync_legacy_campaign_contact_to_organization_context_v1();

comment on function atlas.sync_legacy_campaign_contact_to_organization_context_v1() is
  'Compatibility membrane for pre-governance campaign writers. For campaigns mapped to an Atlas Organization purpose context, every contact insert/update resolves canonical Shared Intelligence identity into the Organization relationship, updates the private campaign membership, and records outreach as a private relationship interaction. The local_intel campaign_contact row is only a compatibility mirror.';

comment on table local_intel.campaign_contacts is
  'Legacy/shared-intelligence campaign-contact compatibility carrier. Organization-owned campaign contact state is authoritative in atlas.organization_purpose_context_memberships and outreach history in atlas.external_relationship_interactions. Writes to mapped legacy campaigns are governed by atlas.sync_legacy_campaign_contact_to_organization_context_v1().';
