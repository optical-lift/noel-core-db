-- Atlas Person Position Self Projection v0 candidate.
-- Read-only composition over current canonical Person-rooted relationships.
-- Candidate only: no migration identity and no production authority.

begin;

create or replace function atlas.person_position_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_person_id uuid;
  v_person atlas.people%rowtype;
  v_principal atlas.principals%rowtype;
  v_households jsonb := '[]'::jsonb;
  v_memberships jsonb := '[]'::jsonb;
  v_responsibilities jsonb := '[]'::jsonb;
  v_access jsonb := jsonb_build_object(
    'contractVersion','organization_access_self_v1',
    'items','[]'::jsonb
  );
  v_ledgers jsonb := jsonb_build_object(
    'contractVersion','principal_ledgers_self_v1',
    'state','principal_required',
    'items','[]'::jsonb
  );
  v_sources jsonb := '[]'::jsonb;
  v_source_state text := 'unsupported_current_schema';
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_person_id := atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion','person_position_self_v0',
      'state','person_required',
      'identity',null,
      'principalRoot',null,
      'householdContexts','[]'::jsonb,
      'institutionalMemberships','[]'::jsonb,
      'durableInstitutionalResponsibilities','[]'::jsonb,
      'institutionalAccess',jsonb_build_object('items','[]'::jsonb),
      'ledgerContexts',jsonb_build_object('items','[]'::jsonb),
      'sourcePosition',jsonb_build_object(
        'state','not_evaluated',
        'items','[]'::jsonb
      ),
      'workPosition',jsonb_build_object(
        'state','not_aggregated_v0',
        'reason','canonical_person_required'
      ),
      'financialInstitutionalPosition',jsonb_build_object(
        'state','not_aggregated_v0',
        'reason','canonical_person_required'
      ),
      'stateQuality',jsonb_build_object(
        'currentOnly',true,
        'coverage','partial',
        'canonicalPersonResolved',false
      ),
      'unsupportedFacets',jsonb_build_array(
        'personal_calendar',
        'whole_person_commitments',
        'private_to_institutional_availability',
        'personal_finance',
        'universal_person_capabilities',
        'universal_things_assets',
        'attention_actuals',
        'person_position_driven_notebook_exposure'
      ),
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'personPositionIsCanonicalTruth',false,
        'personPositionEstablishesNoUpstreamReality',true
      )
    );
  end if;

  select p.*
  into v_person
  from atlas.people p
  where p.id=v_person_id
    and p.status='active'
  limit 1;

  if v_person.id is null then
    return jsonb_build_object(
      'contractVersion','person_position_self_v0',
      'state','person_unavailable',
      'identity',jsonb_build_object('personId',v_person_id),
      'stateQuality',jsonb_build_object(
        'currentOnly',true,
        'coverage','partial',
        'canonicalPersonResolved',false
      ),
      'unsupportedFacets',jsonb_build_array(
        'all_position_facets_until_person_is_active'
      ),
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'personPositionEstablishesNoUpstreamReality',true
      )
    );
  end if;

  select p.*
  into v_principal
  from atlas.principals p
  where p.person_id=v_person_id
    and p.status='active'
  limit 1;

  if v_principal.id is not null and v_principal.active_household_id is not null then
    v_households := jsonb_build_array(
      jsonb_build_object(
        'householdId',v_principal.active_household_id,
        'positionKind','active_principal_household',
        'state','established_current',
        'authorityBasis','atlas.principals.active_household_id',
        'detailState','identity_only_v0'
      )
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'organizationMembershipId',m.id,
        'institutionalIdentitySubjectId',m.identity_subject_id,
        'compatibilityRole',m.role,
        'state','established_current',
        'authorityBasis','atlas.organization_memberships',
        'knowledgeExposureState','domain_specific_not_aggregated_v0',
        'actionAuthorityState','domain_specific_not_aggregated_v0',
        'responsibilityState','separate_facet',
        'compatibilityRoleIsNotAuthority',true
      ))
      order by o.name,o.id,m.id
    ),
    '[]'::jsonb
  )
  into v_memberships
  from atlas.organization_memberships m
  join atlas.organizations o
    on o.id=m.organization_id
   and o.status='active'
  where m.person_id=v_person_id
    and m.active=true
    and (m.eligibility_begins_on is null or m.eligibility_begins_on<=current_date)
    and (m.eligibility_ends_on is null or m.eligibility_ends_on>=current_date);

  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'organizationId',r.organization_id,
        'organizationName',r.organization_name,
        'organizationMembershipId',r.organization_membership_id,
        'appointmentId',r.appointment_id,
        'appointmentKind',r.appointment_kind,
        'positionId',r.position_id,
        'positionKey',r.position_key,
        'positionTitle',r.position_title,
        'positionKind',r.position_kind,
        'organizationUnitId',r.organization_unit_id,
        'organizationUnitKey',r.organization_unit_key,
        'organizationUnitName',r.organization_unit_name,
        'responsibilityId',r.responsibility_id,
        'responsibilityKey',r.responsibility_key,
        'responsibilityName',r.responsibility_name,
        'responsibilityKind',r.responsibility_kind,
        'positionResponsibilityKind',r.position_responsibility_kind,
        'scopeLinkId',r.scope_link_id,
        'scopeKind',r.scope_kind,
        'scopeId',r.scope_id,
        'scopeRelationKind',r.scope_relation_kind,
        'resolutionState',r.resolution_state,
        'evidence',r.evidence,
        'authorityBasis','atlas.effective_person_organization_responsibilities_current_v1',
        'doesNotImplyWorkResponsibility',true,
        'doesNotImplyExecutionWarrant',true
      ))
      order by
        r.organization_name,
        r.position_key,
        r.responsibility_key,
        r.scope_kind,
        r.scope_id,
        r.scope_link_id
    ),
    '[]'::jsonb
  )
  into v_responsibilities
  from atlas.effective_person_organization_responsibilities_current_v1(
    v_person_id,
    null
  ) r;

  v_access := atlas.organization_access_self_api_v1();

  if v_principal.id is not null then
    v_ledgers := atlas.principal_ledgers_self_api_v1();
  end if;

  if to_regprocedure('atlas.connected_sources_self_api_v1()') is not null then
    execute $sql$
      select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb)
      from atlas.connected_sources_self_api_v1() s
    $sql$ into v_sources;
    v_source_state := 'available';
  elsif to_regprocedure('public.connected_sources_self_api_v1()') is not null then
    execute $sql$
      select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb)
      from public.connected_sources_self_api_v1() s
    $sql$ into v_sources;
    v_source_state := 'available';
  end if;

  return jsonb_build_object(
    'contractVersion','person_position_self_v0',
    'state','ready',
    'identity',jsonb_strip_nulls(jsonb_build_object(
      'personId',v_person.id,
      'personStableKey',v_person.stable_key,
      'displayName',v_person.display_name,
      'status',v_person.status,
      'authorityBasis','atlas.people',
      'credentialIsNotPersonIdentity',true
    )),
    'principalRoot',case
      when v_principal.id is null then null
      else jsonb_strip_nulls(jsonb_build_object(
        'principalId',v_principal.id,
        'principalStableKey',v_principal.stable_key,
        'displayName',v_principal.name,
        'homeTimezone',v_principal.home_timezone,
        'activeHouseholdId',v_principal.active_household_id,
        'state','established_current',
        'authorityBasis','atlas.principals',
        'principalIsNotPersonIdentity',true
      ))
    end,
    'householdContexts',v_households,
    'institutionalMemberships',v_memberships,
    'durableInstitutionalResponsibilities',v_responsibilities,
    'institutionalAccess',coalesce(v_access,jsonb_build_object('items','[]'::jsonb)),
    'ledgerContexts',coalesce(v_ledgers,jsonb_build_object('items','[]'::jsonb)),
    'sourcePosition',jsonb_build_object(
      'state',v_source_state,
      'items',coalesce(v_sources,'[]'::jsonb),
      'truthBoundary',jsonb_build_object(
        'connectedSourceIsEvidenceCustody',true,
        'connectedSourceDoesNotEstablishLifeTruth',true,
        'coverageMayRemainUnknown',true
      )
    ),
    'workPosition',jsonb_build_object(
      'state','not_aggregated_v0',
      'reason','work_visibility_and_execution_remain_on_existing_governed_membranes',
      'currentReadFamilies',jsonb_build_array(
        'Employee Atlas',
        'Company Work',
        'Worker Day'
      ),
      'truthBoundary',jsonb_build_object(
        'durableResponsibilityIsNotExactWorkResponsibility',true,
        'exactWorkResponsibilityIsNotExecutionWarrant',true,
        'membershipDoesNotGrantWorkVisibility',true
      )
    ),
    'financialInstitutionalPosition',jsonb_build_object(
      'state','available_on_demand_for_authorized_ledgers',
      'ledgerContextSource','atlas.principal_ledgers_self_api_v1',
      'currentReadSeams',jsonb_build_array(
        'atlas.commercial_financial_position_self_api_v1',
        'atlas.organization_spend_window_self_api_v1',
        'current Expense Reporting read membrane'
      ),
      'personalFinanceState','unsupported_v0',
      'truthBoundary',jsonb_build_object(
        'ledgerAuthorityIsNotCommercialEntitlement',true,
        'institutionalFinanceIsNotPersonalFinance',true,
        'providerObservationsAreNotPersonalMoneyTruth',true
      )
    ),
    'stateQuality',jsonb_build_object(
      'currentOnly',true,
      'coverage','partial',
      'canonicalPersonResolved',true,
      'principalResolved',v_principal.id is not null,
      'historicalPositionReconstruction','not_claimed_v0',
      'sourceCoverageMayBePartial',true,
      'unresolvedStatePreserved',true
    ),
    'unsupportedFacets',jsonb_build_array(
      'personal_calendar',
      'whole_person_commitments',
      'private_to_institutional_availability',
      'personal_finance',
      'universal_person_capabilities',
      'universal_things_assets',
      'attention_actuals',
      'person_position_driven_notebook_exposure'
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'personPositionIsProjectionNotTruthDomain',true,
      'personPositionEstablishesNoUpstreamReality',true,
      'membershipDoesNotImplyKnowledge',true,
      'membershipDoesNotImplyResponsibility',true,
      'responsibilityDoesNotImplyWork',true,
      'workDoesNotImplyExecution',true,
      'sourceDoesNotImplyLifeFact',true,
      'positionDoesNotDecideAttention',true,
      'positionDoesNotPlaceClock',true
    )
  );
end;
$function$;

comment on function atlas.person_position_self_api_v1() is
  'Self-only, read-only Person Position v0. Composes canonical Person, Principal/Household root, institutional membership, current durable responsibility, existing access, Principal Ledger authority and Connected Source orientation without creating a new truth domain or inferring Work visibility, execution warrant, Calendar commitments, Personal Money, derived availability or attention entitlement.';

revoke all on function atlas.person_position_self_api_v1()
  from public, anon;
grant execute on function atlas.person_position_self_api_v1()
  to authenticated;

commit;
