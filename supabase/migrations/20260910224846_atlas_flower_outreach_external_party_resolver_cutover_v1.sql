begin;

create or replace function atlas.record_flower_availability_outreach_service_v1(
  p_farm_id uuid,
  p_round_key text,
  p_sent_at timestamptz,
  p_subject text,
  p_body text,
  p_recipients jsonb,
  p_availability_snapshot_id uuid default null,
  p_sender_label text default null,
  p_sender_address text default null,
  p_source_kind text default 'manual_report',
  p_source_ref text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_farm atlas.farms%rowtype;
  v_round_id uuid;
  v_existing_hash text;
  v_body_hash text;
  v_recipient jsonb;
  v_email text;
  v_display_name text;
  v_source_label text;
  v_recipient_role text;
  v_relationship_id uuid;
  v_subject_id uuid;
  v_buyer_relationship_id uuid;
  v_local_intel_entity_id uuid;
  v_source_record_key text;
  v_source_record_id uuid;
  v_identifiers jsonb;
  v_resolution jsonb;
  v_resolutions jsonb:='{}'::jsonb;
  v_pending jsonb:='[]'::jsonb;
  v_state text;
  v_interaction_id uuid;
  v_recipient_count integer:=0;
begin
  select * into v_farm from atlas.farms where id=p_farm_id;
  if v_farm.id is null or v_farm.organization_id is null then raise exception 'Farm with organization scope is required.' using errcode='P0002'; end if;
  if btrim(coalesce(p_round_key,''))='' or btrim(coalesce(p_subject,''))='' then raise exception 'Round key and subject are required.' using errcode='22023'; end if;
  if p_body is null then raise exception 'Exact email body is required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_recipients,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_recipients,'[]'::jsonb))=0 then raise exception 'Recipients must be a non-empty JSON array.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Metadata must be a JSON object.' using errcode='22023'; end if;
  if p_availability_snapshot_id is not null and not exists(select 1 from atlas.flower_route_availability_snapshots s where s.id=p_availability_snapshot_id and s.farm_id=p_farm_id) then raise exception 'Availability snapshot is outside this farm.' using errcode='23514'; end if;

  if exists(select 1 from (select lower(btrim(value->>'email')) email,count(*) n from jsonb_array_elements(p_recipients) group by lower(btrim(value->>'email')) having count(*)>1) d where d.email<>'') then raise exception 'Availability outreach recipient emails must be unique within a round.' using errcode='23505'; end if;

  v_body_hash:=encode(extensions.digest(convert_to(p_body,'UTF8'),'sha256'),'hex');
  select id,body_sha256 into v_round_id,v_existing_hash from atlas.flower_availability_outreach_rounds where farm_id=p_farm_id and round_key=btrim(p_round_key);
  if v_round_id is not null then
    if v_existing_hash is distinct from v_body_hash then raise exception 'Round key already exists with different email content.' using errcode='23505'; end if;
    return jsonb_build_object('outreachRoundId',v_round_id,'created',false,'state','recorded','recipientCount',(select count(*) from atlas.flower_availability_outreach_recipients r where r.outreach_round_id=v_round_id));
  end if;

  for v_recipient in select value from jsonb_array_elements(p_recipients) loop
    v_email:=lower(btrim(coalesce(v_recipient->>'email','')));
    if v_email='' then raise exception 'Every availability outreach recipient requires an email address.' using errcode='22023'; end if;
    v_display_name:=nullif(btrim(v_recipient->>'displayName'),'');
    v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),'');
    v_recipient_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'to'));
    if v_recipient_role not in ('to','cc','bcc') then raise exception 'recipientRole must be to, cc, or bcc.' using errcode='22023'; end if;

    v_relationship_id:=null; v_subject_id:=null; v_buyer_relationship_id:=null; v_local_intel_entity_id:=null;
    begin v_relationship_id:=nullif(btrim(v_recipient->>'externalRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid externalRelationshipId for recipient %.',v_email using errcode='22023'; end;
    begin v_buyer_relationship_id:=nullif(btrim(v_recipient->>'buyerRelationshipId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid buyerRelationshipId for recipient %.',v_email using errcode='22023'; end;
    begin v_local_intel_entity_id:=nullif(btrim(v_recipient->>'localIntelEntityId'),'')::uuid; exception when invalid_text_representation then raise exception 'Invalid localIntelEntityId for recipient %.',v_email using errcode='22023'; end;

    if v_relationship_id is null and v_buyer_relationship_id is not null then
      select m.external_relationship_id,m.identity_subject_id into v_relationship_id,v_subject_id from atlas.legacy_buyer_relationship_external_mappings m join atlas.buyer_relationship_reconstruction b on b.id=m.buyer_relationship_id where m.buyer_relationship_id=v_buyer_relationship_id and b.farm_id=p_farm_id;
      if v_relationship_id is null then raise exception 'buyerRelationshipId is not an Elm buyer relationship for recipient %.',v_email using errcode='23514'; end if;
    end if;

    v_source_record_key:='round:'||btrim(p_round_key)||':recipient:'||v_email;
    if v_relationship_id is not null then
      select r.subject_id into v_subject_id from atlas.external_relationships r where r.id=v_relationship_id and r.organization_id=v_farm.organization_id and r.organization_unit_id is not distinct from v_farm.organization_unit_id;
      if v_subject_id is null then raise exception 'Recipient relationship is outside the farm organization/unit for %.',v_email using errcode='23514'; end if;
      insert into atlas.identity_source_records(organization_id,source_system_key,source_record_kind,source_record_key,source_observed_at,source_authority,custody_ref,metadata)
      values(v_farm.organization_id,'flower_availability_outreach','recipient',v_source_record_key,p_sent_at,'evidence_only',jsonb_build_object('farmId',v_farm.id,'roundKey',btrim(p_round_key),'recipientEmail',v_email),jsonb_build_object('externalRelationshipId',v_relationship_id,'buyerRelationshipId',v_buyer_relationship_id,'sourceLabel',v_source_label))
      on conflict (organization_id,source_system_key,source_record_kind,source_record_key) do nothing;
      select id into v_source_record_id from atlas.identity_source_records where organization_id=v_farm.organization_id and source_system_key='flower_availability_outreach' and source_record_kind='recipient' and source_record_key=v_source_record_key;
      insert into atlas.identity_source_subject_assertions(organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key)
      values(v_farm.organization_id,v_source_record_id,v_subject_id,'supports',1,'Caller supplied an established Atlas relationship/buyer mapping for this recipient.','flower-outreach-explicit:'||v_source_record_id::text||':'||v_subject_id::text)
      on conflict (organization_id,idempotency_key) where idempotency_key is not null do nothing;
    end if;

    v_identifiers:=jsonb_build_array(jsonb_build_object('type','email','value',v_email,'normalized',v_email,'identityScoped',true));
    if v_local_intel_entity_id is not null then v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object('providerKey','local_intel','type','entity_id','value',v_local_intel_entity_id::text,'normalized',v_local_intel_entity_id::text,'identityScoped',true)); end if;

    v_resolution:=atlas.resolve_external_relationship_service_v1(p_organization_id=>v_farm.organization_id,p_organization_unit_id=>v_farm.organization_unit_id,p_role_key=>'customer',p_display_name=>v_display_name,p_subject_kind=>'organization',p_identifiers=>v_identifiers,p_source_system_key=>'flower_availability_outreach',p_source_record_kind=>'recipient',p_source_record_key=>v_source_record_key,p_source_observed_at=>p_sent_at,p_source_authority=>'evidence_only',p_custody_ref=>jsonb_build_object('farmId',v_farm.id,'roundKey',btrim(p_round_key),'recipientEmail',v_email),p_basis=>jsonb_build_object('sourceLabel',v_source_label,'buyerRelationshipId',v_buyer_relationship_id,'localIntelEntityId',v_local_intel_entity_id)||coalesce(v_recipient->'metadata','{}'::jsonb),p_allow_create=>false,p_new_relationship_state=>'prospective');
    v_state:=v_resolution->>'state';
    if v_state in ('identity_review_required','relationship_inactive','relationship_role_inactive','resolved_with_identifier_conflict') then
      v_pending:=v_pending||jsonb_build_array(jsonb_build_object('email',v_email,'displayName',v_display_name,'state',v_state,'resolution',v_resolution));
    else
      v_resolutions:=jsonb_set(v_resolutions,array[v_email],v_resolution,true);
    end if;
  end loop;

  if jsonb_array_length(v_pending)>0 then
    return jsonb_build_object('state','identity_review_required','outreachRoundId',null,'created',false,'pendingCount',jsonb_array_length(v_pending),'pending',v_pending,'message','No outreach round was created. Resolve the identity/relationship items, then retry the same round key.');
  end if;

  for v_recipient in select value from jsonb_array_elements(p_recipients) loop
    v_email:=lower(btrim(v_recipient->>'email')); v_resolution:=v_resolutions->v_email; v_state:=v_resolution->>'state';
    if v_state in ('no_match','matched_subject_no_relationship','matched_relationship_without_role') then
      v_display_name:=nullif(btrim(v_recipient->>'displayName'),''); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),'');
      begin v_buyer_relationship_id:=nullif(btrim(v_recipient->>'buyerRelationshipId'),'')::uuid; exception when invalid_text_representation then v_buyer_relationship_id:=null; end;
      begin v_local_intel_entity_id:=nullif(btrim(v_recipient->>'localIntelEntityId'),'')::uuid; exception when invalid_text_representation then v_local_intel_entity_id:=null; end;
      v_identifiers:=jsonb_build_array(jsonb_build_object('type','email','value',v_email,'normalized',v_email,'identityScoped',true));
      if v_local_intel_entity_id is not null then v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object('providerKey','local_intel','type','entity_id','value',v_local_intel_entity_id::text,'normalized',v_local_intel_entity_id::text,'identityScoped',true)); end if;
      v_source_record_key:='round:'||btrim(p_round_key)||':recipient:'||v_email;
      v_resolution:=atlas.resolve_external_relationship_service_v1(p_organization_id=>v_farm.organization_id,p_organization_unit_id=>v_farm.organization_unit_id,p_role_key=>'customer',p_display_name=>v_display_name,p_subject_kind=>'organization',p_identifiers=>v_identifiers,p_source_system_key=>'flower_availability_outreach',p_source_record_kind=>'recipient',p_source_record_key=>v_source_record_key,p_source_observed_at=>p_sent_at,p_source_authority=>'evidence_only',p_custody_ref=>jsonb_build_object('farmId',v_farm.id,'roundKey',btrim(p_round_key),'recipientEmail',v_email),p_basis=>jsonb_build_object('sourceLabel',v_source_label,'buyerRelationshipId',v_buyer_relationship_id,'localIntelEntityId',v_local_intel_entity_id)||coalesce(v_recipient->'metadata','{}'::jsonb),p_allow_create=>true,p_new_relationship_state=>'prospective');
      if v_resolution->>'state'<>'resolved' then return jsonb_build_object('state','identity_resolution_blocked','outreachRoundId',null,'created',false,'email',v_email,'resolution',v_resolution,'message','No outreach round was created. Resolve this relationship state and retry.'); end if;
      v_resolutions:=jsonb_set(v_resolutions,array[v_email],v_resolution,true);
    end if;
  end loop;

  insert into atlas.flower_availability_outreach_rounds(organization_id,organization_unit_id,farm_id,availability_snapshot_id,round_key,channel,sender_label,sender_address,subject,body_text,body_sha256,sent_at,source_kind,source_ref,metadata)
  values(v_farm.organization_id,v_farm.organization_unit_id,v_farm.id,p_availability_snapshot_id,btrim(p_round_key),'email',nullif(btrim(p_sender_label),''),nullif(lower(btrim(p_sender_address)),''),btrim(p_subject),p_body,v_body_hash,p_sent_at,lower(btrim(coalesce(nullif(p_source_kind,''),'manual_report'))),nullif(btrim(p_source_ref),''),coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('identityResolver','resolve_external_relationship_service_v1')) returning id into v_round_id;

  for v_recipient in select value from jsonb_array_elements(p_recipients) loop
    v_email:=lower(btrim(v_recipient->>'email')); v_display_name:=nullif(btrim(v_recipient->>'displayName'),''); v_source_label:=nullif(btrim(v_recipient->>'sourceLabel'),''); v_recipient_role:=lower(coalesce(nullif(btrim(v_recipient->>'recipientRole'),''),'to'));
    v_resolution:=v_resolutions->v_email; v_relationship_id:=(v_resolution->>'externalRelationshipId')::uuid; v_subject_id:=(v_resolution->>'subjectId')::uuid;
    insert into atlas.external_relationship_interactions(organization_id,organization_unit_id,external_relationship_id,occurred_at,interaction_kind,channel,outcome,contact_label,follow_up,note,metadata)
    values(v_farm.organization_id,v_farm.organization_unit_id,v_relationship_id,p_sent_at,'availability_offer_sent','email','sent',coalesce(v_display_name,v_email),null,btrim(p_subject),jsonb_build_object('direction','outgoing','flowerAvailabilityOutreachRoundId',v_round_id,'availabilitySnapshotId',p_availability_snapshot_id,'recipientAddress',v_email,'bodySha256',v_body_hash,'sourceLabel',v_source_label,'identitySourceRecordId',v_resolution->>'sourceRecordId')||coalesce(v_recipient->'metadata','{}'::jsonb)) returning id into v_interaction_id;
    insert into atlas.flower_availability_outreach_recipients(outreach_round_id,external_relationship_id,identity_subject_id,interaction_id,recipient_address,recipient_address_normalized,recipient_role,source_label,metadata)
    values(v_round_id,v_relationship_id,v_subject_id,v_interaction_id,v_email,v_email,v_recipient_role,v_source_label,coalesce(v_recipient->'metadata','{}'::jsonb)||jsonb_build_object('identitySourceRecordId',v_resolution->>'sourceRecordId','identityMatchState',v_resolution->>'matchState'));
    v_recipient_count:=v_recipient_count+1;
  end loop;
  return jsonb_build_object('state','recorded','outreachRoundId',v_round_id,'created',true,'recipientCount',v_recipient_count,'bodySha256',v_body_hash);
end;
$function$;

comment on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) is
  'Records one exact flower availability email only after each recipient is resolved through the universal external relationship resolver. Known buyer mappings are preserved, ambiguous/weak candidates open identity review, and new prospective relationships are created only after the no-match pass succeeds.';
revoke all on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_flower_availability_outreach_service_v1(uuid,text,timestamptz,text,text,jsonb,uuid,text,text,text,text,jsonb) to service_role;

commit;
