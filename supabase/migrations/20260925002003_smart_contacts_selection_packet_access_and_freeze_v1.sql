create or replace function atlas.guard_contact_selection_packet_update_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if old.packet_state='confirmed' then
    if new.packet_state not in ('confirmed','handed_off')
       or new.request_id is distinct from old.request_id
       or new.organization_id is distinct from old.organization_id
       or new.organization_unit_id is distinct from old.organization_unit_id
       or new.packet_version is distinct from old.packet_version
       or new.supersedes_packet_id is distinct from old.supersedes_packet_id
       or new.smart_contacts_query is distinct from old.smart_contacts_query
       or new.search_snapshot is distinct from old.search_snapshot
       or new.query_fingerprint is distinct from old.query_fingerprint
       or new.requested_count is distinct from old.requested_count
       or new.candidate_count is distinct from old.candidate_count
       or new.selected_count is distinct from old.selected_count
       or new.created_by_membership_id is distinct from old.created_by_membership_id
       or new.confirmed_by_membership_id is distinct from old.confirmed_by_membership_id
       or new.created_at is distinct from old.created_at
       or new.confirmed_at is distinct from old.confirmed_at
    then
      raise exception 'Confirmed contact selection packets are immutable except for execution handoff.'
        using errcode='55000';
    end if;
  elsif old.packet_state in ('handed_off','superseded','cancelled') then
    if new is distinct from old then
      raise exception 'Finalized contact selection packets are immutable.'
        using errcode='55000';
    end if;
  end if;
  return new;
end
$function$;

drop trigger if exists contact_selection_packets_immutable_after_confirm_v1
  on atlas.contact_selection_packets;
create trigger contact_selection_packets_immutable_after_confirm_v1
before update on atlas.contact_selection_packets
for each row
execute function atlas.guard_contact_selection_packet_update_v1();

create or replace function atlas.guard_contact_selection_packet_item_write_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_packet_id uuid:=coalesce(new.packet_id,old.packet_id);
  v_state text;
begin
  select packet_state into v_state
  from atlas.contact_selection_packets
  where id=v_packet_id;

  if v_state is null then
    raise exception 'Selection packet not found.' using errcode='P0002';
  end if;

  if v_state<>'proposed' then
    raise exception 'Selection packet items are immutable after packet confirmation.'
      using errcode='55000';
  end if;

  return coalesce(new,old);
end
$function$;

drop trigger if exists contact_selection_packet_items_proposed_only_v1
  on atlas.contact_selection_packet_items;
create trigger contact_selection_packet_items_proposed_only_v1
before insert or update or delete on atlas.contact_selection_packet_items
for each row
execute function atlas.guard_contact_selection_packet_item_write_v1();

create or replace function atlas.contact_selection_packet_self_api_v1(
  p_packet_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_packet atlas.contact_selection_packets%rowtype;
  v_items jsonb;
  v_events jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_packet
  from atlas.contact_selection_packets
  where id=p_packet_id;

  if v_packet.id is null then
    raise exception 'Selection packet not found.' using errcode='P0002';
  end if;

  if atlas.current_effective_organization_membership_v1(v_packet.organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'itemId',i.id,
    'entityId',i.entity_id,
    'ordinal',i.ordinal,
    'selectionState',i.selection_state,
    'smartContact',i.smart_contact_snapshot,
    'why',i.reason_snapshot
  ) order by i.ordinal),'[]'::jsonb)
  into v_items
  from atlas.contact_selection_packet_items i
  where i.packet_id=v_packet.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId',e.id,
    'eventKind',e.event_kind,
    'payload',e.event_payload,
    'actorMembershipId',e.actor_membership_id,
    'createdAt',e.created_at
  ) order by e.created_at,e.id),'[]'::jsonb)
  into v_events
  from atlas.contact_selection_packet_events e
  where e.packet_id=v_packet.id;

  return jsonb_build_object(
    'contractVersion','contact_selection_packet_read_v1',
    'packetId',v_packet.id,
    'requestId',v_packet.request_id,
    'organizationId',v_packet.organization_id,
    'organizationUnitId',v_packet.organization_unit_id,
    'packetVersion',v_packet.packet_version,
    'packetState',v_packet.packet_state,
    'smartContactsQuery',v_packet.smart_contacts_query,
    'requestedCount',v_packet.requested_count,
    'candidateCount',v_packet.candidate_count,
    'selectedCount',v_packet.selected_count,
    'revision',v_packet.revision,
    'confirmedAt',v_packet.confirmed_at,
    'handedOffAt',v_packet.handed_off_at,
    'items',v_items,
    'events',v_events
  );
end
$function$;

create or replace function atlas.create_contact_selection_packet_self_api_v1(
  p_request_id uuid,
  p_smart_contacts_query jsonb,
  p_search_limit integer default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_org_id uuid;
  v_membership_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select organization_id into v_org_id
  from atlas.contact_set_intent_requests
  where id=p_request_id;

  if v_org_id is null then
    raise exception 'Contact-set intent request not found.' using errcode='P0002';
  end if;

  v_membership_id:=atlas.current_effective_organization_membership_v1(v_org_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.create_contact_selection_packet_service_v1(
    p_request_id,p_smart_contacts_query,p_search_limit,v_membership_id
  );
end
$function$;

create or replace function atlas.set_contact_selection_packet_selection_self_api_v1(
  p_packet_id uuid,
  p_selected_entity_ids uuid[],
  p_expected_revision integer default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_org_id uuid;
  v_membership_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select organization_id into v_org_id
  from atlas.contact_selection_packets
  where id=p_packet_id;

  if v_org_id is null then
    raise exception 'Selection packet not found.' using errcode='P0002';
  end if;

  v_membership_id:=atlas.current_effective_organization_membership_v1(v_org_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.set_contact_selection_packet_selection_service_v1(
    p_packet_id,p_selected_entity_ids,p_expected_revision,v_membership_id
  );
end
$function$;

create or replace function atlas.confirm_contact_selection_packet_self_api_v1(
  p_packet_id uuid,
  p_expected_revision integer default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_org_id uuid;
  v_membership_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select organization_id into v_org_id
  from atlas.contact_selection_packets
  where id=p_packet_id;

  if v_org_id is null then
    raise exception 'Selection packet not found.' using errcode='P0002';
  end if;

  v_membership_id:=atlas.current_effective_organization_membership_v1(v_org_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.confirm_contact_selection_packet_service_v1(
    p_packet_id,p_expected_revision,v_membership_id
  );
end
$function$;

create or replace function atlas.prepare_contact_set_execution_from_selection_packet_self_api_v1(
  p_packet_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_org_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select organization_id into v_org_id
  from atlas.contact_selection_packets
  where id=p_packet_id;

  if v_org_id is null then
    raise exception 'Selection packet not found.' using errcode='P0002';
  end if;

  if atlas.current_effective_organization_membership_v1(v_org_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.prepare_contact_set_execution_from_selection_packet_service_v1(p_packet_id);
end
$function$;

revoke all on function atlas.contact_selection_packet_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.contact_selection_packet_self_api_v1(uuid)
  to authenticated;

revoke all on function atlas.create_contact_selection_packet_self_api_v1(uuid,jsonb,integer)
  from public,anon;
grant execute on function atlas.create_contact_selection_packet_self_api_v1(uuid,jsonb,integer)
  to authenticated;

revoke all on function atlas.set_contact_selection_packet_selection_self_api_v1(uuid,uuid[],integer)
  from public,anon;
grant execute on function atlas.set_contact_selection_packet_selection_self_api_v1(uuid,uuid[],integer)
  to authenticated;

revoke all on function atlas.confirm_contact_selection_packet_self_api_v1(uuid,integer)
  from public,anon;
grant execute on function atlas.confirm_contact_selection_packet_self_api_v1(uuid,integer)
  to authenticated;

revoke all on function atlas.prepare_contact_set_execution_from_selection_packet_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.prepare_contact_set_execution_from_selection_packet_self_api_v1(uuid)
  to authenticated;
