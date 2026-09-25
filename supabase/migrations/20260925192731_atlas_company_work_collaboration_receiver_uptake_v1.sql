begin;

alter table atlas.work_allocations
  drop constraint work_allocations_establishment_basis_shape_check;

alter table atlas.work_allocations
  add constraint work_allocations_establishment_basis_shape_check
  check (
    (establishment_basis_kind is null and establishment_basis is null)
    or
    (
      establishment_basis_kind is not null
      and establishment_basis is not null
      and jsonb_typeof(establishment_basis)='object'
    )
  );

create table atlas.company_work_participation_offers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  offered_from_responsibility_allocation_id uuid not null
    references atlas.work_allocations(id) on delete restrict,
  offered_by_person_entity_id uuid not null
    references reality.entities(id) on delete restrict,
  offered_by_membership_id_compatibility uuid not null
    references atlas.organization_memberships(id) on delete restrict,
  target_person_entity_id uuid not null
    references reality.entities(id) on delete restrict,
  target_membership_id_compatibility uuid not null
    references atlas.organization_memberships(id) on delete restrict,
  allocation_role text not null
    check (allocation_role in ('participant','approver')),
  offer_state text not null default 'offered'
    check (offer_state in ('offered','accepted','declined','withdrawn','stale')),
  offered_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by_person_entity_id uuid
    references reality.entities(id) on delete restrict,
  resolved_by_membership_id_compatibility uuid
    references atlas.organization_memberships(id) on delete restrict,
  accepted_allocation_id uuid
    references atlas.work_allocations(id) on delete restrict,
  reason text,
  resolution_reason text,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (offered_by_person_entity_id<>target_person_entity_id),
  check (
    (offer_state='offered'
      and resolved_at is null
      and resolved_by_person_entity_id is null
      and resolved_by_membership_id_compatibility is null
      and accepted_allocation_id is null)
    or
    (offer_state='accepted'
      and resolved_at is not null
      and resolved_by_person_entity_id is not null
      and resolved_by_membership_id_compatibility is not null
      and accepted_allocation_id is not null)
    or
    (offer_state in ('declined','withdrawn','stale')
      and resolved_at is not null
      and resolved_by_person_entity_id is not null
      and resolved_by_membership_id_compatibility is not null
      and accepted_allocation_id is null)
  )
);

create unique index company_work_participation_offer_one_open_idx
  on atlas.company_work_participation_offers(
    work_item_id,target_person_entity_id,allocation_role
  )
  where offer_state='offered';

create index company_work_participation_offer_target_state_idx
  on atlas.company_work_participation_offers(
    target_person_entity_id,offer_state,offered_at desc
  );

create index company_work_participation_offer_offerer_state_idx
  on atlas.company_work_participation_offers(
    offered_by_person_entity_id,offer_state,offered_at desc
  );

create index company_work_participation_offer_organization_idx
  on atlas.company_work_participation_offers(organization_id);

create index company_work_participation_offer_work_idx
  on atlas.company_work_participation_offers(work_item_id);

create index company_work_participation_offer_responsibility_allocation_idx
  on atlas.company_work_participation_offers(
    offered_from_responsibility_allocation_id
  );

create index company_work_participation_offer_offerer_membership_idx
  on atlas.company_work_participation_offers(
    offered_by_membership_id_compatibility
  );

create index company_work_participation_offer_target_membership_idx
  on atlas.company_work_participation_offers(
    target_membership_id_compatibility
  );

create index company_work_participation_offer_resolver_person_idx
  on atlas.company_work_participation_offers(
    resolved_by_person_entity_id
  );

create index company_work_participation_offer_resolver_membership_idx
  on atlas.company_work_participation_offers(
    resolved_by_membership_id_compatibility
  );

create index company_work_participation_offer_accepted_allocation_idx
  on atlas.company_work_participation_offers(
    accepted_allocation_id
  );

create unique index work_allocations_one_active_participation_per_person_role_idx
  on atlas.work_allocations(
    work_item_id,assignee_membership_id,allocation_role
  )
  where state='active'
    and allocation_role in ('participant','approver');

alter table atlas.company_work_participation_offers enable row level security;
revoke all on table atlas.company_work_participation_offers
  from public,anon,authenticated,service_role;

comment on table atlas.company_work_participation_offers is
  'Receiver-uptake offers for bounded Company Work participant/approver participation. Offer creation does not create a Work allocation.';

create or replace function atlas.guard_company_work_participation_offer_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_source atlas.work_allocations%rowtype;
  v_offerer atlas.organization_memberships%rowtype;
  v_target atlas.organization_memberships%rowtype;
  v_resolver atlas.organization_memberships%rowtype;
  v_accepted atlas.work_allocations%rowtype;
begin
  if tg_op='UPDATE' then
    if old.organization_id is distinct from new.organization_id
       or old.work_item_id is distinct from new.work_item_id
       or old.offered_from_responsibility_allocation_id is distinct from new.offered_from_responsibility_allocation_id
       or old.offered_by_person_entity_id is distinct from new.offered_by_person_entity_id
       or old.offered_by_membership_id_compatibility is distinct from new.offered_by_membership_id_compatibility
       or old.target_person_entity_id is distinct from new.target_person_entity_id
       or old.target_membership_id_compatibility is distinct from new.target_membership_id_compatibility
       or old.allocation_role is distinct from new.allocation_role
       or old.offered_at is distinct from new.offered_at then
      raise exception 'Company Work participation offer identity/provenance is immutable.'
        using errcode='23514';
    end if;

    if old.offer_state<>'offered' then
      raise exception 'Resolved Company Work participation offers are terminal.'
        using errcode='23514';
    end if;

    if new.offer_state='offered' then
      raise exception 'Company Work participation offer update must resolve the offer.'
        using errcode='23514';
    end if;
  elsif new.offer_state<>'offered' then
    raise exception 'New Company Work participation offers must begin in offered state.'
      using errcode='23514';
  end if;

  select * into v_work
  from atlas.work_items
  where id=new.work_item_id;

  if v_work.id is null
     or v_work.organization_id<>new.organization_id then
    raise exception 'Participation offer Work must belong to the offer Organization.'
      using errcode='23514';
  end if;

  select * into v_source
  from atlas.work_allocations
  where id=new.offered_from_responsibility_allocation_id
    and organization_id=new.organization_id
    and work_item_id=new.work_item_id
    and allocation_role='responsible';

  if v_source.id is null then
    raise exception 'Participation offer must name the exact responsible allocation that issued it.'
      using errcode='23514';
  end if;

  select * into v_offerer
  from atlas.organization_memberships
  where id=new.offered_by_membership_id_compatibility
    and organization_id=new.organization_id
    and person_id=new.offered_by_person_entity_id;

  if v_offerer.id is null
     or v_source.assignee_membership_id<>v_offerer.id then
    raise exception 'Participation offerer must carry the source exact Work responsibility.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=new.offered_by_person_entity_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Participation offerer must be a canonical Reality Person.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=new.target_person_entity_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Participation target must be a canonical Reality Person.'
      using errcode='23514';
  end if;

  select * into v_target
  from atlas.organization_memberships
  where id=new.target_membership_id_compatibility
    and organization_id=new.organization_id
    and person_id=new.target_person_entity_id;

  if v_target.id is null then
    raise exception 'Participation target compatibility carrier must identify the target Person in the same institution.'
      using errcode='23514';
  end if;

  if new.offer_state='offered' then
    if v_work.work_state<>'open'
       or v_source.state<>'active'
       or not atlas.organization_membership_present_effective_at_v1(
         v_offerer.id,v_offerer.organization_id,now()
       )
       or not atlas.organization_membership_present_effective_at_v1(
         v_target.id,v_target.organization_id,now()
       ) then
      raise exception 'New participation offer requires open Work, live source responsibility, and present-effective offerer/target carriers.'
        using errcode='23514';
    end if;
  end if;

  if new.offer_state='accepted' then
    select * into v_accepted
    from atlas.work_allocations
    where id=new.accepted_allocation_id
      and organization_id=new.organization_id
      and work_item_id=new.work_item_id
      and allocation_role=new.allocation_role
      and state='active'
      and establishment_basis_kind='receiver_acceptance';

    if v_accepted.id is null then
      raise exception 'Accepted participation offer must identify the new active receiver-accepted allocation.'
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
       or coalesce(v_accepted.establishment_basis->>'sourceKind','')<>'company_work_participation_offer'
       or coalesce(v_accepted.establishment_basis->>'sourceId','')<>new.id::text
       or coalesce(v_accepted.establishment_basis->>'allocationRole','')<>new.allocation_role then
      raise exception 'Accepted participation provenance must resolve to target receiver uptake from this exact offer.'
        using errcode='23514';
    end if;
  elsif new.offer_state='declined'
        and new.resolved_by_person_entity_id<>new.target_person_entity_id then
    raise exception 'Only the target Person may decline a participation offer.'
      using errcode='23514';
  elsif new.offer_state='withdrawn'
        and new.resolved_by_person_entity_id<>new.offered_by_person_entity_id then
    raise exception 'Only the offering responsible Person may withdraw a participation offer.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger company_work_participation_offer_guard_v1
before insert or update
on atlas.company_work_participation_offers
for each row
execute function atlas.guard_company_work_participation_offer_v1();

revoke all on function atlas.guard_company_work_participation_offer_v1()
  from public,anon,authenticated,service_role;

create or replace function atlas.guard_work_allocation_participation_establishment_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_offer_id uuid;
begin
  if new.allocation_role not in ('participant','approver') then
    return new;
  end if;

  if tg_op='UPDATE'
     and (
       new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis
     ) then
    raise exception 'Company Work participation establishment provenance is immutable.'
      using errcode='23514';
  end if;

  if new.state<>'active' then
    return new;
  end if;

  if new.establishment_basis_kind<>'receiver_acceptance'
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active Company Work participation requires governed receiver acceptance.'
      using errcode='23514';
  end if;

  if coalesce(new.establishment_basis->>'contractVersion','')<>'company_work_participation_establishment_v1'
     or coalesce(new.establishment_basis->>'basisKind','')<>'receiver_acceptance'
     or coalesce(new.establishment_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(new.establishment_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(new.establishment_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text
     or coalesce(new.establishment_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
     or coalesce(new.establishment_basis->>'allocationRole','')<>new.allocation_role
     or coalesce(new.establishment_basis->>'sourceKind','')<>'company_work_participation_offer'
     or nullif(btrim(coalesce(new.establishment_basis->>'sourceId','')),'') is null then
    raise exception 'Company Work participation establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if new.assigned_by_membership_id is null
     or new.assigned_by_membership_id<>new.assignee_membership_id then
    raise exception 'Receiver-accepted participation must be established by the receiver carrier itself.'
      using errcode='23514';
  end if;

  begin
    v_offer_id:=(new.establishment_basis->>'sourceId')::uuid;
  exception when others then
    raise exception 'Participation sourceId must identify a valid participation offer.'
      using errcode='23514';
  end;

  if not exists(
    select 1
    from atlas.company_work_participation_offers o
    join atlas.organization_memberships m
      on m.organization_id=o.organization_id
     and m.person_id=o.target_person_entity_id
     and m.id=new.assignee_membership_id
    where o.id=v_offer_id
      and o.organization_id=new.organization_id
      and o.work_item_id=new.work_item_id
      and o.allocation_role=new.allocation_role
      and o.offer_state in ('offered','accepted')
  ) then
    raise exception 'Receiver-accepted participation must derive from the exact matching participation offer.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

create trigger work_allocations_participation_establishment_guard_v1
before insert or update of
  allocation_role,state,assignee_membership_id,assigned_by_membership_id,
  establishment_basis_kind,establishment_basis
on atlas.work_allocations
for each row
execute function atlas.guard_work_allocation_participation_establishment_v1();

revoke all on function atlas.guard_work_allocation_participation_establishment_v1()
  from public,anon,authenticated,service_role;

create or replace function atlas.offer_company_work_participation_self_api_v1(
  p_work_item_id uuid,
  p_target_person_entity_id uuid,
  p_allocation_role text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_role text:=lower(btrim(coalesce(p_allocation_role,'')));
  v_work atlas.work_items%rowtype;
  v_responsible atlas.work_allocations%rowtype;
  v_actor_membership_id uuid;
  v_target_membership_id uuid;
  v_target_count integer;
  v_existing atlas.company_work_participation_offers%rowtype;
  v_existing_allocation atlas.work_allocations%rowtype;
  v_offer atlas.company_work_participation_offers%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if v_role not in ('participant','approver') then
    raise exception 'Participation role must be participant or approver.'
      using errcode='22023';
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
    raise exception 'Current responsible Person cannot offer themselves a collaboration role on the same Work.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'atlas.company_work.participation:'
      ||p_work_item_id::text||':'
      ||p_target_person_entity_id::text||':'
      ||v_role,
      0
    )
  );

  select * into v_work
  from atlas.work_items
  where id=p_work_item_id
  for update;

  if v_work.id is null then
    raise exception 'Company Work item not found.' using errcode='P0002';
  end if;

  if v_work.work_state<>'open' then
    raise exception 'Only open Company Work may receive participation offers.'
      using errcode='22023';
  end if;

  v_actor_membership_id:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id
  );

  select * into v_responsible
  from atlas.work_allocations
  where work_item_id=v_work.id
    and organization_id=v_work.organization_id
    and allocation_role='responsible'
    and state='active'
  order by allocated_at desc,id desc
  limit 1
  for update;

  if v_actor_membership_id is null
     or v_responsible.id is null
     or v_responsible.assignee_membership_id<>v_actor_membership_id then
    raise exception 'Only the current exact Work responsibility carrier may offer participation.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=p_target_person_entity_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Participation target must already be a canonical Reality Person.'
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
    raise exception 'Participation target requires exactly one present-effective institutional carrier; found %.',
      v_target_count
      using errcode='23514';
  end if;

  select * into v_existing_allocation
  from atlas.work_allocations
  where work_item_id=v_work.id
    and assignee_membership_id=v_target_membership_id
    and allocation_role=v_role
    and state='active'
  order by allocated_at desc,id desc
  limit 1;

  if v_existing_allocation.id is not null then
    return jsonb_build_object(
      'contractVersion','company_work_participation_offer_v1',
      'state','already_participating',
      'deduplicated',true,
      'workItemId',v_work.id,
      'allocationId',v_existing_allocation.id,
      'allocationRole',v_role,
      'targetPersonEntityId',p_target_person_entity_id
    );
  end if;

  select * into v_existing
  from atlas.company_work_participation_offers
  where work_item_id=v_work.id
    and target_person_entity_id=p_target_person_entity_id
    and allocation_role=v_role
    and offer_state='offered'
  limit 1
  for update;

  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','company_work_participation_offer_v1',
      'state','offered',
      'deduplicated',true,
      'offerId',v_existing.id,
      'workItemId',v_work.id,
      'offeredFromResponsibilityAllocationId',
        v_existing.offered_from_responsibility_allocation_id,
      'offeredByPersonEntityId',v_existing.offered_by_person_entity_id,
      'targetPersonEntityId',v_existing.target_person_entity_id,
      'allocationRole',v_existing.allocation_role
    );
  end if;

  insert into atlas.company_work_participation_offers(
    organization_id,
    work_item_id,
    offered_from_responsibility_allocation_id,
    offered_by_person_entity_id,
    offered_by_membership_id_compatibility,
    target_person_entity_id,
    target_membership_id_compatibility,
    allocation_role,
    reason,
    metadata
  ) values(
    v_work.organization_id,
    v_work.id,
    v_responsible.id,
    v_person_id,
    v_actor_membership_id,
    p_target_person_entity_id,
    v_target_membership_id,
    v_role,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'source','offer_company_work_participation_self_api_v1',
      'truthBoundary','Offer records proposed Work participation. No participant or approver allocation exists until target acceptance.'
    )
  )
  returning * into v_offer;

  return jsonb_build_object(
    'contractVersion','company_work_participation_offer_v1',
    'state','offered',
    'deduplicated',false,
    'offerId',v_offer.id,
    'organizationId',v_offer.organization_id,
    'workItemId',v_offer.work_item_id,
    'offeredFromResponsibilityAllocationId',
      v_offer.offered_from_responsibility_allocation_id,
    'offeredByPersonEntityId',v_offer.offered_by_person_entity_id,
    'targetPersonEntityId',v_offer.target_person_entity_id,
    'allocationRole',v_offer.allocation_role,
    'offeredAt',v_offer.offered_at,
    'participationChanged',false
  );
end
$function$;

revoke all on function atlas.offer_company_work_participation_self_api_v1(
  uuid,uuid,text,text
) from public,anon,service_role;
grant execute on function atlas.offer_company_work_participation_self_api_v1(
  uuid,uuid,text,text
) to authenticated;

create or replace function atlas.company_work_participation_offers_self_api_v1()
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
      'contractVersion','company_work_participation_offers_self_v1',
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
      'offeredByPersonEntityId',o.offered_by_person_entity_id,
      'offeredByDisplayName',offerer.display_name,
      'targetPersonEntityId',o.target_person_entity_id,
      'allocationRole',o.allocation_role,
      'offeredAt',o.offered_at,
      'reason',o.reason
    )
    order by o.offered_at,o.id
  ),'[]'::jsonb)
  into v_incoming
  from atlas.company_work_participation_offers o
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
      'targetPersonEntityId',o.target_person_entity_id,
      'targetDisplayName',target.display_name,
      'allocationRole',o.allocation_role,
      'offeredAt',o.offered_at,
      'reason',o.reason
    )
    order by o.offered_at,o.id
  ),'[]'::jsonb)
  into v_outgoing
  from atlas.company_work_participation_offers o
  join atlas.work_items w on w.id=o.work_item_id
  join reality.entities target on target.id=o.target_person_entity_id
  where o.offered_by_person_entity_id=v_person_id
    and o.offer_state='offered';

  return jsonb_build_object(
    'contractVersion','company_work_participation_offers_self_v1',
    'state','ready',
    'personEntityId',v_person_id,
    'incoming',v_incoming,
    'outgoing',v_outgoing,
    'truthBoundary',jsonb_build_object(
      'offerIsNotParticipation',true,
      'acceptanceEstablishesReceiverParticipation',true,
      'responsibilityRemainsSeparate',true
    )
  );
end
$function$;

revoke all on function atlas.company_work_participation_offers_self_api_v1()
  from public,anon,service_role;
grant execute on function atlas.company_work_participation_offers_self_api_v1()
  to authenticated;

create or replace function atlas.respond_company_work_participation_offer_self_api_v1(
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
  v_offer atlas.company_work_participation_offers%rowtype;
  v_work atlas.work_items%rowtype;
  v_source atlas.work_allocations%rowtype;
  v_receiver_membership_id uuid;
  v_receiver_membership_count integer;
  v_existing atlas.work_allocations%rowtype;
  v_new_allocation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if v_decision not in ('accepted','declined') then
    raise exception 'Participation decision must be accepted or declined.'
      using errcode='22023';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Reality Person required.' using errcode='42501';
  end if;

  select * into v_offer
  from atlas.company_work_participation_offers
  where id=p_offer_id
  for update;

  if v_offer.id is null then
    raise exception 'Company Work participation offer not found.'
      using errcode='P0002';
  end if;

  if v_offer.target_person_entity_id<>v_person_id then
    raise exception 'Only the target Reality Person may respond to this participation offer.'
      using errcode='42501';
  end if;

  if v_offer.offer_state<>'offered' then
    if (v_offer.offer_state='accepted' and v_decision='accepted')
       or (v_offer.offer_state='declined' and v_decision='declined') then
      return jsonb_build_object(
        'contractVersion','company_work_participation_response_v1',
        'state',v_offer.offer_state,
        'deduplicated',true,
        'offerId',v_offer.id,
        'workItemId',v_offer.work_item_id,
        'allocationRole',v_offer.allocation_role,
        'acceptedAllocationId',v_offer.accepted_allocation_id
      );
    end if;

    raise exception 'This participation offer is already resolved as %.',
      v_offer.offer_state
      using errcode='23514';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'atlas.company_work.participation:'
      ||v_offer.work_item_id::text||':'
      ||v_offer.target_person_entity_id::text||':'
      ||v_offer.allocation_role,
      0
    )
  );

  select * into v_work
  from atlas.work_items
  where id=v_offer.work_item_id
    and organization_id=v_offer.organization_id
  for update;

  if v_work.id is null then
    raise exception 'Participation Work item not found.'
      using errcode='P0002';
  end if;

  select count(*)::integer,
         (array_agg(id order by created_at,id))[1]
  into v_receiver_membership_count,v_receiver_membership_id
  from atlas.organization_memberships
  where organization_id=v_offer.organization_id
    and person_id=v_person_id
    and atlas.organization_membership_present_effective_at_v1(
      id,organization_id,now()
    );

  if v_receiver_membership_count<>1 then
    raise exception 'Target Person requires exactly one current institutional carrier to respond; found %.',
      v_receiver_membership_count
      using errcode='23514';
  end if;

  if v_decision='declined' then
    update atlas.company_work_participation_offers
    set offer_state='declined',
        resolved_at=now(),
        resolved_by_person_entity_id=v_person_id,
        resolved_by_membership_id_compatibility=v_receiver_membership_id,
        resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
    where id=v_offer.id;

    return jsonb_build_object(
      'contractVersion','company_work_participation_response_v1',
      'state','declined',
      'deduplicated',false,
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id,
      'allocationRole',v_offer.allocation_role,
      'participationChanged',false
    );
  end if;

  select * into v_source
  from atlas.work_allocations
  where id=v_offer.offered_from_responsibility_allocation_id
    and organization_id=v_offer.organization_id
    and work_item_id=v_offer.work_item_id
    and allocation_role='responsible'
  for update;

  if v_work.work_state<>'open'
     or v_source.id is null
     or v_source.state<>'active'
     or not exists(
       select 1
       from atlas.work_allocations
       where work_item_id=v_work.id
         and allocation_role='responsible'
         and state='active'
         and id=v_source.id
     ) then
    update atlas.company_work_participation_offers
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
      'contractVersion','company_work_participation_response_v1',
      'state','stale',
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id,
      'allocationRole',v_offer.allocation_role,
      'participationChanged',false
    );
  end if;

  select * into v_existing
  from atlas.work_allocations
  where work_item_id=v_work.id
    and assignee_membership_id=v_receiver_membership_id
    and allocation_role=v_offer.allocation_role
    and state='active'
  order by allocated_at desc,id desc
  limit 1
  for update;

  if v_existing.id is not null then
    if v_existing.establishment_basis_kind='receiver_acceptance'
       and coalesce(v_existing.establishment_basis->>'sourceId','')=v_offer.id::text then
      update atlas.company_work_participation_offers
      set offer_state='accepted',
          resolved_at=now(),
          resolved_by_person_entity_id=v_person_id,
          resolved_by_membership_id_compatibility=v_receiver_membership_id,
          accepted_allocation_id=v_existing.id,
          resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
      where id=v_offer.id;

      return jsonb_build_object(
        'contractVersion','company_work_participation_response_v1',
        'state','accepted',
        'deduplicated',true,
        'offerId',v_offer.id,
        'workItemId',v_offer.work_item_id,
        'allocationRole',v_offer.allocation_role,
        'acceptedAllocationId',v_existing.id,
        'participationChanged',false
      );
    end if;

    update atlas.company_work_participation_offers
    set offer_state='stale',
        resolved_at=now(),
        resolved_by_person_entity_id=v_person_id,
        resolved_by_membership_id_compatibility=v_receiver_membership_id,
        resolution_reason='participation_already_established_by_other_source'
    where id=v_offer.id;

    return jsonb_build_object(
      'contractVersion','company_work_participation_response_v1',
      'state','stale',
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id,
      'allocationRole',v_offer.allocation_role,
      'participationChanged',false
    );
  end if;

  insert into atlas.work_allocations(
    organization_id,
    work_item_id,
    assignee_membership_id,
    assigned_by_membership_id,
    allocation_role,
    state,
    establishment_basis_kind,
    establishment_basis,
    metadata
  ) values(
    v_offer.organization_id,
    v_offer.work_item_id,
    v_receiver_membership_id,
    v_receiver_membership_id,
    v_offer.allocation_role,
    'active',
    'receiver_acceptance',
    jsonb_build_object(
      'contractVersion','company_work_participation_establishment_v1',
      'basisKind','receiver_acceptance',
      'organizationId',v_offer.organization_id,
      'workItemId',v_offer.work_item_id,
      'assigneeMembershipId',v_receiver_membership_id,
      'actorMembershipId',v_receiver_membership_id,
      'allocationRole',v_offer.allocation_role,
      'sourceKind','company_work_participation_offer',
      'sourceId',v_offer.id,
      'offeredByPersonEntityId',v_offer.offered_by_person_entity_id,
      'targetPersonEntityId',v_offer.target_person_entity_id
    ),
    jsonb_build_object(
      'source','respond_company_work_participation_offer_self_api_v1',
      'participationOfferId',v_offer.id,
      'receiverUptake',true
    )
  )
  returning id into v_new_allocation_id;

  update atlas.company_work_participation_offers
  set offer_state='accepted',
      resolved_at=now(),
      resolved_by_person_entity_id=v_person_id,
      resolved_by_membership_id_compatibility=v_receiver_membership_id,
      accepted_allocation_id=v_new_allocation_id,
      resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=v_offer.id;

  return jsonb_build_object(
    'contractVersion','company_work_participation_response_v1',
    'state','accepted',
    'deduplicated',false,
    'offerId',v_offer.id,
    'organizationId',v_offer.organization_id,
    'workItemId',v_offer.work_item_id,
    'allocationRole',v_offer.allocation_role,
    'acceptedAllocationId',v_new_allocation_id,
    'participantPersonEntityId',v_person_id,
    'establishmentBasis','receiver_acceptance',
    'participationChanged',true,
    'responsibilityChanged',false
  );
end
$function$;

revoke all on function atlas.respond_company_work_participation_offer_self_api_v1(
  uuid,text,text
) from public,anon,service_role;
grant execute on function atlas.respond_company_work_participation_offer_self_api_v1(
  uuid,text,text
) to authenticated;

create or replace function atlas.withdraw_company_work_participation_offer_self_api_v1(
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
  v_offer atlas.company_work_participation_offers%rowtype;
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
  from atlas.company_work_participation_offers
  where id=p_offer_id
  for update;

  if v_offer.id is null then
    raise exception 'Company Work participation offer not found.'
      using errcode='P0002';
  end if;

  if v_offer.offered_by_person_entity_id<>v_person_id then
    raise exception 'Only the offering responsible Person may withdraw this participation offer.'
      using errcode='42501';
  end if;

  if v_offer.offer_state='withdrawn' then
    return jsonb_build_object(
      'contractVersion','company_work_participation_withdraw_v1',
      'state','withdrawn',
      'deduplicated',true,
      'offerId',v_offer.id,
      'workItemId',v_offer.work_item_id,
      'allocationRole',v_offer.allocation_role
    );
  end if;

  if v_offer.offer_state<>'offered' then
    raise exception 'Resolved participation offer cannot be withdrawn.'
      using errcode='23514';
  end if;

  v_actor_membership_id:=atlas.current_effective_organization_membership_v1(
    v_offer.organization_id
  );

  if v_actor_membership_id is null then
    raise exception 'Offering Person no longer has a present-effective institutional carrier.'
      using errcode='42501';
  end if;

  update atlas.company_work_participation_offers
  set offer_state='withdrawn',
      resolved_at=now(),
      resolved_by_person_entity_id=v_person_id,
      resolved_by_membership_id_compatibility=v_actor_membership_id,
      resolution_reason=nullif(btrim(coalesce(p_reason,'')),'')
  where id=v_offer.id;

  return jsonb_build_object(
    'contractVersion','company_work_participation_withdraw_v1',
    'state','withdrawn',
    'deduplicated',false,
    'offerId',v_offer.id,
    'workItemId',v_offer.work_item_id,
    'allocationRole',v_offer.allocation_role,
    'participationChanged',false
  );
end
$function$;

revoke all on function atlas.withdraw_company_work_participation_offer_self_api_v1(
  uuid,text
) from public,anon,service_role;
grant execute on function atlas.withdraw_company_work_participation_offer_self_api_v1(
  uuid,text
) to authenticated;

create or replace function atlas.add_institutional_conversation_collaborator_self_api_v1(
  p_institutional_conversation_id uuid,
  p_target_membership_id uuid,
  p_allocation_role text default 'participant'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_role text:=lower(btrim(coalesce(p_allocation_role,'')));
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_endpoint_id uuid;
  v_target atlas.organization_memberships%rowtype;
  v_offer jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if v_role not in ('participant','approver') then
    raise exception 'Collaborator role must be participant or approver.'
      using errcode='22023';
  end if;

  select * into v_conv
  from atlas.institutional_conversations
  where id=p_institutional_conversation_id
    and conversation_state='open';

  if v_conv.id is null then
    raise exception 'Open institutional conversation not found.'
      using errcode='P0002';
  end if;

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
    raise exception 'Conversation must be claimed before collaboration can be offered.'
      using errcode='22023';
  end if;

  select communication_endpoint_id
  into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,
           created_at
  limit 1;

  select * into v_target
  from atlas.organization_memberships
  where id=p_target_membership_id
    and organization_id=v_conv.organization_id
    and atlas.organization_membership_present_effective_at_v1(
      id,organization_id,now()
    );

  if v_target.id is null or v_target.person_id is null then
    raise exception 'Collaboration target must be a present-effective institutional Person.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from reality.entities
    where id=v_target.person_id
      and entity_kind='person'
      and identity_state='canonical'
  ) then
    raise exception 'Collaboration target must be promoted to a canonical Reality Person before participation can be offered.'
      using errcode='23514';
  end if;

  if not atlas.communication_endpoint_membership_has_capability_v1(
    v_endpoint_id,v_target.id,'view'
  ) then
    raise exception 'Communication collaboration target must already be able to view the source endpoint.'
      using errcode='42501';
  end if;

  v_offer:=atlas.offer_company_work_participation_self_api_v1(
    v_binding.work_item_id,
    v_target.person_id,
    v_role,
    'institutional_conversation_collaboration_offer'
  );

  return jsonb_build_object(
    'contractVersion','institutional_conversation_collaborator_offer_v1',
    'state',v_offer->>'state',
    'institutionalConversationId',v_conv.id,
    'responseCaseId',v_case.id,
    'workItemId',v_binding.work_item_id,
    'targetMembershipId',v_target.id,
    'targetPersonEntityId',v_target.person_id,
    'allocationRole',v_role,
    'participationOfferId',v_offer->>'offerId',
    'acceptedAllocationId',v_offer->>'allocationId',
    'participationChanged',false,
    'receiverAcceptanceRequired',true
  );
end
$function$;

revoke all on function atlas.add_institutional_conversation_collaborator_self_api_v1(
  uuid,uuid,text
) from public,anon,service_role;
grant execute on function atlas.add_institutional_conversation_collaborator_self_api_v1(
  uuid,uuid,text
) to authenticated;

comment on function atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) is
  'Communication compatibility adapter for Company Work collaboration uptake. It may offer participant/approver participation only when the target already has source endpoint visibility; it never assigns a collaborator directly.';

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.offer_company_work_participation_self_api_v1(uuid,uuid,text,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','exact_work_responsibility',
    'purpose','Current exact responsible Person offers bounded participant/approver participation without creating an allocation.',
    'truthBoundary','Offer is not participation. Target acceptance is required.'
  ),
  now(),false
),
(
  'atlas.company_work_participation_offers_self_api_v1()',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'purpose','Read current Reality Person incoming/outgoing Company Work participation offers.',
    'truthBoundary','Raw offer table is not browser-readable.'
  ),
  now(),false
),
(
  'atlas.respond_company_work_participation_offer_self_api_v1(uuid,text,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','target_reality_person_acceptance',
    'purpose','Target Reality Person accepts or declines exact participant/approver participation.',
    'truthBoundary','Acceptance creates receiver-established participation and never changes exact responsibility.'
  ),
  now(),false
),
(
  'atlas.withdraw_company_work_participation_offer_self_api_v1(uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'authoritySource','offering_exact_responsible_person',
    'purpose','Offering responsible Person withdraws unresolved participation offer.',
    'truthBoundary','Withdrawal creates no Work allocation.'
  ),
  now(),false
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
set authenticated_execute_expected=true,
    service_execute_expected=false,
    anonymous_execute_expected=false,
    evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'state','governed_receiver_uptake_offer',
      'truthBoundary','Direct collaborator assignment is replaced by an offer. Target Reality Person acceptance establishes participant/approver allocation.'
    ),
    reviewed_at=now()
where signature='atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)';

commit;
