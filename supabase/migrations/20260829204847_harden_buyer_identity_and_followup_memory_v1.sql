-- Keep identity resolution current as buyer/contact facts arrive.
create or replace function atlas.sync_buyer_identity_from_relationship_v1()
returns trigger
language plpgsql
security definer
set search_path=atlas,public
as $$
begin
  if new.business_name is not null and trim(new.business_name) <> '' then
    insert into atlas.buyer_identity_aliases
      (farm_id,buyer_relationship_id,alias,alias_type,priority,metadata)
    values
      (new.farm_id,new.id,new.business_name,'business_name',1,jsonb_build_object('source','buyer_relationship_reconstruction'))
    on conflict (farm_id,buyer_relationship_id,alias_normalized)
    do update set alias=excluded.alias,is_current=true,priority=least(atlas.buyer_identity_aliases.priority,excluded.priority),updated_at=now();
  end if;

  if new.primary_contact_name is not null and trim(new.primary_contact_name) <> '' then
    insert into atlas.buyer_identity_aliases
      (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
    values
      (new.farm_id,new.id,new.primary_contact_name,'person_name',new.primary_contact_name,'current contact',1,jsonb_build_object('source','buyer_relationship_reconstruction.primary_contact_name'))
    on conflict (farm_id,buyer_relationship_id,alias_normalized)
    do update set alias=excluded.alias,contact_name=excluded.contact_name,contact_role=excluded.contact_role,is_current=true,priority=least(atlas.buyer_identity_aliases.priority,excluded.priority),updated_at=now();
  end if;

  if new.metadata ? 'contact_email' and nullif(trim(new.metadata->>'contact_email'),'') is not null then
    insert into atlas.buyer_identity_aliases
      (farm_id,buyer_relationship_id,alias,alias_type,priority,metadata)
    values
      (new.farm_id,new.id,new.metadata->>'contact_email','email',1,jsonb_build_object('source','buyer_relationship_reconstruction.metadata.contact_email'))
    on conflict (farm_id,buyer_relationship_id,alias_normalized)
    do update set alias=excluded.alias,is_current=true,priority=least(atlas.buyer_identity_aliases.priority,excluded.priority),updated_at=now();
  end if;

  return new;
end;
$$;

drop trigger if exists sync_buyer_identity_from_relationship_v1 on atlas.buyer_relationship_reconstruction;
create trigger sync_buyer_identity_from_relationship_v1
after insert or update of business_name,primary_contact_name,metadata
on atlas.buyer_relationship_reconstruction
for each row execute function atlas.sync_buyer_identity_from_relationship_v1();

create or replace function atlas.sync_buyer_identity_from_contact_event_v1()
returns trigger
language plpgsql
security definer
set search_path=atlas,public
as $$
begin
  if new.contact_name is not null and trim(new.contact_name) <> '' then
    insert into atlas.buyer_identity_aliases
      (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
    values
      (new.farm_id,new.buyer_relationship_id,new.contact_name,'person_name',new.contact_name,'contact',2,jsonb_build_object('source','buyer_contact_event','source_contact_event_id',new.id))
    on conflict (farm_id,buyer_relationship_id,alias_normalized)
    do update set alias=excluded.alias,contact_name=excluded.contact_name,is_current=true,priority=least(atlas.buyer_identity_aliases.priority,excluded.priority),metadata=atlas.buyer_identity_aliases.metadata || excluded.metadata,updated_at=now();
  end if;
  return new;
end;
$$;

drop trigger if exists sync_buyer_identity_from_contact_event_v1 on atlas.buyer_contact_events;
create trigger sync_buyer_identity_from_contact_event_v1
after insert or update of contact_name
on atlas.buyer_contact_events
for each row execute function atlas.sync_buyer_identity_from_contact_event_v1();

-- Backfill all known business names, current contacts, and structured contact emails.
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,priority,metadata)
select farm_id,id,business_name,'business_name',1,jsonb_build_object('source','buyer_relationship_reconstruction')
from atlas.buyer_relationship_reconstruction
where business_name is not null and trim(business_name)<>''
on conflict (farm_id,buyer_relationship_id,alias_normalized) do nothing;

insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,primary_contact_name,'person_name',primary_contact_name,'current contact',1,jsonb_build_object('source','buyer_relationship_reconstruction.primary_contact_name')
from atlas.buyer_relationship_reconstruction
where primary_contact_name is not null and trim(primary_contact_name)<>''
on conflict (farm_id,buyer_relationship_id,alias_normalized) do nothing;

insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,priority,metadata)
select farm_id,id,metadata->>'contact_email','email',1,jsonb_build_object('source','buyer_relationship_reconstruction.metadata.contact_email')
from atlas.buyer_relationship_reconstruction
where metadata ? 'contact_email' and nullif(trim(metadata->>'contact_email'),'') is not null
on conflict (farm_id,buyer_relationship_id,alias_normalized) do nothing;

create or replace view intelligence.v_noel_buyer_followup_queue_v1 as
select
  m.farm_id,
  m.buyer_relationship_id,
  m.stable_key,
  m.business_name,
  m.buyer_type,
  m.city,
  m.primary_contact_name,
  m.relationship_status,
  m.buyer_lane,
  m.buying_stage,
  m.buying_cadence,
  m.route_state,
  m.route_priority,
  m.purchase_truth_state,
  m.exact_atlas_purchase_count,
  m.reported_purchase_evidence_count,
  m.last_atlas_purchase_date,
  m.last_atlas_order_id,
  m.last_contact_at,
  m.last_contact_outcome,
  m.last_contact_name,
  m.last_contact_notes,
  m.last_contact_follow_up,
  m.next_action,
  m.warm_never_purchased_known,
  m.warm_without_atlas_order,
  case when m.last_contact_at is null then null else (current_date - (m.last_contact_at at time zone 'America/Chicago')::date) end as days_since_last_contact,
  case
    when m.warm_never_purchased_known then 'warm_no_known_purchase'
    when m.warm_without_atlas_order and m.reported_purchase_evidence_count>0 then 'warm_historical_buyer_no_exact_atlas_order'
    when m.warm_without_atlas_order then 'warm_no_atlas_order'
    else null
  end as followup_reason
from intelligence.v_noel_buyer_memory_v1 m
where m.route_state='active'
  and (m.warm_never_purchased_known or m.warm_without_atlas_order)
order by m.route_priority asc nulls last, m.last_contact_at asc nulls first, m.business_name;

grant select on intelligence.v_noel_buyer_followup_queue_v1 to authenticated;