-- Establish a canonical paid-purchase seam for Personal Atlas and an idempotent self bootstrap.
-- Payment evidence is recorded by Stripe service custody; a signed-in human may claim only a purchase matching their auth email.

create table if not exists atlas.personal_atlas_purchases (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'stripe',
  provider_checkout_session_id text not null unique,
  provider_subscription_id text,
  purchaser_email text not null,
  offer_key text not null default 'personal_atlas',
  purchase_state text not null default 'active' check (purchase_state in ('active','inactive','cancelled','past_due')),
  purchased_at timestamptz not null default now(),
  claimed_by_user_id uuid references auth.users(id) on delete set null,
  claimed_principal_id uuid references atlas.principals(id) on delete set null,
  claimed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists personal_atlas_purchases_subscription_uidx
  on atlas.personal_atlas_purchases(provider,provider_subscription_id)
  where provider_subscription_id is not null;

alter table atlas.personal_atlas_purchases enable row level security;

create or replace function atlas.record_stripe_personal_atlas_purchase_v1(
  p_checkout_session_id text,
  p_subscription_id text,
  p_purchaser_email text,
  p_purchased_at timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(trim(p_checkout_session_id),'') !~ '^cs_' then raise exception 'Valid Stripe Checkout session required.' using errcode='22023'; end if;
  if coalesce(trim(p_subscription_id),'') = '' then raise exception 'Stripe subscription id required.' using errcode='22023'; end if;
  if position('@' in coalesce(trim(p_purchaser_email),'')) <= 1 then raise exception 'Purchaser email required.' using errcode='22023'; end if;

  insert into atlas.personal_atlas_purchases(
    provider,provider_checkout_session_id,provider_subscription_id,purchaser_email,offer_key,purchase_state,purchased_at,metadata
  ) values (
    'stripe',trim(p_checkout_session_id),trim(p_subscription_id),lower(trim(p_purchaser_email)),'personal_atlas','active',coalesce(p_purchased_at,now()),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (provider_checkout_session_id) do update set
    provider_subscription_id=excluded.provider_subscription_id,
    purchaser_email=excluded.purchaser_email,
    purchase_state='active',
    purchased_at=excluded.purchased_at,
    metadata=atlas.personal_atlas_purchases.metadata || excluded.metadata,
    updated_at=now()
  returning * into v_purchase;

  return jsonb_build_object('ok',true,'purchaseId',v_purchase.id,'checkoutSessionId',v_purchase.provider_checkout_session_id,'purchaseState',v_purchase.purchase_state);
end;
$function$;

revoke all on function atlas.record_stripe_personal_atlas_purchase_v1(text,text,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_stripe_personal_atlas_purchase_v1(text,text,text,timestamptz,jsonb) to service_role;

create or replace function atlas.personal_atlas_purchase_status_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare v_user_id uuid; v_email text; v_purchase atlas.personal_atlas_purchases%rowtype; v_principal_id uuid;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select lower(email) into v_email from auth.users where id=v_user_id;
  select id into v_principal_id from atlas.principals where user_id=v_user_id and status='active' limit 1;
  select * into v_purchase
    from atlas.personal_atlas_purchases
    where purchaser_email=v_email and purchase_state='active' and (claimed_by_user_id is null or claimed_by_user_id=v_user_id)
    order by purchased_at desc,id desc limit 1;
  return jsonb_build_object(
    'ok',true,
    'hasPrincipal',v_principal_id is not null,
    'eligible',v_purchase.id is not null or v_principal_id is not null,
    'purchaseId',v_purchase.id,
    'claimed',v_purchase.claimed_by_user_id is not null
  );
end;
$function$;

create or replace function atlas.begin_personal_atlas_self_api_v1(p_name text,p_timezone text default 'America/Chicago')
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid; v_email text; v_name text; v_timezone text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
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
    where purchaser_email=v_email and purchase_state='active' and (claimed_by_user_id is null or claimed_by_user_id=v_user_id)
    order by purchased_at desc,id desc limit 1
    for update;
  if v_purchase.id is null then raise exception 'Paid Personal Atlas purchase required.' using errcode='42501'; end if;

  insert into atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
  values(v_user_id,'person:'||v_user_id::text,v_name,v_timezone,'active',jsonb_build_object('source','personal_atlas_purchase','purchaseId',v_purchase.id))
  returning * into v_principal;

  insert into atlas.households(principal_id,stable_key,name,timezone,status,metadata)
  values(v_principal.id,'home','Home',v_timezone,'active',jsonb_build_object('source','personal_atlas_purchase'))
  returning * into v_household;

  update atlas.principals set active_household_id=v_household.id,updated_at=now() where id=v_principal.id returning * into v_principal;

  insert into atlas.household_members(household_id,user_id,display_name,relationship,household_role,active,metadata)
  values(v_household.id,v_user_id,v_name,'self','principal',true,jsonb_build_object('source','personal_atlas_purchase'));

  update atlas.personal_atlas_purchases set
    claimed_by_user_id=v_user_id,
    claimed_principal_id=v_principal.id,
    claimed_at=coalesce(claimed_at,now()),
    updated_at=now()
  where id=v_purchase.id;

  return jsonb_build_object('ok',true,'alreadyEstablished',false,'principalId',v_principal.id,'householdId',v_household.id,'purchaseId',v_purchase.id);
end;
$function$;

revoke all on function atlas.personal_atlas_purchase_status_self_api_v1() from public,anon;
revoke all on function atlas.begin_personal_atlas_self_api_v1(text,text) from public,anon;
grant execute on function atlas.personal_atlas_purchase_status_self_api_v1() to authenticated,service_role;
grant execute on function atlas.begin_personal_atlas_self_api_v1(text,text) to authenticated,service_role;

create or replace function public.personal_atlas_purchase_status_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_atlas_purchase_status_self_api_v1(); $function$;

create or replace function public.begin_personal_atlas_self_api_v1(p_name text,p_timezone text default 'America/Chicago')
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.begin_personal_atlas_self_api_v1(p_name,p_timezone); $function$;

revoke all on function public.personal_atlas_purchase_status_self_api_v1() from public,anon;
revoke all on function public.begin_personal_atlas_self_api_v1(text,text) from public,anon;
grant execute on function public.personal_atlas_purchase_status_self_api_v1() to authenticated,service_role;
grant execute on function public.begin_personal_atlas_self_api_v1(text,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.personal_atlas_purchase_status_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Report whether the signed-in human has paid Personal Atlas eligibility.'),now()),
  ('atlas.begin_personal_atlas_self_api_v1(p_name text, p_timezone text)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Idempotently establish a Personal Atlas principal and household only from matching paid purchase evidence.'),now())
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence || excluded.evidence,
  reviewed_at=now();
