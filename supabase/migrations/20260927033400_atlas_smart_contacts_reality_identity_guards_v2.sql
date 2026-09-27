-- Smart Contacts Reality identity guards v2.
-- Prevent compatibility writers from silently dropping or changing canonical Reality identity
-- carried by a V2 Smart Contact snapshot.

create or replace function atlas.guard_smart_contact_run_item_reality_identity_v2()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_snapshot_reality uuid;
  v_snapshot_source uuid;
begin
  begin v_snapshot_reality:=nullif(new.smart_contact_snapshot->>'realityEntityId','')::uuid;
  exception when others then raise exception 'Smart Contact snapshot realityEntityId must be a UUID.' using errcode='23514'; end;
  begin v_snapshot_source:=nullif(new.smart_contact_snapshot->>'sourceEntityId','')::uuid;
  exception when others then raise exception 'Smart Contact snapshot sourceEntityId must be a UUID.' using errcode='23514'; end;

  if v_snapshot_reality is not null and new.reality_entity_id is distinct from v_snapshot_reality then
    raise exception 'Saved Smart Contact canonical Reality identity must match its snapshot.' using errcode='23514';
  end if;
  if coalesce(new.smart_contact_snapshot->>'canonicalState','')='resolved' and new.reality_entity_id is null then
    raise exception 'Resolved Smart Contact snapshot requires stored canonical Reality identity.' using errcode='23514';
  end if;
  if v_snapshot_source is not null and new.entity_id is distinct from v_snapshot_source then
    raise exception 'Saved Smart Contact research identity must match its source snapshot.' using errcode='23514';
  end if;
  if new.reality_entity_id is not null and not exists(
    select 1 from reality.entities e
    where e.id=new.reality_entity_id and e.identity_state='canonical'
  ) then
    raise exception 'Saved Smart Contact Reality identity must remain canonical.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_smart_contact_run_item_reality_identity_v2()
  from public,anon,authenticated;
drop trigger if exists smart_contact_run_item_reality_identity_guard_v2
  on atlas.smart_contact_saved_search_run_items;
create trigger smart_contact_run_item_reality_identity_guard_v2
before insert or update of entity_id,reality_entity_id,smart_contact_snapshot
on atlas.smart_contact_saved_search_run_items
for each row execute function atlas.guard_smart_contact_run_item_reality_identity_v2();

create or replace function atlas.guard_contact_selection_packet_reality_identity_v2()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_snapshot_reality uuid;
  v_snapshot_source uuid;
begin
  begin v_snapshot_reality:=nullif(new.smart_contact_snapshot->>'realityEntityId','')::uuid;
  exception when others then raise exception 'Contact selection snapshot realityEntityId must be a UUID.' using errcode='23514'; end;
  begin v_snapshot_source:=nullif(new.smart_contact_snapshot->>'sourceEntityId','')::uuid;
  exception when others then raise exception 'Contact selection snapshot sourceEntityId must be a UUID.' using errcode='23514'; end;

  if v_snapshot_reality is not null and new.reality_entity_id is distinct from v_snapshot_reality then
    raise exception 'Contact selection canonical Reality identity must match its snapshot.' using errcode='23514';
  end if;
  if coalesce(new.smart_contact_snapshot->>'canonicalState','')='resolved' and new.reality_entity_id is null then
    raise exception 'Resolved Smart Contact cannot enter a selection packet without canonical Reality identity.' using errcode='23514';
  end if;
  if v_snapshot_source is not null and new.entity_id is distinct from v_snapshot_source then
    raise exception 'Contact selection research identity must match its source snapshot.' using errcode='23514';
  end if;
  if new.reality_entity_id is not null and not exists(
    select 1 from reality.entities e
    where e.id=new.reality_entity_id and e.identity_state='canonical'
  ) then
    raise exception 'Contact selection Reality identity must remain canonical.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_contact_selection_packet_reality_identity_v2()
  from public,anon,authenticated;
drop trigger if exists contact_selection_packet_reality_identity_guard_v2
  on atlas.contact_selection_packet_items;
create trigger contact_selection_packet_reality_identity_guard_v2
before insert or update of entity_id,reality_entity_id,smart_contact_snapshot
on atlas.contact_selection_packet_items
for each row execute function atlas.guard_contact_selection_packet_reality_identity_v2();

comment on function atlas.guard_contact_selection_packet_reality_identity_v2() is
  'Prevents legacy contact-selection writers from stripping a canonical Reality identity carried by a V2 Smart Contact snapshot.';
