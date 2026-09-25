begin;

create table atlas.company_work_responsibility_transfer_offers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  from_allocation_id uuid not null references atlas.work_allocations(id) on delete restrict,
  offered_by_person_entity_id uuid not null references reality.entities(id) on delete restrict,
  offered_by_membership_id_compatibility uuid not null references atlas.organization_memberships(id) on delete restrict,
  target_person_entity_id uuid not null references reality.entities(id) on delete restrict,
  target_membership_id_compatibility uuid not null references atlas.organization_memberships(id) on delete restrict,
  offer_state text not null default 'offered'
    check (offer_state in ('offered','accepted','declined','withdrawn','stale')),
  offered_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_person_entity_id uuid references reality.entities(id) on delete restrict,
  resolved_by_membership_id_compatibility uuid references atlas.organization_memberships(id) on delete restrict,
  accepted_allocation_id uuid references atlas.work_allocations(id) on delete restrict,
  reason text,
  resolution_reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (offered_by_person_entity_id<>target_person_entity_id),
  check (
    (offer_state='offered' and resolved_at is null and resolved_by_person_entity_id is null
      and resolved_by_membership_id_compatibility is null and accepted_allocation_id is null)
    or
    (offer_state='accepted' and resolved_at is not null and resolved_by_person_entity_id is not null
      and resolved_by_membership_id_compatibility is not null and accepted_allocation_id is not null)
    or
    (offer_state in ('declined','withdrawn','stale') and resolved_at is not null
      and resolved_by_person_entity_id is not null
      and resolved_by_membership_id_compatibility is not null and accepted_allocation_id is null)
  )
);

create unique index company_work_responsibility_transfer_one_open_per_work_idx
  on atlas.company_work_responsibility_transfer_offers(work_item_id)
  where offer_state='offered';

create index company_work_responsibility_transfer_target_state_idx
  on atlas.company_work_responsibility_transfer_offers(
    target_person_entity_id,offer_state,offered_at desc
  );

create index company_work_responsibility_transfer_offerer_state_idx
  on atlas.company_work_responsibility_transfer_offers(
    offered_by_person_entity_id,offer_state,offered_at desc
  );

alter table atlas.company_work_responsibility_transfer_offers enable row level security;
revoke all on table atlas.company_work_responsibility_transfer_offers
  from public,anon,authenticated,service_role;

comment on table atlas.company_work_responsibility_transfer_offers is
  'Company Work receiver-uptake offers. An offer is not an assignment. Reality Person identity is canonical; Organization Membership UUIDs are compatibility carriers only.';

create or replace function atlas.guard_company_work_responsibility_transfer_offer_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_from atlas.work_allocations%rowtype;
  v_offerer atlas.organization_memberships%rowtype;
  v_target atlas.organization_memberships%rowtype;
  v_accepted atlas.work_allocations%rowtype;
  v_resolver atlas.organization_memberships%rowtype;
begin
  if tg_op='UPDATE' then
    if old.organization_id is distinct from new.organization_id
       or old.work_item_id is distinct from new.work_item_id
       or old.from_allocation_id is distinct from new.from_allocation_id
       or old.offered_by_person_entity_id is distinct from new.offered_by_person_entity_id
       or old.offered_by_membership_id_compatibility is distinct from new.offered_by_membership_id_compatibility
       or old.target_person_entity_id is distinct from new.target_person_entity_id
       or old.target_membership_id_compatibility is distinct from new.target_membership_id_compatibility
       or old.offered_at is distinct from new.offered_at then
      raise exception 'Company Work transfer offer identity/provenance is immutable.'
        using errcode='23514';
    end if;

    if old.offer_state<>'offered' then
      raise exception 'Resolved Company Work transfer offers are terminal.'
        using errcode='23514';
    end if;

    if new.offer_state='offered' then
      raise exception 'Company Work transfer offer update must resolve the offer.'
        using errcode='23514';
    end if;
  elsif new.offer_state<>'offered' then
    raise exception 'New Company Work transfer offers must begin in offered state.'
      using errcode='23514';
  end if;

  select * into v_work
  from atlas.work_items
  where id=new.work_item_id;

  if v_work.id is null or v_work.organization_id<>new.organization_id then
    raise exception 'Transfer offer Work must belong to the offer Organization.'
      using errcode='23514';
  end if;

  select * into v_from
  from atlas.work_allocations
  where id=new.from_allocation_id
    and organization_id=new.organization_id
    and work_item_id=new.work_item_id
    and allocation_role='responsible';

  if v_from.id is null then
    raise exception 'Transfer offer must name the exact responsible allocation.'
      using errcode='23514';
  end if;

  select * into v_offerer
  from atlas.organization_memberships
  where id=new.offered_by_membership_id_compatibility
    and organization_id=new.organization_id
    and person_id=new.offered_by_person_entity_id;

  if v_offerer.id is null or v_offerer.id<>v_from.assignee_membership_id then
    raise exception 'Transfer offerer must be the Person carrying the source responsibility.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=new.offered_by_person_entity_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Transfer offerer must be a canonical Reality Person.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=new.target_person_entity_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Transfer target must be a canonical Reality Person.'
      using errcode='23514';
  end if;

  select * into v_target
  from atlas.organization_memberships
  where id=new.target_membership_id_compatibility
    and organization_id=new.organization_id
    and person_id=new.target_person_entity_id;

  if v_target.id is null then
    raise exception 'Transfer target compatibility membership must identify the target Person in the same institution.'
      using errcode='23514';
  end if;

  if new.offer_state='offered' then
    if v_work.work_state<>'open'
       or v_from.state<>'active'
       or not atlas.organization_membership_present_effective_at_v1(
         v_offerer.id,v_offerer.organization_id,now()
       )
       or not atlas.organization_membership_present_effective_at_v1(
         v_target.id,v_target.organization_id,now()
       ) then
      raise exception 'New transfer offer requires open Work and present-effective offerer/target carriers.'
        using errcode='23514';
    end if;
  end if;

  if new.offer_state='accepted' then
    select * into v_accepted
    from atlas.work_allocations
    where id=new.accepted_allocation_id
      and organization_id=new.organization_id
      and work_item_id=new.work_item_id
      and allocation_role='responsible'
      and state='active'
      and establishment_basis_kind='self_adoption';

    if v_accepted.id is null then
      raise exception 'Accepted transfer must identify the new active self-adopted responsibility.'
        using errcode='23514';
    end if;

    select * into v_resolver
    from atlas.organization_memberships
    where id=new.resolved_by_membership_id_compatibility
      and organization_id=new.organization_id
      and person_id=new.resolved_by_person_entity_id;

    if v_resolver.id is null
       or v_resolver.id<>v_accepted.assignee_membership_id
       or new.resolved_by_person_entity_id<>new.target_person_entity_id
       or coalesce(v_accepted.establishment_basis->>'sourceKind','')<>'company_work_responsibility_transfer_offer'
       or coalesce(v_accepted.establishment_basis->>'sourceId','')<>new.id::text then
      raise exception 'Accepted transfer provenance must resolve to target self-adoption from this exact offer.'
        using errcode='23514';
    end if;
  elsif new.offer_state='declined'
        and new.resolved_by_person_entity_id<>new.target_person_entity_id then
    raise exception 'Only the target Person may decline a transfer offer.'
      using errcode='23514';
  elsif new.offer_state='withdrawn'
        and new.resolved_by_person_entity_id<>new.offered_by_person_entity_id then
    raise exception 'Only the offering Person may withdraw a transfer offer.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger company_work_responsibility_transfer_offer_guard_v1
before insert or update
on atlas.company_work_responsibility_transfer_offers
for each row
execute function atlas.guard_company_work_responsibility_transfer_offer_v1();

revoke all on function atlas.guard_company_work_responsibility_transfer_offer_v1()
  from public,anon,authenticated,service_role;

create or replace function atlas.offer_company_work_responsibility_transfer_self_api_v1(
  p_work_item_id uuid,
  p_target_person_entity_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_work atlas.work_items%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_actor_membership_id uuid;
  v_target_membership_id uuid;
  v_target_count integer;
  v_existing atlas.company_work_responsibility_transfer_offers%rowtype;
  v_offer atlas.company_work_responsibility_transfer_offers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Reality Person required.' using errcode='42501';
  end if;

  if p_work_item_id is null or p_target_person_entity_id is null then
    raise exception 'Work item and target Reality Person are required.'
      using errcode='22023';
  end if;

  if p_target_person_entity_id=v_person_id then
    raise exception 'Responsibility transfer target must be another Person.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0)
  );

  select * into v_work
  from atlas.work_items
  where id=p_work_item_id
  for update;

  if v_work.id is null then
    raise exception 'Company Work item not found.' using errcode='P0002';
  end if;

  if v_work.work_state<>'open' then
    raise exception 'Only open Company Work may be offered for transfer.'
      using errcode='22023';
  end if;

  v_actor_membership_id:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id
  );

  select * into v_current
  from atlas.work_allocations
  where work_item_id=v_work.id
    and organization_id=v_work.organization_id
    and allocation_role='responsible'
    and state='active'
  order by allocated_at desc,id desc
  limit 1
  for update;

  if v_actor_membership_id is null
     or v_current.id is null
     or v_current.assignee_membership_id<>v_actor_membership_id then
    raise exception 'Only the current exact Work responsibility carrier may offer transfer.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=p_target_person_entity_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Transfer target must already be a canonical Reality Person.'
      using errcode='23514';
  end if;

  select count(*)::integer,
         (array_agg(id order by created_at,id))[1]
  into v_target_count,v_target_membership_id
  from atlas.organization_memberships
  where organization_id=v_work.organization_id
    and person_id=p_target_person_entity_id
    and atlas.organization_membership_present_effective_at_v1(
      id,organization_id,now()
    );

  if v_target_count<>1 then
    raise exception 'Transfer target requires exactly one present-effective institutional carrier; found %.',
      v_target_count
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.company_work_responsibility_transfer_offers
  where work_item_id=v_work.id
    and offer_state='offered'
  limit 1
  for update;

  if v_existing.id is not null then
    if v_existing.target_person_entity_id=p_target_person_entity_id then
      return jsonb_build_object(
        'contractVersion','company_work_responsibility_transfer_offer_v1',
        'state','offered',
        'deduplicated',true,
        'offerId',v_existing.id,
        'workItemId',v_work.id,
        'fromAllocationId',v_existing.from_allocation_id,
        'offeredByPersonEntityId',v_existing.offered_by_person_entity_id,
        'targetPersonEntityId',v_existing.target_person_entity_id
      );
    end if;

    raise exception 'This Work already has an outstanding transfer offer. Withdraw or resolve it first.'
      using errcode='23505';
  end if;

  insert into atlas.company_work_responsibility_transfer_offers(
    organization_id,work_item_id,from_allocation_id,
    offered_by_person_entity_id,offered_by_membership_id_compatibility,
    target_person_entity_id,target_membership_id_compatibility,
    reason,metadata
  ) values(
    v_work.organization_id,v_work.id,v_current.id,
    v_person_id,v_actor_membership_id,
    p_target_person_entity_id,v_target_membership_id,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'source','offer_company_work_responsibility_transfer_self_api_v1',
      'truthBoundary','Offer records proposed receiver uptake; responsibility remains unchanged until target acceptance.'
    )
  )
  returning * into v_offer;

  return jsonb_build_object(
    'contractVersion','company_work_responsibility_transfer_offer_v1',
    'state','offered',
    'deduplicated',false,
    'offerId',v_offer.id,
    'organizationId',v_offer.organization_id,
    'workItemId',v_offer.work_item_id,
    'fromAllocationId',v_offer.from_allocation_id,
    'offeredByPersonEntityId',v_offer.offered_by_person_entity_id,
    'targetPersonEntityId',v_offer.target_person_entity_id,
    'offeredAt',v_offer.offered_at,
    'responsibilityChanged',false
  );
end
$function$;

revoke all on function atlas.offer_company_work_responsibility_transfer_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.offer_company_work_responsibility_transfer_self_api_v1(uuid,uuid,text)
  to authenticated;

comment on function atlas.offer_company_work_responsibility_transfer_self_api_v1(uuid,uuid,text) is
  'Current exact responsible Reality Person offers Work to another canonical Reality Person. Offer creation never changes responsibility.';

create or replace function atlas.company_work_responsibility_transfer_offers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_incoming jsonb;
  v_outgoing jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion','company_work_responsibility_transfer_offers_self_v1',
      'state','person_binding_required',
      'incoming','[]'::jsonb,
      'outgoing','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'offerId',o.id,
      'workItemId',o.work_item_id,
      'workTitle',w.title,
      'organizationId',o.organization_id,
      'fromAllocationId',o.from_allocation_id,
      'offeredByPersonEntityId',o.offered_by_person_entity_id,
      'offeredByDisplayName',offerer.display_name,
      'targetPersonEntityId',o.target_person_entity_id,
      'offeredAt',o.offered_at,
      'reason',o.reason
    )
    order by o.offered_at,o.id
  ),'[]'::jsonb)
  into v_incoming
  from atlas.company_work_responsibility_transfer_offers o
  join atlas.work_items w on w.id=o.work_item_id
  join reality.entities offerer on offerer.id=o.offered_by_person_entity_id
  where o.target_person_entity_id=v_person_id
    and o.offer_state='offered';

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'offerId',o.id,
      'workItemId',o.work_item_id,
      'workTitle',w.title,
      'organizationId',o.organization_id,
      'fromAllocationId',o.from_allocation_id,
      'targetPersonEntityId',o.target_person_entity_id,
      'targetDisplayName',target.display_name,
      'offeredAt',o.offered_at,
      'reason',o.reason
    )
    order by o.offered_at,o.id
  ),'[]'::jsonb)
  into v_outgoing
  from atlas.company_work_responsibility_transfer_offers o
  join atlas.work_items w on w.id=o.work_item_id
  join reality.entities target on target.id=o.target_person_entity_id
  where o.offered_by_person_entity_id=v_person_id
    and o.offer_state='offered';

  return jsonb_build_object(
    'contractVersion','company_work_responsibility_transfer_offers_self_v1',
    'state','ready',
    'personEntityId',v_person_id,
    'incoming',v_incoming,
    'outgoing',v_outgoing,
    'truthBoundary',jsonb_build_object(
      'offerIsNotAssignment',true,
      'acceptanceEstablishesReceiverSelfAdoption',true
    )
  );
end
$function$;

revoke all on function atlas.company_work_responsibility_transfer_offers_self_api_v1()
  from public,anon,service_role;
grant execute on function atlas.company_work_responsibility_transfer_offers_self_api_v1()
  to authenticated;

create or replace function atlas.respond_company_work_responsibility_transfer_offer_self_api_v1(
  p_offer_id uuid,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
  v_offer atlas.company_work_responsibility_transfer_offers%rowtype;
  v_work atlas.work_items%rowtype;
  v_from atlas.work_allocations%rowtype;
  v_receiver_membership_id uuid;
  v_assignment jsonb;
  v_new_allocation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if v_decision not in ('accepted','declined') then
    raise exception 'Transfer decision must be accepted or declined.'
      using errcode='22023';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Reality Person required.' using errcode='42501';
  end if;

  select * into v_offer
  from atlas.company_work_responsibility_transfer_offers
  where id=p_offer_id
  for update;

  if v_offer.id is null then
    raise exception 'Company Work responsibility transfer offer not found.'
      using errcode='P0002';
  end if;

  if v_offer.target_person_entity_id<>v_person_id then
    raise exception 'Only the target Reality Person may respond to this transfer offer.'
      using errcode='42501';
  end if;

  if v_offer.offer_state<>'offered' then
    if (v_offer.offer_state='accepted' and v_decision='accepted')
       or (v_offer.offer_state='declined' and v_decision='declined') then
      return jsonb_build_object(
        'contractVersion','company_work_responsibility_transfer_response_v1',
        'state',v_offer.offer_state,
        'deduplicated',true,
        'offerId',v_offer.id,
        'workItemId',v_offer.work_item_id,
        'acceptedAllocationId',v_offer.accepted_allocation_id
      );
    end if;

    raise exception 'This transfer offer is already resolved as %.',v_offer.offer_state
      using errcode='23514';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.company_work.responsibility:'||v_offer.work_item_id::text,0)
  );

  select * into v_work
  from atlas.work_items
  where id=v_offer.work_item_id
    and organization_id=v_offer.organization_id
  for update;

  if v_work.id is null then
    raise exception 'Transfer Work item not found.' using errcode='P0002';
  end if;

  v_receiver_membership_id:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id
  );

  if v_receiver_membership_id is null then
    raise exception 'Target Person no longer has a present-effective institutional carrier.'
      using errcode='42501';
  end if;

  select * into v_from
  from atlas.work_allocations
  where id=v_offer.from_allocation_id
    and organization_id=v_offer.organization_id
    and work_item_id=v_offer.work_item_id
    and allocation_role='responsible'
  for update;

  if v_decision='declined' then
    update atlas.company_work_responsibility_transfer_offers
    set offer_state='declined',
        resolved_at=now(),
        resolved_by_person_entity_id=v_person_id,
        resolved_by_membership_id_compatibility=v_receiver_membership_id,
        resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
    where id=v_offer.id;

    return jsonb_build_object(
      'contractVersion','company_work_responsibility_transfer_response_v1',
      'state','declined',
      'deduplicated',false,
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id,
      'responsibilityChanged',false
    );
  end if;

  if v_work.work_state<>'open'
     or v_from.id is null
     or v_from.state<>'active'
     or not exists(
       select 1
       from atlas.work_allocations
       where work_item_id=v_work.id
         and allocation_role='responsible'
         and state='active'
         and id=v_from.id
     ) then
    update atlas.company_work_responsibility_transfer_offers
    set offer_state='stale',
        resolved_at=now(),
        resolved_by_person_entity_id=v_person_id,
        resolved_by_membership_id_compatibility=v_receiver_membership_id,
        resolution_reason=coalesce(
          nullif(btrim(coalesce(p_reason,'')),''),
          'source_responsibility_changed_before_acceptance'
        )
    where id=v_offer.id;

    return jsonb_build_object(
      'contractVersion','company_work_responsibility_transfer_response_v1',
      'state','stale',
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id,
      'responsibilityChanged',false
    );
  end if;

  update atlas.work_allocations
  set state='released',
      released_at=now(),
      release_reason='receiver_accepted_transfer',
      updated_at=now(),
      metadata=metadata||jsonb_build_object(
        'transferOfferId',v_offer.id,
        'releasedForTargetPersonEntityId',v_person_id,
        'releaseAuthorityBasis','receiver_acceptance'
      )
  where id=v_from.id
    and state='active';

  v_assignment:=atlas.set_company_work_responsibility_with_basis_internal_v2(
    v_work.id,
    v_receiver_membership_id,
    v_receiver_membership_id,
    'self_adoption',
    jsonb_build_object(
      'sourceKind','company_work_responsibility_transfer_offer',
      'sourceId',v_offer.id,
      'transferOfferId',v_offer.id,
      'fromAllocationId',v_offer.from_allocation_id,
      'offeredByPersonEntityId',v_offer.offered_by_person_entity_id,
      'targetPersonEntityId',v_offer.target_person_entity_id
    ),
    coalesce(nullif(btrim(p_reason),''),'receiver_accepted_transfer'),
    jsonb_build_object(
      'source','respond_company_work_responsibility_transfer_offer_self_api_v1',
      'receiverUptake',true
    )
  );

  v_new_allocation_id:=(v_assignment->>'allocationId')::uuid;

  update atlas.company_work_responsibility_transfer_offers
  set offer_state='accepted',
      resolved_at=now(),
      resolved_by_person_entity_id=v_person_id,
      resolved_by_membership_id_compatibility=v_receiver_membership_id,
      accepted_allocation_id=v_new_allocation_id,
      resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=v_offer.id;

  return jsonb_build_object(
    'contractVersion','company_work_responsibility_transfer_response_v1',
    'state','accepted',
    'deduplicated',false,
    'offerId',v_offer.id,
    'organizationId',v_offer.organization_id,
    'workItemId',v_offer.work_item_id,
    'releasedAllocationId',v_offer.from_allocation_id,
    'acceptedAllocationId',v_new_allocation_id,
    'responsiblePersonEntityId',v_person_id,
    'responsibilityEstablishmentBasis','self_adoption',
    'responsibilityChanged',true
  );
end
$function$;

revoke all on function atlas.respond_company_work_responsibility_transfer_offer_self_api_v1(uuid,text,text)
  from public,anon,service_role;
grant execute on function atlas.respond_company_work_responsibility_transfer_offer_self_api_v1(uuid,text,text)
  to authenticated;

comment on function atlas.respond_company_work_responsibility_transfer_offer_self_api_v1(uuid,text,text) is
  'Target Reality Person accepts or declines an exact Work responsibility offer. Acceptance atomically releases source responsibility and establishes receiver self_adoption from the exact offer.';

create or replace function atlas.withdraw_company_work_responsibility_transfer_offer_self_api_v1(
  p_offer_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_offer atlas.company_work_responsibility_transfer_offers%rowtype;
  v_actor_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Reality Person required.' using errcode='42501';
  end if;

  select * into v_offer
  from atlas.company_work_responsibility_transfer_offers
  where id=p_offer_id
  for update;

  if v_offer.id is null then
    raise exception 'Company Work responsibility transfer offer not found.'
      using errcode='P0002';
  end if;

  if v_offer.offered_by_person_entity_id<>v_person_id then
    raise exception 'Only the offering Reality Person may withdraw this transfer offer.'
      using errcode='42501';
  end if;

  if v_offer.offer_state='withdrawn' then
    return jsonb_build_object(
      'contractVersion','company_work_responsibility_transfer_withdraw_v1',
      'state','withdrawn',
      'deduplicated',true,
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id
    );
  end if;

  if v_offer.offer_state<>'offered' then
    raise exception 'Resolved transfer offer cannot be withdrawn.'
      using errcode='23514';
  end if;

  v_actor_membership_id:=atlas.current_effective_organization_membership_v1(
    v_offer.organization_id
  );

  if v_actor_membership_id is null then
    raise exception 'Offering Person no longer has a present-effective institutional carrier.'
      using errcode='42501';
  end if;

  update atlas.company_work_responsibility_transfer_offers
  set offer_state='withdrawn',
      resolved_at=now(),
      resolved_by_person_entity_id=v_person_id,
      resolved_by_membership_id_compatibility=v_actor_membership_id,
      resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=v_offer.id;

  return jsonb_build_object(
    'contractVersion','company_work_responsibility_transfer_withdraw_v1',
    'state','withdrawn',
    'deduplicated',false,
    'offerId',v_offer.id,
    'workItemId',v_offer.work_item_id,
    'responsibilityChanged',false
  );
end
$function$;

revoke all on function atlas.withdraw_company_work_responsibility_transfer_offer_self_api_v1(uuid,text)
  from public,anon,service_role;
grant execute on function atlas.withdraw_company_work_responsibility_transfer_offer_self_api_v1(uuid,text)
  to authenticated;

create or replace function atlas.handoff_institutional_conversation_self_api_v1(
  p_institutional_conversation_id uuid,
  p_target_membership_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_actor_person_id uuid;
  v_actor_membership_id uuid;
  v_target atlas.organization_memberships%rowtype;
  v_offer jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_actor_person_id:=atlas.current_person_id_v1();
  if v_actor_person_id is null then
    raise exception 'Reality Person required.' using errcode='42501';
  end if;

  select * into v_conv
  from atlas.institutional_conversations
  where id=p_institutional_conversation_id
    and conversation_state='open';

  if v_conv.id is null then
    raise exception 'Open institutional conversation not found.'
      using errcode='P0002';
  end if;

  v_actor_membership_id:=atlas.current_effective_organization_membership_v1(
    v_conv.organization_id
  );

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1;

  if v_case.id is null then
    raise exception 'No active response case exists.'
      using errcode='22023';
  end if;

  select * into v_binding
  from atlas.institutional_conversation_response_work_bindings
  where response_case_id=v_case.id;

  if v_binding.id is null then
    raise exception 'Conversation must be claimed before transfer can be offered.'
      using errcode='22023';
  end if;

  select * into v_current
  from atlas.work_allocations
  where work_item_id=v_binding.work_item_id
    and allocation_role='responsible'
    and state='active'
  limit 1;

  if v_actor_membership_id is null
     or v_current.id is null
     or v_current.assignee_membership_id<>v_actor_membership_id then
    raise exception 'Only the current exact response Work responsibility carrier may offer handoff.'
      using errcode='42501';
  end if;

  select * into v_target
  from atlas.organization_memberships
  where id=p_target_membership_id
    and organization_id=v_conv.organization_id
    and atlas.organization_membership_present_effective_at_v1(
      id,organization_id,now()
    );

  if v_target.id is null or v_target.person_id is null then
    raise exception 'Transfer target must be a present-effective institutional Person.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=v_target.person_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Transfer target must be promoted to a canonical Reality Person before Work can be offered.'
      using errcode='23514';
  end if;

  v_offer:=atlas.offer_company_work_responsibility_transfer_self_api_v1(
    v_binding.work_item_id,
    v_target.person_id,
    p_reason
  );

  return jsonb_build_object(
    'contractVersion','institutional_conversation_handoff_v2',
    'state','offered',
    'institutionalConversationId',v_conv.id,
    'responseCaseId',v_case.id,
    'workItemId',v_binding.work_item_id,
    'fromMembershipId',v_current.assignee_membership_id,
    'toMembershipId',v_target.id,
    'toPersonEntityId',v_target.person_id,
    'transferOfferId',v_offer->>'offerId',
    'responsibilityChanged',false,
    'receiverAcceptanceRequired',true
  );
end
$function$;

revoke all on function atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)
  to authenticated;

comment on function atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text) is
  'Communication compatibility adapter for Company Work receiver uptake. Handoff creates a transfer offer only; the target Reality Person must accept before responsibility changes.';

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.offer_company_work_responsibility_transfer_self_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','exact_work_responsibility',
    'purpose','Current exact responsible Person offers Work responsibility to another canonical Reality Person without changing responsibility.',
    'truthBoundary','Offer is not assignment. Only receiver acceptance may establish new responsibility.'
  ),now(),false
),
(
  'atlas.company_work_responsibility_transfer_offers_self_api_v1()',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'purpose','Read outstanding incoming/outgoing responsibility-transfer offers for current Reality Person.',
    'truthBoundary','Raw transfer table is not browser-readable.'
  ),now(),false
),
(
  'atlas.respond_company_work_responsibility_transfer_offer_self_api_v1(uuid,text,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','target_reality_person_acceptance',
    'purpose','Target Person accepts or declines exact Work transfer offer.',
    'truthBoundary','Acceptance atomically releases source allocation and establishes receiver self_adoption.'
  ),now(),false
),
(
  'atlas.withdraw_company_work_responsibility_transfer_offer_self_api_v1(uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','offering_reality_person',
    'purpose','Offering Person withdraws unresolved responsibility-transfer offer.',
    'truthBoundary','Withdrawal does not alter current Work responsibility.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

update atlas.authenticated_rpc_registry
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'state','governed_transfer_offer',
      'truthBoundary','Handoff creates an offer only; target Reality Person acceptance is required before responsibility changes.'
    ),
    service_execute_expected=false,
    authenticated_execute_expected=true,
    anonymous_execute_expected=false,
    reviewed_at=now()
where signature='atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)';

commit;
