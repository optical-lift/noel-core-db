create or replace function atlas.organization_unit_connected_source_context_self_v1(
  p_organization_unit_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_unit atlas.organization_units%rowtype;
  v_org atlas.organizations%rowtype;
  v_membership_role text;
  v_setup_actor boolean := false;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select unit.*
  into v_unit
  from atlas.organization_units unit
  where unit.id = p_organization_unit_id
    and unit.status = 'active';

  if not found then
    return null;
  end if;

  select organization.*
  into v_org
  from atlas.organizations organization
  where organization.id = v_unit.organization_id
    and organization.status = 'active';

  if not found then
    return null;
  end if;

  select membership.role
  into v_membership_role
  from atlas.organization_memberships membership
  where membership.organization_id = v_org.id
    and membership.user_id = v_uid
    and membership.active
  order by case when membership.role = 'owner' then 0 else 1 end, membership.created_at
  limit 1;

  select exists (
    select 1
    from atlas.organization_onboarding_actors actor
    where actor.organization_id = v_org.id
      and actor.human_user_id = v_uid
      and actor.actor_kind = 'setup_actor'
      and actor.active
  ) into v_setup_actor;

  if coalesce(v_membership_role, '') <> 'owner' and not v_setup_actor then
    return null;
  end if;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', v_org.id,
      'stable_key', v_org.stable_key,
      'name', v_org.name,
      'status', v_org.status,
      'onboarding_state', v_org.onboarding_state
    ),
    'organization_unit', jsonb_build_object(
      'id', v_unit.id,
      'stable_key', v_unit.stable_key,
      'name', v_unit.name,
      'unit_kind', v_unit.unit_kind,
      'status', v_unit.status
    ),
    'relationship', jsonb_build_object(
      'setup_actor', v_setup_actor,
      'membership_role', v_membership_role
    )
  );
end;
$$;

revoke all on function atlas.organization_unit_connected_source_context_self_v1(uuid) from public;
grant execute on function atlas.organization_unit_connected_source_context_self_v1(uuid) to authenticated;

create or replace function public.organization_unit_connected_source_context_self_api_v1(
  p_organization_unit_id uuid
)
returns jsonb
language sql
stable
set search_path = pg_catalog, atlas, public
as $$
  select atlas.organization_unit_connected_source_context_self_v1(p_organization_unit_id);
$$;

revoke all on function public.organization_unit_connected_source_context_self_api_v1(uuid) from public;
grant execute on function public.organization_unit_connected_source_context_self_api_v1(uuid) to authenticated;