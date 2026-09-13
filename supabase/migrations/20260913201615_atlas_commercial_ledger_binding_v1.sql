-- Atlas Commercial Ledger Binding v1.
-- Commerce may bind capability to institutional reality; it may not manufacture institutional reality.

BEGIN;

create or replace function atlas.bind_implementation_ledger_entitlement_self_api_v1(
  p_implementation_case_id uuid,
  p_institution_item_id uuid,
  p_ledger_scope_item_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_id uuid,
  p_ledger_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_practitioner_participant_id uuid;
  v_setup_sponsor_participant_id uuid;
  v_setup_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_organization atlas.organizations%rowtype;
  v_ledger atlas.ledgers%rowtype;
  v_starting_label text;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select cp.id
  into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id = p_implementation_case_id
    and cp.relationship_kind = 'practitioner'
    and cp.active
    and cp.human_user_id = v_uid
  limit 1;

  if v_practitioner_participant_id is null then
    raise exception 'This implementation case is not assigned to the current practitioner.' using errcode='42501';
  end if;

  select cp.id, cp.human_user_id
  into v_setup_sponsor_participant_id, v_setup_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id = p_implementation_case_id
    and cp.relationship_kind = 'setup_sponsor'
    and cp.active
    and cp.verified_at is not null
  limit 1;

  if v_setup_sponsor_participant_id is null then
    raise exception 'A verified setup sponsor is required before commercial Ledger binding.' using errcode='23514';
  end if;

  select c.person_id
  into v_sponsor_person_id
  from atlas.person_auth_credentials c
  join atlas.people p on p.id = c.person_id
  where c.auth_user_id = v_setup_sponsor_user_id
    and c.status = 'active'
    and p.status = 'active'
  limit 1;

  if v_sponsor_person_id is null then
    raise exception 'Verified setup sponsor must resolve to a Canonical Person.' using errcode='23514';
  end if;

  select p.id
  into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id = v_sponsor_person_id
    and p.status = 'active'
  order by p.created_at
  limit 1;

  if v_sponsor_principal_id is null then
    raise exception 'Verified setup sponsor must have an active Principal.' using errcode='23514';
  end if;

  select o.*
  into v_organization
  from atlas.organizations o
  where o.id = p_organization_id
    and o.status = 'active';

  if v_organization.id is null then
    raise exception 'Active target Organization required.' using errcode='23503';
  end if;

  select l.*
  into v_ledger
  from atlas.ledgers l
  where l.id = p_ledger_id
    and l.organization_id = p_organization_id
    and l.ledger_kind = 'organization_governing'
    and l.status = 'active';

  if v_ledger.id is null then
    raise exception 'Target Ledger must be the active governing Ledger of the target Organization.' using errcode='23514';
  end if;

  if not atlas.principal_has_ledger_authority_v1(v_sponsor_principal_id, p_ledger_id) then
    raise exception 'Verified setup sponsor Principal does not govern the target Ledger.' using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.implementation_establishment_items e
    where e.id = p_institution_item_id
      and e.implementation_case_id = p_implementation_case_id
      and e.category = 'institution'
      and e.status = 'established'
  ) then
    raise exception 'An established Institution record is required.' using errcode='23514';
  end if;

  if not exists (
    select 1
    from atlas.implementation_establishment_items e
    where e.id = p_ledger_scope_item_id
      and e.implementation_case_id = p_implementation_case_id
      and e.category = 'ledger_scope'
      and e.status = 'established'
  ) then
    raise exception 'An established Ledger scope record is required.' using errcode='23514';
  end if;

  select le.*
  into v_entitlement
  from atlas.ledger_entitlements le
  where le.id = p_ledger_entitlement_id
    and le.implementation_case_id = p_implementation_case_id
  for update;

  if v_entitlement.id is null then
    raise exception 'Ledger entitlement not found for this implementation case.' using errcode='23503';
  end if;

  select b.*
  into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.ledger_entitlement_id = v_entitlement.id
    and b.ended_at is null
  limit 1;

  if v_binding.id is not null then
    if v_binding.organization_id = p_organization_id
       and v_binding.ledger_id = p_ledger_id then
      return jsonb_build_object(
        'ok',true,
        'alreadyBound',true,
        'implementationCaseId',p_implementation_case_id,
        'organizationId',p_organization_id,
        'organizationName',v_organization.name,
        'ledgerId',p_ledger_id,
        'ledgerStableKey',v_ledger.stable_key,
        'ledgerEntitlementId',v_entitlement.id,
        'bindingId',v_binding.id,
        'bindingState',v_binding.state,
        'setupSponsorParticipantId',v_setup_sponsor_participant_id,
        'setupSponsorPrincipalId',v_sponsor_principal_id,
        'organizationCreated',false,
        'principalCreated',false,
        'membershipCreated',false
      );
    end if;

    raise exception 'Ledger entitlement is already bound to a different institutional scope.' using errcode='23505';
  end if;

  if v_entitlement.state not in ('available','reserved') then
    raise exception 'Ledger entitlement is not available for initial binding.' using errcode='23514';
  end if;

  if exists (
    select 1
    from atlas.ledger_entitlement_bindings b
    where b.organization_id = p_organization_id
      and b.organization_unit_id is null
      and b.ended_at is null
      and b.ledger_entitlement_id <> v_entitlement.id
  ) then
    raise exception 'Target Organization already has a live root-scope entitlement binding.' using errcode='23505';
  end if;

  select p.starting_label
  into v_starting_label
  from atlas.implementation_cases c
  join atlas.implementation_purchases p on p.id = c.implementation_purchase_id
  where c.id = p_implementation_case_id;

  if v_starting_label is null then
    raise exception 'Implementation purchase is unavailable.' using errcode='23503';
  end if;

  insert into atlas.ledger_entitlement_bindings(
    implementation_case_id,
    ledger_entitlement_id,
    organization_id,
    organization_unit_id,
    bound_by_participant_id,
    state,
    binding_basis,
    metadata,
    ledger_id
  ) values (
    p_implementation_case_id,
    v_entitlement.id,
    p_organization_id,
    null,
    v_practitioner_participant_id,
    'bound',
    jsonb_build_object(
      'source','bind_implementation_ledger_entitlement_self_api_v1',
      'institutionEstablishmentItemId',p_institution_item_id,
      'ledgerScopeEstablishmentItemId',p_ledger_scope_item_id,
      'practitionerParticipantId',v_practitioner_participant_id,
      'setupSponsorParticipantId',v_setup_sponsor_participant_id,
      'setupSponsorPrincipalId',v_sponsor_principal_id,
      'targetLedgerId',p_ledger_id
    ),
    jsonb_build_object(
      'purchaseStartingLabel',v_starting_label,
      'institutionalRealityPreexisting',true
    ),
    p_ledger_id
  )
  returning * into v_binding;

  update atlas.ledger_entitlements
  set state = 'bound', updated_at = now()
  where id = v_entitlement.id;

  update atlas.implementation_cases
  set metadata = metadata || jsonb_build_object(
      'commercialLedgerBindingEstablishedAt',now(),
      'organizationId',p_organization_id,
      'ledgerId',p_ledger_id,
      'baselineLedgerBindingId',v_binding.id,
      'setupSponsorPrincipalId',v_sponsor_principal_id
    ),
    updated_at = now()
  where id = p_implementation_case_id;

  return jsonb_build_object(
    'ok',true,
    'alreadyBound',false,
    'implementationCaseId',p_implementation_case_id,
    'organizationId',p_organization_id,
    'organizationName',v_organization.name,
    'ledgerId',p_ledger_id,
    'ledgerStableKey',v_ledger.stable_key,
    'ledgerEntitlementId',v_entitlement.id,
    'bindingId',v_binding.id,
    'bindingState',v_binding.state,
    'setupSponsorParticipantId',v_setup_sponsor_participant_id,
    'setupSponsorPrincipalId',v_sponsor_principal_id,
    'organizationCreated',false,
    'principalCreated',false,
    'membershipCreated',false
  );
end;
$function$;

revoke all on function atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
  from public, anon;
grant execute on function atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
  to authenticated;

-- Historical compatibility endpoint: it may report a prior binding, but it may no longer
-- manufacture Organization/Ledger identity from purchase state.
create or replace function atlas.establish_implementation_organization_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_institution_item_id uuid,
  p_ledger_scope_item_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_practitioner_participant_id uuid;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_organization atlas.organizations%rowtype;
  v_ledger atlas.ledgers%rowtype;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select cp.id
  into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id = p_implementation_case_id
    and cp.relationship_kind = 'practitioner'
    and cp.active
    and cp.human_user_id = v_uid
  limit 1;

  if v_practitioner_participant_id is null then
    raise exception 'This implementation case is not assigned to the current practitioner.' using errcode='42501';
  end if;

  select b.*
  into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.implementation_case_id = p_implementation_case_id
    and b.ledger_entitlement_id = p_ledger_entitlement_id
    and b.ended_at is null
  limit 1;

  if v_binding.id is not null then
    select o.* into v_organization
    from atlas.organizations o
    where o.id = v_binding.organization_id;

    select l.* into v_ledger
    from atlas.ledgers l
    where l.id = v_binding.ledger_id;

    return jsonb_build_object(
      'ok',true,
      'alreadyBound',true,
      'organizationId',v_binding.organization_id,
      'organizationName',v_organization.name,
      'organizationStableKey',v_organization.stable_key,
      'ledgerId',v_binding.ledger_id,
      'ledgerStableKey',v_ledger.stable_key,
      'ledgerEntitlementId',p_ledger_entitlement_id,
      'bindingId',v_binding.id,
      'bindingState',v_binding.state,
      'membershipCreated',false,
      'principalCreated',false,
      'organizationCreated',false
    );
  end if;

  raise exception 'Institutional scope must already exist. Use bind_implementation_ledger_entitlement_self_api_v1 to attach this entitlement to an existing governed Ledger.' using errcode='0A000';
end;
$function$;

revoke all on function atlas.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text)
  from public, anon;
grant execute on function atlas.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text)
  to authenticated, service_role;

COMMIT;
