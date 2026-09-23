-- Atlas Notebook Exposure Reconciliation v1
-- Write-side membrane from production-live Domain Exposure into notebook-owned
-- carrier/source-binding lifecycle. It creates no source-domain truth and does
-- not grant source-read, Today, action, or execution authority.

create or replace function atlas.notebook_exposure_carrier_spec_self_v1(
  p_exposure jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_contract_key text := nullif(p_exposure->>'contractKey','');
  v_life jsonb;
  v_definition jsonb;
  v_definition_id text;
  v_signal_kind text;
  v_recipe_key text;
  v_relationship_kind text;
  v_title text;
  v_contract jsonb;
  v_principal_id text;
  v_org_id text;
  v_position jsonb;
  v_membership jsonb;
  v_org_name text;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if coalesce(p_exposure->'encounter'->>'state','') <> 'eligible'
     or coalesce(p_exposure->'place'->>'disposition','none') not in ('stable','transient') then
    return null;
  end if;

  if v_contract_key='person.life_definition.v1' then
    v_definition_id := nullif(p_exposure->'subjectRef'->>'id','');
    if v_definition_id is null then
      raise exception 'Eligible Person Life exposure omitted definition identity.' using errcode='23514';
    end if;

    v_life := atlas.person_life_state_api_v1();

    select value
      into v_definition
    from jsonb_array_elements(coalesce(v_life->'definitions','[]'::jsonb))
    where value->>'definitionId'=v_definition_id
    limit 1;

    if v_definition is null then
      raise exception 'Eligible Person Life exposure is not present in governed Person Life read.'
        using errcode='23514';
    end if;

    v_signal_kind := coalesce(nullif(v_definition->>'signalKind',''),'state');
    v_recipe_key := case v_signal_kind
      when 'goal' then 'life-progress'
      when 'rhythm' then 'life-occurrence'
      else 'life-log'
    end;
    v_relationship_kind := case v_signal_kind
      when 'goal' then 'progress'
      when 'rhythm' then 'cadence'
      else 'state'
    end;
    v_title := coalesce(
      nullif(v_definition->'lifeSignal'->>'title',''),
      nullif(v_definition->'lifeSignal'->>'label',''),
      initcap(replace(v_signal_kind,'_',' '))
    );

    v_contract := case v_recipe_key
      when 'life-progress' then jsonb_build_object(
        'contractVersion','notebook_spread_composition_v1',
        'patternKey','dominant-supporting-pair',
        'forms',jsonb_build_array(
          jsonb_build_object(
            'formFamily','free-field','role','anchor','order',1,
            'supportedRelationships',jsonb_build_array('progress'),
            'emptyBehavior','show-quiet-geometry',
            'phoneRule','Keep the explicit Goal orientation, status, and latest evidence together.'
          ),
          jsonb_build_object(
            'formFamily','path','role','supporting','order',2,
            'supportedRelationships',jsonb_build_array('progress'),
            'emptyBehavior','show-established-future-space',
            'phoneRule','Preserve explicit requirements or milestones in source order; never invent a plan.'
          ),
          jsonb_build_object(
            'formFamily','ledger','role','supporting','order',3,
            'supportedRelationships',jsonb_build_array('progress'),
            'emptyBehavior','omit',
            'phoneRule','Show only established open consequences beneath Goal reality.'
          )
        ),
        'surfaceBudget',jsonb_build_object(
          'anchorCount',1,'supportingCount',2,'marginCount',0,'latentIsDefault',true
        ),
        'phoneLinearization',jsonb_build_array('free-field','path','ledger'),
        'stability',jsonb_build_object(
          'meaningPositionsAreStable',true,'historyPreservedByRevision',true
        ),
        'sourceBindingPolicy',jsonb_build_object(
          'sourceTruthExternal',true,
          'missingSourceDoesNotCreateEmptyIntegrationTile',true
        ),
        'compilerBasis',jsonb_build_object(
          'contract','person.life_definition.v1',
          'recipe','progress',
          'owner','domain_exposure_reconciliation'
        )
      )
      when 'life-occurrence' then jsonb_build_object(
        'contractVersion','notebook_spread_composition_v1',
        'patternKey','dominant-supporting-pair',
        'forms',jsonb_build_array(
          jsonb_build_object(
            'formFamily','free-field','role','anchor','order',1,
            'supportedRelationships',jsonb_build_array('cadence'),
            'emptyBehavior','show-quiet-geometry',
            'phoneRule','Keep the explicit Rhythm orientation and supported cadence visible first.'
          ),
          jsonb_build_object(
            'formFamily','timeline','role','supporting','order',2,
            'supportedRelationships',jsonb_build_array('cadence'),
            'emptyBehavior','show-established-future-space',
            'phoneRule','Keep recorded occurrence/state evidence chronological; do not infer missing occurrences.'
          ),
          jsonb_build_object(
            'formFamily','ledger','role','supporting','order',3,
            'supportedRelationships',jsonb_build_array('cadence'),
            'emptyBehavior','omit',
            'phoneRule','Show only established open consequences beneath Rhythm reality.'
          )
        ),
        'surfaceBudget',jsonb_build_object(
          'anchorCount',1,'supportingCount',2,'marginCount',0,'latentIsDefault',true
        ),
        'phoneLinearization',jsonb_build_array('free-field','timeline','ledger'),
        'stability',jsonb_build_object(
          'meaningPositionsAreStable',true,'historyPreservedByRevision',true
        ),
        'sourceBindingPolicy',jsonb_build_object(
          'sourceTruthExternal',true,
          'missingSourceDoesNotCreateEmptyIntegrationTile',true
        ),
        'compilerBasis',jsonb_build_object(
          'contract','person.life_definition.v1',
          'recipe','occurrence',
          'owner','domain_exposure_reconciliation'
        )
      )
      else jsonb_build_object(
        'contractVersion','notebook_spread_composition_v1',
        'patternKey','dominant-supporting-pair',
        'forms',jsonb_build_array(
          jsonb_build_object(
            'formFamily','free-field','role','anchor','order',1,
            'supportedRelationships',jsonb_build_array('state'),
            'emptyBehavior','show-quiet-geometry',
            'phoneRule','Keep the explicit Life signal orientation visible first.'
          ),
          jsonb_build_object(
            'formFamily','log','role','supporting','order',2,
            'supportedRelationships',jsonb_build_array('state'),
            'emptyBehavior','show-established-future-space',
            'phoneRule','Preserve recorded state evidence chronologically without inventing interpretation.'
          ),
          jsonb_build_object(
            'formFamily','ledger','role','supporting','order',3,
            'supportedRelationships',jsonb_build_array('state'),
            'emptyBehavior','omit',
            'phoneRule','Show only established consequence instances; carrier and Clock authority stay separate.'
          )
        ),
        'surfaceBudget',jsonb_build_object(
          'anchorCount',1,'supportingCount',2,'marginCount',0,'latentIsDefault',true
        ),
        'phoneLinearization',jsonb_build_array('free-field','log','ledger'),
        'stability',jsonb_build_object(
          'meaningPositionsAreStable',true,'historyPreservedByRevision',true
        ),
        'sourceBindingPolicy',jsonb_build_object(
          'sourceTruthExternal',true,
          'missingSourceDoesNotCreateEmptyIntegrationTile',true
        ),
        'compilerBasis',jsonb_build_object(
          'contract','person.life_definition.v1',
          'recipe','life-log',
          'owner','domain_exposure_reconciliation'
        )
      )
    end;

    return jsonb_build_object(
      'spreadKey','life:'||v_definition_id,
      'scope',jsonb_build_object(
        'kind','person',
        'id',v_life->'scope'->>'id'
      ),
      'subject',jsonb_build_object(
        'domain','person',
        'kind','person_life_definition',
        'id',v_definition_id
      ),
      'purposeKey','life-orientation',
      'horizonKey','current',
      'threadKey','thread:life:'||v_definition_id,
      'title',v_title,
      'sectionKey','Life',
      'recipeKey',v_recipe_key,
      'creationMode','resolved',
      'compositionContract',v_contract,
      'basis',jsonb_build_object(
        'kind','domain_exposure_reconciliation',
        'contractKey',v_contract_key,
        'definitionId',v_definition_id,
        'signalKind',v_signal_kind
      ),
      'metadata',jsonb_build_object(
        'source','person_life_definition',
        'signalKind',v_signal_kind
      ),
      'bindingBasis',jsonb_build_object(
        'kind','domain_exposure_reconciliation',
        'contractKey',v_contract_key,
        'governedRead',p_exposure->'sourceBinding'->>'governedRead',
        'definitionId',v_definition_id,
        'signalKind',v_signal_kind,
        'recipeKey',v_recipe_key
      ),
      'bindingMetadata','{}'::jsonb,
      'expectedRelationshipKind',v_relationship_kind
    );
  end if;

  if v_contract_key='principal.connections_orientation.v1' then
    v_principal_id := coalesce(
      nullif(p_exposure->'sourceBinding'->>'sourceId',''),
      nullif(p_exposure->'subjectRef'->>'id','')
    );
    if v_principal_id is null then
      raise exception 'Eligible Connections exposure omitted Principal identity.' using errcode='23514';
    end if;

    v_contract := jsonb_build_object(
      'contractVersion','notebook_spread_composition_v1',
      'patternKey','single-form-continuation',
      'forms',jsonb_build_array(jsonb_build_object(
        'formFamily','ledger','role','anchor','order',1,
        'supportedRelationships',jsonb_build_array('evidence','state'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Keep outlet identity and source authorization state visible; collapse provider detail before hiding state.'
      )),
      'surfaceBudget',jsonb_build_object(
        'anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true
      ),
      'phoneLinearization',jsonb_build_array('ledger'),
      'stability',jsonb_build_object(
        'meaningPositionsAreStable',true,
        'recomposeOnlyForMeaningfulPhaseChange',true,
        'historyPreservedByRevision',true
      ),
      'sourceBindingPolicy',jsonb_build_object(
        'sourceTruthExternal',true,
        'missingSourceDoesNotCreateSourceTruth',true,
        'connectionStateDoesNotGrantAuthority',true,
        'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
      ),
      'compilerBasis',jsonb_build_object(
        'systemSpread','connections',
        'owner','domain_exposure_reconciliation'
      )
    );

    return jsonb_build_object(
      'spreadKey','connections',
      'scope',jsonb_build_object('kind','person','id',v_principal_id),
      'subject',jsonb_build_object(
        'domain','principal','kind','connections','id',v_principal_id
      ),
      'purposeKey','source-coverage-orientation',
      'horizonKey','current',
      'threadKey','connections',
      'title','Connections',
      'sectionKey','Connections',
      'recipeKey',null,
      'creationMode','resolved',
      'compositionContract',v_contract,
      'basis',jsonb_build_object(
        'kind','domain_exposure_reconciliation',
        'contractKey',v_contract_key
      ),
      'metadata',jsonb_build_object(
        'permanent',true,
        'truthOwner',false
      ),
      'bindingBasis',jsonb_build_object(
        'kind','domain_exposure_reconciliation',
        'contractKey',v_contract_key,
        'governedRead',p_exposure->'sourceBinding'->>'governedRead'
      ),
      'bindingMetadata',jsonb_build_object(
        'projection','connections-ledger-v1'
      )
    );
  end if;

  if v_contract_key='organization.ledger_owner_compatibility.v1' then
    v_org_id := nullif(p_exposure->'contextRef'->>'id','');
    if v_org_id is null then
      raise exception 'Eligible Ledger exposure omitted Organization identity.' using errcode='23514';
    end if;

    v_position := atlas.person_position_self_api_v1();
    select value
      into v_membership
    from jsonb_array_elements(coalesce(v_position->'institutionalMemberships','[]'::jsonb))
    where value->>'organizationId'=v_org_id
    limit 1;

    v_org_name := coalesce(
      nullif(v_membership->>'organizationName',''),
      'Organization Ledger'
    );

    v_contract := jsonb_build_object(
      'contractVersion','notebook_spread_composition_v1',
      'patternKey','single-form-continuation',
      'forms',jsonb_build_array(jsonb_build_object(
        'formFamily','log',
        'role','anchor',
        'order',1,
        'supportedRelationships',jsonb_build_array('evidence','state'),
        'emptyBehavior','show-established-future-space',
        'phoneRule','Preserve Ledger occurrence order and exact entry identity.'
      )),
      'surfaceBudget',jsonb_build_object(
        'anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true
      ),
      'phoneLinearization',jsonb_build_array('log'),
      'stability',jsonb_build_object(
        'meaningPositionsAreStable',true,
        'recomposeOnlyForMeaningfulPhaseChange',true,
        'historyPreservedByRevision',true
      ),
      'sourceBindingPolicy',jsonb_build_object(
        'sourceTruthExternal',true,
        'missingSourceDoesNotCreateEmptyIntegrationTile',true,
        'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true
      ),
      'compilerBasis',jsonb_build_object(
        'page','organization-ledger',
        'owner','domain_exposure_reconciliation'
      )
    );

    return jsonb_build_object(
      'spreadKey','ledger:'||v_org_id,
      'scope',jsonb_build_object('kind','organization','id',v_org_id),
      'subject',jsonb_build_object(
        'domain','organization',
        'kind','organization_ledger',
        'id',v_org_id
      ),
      'purposeKey','recent-ledger-orientation',
      'horizonKey','rolling-30-days',
      'threadKey','thread:organization-ledger:'||v_org_id,
      'title',v_org_name,
      'sectionKey','Organizations',
      'recipeKey',null,
      'creationMode','resolved',
      'compositionContract',v_contract,
      'basis',jsonb_build_object(
        'kind','domain_exposure_reconciliation',
        'contractKey',v_contract_key,
        'organizationId',v_org_id,
        'governedRead',p_exposure->'sourceBinding'->>'governedRead'
      ),
      'metadata',jsonb_strip_nulls(jsonb_build_object(
        'organizationId',v_org_id,
        'ledgerId',p_exposure->'sourceBinding'->'metadata'->>'ledgerId',
        'admission','domain_exposure'
      )),
      'bindingBasis',jsonb_build_object(
        'kind','domain_exposure_reconciliation',
        'contractKey',v_contract_key,
        'governedRead',p_exposure->'sourceBinding'->>'governedRead'
      ),
      'bindingMetadata',coalesce(p_exposure->'sourceBinding'->'metadata','{}'::jsonb)
    );
  end if;

  return null;
end;
$function$;

revoke all on function atlas.notebook_exposure_carrier_spec_self_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.notebook_exposure_carrier_spec_self_v1(jsonb)
  to service_role;


create or replace function atlas.notebook_exposure_reconciliation_plan_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_exposures jsonb;
  v_state text;
  v_principal_id uuid;
  v_item jsonb;
  v_contract_key text;
  v_encounter text;
  v_place text;
  v_desired_state text;
  v_index_disposition text;
  v_key text;
  v_spec jsonb;
  v_binding jsonb;
  v_existing atlas.notebook_spread_instances%rowtype;
  v_identity_match boolean;
  v_carrier_projection_match boolean;
  v_binding_match boolean;
  v_binding_payload_match boolean;
  v_active_binding_count integer;
  v_action text;
  v_binding_directive text;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_exposures := atlas.domain_exposure_evaluations_self_api_v1();
  v_state := coalesce(v_exposures->>'state','unknown');

  if v_state <> 'ready' then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_exposure_reconciliation_plan_self_v1',
      'state',v_state,
      'personPosition',v_exposures->'personPosition',
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'exposureIsAdmissionAuthority',true,
        'carrierExistenceIsNotExposureAuthority',true,
        'mutationAuthorized',false
      )
    );
  end if;

  v_principal_id := nullif(v_exposures->'personPosition'->>'principalId','')::uuid;
  if v_principal_id is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_exposure_reconciliation_plan_self_v1',
      'state','principal_required',
      'personPosition',v_exposures->'personPosition',
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'mutationAuthorized',false
      )
    );
  end if;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(v_exposures->'items','[]'::jsonb))
  loop
    v_contract_key := nullif(v_item->>'contractKey','');
    v_encounter := coalesce(v_item->'encounter'->>'state','unresolved');
    v_place := coalesce(v_item->'place'->>'disposition','none');
    v_desired_state := nullif(v_item->'place'->>'desiredCarrierState','');
    v_index_disposition := coalesce(v_item->'index'->>'disposition','unresolved');
    v_binding := v_item->'sourceBinding';

    v_key := nullif(v_item->'place'->>'durabilityKey','');
    if v_key is null
       and v_contract_key='organization.ledger_owner_compatibility.v1'
       and nullif(v_item->'contextRef'->>'id','') is not null then
      v_key := 'ledger:'||(v_item->'contextRef'->>'id');
    end if;

    v_spec := case
      when v_encounter='eligible' and v_place in ('stable','transient')
        then atlas.notebook_exposure_carrier_spec_self_v1(v_item)
      else null
    end;

    v_existing := null;
    if v_key is not null then
      select *
        into v_existing
      from atlas.notebook_spread_instances s
      where s.principal_id=v_principal_id
        and s.spread_key=v_key
      limit 1;
    end if;

    v_identity_match := true;
    if v_existing.id is not null and v_spec is not null then
      v_identity_match :=
        v_existing.spread_key = v_spec->>'spreadKey'
        and v_existing.scope_kind = v_spec->'scope'->>'kind'
        and v_existing.scope_id = v_spec->'scope'->>'id'
        and v_existing.subject_domain = v_spec->'subject'->>'domain'
        and v_existing.subject_kind = v_spec->'subject'->>'kind'
        and v_existing.subject_id = v_spec->'subject'->>'id'
        and v_existing.purpose_key = v_spec->>'purposeKey'
        and v_existing.horizon_key = v_spec->>'horizonKey'
        and v_existing.thread_key = v_spec->>'threadKey';
    end if;

    v_carrier_projection_match := false;
    if v_existing.id is not null and v_spec is not null then
      v_carrier_projection_match :=
        v_existing.title = v_spec->>'title'
        and v_existing.section_key = v_spec->>'sectionKey'
        and v_existing.recipe_key is not distinct from nullif(v_spec->>'recipeKey','')
        and v_existing.composition_contract = coalesce(v_spec->'compositionContract','{}'::jsonb)
        and v_existing.basis = coalesce(v_spec->'basis','{}'::jsonb)
        and v_existing.metadata = coalesce(v_spec->'metadata','{}'::jsonb);
    end if;

    v_binding_match := false;
    v_binding_payload_match := false;
    v_active_binding_count := 0;
    if v_existing.id is not null then
      select count(*)::integer
        into v_active_binding_count
      from atlas.notebook_spread_source_bindings b
      where b.spread_instance_id=v_existing.id
        and b.binding_state='active'
        and b.retired_at is null;

      if v_binding is not null then
        select exists (
          select 1
          from atlas.notebook_spread_source_bindings b
          where b.spread_instance_id=v_existing.id
            and b.binding_state='active'
            and b.retired_at is null
            and b.source_domain=v_binding->>'sourceDomain'
            and b.source_kind=v_binding->>'sourceKind'
            and b.source_id=v_binding->>'sourceId'
            and b.relationship_kind=v_binding->>'relationshipKind'
        ) into v_binding_match;

        select exists (
          select 1
          from atlas.notebook_spread_source_bindings b
          where b.spread_instance_id=v_existing.id
            and b.binding_state='active'
            and b.retired_at is null
            and b.source_domain=v_binding->>'sourceDomain'
            and b.source_kind=v_binding->>'sourceKind'
            and b.source_id=v_binding->>'sourceId'
            and b.relationship_kind=v_binding->>'relationshipKind'
            and b.basis = coalesce(v_spec->'bindingBasis','{}'::jsonb)
            and b.metadata = coalesce(
              v_spec->'bindingMetadata',
              coalesce(v_binding->'metadata','{}'::jsonb)
            )
        ) into v_binding_payload_match;
      end if;
    end if;

    if v_encounter='eligible' and v_place in ('stable','transient') then
      v_binding_directive := case
        when v_binding is not null then 'ensure_active'
        else 'preserve'
      end;

      if v_key is null or v_spec is null or v_desired_state not in ('open','closed') then
        v_action := 'invalid';
      elsif v_existing.id is null then
        v_action := 'ensure_place';
      elsif not v_identity_match then
        v_action := 'invalid_collision';
      elsif v_desired_state='open' and v_existing.spread_state='closed' then
        v_action := 'reopen_place';
      elsif v_desired_state='closed' and v_existing.spread_state='open' then
        v_action := 'close_place';
      elsif not v_carrier_projection_match then
        v_action := 'refresh_carrier';
      elsif v_binding is not null and (not v_binding_match or not v_binding_payload_match) then
        v_action := 'replace_binding';
      else
        v_action := 'no_op';
      end if;
    else
      v_binding_directive := 'retire';
      if v_key is null or v_existing.id is null then
        v_action := 'no_op';
      elsif v_existing.spread_state='open' then
        v_action := 'close_place';
      elsif v_active_binding_count>0 then
        v_action := 'retain_closed_history';
      else
        v_action := 'no_op';
      end if;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','notebook_exposure_reconciliation_item_v1',
      'contractKey',v_contract_key,
      'durabilityKey',v_key,
      'encounterState',v_encounter,
      'placeDisposition',v_place,
      'desiredCarrierState',v_desired_state,
      'indexDirective',v_index_disposition,
      'action',v_action,
      'bindingDirective',v_binding_directive,
      'spreadInstanceId',v_existing.id,
      'existingSpreadState',case when v_existing.id is null then null else v_existing.spread_state end,
      'carrierSpec',v_spec,
      'sourceBinding',v_binding,
      'stateQuality',v_item->'stateQuality',
      'reasonCodes',coalesce(v_item->'encounter'->'reasonCodes','[]'::jsonb)
    )));
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_exposure_reconciliation_plan_self_v1',
    'state','ready',
    'personPosition',v_exposures->'personPosition',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'domainExposureConsumed',true,
      'exposureIsAdmissionAuthority',true,
      'carrierExistenceIsNotExposureAuthority',true,
      'carrierSpecOwnsNoSourceTruth',true,
      'mutationAuthorized',false,
      'sourceReadAuthorityGranted',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false,
      'executionAuthorityGranted',false
    )
  );
end;
$function$;

revoke all on function atlas.notebook_exposure_reconciliation_plan_self_api_v1()
  from public,anon;
grant execute on function atlas.notebook_exposure_reconciliation_plan_self_api_v1()
  to authenticated,service_role;


create or replace function atlas.reconcile_notebook_exposure_self_api_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_plan jsonb;
  v_state text;
  v_principal_id uuid;
  v_item jsonb;
  v_action text;
  v_binding_directive text;
  v_key text;
  v_spec jsonb;
  v_binding jsonb;
  v_existing atlas.notebook_spread_instances%rowtype;
  v_spread_id uuid;
  v_changed boolean;
  v_results jsonb := '[]'::jsonb;
  v_total_changed integer := 0;
  v_rows integer;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_plan := atlas.notebook_exposure_reconciliation_plan_self_api_v1();
  v_state := coalesce(v_plan->>'state','unknown');

  if v_state <> 'ready' then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','reconcile_notebook_exposure_self_v1',
      'state',v_state,
      'changedCount',0,
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'domainTruthCreated',false,
        'sourceReadAuthorityGranted',false,
        'todayPlacementAuthorized',false,
        'actionAuthorityGranted',false,
        'executionAuthorityGranted',false
      )
    );
  end if;

  v_principal_id := nullif(v_plan->'personPosition'->>'principalId','')::uuid;
  if v_principal_id is null then
    raise exception 'Ready reconciliation plan omitted Principal identity.' using errcode='23514';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(v_plan->'items','[]'::jsonb))
  loop
    v_action := coalesce(v_item->>'action','invalid');
    v_binding_directive := coalesce(v_item->>'bindingDirective','preserve');
    v_key := nullif(v_item->>'durabilityKey','');
    v_spec := v_item->'carrierSpec';
    v_binding := v_item->'sourceBinding';
    v_changed := false;
    v_spread_id := null;

    if v_action in ('invalid','invalid_collision') then
      raise exception 'Notebook Exposure reconciliation refused % for contract % / durability key %.',
        v_action,
        coalesce(v_item->>'contractKey','unknown'),
        coalesce(v_key,'(none)')
        using errcode='23505';
    end if;

    v_existing := null;
    if v_key is not null then
      select *
        into v_existing
      from atlas.notebook_spread_instances s
      where s.principal_id=v_principal_id
        and s.spread_key=v_key
      for update;
    end if;

    if v_binding_directive='retire' then
      if v_existing.id is not null then
        v_spread_id := v_existing.id;

        if v_existing.spread_state <> 'closed' then
          update atlas.notebook_spread_instances
          set spread_state='closed',
              closed_at=coalesce(closed_at,now()),
              updated_at=now()
          where id=v_existing.id;
          v_changed := true;
        end if;

        update atlas.notebook_spread_source_bindings
        set binding_state='retired',
            retired_at=coalesce(retired_at,now()),
            updated_at=now()
        where spread_instance_id=v_existing.id
          and binding_state='active'
          and retired_at is null;
        get diagnostics v_rows = row_count;
        if v_rows>0 then v_changed := true; end if;
      end if;
    else
      if v_action <> 'no_op' then
        if v_spec is null or v_key is null then
          raise exception 'Eligible notebook reconciliation omitted carrier specification.'
            using errcode='23514';
        end if;

        v_spread_id := atlas.set_notebook_spread_instance_v2(
          v_principal_id,
          v_spec->>'spreadKey',
          v_spec->'scope'->>'kind',
          v_spec->'scope'->>'id',
          v_spec->'subject'->>'domain',
          v_spec->'subject'->>'kind',
          v_spec->'subject'->>'id',
          v_spec->>'purposeKey',
          v_spec->>'horizonKey',
          v_spec->>'threadKey',
          v_spec->>'title',
          v_spec->>'sectionKey',
          v_spec->>'recipeKey',
          coalesce(nullif(v_spec->>'creationMode',''),'resolved'),
          v_item->>'desiredCarrierState',
          coalesce(v_spec->'compositionContract','{}'::jsonb),
          coalesce(v_spec->'basis','{}'::jsonb),
          coalesce(v_spec->'metadata','{}'::jsonb)
        );
        v_changed := true;
      else
        v_spread_id := v_existing.id;
      end if;

      if v_binding_directive='ensure_active' and v_action <> 'no_op' then
        if v_binding is null or v_spread_id is null then
          raise exception 'Eligible notebook reconciliation omitted source binding.'
            using errcode='23514';
        end if;

        update atlas.notebook_spread_source_bindings
        set binding_state='retired',
            retired_at=coalesce(retired_at,now()),
            updated_at=now()
        where spread_instance_id=v_spread_id
          and binding_state='active'
          and retired_at is null
          and source_domain=v_binding->>'sourceDomain'
          and source_id=v_binding->>'sourceId'
          and (
            source_kind <> v_binding->>'sourceKind'
            or relationship_kind <> v_binding->>'relationshipKind'
          );

        perform atlas.bind_notebook_spread_source_v1(
          v_spread_id,
          v_binding->>'sourceDomain',
          v_binding->>'sourceKind',
          v_binding->>'sourceId',
          v_binding->>'relationshipKind',
          'active',
          coalesce(v_spec->'bindingBasis','{}'::jsonb),
          coalesce(v_spec->'bindingMetadata',coalesce(v_binding->'metadata','{}'::jsonb))
        );
      end if;
    end if;

    if v_changed then
      v_total_changed := v_total_changed + 1;
    end if;

    v_results := v_results || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'contractKey',v_item->>'contractKey',
      'durabilityKey',v_key,
      'action',v_action,
      'bindingDirective',v_binding_directive,
      'spreadInstanceId',coalesce(v_spread_id,v_existing.id),
      'changed',v_changed
    )));
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reconcile_notebook_exposure_self_v1',
    'state','ready',
    'changedCount',v_total_changed,
    'items',v_results,
    'truthBoundary',jsonb_build_object(
      'domainExposureWasAdmissionAuthority',true,
      'notebookMutationOnly',true,
      'domainTruthCreated',false,
      'sourceTruthCopied',false,
      'sourceReadAuthorityGranted',false,
      'indexAuthorityGranted',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false,
      'executionAuthorityGranted',false
    )
  );
end;
$function$;

revoke all on function atlas.reconcile_notebook_exposure_self_api_v1()
  from public,anon;
grant execute on function atlas.reconcile_notebook_exposure_self_api_v1()
  to authenticated,service_role;
