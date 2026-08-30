create table if not exists local_intel.business_census_query_families (
  stable_key text primary key,
  sort_order integer not null unique,
  label text not null,
  naics_scope text[] not null default '{}',
  search_queries text[] not null,
  status text not null default 'active' check (status in ('active','paused','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into local_intel.business_census_query_families(stable_key,sort_order,label,naics_scope,search_queries,metadata)
values
('agriculture',10,'Agriculture, forestry, fishing and hunting',array['11'],array['farms','agricultural services','feed stores','nurseries and greenhouses'],jsonb_build_object('naics_sector','11')),
('mining',20,'Mining, quarrying, oil and gas',array['21'],array['mining companies','quarries','oil and gas services'],jsonb_build_object('naics_sector','21')),
('utilities',30,'Utilities',array['22'],array['utility companies','electric utilities','water utilities','gas utilities'],jsonb_build_object('naics_sector','22')),
('construction',40,'Construction and trades',array['23'],array['construction companies','general contractors','plumbers','electricians','HVAC contractors','roofers'],jsonb_build_object('naics_sector','23')),
('manufacturing',50,'Manufacturing',array['31','32','33'],array['manufacturers','factories','fabrication shops','machine shops'],jsonb_build_object('naics_sectors',jsonb_build_array('31','32','33'))),
('wholesale',60,'Wholesale trade',array['42'],array['wholesalers','distributors','industrial suppliers','commercial supply companies'],jsonb_build_object('naics_sector','42')),
('retail',70,'Retail trade',array['44','45'],array['stores','retail shops','grocery stores','boutiques','hardware stores','specialty stores'],jsonb_build_object('naics_sectors',jsonb_build_array('44','45'))),
('transportation',80,'Transportation and warehousing',array['48','49'],array['trucking companies','transportation services','warehouses','couriers','towing companies'],jsonb_build_object('naics_sectors',jsonb_build_array('48','49'))),
('information',90,'Information and communications',array['51'],array['telecommunications companies','internet providers','publishers','media companies','software companies','IT services'],jsonb_build_object('naics_sector','51')),
('finance',100,'Finance and insurance',array['52'],array['banks','credit unions','insurance agencies','financial advisors','accounting firms'],jsonb_build_object('naics_sector','52')),
('real-estate',110,'Real estate, rental and leasing',array['53'],array['real estate companies','property management','rental companies','self storage','equipment rental'],jsonb_build_object('naics_sector','53')),
('professional',120,'Professional, scientific and technical services',array['54'],array['law firms','engineering firms','architects','consultants','marketing agencies','photographers','printing companies','screen printing','sign shops','veterinarians'],jsonb_build_object('naics_sector','54')),
('management',130,'Management of companies and enterprises',array['55'],array['management companies','holding companies','corporate offices'],jsonb_build_object('naics_sector','55')),
('administrative',140,'Administrative, support and waste services',array['56'],array['staffing agencies','janitorial services','landscaping companies','pest control','security companies','waste services'],jsonb_build_object('naics_sector','56')),
('education',150,'Educational services and childcare',array['61'],array['private schools','preschools','childcare','tutoring','music lessons','dance schools','training centers'],jsonb_build_object('naics_sector','61')),
('health',160,'Health care and social assistance',array['62'],array['doctors','dentists','medical clinics','therapy practices','chiropractors','pharmacies','home health','counseling services'],jsonb_build_object('naics_sector','62')),
('arts-recreation',170,'Arts, entertainment and recreation',array['71'],array['entertainment','gyms','fitness centers','theaters','bowling alleys','golf courses','recreation businesses'],jsonb_build_object('naics_sector','71')),
('food-lodging',180,'Accommodation and food services',array['72'],array['restaurants','cafes','coffee shops','caterers','hotels','motels','food trucks'],jsonb_build_object('naics_sector','72')),
('other-services',190,'Other services',array['81'],array['auto repair','salons','barbers','laundromats','repair services','funeral homes','pet groomers','personal services'],jsonb_build_object('naics_sector','81'))
on conflict (stable_key) do update
set sort_order=excluded.sort_order,label=excluded.label,naics_scope=excluded.naics_scope,search_queries=excluded.search_queries,status='active',metadata=excluded.metadata,updated_at=now();

create table if not exists local_intel.business_census_work_items (
  id uuid primary key default gen_random_uuid(),
  frame_id uuid not null references local_intel.market_census_frames(id) on delete cascade,
  denominator_source_candidate_id uuid not null references local_intel.market_census_source_candidates(id) on delete cascade,
  postal_code text not null,
  locality_label text not null,
  expected_paid_establishments integer not null check (expected_paid_establishments >= 0),
  query_family_key text not null references local_intel.business_census_query_families(stable_key),
  priority integer not null default 0,
  status text not null default 'queued' check (status in ('queued','in_process','complete','retry','blocked','held')),
  attempt_count integer not null default 0,
  observed_result_count integer not null default 0,
  matched_existing_count integer not null default 0,
  created_new_count integer not null default 0,
  review_count integer not null default 0,
  first_started_at timestamptz,
  last_started_at timestamptz,
  last_completed_at timestamptz,
  last_error text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(frame_id,postal_code,query_family_key)
);

create index if not exists business_census_work_queue_idx
  on local_intel.business_census_work_items(status,priority desc,expected_paid_establishments desc,postal_code,query_family_key);

create table if not exists local_intel.business_census_discovery_records (
  id uuid primary key default gen_random_uuid(),
  work_item_id uuid not null references local_intel.business_census_work_items(id) on delete cascade,
  discovery_fingerprint text not null,
  business_name text not null,
  address_line1 text,
  city text,
  state text,
  postal_code text,
  phone text,
  website_url text,
  category_text text,
  source_url text not null,
  source_title text,
  publisher text,
  source_kind text not null default 'business_search_result',
  source_id uuid references local_intel.sources(id) on delete set null,
  ingestion_source_id uuid references local_intel.ingestion_sources(id) on delete set null,
  ingestion_candidate_id uuid references local_intel.entity_ingestion_candidates(id) on delete set null,
  canonical_entity_id uuid references local_intel.entities(id) on delete set null,
  disposition text not null check (disposition in ('matched_existing','created_new','needs_review','duplicate','ignored')),
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(work_item_id,discovery_fingerprint)
);

create index if not exists business_census_discovery_entity_idx on local_intel.business_census_discovery_records(canonical_entity_id);
create index if not exists business_census_discovery_disposition_idx on local_intel.business_census_discovery_records(disposition,observed_at desc);

with frame as (
  select id from local_intel.market_census_frames where stable_key='elm-regional-80mi-paid-establishment-census-v1' and status='active' limit 1
), source_candidate as (
  select sc.id
  from local_intel.market_census_source_candidates sc
  join local_intel.market_census_cells c on c.id=sc.cell_id
  join frame f on f.id=c.frame_id
  where c.stable_key='paid-establishments-all-sectors'
    and sc.status='imported'
  order by sc.updated_at desc
  limit 1
), eligible_zip as (
  select i.source_geography_key as postal_code,
         i.source_geography_label as locality_label,
         i.native_count_sum::integer as expected_paid_establishments
  from local_intel.market_census_source_geography_inventory i
  join source_candidate sc on sc.id=i.source_candidate_id
  join frame f on true
  join local_intel.market_census_geography_crosswalks x
    on x.frame_id=f.id
   and x.source_geography_kind=i.source_geography_kind
   and x.source_geography_key=i.source_geography_key
  where i.inventory_state <> 'excluded'
    and x.is_current
    and x.adjudication_state='accepted'
    and coalesce(x.inclusion_share,0)>0
)
insert into local_intel.business_census_work_items(
  frame_id,denominator_source_candidate_id,postal_code,locality_label,expected_paid_establishments,query_family_key,priority,metadata
)
select f.id,sc.id,z.postal_code,z.locality_label,z.expected_paid_establishments,q.stable_key,
       (z.expected_paid_establishments * 1000) - q.sort_order,
       jsonb_build_object(
         'scope','all_publicly_discoverable_businesses',
         'denominator_role','paid_establishment_floor_not_identity_source',
         'geography_semantics','accepted_80mi_zcta_representative_point_proxy',
         'query_family_order',q.sort_order
       )
from frame f cross join source_candidate sc cross join eligible_zip z cross join local_intel.business_census_query_families q
where q.status='active'
on conflict (frame_id,postal_code,query_family_key) do update
set locality_label=excluded.locality_label,
    expected_paid_establishments=excluded.expected_paid_establishments,
    priority=excluded.priority,
    metadata=local_intel.business_census_work_items.metadata || excluded.metadata,
    updated_at=now();

create or replace function local_intel.claim_business_census_work_v1(p_limit integer default 8)
returns table(
  work_item_id uuid,
  postal_code text,
  locality_label text,
  expected_paid_establishments integer,
  query_family_key text,
  query_family_label text,
  search_queries text[],
  attempt_count integer
)
language plpgsql
security definer
set search_path=pg_catalog,local_intel
as $function$
begin
  return query
  with picked as (
    select w.id
    from local_intel.business_census_work_items w
    where w.status in ('queued','retry')
    order by w.priority desc,w.attempt_count asc,w.postal_code,w.query_family_key
    for update skip locked
    limit greatest(1,least(coalesce(p_limit,8),30))
  ), updated as (
    update local_intel.business_census_work_items w
       set status='in_process',
           attempt_count=w.attempt_count+1,
           first_started_at=coalesce(w.first_started_at,now()),
           last_started_at=now(),
           last_error=null,
           updated_at=now()
      from picked p
     where w.id=p.id
    returning w.*
  )
  select u.id,u.postal_code,u.locality_label,u.expected_paid_establishments,u.query_family_key,q.label,q.search_queries,u.attempt_count
  from updated u join local_intel.business_census_query_families q on q.stable_key=u.query_family_key
  order by u.priority desc,u.postal_code,u.query_family_key;
end;
$function$;

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

  select count(*),min(e.id) into v_match_count,v_entity_id
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
    select count(*),min(e.id) into v_name_city_count,v_entity_id
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

create or replace function local_intel.complete_business_census_work_v1(p_work_item_id uuid,p_success boolean default true,p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,local_intel
as $function$
declare v_row local_intel.business_census_work_items%rowtype;
begin
  update local_intel.business_census_work_items
     set status=case when p_success then 'complete' else 'retry' end,
         last_completed_at=case when p_success then now() else last_completed_at end,
         last_error=case when p_success then null else left(coalesce(p_error,'unspecified error'),2000) end,
         updated_at=now()
   where id=p_work_item_id
   returning * into v_row;
  if not found then raise exception 'Business census work item % not found',p_work_item_id; end if;
  return jsonb_build_object('work_item_id',v_row.id,'status',v_row.status,'observed_result_count',v_row.observed_result_count,'matched_existing_count',v_row.matched_existing_count,'created_new_count',v_row.created_new_count,'review_count',v_row.review_count);
end;
$function$;

create or replace view local_intel.v_business_census_progress_v1 as
with zip_state as (
  select frame_id,postal_code,max(locality_label) as locality_label,max(expected_paid_establishments) as expected_paid_establishments,
         count(*) as family_count,
         count(*) filter (where status='complete') as completed_family_count,
         count(*) filter (where status='in_process') as in_process_family_count,
         count(*) filter (where status in ('queued','retry')) as remaining_family_count,
         sum(observed_result_count) as observed_result_count,
         sum(matched_existing_count) as matched_existing_count,
         sum(created_new_count) as created_new_count,
         sum(review_count) as review_count
  from local_intel.business_census_work_items
  group by frame_id,postal_code
)
select f.stable_key as frame_key,
       count(*) as postal_codes_in_scope,
       sum(z.expected_paid_establishments)::bigint as modeled_paid_establishment_floor,
       count(*) filter (where z.completed_family_count=z.family_count) as postal_codes_fully_enumerated,
       sum(z.completed_family_count)::bigint as completed_query_families,
       sum(z.family_count)::bigint as total_query_families,
       sum(z.remaining_family_count)::bigint as remaining_query_families,
       sum(z.in_process_family_count)::bigint as in_process_query_families,
       sum(z.observed_result_count)::bigint as observed_business_results,
       sum(z.matched_existing_count)::bigint as matched_existing_results,
       sum(z.created_new_count)::bigint as created_new_businesses,
       sum(z.review_count)::bigint as identity_reviews_required,
       (select count(*) from local_intel.entities e where e.entity_type='business' and e.status<>'inactive')::bigint as current_active_business_entities,
       now() as observed_at
from zip_state z join local_intel.market_census_frames f on f.id=z.frame_id
group by f.stable_key;

revoke all on function local_intel.claim_business_census_work_v1(integer) from public,anon,authenticated;
revoke all on function local_intel.record_business_census_discovery_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function local_intel.complete_business_census_work_v1(uuid,boolean,text) from public,anon,authenticated;
grant execute on function local_intel.claim_business_census_work_v1(integer) to service_role;
grant execute on function local_intel.record_business_census_discovery_v1(uuid,jsonb) to service_role;
grant execute on function local_intel.complete_business_census_work_v1(uuid,boolean,text) to service_role;

comment on table local_intel.business_census_work_items is 'Durable executor queue for the original Elm Local all-business census across the governed 80-mile market. County Business Patterns supplies a paid-establishment completeness floor only; it is never used as named identity evidence.';
comment on function local_intel.record_business_census_discovery_v1(uuid,jsonb) is 'Ingests one publicly discovered named business into governed Local Intel identity custody. Strong deterministic identity matches attach evidence to an existing entity; ambiguous same-name/locality cases route to review; otherwise a public_indexed canonical business is created. This function never asserts current availability.';