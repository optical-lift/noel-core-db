begin;

create table atlas.flower_route_availability_commercial_offer_extensions (
  availability_snapshot_id uuid primary key references atlas.flower_route_availability_snapshots(id) on delete restrict,
  commercial_offer_snapshot_id uuid not null unique references atlas.commercial_offer_snapshots(id) on delete restrict,
  created_at timestamptz not null default now()
);
comment on table atlas.flower_route_availability_commercial_offer_extensions is 'Typed bridge from flower route availability evidence to the universal immutable commercial offer snapshot presented to outside relationships.';

create table atlas.flower_availability_outreach_commercial_distribution_extensions (
  flower_outreach_round_id uuid primary key references atlas.flower_availability_outreach_rounds(id) on delete restrict,
  commercial_offer_distribution_id uuid not null unique references atlas.commercial_offer_distributions(id) on delete restrict,
  created_at timestamptz not null default now()
);
comment on table atlas.flower_availability_outreach_commercial_distribution_extensions is 'Compatibility bridge from the flower-specific outreach carrier to the universal commercial offer distribution record. New cross-domain reads should use the universal distribution.';

create table atlas.community_registration_commercial_offer_snapshot_extensions (
  registration_offering_id uuid not null references atlas.community_registration_offerings(id) on delete restrict,
  commercial_offer_snapshot_id uuid not null unique references atlas.commercial_offer_snapshots(id) on delete restrict,
  captured_at timestamptz not null default now(),
  primary key(registration_offering_id,commercial_offer_snapshot_id)
);
comment on table atlas.community_registration_commercial_offer_snapshot_extensions is 'Typed bridge proving the commercial offer snapshot kernel with a non-flower domain: a registration offering may be captured as one or more immutable offer-state snapshots over time.';

alter table atlas.flower_availability_outreach_recipients drop constraint if exists flower_availability_outreach_recipients_recipient_role_check;
alter table atlas.flower_availability_outreach_recipients add constraint flower_availability_outreach_recipients_recipient_role_check check (recipient_role in ('to','cc','bcc','unknown'));
alter table atlas.flower_availability_outreach_recipients alter column recipient_role set default 'unknown';

create or replace function atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(p_availability_snapshot_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_snapshot atlas.flower_route_availability_snapshots%rowtype; v_farm atlas.farms%rowtype; v_lane atlas.flower_sales_route_lanes%rowtype; v_existing_id uuid; v_lines jsonb; v_result jsonb;
begin
  select * into v_snapshot from atlas.flower_route_availability_snapshots where id=p_availability_snapshot_id;
  if v_snapshot.id is null then raise exception 'Flower availability snapshot not found.' using errcode='P0002'; end if;
  select * into v_farm from atlas.farms where id=v_snapshot.farm_id;
  if v_farm.id is null or v_farm.organization_id is null then raise exception 'Flower availability snapshot has no organization scope.' using errcode='23514'; end if;
  select * into v_lane from atlas.flower_sales_route_lanes where id=v_snapshot.route_lane_id;
  select commercial_offer_snapshot_id into v_existing_id from atlas.flower_route_availability_commercial_offer_extensions where availability_snapshot_id=v_snapshot.id;
  if v_existing_id is not null then return jsonb_build_object('commercialOfferSnapshotId',v_existing_id,'created',false,'availabilitySnapshotId',v_snapshot.id); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'lineKey',l.id::text,
    'description',l.product_label,
    'quantityAvailable',l.quantity,
    'unit',l.unit,
    'unitPrice',l.unit_price,
    'priceMin',l.price_min,
    'priceMax',l.price_max,
    'currency',case when l.unit_price is not null or l.price_min is not null or l.price_max is not null then 'USD' else null end,
    'priceBasis',l.price_basis,
    'sourceRef',l.id::text,
    'terms',jsonb_strip_nulls(jsonb_build_object('reportedProductLabel',l.reported_product_label,'containerLabel',l.container_label,'floristSellable',l.florist_sellable,'priceNote',l.price_note)),
    'metadata',l.metadata
  ) order by l.created_at,l.id),'[]'::jsonb) into v_lines
  from atlas.flower_route_availability_lines l where l.snapshot_id=v_snapshot.id;
  v_result:=atlas.record_commercial_offer_snapshot_service_v1(
    p_organization_id=>v_farm.organization_id,
    p_organization_unit_id=>v_farm.organization_unit_id,
    p_snapshot_key=>'flower_route_availability:'||v_snapshot.id::text,
    p_title=>'Flower availability — '||v_snapshot.effective_date::text||coalesce(' — '||nullif(v_lane.lane_label,''),''),
    p_offer_state=>case when jsonb_array_length(v_lines)>0 then 'complete' else 'incomplete_evidence' end,
    p_valid_from=>v_snapshot.observed_at,
    p_valid_until=>null,
    p_lines=>v_lines,
    p_assets=>'[]'::jsonb,
    p_source_kind=>'domain_snapshot',
    p_source_ref=>v_snapshot.id::text,
    p_metadata=>jsonb_build_object('sourceDomain','flower','farmId',v_snapshot.farm_id,'availabilitySnapshotId',v_snapshot.id,'routeLaneId',v_snapshot.route_lane_id,'effectiveDate',v_snapshot.effective_date,'sourcePerson',v_snapshot.source_person,'sourceKind',v_snapshot.source_kind,'sourceNote',v_snapshot.note)
  );
  insert into atlas.flower_route_availability_commercial_offer_extensions(availability_snapshot_id,commercial_offer_snapshot_id)
  values(v_snapshot.id,(v_result->>'offerSnapshotId')::uuid)
  on conflict (availability_snapshot_id) do nothing;
  return v_result||jsonb_build_object('availabilitySnapshotId',v_snapshot.id);
end;$function$;
comment on function atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(uuid) is 'Projects one immutable flower availability snapshot into the universal commercial offer snapshot kernel without changing flower inventory authority.';

create or replace function atlas.ensure_community_registration_commercial_offer_snapshot_service_v1(p_registration_offering_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_registration atlas.community_registration_offerings%rowtype; v_farm atlas.farms%rowtype; v_commercial_offering_id uuid; v_snapshot_key text; v_existing_id uuid; v_result jsonb; v_line jsonb;
begin
  select * into v_registration from atlas.community_registration_offerings where id=p_registration_offering_id;
  if v_registration.id is null then raise exception 'Community registration offering not found.' using errcode='P0002'; end if;
  select * into v_farm from atlas.farms where id=v_registration.farm_id;
  if v_farm.id is null or v_farm.organization_id is null then raise exception 'Registration offering has no organization scope.' using errcode='23514'; end if;
  select commercial_offering_id into v_commercial_offering_id from atlas.community_registration_commercial_offering_extensions where registration_offering_id=v_registration.id;
  if v_commercial_offering_id is null then raise exception 'Registration offering has not been mapped to universal Commercial Offering.' using errcode='23514'; end if;
  v_snapshot_key:='community_registration:'||v_registration.id::text||':captured:'||extract(epoch from v_registration.updated_at)::bigint::text;
  select e.commercial_offer_snapshot_id into v_existing_id from atlas.community_registration_commercial_offer_snapshot_extensions e join atlas.commercial_offer_snapshots s on s.id=e.commercial_offer_snapshot_id where e.registration_offering_id=v_registration.id and s.snapshot_key=v_snapshot_key limit 1;
  if v_existing_id is not null then return jsonb_build_object('commercialOfferSnapshotId',v_existing_id,'created',false,'registrationOfferingId',v_registration.id); end if;
  v_line:=jsonb_build_object('lineKey',v_registration.id::text,'commercialOfferingId',v_commercial_offering_id,'description',v_registration.title,'unit',v_registration.fee_basis,'unitPrice',v_registration.fee_amount,'currency',v_registration.fee_currency,'priceBasis',v_registration.fee_basis,'sourceRef',v_registration.id::text,'terms',jsonb_strip_nulls(jsonb_build_object('registrationScope',v_registration.registration_scope,'status',v_registration.status,'opensAt',v_registration.opens_at,'closesAt',v_registration.closes_at,'publicDescription',v_registration.public_description,'termsVersion',v_registration.terms_version)),'metadata',v_registration.metadata);
  v_result:=atlas.record_commercial_offer_snapshot_service_v1(
    p_organization_id=>v_farm.organization_id,p_organization_unit_id=>v_farm.organization_unit_id,p_snapshot_key=>v_snapshot_key,p_title=>v_registration.title,p_offer_state=>'complete',p_valid_from=>v_registration.opens_at,p_valid_until=>v_registration.closes_at,p_lines=>jsonb_build_array(v_line),p_assets=>'[]'::jsonb,p_source_kind=>'domain_snapshot',p_source_ref=>v_registration.id::text,p_metadata=>jsonb_build_object('sourceDomain','community_registration','registrationOfferingId',v_registration.id,'farmId',v_registration.farm_id)
  );
  insert into atlas.community_registration_commercial_offer_snapshot_extensions(registration_offering_id,commercial_offer_snapshot_id)
  values(v_registration.id,(v_result->>'offerSnapshotId')::uuid) on conflict do nothing;
  return v_result||jsonb_build_object('registrationOfferingId',v_registration.id);
end;$function$;
comment on function atlas.ensure_community_registration_commercial_offer_snapshot_service_v1(uuid) is 'Captures one current community registration offering state as an immutable universal commercial offer snapshot; registration remains the owning domain authority.';

create or replace function atlas.record_flower_availability_outreach_service_v2(
  p_farm_id uuid,p_round_key text,p_sent_at timestamptz,p_subject text,p_body text,p_recipients jsonb,p_availability_snapshot_id uuid default null,p_sender_label text default null,p_sender_address text default null,p_source_kind text default 'manual_report',p_source_ref text default null,p_metadata jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,extensions as $function$
declare v_farm atlas.farms%rowtype; v_existing_round_id uuid; v_existing_distribution_id uuid; v_body_hash text; v_snapshot_result jsonb; v_offer_snapshot_id uuid; v_offer_assets jsonb:='[]'::jsonb; v_generic_recipients jsonb:='[]'::jsonb; v_recipient jsonb; v_generic_recipient jsonb; v_email text; v_display_name text; v_source_label text; v_role text; v_external_relationship_id uuid; v_buyer_relationship_id uuid; v_local_intel_entity_id uuid; v_identifiers jsonb; v_index integer:=0; v_distribution_result jsonb; v_distribution_id uuid; v_generic_recipient_row atlas.commercial_offer_distribution_recipients%rowtype; v_round_id uuid; v_recipient_count integer:=0;
begin
  select * into v_farm from atlas.farms where id=p_farm_id;
  if v_farm.id is null or v_farm.organization_id is null then raise exception 'Farm with organization scope is required.' using errcode='P0002'; end if;
  if btrim(coalesce(p_round_key,''))='' or btrim(coalesce(p_subject,''))='' then raise exception 'Round key and subject are required.' using errcode='22023'; end if;
  if p_body is null then raise exception 'Exact email body is required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_recipients,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_recipients,'[]'::jsonb))=0 then raise exception 'Recipients must be a non-empty JSON array.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Metadata must be an object.' using errcode='22023'; end if;
  if p_availability_snapshot_id is not null and not exists(select 1 from atlas.flower_route_availability_snapshots s where s.id=p_availability_snapshot_id and s.farm_id=p_farm_id) then raise exception 'Availability snapshot is outside this farm.' using errcode='23514'; end if;

  select id into v_existing_round_id from atlas.flower_availability_outreach_rounds where farm_id=p_farm_id and round_key=btrim(p_round_key);
  if v_existing_round_id is not null then
    select commercial_offer_distribution_id into v_existing_distribution_id from atlas.flower_availability_outreach_commercial_distribution_extensions where flower_outreach_round_id=v_existing_round_id;
    return jsonb_build_object('state','recorded','outreachRoundId',v_existing_round_id,'commercialOfferDistributionId',v_existing_distribution_id,'created',false,'recipientCount',(select count(*) from atlas.flower_availability_outreach_recipients r where r.outreach_round_id=v_existing_round_id));
  end if;

  if p_availability_snapshot_id is not null then
    v_snapshot_result:=atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(p_availability_snapshot_id);
    v_offer_snapshot_id:=(v_snapshot_result->>'commercialOfferSnapshotId')::uuid;
  else
    if coalesce((p_metadata->>'availabilityAttachmentMentioned')::boolean,false) then
      v_offer_assets:=jsonb_build_array(jsonb_build_object('assetKey','referenced-offer-materials','assetRole','referenced_offer_materials','captureState','missing_evidence','sourceRef','email-body-reference','metadata',jsonb_build_object('reason','Email states that examples/price material accompanied the message, but exact assets were not captured.')));
    end if;
    v_snapshot_result:=atlas.record_commercial_offer_snapshot_service_v1(
      p_organization_id=>v_farm.organization_id,p_organization_unit_id=>v_farm.organization_unit_id,p_snapshot_key=>'flower_availability_outreach:'||btrim(p_round_key)||':offer',p_title=>'Flower availability referenced by '||btrim(p_subject),p_offer_state=>'incomplete_evidence',p_valid_from=>p_sent_at,p_valid_until=>null,p_lines=>'[]'::jsonb,p_assets=>v_offer_assets,p_source_kind=>case when lower(btrim(coalesce(p_source_kind,'manual_report')))='provider_observation' then 'provider_observation' when lower(btrim(coalesce(p_source_kind,'manual_report')))='imported_record' then 'imported_record' else 'manual_capture' end,p_source_ref=>p_source_ref,p_metadata=>coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('sourceDomain','flower','farmId',p_farm_id,'missingAvailabilitySnapshot',true)
    );
    v_offer_snapshot_id:=(v_snapshot_result->>'offerSnapshotId')::uuid;
  end if;

  for v_recipient in select value from jsonb_array_elements(p_recipients) loop
    v_index:=v_index+1; v_email:=lower(btrim(coalesce(v_recipient->>'email',''))); if v_email='' then raise exception 'Every flower outreach recipient requires an email.' using errcode='22023'; end if;
    v_display_name:=nullif(btrim(v_recipient->>'displayName'),''); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),'');
    v_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'unknown')); if v_role not in ('to','cc','bcc','unknown') then raise exception 'recipientRole must be to, cc, bcc, or unknown.' using errcode='22023'; end if;
    begin v_external_relationship_id:=nullif(btrim(v_recipient->>'externalRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid externalRelationshipId for %.',v_email using errcode='22023'; end;
    begin v_buyer_relationship_id:=nullif(btrim(v_recipient->>'buyerRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid buyerRelationshipId for %.',v_email using errcode='22023'; end;
    begin v_local_intel_entity_id:=nullif(btrim(v_recipient->>'localIntelEntityId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid localIntelEntityId for %.',v_email using errcode='22023'; end;
    if v_external_relationship_id is null and v_buyer_relationship_id is not null then select m.external_relationship_id into v_external_relationship_id from atlas.legacy_buyer_relationship_external_mappings m join atlas.buyer_relationship_reconstruction b on b.id=m.buyer_relationship_id where m.buyer_relationship_id=v_buyer_relationship_id and b.farm_id=p_farm_id; if v_external_relationship_id is null then raise exception 'buyerRelationshipId is outside this farm for %.',v_email using errcode='23514'; end if; end if;
    v_identifiers:=jsonb_build_array(jsonb_build_object('type','email','value',v_email,'normalized',v_email,'identityScoped',true));
    if v_local_intel_entity_id is not null then v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object('providerKey','local_intel','type','entity_id','value',v_local_intel_entity_id::text,'normalized',v_local_intel_entity_id::text,'identityScoped',true)); end if;
    v_generic_recipient:=jsonb_strip_nulls(jsonb_build_object('externalRelationshipId',v_external_relationship_id,'displayName',v_display_name,'contactKind','email','contactValue',v_email,'contactNormalized',v_email,'recipientRole',v_role,'sourceLabel',v_source_label,'identifiers',v_identifiers,'metadata',coalesce(v_recipient->'metadata','{}'::jsonb)||jsonb_build_object('sourceDomain','flower','flowerRecipientIndex',v_index,'buyerRelationshipId',v_buyer_relationship_id,'localIntelEntityId',v_local_intel_entity_id)));
    v_generic_recipients:=v_generic_recipients||jsonb_build_array(v_generic_recipient);
  end loop;

  v_distribution_result:=atlas.record_commercial_offer_distribution_service_v1(p_offer_snapshot_id=>v_offer_snapshot_id,p_distribution_key=>'flower_availability:'||btrim(p_round_key),p_occurred_at=>p_sent_at,p_channel=>'email',p_recipients=>v_generic_recipients,p_subject=>p_subject,p_body=>p_body,p_sender_label=>p_sender_label,p_sender_address=>p_sender_address,p_source_kind=>lower(btrim(coalesce(p_source_kind,'manual_report'))),p_source_ref=>p_source_ref,p_metadata=>coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('sourceDomain','flower','farmId',p_farm_id,'flowerRoundKey',btrim(p_round_key)),p_allow_create_prospects=>true);
  if v_distribution_result->>'state' is distinct from 'recorded' then return v_distribution_result||jsonb_build_object('outreachRoundId',null,'commercialOfferSnapshotId',v_offer_snapshot_id); end if;
  v_distribution_id:=(v_distribution_result->>'distributionId')::uuid; v_body_hash:=encode(extensions.digest(convert_to(p_body,'UTF8'),'sha256'),'hex');

  insert into atlas.flower_availability_outreach_rounds(organization_id,organization_unit_id,farm_id,availability_snapshot_id,round_key,channel,sender_label,sender_address,subject,body_text,body_sha256,sent_at,source_kind,source_ref,metadata)
  values(v_farm.organization_id,v_farm.organization_unit_id,v_farm.id,p_availability_snapshot_id,btrim(p_round_key),'email',nullif(btrim(p_sender_label),''),nullif(lower(btrim(p_sender_address)),''),btrim(p_subject),p_body,v_body_hash,p_sent_at,lower(btrim(coalesce(p_source_kind,'manual_report'))),nullif(btrim(p_source_ref),''),coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('commercialOfferSnapshotId',v_offer_snapshot_id,'commercialOfferDistributionId',v_distribution_id,'universalDistributionAuthority',true)) returning id into v_round_id;
  insert into atlas.flower_availability_outreach_commercial_distribution_extensions(flower_outreach_round_id,commercial_offer_distribution_id) values(v_round_id,v_distribution_id);

  v_index:=0;
  for v_recipient in select value from jsonb_array_elements(p_recipients) loop
    v_index:=v_index+1; v_email:=lower(btrim(v_recipient->>'email')); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),''); v_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'unknown'));
    select * into v_generic_recipient_row from atlas.commercial_offer_distribution_recipients r where r.distribution_id=v_distribution_id and (r.metadata->>'flowerRecipientIndex')::int=v_index limit 1;
    if v_generic_recipient_row.id is null then raise exception 'Universal offer distribution recipient mapping missing for flower recipient %.',v_index using errcode='23514'; end if;
    insert into atlas.flower_availability_outreach_recipients(outreach_round_id,external_relationship_id,identity_subject_id,interaction_id,recipient_address,recipient_address_normalized,recipient_role,source_label,metadata)
    values(v_round_id,v_generic_recipient_row.external_relationship_id,v_generic_recipient_row.identity_subject_id,v_generic_recipient_row.interaction_id,v_email,v_email,v_role,v_source_label,coalesce(v_recipient->'metadata','{}'::jsonb)||jsonb_build_object('commercialOfferDistributionRecipientId',v_generic_recipient_row.id,'commercialOfferSnapshotId',v_offer_snapshot_id,'commercialOfferDistributionId',v_distribution_id));
    v_recipient_count:=v_recipient_count+1;
  end loop;
  return jsonb_build_object('state','recorded','outreachRoundId',v_round_id,'commercialOfferSnapshotId',v_offer_snapshot_id,'commercialOfferDistributionId',v_distribution_id,'created',true,'recipientCount',v_recipient_count,'bodySha256',v_body_hash);
end;$function$;
comment on function atlas.record_flower_availability_outreach_service_v2(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) is 'Flower adapter over the universal Commercial Offer Snapshot + Distribution kernel. Flower availability remains domain evidence; recipient identity uses the canonical external-party resolver; the flower tables remain a typed compatibility/read bridge.';

create or replace function atlas.record_flower_availability_outreach_service_v1(
  p_farm_id uuid,p_round_key text,p_sent_at timestamptz,p_subject text,p_body text,p_recipients jsonb,p_availability_snapshot_id uuid default null,p_sender_label text default null,p_sender_address text default null,p_source_kind text default 'manual_report',p_source_ref text default null,p_metadata jsonb default '{}'::jsonb
)
returns jsonb language sql security definer set search_path=pg_catalog,atlas as $function$
  select atlas.record_flower_availability_outreach_service_v2(p_farm_id,p_round_key,p_sent_at,p_subject,p_body,p_recipients,p_availability_snapshot_id,p_sender_label,p_sender_address,p_source_kind,p_source_ref,p_metadata);
$function$;
comment on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) is 'Compatibility entrypoint; delegates flower availability outreach to v2, which records the universal commercial offer snapshot/distribution authority.';

-- Prove the immutable offer snapshot kernel with both existing domain families.
do $block$
declare r record; x jsonb;
begin
  for r in select id from atlas.flower_route_availability_snapshots loop x:=atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(r.id); end loop;
  for r in select id from atlas.community_registration_offerings loop x:=atlas.ensure_community_registration_commercial_offer_snapshot_service_v1(r.id); end loop;
end;$block$;

-- Backfill existing flower outreach as universal distribution evidence without inventing missing offer material.
do $block$
declare r atlas.flower_availability_outreach_rounds%rowtype; v_offer_snapshot_id uuid; v_snapshot_result jsonb; v_distribution_id uuid; v_content_hash text; v_asset jsonb; rec record;
begin
  for r in select * from atlas.flower_availability_outreach_rounds fo where not exists(select 1 from atlas.flower_availability_outreach_commercial_distribution_extensions e where e.flower_outreach_round_id=fo.id) order by fo.created_at,fo.id loop
    if r.availability_snapshot_id is not null then
      v_snapshot_result:=atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(r.availability_snapshot_id); v_offer_snapshot_id:=(v_snapshot_result->>'commercialOfferSnapshotId')::uuid;
    else
      v_asset:='[]'::jsonb;
      if coalesce((r.metadata->>'availabilityAttachmentMentioned')::boolean,false) then v_asset:=jsonb_build_array(jsonb_build_object('assetKey','referenced-offer-materials','assetRole','referenced_offer_materials','captureState','missing_evidence','sourceRef','email-body-reference','metadata',jsonb_build_object('reason','Historical outreach states that offer materials accompanied the message, but exact assets were not captured.'))); end if;
      v_snapshot_result:=atlas.record_commercial_offer_snapshot_service_v1(p_organization_id=>r.organization_id,p_organization_unit_id=>r.organization_unit_id,p_snapshot_key=>'flower_availability_outreach:'||r.round_key||':offer',p_title=>'Flower availability referenced by '||r.subject,p_offer_state=>'incomplete_evidence',p_valid_from=>r.sent_at,p_lines=>'[]'::jsonb,p_assets=>v_asset,p_source_kind=>case when r.source_kind='provider_observation' then 'provider_observation' when r.source_kind='imported_record' then 'imported_record' else 'manual_capture' end,p_source_ref=>r.source_ref,p_metadata=>r.metadata||jsonb_build_object('sourceDomain','flower','farmId',r.farm_id,'flowerOutreachRoundId',r.id,'missingAvailabilitySnapshot',true));
      v_offer_snapshot_id:=(v_snapshot_result->>'offerSnapshotId')::uuid;
    end if;
    v_content_hash:=encode(extensions.digest(convert_to(jsonb_build_object('channel',r.channel,'subject',r.subject,'body',r.body_text)::text,'UTF8'),'sha256'),'hex');
    insert into atlas.commercial_offer_distributions(organization_id,organization_unit_id,offer_snapshot_id,distribution_key,channel,sender_label,sender_address,subject,body_text,content_sha256,occurred_at,source_kind,source_ref,metadata)
    values(r.organization_id,r.organization_unit_id,v_offer_snapshot_id,'flower_availability:'||r.round_key,r.channel,r.sender_label,r.sender_address,r.subject,r.body_text,v_content_hash,r.sent_at,case when r.source_kind in ('provider_observation','imported_record') then r.source_kind else 'manual_report' end,r.source_ref,r.metadata||jsonb_build_object('sourceDomain','flower','flowerOutreachRoundId',r.id,'backfilledFromFlowerCarrier',true)) returning id into v_distribution_id;
    for rec in select fr.* from atlas.flower_availability_outreach_recipients fr where fr.outreach_round_id=r.id order by fr.created_at,fr.id loop
      insert into atlas.commercial_offer_distribution_recipients(distribution_id,external_relationship_id,identity_subject_id,interaction_id,contact_kind,contact_value,contact_normalized,recipient_role,source_label,metadata)
      values(v_distribution_id,rec.external_relationship_id,rec.identity_subject_id,rec.interaction_id,'email',rec.recipient_address,rec.recipient_address_normalized,rec.recipient_role,rec.source_label,rec.metadata||jsonb_build_object('sourceDomain','flower','flowerOutreachRecipientId',rec.id,'backfilledFromFlowerCarrier',true));
    end loop;
    insert into atlas.flower_availability_outreach_commercial_distribution_extensions(flower_outreach_round_id,commercial_offer_distribution_id) values(r.id,v_distribution_id);
  end loop;
end;$block$;

alter table atlas.flower_route_availability_commercial_offer_extensions enable row level security;
alter table atlas.flower_availability_outreach_commercial_distribution_extensions enable row level security;
alter table atlas.community_registration_commercial_offer_snapshot_extensions enable row level security;
revoke all on table atlas.flower_route_availability_commercial_offer_extensions from public,anon,authenticated;
revoke all on table atlas.flower_availability_outreach_commercial_distribution_extensions from public,anon,authenticated;
revoke all on table atlas.community_registration_commercial_offer_snapshot_extensions from public,anon,authenticated;
grant all on table atlas.flower_route_availability_commercial_offer_extensions to service_role;
grant all on table atlas.flower_availability_outreach_commercial_distribution_extensions to service_role;
grant all on table atlas.community_registration_commercial_offer_snapshot_extensions to service_role;

revoke all on function atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.ensure_community_registration_commercial_offer_snapshot_service_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.record_flower_availability_outreach_service_v2(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.ensure_flower_route_availability_commercial_offer_snapshot_service_v1(uuid) to service_role;
grant execute on function atlas.ensure_community_registration_commercial_offer_snapshot_service_v1(uuid) to service_role;
grant execute on function atlas.record_flower_availability_outreach_service_v2(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) to service_role;

commit;
