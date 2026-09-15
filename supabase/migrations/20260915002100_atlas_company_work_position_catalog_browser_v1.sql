begin;

create or replace function atlas.organization_company_work_positions_api_v1(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_organization_id is null then raise exception 'Organization required.' using errcode='22023'; end if;
  if not atlas.is_organization_owner(p_organization_id)
     and not exists(
       select 1 from atlas.farms f
       join atlas.farm_memberships fm on fm.farm_id=f.id
       where f.organization_id=p_organization_id
         and fm.user_id=v_uid
         and fm.active
         and fm.role in ('owner','manager')
     ) then
    raise exception 'Organization management authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'positionId',p.id,
    'positionKey',p.stable_key,
    'positionTitle',p.display_title,
    'positionKind',p.position_kind,
    'organizationUnitId',p.organization_unit_id,
    'organizationUnitName',u.name,
    'responsibilities',coalesce((
      select jsonb_agg(jsonb_build_object(
        'responsibilityId',r.id,
        'responsibilityKey',r.stable_key,
        'responsibilityName',r.name,
        'responsibilityKind',r.responsibility_kind,
        'relationshipKind',pr.relationship_kind,
        'scopes',coalesce((
          select jsonb_agg(jsonb_build_object(
            'scopeKind',rs.scope_kind,
            'scopeId',rs.scope_id,
            'relationKind',rs.relation_kind
          ) order by rs.scope_kind,rs.scope_id,rs.id)
          from atlas.organization_responsibility_scopes rs
          where rs.organization_id=p.organization_id
            and rs.responsibility_id=r.id
        ),'[]'::jsonb)
      ) order by r.stable_key,r.id)
      from atlas.organization_position_responsibilities pr
      join atlas.organization_responsibilities r
        on r.id=pr.responsibility_id
       and r.organization_id=p.organization_id
       and r.status='active'
      where pr.position_id=p.id
    ),'[]'::jsonb)
  ) order by u.name,p.display_title,p.id),'[]'::jsonb)
  into v_items
  from atlas.organization_positions p
  join atlas.organization_units u
    on u.id=p.organization_unit_id
   and u.organization_id=p.organization_id
   and u.status='active'
  where p.organization_id=p_organization_id
    and p.status='active';

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_company_work_positions_v1',
    'organizationId',p_organization_id,
    'items',v_items
  );
end;
$function$;

comment on function atlas.organization_company_work_positions_api_v1(uuid) is
  'Management read of existing governed Position definitions and their Responsibility scopes. This is definition truth only; reading the catalog appoints nobody and allocates no Company Work.';

revoke all on function atlas.organization_company_work_positions_api_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.organization_company_work_positions_api_v1(uuid) to postgres,service_role;

create or replace function public.organization_company_work_positions_api_v1(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_company_work_positions_api_v1(p_organization_id);
$function$;

revoke all on function public.organization_company_work_positions_api_v1(uuid) from public,anon,authenticated;
grant execute on function public.organization_company_work_positions_api_v1(uuid) to authenticated,service_role;

commit;
