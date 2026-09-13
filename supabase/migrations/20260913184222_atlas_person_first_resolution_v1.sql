-- Atlas Person-First Resolution v1.
-- Moves foundational durable-human Principal / Organization Membership resolution
-- from direct auth-user identity to canonical Person while preserving credential
-- and commercial/audit evidence semantics.

BEGIN;

create or replace function atlas.current_principal_id_v1()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select p.id
  from atlas.principals p
  where p.person_id = atlas.current_person_id_v1()
    and p.status = 'active'
  limit 1;
$function$;

create or replace function atlas.current_organization_membership_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select om.id
  from atlas.organization_memberships om
  where om.organization_id = p_organization_id
    and om.person_id = atlas.current_person_id_v1()
    and om.active
  order by case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end,
           om.created_at
  limit 1;
$function$;

create or replace function atlas.is_organization_member(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select exists (
    select 1
    from atlas.organization_memberships om
    where om.organization_id = p_organization_id
      and om.person_id = atlas.current_person_id_v1()
      and om.active = true
  );
$function$;

create or replace function atlas.is_organization_owner(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select exists (
    select 1
    from atlas.organization_memberships om
    where om.organization_id = p_organization_id
      and om.person_id = atlas.current_person_id_v1()
      and om.active = true
      and om.role = 'owner'
  );
$function$;

create or replace function atlas.atlas_home_identity_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  with current_principal as (
    select p.id, p.name
    from atlas.principals p
    where p.id = atlas.current_principal_id_v1()
      and p.status = 'active'
    limit 1
  )
  select jsonb_build_object(
    'ok', true,
    'authenticated', auth.uid() is not null,
    'hasPrincipal', exists(select 1 from current_principal),
    'principalName', (select cp.name from current_principal cp limit 1)
  );
$function$;

create or replace function atlas.organization_access_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_person_id uuid;
  v_items jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok',true,'authenticated',false,'items','[]'::jsonb);
  end if;

  v_person_id := atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'ok',true,
      'authenticated',true,
      'contractVersion','organization_access_self_v1',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'organizationId',o.id,
        'organizationName',o.name,
        'organizationMembershipId',m.id,
        'identitySubjectId',m.identity_subject_id,
        'employeeSeatId',s.id,
        'accessClass',s.seat_class,
        'seatStatus',s.status,
        'billingState',s.billing_state,
        'membershipRole',m.role
      ) order by o.name,o.id
    ),
    '[]'::jsonb
  )
  into v_items
  from atlas.organization_member_credentials c
  join atlas.organization_memberships m
    on m.id = c.organization_membership_id
   and m.organization_id = c.organization_id
  join atlas.organization_employee_seats s
    on s.id = c.employee_seat_id
   and s.organization_membership_id = m.id
   and s.organization_id = m.organization_id
  join atlas.organizations o
    on o.id = m.organization_id
  where c.credential_kind = 'auth_user'
    and c.auth_user_id = v_uid
    and c.status = 'active'
    and (c.expires_at is null or c.expires_at > now())
    and m.person_id = v_person_id
    and m.active
    and s.status = 'active'
    and o.status = 'active';

  return jsonb_build_object(
    'ok',true,
    'authenticated',true,
    'contractVersion','organization_access_self_v1',
    'items',v_items
  );
end;
$function$;

create or replace function atlas.personal_atlas_access_status_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_latest atlas.personal_atlas_purchases%rowtype;
  v_principal_id uuid;
  v_implementation_case_id uuid;
  v_implementation_purchase_id uuid;
  v_grant atlas.personal_atlas_access_grants%rowtype;
  v_eligible boolean;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select lower(email) into v_email
  from auth.users
  where id = v_user_id;

  -- Durable Principal identity resolves through canonical Person.
  v_principal_id := atlas.current_principal_id_v1();

  -- Purchase/claim evidence remains credential-bound in this tranche.
  select * into v_purchase
  from atlas.personal_atlas_purchases
  where purchase_state='active'
    and (
      claimed_by_user_id=v_user_id
      or (claimed_by_user_id is null and purchaser_email=v_email)
    )
  order by purchased_at desc,id desc
  limit 1;

  select * into v_latest
  from atlas.personal_atlas_purchases
  where claimed_by_user_id=v_user_id
     or (claimed_by_user_id is null and purchaser_email=v_email)
  order by purchased_at desc,id desc
  limit 1;

  if v_purchase.id is null then
    select c.id,p.id
      into v_implementation_case_id,v_implementation_purchase_id
    from atlas.implementation_case_participants sponsor
    join atlas.implementation_cases c
      on c.id=sponsor.implementation_case_id
    join atlas.implementation_purchases p
      on p.id=c.implementation_purchase_id
    where sponsor.human_user_id=v_user_id
      and sponsor.relationship_kind='setup_sponsor'
      and sponsor.active
      and c.state not in ('closed','cancelled')
      and p.purchase_state='active'
    order by p.purchased_at desc,c.id desc
    limit 1;
  end if;

  if v_principal_id is not null then
    select * into v_grant
    from atlas.personal_atlas_access_grants g
    where g.principal_id=v_principal_id
      and g.state='active'
    order by g.granted_at desc,g.id desc
    limit 1;
  end if;

  v_eligible := v_purchase.id is not null
    or v_implementation_case_id is not null
    or v_grant.id is not null;

  return jsonb_build_object(
    'ok',true,
    'hasPrincipal',v_principal_id is not null,
    'eligible',v_eligible,
    'accessState',case when v_eligible then 'active' else 'locked' end,
    'accessBasis',case
      when v_purchase.id is not null then 'personal_atlas_purchase'
      when v_implementation_case_id is not null then 'organization_implementation_setup_sponsor'
      when v_grant.id is not null then 'personal_atlas_access_grant'
      else null
    end,
    'purchaseId',coalesce(v_purchase.id,v_latest.id),
    'purchaseState',v_latest.purchase_state,
    'claimed',coalesce(v_purchase.claimed_by_user_id,v_latest.claimed_by_user_id) is not null,
    'implementationCaseId',v_implementation_case_id,
    'implementationPurchaseId',v_implementation_purchase_id,
    'grantId',v_grant.id,
    'grantKind',v_grant.grant_kind
  );
end;
$function$;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal_id uuid;
  v_principal atlas.principals%rowtype;
  v_household jsonb;
  v_portfolio jsonb;
  v_candidates jsonb;
  v_day date;
  v_clock jsonb;
  v_office jsonb;
  v_readiness jsonb;
  v_capability_holds jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();

  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_self_context_v2',
      'state','principal_required'
    );
  end if;

  select * into v_principal
  from atlas.principals p
  where p.id = v_principal_id
    and p.status='active'
  limit 1;

  if v_principal.id is null then
    return jsonb_build_object(
      'contractVersion','principal_self_context_v2',
      'state','principal_required'
    );
  end if;

  v_day := (now() at time zone coalesce(nullif(v_principal.home_timezone,''),'America/Chicago'))::date;

  select to_jsonb(h) into v_household
  from atlas.households h
  where h.id=v_principal.active_household_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',u.id,
        'stableKey',u.stable_key,
        'name',u.name,
        'unitKind',u.unit_kind,
        'linkedFarmId',u.linked_farm_id,
        'lifecycleState',u.lifecycle_state,
        'portfolioRole',u.portfolio_role,
        'horizon',u.horizon,
        'archivedAt',u.archived_at
      ) order by case u.horizon when 'H1' then 1 when 'H2' then 2 else 3 end,u.name
    ),
    '[]'::jsonb
  )
  into v_portfolio
  from atlas.portfolio_units u
  where u.owner_id=v_principal.id
    and u.archived_at is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'domain',c.domain,
        'sourceType',c.source_type,
        'sourceId',c.source_id,
        'title',c.title,
        'floorClass',c.floor_class,
        'windowStart',c.window_start,
        'windowEnd',c.window_end,
        'fixedStart',c.fixed_start,
        'mustBeginBy',c.must_begin_by,
        'mustFinishBy',c.must_finish_by,
        'expectedMinutes',c.expected_minutes,
        'protectionLevel',c.protection_level,
        'ownerRequired',c.owner_required,
        'consequence',c.consequence,
        'reasonForFloor',c.reason_for_floor,
        'portfolioUnitId',c.portfolio_unit_id,
        'horizon',c.horizon
      ) order by c.floor_class,c.window_end nulls last,c.title
    ),
    '[]'::jsonb
  )
  into v_candidates
  from atlas.principal_clock_candidates_v1 c
  where c.principal_id=v_principal.id;

  v_clock:=atlas.principal_clock_api_v1(v_day,now());
  v_office:=atlas.principal_office_context_api_v1();
  v_readiness:=atlas.principal_reality_readiness_v3(v_principal.id,v_day);
  v_capability_holds:=atlas.principal_capability_holds_v1(v_principal.id);

  return jsonb_build_object(
    'contractVersion','principal_self_context_v2',
    'state','ready',
    'principal',jsonb_build_object(
      'id',v_principal.id,
      'stableKey',v_principal.stable_key,
      'name',v_principal.name,
      'organizationId',v_principal.organization_id,
      'homeTimezone',v_principal.home_timezone,
      'activeHouseholdId',v_principal.active_household_id
    ),
    'household',v_household,
    'portfolioUnits',v_portfolio,
    'clockCandidatesMode','raw_inventory_not_arbitration',
    'clockCandidates',v_candidates,
    'principalClock',v_clock,
    'principalOffice',v_office,
    'capacityToday',atlas.principal_capacity_day_state_v1(v_principal.id,v_day),
    'capabilityHolds',v_capability_holds,
    'realityReadiness',v_readiness
  );
end;
$function$;

COMMIT;
