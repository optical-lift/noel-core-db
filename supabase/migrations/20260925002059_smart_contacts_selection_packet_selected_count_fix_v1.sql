create or replace function atlas.set_contact_selection_packet_selection_service_v1(
  p_packet_id uuid,p_selected_entity_ids uuid[],p_expected_revision integer default null,
  p_actor_membership_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_packet atlas.contact_selection_packets%rowtype; v_ids uuid[]; v_known integer;
  v_selected integer; v_old_ids jsonb; v_new_ids jsonb;
begin
  select * into v_packet from atlas.contact_selection_packets where id=p_packet_id for update;
  if v_packet.id is null then raise exception 'Selection packet not found.' using errcode='P0002'; end if;
  if v_packet.packet_state<>'proposed' then raise exception 'Only proposed selection packets may be edited.' using errcode='23514'; end if;
  if p_expected_revision is not null and p_expected_revision<>v_packet.revision then
    raise exception 'Selection packet revision changed; refresh before editing.' using errcode='40001';
  end if;
  if p_actor_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_actor_membership_id and m.organization_id=v_packet.organization_id and m.active
  ) then raise exception 'Actor membership does not belong to this Organization.' using errcode='42501'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[])
  into v_ids from unnest(coalesce(p_selected_entity_ids,'{}'::uuid[])) x;

  select count(*) into v_known from atlas.contact_selection_packet_items i
  where i.packet_id=v_packet.id and i.entity_id=any(v_ids);
  if v_known<>cardinality(v_ids) then
    raise exception 'Every selected entity must already exist in this packet snapshot.' using errcode='23503';
  end if;

  select coalesce(jsonb_agg(entity_id order by ordinal),'[]'::jsonb)
  into v_old_ids from atlas.contact_selection_packet_items
  where packet_id=v_packet.id and selection_state='selected';

  update atlas.contact_selection_packet_items
  set selection_state=case when entity_id=any(v_ids) then 'selected' else 'alternate' end,
      updated_at=now()
  where packet_id=v_packet.id;

  select
    count(*) filter(where selection_state='selected')::integer,
    coalesce(jsonb_agg(entity_id order by ordinal) filter(where selection_state='selected'),'[]'::jsonb)
  into v_selected,v_new_ids
  from atlas.contact_selection_packet_items where packet_id=v_packet.id;

  update atlas.contact_selection_packets
  set selected_count=v_selected,revision=revision+1,updated_at=now()
  where id=v_packet.id returning * into v_packet;

  insert into atlas.contact_selection_packet_events(
    packet_id,organization_id,event_kind,event_payload,actor_membership_id
  ) values (
    v_packet.id,v_packet.organization_id,'selection_changed',
    jsonb_build_object(
      'priorSelectedEntityIds',v_old_ids,'selectedEntityIds',v_new_ids,
      'selectedCount',v_selected,'revision',v_packet.revision
    ),p_actor_membership_id
  );

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','contact_selection_packet_selection_v1',
    'packetId',v_packet.id,'packetState',v_packet.packet_state,
    'selectedCount',v_packet.selected_count,'revision',v_packet.revision,
    'selectedEntityIds',v_new_ids
  );
end
$function$;