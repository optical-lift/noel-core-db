-- Atlas Person Position Self Projection v0 candidate.
-- Read-only composition over current canonical Person-rooted relationships.
-- Candidate only: no migration identity and no production authority.

begin;

-- Current durable responsibility v2.
-- Institutional Person Record + Position Appointment are the current human/institution
-- and position roots. Organization Membership and Identity Subject remain optional
-- compatibility/provenance carriers and are not required for responsibility existence.
create or replace function atlas.effective_person_organization_responsibilities_current_v2(
  p_person_id uuid,
  p_organization_id uuid default null
)
returns table(
  person_id uuid,
  person_display_name text,
  institutional_person_record_id uuid,
  organization_id uuid,
  organization_key text,
  organization_name text,
  organization_membership_id uuid,
  identity_subject_id uuid,
  appointment_id uuid,
  appointment_kind text,
  position_id uuid,
  position_key text,
  position_title text,
  position_kind text,
  organization_unit_id uuid,
  organization_unit_key text,
  organization_unit_name text,
  organization_unit_kind text,
  responsibility_id uuid,
  responsibility_key text,
  responsibility_name text,
  responsibility_kind text,
  position_responsibility_kind text,
  scope_link_id uuid,
  scope_kind text,
  scope_id text,
  scope_relation_kind text,
  resolution_state text,
  evidence jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select
    pe.id as person_id,
    pe.display_name as person_display_name,
    ipr.id as institutional_person_record_id,
    o.id as organization_id,
    o.stable_key as organization_key,
    o.name as organization_name,
    a.organization_membership_id,
    coalesce(a.identity_subject_id,ipr.identity_subject_id) as identity_subject_id,
    a.id as appointment_id,
    a.appointment_kind,
    p.id as position_id,
    p.stable_key as position_key,
    p.display_title as position_title,
    p.position_kind,
    u.id as organization_unit_id,
    u.stable_key as organization_unit_key,
    u.name as organization_unit_name,
    u.unit_kind as organization_unit_kind,
    r.id as responsibility_id,
    r.stable_key as responsibility_key,
    r.name as responsibility_name,
    r.responsibility_kind,
    pr.relationship_kind as position_responsibility_kind,
    rs.id as scope_link_id,
    rs.scope_kind,
    rs.scope_id,
    rs.relation_kind as scope_relation_kind,
    case
      when rs.scope_kind='organization_unit' and su.id is not null then 'established_current'::text
      else 'indeterminate'::text
    end as resolution_state,
    jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','effective_person_organization_responsibilities_current_v2',
      'personId',pe.id,
      'institutionalPersonRecordId',ipr.id,
      'organizationMembershipId',a.organization_membership_id,
      'identitySubjectId',coalesce(a.identity_subject_id,ipr.identity_subject_id),
      'appointmentId',a.id,
      'positionId',p.id,
      'responsibilityId',r.id,
      'scopeLinkId',rs.id,
      'scopeResolution',case
        when rs.scope_kind<>'organization_unit' then 'unsupported_scope_kind'
        when su.id is null then 'organization_unit_unresolved'
        else 'resolved'
      end,
      'resolvedScopeOrganizationUnitId',su.id,
      'institutionalPersonRecordRequired',true,
      'organizationMembershipRequired',false,
      'identitySubjectRequired',false,
      'currentOnly',true,
      'historicalDefinitionReconstruction','not_yet_available'
    )) as evidence
  from atlas.people pe
  join atlas.institutional_person_records ipr
    on ipr.person_id=pe.id
   and ipr.status='active'
  join atlas.organizations o
    on o.id=ipr.organization_id
   and o.status='active'
  join atlas.organization_position_appointments a
    on a.organization_id=ipr.organization_id
   and a.institutional_person_record_id=ipr.id
   and a.status='active'
   and a.begins_at<=now()
   and (a.ends_at is null or a.ends_at>now())
  join atlas.organization_positions p
    on p.id=a.position_id
   and p.organization_id=ipr.organization_id
   and p.status='active'
  join atlas.organization_units u
    on u.id=p.organization_unit_id
   and u.organization_id=p.organization_id
   and u.status='active'
  join atlas.organization_position_responsibilities pr
    on pr.position_id=p.id
  join atlas.organization_responsibilities r
    on r.id=pr.responsibility_id
   and r.organization_id=ipr.organization_id
   and r.status='active'
  join atlas.organization_responsibility_scopes rs
    on rs.organization_id=ipr.organization_id
   and rs.responsibility_id=r.id
  left join atlas.organization_units su
    on rs.scope_kind='organization_unit'
   and su.id=case
     when rs.scope_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       then rs.scope_id::uuid
     else null
   end
   and su.organization_id=rs.organization_id
   and su.status='active'
  where pe.id=p_person_id
    and pe.status='active'
    and (p_organization_id is null or ipr.organization_id=p_organization_id)
  order by o.stable_key,u.stable_key,p.stable_key,r.stable_key,rs.scope_kind,rs.scope_id,rs.id;
$function$;

comment on function atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid) is
  'Canonical current effective Person↔Organization durable-responsibility read rooted in canonical Person + active Institutional Person Record + current Position Appointment + current Position→Responsibility definition + bounded Responsibility Scope. Organization Membership and Identity Subject are optional compatibility/provenance carriers, not required responsibility roots. Unsupported or unresolved Scope remains indeterminate. Current-only until append-only position/responsibility/scope definition history exists.';

revoke all on function atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)
  from public, anon, authenticated;
grant execute on function atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)
  to postgres, service_role;

insert into atlas.architecture_truth_authorities(
  authority_key,
  domain_key,
  truth_question,
  authority_owner,
  authority_status,
  canonical_relations,
  canonical_functions,
  supporting_relations,
  consumer_surfaces,
  known_competitors,
  source_custody,
  rationale
) values (
  'person_organization_current_durable_responsibility',
  'institutional_responsibility',
  'What bounded Organization responsibility does this canonical Person currently carry through current institutional placement?',
  'atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)',
  'canonical',
  array[
    'atlas.people',
    'atlas.institutional_person_records',
    'atlas.organization_position_appointments',
    'atlas.organization_positions',
    'atlas.organization_position_responsibilities',
    'atlas.organization_responsibilities',
    'atlas.organization_responsibility_scopes',
    'atlas.organization_units'
  ],
  array[
    'atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)'
  ],
  array[
    'atlas.organization_memberships',
    'atlas.identity_subjects',
    'atlas.organization_employee_seats',
    'atlas.work_allocations'
  ],
  array[
    'Person Position',
    'future Person-specific Ledger projection',
    'future governed effect-uptake relationship evidence'
  ],
  array[
    'atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)',
    'atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)',
    'organization_memberships.role treated as durable responsibility',
    'employee seat treated as durable responsibility',
    'work_allocations treated as standing institutional responsibility'
  ],
  'optical-lift/noel-core-db:candidates/atlas_person_position_self_projection_v0.sql',
  'Institutional Person Record is now the canonical Organization-scoped human relation and Position Appointment is canonically bound to it. Current durable responsibility therefore must not require Organization Membership or Identity Subject. Those older carriers remain useful provenance/compatibility evidence but cannot own responsibility existence.'
)
on conflict (authority_key)
do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

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
        'institutionalPersonRecordId',r.institutional_person_record_id,
        'organizationMembershipId',r.organization_membership_id,
        'institutionalIdentitySubjectId',r.identity_subject_id,
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
        'authorityBasis','atlas.effective_person_organization_responsibilities_current_v2',
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
  from atlas.effective_person_organization_responsibilities_current_v2(
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
  'Self-only, read-only Person Position v0. Composes canonical Person, Principal/Household root, institutional membership, IPR-rooted current durable responsibility, existing access, Principal Ledger authority and Connected Source orientation without creating a new truth domain or inferring Work visibility, execution warrant, Calendar commitments, Personal Money, derived availability or attention entitlement.';

revoke all on function atlas.person_position_self_api_v1()
  from public, anon;
grant execute on function atlas.person_position_self_api_v1()
  to authenticated;

commit;
