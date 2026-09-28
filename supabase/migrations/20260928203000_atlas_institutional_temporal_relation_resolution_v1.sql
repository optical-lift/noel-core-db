-- Atlas Institutional Temporal Relation Resolution v1
--
-- Read-only source membrane for the canonical institutional relation spine.
-- This migration creates no structural truth, authority, Work allocation,
-- applicability, Principal claim, Clock state, or projection state.

create or replace function reality.institution_relation_effective_at_v1(
  p_relation_id uuid,
  p_as_of timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_effective boolean;
begin
  if p_relation_id is null then
    raise exception 'Institutional relation ID is required.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'Explicit as_of is required.' using errcode='22023';
  end if;

  select (
    er.relationship_state='established'
    and er.valid_from is not null
    and er.valid_from<=p_as_of
    and (er.valid_until is null or er.valid_until>p_as_of)
  )
  into v_effective
  from reality.entity_relationships er
  where er.id=p_relation_id
    and er.relationship_kind in (
      'institutional_standing',
      'institution_has_position',
      'institution_has_responsibility',
      'occupies_position',
      'position_carries_responsibility'
    );

  if not found then
    raise exception 'Governed institutional relation not found.' using errcode='P0002';
  end if;

  return coalesce(v_effective,false);
end
$function$;

revoke all on function reality.institution_relation_effective_at_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;


create or replace function atlas.institutional_relation_history_self_api_v1(
  p_institution_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_person jsonb;
  v_institution jsonb;
  v_relations jsonb:='[]'::jsonb;
  v_entities jsonb:='[]'::jsonb;
  v_captured_at timestamptz:=clock_timestamp();
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  if p_institution_entity_id is null then
    raise exception 'Institution Entity is required.' using errcode='22023';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion','institutional_relation_history_self_v1',
      'state','person_binding_required',
      'capturedAt',v_captured_at,
      'relations','[]'::jsonb,
      'entities','[]'::jsonb,
      'completeness',jsonb_build_object('complete',false)
    );
  end if;

  perform reality.assert_canonical_entity_kind_v1(v_person_id,'person');
  perform reality.assert_institution_subject_v1(p_institution_entity_id);

  select jsonb_build_object(
    'id',e.id,
    'stableKey',e.stable_key,
    'kind',e.entity_kind,
    'displayName',e.display_name,
    'identityState',e.identity_state
  )
  into v_person
  from reality.entities e
  where e.id=v_person_id;

  select jsonb_build_object(
    'id',e.id,
    'stableKey',e.stable_key,
    'kind',e.entity_kind,
    'displayName',e.display_name,
    'identityState',e.identity_state
  )
  into v_institution
  from reality.entities e
  where e.id=p_institution_entity_id;

  with position_ids as (
    select distinct er.object_entity_id as entity_id
    from reality.entity_relationships er
    where er.relationship_kind='institution_has_position'
      and er.subject_entity_id=p_institution_entity_id
  ),
  responsibility_ids as (
    select distinct er.object_entity_id as entity_id
    from reality.entity_relationships er
    where er.relationship_kind='institution_has_responsibility'
      and er.subject_entity_id=p_institution_entity_id
  ),
  bounded as (
    select er.*
    from reality.entity_relationships er
    where
      (er.relationship_kind='institutional_standing'
       and er.subject_entity_id=v_person_id
       and er.object_entity_id=p_institution_entity_id)
      or
      (er.relationship_kind='institution_has_position'
       and er.subject_entity_id=p_institution_entity_id)
      or
      (er.relationship_kind='institution_has_responsibility'
       and er.subject_entity_id=p_institution_entity_id)
      or
      (er.relationship_kind='occupies_position'
       and er.subject_entity_id=v_person_id
       and er.object_entity_id in (select entity_id from position_ids))
      or
      (er.relationship_kind='position_carries_responsibility'
       and er.subject_entity_id in (select entity_id from position_ids)
       and er.object_entity_id in (select entity_id from responsibility_ids))
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'relationId',b.id,
        'relationshipKind',b.relationship_kind,
        'relationshipState',b.relationship_state,
        'subjectEntityId',b.subject_entity_id,
        'objectEntityId',b.object_entity_id,
        'validFrom',b.valid_from,
        'validUntil',b.valid_until,
        'evidence',b.evidence,
        'metadata',b.metadata,
        'createdAt',b.created_at,
        'updatedAt',b.updated_at
      )
      order by b.relationship_kind,b.valid_from,b.id
    ),
    '[]'::jsonb
  )
  into v_relations
  from bounded b;

  with relevant_ids as (
    select distinct er.object_entity_id as entity_id
    from reality.entity_relationships er
    where er.relationship_kind='institution_has_position'
      and er.subject_entity_id=p_institution_entity_id
    union
    select distinct er.object_entity_id
    from reality.entity_relationships er
    where er.relationship_kind='institution_has_responsibility'
      and er.subject_entity_id=p_institution_entity_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',e.id,
        'stableKey',e.stable_key,
        'kind',e.entity_kind,
        'displayName',e.display_name,
        'identityState',e.identity_state,
        'metadata',e.metadata
      )
      order by e.entity_kind,e.stable_key,e.id
    ),
    '[]'::jsonb
  )
  into v_entities
  from reality.entities e
  join relevant_ids r on r.entity_id=e.id
  where e.entity_kind in ('position','responsibility');

  return jsonb_build_object(
    'contractVersion','institutional_relation_history_self_v1',
    'state','ready',
    'capturedAt',v_captured_at,
    'person',v_person,
    'institution',v_institution,
    'relations',v_relations,
    'entities',v_entities,
    'completeness',jsonb_build_object(
      'complete',true,
      'boundedToPersonEntityId',v_person_id,
      'boundedToInstitutionEntityId',p_institution_entity_id,
      'relationFamilies',jsonb_build_array(
        'institutional_standing',
        'institution_has_position',
        'institution_has_responsibility',
        'occupies_position',
        'position_carries_responsibility'
      ),
      'includesAllRelationshipStates',true,
      'historicalIntervalsPreserved',true
    ),
    'truthBoundary',jsonb_build_object(
      'readDoesNotCreateReality',true,
      'readDoesNotGrantAuthority',true,
      'positionDoesNotGrantExecutionAuthority',true,
      'responsibilityDefinitionDoesNotGrantExecutionAuthority',true,
      'seatOrOwnershipInference',false,
      'applicabilityCreated',false,
      'workAllocationCreated',false,
      'principalClaimCreated',false,
      'clockOrTodayStateCreated',false
    )
  );
end
$function$;

revoke all on function atlas.institutional_relation_history_self_api_v1(uuid)
  from public,anon,service_role;
grant execute on function atlas.institutional_relation_history_self_api_v1(uuid)
  to authenticated;

comment on function atlas.institutional_relation_history_self_api_v1(uuid) is
  'Complete bounded canonical institutional relation history for the authenticated Reality Person and one exact Institution. Read-only source membrane; downstream Relation Resolution supplies explicit as_of semantics.';
