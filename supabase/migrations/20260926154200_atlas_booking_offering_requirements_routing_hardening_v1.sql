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
  v_existing ledger.booking_offerings%rowtype;
  v_active_root uuid;
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

  select * into v_existing
  from ledger.booking_offerings o
  where o.ledger_id=p_ledger_id and o.stable_key=btrim(p_stable_key)
  for update;

  if v_existing.id is not null and v_existing.offering_state='retired' then
    raise exception 'Retired booking offering cannot be changed.' using errcode='23514';
  end if;

  if v_existing.id is not null and v_existing.offering_state='active' and (
       btrim(p_booking_kind)<>v_existing.booking_kind
       or btrim(p_occurrence_type)<>v_existing.occurrence_type
       or p_default_duration_minutes<>v_existing.default_duration_minutes
  ) then
    raise exception 'Deactivate a booking offering before changing its structural definition.' using errcode='23514';
  end if;

  if v_existing.id is null then
    if p_offering_state='active' then
      raise exception 'Create the offering as draft, establish its requirement graph, then activate it.' using errcode='23514';
    end if;
    insert into ledger.booking_offerings(
      ledger_id,stable_key,name,description,booking_kind,occurrence_type,default_duration_minutes,
      offering_state,created_by_seat_id,metadata,provenance
    ) values(
      p_ledger_id,btrim(p_stable_key),btrim(p_name),nullif(btrim(p_description),''),btrim(p_booking_kind),
      btrim(p_occurrence_type),p_default_duration_minutes,p_offering_state,p_created_by_seat_id,p_metadata,p_provenance
    ) returning id into v_offering_id;
  else
    v_offering_id:=v_existing.id;
    if p_offering_state='active' and v_existing.offering_state<>'active' then
      select g.id into v_active_root
      from ledger.booking_offering_requirement_groups g
      where g.offering_id=v_existing.id and g.parent_group_id is null and g.group_state='active';
      if v_active_root is null or not exists(
        select 1 from ledger.booking_offering_requirements r
        where r.offering_id=v_existing.id and r.requirement_state='active'
      ) then
        raise exception 'Booking offering requires an active root group and at least one active requirement before activation.' using errcode='23514';
      end if;
    end if;
    update ledger.booking_offerings
    set name=btrim(p_name),
        description=nullif(btrim(p_description),''),
        booking_kind=btrim(p_booking_kind),
        occurrence_type=btrim(p_occurrence_type),
        default_duration_minutes=p_default_duration_minutes,
        offering_state=p_offering_state,
        metadata=p_metadata,
        provenance=p_provenance
    where id=v_existing.id;
  end if;

  return ledger.booking_offering_detail_v1(v_offering_id);
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
  v_routing_mode text;
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
  v_routing_mode:=coalesce(v_routing_mode,'manual');
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

  if v_routing_mode='first_eligible' and v_candidate_count>0 then
    if v_requirement.requirement_kind='resource' then
      select value into v_recommended
      from jsonb_array_elements(v_candidates)
      where coalesce((value->>'available')::boolean,false)
      order by coalesce(value->>'stableKey',''),value->>'resourceId'
      limit 1;
    else
      select value into v_recommended
      from jsonb_array_elements(v_candidates)
      order by coalesce(value->>'displayName',''),value->>'seatId'
      limit 1;
    end if;
  elsif v_routing_mode='ordered_priority' and v_candidate_count>0 then
    if v_requirement.requirement_kind='resource' then
      select value into v_recommended
      from jsonb_array_elements(v_candidates)
      where coalesce((value->>'available')::boolean,false)
      order by (value->>'priority')::integer,coalesce(value->>'stableKey',''),value->>'resourceId'
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

  if v_total=0 then
    v_needed:=1;
    v_potential:=false;
    v_verified:=false;
  else
    v_needed:=case v_group.satisfaction_mode
      when 'all' then v_total
      when 'any' then 1
      else v_group.minimum_satisfied
    end;
    v_potential:=v_potential_count>=v_needed;
    v_verified:=v_verified_count>=v_needed;
  end if;

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

revoke execute on function ledger.upsert_booking_offering_service_v1(uuid,text,text,text,text,integer,text,text,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke execute on function ledger.booking_offering_requirement_candidates_v1(uuid,uuid,timestamptz,timestamptz) from public,anon,authenticated;
revoke execute on function ledger.booking_offering_group_evaluation_v1(uuid,timestamptz,timestamptz) from public,anon,authenticated;
