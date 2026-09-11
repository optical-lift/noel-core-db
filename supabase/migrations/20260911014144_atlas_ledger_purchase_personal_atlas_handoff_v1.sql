create or replace function atlas.personal_atlas_access_status_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_latest atlas.personal_atlas_purchases%rowtype;
  v_principal_id uuid;
  v_implementation_case_id uuid;
  v_implementation_purchase_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select lower(email) into v_email from auth.users where id=v_user_id;
  select id into v_principal_id from atlas.principals where user_id=v_user_id and status='active' limit 1;

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
    join atlas.implementation_cases c on c.id=sponsor.implementation_case_id
    join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
    where sponsor.human_user_id=v_user_id
      and sponsor.relationship_kind='setup_sponsor'
      and sponsor.active
      and c.state not in ('closed','cancelled')
      and p.purchase_state='active'
    order by p.purchased_at desc,c.id desc
    limit 1;
  end if;

  return jsonb_build_object(
    'ok',true,
    'hasPrincipal',v_principal_id is not null,
    'eligible',v_purchase.id is not null or v_implementation_case_id is not null,
    'accessState',case when v_purchase.id is not null or v_implementation_case_id is not null then 'active' else 'locked' end,
    'accessBasis',case
      when v_purchase.id is not null then 'personal_atlas_purchase'
      when v_implementation_case_id is not null then 'organization_implementation_setup_sponsor'
      else null
    end,
    'purchaseId',coalesce(v_purchase.id,v_latest.id),
    'purchaseState',v_latest.purchase_state,
    'claimed',coalesce(v_purchase.claimed_by_user_id,v_latest.claimed_by_user_id) is not null,
    'implementationCaseId',v_implementation_case_id,
    'implementationPurchaseId',v_implementation_purchase_id
  );
end;
$function$;

create or replace function public.personal_atlas_access_status_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.personal_atlas_access_status_self_api_v1();
$function$;

revoke all on function public.personal_atlas_access_status_self_api_v1() from public,anon;
grant execute on function public.personal_atlas_access_status_self_api_v1() to authenticated,service_role;

create or replace function atlas.begin_personal_atlas_self_api_v1(p_name text, p_timezone text default 'America/Chicago'::text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_name text;
  v_timezone text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_implementation_case_id uuid;
  v_implementation_purchase_id uuid;
  v_access_source text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_name:=nullif(trim(p_name),'');
  v_timezone:=coalesce(nullif(trim(p_timezone),''),'America/Chicago');
  if v_name is null then raise exception 'Name required.' using errcode='22023'; end if;
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then raise exception 'Unknown timezone.' using errcode='22023'; end if;

  select lower(email) into v_email from auth.users where id=v_user_id;
  select * into v_principal from atlas.principals where user_id=v_user_id limit 1;
  if v_principal.id is not null then
    return jsonb_build_object('ok',true,'alreadyEstablished',true,'principalId',v_principal.id,'householdId',v_principal.active_household_id);
  end if;

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where purchaser_email=v_email
    and purchase_state='active'
    and (claimed_by_user_id is null or claimed_by_user_id=v_user_id)
  order by purchased_at desc,id desc
  limit 1
  for update;

  if v_purchase.id is not null then
    v_access_source := 'personal_atlas_purchase';
  else
    select c.id,p.id
      into v_implementation_case_id,v_implementation_purchase_id
    from atlas.implementation_case_participants sponsor
    join atlas.implementation_cases c on c.id=sponsor.implementation_case_id
    join atlas.implementation_purchases p on p.id=c.implementation_purchase_id
    where sponsor.human_user_id=v_user_id
      and sponsor.relationship_kind='setup_sponsor'
      and sponsor.active
      and c.state not in ('closed','cancelled')
      and p.purchase_state='active'
    order by p.purchased_at desc,c.id desc
    limit 1;

    if v_implementation_case_id is null then
      raise exception 'Active Atlas access required.' using errcode='42501';
    end if;
    v_access_source := 'organization_implementation_setup_sponsor';
  end if;

  insert into atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
  values(
    v_user_id,
    'person:'||v_user_id::text,
    v_name,
    v_timezone,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id,
      'implementationPurchaseId',v_implementation_purchase_id
    ))
  )
  returning * into v_principal;

  insert into atlas.households(principal_id,stable_key,name,timezone,status,metadata)
  values(
    v_principal.id,
    'home',
    'Home',
    v_timezone,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id
    ))
  )
  returning * into v_household;

  update atlas.principals
  set active_household_id=v_household.id,updated_at=now()
  where id=v_principal.id
  returning * into v_principal;

  insert into atlas.household_members(household_id,user_id,display_name,relationship,household_role,active,metadata)
  values(
    v_household.id,
    v_user_id,
    v_name,
    'self',
    'principal',
    true,
    jsonb_strip_nulls(jsonb_build_object(
      'source',v_access_source,
      'purchaseId',v_purchase.id,
      'implementationCaseId',v_implementation_case_id
    ))
  );

  if v_purchase.id is not null then
    update atlas.personal_atlas_purchases
    set claimed_by_user_id=v_user_id,
        claimed_principal_id=v_principal.id,
        claimed_at=coalesce(claimed_at,now()),
        updated_at=now()
    where id=v_purchase.id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'alreadyEstablished',false,
    'principalId',v_principal.id,
    'householdId',v_household.id,
    'purchaseId',v_purchase.id,
    'implementationCaseId',v_implementation_case_id,
    'accessBasis',v_access_source
  ));
end;
$function$;

comment on function atlas.personal_atlas_access_status_self_api_v1() is 'Authoritative self-access projection for the Personal Atlas shell. Active personal purchase or active verified organization implementation setup-sponsor relationship may admit the human. Ledger/implementation views remain reachable only through an established Personal Atlas.';
comment on function atlas.begin_personal_atlas_self_api_v1(text,text) is 'Establishes Personal Atlas identity from either an active paid Personal Atlas purchase or an active verified organization implementation setup-sponsor access basis. Organization implementation access does not itself create Organization, membership, Ledger binding, or a recurring Personal Atlas billing entitlement.';
