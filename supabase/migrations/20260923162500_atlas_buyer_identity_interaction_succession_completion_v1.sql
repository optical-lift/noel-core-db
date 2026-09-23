-- Atlas buyer relationship / contact succession completion v1
-- Finish the legacy buyer identity + interaction migration, then keep the
-- legacy buyer tables only as compatibility mirrors over the generic
-- Organization relationship seam.

do $$
declare
  v_entity_id uuid;
begin
  -- The final unmapped legacy buyer already has an Elm Organization identity
  -- subject + external relationship from earlier outreach. Establish the
  -- missing canonical Shared Intelligence entity from the existing stored
  -- business facts without claiming external verification.
  insert into local_intel.entities(
    stable_key,
    entity_type,
    name,
    email,
    address_line1,
    city,
    state,
    postal_code,
    status,
    verification_state,
    local_context_id,
    metadata
  )
  select
    'forget-me-not-floral-and-design-ozark-mo',
    'business',
    'Forget Me Not Floral & Design',
    'forgetmenotfloralanddesign@gmail.com',
    '3037 Westwind Dr',
    'Ozark',
    'MO',
    '65721',
    'active',
    'needs_verification',
    'f12da65e-9daf-46c8-b881-c4304d5d4b20'::uuid,
    jsonb_build_object(
      'successionBasis','atlas_legacy_buyer_relationship',
      'legacyBuyerRelationshipId','10945391-3613-41b3-9726-9adc0b381eb8',
      'verificationNote','Canonicalized from existing Atlas business facts; public operating location remains unverified.'
    )
  where not exists(
    select 1
    from local_intel.entities e
    where e.stable_key='forget-me-not-floral-and-design-ozark-mo'
       or lower(coalesce(e.email,''))='forgetmenotfloralanddesign@gmail.com'
  );

  select e.id
  into v_entity_id
  from local_intel.entities e
  where e.stable_key='forget-me-not-floral-and-design-ozark-mo'
     or lower(coalesce(e.email,''))='forgetmenotfloralanddesign@gmail.com'
  order by case when e.stable_key='forget-me-not-floral-and-design-ozark-mo' then 0 else 1 end,e.created_at
  limit 1;

  if v_entity_id is null then
    raise exception 'Could not establish canonical Forget Me Not entity.'
      using errcode='P0001';
  end if;

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
    'a1379fac-fce8-444c-a380-f6a6c79ddf3c'::uuid,
    'local_intel',
    'entity_id',
    v_entity_id::text,
    v_entity_id::text,
    true,
    1,
    jsonb_build_object(
      'basis','legacy_buyer_exact_identity_reconciliation',
      'legacyBuyerRelationshipId','10945391-3613-41b3-9726-9adc0b381eb8'
    )
  where not exists(
    select 1
    from atlas.identity_subject_external_identifiers i
    where i.organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and i.provider_key='local_intel'
      and i.identifier_type='entity_id'
      and i.identifier_normalized=v_entity_id::text
      and i.is_current
  );

  update atlas.buyer_relationship_reconstruction
  set entity_id=v_entity_id,
      updated_at=now()
  where id='10945391-3613-41b3-9726-9adc0b381eb8'::uuid;

  insert into atlas.legacy_buyer_relationship_external_mappings(
    buyer_relationship_id,
    external_relationship_id,
    identity_subject_id
  )
  values(
    '10945391-3613-41b3-9726-9adc0b381eb8'::uuid,
    '9ce479fa-cb58-4f01-bd24-41a2da58edd6'::uuid,
    'a1379fac-fce8-444c-a380-f6a6c79ddf3c'::uuid
  )
  on conflict (buyer_relationship_id) do nothing;
end
$$;

do $$
declare
  v_event atlas.buyer_contact_events%rowtype;
  v_relationship_id uuid;
  v_organization_id uuid;
  v_interaction jsonb;
  v_interaction_id uuid;
begin
  -- Backfill every remaining legacy buyer contact event into the generic
  -- Organization-private interaction history exactly once.
  for v_event in
    select e.*
    from atlas.buyer_contact_events e
    left join atlas.legacy_buyer_contact_external_interaction_mappings m
      on m.buyer_contact_event_id=e.id
    where m.buyer_contact_event_id is null
    order by e.occurred_at,e.id
  loop
    select m.external_relationship_id,r.organization_id
    into v_relationship_id,v_organization_id
    from atlas.legacy_buyer_relationship_external_mappings m
    join atlas.external_relationships r
      on r.id=m.external_relationship_id
    where m.buyer_relationship_id=v_event.buyer_relationship_id;

    if v_relationship_id is null or v_organization_id is null then
      raise exception 'Legacy buyer contact % has no generic relationship successor.',v_event.id
        using errcode='23514';
    end if;

    v_interaction := atlas.record_shared_directory_interaction_service_v1(
      v_organization_id,
      v_relationship_id,
      'buyer_outreach',
      v_event.occurred_at,
      v_event.contact_method,
      v_event.outcome,
      v_event.contact_name,
      v_event.follow_up,
      v_event.notes,
      jsonb_strip_nulls(jsonb_build_object(
        'legacyBuyerContactEventId',v_event.id,
        'legacyBuyerRelationshipId',v_event.buyer_relationship_id,
        'contactDetails',v_event.contact_details,
        'salesChannel',v_event.sales_channel,
        'offerKey',v_event.offer_key,
        'quantity',v_event.quantity,
        'quotedWeeklyPrice',v_event.quoted_weekly_price,
        'agreedStartDate',v_event.agreed_start_date,
        'recordedByMembershipId',v_event.recorded_by_membership_id,
        'legacyMetadata',coalesce(v_event.metadata,'{}'::jsonb),
        'successionBasis','legacy_buyer_contact_event'
      ))
    );

    v_interaction_id := nullif(v_interaction->>'interactionId','')::uuid;

    if v_interaction_id is null then
      raise exception 'Could not create generic interaction for legacy buyer contact %',v_event.id
        using errcode='P0001';
    end if;

    update atlas.external_relationship_interactions
    set source_task_id=v_event.source_task_id
    where id=v_interaction_id;

    insert into atlas.legacy_buyer_contact_external_interaction_mappings(
      buyer_contact_event_id,
      external_relationship_interaction_id
    )
    values(v_event.id,v_interaction_id)
    on conflict (buyer_contact_event_id) do nothing;
  end loop;
end
$$;

create or replace function atlas.sync_legacy_buyer_contact_event_to_external_interaction_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_relationship_id uuid;
  v_organization_id uuid;
  v_mapping atlas.legacy_buyer_contact_external_interaction_mappings%rowtype;
  v_interaction jsonb;
  v_interaction_id uuid;
begin
  select m.external_relationship_id,r.organization_id
  into v_relationship_id,v_organization_id
  from atlas.legacy_buyer_relationship_external_mappings m
  join atlas.external_relationships r
    on r.id=m.external_relationship_id
  where m.buyer_relationship_id=new.buyer_relationship_id;

  if v_relationship_id is null or v_organization_id is null then
    raise exception
      'Legacy buyer contact writes require an existing generic external relationship successor.'
      using errcode='23514';
  end if;

  select *
  into v_mapping
  from atlas.legacy_buyer_contact_external_interaction_mappings m
  where m.buyer_contact_event_id=new.id;

  if v_mapping.buyer_contact_event_id is null then
    v_interaction := atlas.record_shared_directory_interaction_service_v1(
      v_organization_id,
      v_relationship_id,
      'buyer_outreach',
      new.occurred_at,
      new.contact_method,
      new.outcome,
      new.contact_name,
      new.follow_up,
      new.notes,
      jsonb_strip_nulls(jsonb_build_object(
        'legacyBuyerContactEventId',new.id,
        'legacyBuyerRelationshipId',new.buyer_relationship_id,
        'contactDetails',new.contact_details,
        'salesChannel',new.sales_channel,
        'offerKey',new.offer_key,
        'quantity',new.quantity,
        'quotedWeeklyPrice',new.quoted_weekly_price,
        'agreedStartDate',new.agreed_start_date,
        'recordedByMembershipId',new.recorded_by_membership_id,
        'legacyMetadata',coalesce(new.metadata,'{}'::jsonb),
        'compatibilityBridge','legacy_buyer_contact_writer_membrane_v1'
      ))
    );

    v_interaction_id := nullif(v_interaction->>'interactionId','')::uuid;

    update atlas.external_relationship_interactions
    set source_task_id=new.source_task_id
    where id=v_interaction_id;

    insert into atlas.legacy_buyer_contact_external_interaction_mappings(
      buyer_contact_event_id,
      external_relationship_interaction_id
    )
    values(new.id,v_interaction_id);
  else
    v_interaction_id := v_mapping.external_relationship_interaction_id;

    update atlas.external_relationship_interactions
    set occurred_at=new.occurred_at,
        interaction_kind='buyer_outreach',
        channel=new.contact_method,
        outcome=new.outcome,
        contact_label=new.contact_name,
        follow_up=new.follow_up,
        note=new.notes,
        source_task_id=new.source_task_id,
        metadata=coalesce(metadata,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'legacyBuyerContactEventId',new.id,
          'legacyBuyerRelationshipId',new.buyer_relationship_id,
          'contactDetails',new.contact_details,
          'salesChannel',new.sales_channel,
          'offerKey',new.offer_key,
          'quantity',new.quantity,
          'quotedWeeklyPrice',new.quoted_weekly_price,
          'agreedStartDate',new.agreed_start_date,
          'recordedByMembershipId',new.recorded_by_membership_id,
          'legacyMetadata',coalesce(new.metadata,'{}'::jsonb),
          'compatibilityBridge','legacy_buyer_contact_writer_membrane_v1'
        ))
    where id=v_interaction_id
      and organization_id=v_organization_id
      and external_relationship_id=v_relationship_id;
  end if;

  if new.source_task_id is not null then
    update atlas.tasks t
    set metadata=coalesce(t.metadata,'{}'::jsonb) || jsonb_build_object(
          'result_storage','atlas.external_relationship_interactions',
          'legacy_result_mirror','atlas.buyer_contact_events',
          'external_relationship_id',v_relationship_id,
          'external_relationship_interaction_id',v_interaction_id
        ),
        updated_at=now()
    where t.id=new.source_task_id;
  end if;

  return new;
end
$function$;

drop trigger if exists sync_legacy_buyer_contact_event_to_external_interaction_v1
  on atlas.buyer_contact_events;

create trigger sync_legacy_buyer_contact_event_to_external_interaction_v1
after insert or update
on atlas.buyer_contact_events
for each row
execute function atlas.sync_legacy_buyer_contact_event_to_external_interaction_v1();

create or replace function atlas.guard_legacy_buyer_relationship_identity_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_mapping atlas.legacy_buyer_relationship_external_mappings%rowtype;
begin
  if tg_op='INSERT' then
    raise exception
      'Legacy buyer relationship creation is retired. Resolve canonical Shared Intelligence identity and create/use atlas.external_relationships.'
      using errcode='0A000';
  end if;

  if tg_op='DELETE' then
    raise exception
      'Legacy buyer relationship deletion is disabled after external-relationship succession.'
      using errcode='0A000';
  end if;

  select *
  into v_mapping
  from atlas.legacy_buyer_relationship_external_mappings m
  where m.buyer_relationship_id=new.id;

  if v_mapping.buyer_relationship_id is null then
    raise exception
      'Legacy buyer relationship update requires a generic external relationship successor.'
      using errcode='23514';
  end if;

  if new.entity_id is distinct from old.entity_id then
    raise exception
      'Legacy buyer identity cannot be reassigned. Resolve identity through the Shared Directory seam.'
      using errcode='0A000';
  end if;

  update atlas.external_relationships r
  set metadata=coalesce(r.metadata,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
        'legacyBuyerRelationshipId',new.id,
        'legacyBuyerStableKey',new.stable_key,
        'legacyBuyerType',new.buyer_type,
        'legacyRelationshipStatus',new.relationship_status,
        'legacyPrimaryContactName',new.primary_contact_name,
        'legacyPriorityRank',new.priority_rank,
        'legacyVolumeTier',new.volume_tier,
        'legacyNextAction',new.next_action,
        'legacyCompatibilityMirror','atlas.buyer_relationship_reconstruction',
        'relationshipAuthority','atlas.external_relationships'
      )),
      updated_at=now()
  where r.id=v_mapping.external_relationship_id;

  return new;
end
$function$;

drop trigger if exists guard_legacy_buyer_relationship_identity_v1
  on atlas.buyer_relationship_reconstruction;

create trigger guard_legacy_buyer_relationship_identity_v1
after insert or update or delete
on atlas.buyer_relationship_reconstruction
for each row
execute function atlas.guard_legacy_buyer_relationship_identity_v1();

comment on table atlas.buyer_relationship_reconstruction is
  'Legacy compatibility mirror after universal external-relationship succession. New relationship identity must be established through canonical Shared Intelligence entity resolution and atlas.external_relationships.';
comment on table atlas.buyer_contact_events is
  'Legacy buyer-contact compatibility mirror. Organization-private interaction authority is atlas.external_relationship_interactions; inserts/updates are synchronously governed by atlas.sync_legacy_buyer_contact_event_to_external_interaction_v1().';
comment on function atlas.sync_legacy_buyer_contact_event_to_external_interaction_v1() is
  'Compatibility membrane ensuring every legacy buyer contact write has exactly one generic Organization-private external relationship interaction successor.';
comment on function atlas.guard_legacy_buyer_relationship_identity_v1() is
  'Prevents new legacy buyer identity creation/deletion, prevents identity reassignment, and mirrors allowed legacy status updates onto the generic external relationship overlay.';
