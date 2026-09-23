-- Atlas Domain Exposure Evaluator v1 candidate.
-- Read-only shared evaluation over Person Position + domain-owned governed reads.
-- Candidate only: no migration identity and no production authority.

begin;

create or replace function atlas.domain_exposure_evaluations_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_position jsonb;
  v_position_state text;
  v_person_id text;
  v_principal_id text;
  v_life jsonb := jsonb_build_object('definitions','[]'::jsonb);
  v_items jsonb := '[]'::jsonb;
  v_def jsonb;
  v_membership jsonb;
  v_ledger jsonb;
  v_ledger_match jsonb;
  v_definition_id text;
  v_signal_kind text;
  v_definition_status text;
  v_relationship_kind text;
  v_org_id text;
  v_role text;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if to_regprocedure('atlas.person_position_self_api_v1()') is null then
    return jsonb_build_object(
      'contractVersion','domain_exposure_evaluations_self_v1',
      'state','person_position_dependency_unavailable',
      'personPosition',null,
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'personPositionRequired',true,
        'sourceTruthCreated',false,
        'notebookMutationAuthorized',false,
        'indexMutationAuthorized',false,
        'todayPlacementAuthorized',false,
        'actionAuthorityGranted',false
      )
    );
  end if;

  execute 'select atlas.person_position_self_api_v1()'
    into v_position;

  v_position_state := coalesce(v_position->>'state','unknown');

  if v_position_state <> 'ready' then
    return jsonb_build_object(
      'contractVersion','domain_exposure_evaluations_self_v1',
      'state',v_position_state,
      'personPosition',jsonb_build_object(
        'contractVersion',v_position->>'contractVersion',
        'state',v_position_state
      ),
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'personPositionRequired',true,
        'canonicalPersonRequired',true,
        'sourceTruthCreated',false,
        'notebookMutationAuthorized',false,
        'indexMutationAuthorized',false,
        'todayPlacementAuthorized',false,
        'actionAuthorityGranted',false
      )
    );
  end if;

  v_person_id := nullif(v_position->'identity'->>'personId','');
  v_principal_id := nullif(v_position->'principalRoot'->>'principalId','');

  if v_person_id is null then
    raise exception 'Ready Person Position did not supply canonical Person identity.'
      using errcode='23514';
  end if;

  -- Person Life remains private and domain-owned. The shared evaluator consumes
  -- the existing signed-in Person Life read rather than querying its tables.
  if to_regprocedure('atlas.person_life_state_api_v1()') is not null then
    v_life := atlas.person_life_state_api_v1();
  end if;

  for v_def in
    select value
    from jsonb_array_elements(coalesce(v_life->'definitions','[]'::jsonb))
  loop
    v_definition_id := nullif(v_def->>'definitionId','');
    v_signal_kind := nullif(v_def->>'signalKind','');
    v_definition_status := coalesce(nullif(v_def->>'status',''),'active');
    v_relationship_kind := case v_signal_kind
      when 'goal' then 'progress'
      when 'rhythm' then 'cadence'
      else 'state'
    end;

    if v_definition_id is null then
      continue;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'contractVersion','domain_exposure_evaluation_v1',
      'contractKey','person.life_definition.v1',
      'personRef',jsonb_build_object(
        'kind','person','id',v_person_id,'domain','identity'
      ),
      'contextRef',case
        when v_principal_id is not null then jsonb_build_object(
          'kind','principal','id',v_principal_id,'domain','identity'
        )
        else jsonb_build_object(
          'kind','person','id',v_person_id,'domain','identity'
        )
      end,
      'subjectRef',jsonb_build_object(
        'kind','life_definition','id',v_definition_id,'domain','person'
      ),
      'encounter',jsonb_build_object(
        'state','eligible',
        'basisRefs',jsonb_build_array(jsonb_build_object(
          'kind','person_life_definition',
          'id',v_definition_id,
          'domain','person',
          'relation','owner_scoped_private_life_truth'
        )),
        'reasonCodes',jsonb_build_array(
          case
            when v_definition_status='retired'
              then 'retired_definition_remains_owner_retrievable_history'
            else 'canonical_active_person_life_definition'
          end
        )
      ),
      'place',jsonb_build_object(
        'disposition','stable',
        'desiredCarrierState',case
          when v_definition_status='retired' then 'closed'
          else 'open'
        end,
        'durabilityKey','life:'||v_definition_id,
        'reasonCodes',jsonb_build_array(
          case
            when v_definition_status='retired'
              then 'retired_definition_preserves_durable_place'
            else 'active_definition_has_durable_identity'
          end
        )
      ),
      'index',jsonb_build_object(
        'disposition','listed',
        'reasonCodes',jsonb_build_array(
          case
            when v_definition_status='retired'
              then 'current_index_keeps_closed_spreads_retrievable'
            else 'active_owner_scoped_life_place'
          end
        )
      ),
      'attentionNomination',jsonb_build_object(
        'disposition','quiet',
        'reasonCodes',jsonb_build_array(
          case
            when v_definition_status='retired'
              then 'retired_history_cannot_nominate_current_attention'
            else 'definition_existence_is_not_attention_authority'
          end
        ),
        'claimRefs','[]'::jsonb
      ),
      'sourceBinding',jsonb_build_object(
        'sourceDomain','person',
        'sourceKind','life_definition_v1',
        'sourceId',v_definition_id,
        'relationshipKind',v_relationship_kind,
        'governedRead','atlas.person_life_state_api_v1'
      ),
      'stateQuality',jsonb_build_object(
        'resolution','established',
        'freshness','current',
        'coverage','partial',
        'provenanceRefs',jsonb_build_array(jsonb_build_object(
          'kind','person_life_definition',
          'id',v_definition_id,
          'domain','person'
        ))
      ),
      'disclosure',jsonb_build_object(
        'shape','exact',
        'sourceReasonDisclosure','not_applicable'
      ),
      'operations','[]'::jsonb,
      'prohibitedInferences',jsonb_build_array(
        'definition existence does not imply Today placement',
        'open consequence does not imply execution warrant',
        'Person Life truth cannot be exposed to another institution merely because the Person participates there'
      )
    ));
  end loop;

  -- Connections is a permanent Principal orientation. It does not imply that a
  -- provider exists, is authorized, is synchronized, or has complete coverage.
  if v_principal_id is not null then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'contractVersion','domain_exposure_evaluation_v1',
      'contractKey','principal.connections_orientation.v1',
      'personRef',jsonb_build_object(
        'kind','person','id',v_person_id,'domain','identity'
      ),
      'contextRef',jsonb_build_object(
        'kind','principal','id',v_principal_id,'domain','identity'
      ),
      'subjectRef',jsonb_build_object(
        'kind','connections','id',v_principal_id,'domain','principal'
      ),
      'encounter',jsonb_build_object(
        'state','eligible',
        'basisRefs',jsonb_build_array(jsonb_build_object(
          'kind','principal',
          'id',v_principal_id,
          'domain','identity',
          'relation','active_principal_orientation'
        )),
        'reasonCodes',jsonb_build_array(
          'active_principal_has_permanent_connections_orientation'
        )
      ),
      'place',jsonb_build_object(
        'disposition','stable',
        'desiredCarrierState','open',
        'durabilityKey','connections',
        'reasonCodes',jsonb_build_array(
          'permanent_principal_orientation_place'
        )
      ),
      'index',jsonb_build_object(
        'disposition','listed',
        'reasonCodes',jsonb_build_array(
          'permanent_principal_orientation_place'
        )
      ),
      'attentionNomination',jsonb_build_object(
        'disposition','quiet',
        'reasonCodes',jsonb_build_array(
          'connection_state_does_not_grant_attention_authority'
        ),
        'claimRefs','[]'::jsonb
      ),
      'sourceBinding',jsonb_build_object(
        'sourceDomain','principal',
        'sourceKind','connected_sources_v1',
        'sourceId',v_principal_id,
        'relationshipKind','evidence',
        'governedRead','atlas.connected_sources_self_api_v1'
      ),
      'stateQuality',jsonb_build_object(
        'resolution','established',
        'freshness','unknown',
        'coverage','unknown',
        'provenanceRefs',jsonb_build_array(jsonb_build_object(
          'kind','principal',
          'id',v_principal_id,
          'domain','identity'
        ))
      ),
      'disclosure',jsonb_build_object(
        'shape','summary',
        'sourceReasonDisclosure','not_applicable'
      ),
      'operations','[]'::jsonb,
      'prohibitedInferences',jsonb_build_array(
        'Connections page existence does not establish any provider connection',
        'Connected Source existence does not establish downstream life truth',
        'connected or synced source does not grant domain action authority',
        'unknown source coverage cannot be presented as trustworthy silence'
      )
    ));
  end if;

  -- Organization Ledger exposure preserves the current transitional owner-role
  -- admission while separately requiring the root-governing Ledger context
  -- already exposed by Person Position.
  for v_membership in
    select value
    from jsonb_array_elements(
      coalesce(v_position->'institutionalMemberships','[]'::jsonb)
    )
  loop
    v_org_id := nullif(v_membership->>'organizationId','');
    v_role := nullif(v_membership->>'compatibilityRole','');
    v_ledger_match := null;

    if v_org_id is null then
      continue;
    end if;

    select value
      into v_ledger_match
    from jsonb_array_elements(
      coalesce(v_position->'ledgerContexts'->'items','[]'::jsonb)
    )
    where value->>'organizationId'=v_org_id
    limit 1;

    if v_role='owner' and v_ledger_match is not null then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','organization.ledger_owner_compatibility.v1',
        'personRef',jsonb_build_object(
          'kind','person','id',v_person_id,'domain','identity'
        ),
        'contextRef',jsonb_build_object(
          'kind','organization','id',v_org_id,'domain','organization'
        ),
        'subjectRef',jsonb_build_object(
          'kind','organization_ledger','id',v_org_id,'domain','organization'
        ),
        'encounter',jsonb_build_object(
          'state','eligible',
          'basisRefs',jsonb_build_array(
            jsonb_build_object(
              'kind','organization_membership',
              'id',v_membership->>'organizationMembershipId',
              'domain','organization',
              'relation','active_owner_compatibility'
            ),
            jsonb_build_object(
              'kind','ledger',
              'id',v_ledger_match->>'ledgerId',
              'domain','ledger',
              'relation','root_governing_context'
            )
          ),
          'reasonCodes',jsonb_build_array(
            'current_owner_membership_compatibility_admission'
          )
        ),
        'place',jsonb_build_object(
          'disposition','stable',
          'desiredCarrierState','open',
          'durabilityKey','ledger:'||v_org_id,
          'reasonCodes',jsonb_build_array(
            'current_owner_compatibility_warrants_durable_place'
          )
        ),
        'index',jsonb_build_object(
          'disposition','listed',
          'reasonCodes',jsonb_build_array(
            'current_owner_compatibility_admission'
          )
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array(
            'ledger_relationship_is_not_current_attention'
          ),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',jsonb_build_object(
          'sourceDomain','organization',
          'sourceKind','ledger_recent_v1',
          'sourceId',v_org_id,
          'relationshipKind','evidence',
          'governedRead','atlas.organization_ledger_owner_recent_api_v1',
          'metadata',jsonb_build_object(
            'ledgerId',v_ledger_match->>'ledgerId',
            'admissionBasis','transitional_owner_compatibility'
          )
        ),
        'stateQuality',jsonb_build_object(
          'resolution','established',
          'freshness','current',
          'coverage','partial',
          'provenanceRefs',jsonb_build_array(
            jsonb_build_object(
              'kind','organization_membership',
              'id',v_membership->>'organizationMembershipId',
              'domain','organization'
            ),
            jsonb_build_object(
              'kind','ledger',
              'id',v_ledger_match->>'ledgerId',
              'domain','ledger'
            )
          )
        ),
        'disclosure',jsonb_build_object(
          'shape','exact',
          'sourceReasonDisclosure','not_applicable'
        ),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'ordinary Organization Membership does not imply Ledger exposure',
          'owner role is a current compatibility admission and must not generalize into a universal role-to-visibility rule',
          'Position title does not imply Ledger exposure',
          'commercial entitlement does not imply governing Ledger authority',
          'Ledger exposure does not imply action or execution authority',
          'future cutover to exact Principal Ledger authority must preserve durable spread identity rather than create a second Ledger page'
        )
      ));
    elsif v_role='owner' then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','organization.ledger_owner_compatibility.v1',
        'personRef',jsonb_build_object(
          'kind','person','id',v_person_id,'domain','identity'
        ),
        'contextRef',jsonb_build_object(
          'kind','organization','id',v_org_id,'domain','organization'
        ),
        'subjectRef',jsonb_build_object(
          'kind','organization_ledger','id',v_org_id,'domain','organization'
        ),
        'encounter',jsonb_build_object(
          'state','unresolved',
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','organization_membership',
            'id',v_membership->>'organizationMembershipId',
            'domain','organization',
            'relation','active_owner_compatibility'
          )),
          'reasonCodes',jsonb_build_array(
            'owner_compatibility_without_root_ledger_context'
          )
        ),
        'place',jsonb_build_object(
          'disposition','none',
          'reasonCodes',jsonb_build_array(
            'root_ledger_context_required'
          )
        ),
        'index',jsonb_build_object(
          'disposition','absent',
          'reasonCodes',jsonb_build_array(
            'root_ledger_context_required'
          )
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','unresolved',
          'reasonCodes',jsonb_build_array(
            'root_ledger_context_required'
          ),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',null,
        'stateQuality',jsonb_build_object(
          'resolution','unresolved',
          'freshness','current',
          'coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','organization_membership',
            'id',v_membership->>'organizationMembershipId',
            'domain','organization'
          ))
        ),
        'disclosure',jsonb_build_object(
          'shape','summary',
          'sourceReasonDisclosure','not_applicable'
        ),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'owner compatibility does not manufacture a governing Ledger',
          'unresolved Ledger context cannot create a notebook source binding',
          'unresolved exposure cannot nominate established attention'
        )
      ));
    else
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'contractVersion','domain_exposure_evaluation_v1',
        'contractKey','organization.ledger_owner_compatibility.v1',
        'personRef',jsonb_build_object(
          'kind','person','id',v_person_id,'domain','identity'
        ),
        'contextRef',jsonb_build_object(
          'kind','organization','id',v_org_id,'domain','organization'
        ),
        'subjectRef',jsonb_build_object(
          'kind','organization_ledger','id',v_org_id,'domain','organization'
        ),
        'encounter',jsonb_build_object(
          'state','ineligible',
          'basisRefs',jsonb_build_array(jsonb_build_object(
            'kind','organization_membership',
            'id',v_membership->>'organizationMembershipId',
            'domain','organization',
            'relation','participates_in'
          )),
          'reasonCodes',jsonb_build_array(
            'membership_without_owner_compatibility_admission'
          )
        ),
        'place',jsonb_build_object(
          'disposition','none',
          'durabilityKey','ledger:'||v_org_id,
          'reasonCodes',jsonb_build_array(
            'no_current_ledger_exposure_basis'
          )
        ),
        'index',jsonb_build_object(
          'disposition','absent',
          'reasonCodes',jsonb_build_array(
            'no_current_ledger_exposure_basis'
          )
        ),
        'attentionNomination',jsonb_build_object(
          'disposition','quiet',
          'reasonCodes',jsonb_build_array(
            'ineligible_material_cannot_nominate_attention'
          ),
          'claimRefs','[]'::jsonb
        ),
        'sourceBinding',null,
        'stateQuality',jsonb_build_object(
          'resolution','established',
          'freshness','current',
          'coverage','partial',
          'provenanceRefs',jsonb_build_array(jsonb_build_object(
            'kind','organization_membership',
            'id',v_membership->>'organizationMembershipId',
            'domain','organization'
          ))
        ),
        'disclosure',jsonb_build_object(
          'shape','summary',
          'sourceReasonDisclosure','not_applicable'
        ),
        'operations','[]'::jsonb,
        'prohibitedInferences',jsonb_build_array(
          'membership does not imply knowledge',
          'membership does not imply Ledger authority'
        )
      ));
    end if;
  end loop;

  -- Preserve otherwise-unrepresented root Ledger contexts as explicitly
  -- unexposed under the current transitional owner-compatibility law.
  for v_ledger in
    select value
    from jsonb_array_elements(
      coalesce(v_position->'ledgerContexts'->'items','[]'::jsonb)
    )
  loop
    v_org_id := nullif(v_ledger->>'organizationId','');

    if v_org_id is null then
      continue;
    end if;

    if exists (
      select 1
      from jsonb_array_elements(
        coalesce(v_position->'institutionalMemberships','[]'::jsonb)
      ) m(value)
      where m.value->>'organizationId'=v_org_id
    ) then
      continue;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'contractVersion','domain_exposure_evaluation_v1',
      'contractKey','organization.ledger_owner_compatibility.v1',
      'personRef',jsonb_build_object(
        'kind','person','id',v_person_id,'domain','identity'
      ),
      'contextRef',jsonb_build_object(
        'kind','organization','id',v_org_id,'domain','organization'
      ),
      'subjectRef',jsonb_build_object(
        'kind','organization_ledger','id',v_org_id,'domain','organization'
      ),
      'encounter',jsonb_build_object(
        'state','ineligible',
        'basisRefs',jsonb_build_array(jsonb_build_object(
          'kind','ledger',
          'id',v_ledger->>'ledgerId',
          'domain','ledger',
          'relation','root_governing_without_current_owner_compatibility'
        )),
        'reasonCodes',jsonb_build_array(
          'current_transitional_owner_compatibility_absent'
        )
      ),
      'place',jsonb_build_object(
        'disposition','none',
        'durabilityKey','ledger:'||v_org_id,
        'reasonCodes',jsonb_build_array(
          'current_transitional_owner_compatibility_absent'
        )
      ),
      'index',jsonb_build_object(
        'disposition','absent',
        'reasonCodes',jsonb_build_array(
          'current_transitional_owner_compatibility_absent'
        )
      ),
      'attentionNomination',jsonb_build_object(
        'disposition','quiet',
        'reasonCodes',jsonb_build_array(
          'ineligible_material_cannot_nominate_attention'
        ),
        'claimRefs','[]'::jsonb
      ),
      'sourceBinding',null,
      'stateQuality',jsonb_build_object(
        'resolution','established',
        'freshness','current',
        'coverage','partial',
        'provenanceRefs',jsonb_build_array(jsonb_build_object(
          'kind','ledger',
          'id',v_ledger->>'ledgerId',
          'domain','ledger'
        ))
      ),
      'disclosure',jsonb_build_object(
        'shape','summary',
        'sourceReasonDisclosure','not_applicable'
      ),
      'operations','[]'::jsonb,
      'prohibitedInferences',jsonb_build_array(
        'root Ledger authority does not silently rewrite the current notebook admission contract',
        'future authority cutover requires an explicit governed migration of admission law'
      )
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','domain_exposure_evaluations_self_v1',
    'state','ready',
    'personPosition',jsonb_build_object(
      'contractVersion',v_position->>'contractVersion',
      'state',v_position_state,
      'personId',v_person_id,
      'principalId',v_principal_id
    ),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'personPositionConsumed',true,
      'domainReadsRemainAuthoritative',true,
      'exposureEvaluationIsNotTruthDomain',true,
      'sourceTruthCreated',false,
      'notebookMutationAuthorized',false,
      'indexMutationAuthorized',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false,
      'executionAuthorityGranted',false
    )
  );
end;
$function$;

comment on function atlas.domain_exposure_evaluations_self_api_v1() is
  'Self-only, read-only Domain Exposure evaluator v1. Consumes Person Position and domain-owned governed self reads to emit Person Life, Connections and transitional Organization Ledger exposure evaluations without creating source truth, notebook carriers, source bindings, Index state, Today placement or action authority.';

revoke all on function atlas.domain_exposure_evaluations_self_api_v1()
  from public, anon;
grant execute on function atlas.domain_exposure_evaluations_self_api_v1()
  to authenticated;

commit;
