create or replace function local_intel.record_business_census_discovery_v1(p_work_item_id uuid,p_record jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,local_intel
as $function$
declare
  v_work local_intel.business_census_work_items%rowtype;
  v_name text;
  v_address text;
  v_city text;
  v_state text;
  v_postal text;
  v_phone text;
  v_phone_norm text;
  v_website text;
  v_category text;
  v_source_url text;
  v_source_title text;
  v_publisher text;
  v_source_kind text;
  v_fingerprint text;
  v_source_id uuid;
  v_ingestion_source_id uuid;
  v_candidate_id uuid;
  v_entity_id uuid;
  v_match_count integer;
  v_name_city_count integer;
  v_disposition text;
  v_stable_key text;
begin
  select * into v_work from local_intel.business_census_work_items where id=p_work_item_id for update;
  if not found then raise exception 'Business census work item % not found',p_work_item_id; end if;
  if v_work.status not in ('in_process','queued','retry') then
    raise exception 'Business census work item % is in status %',p_work_item_id,v_work.status;
  end if;

  v_name:=nullif(btrim(coalesce(p_record->>'name','')),'');
  if v_name is null then raise exception 'Business census discovery requires name'; end if;
  v_address:=nullif(btrim(coalesce(p_record->>'address_line1','')),'');
  v_city:=coalesce(nullif(btrim(p_record->>'city'),''),split_part(v_work.locality_label,',',1));
  v_state:=upper(coalesce(nullif(btrim(p_record->>'state'),''),nullif(btrim(split_part(v_work.locality_label,',',2)),'')));
  v_postal:=coalesce(nullif(btrim(p_record->>'postal_code'),''),v_work.postal_code);
  v_phone:=nullif(btrim(coalesce(p_record->>'phone','')),'');
  v_phone_norm:=regexp_replace(coalesce(v_phone,''),'[^0-9]','','g');
  v_website:=nullif(btrim(coalesce(p_record->>'website_url','')),'');
  v_category:=nullif(btrim(coalesce(p_record->>'category','')),'');
  v_source_title:=coalesce(nullif(btrim(p_record->>'source_title'),''),v_name || ' business census discovery');
  v_publisher:=coalesce(nullif(btrim(p_record->>'publisher'),''),'Elm Local public business discovery');
  v_source_kind:=coalesce(nullif(btrim(p_record->>'source_kind'),''),'business_search_result');
  v_fingerprint:=md5(lower(v_name)||'|'||lower(coalesce(v_address,''))||'|'||v_postal||'|'||v_phone_norm||'|'||lower(coalesce(v_website,'')));
  v_source_url:=coalesce(nullif(btrim(p_record->>'source_url'),''),'noel://local-intel/business-census/discovery/'||v_fingerprint);

  select id into v_source_id from local_intel.sources where source_url=v_source_url;
  if v_source_id is null then
    insert into local_intel.sources(source_url,source_kind,publisher,title,retrieved_at,notes,metadata)
    values(v_source_url,v_source_kind,v_publisher,v_source_title,now(),'Elm Local business census durable identity/category discovery; does not establish current availability.',
      jsonb_build_object('business_census',true,'work_item_id',p_work_item_id,'query_family',v_work.query_family_key,'raw',coalesce(p_record->'raw','{}'::jsonb)))
    returning id into v_source_id;
  end if;

  select id into v_ingestion_source_id
  from local_intel.ingestion_sources
  where source_id=v_source_id and source_role='organization_directory';
  if v_ingestion_source_id is null then
    insert into local_intel.ingestion_sources(source_id,source_role,status,ingestion_priority,last_ingested_at,metadata)
    values(v_source_id,'organization_directory','active',95,now(),jsonb_build_object('business_census',true,'work_item_id',p_work_item_id))
    returning id into v_ingestion_source_id;
  end if;

  insert into local_intel.entity_ingestion_candidates(
    ingestion_source_id,source_record_key,proposed_entity_type,proposed_name,website_url,phone,address_line1,city,state,postal_code,category_text,confidence,review_state,metadata
  ) values(
    v_ingestion_source_id,v_fingerprint,'business',v_name,v_website,v_phone,v_address,v_city,v_state,v_postal,v_category,0.85,'pending',
    jsonb_build_object('business_census',true,'work_item_id',p_work_item_id,'query_family',v_work.query_family_key,'source_id',v_source_id)
  )
  on conflict (ingestion_source_id,source_record_key) do update
  set website_url=coalesce(excluded.website_url,local_intel.entity_ingestion_candidates.website_url),
      phone=coalesce(excluded.phone,local_intel.entity_ingestion_candidates.phone),
      address_line1=coalesce(excluded.address_line1,local_intel.entity_ingestion_candidates.address_line1),
      city=coalesce(excluded.city,local_intel.entity_ingestion_candidates.city),
      state=coalesce(excluded.state,local_intel.entity_ingestion_candidates.state),
      postal_code=coalesce(excluded.postal_code,local_intel.entity_ingestion_candidates.postal_code),
      category_text=coalesce(excluded.category_text,local_intel.entity_ingestion_candidates.category_text),
      metadata=local_intel.entity_ingestion_candidates.metadata||excluded.metadata,
      updated_at=now()
  returning id into v_candidate_id;

  select count(*),(array_agg(e.id order by e.id::text))[1] into v_match_count,v_entity_id
  from local_intel.entities e
  where e.entity_type='business'
    and e.status <> 'inactive'
    and (
      (v_phone_norm<>'' and regexp_replace(coalesce(e.phone,''),'[^0-9]','','g')=v_phone_norm)
      or (v_address is not null and lower(btrim(e.name))=lower(btrim(v_name)) and lower(regexp_replace(coalesce(e.address_line1,''),'[^a-zA-Z0-9]','','g'))=lower(regexp_replace(v_address,'[^a-zA-Z0-9]','','g')))
    );

  if v_match_count=1 then
    v_disposition:='matched_existing';
    update local_intel.entity_ingestion_candidates set review_state='matched_existing',matched_entity_id=v_entity_id,updated_at=now() where id=v_candidate_id;
    insert into local_intel.entity_sources(entity_id,source_id,relation_kind) values(v_entity_id,v_source_id,'evidence') on conflict do nothing;
    update local_intel.entities
       set website_url=coalesce(website_url,v_website),phone=coalesce(phone,v_phone),address_line1=coalesce(address_line1,v_address),city=coalesce(city,v_city),state=coalesce(state,v_state),postal_code=coalesce(postal_code,v_postal),last_verified_at=greatest(coalesce(last_verified_at,'epoch'::timestamptz),now()),updated_at=now()
     where id=v_entity_id;
    update local_intel.business_census_work_items set matched_existing_count=matched_existing_count+1,updated_at=now() where id=p_work_item_id;
  else
    select count(*),(array_agg(e.id order by e.id::text))[1] into v_name_city_count,v_entity_id
    from local_intel.entities e
    where e.entity_type='business' and e.status<>'inactive'
      and lower(btrim(e.name))=lower(btrim(v_name))
      and lower(btrim(coalesce(e.city,'')))=lower(btrim(coalesce(v_city,'')));

    if v_match_count>1 or v_name_city_count>0 then
      v_disposition:='needs_review';
      update local_intel.entity_ingestion_candidates
         set review_state='needs_review',
             resolver_recommended_entity_id=case when v_name_city_count=1 then v_entity_id else null end,
             resolver_recommendation_state=case when v_name_city_count=1 then 'review_candidate' else null end,
             resolver_algorithm_key='business_census_identity_v1',
             resolver_algorithm_version='1',
             resolver_recommendation_basis='Same normalized business name and locality requires identity adjudication before merge.',
             resolver_recommendation_evidence=jsonb_build_object('name',v_name,'city',v_city,'postal_code',v_postal,'phone',v_phone,'address',v_address),
             resolver_recommended_at=now(),updated_at=now()
       where id=v_candidate_id;
      update local_intel.business_census_work_items set review_count=review_count+1,updated_at=now() where id=p_work_item_id;
      v_entity_id:=null;
    else
      v_stable_key:='census-'||left(trim(both '-' from regexp_replace(lower(v_name),'[^a-z0-9]+','-','g')),60)||'-'||left(v_fingerprint,10);
      insert into local_intel.entities(stable_key,entity_type,name,website_url,phone,address_line1,city,state,postal_code,status,verification_state,last_verified_at,metadata)
      values(v_stable_key,'business',v_name,v_website,v_phone,v_address,v_city,v_state,v_postal,'active','public_indexed',now(),
        jsonb_build_object('business_census',true,'identity_basis','publicly indexed named business discovery','first_census_source_id',v_source_id,'query_family',v_work.query_family_key))
      returning id into v_entity_id;
      update local_intel.entity_ingestion_candidates set review_state='promoted',matched_entity_id=v_entity_id,updated_at=now() where id=v_candidate_id;
      insert into local_intel.entity_sources(entity_id,source_id,relation_kind) values(v_entity_id,v_source_id,'evidence') on conflict do nothing;
      update local_intel.business_census_work_items set created_new_count=created_new_count+1,updated_at=now() where id=p_work_item_id;
      v_disposition:='created_new';
    end if;
  end if;

  insert into local_intel.business_census_discovery_records(
    work_item_id,discovery_fingerprint,business_name,address_line1,city,state,postal_code,phone,website_url,category_text,source_url,source_title,publisher,source_kind,source_id,ingestion_source_id,ingestion_candidate_id,canonical_entity_id,disposition,metadata
  ) values(
    p_work_item_id,v_fingerprint,v_name,v_address,v_city,v_state,v_postal,v_phone,v_website,v_category,v_source_url,v_source_title,v_publisher,v_source_kind,v_source_id,v_ingestion_source_id,v_candidate_id,v_entity_id,v_disposition,
    jsonb_build_object('raw',coalesce(p_record->'raw','{}'::jsonb))
  ) on conflict (work_item_id,discovery_fingerprint) do update
    set source_id=excluded.source_id,ingestion_source_id=excluded.ingestion_source_id,ingestion_candidate_id=excluded.ingestion_candidate_id,canonical_entity_id=coalesce(excluded.canonical_entity_id,local_intel.business_census_discovery_records.canonical_entity_id),disposition=excluded.disposition,observed_at=now(),updated_at=now(),metadata=local_intel.business_census_discovery_records.metadata||excluded.metadata;

  update local_intel.business_census_work_items set observed_result_count=observed_result_count+1,updated_at=now() where id=p_work_item_id;
  return jsonb_build_object('work_item_id',p_work_item_id,'disposition',v_disposition,'entity_id',v_entity_id,'candidate_id',v_candidate_id,'source_id',v_source_id);
end;
$function$;

revoke all on function local_intel.record_business_census_discovery_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function local_intel.record_business_census_discovery_v1(uuid,jsonb) to service_role;