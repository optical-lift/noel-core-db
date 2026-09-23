-- Atlas participating-domain Domain Exposure v2 candidate.
-- Adds Household, Flower and Correspondence domain-owned exposure membranes,
-- then composes them with the production-live v1 evaluator.
-- Candidate only: no migration identity and no production authority.

begin;

create or replace function atlas.household_domain_exposure_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_position jsonb;
  v_person_id text;
  v_household jsonb;
  v_household_id text;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if to_regprocedure('atlas.person_position_self_api_v1()') is null then
    return jsonb_build_object(
      'contractVersion','household_domain_exposure_self_v1',
      'state','person_position_dependency_unavailable',
      'items','[]'::jsonb
    );
  end if;

  v_position := atlas.person_position_self_api_v1();
  if coalesce(v_position->>'state','') <> 'ready' then
    return jsonb_build_object(
      'contractVersion','household_domain_exposure_self_v1',
      'state',coalesce(v_position->>'state','unresolved'),
      'items','[]'::jsonb
    );
  end if;

  v_person_id := nullif(v_position->'person'->>'personId','');
  if v_person_id is null then
    v_person_id := nullif(v_position->>'personId','');
  end if;

  for v_household in
    select value
    from jsonb_array_elements(coalesce(v_position->'householdContexts','[]'::jsonb))
  loop
    if v_household->>'positionKind' <> 'active_principal_household'
       or v_household->>'state' <> 'established_current' then
      continue;
    end if;

    v_household_id := nullif(v_household->>'householdId','');
    if v_household_id is null then
      continue;
    end if;

    v_items := v_items || jsonb_build_array(
      jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','household.care_orientation.v1',
        'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
        'contextRef',jsonb_build_object('kind','household','id',v_household_id,'domain','household'),
        'subjectRef',jsonb_build_object('kind','household_care','id',v_household_id,'domain','household'),
        'encounter',jsonb_build_object(
          'state','eligible',
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','household_position','id',v_household_id,'domain','household',
            'relation','active_principal_household'
          )),
          'reasonCodes',jsonb_build_array('active_principal_household_orientation')
        ),
        'place',jsonb_build_object(
          'disposition','stable','desiredCarrierState','open','durabilityKey','home-care',
          'reasonCodes',jsonb_build_array('household_care_is_stable_orientation')
        ),
        'index',jsonb_build_object(
          'disposition','listed','reasonCodes',jsonb_build_array('active_household_orientation')
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array('household_place_existence_is_not_attention_authority'),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',jsonb_build_object(
          'sourceDomain','household','sourceKind','care_snapshot_v1','sourceId',v_household_id,
          'relationshipKind','state','governedRead','atlas.principal_household_care_snapshot_v1'
        ),
        'stateQuality',jsonb_build_object(
          'resolution','established','freshness','current','coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','household_position','id',v_household_id,'domain','household'
          ))
        ),
        'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'household place existence does not create Today placement',
          'household encounter does not grant household mutation authority',
          'active household context does not disclose another household'
        )
      ),
      jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','household.rhythm_orientation.v1',
        'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
        'contextRef',jsonb_build_object('kind','household','id',v_household_id,'domain','household'),
        'subjectRef',jsonb_build_object('kind','household_rhythm','id',v_household_id,'domain','household'),
        'encounter',jsonb_build_object(
          'state','eligible',
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','household_position','id',v_household_id,'domain','household',
            'relation','active_principal_household'
          )),
          'reasonCodes',jsonb_build_array('active_principal_household_orientation')
        ),
        'place',jsonb_build_object(
          'disposition','stable','desiredCarrierState','open','durabilityKey','household-rhythm',
          'reasonCodes',jsonb_build_array('household_rhythm_is_stable_orientation')
        ),
        'index',jsonb_build_object(
          'disposition','listed','reasonCodes',jsonb_build_array('active_household_orientation')
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array('rhythm_existence_is_not_attention_authority'),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',jsonb_build_object(
          'sourceDomain','household','sourceKind','rhythm_snapshot_v1','sourceId',v_household_id,
          'relationshipKind','cadence','governedRead','public.personal_setup_self_api_v1'
        ),
        'stateQuality',jsonb_build_object(
          'resolution','established','freshness','current','coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','household_position','id',v_household_id,'domain','household'
          ))
        ),
        'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'rhythm existence does not create current attention',
          'rhythm encounter does not grant cadence mutation authority'
        )
      ),
      jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','household.laundry_kernel_orientation.v1',
        'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
        'contextRef',jsonb_build_object('kind','household','id',v_household_id,'domain','household'),
        'subjectRef',jsonb_build_object('kind','world_kernel','id','household.laundry','domain','household'),
        'encounter',jsonb_build_object(
          'state','eligible',
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','household_position','id',v_household_id,'domain','household',
            'relation','active_principal_household'
          )),
          'reasonCodes',jsonb_build_array('active_principal_household_orientation')
        ),
        'place',jsonb_build_object(
          'disposition','stable','desiredCarrierState','open','durabilityKey','laundry',
          'reasonCodes',jsonb_build_array('laundry_kernel_is_stable_household_orientation')
        ),
        'index',jsonb_build_object(
          'disposition','listed','reasonCodes',jsonb_build_array('active_household_orientation')
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array('kernel_existence_is_not_attention_authority'),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',jsonb_build_object(
          'sourceDomain','household','sourceKind','laundry_kernel_v1','sourceId',v_household_id,
          'relationshipKind','sequence','governedRead','atlas.personal_laundry_kernel_self_api_v1'
        ),
        'stateQuality',jsonb_build_object(
          'resolution','established','freshness','current','coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','household_position','id',v_household_id,'domain','household'
          ))
        ),
        'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'world kernel existence does not establish a household instance',
          'kernel encounter does not grant execution authority',
          'laundry place existence does not place laundry on Today'
        )
      )
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','household_domain_exposure_self_v1',
    'state','ready',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'domainOwned',true,
      'personPositionConsumed',true,
      'carrierTablesRead',false,
      'notebookMutationAuthorized',false,
      'attentionAuthorityGranted',false
    )
  );
end;
$function$;

revoke all on function atlas.household_domain_exposure_self_api_v1() from public, anon;
grant execute on function atlas.household_domain_exposure_self_api_v1() to authenticated;

create or replace function atlas.flower_domain_exposure_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_position jsonb;
  v_person_id text;
  v_farm record;
  v_role text;
  v_unit_id text;
  v_context jsonb;
  v_items jsonb := '[]'::jsonb;
  v_harvest_eligible boolean;
  v_commercial_eligible boolean;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_position := atlas.person_position_self_api_v1();
  if coalesce(v_position->>'state','') <> 'ready' then
    return jsonb_build_object(
      'contractVersion','flower_domain_exposure_self_v1',
      'state',coalesce(v_position->>'state','unresolved'),
      'items','[]'::jsonb
    );
  end if;

  v_person_id := coalesce(
    nullif(v_position->'person'->>'personId',''),
    nullif(v_position->>'personId','')
  );

  for v_farm in
    select f.id as farm_id,
           f.organization_id,
           f.organization_unit_id,
           f.name as farm_name,
           fm.id as membership_id,
           fm.role
    from atlas.farms f
    join lateral (
      select m.id,m.role
      from atlas.farm_memberships m
      where m.user_id=v_uid
        and m.farm_id=f.id
        and m.active=true
      order by m.created_at,m.id
      limit 1
    ) fm on true
    where f.status='active'
    order by f.name,f.id
  loop
    v_role := v_farm.role;
    v_unit_id := case when v_farm.organization_unit_id is null then null else v_farm.organization_unit_id::text end;
    v_harvest_eligible := v_role in ('owner','manager','farm_hand') and v_unit_id is not null;
    v_commercial_eligible := v_role in ('owner','manager') and v_unit_id is not null;

    v_context := case
      when v_unit_id is null then jsonb_build_object(
        'kind','organization','id',v_farm.organization_id,'domain','organization',
        'resolution','organization_unit_required'
      )
      else jsonb_build_object(
        'kind','organization_unit','id',v_unit_id,'domain','organization',
        'organizationId',v_farm.organization_id
      )
    end;

    v_items := v_items || jsonb_build_array(
      jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','flower.harvest_orientation.v1',
        'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
        'contextRef',v_context,
        'subjectRef',jsonb_build_object('kind','farm','id',v_farm.farm_id,'domain','flower'),
        'encounter',jsonb_build_object(
          'state',case when v_harvest_eligible then 'eligible' else
            case when v_unit_id is null and v_role in ('owner','manager','farm_hand') then 'unresolved' else 'ineligible' end end,
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','farm_membership','id',v_farm.membership_id,'domain','flower',
            'relation','active_membership','role',v_role
          )),
          'reasonCodes',jsonb_build_array(
            case
              when v_unit_id is null then 'canonical_organization_unit_required'
              when v_harvest_eligible then 'active_farm_membership_has_harvest_read'
              else 'farm_harvest_read_not_authorized'
            end
          )
        ),
        'place',case when v_harvest_eligible then jsonb_build_object(
          'disposition','stable','desiredCarrierState','open',
          'durabilityKey','flower-harvest:'||v_farm.farm_id::text,
          'reasonCodes',jsonb_build_array('farm_harvest_is_stable_operating_orientation')
        ) else jsonb_build_object(
          'disposition','none','durabilityKey','flower-harvest:'||v_farm.farm_id::text,
          'reasonCodes',jsonb_build_array('harvest_exposure_basis_not_established')
        ) end,
        'index',jsonb_build_object(
          'disposition',case when v_harvest_eligible then 'listed' else 'absent' end,
          'reasonCodes',jsonb_build_array(
            case when v_harvest_eligible then 'domain_authorized_harvest_orientation'
                 else 'harvest_not_exposed' end
          )
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array('harvest_page_existence_is_not_attention_authority'),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',case when v_harvest_eligible then jsonb_build_object(
          'sourceDomain','flower','sourceKind','harvest_recent_v1','sourceId',v_farm.farm_id,
          'relationshipKind','evidence','governedRead','atlas.flower_harvest_notebook_self_api_v1',
          'metadata',jsonb_build_object(
            'supportingGovernedReads',jsonb_build_array('atlas.flower_ready_inventory_notebook_self_api_v1')
          )
        ) else null end,
        'stateQuality',jsonb_build_object(
          'resolution',case when v_unit_id is null then 'unresolved' else 'established' end,
          'freshness','current','coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','farm_membership','id',v_farm.membership_id,'domain','flower'
          ))
        ),
        'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'farm membership is a Flower-domain rule and not a universal Atlas role rule',
          'Harvest exposure does not imply Ready inventory authority',
          'Harvest exposure does not grant Flower mutation authority',
          'Flower page existence does not create Today placement'
        )
      ),
      jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','flower.ready_inventory_orientation.v1',
        'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
        'contextRef',v_context,
        'subjectRef',jsonb_build_object('kind','farm','id',v_farm.farm_id,'domain','flower'),
        'encounter',jsonb_build_object(
          'state',case when v_commercial_eligible then 'eligible' else
            case when v_unit_id is null and v_role in ('owner','manager') then 'unresolved' else 'ineligible' end end,
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','farm_membership','id',v_farm.membership_id,'domain','flower',
            'relation','active_membership','role',v_role
          )),
          'reasonCodes',jsonb_build_array(
            case
              when v_unit_id is null then 'canonical_organization_unit_required'
              when v_commercial_eligible then 'owner_or_manager_inventory_authority'
              else 'owner_or_manager_inventory_authority_required'
            end
          )
        ),
        'place',case when v_commercial_eligible then jsonb_build_object(
          'disposition','stable','desiredCarrierState','open',
          'durabilityKey','flower-ready:'||v_farm.farm_id::text,
          'reasonCodes',jsonb_build_array('ready_inventory_is_stable_operating_orientation')
        ) else jsonb_build_object(
          'disposition','none','durabilityKey','flower-ready:'||v_farm.farm_id::text,
          'reasonCodes',jsonb_build_array('ready_inventory_exposure_basis_not_established')
        ) end,
        'index',jsonb_build_object(
          'disposition',case when v_commercial_eligible then 'listed' else 'absent' end,
          'reasonCodes',jsonb_build_array(
            case when v_commercial_eligible then 'domain_authorized_ready_inventory_orientation'
                 else 'ready_inventory_not_exposed' end
          )
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array('ready_page_existence_is_not_attention_authority'),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',case when v_commercial_eligible then jsonb_build_object(
          'sourceDomain','flower','sourceKind','ready_inventory_position_v1','sourceId',v_farm.farm_id,
          'relationshipKind','state','governedRead','atlas.flower_ready_inventory_notebook_self_api_v1',
          'metadata',jsonb_build_object(
            'supportingGovernedReads',jsonb_build_array('atlas.flower_route_availability_notebook_self_api_v1')
          )
        ) else null end,
        'stateQuality',jsonb_build_object(
          'resolution',case when v_unit_id is null and v_role in ('owner','manager') then 'unresolved' else 'established' end,
          'freshness','current','coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','farm_membership','id',v_farm.membership_id,'domain','flower'
          ))
        ),
        'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'owner or manager is a Flower-domain authority condition only',
          'Ready exposure does not grant inventory mutation authority',
          'route availability remains separate source evidence'
        )
      ),
      jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','flower.commercial_commitments_orientation.v1',
        'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
        'contextRef',v_context,
        'subjectRef',jsonb_build_object('kind','farm','id',v_farm.farm_id,'domain','flower'),
        'encounter',jsonb_build_object(
          'state',case when v_commercial_eligible then 'eligible' else
            case when v_unit_id is null and v_role in ('owner','manager') then 'unresolved' else 'ineligible' end end,
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','farm_membership','id',v_farm.membership_id,'domain','flower',
            'relation','active_membership','role',v_role
          )),
          'reasonCodes',jsonb_build_array(
            case
              when v_unit_id is null then 'canonical_organization_unit_required'
              when v_commercial_eligible then 'owner_or_manager_commercial_authority'
              else 'owner_or_manager_commercial_authority_required'
            end
          )
        ),
        'place',case when v_commercial_eligible then jsonb_build_object(
          'disposition','stable','desiredCarrierState','open',
          'durabilityKey','flower-orders:'||v_farm.farm_id::text,
          'reasonCodes',jsonb_build_array('commercial_commitments_are_stable_operating_orientation')
        ) else jsonb_build_object(
          'disposition','none','durabilityKey','flower-orders:'||v_farm.farm_id::text,
          'reasonCodes',jsonb_build_array('commercial_exposure_basis_not_established')
        ) end,
        'index',jsonb_build_object(
          'disposition',case when v_commercial_eligible then 'listed' else 'absent' end,
          'reasonCodes',jsonb_build_array(
            case when v_commercial_eligible then 'domain_authorized_commercial_orientation'
                 else 'commercial_not_exposed' end
          )
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array('commercial_page_existence_is_not_attention_authority'),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',case when v_commercial_eligible then jsonb_build_object(
          'sourceDomain','flower','sourceKind','commercial_commitments_v1','sourceId',v_farm.farm_id,
          'relationshipKind','state','governedRead','atlas.flower_commercial_commitments_notebook_self_api_v1'
        ) else null end,
        'stateQuality',jsonb_build_object(
          'resolution',case when v_unit_id is null and v_role in ('owner','manager') then 'unresolved' else 'established' end,
          'freshness','current','coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','farm_membership','id',v_farm.membership_id,'domain','flower'
          ))
        ),
        'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'commercial exposure does not imply sale, fulfillment, or money mutation authority',
          'farm commercial roles are not universal Atlas visibility roles'
        )
      )
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','flower_domain_exposure_self_v1',
    'state','ready',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'domainOwned',true,
      'farmAuthorityRemainsDomainLocal',true,
      'carrierTablesRead',false,
      'notebookMutationAuthorized',false,
      'actionAuthorityGranted',false
    )
  );
end;
$function$;

revoke all on function atlas.flower_domain_exposure_self_api_v1() from public, anon;
grant execute on function atlas.flower_domain_exposure_self_api_v1() to authenticated;

create or replace function atlas.correspondence_domain_exposure_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_position jsonb;
  v_person_id text;
  v_endpoint record;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_position := atlas.person_position_self_api_v1();
  if coalesce(v_position->>'state','') <> 'ready' then
    return jsonb_build_object(
      'contractVersion','correspondence_domain_exposure_self_v1',
      'state',coalesce(v_position->>'state','unresolved'),
      'items','[]'::jsonb
    );
  end if;

  v_person_id := coalesce(
    nullif(v_position->'person'->>'personId',''),
    nullif(v_position->>'personId','')
  );

  for v_endpoint in
    select ep.id as endpoint_id,
           ep.organization_id,
           ep.organization_unit_id,
           atlas.effective_communication_endpoint_organization_v1(ep.id) as effective_organization_id
    from atlas.communication_endpoints ep
    where ep.organization_id is not null
      and ep.principal_id is null
      and ep.endpoint_state='active'
      and atlas.communication_endpoint_authorized_self_v1(ep.id,'view')
    order by ep.created_at,ep.id
  loop
    if v_endpoint.effective_organization_id is null then
      continue;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'contractVersion','domain_exposure_evaluation_v1',
      'contractKey','communication.correspondence_endpoint_view.v1',
      'personRef',jsonb_build_object('kind','person','id',v_person_id,'domain','identity'),
      'contextRef',jsonb_build_object(
        'kind','organization','id',v_endpoint.effective_organization_id,'domain','organization',
        'organizationUnitId',v_endpoint.organization_unit_id
      ),
      'subjectRef',jsonb_build_object(
        'kind','communication_endpoint','id',v_endpoint.endpoint_id,'domain','communication'
      ),
      'encounter',jsonb_build_object(
        'state','eligible',
        'basisRefs',jsonb_build_array(jsonb_build_object(
          'kind','communication_endpoint','id',v_endpoint.endpoint_id,'domain','communication',
          'relation','view_capability'
        )),
        'reasonCodes',jsonb_build_array('active_endpoint_view_capability')
      ),
      'place',jsonb_build_object(
        'disposition','stable','desiredCarrierState','open',
        'durabilityKey','letters:'||v_endpoint.endpoint_id::text,
        'reasonCodes',jsonb_build_array('authorized_correspondence_endpoint_is_stable_orientation')
      ),
      'index',jsonb_build_object(
        'disposition','listed','reasonCodes',jsonb_build_array('endpoint_view_authority')
      ),
      'attentionNomination',jsonb_build_object(
        'disposition','quiet',
        'reasonCodes',jsonb_build_array('correspondence_place_existence_is_not_attention_authority'),
        'claimRefs','[]'::jsonb
      ),
      'sourceBinding',jsonb_build_object(
        'sourceDomain','communication','sourceKind','conversation_sequence_v1',
        'sourceId',v_endpoint.endpoint_id,
        'relationshipKind','sequence',
        'governedRead','atlas.organization_correspondence_list_self_api_v4',
        'metadata',jsonb_build_object('organizationId',v_endpoint.effective_organization_id)
      ),
      'stateQuality',jsonb_build_object(
        'resolution','established','freshness','current','coverage','partial',
        'provenanceRefs',jsonb_build_array(jsonb_build_object(
          'kind','communication_endpoint','id',v_endpoint.endpoint_id,'domain','communication'
        ))
      ),
      'disclosure',jsonb_build_object('shape','summary','sourceReasonDisclosure','not_applicable'),
      'operations','[]'::jsonb,
      'prohibitedInferences',jsonb_build_array(
        'Organization membership without endpoint view capability does not imply Correspondence exposure',
        'Correspondence exposure does not grant send, claim, handoff, close, or admin authority',
        'conversation read authority remains separate and source-owned',
        'Correspondence place existence does not nominate current attention'
      )
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','correspondence_domain_exposure_self_v1',
    'state','ready',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'domainOwned',true,
      'endpointCapabilityRequired',true,
      'conversationReadAuthoritySeparate',true,
      'carrierTablesRead',false,
      'notebookMutationAuthorized',false,
      'actionAuthorityGranted',false
    )
  );
end;
$function$;

revoke all on function atlas.correspondence_domain_exposure_self_api_v1() from public, anon;
grant execute on function atlas.correspondence_domain_exposure_self_api_v1() to authenticated;

create or replace function atlas.domain_exposure_evaluations_self_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_base jsonb;
  v_household jsonb;
  v_flower jsonb;
  v_correspondence jsonb;
  v_items jsonb := '[]'::jsonb;
  v_boundary jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null then
    return jsonb_build_object(
      'contractVersion','domain_exposure_evaluations_self_v2',
      'state','domain_exposure_v1_dependency_unavailable',
      'items','[]'::jsonb
    );
  end if;

  v_base := atlas.domain_exposure_evaluations_self_api_v1();

  if coalesce(v_base->>'state','') <> 'ready' then
    return (v_base - 'contractVersion') || jsonb_build_object(
      'contractVersion','domain_exposure_evaluations_self_v2',
      'items',coalesce(v_base->'items','[]'::jsonb),
      'componentStates',jsonb_build_object('v1',v_base->>'state')
    );
  end if;

  v_household := atlas.household_domain_exposure_self_api_v1();
  v_flower := atlas.flower_domain_exposure_self_api_v1();
  v_correspondence := atlas.correspondence_domain_exposure_self_api_v1();

  v_items := coalesce(v_base->'items','[]'::jsonb)
    || coalesce(v_household->'items','[]'::jsonb)
    || coalesce(v_flower->'items','[]'::jsonb)
    || coalesce(v_correspondence->'items','[]'::jsonb);

  v_boundary := coalesce(v_base->'truthBoundary','{}'::jsonb) || jsonb_build_object(
    'tableBlindSharedComposer',true,
    'domainOwnedExposureMembranesConsumed',true,
    'carrierExistenceIsNotKnowledgeAuthority',true,
    'notebookMutationAuthorized',false,
    'indexMutationAuthorized',false,
    'todayPlacementAuthorized',false,
    'actionAuthorityGranted',false,
    'executionAuthorityGranted',false
  );

  return (v_base - 'contractVersion' - 'items' - 'truthBoundary') || jsonb_build_object(
    'contractVersion','domain_exposure_evaluations_self_v2',
    'state','ready',
    'items',v_items,
    'componentStates',jsonb_build_object(
      'v1',v_base->>'state',
      'household',v_household->>'state',
      'flower',v_flower->>'state',
      'correspondence',v_correspondence->>'state'
    ),
    'truthBoundary',v_boundary
  );
end;
$function$;

comment on function atlas.domain_exposure_evaluations_self_api_v2() is
  'Table-blind shared Domain Exposure composer v2. Extends the v1 evaluator with Household, Flower and Correspondence domain-owned exposure membranes without using notebook carrier existence as knowledge authority.';

revoke all on function atlas.domain_exposure_evaluations_self_api_v2() from public, anon;
grant execute on function atlas.domain_exposure_evaluations_self_api_v2() to authenticated;



create or replace function atlas.notebook_index_admitted_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_exposure jsonb;
  v_spreads jsonb;
  v_items jsonb := '[]'::jsonb;
  v_spread jsonb;
  v_eval jsonb;
  v_key text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v2()') is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_index_admitted_self_v1',
      'state','domain_exposure_dependency_unavailable',
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'carrierExistenceDoesNotGrantEncounter',true,
        'indexDoesNotGrantSourceAuthority',true,
        'hiddenCarrierEnumerationSuppressed',true,
        'notebookMutationAuthorized',false
      )
    );
  end if;

  execute 'select atlas.domain_exposure_evaluations_self_api_v2()'
    into v_exposure;

  if coalesce(v_exposure->>'state','') <> 'ready' then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_index_admitted_self_v1',
      'state',coalesce(v_exposure->>'state','unresolved'),
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'carrierExistenceDoesNotGrantEncounter',true,
        'indexDoesNotGrantSourceAuthority',true,
        'hiddenCarrierEnumerationSuppressed',true,
        'notebookMutationAuthorized',false
      )
    );
  end if;

  v_spreads := atlas.notebook_spread_instances_self_api_v1();

  v_items := jsonb_build_array(
    jsonb_build_object(
      'addressKind','today',
      'spreadKey','today',
      'templateKey','today',
      'title','Today',
      'section','Notebook'
    ),
    jsonb_build_object(
      'addressKind','index',
      'spreadKey','index',
      'templateKey','index',
      'title','Index',
      'section','Notebook'
    )
  );

  for v_spread in
    select value
    from jsonb_array_elements(coalesce(v_spreads->'items','[]'::jsonb))
  loop
    v_key := nullif(v_spread->>'spreadKey','');
    if v_key is null then
      continue;
    end if;

    select value
      into v_eval
    from jsonb_array_elements(coalesce(v_exposure->'items','[]'::jsonb))
    where value->'place'->>'durabilityKey'=v_key
    limit 1;

    if v_eval is null then
      continue;
    end if;

    if v_eval->'encounter'->>'state' <> 'eligible'
       or v_eval->'place'->>'disposition' not in ('stable','transient')
       or v_eval->'index'->>'disposition' <> 'listed'
       or jsonb_typeof(v_eval->'sourceBinding') <> 'object'
       or nullif(v_eval->'sourceBinding'->>'governedRead','') is null then
      continue;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'addressKind','spread',
      'spreadKey',v_key,
      'templateKey','composed',
      'title',v_spread->>'title',
      'section',v_spread->>'sectionKey',
      'scope',v_spread->'scope',
      'subject',v_spread->'subject',
      'spreadInstanceId',v_spread->>'spreadInstanceId',
      'spreadState',v_spread->>'spreadState',
      'threadKey',v_spread->>'threadKey',
      'recipeKey',v_spread->>'recipeKey',
      'purposeKey',v_spread->>'purposeKey',
      'horizonKey',v_spread->>'horizonKey',
      'exposureContractKey',v_eval->>'contractKey'
    ));
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_index_admitted_self_v1',
    'state','ready',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'indexIsRetrievalProjection',true,
      'carrierExistenceDoesNotGrantEncounter',true,
      'indexDispositionComesFromDomainExposure',true,
      'quietIsNotAdvertised',true,
      'absentAndUnresolvedAreNotEnumerated',true,
      'indexDoesNotGrantSourceAuthority',true,
      'hiddenCarrierEnumerationSuppressed',true,
      'notebookMutationAuthorized',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false
    )
  );
end;
$function$;

comment on function atlas.notebook_index_admitted_self_api_v1() is
  'Person-relative notebook Index read governed by Domain Exposure v2. Returns only system addresses plus listed durable places; quiet/absent/unresolved carriers are not enumerated and source authority remains separate.';

revoke all on function atlas.notebook_index_admitted_self_api_v1()
  from public, anon;
grant execute on function atlas.notebook_index_admitted_self_api_v1()
  to authenticated;

create or replace function atlas.notebook_address_admitted_self_api_v1(
  p_spread_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_key text := nullif(btrim(p_spread_key),'');
  v_exposure jsonb;
  v_eval jsonb;
  v_raw jsonb;
  v_index_disposition text;
  v_source_read text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if v_key is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  if v_key in ('today','index') then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_address_admitted_self_v1',
      'state','system',
      'spreadKey',v_key,
      'indexDisposition','listed',
      'spread',null,
      'sourceRead',null,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'systemAddress',true,
        'addressAdmissionDoesNotGrantSourceAuthority',true,
        'notebookMutationAuthorized',false
      )
    );
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v2()') is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  execute 'select atlas.domain_exposure_evaluations_self_api_v2()'
    into v_exposure;

  if coalesce(v_exposure->>'state','') <> 'ready' then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  select value
    into v_eval
  from jsonb_array_elements(coalesce(v_exposure->'items','[]'::jsonb))
  where value->'place'->>'durabilityKey'=v_key
  limit 1;

  if v_eval is null
     or v_eval->'encounter'->>'state' <> 'eligible'
     or v_eval->'place'->>'disposition' not in ('stable','transient')
     or v_eval->'index'->>'disposition' not in ('listed','quiet')
     or jsonb_typeof(v_eval->'sourceBinding') <> 'object'
     or nullif(v_eval->'sourceBinding'->>'governedRead','') is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  v_index_disposition := v_eval->'index'->>'disposition';
  v_source_read := v_eval->'sourceBinding'->>'governedRead';

  begin
    v_raw := atlas.notebook_spread_instance_self_api_v1(v_key);
  exception
    when no_data_found then
      raise exception 'Notebook address not found.' using errcode='P0002';
  end;

  if v_raw is null or v_raw->'spread' is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_address_admitted_self_v1',
    'state',case when v_index_disposition='quiet' then 'quiet' else 'listed' end,
    'spreadKey',v_key,
    'indexDisposition',v_index_disposition,
    'spread',v_raw->'spread',
    'sourceBindings',v_raw->'sourceBindings',
    'latestCompositionRevision',v_raw->'latestCompositionRevision',
    'sourceRead',v_source_read,
    'exposureContractKey',v_eval->>'contractKey',
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'carrierExistenceDoesNotGrantEncounter',true,
      'listedAndQuietMayResolveDirectly',true,
      'quietDoesNotAuthorizeIndexAdvertisement',true,
      'absentAndUnresolvedAreIndistinguishableFromNotFound',true,
      'addressAdmissionDoesNotGrantSourceAuthority',true,
      'sourceReadMustAuthorizeSeparately',true,
      'rawSpreadReaderIsTransitionalDependency',true,
      'notebookMutationAuthorized',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false
    )
  );
end;
$function$;

comment on function atlas.notebook_address_admitted_self_api_v1(text) is
  'Person-relative durable NotebookAddress resolver governed by Domain Exposure v2. Listed and quiet addresses may resolve; absent/unresolved/unmapped carriers fail closed as not-found. Source read authority remains separate.';

revoke all on function atlas.notebook_address_admitted_self_api_v1(text)
  from public, anon;
grant execute on function atlas.notebook_address_admitted_self_api_v1(text)
  to authenticated;


commit;
