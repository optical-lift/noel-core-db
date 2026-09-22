begin;

create table if not exists atlas.personal_atlas_purchase_claim_tickets (
  id uuid primary key default gen_random_uuid(),
  personal_atlas_purchase_id uuid not null
    references atlas.personal_atlas_purchases(id) on delete restrict,
  token_sha256 text not null unique
    check (token_sha256 ~ '^[0-9a-f]{64}$'),
  state text not null default 'issued'
    check (state in ('issued','consumed','expired','revoked')),
  expires_at timestamptz not null,
  issued_at timestamptz not null default now(),
  consumed_at timestamptz,
  consumed_by_user_id uuid references auth.users(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (state='consumed' and consumed_at is not null and consumed_by_user_id is not null)
    or
    (state<>'consumed' and consumed_at is null and consumed_by_user_id is null)
  )
);

create index if not exists personal_atlas_purchase_claim_tickets_purchase_idx
  on atlas.personal_atlas_purchase_claim_tickets(personal_atlas_purchase_id,issued_at desc);

alter table atlas.personal_atlas_purchase_claim_tickets enable row level security;
revoke all on table atlas.personal_atlas_purchase_claim_tickets
  from public,anon,authenticated,service_role;

create or replace function atlas.issue_personal_atlas_purchase_claim_ticket_service_v1(
  p_checkout_session_id text,
  p_ttl_seconds integer default 1800,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $function$
declare
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_ticket_id uuid;
  v_token text;
  v_hash text;
  v_expires_at timestamptz;
begin
  if coalesce(btrim(p_checkout_session_id),'') !~ '^cs_' then
    raise exception 'Valid Stripe Checkout session required.' using errcode='22023';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds < 300 or p_ttl_seconds > 7200 then
    raise exception 'Claim ticket lifetime must be between 5 minutes and 2 hours.'
      using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Claim ticket metadata must be a JSON object.' using errcode='22023';
  end if;

  select *
  into v_purchase
  from atlas.personal_atlas_purchases p
  where p.provider='stripe'
    and p.provider_checkout_session_id=btrim(p_checkout_session_id)
    and p.purchase_state='active'
  for update;

  if v_purchase.id is null then
    raise exception 'Active Personal Atlas purchase not found.' using errcode='P0002';
  end if;
  if v_purchase.claimed_by_user_id is not null then
    raise exception 'Personal Atlas purchase is already claimed.' using errcode='23514';
  end if;

  update atlas.personal_atlas_purchase_claim_tickets
  set state='revoked',
      updated_at=now()
  where personal_atlas_purchase_id=v_purchase.id
    and state='issued';

  v_token:='pat_'||encode(extensions.gen_random_bytes(32),'hex');
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  v_expires_at:=now()+make_interval(secs=>p_ttl_seconds);

  insert into atlas.personal_atlas_purchase_claim_tickets(
    personal_atlas_purchase_id,token_sha256,state,expires_at,metadata
  ) values (
    v_purchase.id,v_hash,'issued',v_expires_at,
    p_metadata||jsonb_build_object(
      'source','issue_personal_atlas_purchase_claim_ticket_service_v1',
      'checkoutSessionId',v_purchase.provider_checkout_session_id
    )
  )
  returning id into v_ticket_id;

  return jsonb_build_object(
    'ok',true,
    'ticketId',v_ticket_id,
    'purchaseId',v_purchase.id,
    'claimToken',v_token,
    'expiresAt',v_expires_at,
    'purchaserEmailIsAtlasIdentity',false
  );
end;
$function$;

revoke all on function atlas.issue_personal_atlas_purchase_claim_ticket_service_v1(text,integer,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.issue_personal_atlas_purchase_claim_ticket_service_v1(text,integer,jsonb)
  to service_role;

create or replace function atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(
  p_claim_token text,
  p_auth_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $function$
declare
  v_hash text;
  v_ticket atlas.personal_atlas_purchase_claim_tickets%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if coalesce(btrim(p_claim_token),'') !~ '^pat_[0-9a-f]{64}$' then
    raise exception 'Valid Personal Atlas claim token required.' using errcode='22023';
  end if;
  if p_auth_user_id is null
     or not exists(select 1 from auth.users u where u.id=p_auth_user_id) then
    raise exception 'Verified Atlas user required.' using errcode='42501';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Claim metadata must be a JSON object.' using errcode='22023';
  end if;

  v_hash:=encode(extensions.digest(btrim(p_claim_token),'sha256'),'hex');

  select *
  into v_ticket
  from atlas.personal_atlas_purchase_claim_tickets t
  where t.token_sha256=v_hash
  for update;

  if v_ticket.id is null then
    raise exception 'Personal Atlas claim ticket not found.' using errcode='P0002';
  end if;

  if v_ticket.state='consumed' then
    if v_ticket.consumed_by_user_id=p_auth_user_id then
      return jsonb_build_object(
        'ok',true,'changed',false,'alreadyClaimed',true,
        'ticketId',v_ticket.id,'purchaseId',v_ticket.personal_atlas_purchase_id,
        'claimedByUserId',p_auth_user_id
      );
    end if;
    raise exception 'Personal Atlas claim ticket has already been consumed.'
      using errcode='42501';
  end if;

  if v_ticket.state<>'issued' then
    raise exception 'Personal Atlas claim ticket is not active.' using errcode='42501';
  end if;

  if v_ticket.expires_at<=now() then
    update atlas.personal_atlas_purchase_claim_tickets
    set state='expired',updated_at=now()
    where id=v_ticket.id;
    return jsonb_build_object(
      'ok',false,'changed',false,'code','claim_ticket_expired',
      'ticketId',v_ticket.id,'purchaseId',v_ticket.personal_atlas_purchase_id
    );
  end if;

  select *
  into v_purchase
  from atlas.personal_atlas_purchases p
  where p.id=v_ticket.personal_atlas_purchase_id
  for update;

  if v_purchase.id is null or v_purchase.purchase_state<>'active' then
    raise exception 'Active Personal Atlas purchase required.' using errcode='23514';
  end if;

  if v_purchase.claimed_by_user_id is not null
     and v_purchase.claimed_by_user_id<>p_auth_user_id then
    raise exception 'Personal Atlas purchase is already claimed by another Atlas user.'
      using errcode='42501';
  end if;

  update atlas.personal_atlas_purchases
  set claimed_by_user_id=p_auth_user_id,
      claimed_at=coalesce(claimed_at,now()),
      metadata=metadata||jsonb_build_object(
        'claimSource','personal_atlas_purchase_claim_ticket_v1',
        'claimTicketId',v_ticket.id
      ),
      updated_at=now()
  where id=v_purchase.id;

  update atlas.personal_atlas_purchase_claim_tickets
  set state='consumed',
      consumed_at=now(),
      consumed_by_user_id=p_auth_user_id,
      metadata=metadata||p_metadata||jsonb_build_object(
        'consumeSource','consume_personal_atlas_purchase_claim_ticket_service_v1'
      ),
      updated_at=now()
  where id=v_ticket.id;

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'alreadyClaimed',false,
    'ticketId',v_ticket.id,
    'purchaseId',v_purchase.id,
    'claimedByUserId',p_auth_user_id,
    'purchaserEmailIsAtlasIdentity',false
  );
end;
$function$;

revoke all on function atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(text,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.consume_personal_atlas_purchase_claim_ticket_service_v1(text,uuid,jsonb)
  to service_role;

CREATE OR REPLACE FUNCTION atlas.begin_personal_atlas_self_api_v1(p_name text, p_timezone text DEFAULT 'America/Chicago'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
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
  where purchase_state='active'
    and (
      claimed_by_user_id=v_user_id
      or (claimed_by_user_id is null and purchaser_email=v_email)
    )
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

commit;
