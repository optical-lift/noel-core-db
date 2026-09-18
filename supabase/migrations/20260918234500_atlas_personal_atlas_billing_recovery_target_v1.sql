begin;

create or replace function atlas.personal_atlas_billing_recovery_target_service_v1(
  p_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_email text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
begin
  if p_auth_user_id is null then
    raise exception 'Authenticated user id required.' using errcode='22023';
  end if;

  -- Prefer an explicitly claimed Personal Atlas purchase. This remains the
  -- strongest billing-custody link after Principal bootstrap.
  select *
    into v_purchase
  from atlas.personal_atlas_purchases p
  where p.provider='stripe'
    and p.offer_key='personal_atlas'
    and p.claimed_by_user_id=p_auth_user_id
    and coalesce(trim(p.provider_subscription_id),'') <> ''
  order by p.purchased_at desc,p.id desc
  limit 1;

  -- A verified human may have bought Personal Atlas after first entering Atlas
  -- through an organization setup sponsor. Such a purchase can still be
  -- unclaimed because the Principal already existed; verified auth email is the
  -- fallback ownership seam in that case.
  if v_purchase.id is null then
    select lower(email)
      into v_email
    from auth.users
    where id=p_auth_user_id;

    if v_email is not null then
      select *
        into v_purchase
      from atlas.personal_atlas_purchases p
      where p.provider='stripe'
        and p.offer_key='personal_atlas'
        and p.claimed_by_user_id is null
        and p.purchaser_email=v_email
        and coalesce(trim(p.provider_subscription_id),'') <> ''
      order by p.purchased_at desc,p.id desc
      limit 1;
    end if;
  end if;

  if v_purchase.id is null then
    return jsonb_build_object(
      'ok',false,
      'reason','no_personal_atlas_billing_subscription'
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'purchaseId',v_purchase.id,
    'provider','stripe',
    'providerSubscriptionId',v_purchase.provider_subscription_id,
    'purchaseState',v_purchase.purchase_state
  );
end;
$function$;

revoke all on function atlas.personal_atlas_billing_recovery_target_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.personal_atlas_billing_recovery_target_service_v1(uuid)
  to service_role;

comment on function atlas.personal_atlas_billing_recovery_target_service_v1(uuid) is
  'Service-only lookup of the verified auth user Personal Atlas Stripe subscription for billing recovery. Browser callers do not supply provider identity.';

commit;
