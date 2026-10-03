do $cutover$
declare
  v_lex_person constant uuid := '59e9fd9d-e7fd-48ca-91e0-ee271c05148e';
  v_lex_auth constant uuid := '4cd799e2-16d4-4020-9d21-ccf1a2b98553';
  v_lex_credential constant uuid := '30a8b461-2732-47e4-87c5-5bd0d711b6e8';
  v_lex_principal constant uuid := 'e99e759c-1a65-4ddc-ba41-91f72c5981d8';

  v_elm_entity constant uuid := 'de584041-a636-424d-b8f5-2ff90ba3685e';
  v_elm_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';

  v_flower_ledger constant uuid := '0c5f53dd-3659-4fed-b8d7-a771a4172f36';
  v_venue_ledger constant uuid := '8df18008-28ef-48e9-babd-1eb0e0dd7e3c';

  v_lex_membership constant uuid := 'b528660c-19d7-4411-b293-879fd74809c8';
  v_flower_authority constant uuid := '522dbfb6-d731-4bdc-941e-c5d798225bfe';
  v_venue_authority constant uuid := '4721b33a-1d06-4576-b485-7def85765882';

  v_flower_case uuid;
  v_venue_case uuid;
  v_flower_seat uuid;
  v_venue_seat uuid;
  v_old_action_count integer;
  v_new_action_count integer;
begin
  if not exists(
    select 1 from atlas.people
    where id=v_lex_person and status='active' and display_name='Lex'
  ) then raise exception 'Lex Person admission source is not current.'; end if;

  if not exists(
    select 1 from atlas.person_auth_credentials
    where id=v_lex_credential and person_id=v_lex_person
      and auth_user_id=v_lex_auth and status='active'
  ) then raise exception 'Lex Auth binding admission source is not current.'; end if;

  if not exists(
    select 1 from local_intel.entities
    where id=v_elm_entity and stable_key='elm-farm'
      and name='Elm Farm' and status='active'
  ) then raise exception 'Elm Shared Intelligence identity source is not current.'; end if;

  if not exists(
    select 1 from atlas.organizations
    where id=v_elm_org and stable_key='elm_farm' and name='Elm Farm' and status='active'
  ) then raise exception 'Elm legacy institutional carrier is not current.'; end if;

  if not exists(
    select 1 from atlas.ledgers
    where id=v_flower_ledger and status='active'
  ) or not exists(
    select 1 from atlas.ledgers
    where id=v_venue_ledger and status='active'
  ) then raise exception 'Elm legacy Ledger sources are not current.'; end if;

  insert into reality.entities(
    id,stable_key,entity_kind,display_name,identity_state,metadata
  ) values (
    v_lex_person,'lex','person','Lex','canonical',
    jsonb_build_object(
      'admissionState','admit_as_is',
      'admissionBasis','existing Atlas Person + active Auth credential',
      'legacyAtlasPeopleId',v_lex_person,
      'admittedAt',now()
    )
  );

  insert into reality.auth_person_bindings(
    id,auth_user_id,person_entity_id,binding_state,binding_basis,bound_at
  )
  select
    v_lex_credential,pac.auth_user_id,v_lex_person,'active',
    jsonb_build_object(
      'admissionState','admit_as_is',
      'source','atlas.person_auth_credentials',
      'legacyCredentialId',pac.id,
      'legacyProvenance',pac.provenance
    ),
    pac.bound_at
  from atlas.person_auth_credentials pac
  where pac.id=v_lex_credential;

  insert into reality.entities(
    id,stable_key,entity_kind,display_name,identity_state,metadata
  )
  select
    e.id,'elm-farm','business','Elm Farm','canonical',
    jsonb_build_object(
      'admissionState','reconcile',
      'admissionBasis','same real-world Elm Farm identity; legacy Shared Intelligence record conflated business with place attributes',
      'legacySharedIntelligenceEntityId',e.id,
      'legacySharedIntelligenceEntityType',e.entity_type,
      'legacyOrganizationId',v_elm_org,
      'website',e.website_url,
      'physicalAddress',jsonb_strip_nulls(jsonb_build_object(
        'addressLine1',e.address_line1,
        'city',e.city,
        'state',e.state,
        'postalCode',e.postal_code
      )),
      'identityBoundary','Elm Farm business/entity; physical place facts remain observations about the same subject and may later be normalized into Place relationships',
      'admittedAt',now()
    )
  from local_intel.entities e
  where e.id=v_elm_entity;

  insert into reality.contact_routes(
    entity_id,route_kind,route_value,normalized_value,route_state,public_disclosure,evidence,metadata
  )
  select
    v_elm_entity,'postal',
    concat_ws(', ',nullif(e.address_line1,''),nullif(e.city,''),nullif(e.state,''),nullif(e.postal_code,'')),
    lower(regexp_replace(concat_ws(' ',e.address_line1,e.city,e.state,e.postal_code),'\s+',' ','g')),
    'observed',true,
    jsonb_build_object(
      'source','local_intel.entities','legacyEntityId',e.id,
      'verificationState',e.verification_state,'lastVerifiedAt',e.last_verified_at
    ),
    '{"claimChallengeEligible":true}'::jsonb
  from local_intel.entities e
  where e.id=v_elm_entity and e.address_line1 is not null;

  insert into reality.contact_routes(
    entity_id,route_kind,route_value,normalized_value,route_state,public_disclosure,evidence,metadata
  )
  select
    v_elm_entity,'website',e.website_url,lower(e.website_url),'observed',true,
    jsonb_build_object(
      'source','local_intel.entities','legacyEntityId',e.id,
      'verificationState',e.verification_state,'lastVerifiedAt',e.last_verified_at
    ),
    '{"claimChallengeEligible":false}'::jsonb
  from local_intel.entities e
  where e.id=v_elm_entity and e.website_url is not null;

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,desired_ledger_name,
    onboarding_state,case_kind,onboarding_basis
  ) values (
    v_elm_entity,v_lex_person,'Elm Farm Flower Ledger',
    'ready_to_activate','legacy_adjudicated_migration',
    jsonb_build_object(
      'legacyLedgerId',v_flower_ledger,
      'migrationAdjudicated',true,
      'adjudication','Legacy Elm Farm Ledger contains established farm/production actions and is admitted as the flower/farm operating Ledger of canonical Elm Farm.',
      'legacyRelationship','Sibling of the separate Elm Venue Ledger.',
      'requestedBy','Lex during Reality/Ledger constitutional cutover'
    )
  ) returning id into v_flower_case;

  insert into ledger.ledgers(
    id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata,activated_at
  )
  select
    l.id,v_elm_entity,v_flower_case,'elm-farm:flower','Elm Farm Flower Ledger','active',
    jsonb_build_object(
      'admissionState','reconcile','legacyLedgerId',l.id,
      'legacyStableKey',l.stable_key,'legacyName',l.name,'legacyLedgerKind',l.ledger_kind,
      'operationalBoundary','Elm Farm flower/farm production and related farm operations',
      'doesNotOwnSubjectEntity',true
    ),
    l.created_at
  from atlas.ledgers l
  where l.id=v_flower_ledger;

  insert into ledger.onboarding_cases(
    subject_entity_id,requested_by_person_entity_id,desired_ledger_name,
    onboarding_state,case_kind,onboarding_basis
  ) values (
    v_elm_entity,v_lex_person,'Elm Farm Venue Ledger',
    'ready_to_activate','legacy_adjudicated_migration',
    jsonb_build_object(
      'legacyLedgerId',v_venue_ledger,
      'migrationAdjudicated',true,
      'adjudication','Separate historical Elm Venue Ledger is preserved as a distinct action world of canonical Elm Farm.',
      'legacyRelationship','Sibling of the legacy Elm Farm operating Ledger.',
      'requestedBy','Lex during Reality/Ledger constitutional cutover'
    )
  ) returning id into v_venue_case;

  insert into ledger.ledgers(
    id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state,metadata,activated_at
  )
  select
    l.id,v_elm_entity,v_venue_case,'elm-farm:venue','Elm Farm Venue Ledger','active',
    jsonb_build_object(
      'admissionState','admit_as_is','legacyLedgerId',l.id,
      'legacyStableKey',l.stable_key,'legacyName',l.name,'legacyLedgerKind',l.ledger_kind,
      'operationalBoundary','Elm Farm venue and gathering operations',
      'doesNotOwnSubjectEntity',true
    ),
    l.created_at
  from atlas.ledgers l
  where l.id=v_venue_ledger;

  insert into ledger.seats(ledger_id,person_entity_id,seat_basis,began_at)
  select
    v_flower_ledger,v_lex_person,
    jsonb_build_object(
      'basisKind','migration_adjudication','legacyMembershipId',v_lex_membership,
      'legacyLedgerAuthorityEvidenceId',v_flower_authority,
      'meaning','Lex participates in this Ledger',
      'doesNotEstablishOwnership',true,'doesNotPreservePrincipalAuthority',true
    ),
    least(m.created_at,pla.established_at)
  from atlas.organization_memberships m
  join atlas.principal_ledger_authorities pla on pla.id=v_flower_authority
  where m.id=v_lex_membership and m.active
  returning id into v_flower_seat;

  insert into ledger.seats(ledger_id,person_entity_id,seat_basis,began_at)
  select
    v_venue_ledger,v_lex_person,
    jsonb_build_object(
      'basisKind','migration_adjudication','legacyMembershipId',v_lex_membership,
      'legacyLedgerAuthorityEvidenceId',v_venue_authority,
      'meaning','Lex participates in this Ledger',
      'doesNotEstablishOwnership',true,'doesNotPreservePrincipalAuthority',true
    ),
    least(m.created_at,pla.established_at)
  from atlas.organization_memberships m
  join atlas.principal_ledger_authorities pla on pla.id=v_venue_authority
  where m.id=v_lex_membership and m.active
  returning id into v_venue_seat;

  select count(*)::integer into v_old_action_count
  from atlas.organization_ledger_entries
  where ledger_id=v_flower_ledger;

  insert into ledger.actions(
    id,ledger_id,action_kind,performed_by_entity_id,occurred_at,payload,provenance,idempotency_key,created_at
  )
  select
    e.id,v_flower_ledger,e.semantic_type,null,e.occurred_at,
    jsonb_build_object(
      'title',e.title,'detail',e.detail,'truthStatus',e.truth_status,
      'designationStatus',e.designation_status,'legacyPayload',e.payload,'correlation',e.correlation
    ),
    jsonb_build_object(
      'migration','atlas_reality_ledger_lex_elm_cutover_v1',
      'sourceTable','atlas.organization_ledger_entries',
      'legacyEntryId',e.id,'legacyOrganizationId',e.organization_id,
      'legacyOrganizationUnitId',e.organization_unit_id,
      'legacyProvenance',e.provenance,'actorNotYetAdmitted',true
    ),
    'legacy:atlas.organization_ledger_entries:'||e.id::text,e.created_at
  from atlas.organization_ledger_entries e
  where e.ledger_id=v_flower_ledger;

  select count(*)::integer into v_new_action_count
  from ledger.actions
  where ledger_id=v_flower_ledger;

  if v_new_action_count<>v_old_action_count then
    raise exception 'Elm Flower Ledger action migration mismatch: old %, new %',
      v_old_action_count,v_new_action_count;
  end if;

  insert into compatibility.legacy_bindings(
    legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id,basis
  ) values
    ('atlas','people',v_lex_person::text,'maps_to','reality','entities',v_lex_person,
      '{"admission":"admit_as_is"}'::jsonb),
    ('atlas','person_auth_credentials',v_lex_credential::text,'maps_to','reality','auth_person_bindings',v_lex_credential,
      '{"admission":"admit_as_is"}'::jsonb),
    ('local_intel','entities',v_elm_entity::text,'maps_to','reality','entities',v_elm_entity,
      '{"admission":"reconcile","legacyType":"place","newKind":"business"}'::jsonb),
    ('atlas','organizations',v_elm_org::text,'maps_to','reality','entities',v_elm_entity,
      '{"legacyRole":"duplicate institutional identity carrier"}'::jsonb),
    ('atlas','ledgers',v_flower_ledger::text,'maps_to','ledger','ledgers',v_flower_ledger,
      '{"admission":"reconcile","newStableKey":"elm-farm:flower"}'::jsonb),
    ('atlas','ledgers',v_venue_ledger::text,'maps_to','ledger','ledgers',v_venue_ledger,
      '{"admission":"admit_as_is","newStableKey":"elm-farm:venue"}'::jsonb),
    ('atlas','organization_memberships',v_lex_membership::text,'split_into','ledger','seats',v_flower_seat,
      '{"doesNotPreserveRole":"owner"}'::jsonb),
    ('atlas','organization_memberships',v_lex_membership::text,'split_into','ledger','seats',v_venue_seat,
      '{"doesNotPreserveRole":"owner"}'::jsonb);

  insert into compatibility.legacy_bindings(
    legacy_schema,legacy_table,legacy_key,disposition,basis
  ) values
    ('atlas','principals',v_lex_principal::text,'retired',
      '{"reason":"Auth now binds directly to canonical Person; Principal has no new-core authority role."}'::jsonb),
    ('atlas','principal_ledger_authorities',v_flower_authority::text,'retired',
      '{"reason":"Principal Ledger Authority does not migrate; participation is represented by a Seat."}'::jsonb),
    ('atlas','principal_ledger_authorities',v_venue_authority::text,'retired',
      '{"reason":"Principal Ledger Authority does not migrate; participation is represented by a Seat."}'::jsonb);

  insert into compatibility.legacy_bindings(
    legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id,basis
  )
  select
    'atlas','organization_ledger_entries',e.id::text,'maps_to',
    'ledger','actions',e.id,
    '{"migration":"preserve established action as Ledger action"}'::jsonb
  from atlas.organization_ledger_entries e
  where e.ledger_id=v_flower_ledger;
end
$cutover$;
