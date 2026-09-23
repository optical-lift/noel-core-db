-- Atlas legacy local_intel campaign ownership cleanup v1
-- Move the two existing Elm-owned campaign uses into Organization-private
-- purpose contexts without cloning canonical Shared Intelligence entities.
-- Legacy local_intel campaign rows remain compatibility carriers only.

create table if not exists atlas.legacy_local_intel_campaign_context_mappings (
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  local_intel_campaign_id uuid primary key references local_intel.campaigns(id) on delete restrict,
  purpose_context_id uuid not null,
  created_at timestamptz not null default now(),
  constraint legacy_local_intel_campaign_context_mappings_context_org_fk
    foreign key (organization_id,purpose_context_id)
    references atlas.organization_purpose_contexts(organization_id,id)
    on delete restrict,
  unique (organization_id,purpose_context_id)
);

create table if not exists atlas.legacy_local_intel_campaign_contact_membership_mappings (
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  local_intel_campaign_contact_id uuid primary key references local_intel.campaign_contacts(id) on delete restrict,
  purpose_context_membership_id uuid not null references atlas.organization_purpose_context_memberships(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id,purpose_context_membership_id)
);

alter table atlas.legacy_local_intel_campaign_context_mappings enable row level security;
alter table atlas.legacy_local_intel_campaign_contact_membership_mappings enable row level security;

revoke all on table atlas.legacy_local_intel_campaign_context_mappings from public,anon,authenticated;
revoke all on table atlas.legacy_local_intel_campaign_contact_membership_mappings from public,anon,authenticated;
grant select,insert,update,delete on table atlas.legacy_local_intel_campaign_context_mappings to service_role;
grant select,insert,update,delete on table atlas.legacy_local_intel_campaign_contact_membership_mappings to service_role;

comment on table atlas.legacy_local_intel_campaign_context_mappings is
  'Compatibility map from pre-governance local_intel campaign rows to Organization-private purpose contexts. New Organization campaigns belong in Atlas purpose contexts, not Shared Intelligence.';
comment on table atlas.legacy_local_intel_campaign_contact_membership_mappings is
  'Compatibility map from pre-governance local_intel campaign contact rows to Organization-private purpose-context memberships over canonical Shared Intelligence entities.';

-- Resolve one pre-existing identity-review hold without creating a second subject:
-- the legacy buyer relationship for Jagged Edge already points to this exact
-- Organization subject/relationship, and the canonical Shared Intelligence
-- entity has the same business identity. Bind that canonical entity to the
-- existing subject rather than creating another identity.
insert into atlas.identity_subject_external_identifiers(
  organization_id,
  subject_id,
  provider_key,
  identifier_type,
  identifier_value,
  identifier_normalized,
  is_current,
  priority,
  metadata
)
select
  'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
  'f0bdeadf-6b91-4835-992e-b964b46d6eb1'::uuid,
  'local_intel',
  'entity_id',
  '5bfeeb23-e13f-45fc-beef-d26acc099742',
  '5bfeeb23-e13f-45fc-beef-d26acc099742',
  true,
  1,
  jsonb_build_object(
    'basis','legacy_buyer_exact_identity_reconciliation',
    'legacyBuyerRelationshipId','6362f9eb-cc65-485a-acc0-51c6f57a4064',
    'canonicalEntityName','Jagged Edge Salon Featuring B''s Esthetics'
  )
where not exists (
  select 1
  from atlas.identity_subject_external_identifiers i
  where i.organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
    and i.subject_id='f0bdeadf-6b91-4835-992e-b964b46d6eb1'::uuid
    and i.provider_key='local_intel'
    and i.identifier_type='entity_id'
    and i.identifier_normalized='5bfeeb23-e13f-45fc-beef-d26acc099742'
    and i.is_current
);

update atlas.buyer_relationship_reconstruction
set entity_id='5bfeeb23-e13f-45fc-beef-d26acc099742'::uuid,
    updated_at=now()
where id='6362f9eb-cc65-485a-acc0-51c6f57a4064'::uuid
  and entity_id is null;

do $$
declare
  v_org uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_campaign local_intel.campaigns%rowtype;
  v_contact local_intel.campaign_contacts%rowtype;
  v_context_id uuid;
  v_relationship_id uuid;
  v_membership_id uuid;
  v_attach jsonb;
begin
  for v_campaign in
    select *
    from local_intel.campaigns
    where id in (
      '116d88f5-cbbd-4b24-a3f7-01c1f90bb5ea'::uuid,
      'e8906630-2b0f-4bed-b2f4-e370dafde452'::uuid
    )
    order by created_at,id
  loop
    v_context_id := (
      atlas.create_purpose_context_service_v1(
        v_org,
        case v_campaign.id
          when '116d88f5-cbbd-4b24-a3f7-01c1f90bb5ea'::uuid
            then 'venue_pilot_01'
          when 'e8906630-2b0f-4bed-b2f4-e370dafde452'::uuid
            then 'hair_sourcing_marshfield_20260828'
        end,
        'campaign',
        v_campaign.name,
        v_campaign.learning_objective,
        jsonb_strip_nulls(jsonb_build_object(
          'campaignKind',v_campaign.campaign_kind,
          'status',v_campaign.status,
          'channel',v_campaign.channel,
          'offerText',v_campaign.offer_text,
          'startsAt',v_campaign.starts_at,
          'endsAt',v_campaign.ends_at,
          'offeringId',v_campaign.offering_id,
          'legacySource',jsonb_build_object(
            'schema','local_intel',
            'table','campaigns',
            'campaignId',v_campaign.id,
            'stableKey',v_campaign.stable_key
          ),
          'legacyMetadata',coalesce(v_campaign.metadata,'{}'::jsonb)
        )),
        null
      )->>'contextId'
    )::uuid;

    insert into atlas.legacy_local_intel_campaign_context_mappings(
      organization_id,local_intel_campaign_id,purpose_context_id
    ) values (
      v_org,v_campaign.id,v_context_id
    )
    on conflict (local_intel_campaign_id) do update
    set organization_id=excluded.organization_id,
        purpose_context_id=excluded.purpose_context_id;

    for v_contact in
      select *
      from local_intel.campaign_contacts
      where campaign_id=v_campaign.id
      order by created_at,id
    loop
      if v_contact.entity_id is null then
        continue;
      end if;

      v_attach := atlas.attach_shared_directory_entity_service_v1(
        v_org,
        v_contact.entity_id,
        'contact',
        null
      );

      v_relationship_id := nullif(v_attach->>'externalRelationshipId','')::uuid;

      if v_relationship_id is null then
        raise exception 'Could not establish Organization relationship for campaign contact %',v_contact.id;
      end if;

      v_membership_id := (
        atlas.add_external_relationship_to_purpose_context_service_v1(
          v_org,
          v_context_id,
          v_relationship_id,
          array['outreach_target'],
          jsonb_strip_nulls(jsonb_build_object(
            'campaignState',v_contact.state,
            'lastActionAt',v_contact.last_action_at,
            'selectedContactPointId',v_contact.contact_point_id,
            'campaignTargetId',v_contact.campaign_target_id,
            'campaignAssetId',v_contact.campaign_asset_id,
            'legacyCampaignContactId',v_contact.id,
            'legacyMetadata',coalesce(v_contact.metadata,'{}'::jsonb)
          )),
          jsonb_build_object(
            'basis','legacy_local_intel_campaign_contact_migration',
            'canonicalEntityId',v_contact.entity_id,
            'legacyCampaignId',v_campaign.id,
            'legacyCampaignContactId',v_contact.id
          ),
          null
        )->>'membershipId'
      )::uuid;

      insert into atlas.legacy_local_intel_campaign_contact_membership_mappings(
        organization_id,local_intel_campaign_contact_id,purpose_context_membership_id
      ) values (
        v_org,v_contact.id,v_membership_id
      )
      on conflict (local_intel_campaign_contact_id) do update
      set organization_id=excluded.organization_id,
          purpose_context_membership_id=excluded.purpose_context_membership_id;
    end loop;
  end loop;
end
$$;

comment on table local_intel.campaigns is
  'Legacy/shared-intelligence campaign carrier. Existing Elm-owned campaign uses have successor Organization-private Atlas purpose contexts. Do not create new Ledger-private campaign ownership here.';
comment on table local_intel.campaign_contacts is
  'Legacy/shared-intelligence campaign-contact carrier. Existing Elm-owned campaign contact use has successor Atlas purpose-context memberships over canonical entities. Do not treat this table as Organization-private contact ownership.';
