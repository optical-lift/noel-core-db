begin;

-- Atlas Implementation Initial Scope Capability Signal v1
--
-- Additive read membrane only.
--
-- Extends the live discovery response with dynamic capability flags. The
-- Workbench may therefore deploy before admission authority exists: discovery
-- remains visible, while mutation actions stay disabled until the exact public
-- admission membranes both exist and are executable by authenticated callers.
--
-- An assigned practitioner may discover institutional scopes only through the
-- verified setup sponsor's canonical Person -> Principal -> root-governing Ledger
-- authority. There is no global Organization search and no mutation.

create or replace function atlas.implementation_initial_scope_options_self_api_v1(
  p_implementation_case_id uuid,
  p_query text default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_query text := lower(btrim(coalesce(p_query,'')));
  v_limit integer := least(greatest(coalesce(p_limit,25),1),50);
  v_setup_sponsor_user_id uuid;
  v_setup_sponsor_participant_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_entitlements jsonb := '[]'::jsonb;
  v_bindings jsonb := '[]'::jsonb;
  v_existing_admission_proc regprocedure;
  v_new_admission_proc regprocedure;
  v_existing_admission_command_available boolean := false;
  v_new_admission_command_available boolean := false;
  v_has_available_existing_scope boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    p_implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.implementation_cases c
    where c.id=p_implementation_case_id
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Open Implementation Case not found.'
      using errcode='23503';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'bindingId',b.id,
      'ledgerEntitlementId',b.ledger_entitlement_id,
      'bindingState',b.state,
      'organizationId',o.id,
      'organizationLabel',o.name,
      'ledgerId',l.id,
      'ledgerLabel',l.name
    ) order by b.bound_at,b.id
  ),'[]'::jsonb)
  into v_bindings
  from atlas.ledger_entitlement_bindings b
  join atlas.organizations o
    on o.id=b.organization_id
   and o.status='active'
  join atlas.ledgers l
    on l.id=b.ledger_id
   and l.status='active'
  where b.implementation_case_id=p_implementation_case_id
    and b.organization_unit_id is null
    and b.ended_at is null
    and b.state in ('bound','activated');

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'ledgerEntitlementId',le.id,
      'number',le.entitlement_number,
      'state',le.state,
      'priceClass',le.price_class
    ) order by le.entitlement_number
  ),'[]'::jsonb)
  into v_entitlements
  from atlas.ledger_entitlements le
  where le.implementation_case_id=p_implementation_case_id
    and le.price_class='baseline_first'
    and le.state in ('available','reserved');

  v_existing_admission_proc := to_regprocedure(
    'public.admit_existing_implementation_scope_self_api_v1(uuid,uuid,uuid,uuid,jsonb)'
  );
  v_new_admission_proc := to_regprocedure(
    'public.establish_new_implementation_scope_self_api_v1(uuid,uuid,text,jsonb)'
  );

  v_existing_admission_command_available :=
    v_existing_admission_proc is not null
    and has_function_privilege('authenticated',v_existing_admission_proc,'EXECUTE');

  v_new_admission_command_available :=
    v_new_admission_proc is not null
    and has_function_privilege('authenticated',v_new_admission_proc,'EXECUTE');

  if jsonb_array_length(v_bindings)>0 then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_initial_scope_options_v1',
      'state','bound',
      'bindings',v_bindings,
      'availableEntitlements',v_entitlements,
      'items','[]'::jsonb,
      'existingAdmissionCommandAvailable',false,
      'newAdmissionCommandAvailable',false,
      'canAdmitExistingScope',false,
      'canEstablishNewOrganization',false
    );
  end if;

  select cp.id,cp.human_user_id
  into v_setup_sponsor_participant_id,v_setup_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='setup_sponsor'
    and cp.active
    and cp.ended_at is null
    and cp.verified_at is not null
  order by cp.started_at,cp.id
  limit 1;

  if v_setup_sponsor_participant_id is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_initial_scope_options_v1',
      'state','setup_sponsor_required',
      'bindings','[]'::jsonb,
      'availableEntitlements',v_entitlements,
      'items','[]'::jsonb,
      'canEstablishNewOrganization',false
    );
  end if;

  select pac.person_id
  into v_sponsor_person_id
  from atlas.person_auth_credentials pac
  join atlas.people p
    on p.id=pac.person_id
   and p.status='active'
  where pac.auth_user_id=v_setup_sponsor_user_id
    and pac.status='active'
  order by pac.bound_at,pac.id
  limit 1;

  select p.id
  into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id=v_sponsor_person_id
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_sponsor_person_id is null or v_sponsor_principal_id is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_initial_scope_options_v1',
      'state','setup_sponsor_principal_required',
      'bindings','[]'::jsonb,
      'availableEntitlements',v_entitlements,
      'items','[]'::jsonb,
      'canEstablishNewOrganization',false
    );
  end if;

  select coalesce(jsonb_agg(item order by organization_label,ledger_label),'[]'::jsonb)
  into v_items
  from (
    select *
    from (
      select distinct on (o.id,l.id)
        o.name as organization_label,
        l.name as ledger_label,
        jsonb_build_object(
          'organizationId',o.id,
          'organizationLabel',o.name,
          'ledgerId',l.id,
          'ledgerLabel',l.name,
          'ledgerStableKey',l.stable_key,
          'authorityKind',a.authority_kind,
          'participationKind',lop.participation_kind,
          'availableForAdmission',case when live_binding.id is null then true else false end
        ) as item
      from atlas.principal_ledger_authorities a
      join atlas.ledgers l
        on l.id=a.ledger_id
       and l.status='active'
      join atlas.ledger_organization_participations lop
        on lop.ledger_id=l.id
       and lop.status='active'
       and lop.ended_at is null
       and lop.participation_kind='governing'
       and lop.is_compatibility_primary
      join atlas.organizations o
        on o.id=lop.organization_id
       and o.status='active'
      left join lateral (
        select b.id
        from atlas.ledger_entitlement_bindings b
        where b.ledger_id=l.id
          and b.organization_unit_id is null
          and b.ended_at is null
          and b.state in ('bound','activated')
        order by b.bound_at,b.id
        limit 1
      ) live_binding on true
      where a.principal_id=v_sponsor_principal_id
        and a.authority_kind='root_governing'
        and a.status='active'
        and a.ended_at is null
        and (
          v_query=''
          or strpos(lower(o.name),v_query)>0
          or strpos(lower(l.name),v_query)>0
        )
      order by o.id,l.id,o.name,l.name
    ) deduped
    order by organization_label,ledger_label
    limit v_limit
  ) matches;

  select exists(
    select 1
    from jsonb_array_elements(v_items) as option
    where coalesce((option->>'availableForAdmission')::boolean,false)
  )
  into v_has_available_existing_scope;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_initial_scope_options_v2',
    'state','ready',
    'bindings','[]'::jsonb,
    'availableEntitlements',v_entitlements,
    'items',v_items,
    'existingAdmissionCommandAvailable',v_existing_admission_command_available,
    'newAdmissionCommandAvailable',v_new_admission_command_available,
    'canAdmitExistingScope',
      v_existing_admission_command_available
      and v_has_available_existing_scope
      and jsonb_array_length(v_entitlements)>0,
    'canEstablishNewOrganization',
      v_new_admission_command_available
      and jsonb_array_length(v_entitlements)>0,
    'authorityBasis','verified_setup_sponsor_principal'
  );
end;
$function$;

revoke all on function atlas.implementation_initial_scope_options_self_api_v1(
  uuid,text,integer
) from public,anon,authenticated,service_role;

create or replace function public.implementation_initial_scope_options_self_api_v1(
  p_implementation_case_id uuid,
  p_query text default null,
  p_limit integer default 25
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.implementation_initial_scope_options_self_api_v1(
    p_implementation_case_id,p_query,p_limit
  );
$function$;

revoke all on function public.implementation_initial_scope_options_self_api_v1(
  uuid,text,integer
) from public,anon,service_role;

grant execute on function public.implementation_initial_scope_options_self_api_v1(
  uuid,text,integer
) to authenticated;

comment on function public.implementation_initial_scope_options_self_api_v1(
  uuid,text,integer
) is
  'Read-only Implementation initial-scope discovery. Existing Organizations are visible only through the verified setup sponsor Principal root-governing Ledger authority; there is no global Organization search.';

commit;
