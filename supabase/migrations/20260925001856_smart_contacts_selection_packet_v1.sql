alter table atlas.contact_set_intent_requests
  add constraint contact_set_intent_requests_org_id_id_key
  unique (organization_id,id);

create table atlas.contact_selection_packets (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references atlas.contact_set_intent_requests(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid null,
  packet_version integer not null default 1 check (packet_version > 0),
  supersedes_packet_id uuid null references atlas.contact_selection_packets(id) on delete restrict,
  packet_state text not null default 'proposed'
    check (packet_state in ('proposed','confirmed','handed_off','superseded','cancelled')),
  smart_contacts_query jsonb not null check (jsonb_typeof(smart_contacts_query)='object'),
  search_snapshot jsonb not null check (jsonb_typeof(search_snapshot)='object'),
  query_fingerprint text not null,
  requested_count integer null check (requested_count is null or requested_count > 0),
  candidate_count integer not null default 0 check (candidate_count >= 0),
  selected_count integer not null default 0 check (selected_count >= 0),
  revision integer not null default 1 check (revision > 0),
  created_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  confirmed_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz null,
  handed_off_at timestamptz null,
  constraint contact_selection_packets_request_org_fk
    foreign key (organization_id,request_id)
    references atlas.contact_set_intent_requests(organization_id,id)
    on delete cascade,
  constraint contact_selection_packets_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id)
    on delete restrict,
  unique(request_id,packet_version)
);

create unique index contact_selection_packets_one_live_per_request_idx
  on atlas.contact_selection_packets(request_id)
  where packet_state in ('proposed','confirmed','handed_off');

create index contact_selection_packets_org_state_idx
  on atlas.contact_selection_packets(organization_id,packet_state,created_at desc);

create table atlas.contact_selection_packet_items (
  id uuid primary key default gen_random_uuid(),
  packet_id uuid not null references atlas.contact_selection_packets(id) on delete cascade,
  entity_id uuid not null references local_intel.entities(id) on delete restrict,
  ordinal integer not null check (ordinal > 0),
  selection_state text not null default 'alternate'
    check (selection_state in ('selected','alternate')),
  smart_contact_snapshot jsonb not null check (jsonb_typeof(smart_contact_snapshot)='object'),
  reason_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(reason_snapshot)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(packet_id,entity_id),
  unique(packet_id,ordinal)
);

create index contact_selection_packet_items_entity_idx
  on atlas.contact_selection_packet_items(entity_id,packet_id);

create table atlas.contact_selection_packet_events (
  id uuid primary key default gen_random_uuid(),
  packet_id uuid not null references atlas.contact_selection_packets(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  event_kind text not null
    check (event_kind in ('created','selection_changed','confirmed','handed_off','superseded','cancelled')),
  event_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(event_payload)='object'),
  actor_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now()
);

create index contact_selection_packet_events_packet_idx
  on atlas.contact_selection_packet_events(packet_id,created_at);

alter table atlas.contact_selection_packets enable row level security;
alter table atlas.contact_selection_packet_items enable row level security;
alter table atlas.contact_selection_packet_events enable row level security;

revoke all on table atlas.contact_selection_packets from public,anon,authenticated;
revoke all on table atlas.contact_selection_packet_items from public,anon,authenticated;
revoke all on table atlas.contact_selection_packet_events from public,anon,authenticated;
grant select,insert,update,delete on table atlas.contact_selection_packets to service_role;
grant select,insert,update,delete on table atlas.contact_selection_packet_items to service_role;
grant select,insert on table atlas.contact_selection_packet_events to service_role;

comment on table atlas.contact_selection_packets is
  'Organization-private durable Smart Contacts selection packet. Freezes the search answer and selection state without creating Shared Intelligence truth, external relationships, or communication authority.';
comment on table atlas.contact_selection_packet_items is
  'Frozen candidate/result rows belonging to one Smart Contacts selection packet. Each item preserves the Smart Contact explanation available at selection time.';
comment on table atlas.contact_selection_packet_events is
  'Append-only audit events for Smart Contacts selection packet creation, edits, confirmation, and execution handoff.';

create or replace function atlas.create_contact_selection_packet_service_v1(
  p_request_id uuid,p_smart_contacts_query jsonb,p_search_limit integer default null,
  p_created_by_membership_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_request atlas.contact_set_intent_requests%rowtype;
  v_existing atlas.contact_selection_packets%rowtype;
  v_packet atlas.contact_selection_packets%rowtype;
  v_search jsonb; v_requested integer; v_candidate_count integer;
  v_selected_count integer; v_limit integer; v_query_fingerprint text;
  v_version integer; v_item jsonb; v_ordinal integer;
begin
  if p_smart_contacts_query is null or jsonb_typeof(p_smart_contacts_query)<>'object' then
    raise exception 'Smart Contacts query must be an object.' using errcode='22023';
  end if;

  select * into v_request from atlas.contact_set_intent_requests where id=p_request_id;
  if v_request.id is null then
    raise exception 'Contact-set intent request not found.' using errcode='P0002';
  end if;
  if v_request.request_state<>'ready' or v_request.interpretation is null then
    raise exception 'Contact-set intent request must be ready before selection.' using errcode='23514';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_created_by_membership_id
      and m.organization_id=v_request.organization_id and m.active
  ) then
    raise exception 'Creating membership does not belong to the requesting Organization.' using errcode='42501';
  end if;

  begin
    v_requested:=nullif(v_request.interpretation#>>'{population,desiredCount}','')::integer;
  exception when invalid_text_representation then
    raise exception 'Contact-set desired count is invalid.' using errcode='23514';
  end;

  if v_requested is not null and v_requested<=0 then
    raise exception 'Contact-set desired count must be positive.' using errcode='23514';
  end if;

  v_limit:=least(200,greatest(coalesce(p_search_limit,0),20,coalesce(v_requested,20)*3));
  v_query_fingerprint:=md5(p_smart_contacts_query::text);

  select * into v_existing
  from atlas.contact_selection_packets p
  where p.request_id=v_request.id and p.packet_state in ('proposed','confirmed','handed_off')
  order by p.packet_version desc limit 1;

  if v_existing.id is not null then
    if v_existing.query_fingerprint=v_query_fingerprint then
      return jsonb_build_object(
        'ok',true,'changed',false,'contractVersion','contact_selection_packet_v1',
        'packetId',v_existing.id,'requestId',v_existing.request_id,
        'packetState',v_existing.packet_state,'candidateCount',v_existing.candidate_count,
        'selectedCount',v_existing.selected_count,'revision',v_existing.revision
      );
    end if;
    raise exception 'An active selection packet already exists for this request. Supersede or cancel it before changing the Smart Contacts query.'
      using errcode='23505';
  end if;

  v_search:=atlas.smart_contacts_search_service_v1(v_request.organization_id,p_smart_contacts_query,v_limit);
  v_candidate_count:=coalesce((v_search->>'resultCount')::integer,0);

  select coalesce(max(packet_version),0)+1 into v_version
  from atlas.contact_selection_packets where request_id=v_request.id;

  insert into atlas.contact_selection_packets(
    request_id,organization_id,organization_unit_id,packet_version,packet_state,
    smart_contacts_query,search_snapshot,query_fingerprint,requested_count,
    candidate_count,selected_count,revision,created_by_membership_id
  ) values (
    v_request.id,v_request.organization_id,v_request.organization_unit_id,v_version,'proposed',
    p_smart_contacts_query,v_search,v_query_fingerprint,v_requested,
    v_candidate_count,0,1,p_created_by_membership_id
  ) returning * into v_packet;

  v_ordinal:=0;
  for v_item in select value from jsonb_array_elements(coalesce(v_search->'items','[]'::jsonb))
  loop
    v_ordinal:=v_ordinal+1;
    insert into atlas.contact_selection_packet_items(
      packet_id,entity_id,ordinal,selection_state,smart_contact_snapshot,reason_snapshot
    ) values (
      v_packet.id,(v_item->>'entityId')::uuid,v_ordinal,
      case when v_requested is null or v_ordinal<=v_requested then 'selected' else 'alternate' end,
      v_item,
      jsonb_build_object(
        'match',coalesce(v_item->'match','{}'::jsonb),
        'peopleState',v_item#>>'{people,state}',
        'contactabilityState',v_item#>>'{contactability,state}',
        'freshnessState',v_item#>>'{freshness,state}',
        'researchGaps',coalesce(v_item->'researchGaps','[]'::jsonb)
      )
    );
  end loop;

  select count(*)::integer into v_selected_count
  from atlas.contact_selection_packet_items
  where packet_id=v_packet.id and selection_state='selected';

  update atlas.contact_selection_packets
  set selected_count=v_selected_count,updated_at=now()
  where id=v_packet.id returning * into v_packet;

  insert into atlas.contact_selection_packet_events(
    packet_id,organization_id,event_kind,event_payload,actor_membership_id
  ) values (
    v_packet.id,v_packet.organization_id,'created',
    jsonb_build_object(
      'requestId',v_packet.request_id,'queryFingerprint',v_packet.query_fingerprint,
      'requestedCount',v_packet.requested_count,'candidateCount',v_packet.candidate_count,
      'selectedCount',v_packet.selected_count
    ),p_created_by_membership_id
  );

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','contact_selection_packet_v1',
    'packetId',v_packet.id,'requestId',v_packet.request_id,
    'organizationId',v_packet.organization_id,'packetVersion',v_packet.packet_version,
    'packetState',v_packet.packet_state,'requestedCount',v_packet.requested_count,
    'candidateCount',v_packet.candidate_count,'selectedCount',v_packet.selected_count,
    'revision',v_packet.revision,
    'truthBoundary',jsonb_build_object(
      'sharedIntelligenceMutation',false,'organizationRelationshipCreated',false,
      'communicationAuthorized',false,'selectionIsOrganizationPrivate',true
    )
  );
end
$function$;

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

  select count(*)::integer,
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

create or replace function atlas.confirm_contact_selection_packet_service_v1(
  p_packet_id uuid,p_expected_revision integer default null,p_actor_membership_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare v_packet atlas.contact_selection_packets%rowtype; v_selected jsonb;
begin
  select * into v_packet from atlas.contact_selection_packets where id=p_packet_id for update;
  if v_packet.id is null then raise exception 'Selection packet not found.' using errcode='P0002'; end if;
  if v_packet.packet_state in ('confirmed','handed_off') then
    return jsonb_build_object('ok',true,'changed',false,'packetId',v_packet.id,'packetState',v_packet.packet_state,'revision',v_packet.revision);
  end if;
  if v_packet.packet_state<>'proposed' then raise exception 'Only proposed selection packets may be confirmed.' using errcode='23514'; end if;
  if p_expected_revision is not null and p_expected_revision<>v_packet.revision then
    raise exception 'Selection packet revision changed; refresh before confirming.' using errcode='40001';
  end if;
  if v_packet.selected_count<=0 then raise exception 'At least one selected entity is required before confirmation.' using errcode='23514'; end if;
  if p_actor_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_actor_membership_id and m.organization_id=v_packet.organization_id and m.active
  ) then raise exception 'Actor membership does not belong to this Organization.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'entityId',i.entity_id,'ordinal',i.ordinal,'smartContact',i.smart_contact_snapshot,'whySelected',i.reason_snapshot
  ) order by i.ordinal),'[]'::jsonb)
  into v_selected
  from atlas.contact_selection_packet_items i
  where i.packet_id=v_packet.id and i.selection_state='selected';

  update atlas.contact_selection_packets
  set packet_state='confirmed',confirmed_by_membership_id=p_actor_membership_id,
      confirmed_at=now(),revision=revision+1,updated_at=now()
  where id=v_packet.id returning * into v_packet;

  insert into atlas.contact_selection_packet_events(
    packet_id,organization_id,event_kind,event_payload,actor_membership_id
  ) values (
    v_packet.id,v_packet.organization_id,'confirmed',
    jsonb_build_object(
      'selectedCount',v_packet.selected_count,'requestedCount',v_packet.requested_count,
      'confirmedSelection',v_selected,
      'partialSelection',v_packet.requested_count is not null and v_packet.selected_count<v_packet.requested_count,
      'revision',v_packet.revision
    ),p_actor_membership_id
  );

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','contact_selection_packet_confirmation_v1',
    'packetId',v_packet.id,'packetState',v_packet.packet_state,
    'selectedCount',v_packet.selected_count,'requestedCount',v_packet.requested_count,
    'partialSelection',v_packet.requested_count is not null and v_packet.selected_count<v_packet.requested_count,
    'confirmedSelection',v_selected,'revision',v_packet.revision,
    'truthBoundary',jsonb_build_object(
      'selectionFrozen',true,'sharedIntelligenceMutation',false,
      'organizationRelationshipCreated',false,'communicationAuthorized',false
    )
  );
end
$function$;

create or replace function atlas.prepare_contact_set_execution_from_selection_packet_service_v1(
  p_packet_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
  v_packet atlas.contact_selection_packets%rowtype;
  v_request atlas.contact_set_intent_requests%rowtype;
  v_existing atlas.contact_set_execution_runs%rowtype;
  v_run atlas.contact_set_execution_runs%rowtype;
  v_required text[]; v_items jsonb; v_gap_items jsonb;
begin
  select * into v_packet from atlas.contact_selection_packets where id=p_packet_id for update;
  if v_packet.id is null then raise exception 'Selection packet not found.' using errcode='P0002'; end if;
  if v_packet.packet_state not in ('confirmed','handed_off') then
    raise exception 'Selection packet must be confirmed before execution preparation.' using errcode='23514';
  end if;

  select * into v_request from atlas.contact_set_intent_requests where id=v_packet.request_id;
  if v_request.id is null or v_request.request_state<>'ready' then
    raise exception 'Ready contact-set intent request is required for execution handoff.' using errcode='23514';
  end if;

  select * into v_existing from atlas.contact_set_execution_runs where request_id=v_request.id;
  if v_existing.id is not null then
    if v_existing.directory_snapshot->>'selectionPacketId'=v_packet.id::text then
      return jsonb_build_object(
        'ok',true,'changed',false,'contractVersion','contact_selection_packet_execution_handoff_v1',
        'packetId',v_packet.id,'runId',v_existing.id,'executionState',v_existing.execution_state
      );
    end if;
    raise exception 'This request already has an execution run prepared from a different selection path.' using errcode='23505';
  end if;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_required
  from jsonb_array_elements_text(coalesce(v_request.interpretation#>'{fields,required}','[]'::jsonb)) x;
  if cardinality(v_required)=0 then v_required:=array['canonical_entity']; end if;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'entityId',i.entity_id,'ordinal',i.ordinal,'smartContact',i.smart_contact_snapshot,'whySelected',i.reason_snapshot
    ) order by i.ordinal),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'entityId',i.entity_id,'researchGaps',coalesce(i.smart_contact_snapshot->'researchGaps','[]'::jsonb)
    ) order by i.ordinal)
      filter (where jsonb_array_length(coalesce(i.smart_contact_snapshot->'researchGaps','[]'::jsonb))>0),'[]'::jsonb)
  into v_items,v_gap_items
  from atlas.contact_selection_packet_items i
  where i.packet_id=v_packet.id and i.selection_state='selected';

  insert into atlas.contact_set_execution_runs(
    request_id,organization_id,organization_unit_id,execution_state,
    required_fields,desired_count,selected_count,directory_snapshot,gap_snapshot,ledger_effect_snapshot
  ) values (
    v_request.id,v_packet.organization_id,v_packet.organization_unit_id,'ready',
    v_required,v_packet.requested_count,v_packet.selected_count,
    jsonb_build_object(
      'contractVersion','contact_selection_packet_execution_input_v1',
      'selectionPacketId',v_packet.id,'selectionPacketVersion',v_packet.packet_version,
      'selectionConfirmedAt',v_packet.confirmed_at,'smartContactsQuery',v_packet.smart_contacts_query,'items',v_items
    ),
    jsonb_build_object(
      'contractVersion','contact_selection_packet_accepted_gaps_v1',
      'selectionWasConfirmed',true,'acceptedResearchGaps',v_gap_items,
      'populationGap',v_packet.requested_count is not null and v_packet.selected_count<v_packet.requested_count
    ),
    jsonb_build_object(
      'selectionPacketId',v_packet.id,'attachToLedger',false,'results','[]'::jsonb,'communicationAuthorized',false
    )
  ) returning * into v_run;

  update atlas.contact_selection_packets
  set packet_state='handed_off',handed_off_at=now(),updated_at=now()
  where id=v_packet.id returning * into v_packet;

  insert into atlas.contact_selection_packet_events(packet_id,organization_id,event_kind,event_payload)
  values (
    v_packet.id,v_packet.organization_id,'handed_off',
    jsonb_build_object(
      'executionRunId',v_run.id,'requestId',v_run.request_id,
      'selectedCount',v_run.selected_count,'communicationAuthorized',false,
      'organizationRelationshipCreated',false
    )
  );

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','contact_selection_packet_execution_handoff_v1',
    'packetId',v_packet.id,'packetState',v_packet.packet_state,'runId',v_run.id,
    'requestId',v_run.request_id,'executionState',v_run.execution_state,'selectedCount',v_run.selected_count,
    'directory',v_run.directory_snapshot,'gaps',v_run.gap_snapshot,'ledgerEffects',v_run.ledger_effect_snapshot,
    'truthBoundary',jsonb_build_object(
      'selectionWasConfirmed',true,'sharedIntelligenceMutation',false,
      'organizationRelationshipCreated',false,'communicationAuthorized',false
    )
  );
end
$function$;

revoke all on function atlas.create_contact_selection_packet_service_v1(uuid,jsonb,integer,uuid)
  from public,anon,authenticated;
grant execute on function atlas.create_contact_selection_packet_service_v1(uuid,jsonb,integer,uuid) to service_role;
revoke all on function atlas.set_contact_selection_packet_selection_service_v1(uuid,uuid[],integer,uuid)
  from public,anon,authenticated;
grant execute on function atlas.set_contact_selection_packet_selection_service_v1(uuid,uuid[],integer,uuid) to service_role;
revoke all on function atlas.confirm_contact_selection_packet_service_v1(uuid,integer,uuid)
  from public,anon,authenticated;
grant execute on function atlas.confirm_contact_selection_packet_service_v1(uuid,integer,uuid) to service_role;
revoke all on function atlas.prepare_contact_set_execution_from_selection_packet_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.prepare_contact_set_execution_from_selection_packet_service_v1(uuid) to service_role;
