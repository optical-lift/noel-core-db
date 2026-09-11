alter table local_intel.business_census_work_items
  add column if not exists local_context_id uuid;

update local_intel.business_census_work_items w
set local_context_id = mo.local_context_id
from local_intel.market_census_frames f
join local_intel.market_origins mo on mo.id=f.market_origin_id
where w.frame_id=f.id and w.local_context_id is null;

alter table local_intel.business_census_work_items alter column local_context_id set not null;
alter table local_intel.business_census_work_items drop constraint if exists business_census_work_items_local_context_fk;
alter table local_intel.business_census_work_items add constraint business_census_work_items_local_context_fk foreign key(local_context_id) references local_intel.local_contexts(id) on delete restrict;
create index if not exists business_census_work_items_context_queue_idx on local_intel.business_census_work_items(local_context_id,status,priority desc,attempt_count);

create or replace function local_intel.stamp_business_census_work_context_v1()
returns trigger language plpgsql set search_path to 'local_intel','pg_catalog' as $$
declare v_context uuid;
begin
  select mo.local_context_id into v_context
  from local_intel.market_census_frames f join local_intel.market_origins mo on mo.id=f.market_origin_id
  where f.id=new.frame_id;
  if v_context is null then raise exception 'business census frame has no Local context'; end if;
  if new.local_context_id is null then new.local_context_id:=v_context;
  elsif new.local_context_id<>v_context then raise exception 'business census work item Local context must match frame Local context';
  end if;
  return new;
end $$;

drop trigger if exists business_census_work_context_stamp_v1 on local_intel.business_census_work_items;
create trigger business_census_work_context_stamp_v1 before insert or update of frame_id,local_context_id on local_intel.business_census_work_items for each row execute function local_intel.stamp_business_census_work_context_v1();

-- Compatibility RPC: safe only while there is one active Local.
create or replace function local_intel.claim_business_census_work_v1(p_limit integer default 8)
returns table(work_item_id uuid, postal_code text, locality_label text, expected_paid_establishments integer, query_family_key text, query_family_label text, search_queries text[], attempt_count integer)
language plpgsql security definer set search_path to 'pg_catalog','local_intel' as $$
declare v_context uuid; v_count integer;
begin
  select count(*),min(id::text)::uuid into v_count,v_context from local_intel.local_contexts where status='active';
  if v_count<>1 or v_context is null then raise exception 'claim_business_census_work_v1 requires exactly one active Local; use v2 with local_context_id'; end if;
  return query
  with picked as (
    select w.id from local_intel.business_census_work_items w
    where w.local_context_id=v_context and w.status in ('queued','retry')
    order by w.priority desc,w.attempt_count asc,w.postal_code,w.query_family_key
    for update skip locked limit greatest(1,least(coalesce(p_limit,8),30))
  ), updated as (
    update local_intel.business_census_work_items w set status='in_process',attempt_count=w.attempt_count+1,
      first_started_at=coalesce(w.first_started_at,now()),last_started_at=now(),last_error=null,updated_at=now()
    from picked p where w.id=p.id returning w.*
  )
  select u.id,u.postal_code,u.locality_label,u.expected_paid_establishments,u.query_family_key,q.label,q.search_queries,u.attempt_count
  from updated u join local_intel.business_census_query_families q on q.stable_key=u.query_family_key
  order by u.priority desc,u.postal_code,u.query_family_key;
end $$;

create or replace function local_intel.claim_business_census_work_v2(p_local_context_id uuid,p_limit integer default 8)
returns table(work_item_id uuid, postal_code text, locality_label text, expected_paid_establishments integer, query_family_key text, query_family_label text, search_queries text[], attempt_count integer)
language plpgsql security definer set search_path to 'pg_catalog','local_intel' as $$
begin
  if not exists(select 1 from local_intel.local_contexts where id=p_local_context_id and status='active') then raise exception 'active local_context_id is required'; end if;
  return query
  with picked as (
    select w.id from local_intel.business_census_work_items w
    where w.local_context_id=p_local_context_id and w.status in ('queued','retry')
    order by w.priority desc,w.attempt_count asc,w.postal_code,w.query_family_key
    for update skip locked limit greatest(1,least(coalesce(p_limit,8),30))
  ), updated as (
    update local_intel.business_census_work_items w set status='in_process',attempt_count=w.attempt_count+1,
      first_started_at=coalesce(w.first_started_at,now()),last_started_at=now(),last_error=null,updated_at=now()
    from picked p where w.id=p.id returning w.*
  )
  select u.id,u.postal_code,u.locality_label,u.expected_paid_establishments,u.query_family_key,q.label,q.search_queries,u.attempt_count
  from updated u join local_intel.business_census_query_families q on q.stable_key=u.query_family_key
  order by u.priority desc,u.postal_code,u.query_family_key;
end $$;
