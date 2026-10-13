BEGIN;

-- Atlas Personal complimentary testing invitation source candidate v1.
-- No Stripe customer, SetupIntent, subscription, purchase, or invoice is created.
-- The signed-in human owns only their verified-email invitation claim.
-- Operator issuance is a separate service-role authorization; this candidate seeds no codes or users.
-- Exact DB Source: live-deployed begin_personal_atlas_self_api_v1 and
-- personal_atlas_access_status_self_api_v1, extended narrowly, not replaced by a new Principal writer.

create table if not exists atlas.personal_atlas_complimentary_test_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email=lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  code_digest text not null unique check (code_digest ~ '^[0-9a-f]{64}$'),
  state text not null default 'issued' check (state in ('issued','revoked')),
  expires_at timestamptz not null,
  claimed_by_user_id uuid unique references auth.users(id),
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint claimed_both_or_neither check ((claimed_by_user_id is null)=(claimed_at is null))
);
create index if not exists personal_atlas_complimentary_test_invites_email_idx
  on atlas.personal_atlas_complimentary_test_invitations(email,state);
alter table atlas.personal_atlas_complimentary_test_invitations enable row level security;
revoke all on atlas.personal_atlas_complimentary_test_invitations from public,anon,authenticated;
-- No blanket RLS policy. Service administration only; a user receives no direct table access.

create or replace function public.redeem_personal_atlas_complimentary_test_self_api_v1(p_code text)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','atlas','auth','extensions'
as $redeem$
declare
  v_user_id uuid;
  v_email text;
  v_code text;
  v_invite atlas.personal_atlas_complimentary_test_invitations%rowtype;
  v_principal_id uuid;
  v_grant_id uuid;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select lower(btrim(u.email)) into v_email from auth.users u
  where u.id=v_user_id and u.email_confirmed_at is not null;
  if v_email is null then raise exception 'Verified email required.' using errcode='42501'; end if;
  v_code:=btrim(coalesce(p_code,''));
  -- Codes are long unpredictable secrets; not guessable human words or published demo codes.
  if length(v_code)<20 or length(v_code)>128 then
    raise exception 'Invalid or unavailable testing invitation.' using errcode='22023';
  end if;
  select * into v_invite from atlas.personal_atlas_complimentary_test_invitations i
  where i.email=v_email
    and i.code_digest=encode(extensions.digest(v_code,'sha256'),'hex')
    and i.state='issued'
    and i.expires_at>now()
  for update;
  if v_invite.id is null or
     (v_invite.claimed_by_user_id is not null and v_invite.claimed_by_user_id<>v_user_id) then
    raise exception 'Invalid or unavailable testing invitation.' using errcode='22023';
  end if;
  if v_invite.claimed_by_user_id is null then
    update atlas.personal_atlas_complimentary_test_invitations i
    set claimed_by_user_id=v_user_id,claimed_at=now()
    where i.id=v_invite.id;
  end if;
  -- Existing Principal: same canonical access-grant writer, never forge a Stripe purchase.
  select p.id into v_principal_id from atlas.principals p
  where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal_id is not null then
    v_grant_id:=public.grant_personal_atlas_access_v1(
      v_principal_id,'complimentary_testing',
      jsonb_build_object('authority','verified_email_invitation','invitationId',v_invite.id));
  end if;
  return jsonb_build_object(
    'ok',true,'redeemed',true,'hasPrincipal',v_principal_id is not null,
    'accessKind','complimentary_testing','createsStripeObligation',false);
end;
$redeem$;
revoke all on function public.redeem_personal_atlas_complimentary_test_self_api_v1(text) from public,anon,authenticated;
grant execute on function public.redeem_personal_atlas_complimentary_test_self_api_v1(text) to authenticated;
-- Service may administer invitation rows only through a separately authorized operating procedure.
-- Code digests, names, and personal email addresses are never embedded in migration source.


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
  v_complimentary_invite_id uuid;
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
    select i.id into v_complimentary_invite_id
    from atlas.personal_atlas_complimentary_test_invitations i
    where i.claimed_by_user_id=v_user_id
      and i.email=v_email
      and i.state='issued'
      and i.claimed_at is not null
    limit 1;
    if v_complimentary_invite_id is not null then
      v_access_source := 'complimentary_testing';
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

  if v_complimentary_invite_id is not null then
    perform public.grant_personal_atlas_access_v1(
      v_principal.id,'complimentary_testing',
      jsonb_build_object('authority','verified_email_invitation',
                         'invitationId',v_complimentary_invite_id)
    );
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


CREATE OR REPLACE FUNCTION atlas.personal_atlas_access_status_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
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
  v_complimentary_invite_id uuid;
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

  -- The unestablished Principal is eligible only after an explicitly
  -- redeemed and verified-email-bound testing invitation.
  if v_principal_id is null then
    select i.id into v_complimentary_invite_id
    from atlas.personal_atlas_complimentary_test_invitations i
    where i.claimed_by_user_id=v_user_id
      and i.email=v_email
      and i.state='issued'
      and i.claimed_at is not null
    limit 1;
  end if;

  v_eligible := v_purchase.id is not null
    or v_implementation_case_id is not null
    or v_grant.id is not null
    or v_complimentary_invite_id is not null;

  return jsonb_build_object(
    'ok',true,
    'hasPrincipal',v_principal_id is not null,
    'eligible',v_eligible,
    'accessState',case when v_eligible then 'active' else 'locked' end,
    'accessBasis',case
      when v_purchase.id is not null then 'personal_atlas_purchase'
      when v_implementation_case_id is not null then 'organization_implementation_setup_sponsor'
      when v_grant.id is not null then 'personal_atlas_access_grant'
      when v_complimentary_invite_id is not null then 'complimentary_testing_invitation'
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


-- Reassert original routine grants: replacement must not enlarge caller authority.
revoke all on function atlas.begin_personal_atlas_self_api_v1(text,text) from public,anon;
revoke all on function atlas.personal_atlas_access_status_self_api_v1() from public,anon;
-- No extra public bootstrap or access-status function is introduced.

COMMIT;
