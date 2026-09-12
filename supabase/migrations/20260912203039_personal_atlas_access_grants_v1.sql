begin;

create table if not exists atlas.personal_atlas_access_grants (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  grant_kind text not null,
  state text not null default 'active' check (state in ('active','revoked')),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint personal_atlas_access_grants_revocation_consistency check (
    (state='active' and revoked_at is null)
    or (state='revoked' and revoked_at is not null)
  )
);

create unique index if not exists personal_atlas_access_grants_one_active_per_principal
  on atlas.personal_atlas_access_grants(principal_id)
  where state='active';

revoke all on atlas.personal_atlas_access_grants from public, anon, authenticated;
grant select, insert, update on atlas.personal_atlas_access_grants to service_role;

create or replace function public.grant_personal_atlas_access_v1(
  p_principal_id uuid,
  p_grant_kind text,
  p_basis jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_grant_id uuid;
begin
  if p_principal_id is null then
    raise exception 'principal id required' using errcode='22023';
  end if;
  if nullif(btrim(p_grant_kind),'') is null then
    raise exception 'grant kind required' using errcode='22023';
  end if;
  if not exists (
    select 1 from atlas.principals p where p.id=p_principal_id and p.status='active'
  ) then
    raise exception 'active principal not found' using errcode='P0002';
  end if;

  select g.id into v_grant_id
  from atlas.personal_atlas_access_grants g
  where g.principal_id=p_principal_id and g.state='active'
  order by g.granted_at desc,g.id desc
  limit 1;

  if v_grant_id is not null then
    return v_grant_id;
  end if;

  insert into atlas.personal_atlas_access_grants(principal_id,grant_kind,basis)
  values (p_principal_id,btrim(p_grant_kind),coalesce(p_basis,'{}'::jsonb))
  returning id into v_grant_id;

  return v_grant_id;
end;
$function$;

revoke all on function public.grant_personal_atlas_access_v1(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.grant_personal_atlas_access_v1(uuid,text,jsonb) to service_role;

create or replace function public.revoke_personal_atlas_access_v1(
  p_principal_id uuid,
  p_basis jsonb default '{}'::jsonb
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_count integer;
begin
  update atlas.personal_atlas_access_grants g
  set state='revoked',
      revoked_at=now(),
      updated_at=now(),
      metadata=coalesce(g.metadata,'{}'::jsonb) || jsonb_build_object('revocation_basis',coalesce(p_basis,'{}'::jsonb))
  where g.principal_id=p_principal_id and g.state='active';
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke all on function public.revoke_personal_atlas_access_v1(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.revoke_personal_atlas_access_v1(uuid,jsonb) to service_role;

create or replace function atlas.personal_atlas_access_status_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
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

  if v_principal_id is not null then
    select * into v_grant
    from atlas.personal_atlas_access_grants g
    where g.principal_id=v_principal_id and g.state='active'
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

revoke all on function atlas.personal_atlas_access_status_self_api_v1() from public, anon, authenticated;

create or replace function public.atlas_home_identity_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.atlas_home_identity_self_api_v1();
$function$;

revoke all on function public.atlas_home_identity_self_api_v1() from public, anon;
grant execute on function public.atlas_home_identity_self_api_v1() to authenticated, service_role;

commit;
