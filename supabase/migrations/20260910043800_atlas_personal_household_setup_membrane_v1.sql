-- Personal Atlas household setup membrane.
-- A paid Personal Atlas may establish its Principal from a real supplied name,
-- then manage ordinary household members without depending on the retired Welcome flow.

create unique index if not exists household_members_personal_atlas_request_key_uidx
  on atlas.household_members(household_id, (metadata->>'personalAtlasRequestKey'))
  where metadata->>'source' = 'personal_atlas_household'
    and metadata ? 'personalAtlasRequestKey';

create or replace function atlas.personal_household_members_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_household_id uuid;
  v_household atlas.households%rowtype;
  v_members jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    return jsonb_build_object('ok',true,'hasPrincipal',false,'household',null,'members','[]'::jsonb);
  end if;

  select * into v_household from atlas.households where id=v_household_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,
    'displayName',m.display_name,
    'relationship',m.relationship,
    'self',(m.user_id=v_user_id or m.household_role='principal'),
    'active',m.active
  ) order by case when (m.user_id=v_user_id or m.household_role='principal') then 0 else 1 end,m.created_at,m.id),'[]'::jsonb)
    into v_members
    from atlas.household_members m
    where m.household_id=v_household_id and m.active=true;

  return jsonb_build_object(
    'ok',true,
    'hasPrincipal',true,
    'household',jsonb_build_object('id',v_household.id,'name',v_household.name,'timezone',v_household.timezone),
    'members',v_members
  );
end;
$function$;

create or replace function atlas.personal_household_upsert_member_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_household_id uuid;
  v_member_id uuid;
  v_request_key text;
  v_name text;
  v_relationship text;
  v_active boolean := true;
  v_member atlas.household_members%rowtype;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  v_name := nullif(trim(p_input->>'displayName'),'');
  v_relationship := nullif(trim(p_input->>'relationship'),'');
  v_request_key := nullif(trim(p_input->>'requestKey'),'');
  if nullif(trim(p_input->>'memberId'),'') is not null then
    v_member_id := (p_input->>'memberId')::uuid;
  end if;
  if p_input ? 'active' then
    v_active := (p_input->>'active')::boolean;
  end if;

  if v_name is null then
    raise exception 'Name required.' using errcode='22023';
  end if;

  if v_member_id is not null then
    select * into v_member
      from atlas.household_members
      where id=v_member_id and household_id=v_household_id
      for update;

    if v_member.id is null then
      raise exception 'Household member not found.' using errcode='22023';
    end if;
    if v_member.user_id is not null or v_member.household_role='principal' then
      raise exception 'The Principal household member is not editable here.' using errcode='42501';
    end if;

    update atlas.household_members
      set display_name=v_name,
          relationship=case when p_input ? 'relationship' then v_relationship else relationship end,
          active=v_active,
          metadata=metadata || jsonb_build_object('source','personal_atlas_household'),
          updated_at=now()
      where id=v_member.id
      returning * into v_member;
  else
    if v_request_key is null then
      raise exception 'requestKey required for a new household member.' using errcode='22023';
    end if;

    select * into v_member
      from atlas.household_members
      where household_id=v_household_id
        and metadata->>'source'='personal_atlas_household'
        and metadata->>'personalAtlasRequestKey'=v_request_key
      limit 1
      for update;

    if v_member.id is null then
      insert into atlas.household_members(
        household_id,user_id,display_name,relationship,household_role,active,metadata
      ) values(
        v_household_id,null,v_name,v_relationship,'member',v_active,
        jsonb_build_object(
          'source','personal_atlas_household',
          'personalAtlasRequestKey',v_request_key
        )
      )
      returning * into v_member;
    else
      update atlas.household_members
        set display_name=v_name,
            relationship=case when p_input ? 'relationship' then v_relationship else relationship end,
            active=v_active,
            updated_at=now()
        where id=v_member.id
        returning * into v_member;
    end if;
  end if;

  return jsonb_build_object('ok',true,'member',jsonb_build_object(
    'id',v_member.id,
    'displayName',v_member.display_name,
    'relationship',v_member.relationship,
    'self',false,
    'active',v_member.active
  ));
end;
$function$;

revoke all on function atlas.personal_household_members_self_api_v1() from public,anon;
revoke all on function atlas.personal_household_upsert_member_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.personal_household_members_self_api_v1() to authenticated,service_role;
grant execute on function atlas.personal_household_upsert_member_self_api_v1(jsonb) to authenticated,service_role;

create or replace function public.personal_household_members_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.personal_household_members_self_api_v1();
$function$;

create or replace function public.personal_household_upsert_member_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.personal_household_upsert_member_self_api_v1(p_input);
$function$;

revoke all on function public.personal_household_members_self_api_v1() from public,anon;
revoke all on function public.personal_household_upsert_member_self_api_v1(jsonb) from public,anon;
grant execute on function public.personal_household_members_self_api_v1() to authenticated,service_role;
grant execute on function public.personal_household_upsert_member_self_api_v1(jsonb) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  (
    'atlas.personal_household_members_self_api_v1()',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Read the current Principal household for the Personal Atlas household surface.'),now()
  ),
  (
    'atlas.personal_household_upsert_member_self_api_v1(p_input jsonb)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Add or edit ordinary non-account household members without retired Welcome-flow identity semantics.'),now()
  )
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
