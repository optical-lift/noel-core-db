create or replace function ledger.guard_booking_offering_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_ledger_state text;
  v_seat_ledger uuid;
begin
  select l.ledger_state into v_ledger_state from ledger.ledgers l where l.id=new.ledger_id;
  if v_ledger_state is null then
    raise exception 'Booking offering requires a Ledger.' using errcode='23514';
  end if;
  if new.offering_state in ('draft','active') and v_ledger_state<>'active' then
    raise exception 'Draft or active booking offering requires an active Ledger.' using errcode='23514';
  end if;
  if new.created_by_seat_id is not null then
    select s.ledger_id into v_seat_ledger from ledger.seats s where s.id=new.created_by_seat_id;
    if v_seat_ledger is null or v_seat_ledger<>new.ledger_id then
      raise exception 'Booking offering creator Seat must belong to the offering Ledger.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

create or replace function ledger.guard_booking_offering_routing_candidate_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_requirement ledger.booking_offering_requirements%rowtype;
  v_ledger_id uuid;
  v_subject_entity_id uuid;
  v_resource_kind text;
  v_resource_owner uuid;
  v_seat_ledger uuid;
begin
  select r.* into v_requirement
  from ledger.booking_offering_routing_policies p
  join ledger.booking_offering_requirements r on r.id=p.requirement_id
  where p.id=new.routing_policy_id;
  if v_requirement.id is null then
    raise exception 'Routing candidate requires a valid requirement.' using errcode='23514';
  end if;

  select o.ledger_id,l.subject_entity_id into v_ledger_id,v_subject_entity_id
  from ledger.booking_offerings o
  join ledger.ledgers l on l.id=o.ledger_id
  where o.id=v_requirement.offering_id;

  if v_requirement.requirement_kind='resource' then
    if new.candidate_kind<>'resource' then
      raise exception 'Resource requirement routing candidates must be Resources.' using errcode='23514';
    end if;
    select r.owner_entity_id,r.resource_kind into v_resource_owner,v_resource_kind
    from reality.resources r where r.id=new.resource_id;
    if v_resource_owner is null or v_resource_owner<>v_subject_entity_id then
      raise exception 'Routing Resource must belong to the offering Ledger subject.' using errcode='23514';
    end if;
    if v_requirement.resource_id is not null and new.resource_id<>v_requirement.resource_id then
      raise exception 'Routing Resource must match the specific Resource requirement.' using errcode='23514';
    end if;
    if v_requirement.resource_kind is not null and v_resource_kind<>v_requirement.resource_kind then
      raise exception 'Routing Resource must match the required Resource kind.' using errcode='23514';
    end if;
  else
    if new.candidate_kind<>'seat' then
      raise exception 'Seat responsibility routing candidates must be Seats.' using errcode='23514';
    end if;
    select s.ledger_id into v_seat_ledger from ledger.seats s where s.id=new.seat_id;
    if v_seat_ledger is null or v_seat_ledger<>v_ledger_id then
      raise exception 'Routing Seat must belong to the offering Ledger.' using errcode='23514';
    end if;
    if new.candidate_state='active' and not exists(
      select 1 from ledger.seat_responsibilities sr
      where sr.seat_id=new.seat_id
        and sr.responsibility_key=v_requirement.seat_responsibility_key
        and sr.responsibility_state='active'
        and (sr.ended_at is null or sr.ended_at>now())
    ) then
      raise exception 'Active routing Seat must currently satisfy the required responsibility.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

create or replace function ledger.booking_offering_detail_v1(p_offering_id uuid)
returns jsonb
language sql stable security definer set search_path='' as $$
  select case when o.id is null then null else jsonb_build_object(
    'contractVersion','ledger_booking_offering_detail_v1',
    'offeringId',o.id,
    'ledgerId',o.ledger_id,
    'stableKey',o.stable_key,
    'name',o.name,
    'description',o.description,
    'bookingKind',o.booking_kind,
    'occurrenceType',o.occurrence_type,
    'defaultDurationMinutes',o.default_duration_minutes,
    'offeringState',o.offering_state,
    'createdBySeatId',o.created_by_seat_id,
    'metadata',o.metadata,
    'provenance',o.provenance,
    'createdAt',o.created_at,
    'updatedAt',o.updated_at,
    'groups',coalesce((
      select jsonb_agg(jsonb_build_object(
        'groupId',g.id,'parentGroupId',g.parent_group_id,'stableKey',g.stable_key,
        'label',g.label,'satisfactionMode',g.satisfaction_mode,'minimumSatisfied',g.minimum_satisfied,
        'groupState',g.group_state,'sortOrder',g.sort_order,'metadata',g.metadata
      ) order by g.sort_order,g.stable_key,g.id)
      from ledger.booking_offering_requirement_groups g where g.offering_id=o.id
    ),'[]'::jsonb),
    'requirements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'requirementId',r.id,'groupId',r.group_id,'stableKey',r.stable_key,'label',r.label,
        'requirementKind',r.requirement_kind,'requirementState',r.requirement_state,
        'requiredUnits',r.required_units,'resourceId',r.resource_id,'resourceKind',r.resource_kind,
        'claimKind',r.claim_kind,'claimQuantity',r.claim_quantity,'claimQuantityUnit',r.claim_quantity_unit,
        'seatResponsibilityKey',r.seat_responsibility_key,'sortOrder',r.sort_order,'metadata',r.metadata
      ) order by r.sort_order,r.stable_key,r.id)
      from ledger.booking_offering_requirements r where r.offering_id=o.id
    ),'[]'::jsonb),
    'routingPolicies',coalesce((
      select jsonb_agg(jsonb_build_object(
        'routingPolicyId',p.id,'requirementId',p.requirement_id,'routingMode',p.routing_mode,
        'policyState',p.policy_state,'metadata',p.metadata,
        'candidates',coalesce((
          select jsonb_agg(jsonb_build_object(
            'candidateId',c.id,'candidateKind',c.candidate_kind,'resourceId',c.resource_id,
            'seatId',c.seat_id,'priority',c.priority,'candidateState',c.candidate_state,'metadata',c.metadata
          ) order by c.priority,c.id)
          from ledger.booking_offering_routing_candidates c where c.routing_policy_id=p.id
        ),'[]'::jsonb)
      ) order by p.requirement_id,p.id)
      from ledger.booking_offering_routing_policies p where p.offering_id=o.id
    ),'[]'::jsonb)
  ) end
  from ledger.booking_offerings o where o.id=p_offering_id;
$$;

create or replace function ledger.booking_offerings_service_v1(
  p_ledger_id uuid,
  p_offering_state text default null
) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'contractVersion','ledger_booking_offerings_v1',
    'ledgerId',p_ledger_id,
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'offeringId',o.id,'stableKey',o.stable_key,'name',o.name,'description',o.description,
      'bookingKind',o.booking_kind,'occurrenceType',o.occurrence_type,
      'defaultDurationMinutes',o.default_duration_minutes,'offeringState',o.offering_state,
      'updatedAt',o.updated_at
    ) order by o.name,o.stable_key) filter (where o.id is not null),'[]'::jsonb)
  )
  from ledger.booking_offerings o
  where o.ledger_id=p_ledger_id
    and (p_offering_state is null or o.offering_state=p_offering_state);
$$;

create or replace function ledger.upsert_booking_offering_service_v1(
  p_ledger_id uuid,
  p_stable_key text,
  p_name text,
  p_booking_kind text,
  p_occurrence_type text,
  p_default_duration_minutes integer,
  p_description text default null,
  p_offering_state text default 'draft',
  p_created_by_seat_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_offering_id uuid;
begin
  if nullif(btrim(p_stable_key),'') is null
     or nullif(btrim(p_name),'') is null
     or nullif(btrim(p_booking_kind),'') is null
     or nullif(btrim(p_occurrence_type),'') is null
     or p_default_duration_minutes is null or p_default_duration_minutes<=0 then
    raise exception 'Booking offering stable key, name, booking kind, occurrence type, and positive duration are required.' using errcode='22023';
  end if;
  if p_offering_state not in ('draft','active','inactive','retired') then
    raise exception 'Unknown booking offering state: %',p_offering_state using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Booking offering metadata/provenance must be JSON objects.' using errcode='22023';
  end if;

  insert into ledger.booking_offerings(
    ledger_id,stable_key,name,description,booking_kind,occurrence_type,default_duration_minutes,
    offering_state,created_by_seat_id,metadata,provenance
  ) values(
    p_ledger_id,btrim(p_stable_key),btrim(p_name),nullif(btrim(p_description),''),btrim(p_booking_kind),
    btrim(p_occurrence_type),p_default_duration_minutes,p_offering_state,p_created_by_seat_id,p_metadata,p_provenance
  )
  on conflict (ledger_id,stable_key) do update set
    name=excluded.name,
    description=excluded.description,
    booking_kind=excluded.booking_kind,
    occurrence_type=excluded.occurrence_type,
    default_duration_minutes=excluded.default_duration_minutes,
    offering_state=excluded.offering_state,
    metadata=excluded.metadata,
    provenance=excluded.provenance
  returning id into v_offering_id;

  return ledger.booking_offering_detail_v1(v_offering_id);
end;
$$;

create or replace function ledger.replace_booking_offering_requirement_graph_service_v1(
  p_offering_id uuid,
  p_groups jsonb,
  p_requirements jsonb,
  p_routing_policies jsonb default '[]'::jsonb,
  p_routing_candidates jsonb default '[]'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_offering ledger.booking_offerings%rowtype;
  v_group jsonb;
  v_requirement jsonb;
  v_policy jsonb;
  v_candidate jsonb;
  v_group_id uuid;
  v_requirement_id uuid;
  v_policy_id uuid;
  v_parent_id uuid;
  v_total integer;
  v_inserted integer;
  v_pass integer:=0;
  v_root_count integer;
begin
  if p_groups is null or jsonb_typeof(p_groups)<>'array' or jsonb_array_length(p_groups)=0
     or p_requirements is null or jsonb_typeof(p_requirements)<>'array'
     or p_routing_policies is null or jsonb_typeof(p_routing_policies)<>'array'
     or p_routing_candidates is null or jsonb_typeof(p_routing_candidates)<>'array'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Offering graph inputs must be JSON arrays and provenance must be an object.' using errcode='22023';
  end if;

  select * into v_offering from ledger.booking_offerings o where o.id=p_offering_id for update;
  if v_offering.id is null then raise exception 'Booking offering not found.' using errcode='P0002'; end if;
  if v_offering.offering_state='active' then
    raise exception 'Deactivate a booking offering before replacing its requirement graph.' using errcode='23514';
  end if;
  if v_offering.offering_state='retired' then
    raise exception 'Retired booking offering definition cannot be replaced.' using errcode='23514';
  end if;

  select count(*) into v_root_count
  from jsonb_array_elements(p_groups) x
  where nullif(x->>'parentGroupKey','') is null;
  if v_root_count<>1 then
    raise exception 'Booking offering requirement graph requires exactly one root group.' using errcode='22023';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_groups) x
    where jsonb_typeof(x)<>'object' or nullif(btrim(x->>'stableKey'),'') is null
      or coalesce(x->>'satisfactionMode','all') not in ('all','any','minimum')
  ) then
    raise exception 'Every requirement group requires a stableKey and valid satisfactionMode.' using errcode='22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_groups)) <>
     (select count(distinct x->>'stableKey') from jsonb_array_elements(p_groups) x) then
    raise exception 'Requirement group stable keys must be unique within the offering.' using errcode='22023';
  end if;

  delete from ledger.booking_offering_requirement_groups where offering_id=p_offering_id;

  for v_group in
    select value from jsonb_array_elements(p_groups)
    where nullif(value->>'parentGroupKey','') is null
  loop
    insert into ledger.booking_offering_requirement_groups(
      offering_id,parent_group_id,stable_key,label,satisfaction_mode,minimum_satisfied,group_state,sort_order,metadata,provenance
    ) values(
      p_offering_id,null,btrim(v_group->>'stableKey'),nullif(btrim(v_group->>'label'),''),
      coalesce(v_group->>'satisfactionMode','all'),
      case when coalesce(v_group->>'satisfactionMode','all')='minimum' then (v_group->>'minimumSatisfied')::integer else null end,
      coalesce(v_group->>'groupState','active'),coalesce((v_group->>'sortOrder')::integer,0),
      coalesce(v_group->'metadata','{}'::jsonb),p_provenance
    );
  end loop;

  v_total:=jsonb_array_length(p_groups);
  while (select count(*) from ledger.booking_offering_requirement_groups where offering_id=p_offering_id) < v_total loop
    v_pass:=v_pass+1;
    if v_pass>v_total then
      raise exception 'Requirement group parent references are cyclic or unresolved.' using errcode='22023';
    end if;
    v_inserted:=0;
    for v_group in
      select value from jsonb_array_elements(p_groups) x
      where nullif(value->>'parentGroupKey','') is not null
        and not exists(
          select 1 from ledger.booking_offering_requirement_groups g
          where g.offering_id=p_offering_id and g.stable_key=value->>'stableKey'
        )
    loop
      select g.id into v_parent_id
      from ledger.booking_offering_requirement_groups g
      where g.offering_id=p_offering_id and g.stable_key=v_group->>'parentGroupKey';
      if v_parent_id is not null then
        insert into ledger.booking_offering_requirement_groups(
          offering_id,parent_group_id,stable_key,label,satisfaction_mode,minimum_satisfied,group_state,sort_order,metadata,provenance
        ) values(
          p_offering_id,v_parent_id,btrim(v_group->>'stableKey'),nullif(btrim(v_group->>'label'),''),
          coalesce(v_group->>'satisfactionMode','all'),
          case when coalesce(v_group->>'satisfactionMode','all')='minimum' then (v_group->>'minimumSatisfied')::integer else null end,
          coalesce(v_group->>'groupState','active'),coalesce((v_group->>'sortOrder')::integer,0),
          coalesce(v_group->'metadata','{}'::jsonb),p_provenance
        );
        v_inserted:=v_inserted+1;
      end if;
    end loop;
    if v_inserted=0 then
      raise exception 'Requirement group parent references are cyclic or unresolved.' using errcode='22023';
    end if;
  end loop;

  if exists(
    select 1 from jsonb_array_elements(p_requirements) x
    where jsonb_typeof(x)<>'object' or nullif(btrim(x->>'stableKey'),'') is null
      or nullif(btrim(x->>'groupKey'),'') is null
      or x->>'requirementKind' not in ('resource','seat_responsibility')
  ) then
    raise exception 'Every requirement requires stableKey, groupKey, and a valid requirementKind.' using errcode='22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_requirements)) <>
     (select count(distinct x->>'stableKey') from jsonb_array_elements(p_requirements) x) then
    raise exception 'Requirement stable keys must be unique within the offering.' using errcode='22023';
  end if;

  for v_requirement in select value from jsonb_array_elements(p_requirements)
  loop
    select g.id into v_group_id from ledger.booking_offering_requirement_groups g
    where g.offering_id=p_offering_id and g.stable_key=v_requirement->>'groupKey';
    if v_group_id is null then
      raise exception 'Requirement % references unknown group %',v_requirement->>'stableKey',v_requirement->>'groupKey' using errcode='22023';
    end if;
    insert into ledger.booking_offering_requirements(
      offering_id,group_id,stable_key,label,requirement_kind,requirement_state,required_units,
      resource_id,resource_kind,claim_kind,claim_quantity,claim_quantity_unit,seat_responsibility_key,
      sort_order,metadata,provenance
    ) values(
      p_offering_id,v_group_id,btrim(v_requirement->>'stableKey'),nullif(btrim(v_requirement->>'label'),''),
      v_requirement->>'requirementKind',coalesce(v_requirement->>'requirementState','active'),
      coalesce((v_requirement->>'requiredUnits')::integer,1),
      case when nullif(v_requirement->>'resourceId','') is null then null else (v_requirement->>'resourceId')::uuid end,
      nullif(btrim(v_requirement->>'resourceKind'),''),nullif(v_requirement->>'claimKind',''),
      case when nullif(v_requirement->>'claimQuantity','') is null then null else (v_requirement->>'claimQuantity')::numeric end,
      nullif(btrim(v_requirement->>'claimQuantityUnit'),''),nullif(btrim(v_requirement->>'seatResponsibilityKey'),''),
      coalesce((v_requirement->>'sortOrder')::integer,0),coalesce(v_requirement->'metadata','{}'::jsonb),p_provenance
    );
  end loop;

  for v_policy in select value from jsonb_array_elements(p_routing_policies)
  loop
    select r.id into v_requirement_id from ledger.booking_offering_requirements r
    where r.offering_id=p_offering_id and r.stable_key=v_policy->>'requirementKey';
    if v_requirement_id is null then
      raise exception 'Routing policy references unknown requirement %',v_policy->>'requirementKey' using errcode='22023';
    end if;
    insert into ledger.booking_offering_routing_policies(
      offering_id,requirement_id,routing_mode,policy_state,metadata,provenance
    ) values(
      p_offering_id,v_requirement_id,coalesce(v_policy->>'routingMode','manual'),
      coalesce(v_policy->>'policyState','active'),coalesce(v_policy->'metadata','{}'::jsonb),p_provenance
    );
  end loop;

  for v_candidate in select value from jsonb_array_elements(p_routing_candidates)
  loop
    select p.id into v_policy_id
    from ledger.booking_offering_routing_policies p
    join ledger.booking_offering_requirements r on r.id=p.requirement_id
    where p.offering_id=p_offering_id and r.stable_key=v_candidate->>'requirementKey';
    if v_policy_id is null then
      raise exception 'Routing candidate requires a routing policy for requirement %',v_candidate->>'requirementKey' using errcode='22023';
    end if;
    insert into ledger.booking_offering_routing_candidates(
      routing_policy_id,candidate_kind,resource_id,seat_id,priority,candidate_state,metadata,provenance
    ) values(
      v_policy_id,v_candidate->>'candidateKind',
      case when nullif(v_candidate->>'resourceId','') is null then null else (v_candidate->>'resourceId')::uuid end,
      case when nullif(v_candidate->>'seatId','') is null then null else (v_candidate->>'seatId')::uuid end,
      coalesce((v_candidate->>'priority')::integer,100),coalesce(v_candidate->>'candidateState','active'),
      coalesce(v_candidate->'metadata','{}'::jsonb),p_provenance
    );
  end loop;

  return ledger.booking_offering_detail_v1(p_offering_id);
end;
$$;

create or replace function ledger.booking_offering_requirement_candidates_v1(
  p_offering_id uuid,
  p_requirement_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_requirement ledger.booking_offering_requirements%rowtype;
  v_ledger_id uuid;
  v_subject_entity_id uuid;
  v_routing_mode text:='manual';
  v_policy_id uuid;
  v_has_explicit boolean:=false;
  v_candidates jsonb:='[]'::jsonb;
  v_candidate_count integer:=0;
  v_recommended jsonb:=null;
  v_potential boolean:=false;
  v_time_verified boolean:=false;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Offering evaluation requires startsAt < endsAt.' using errcode='22023';
  end if;
  select r.* into v_requirement from ledger.booking_offering_requirements r
  where r.id=p_requirement_id and r.offering_id=p_offering_id and r.requirement_state='active';
  if v_requirement.id is null then raise exception 'Active booking offering requirement not found.' using errcode='P0002'; end if;
  select o.ledger_id,l.subject_entity_id into v_ledger_id,v_subject_entity_id
  from ledger.booking_offerings o join ledger.ledgers l on l.id=o.ledger_id
  where o.id=p_offering_id;

  select p.id,p.routing_mode into v_policy_id,v_routing_mode
  from ledger.booking_offering_routing_policies p
  where p.requirement_id=p_requirement_id and p.policy_state='active';
  if v_policy_id is not null then
    select exists(select 1 from ledger.booking_offering_routing_candidates c where c.routing_policy_id=v_policy_id and c.candidate_state='active') into v_has_explicit;
  end if;

  if v_requirement.requirement_kind='resource' then
    with candidates as (
      select r.id,r.stable_key,r.label,r.resource_kind,r.capacity_mode,
             coalesce(c.priority,100) as priority,
             ledger.resource_claim_availability_v1(
               v_ledger_id,r.id,p_starts_at,p_ends_at,v_requirement.claim_kind,v_requirement.claim_quantity,null,null
             ) as availability
      from reality.resources r
      left join ledger.booking_offering_routing_candidates c
        on c.routing_policy_id=v_policy_id and c.resource_id=r.id and c.candidate_state='active'
      where r.owner_entity_id=v_subject_entity_id
        and r.resource_state='active'
        and r.reservable
        and (v_requirement.resource_id is null or r.id=v_requirement.resource_id)
        and (v_requirement.resource_kind is null or r.resource_kind=v_requirement.resource_kind)
        and (not v_has_explicit or c.id is not null)
    ), packed as (
      select *,coalesce((availability->>'available')::boolean,false) as is_available from candidates
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'candidateKind','resource','resourceId',id,'stableKey',stable_key,'label',label,
             'resourceKind',resource_kind,'capacityMode',capacity_mode,'priority',priority,
             'available',is_available,'availabilityKnown',true,'availability',availability
           ) order by priority,label,id),'[]'::jsonb),
           count(*) filter (where is_available)
      into v_candidates,v_candidate_count
    from packed;
    v_potential:=v_candidate_count>=v_requirement.required_units;
    v_time_verified:=v_potential;
  else
    with candidates as (
      select distinct s.id as seat_id,s.person_entity_id,e.display_name,coalesce(c.priority,100) as priority
      from ledger.seats s
      join ledger.seat_responsibilities sr on sr.seat_id=s.id
      join reality.entities e on e.id=s.person_entity_id
      left join ledger.booking_offering_routing_candidates c
        on c.routing_policy_id=v_policy_id and c.seat_id=s.id and c.candidate_state='active'
      where s.ledger_id=v_ledger_id and s.seat_state='active'
        and (s.ended_at is null or s.ended_at>now())
        and sr.responsibility_key=v_requirement.seat_responsibility_key
        and sr.responsibility_state='active'
        and (sr.ended_at is null or sr.ended_at>now())
        and (not v_has_explicit or c.id is not null)
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'candidateKind','seat','seatId',seat_id,'personEntityId',person_entity_id,
             'displayName',display_name,'priority',priority,'eligible',true,
             'availabilityKnown',false
           ) order by priority,display_name,seat_id),'[]'::jsonb),count(*)
      into v_candidates,v_candidate_count
    from candidates;
    v_potential:=v_candidate_count>=v_requirement.required_units;
    v_time_verified:=false;
  end if;

  if v_routing_mode in ('first_eligible','ordered_priority') and v_candidate_count>0 then
    if v_requirement.requirement_kind='resource' then
      select value into v_recommended
      from jsonb_array_elements(v_candidates)
      where coalesce((value->>'available')::boolean,false)
      order by (value->>'priority')::integer,coalesce(value->>'label',''),value->>'resourceId'
      limit 1;
    else
      select value into v_recommended
      from jsonb_array_elements(v_candidates)
      order by (value->>'priority')::integer,coalesce(value->>'displayName',''),value->>'seatId'
      limit 1;
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_booking_offering_requirement_candidates_v1',
    'offeringId',p_offering_id,'requirementId',v_requirement.id,'stableKey',v_requirement.stable_key,
    'label',v_requirement.label,'requirementKind',v_requirement.requirement_kind,
    'requiredUnits',v_requirement.required_units,'routingMode',v_routing_mode,
    'candidateCount',v_candidate_count,'potentiallySatisfiable',v_potential,
    'fullyTimeVerified',v_time_verified,'candidates',v_candidates,'recommendedCandidate',v_recommended,
    'timeAvailabilityBoundary',case when v_requirement.requirement_kind='seat_responsibility'
      then 'seat_eligibility_known_person_free_busy_not_yet_canonical' else 'resource_availability_verified' end
  );
end;
$$;

create or replace function ledger.booking_offering_group_evaluation_v1(
  p_group_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_group ledger.booking_offering_requirement_groups%rowtype;
  v_requirements jsonb:='[]'::jsonb;
  v_groups jsonb:='[]'::jsonb;
  v_child jsonb;
  v_total integer:=0;
  v_potential_count integer:=0;
  v_verified_count integer:=0;
  v_needed integer:=0;
  v_potential boolean:=false;
  v_verified boolean:=false;
  v_requirement record;
  v_subgroup record;
begin
  select * into v_group from ledger.booking_offering_requirement_groups g where g.id=p_group_id and g.group_state='active';
  if v_group.id is null then raise exception 'Active requirement group not found.' using errcode='P0002'; end if;

  for v_requirement in
    select r.id from ledger.booking_offering_requirements r
    where r.group_id=v_group.id and r.requirement_state='active'
    order by r.sort_order,r.stable_key,r.id
  loop
    v_child:=ledger.booking_offering_requirement_candidates_v1(v_group.offering_id,v_requirement.id,p_starts_at,p_ends_at);
    v_requirements:=v_requirements||jsonb_build_array(v_child);
    v_total:=v_total+1;
    if coalesce((v_child->>'potentiallySatisfiable')::boolean,false) then v_potential_count:=v_potential_count+1; end if;
    if coalesce((v_child->>'fullyTimeVerified')::boolean,false) then v_verified_count:=v_verified_count+1; end if;
  end loop;

  for v_subgroup in
    select g.id from ledger.booking_offering_requirement_groups g
    where g.parent_group_id=v_group.id and g.group_state='active'
    order by g.sort_order,g.stable_key,g.id
  loop
    v_child:=ledger.booking_offering_group_evaluation_v1(v_subgroup.id,p_starts_at,p_ends_at);
    v_groups:=v_groups||jsonb_build_array(v_child);
    v_total:=v_total+1;
    if coalesce((v_child->>'potentiallySatisfiable')::boolean,false) then v_potential_count:=v_potential_count+1; end if;
    if coalesce((v_child->>'fullyTimeVerified')::boolean,false) then v_verified_count:=v_verified_count+1; end if;
  end loop;

  v_needed:=case v_group.satisfaction_mode
    when 'all' then v_total
    when 'any' then case when v_total>0 then 1 else 0 end
    else v_group.minimum_satisfied
  end;
  v_potential:=v_potential_count>=v_needed;
  v_verified:=v_verified_count>=v_needed;

  return jsonb_build_object(
    'contractVersion','ledger_booking_offering_group_evaluation_v1',
    'groupId',v_group.id,'stableKey',v_group.stable_key,'label',v_group.label,
    'satisfactionMode',v_group.satisfaction_mode,'minimumSatisfied',v_group.minimum_satisfied,
    'childCount',v_total,'requiredSatisfiedCount',v_needed,
    'potentiallySatisfiedCount',v_potential_count,'fullyTimeVerifiedCount',v_verified_count,
    'potentiallySatisfiable',v_potential,'fullyTimeVerified',v_verified,
    'requirements',v_requirements,'groups',v_groups
  );
end;
$$;

create or replace function ledger.evaluate_booking_offering_v1(
  p_offering_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_offering ledger.booking_offerings%rowtype;
  v_root_id uuid;
  v_eval jsonb;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Offering evaluation requires startsAt < endsAt.' using errcode='22023';
  end if;
  select * into v_offering from ledger.booking_offerings o where o.id=p_offering_id;
  if v_offering.id is null then raise exception 'Booking offering not found.' using errcode='P0002'; end if;
  if v_offering.offering_state='retired' then
    raise exception 'Retired booking offering cannot be evaluated for new scheduling.' using errcode='23514';
  end if;
  select g.id into v_root_id from ledger.booking_offering_requirement_groups g
  where g.offering_id=p_offering_id and g.parent_group_id is null and g.group_state='active';
  if v_root_id is null then
    return jsonb_build_object(
      'contractVersion','ledger_booking_offering_evaluation_v1','offeringId',p_offering_id,
      'ledgerId',v_offering.ledger_id,'definitionComplete',false,'potentiallySatisfiable',false,
      'fullyTimeVerified',false,'reason','active_root_requirement_group_missing'
    );
  end if;
  v_eval:=ledger.booking_offering_group_evaluation_v1(v_root_id,p_starts_at,p_ends_at);
  return jsonb_build_object(
    'contractVersion','ledger_booking_offering_evaluation_v1','offeringId',p_offering_id,
    'ledgerId',v_offering.ledger_id,'stableKey',v_offering.stable_key,'name',v_offering.name,
    'bookingKind',v_offering.booking_kind,'occurrenceType',v_offering.occurrence_type,
    'defaultDurationMinutes',v_offering.default_duration_minutes,'offeringState',v_offering.offering_state,
    'requestedStartsAt',p_starts_at,'requestedEndsAt',p_ends_at,
    'requestedDurationMinutes',extract(epoch from (p_ends_at-p_starts_at))/60,
    'definitionComplete',true,'potentiallySatisfiable',coalesce((v_eval->>'potentiallySatisfiable')::boolean,false),
    'fullyTimeVerified',coalesce((v_eval->>'fullyTimeVerified')::boolean,false),
    'requirementGraph',v_eval,
    'truthBoundary',jsonb_build_object(
      'requirementIsNotAssignment',true,'routingIsNotAuthority',true,
      'seatEligibilityIsNotPersonFreeBusy',true,'resourceAvailabilityIsEvaluatedAtRequestedInterval',true
    )
  );
end;
$$;

update reality.responsibility_relations
set permitted_operations=(
      select array_agg(distinct op order by op)
      from unnest(permitted_operations || array['offering.read','offering.manage']::text[]) op
    ),
    updated_at=now()
where responsibility_key='institutional_schedule_operations'
  and relation_state='active'
  and jurisdiction_kind='entity'
  and scope ? 'ledgerIds';

create or replace function atlas.ledger_booking_offerings_self_api_v1(
  p_ledger_id uuid,
  p_offering_state text default null
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'offering.read');
  return ledger.booking_offerings_service_v1(p_ledger_id,p_offering_state);
end;
$$;

create or replace function atlas.ledger_booking_offering_self_api_v1(
  p_ledger_id uuid,
  p_offering_id uuid
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'offering.read');
  if not exists(select 1 from ledger.booking_offerings o where o.id=p_offering_id and o.ledger_id=p_ledger_id) then
    raise exception 'Booking offering is outside this Ledger.' using errcode='42501';
  end if;
  v_result:=ledger.booking_offering_detail_v1(p_offering_id);
  return v_result;
end;
$$;

create or replace function atlas.evaluate_ledger_booking_offering_self_api_v1(
  p_ledger_id uuid,
  p_offering_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'offering.read');
  if not exists(select 1 from ledger.booking_offerings o where o.id=p_offering_id and o.ledger_id=p_ledger_id) then
    raise exception 'Booking offering is outside this Ledger.' using errcode='42501';
  end if;
  return ledger.evaluate_booking_offering_v1(p_offering_id,p_starts_at,p_ends_at);
end;
$$;

create or replace function atlas.upsert_ledger_booking_offering_self_api_v1(
  p_ledger_id uuid,
  p_stable_key text,
  p_name text,
  p_booking_kind text,
  p_occurrence_type text,
  p_default_duration_minutes integer,
  p_description text default null,
  p_offering_state text default 'draft',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_seat uuid; v_person uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'offering.manage');
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.upsert_booking_offering_service_v1(
    p_ledger_id,p_stable_key,p_name,p_booking_kind,p_occurrence_type,p_default_duration_minutes,
    p_description,p_offering_state,v_seat,p_metadata,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    )
  );
end;
$$;

create or replace function atlas.replace_ledger_booking_offering_requirement_graph_self_api_v1(
  p_ledger_id uuid,
  p_offering_id uuid,
  p_groups jsonb,
  p_requirements jsonb,
  p_routing_policies jsonb default '[]'::jsonb,
  p_routing_candidates jsonb default '[]'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'offering.manage');
  if not exists(select 1 from ledger.booking_offerings o where o.id=p_offering_id and o.ledger_id=p_ledger_id) then
    raise exception 'Booking offering is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  return ledger.replace_booking_offering_requirement_graph_service_v1(
    p_offering_id,p_groups,p_requirements,p_routing_policies,p_routing_candidates,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    )
  );
end;
$$;

revoke execute on function ledger.guard_booking_offering_v1() from public,anon,authenticated;
revoke execute on function ledger.guard_booking_offering_routing_candidate_v1() from public,anon,authenticated;
revoke execute on function ledger.booking_offering_detail_v1(uuid) from public,anon,authenticated;
revoke execute on function ledger.booking_offerings_service_v1(uuid,text) from public,anon,authenticated;
revoke execute on function ledger.upsert_booking_offering_service_v1(uuid,text,text,text,text,integer,text,text,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke execute on function ledger.replace_booking_offering_requirement_graph_service_v1(uuid,jsonb,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated;
revoke execute on function ledger.booking_offering_requirement_candidates_v1(uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke execute on function ledger.booking_offering_group_evaluation_v1(uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke execute on function ledger.evaluate_booking_offering_v1(uuid,timestamptz,timestamptz) from public,anon,authenticated;

revoke execute on function atlas.ledger_booking_offerings_self_api_v1(uuid,text) from public,anon;
revoke execute on function atlas.ledger_booking_offering_self_api_v1(uuid,uuid) from public,anon;
revoke execute on function atlas.evaluate_ledger_booking_offering_self_api_v1(uuid,uuid,timestamptz,timestamptz) from public,anon;
revoke execute on function atlas.upsert_ledger_booking_offering_self_api_v1(uuid,text,text,text,text,integer,text,text,jsonb,jsonb) from public,anon;
revoke execute on function atlas.replace_ledger_booking_offering_requirement_graph_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,jsonb,jsonb) from public,anon;
grant execute on function atlas.ledger_booking_offerings_self_api_v1(uuid,text) to authenticated;
grant execute on function atlas.ledger_booking_offering_self_api_v1(uuid,uuid) to authenticated;
grant execute on function atlas.evaluate_ledger_booking_offering_self_api_v1(uuid,uuid,timestamptz,timestamptz) to authenticated;
grant execute on function atlas.upsert_ledger_booking_offering_self_api_v1(uuid,text,text,text,text,integer,text,text,jsonb,jsonb) to authenticated;
grant execute on function atlas.replace_ledger_booking_offering_requirement_graph_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,jsonb,jsonb) to authenticated;
