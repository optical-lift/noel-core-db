-- Personal Atlas access is all-or-nothing: an inactive, past-due, or cancelled
-- Personal Atlas subscription does not retain notebook access merely because a
-- Principal was already established.

create or replace function atlas.personal_atlas_purchase_status_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_latest atlas.personal_atlas_purchases%rowtype;
  v_principal_id uuid;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

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

  return jsonb_build_object(
    'ok',true,
    'hasPrincipal',v_principal_id is not null,
    'eligible',v_purchase.id is not null,
    'accessState',case when v_purchase.id is not null then 'active' else 'locked' end,
    'purchaseId',coalesce(v_purchase.id,v_latest.id),
    'purchaseState',v_latest.purchase_state,
    'claimed',coalesce(v_purchase.claimed_by_user_id,v_latest.claimed_by_user_id) is not null
  );
end;
$function$;

-- Reassert authenticated-only browser access after replacing the function.
revoke all on function atlas.personal_atlas_purchase_status_self_api_v1() from public,anon;
grant execute on function atlas.personal_atlas_purchase_status_self_api_v1() to authenticated,service_role;

create or replace function public.personal_atlas_purchase_status_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.personal_atlas_purchase_status_self_api_v1();
$function$;

revoke all on function public.personal_atlas_purchase_status_self_api_v1() from public,anon;
grant execute on function public.personal_atlas_purchase_status_self_api_v1() to authenticated,service_role;
