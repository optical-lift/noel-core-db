-- Atlas Responsibility Applicability v1
--
-- Canonical, read-only resolution membrane for determining whether one canonical
-- Responsibility applies to one exact Reality Entity for one exact operation at
-- one explicit instant.
--
-- This contract does not grant execution authority, allocate Work, establish a
-- Principal claim, admit Clock state, or infer applicability from legacy
-- organization-responsibility carriers.

create table if not exists atlas.responsibility_applicability_governance (
  id uuid primary key default gen_random_uuid(),
  applicability_relation_id uuid not null references reality.entity_relationships(id) on delete restrict,
  operation_key text not null,
  governance_state text not null default 'established',
  valid_from timestamptz not null,
  valid_until timestamptz,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint responsibility_applicability_governance_operation_key_nonblank
    check (btrim(operation_key)<>''),
  constraint responsibility_applicability_governance_state_v1
    check (governance_state in ('established','retired')),
  constraint responsibility_applicability_governance_interval_v1
    check (valid_until is null or valid_until>valid_from)
);

create index if not exists responsibility_applicability_governance_lookup_v1
  on atlas.responsibility_applicability_governance(
    applicability_relation_id,
    operation_key,
    valid_from,
    valid_until
  );

comment on table atlas.responsibility_applicability_governance is
  'Separate governance for canonical responsibility_applies_to relations. Operation scope and governance history live here; the Reality relation remains the canonical structural applicability fact.';

revoke all on table atlas.responsibility_applicability_governance
  from public,anon,authenticated,service_role;


create or replace function reality.responsibility_applicability_effective_at_v1(
  p_relation_id uuid,
  p_operation_key text,
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
    raise exception 'Applicability relation ID is required.' using errcode='22023';
  end if;
  if p_operation_key is null or btrim(p_operation_key)='' then
    raise exception 'Exact operation key is required.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'Explicit as_of is required.' using errcode='22023';
  end if;

  select exists(
    select 1
    from reality.entity_relationships er
    join atlas.responsibility_applicability_governance rag
      on rag.applicability_relation_id=er.id
    where er.id=p_relation_id
      and er.relationship_kind='responsibility_applies_to'
      and er.relationship_state='established'
      and er.valid_from is not null
      and er.valid_from<=p_as_of
      and (er.valid_until is null or er.valid_until>p_as_of)
      and rag.operation_key=p_operation_key
      and rag.governance_state='established'
      and rag.valid_from<=p_as_of
      and (rag.valid_until is null or rag.valid_until>p_as_of)
  )
  into v_effective;

  if not exists(
    select 1
    from reality.entity_relationships er
    where er.id=p_relation_id
      and er.relationship_kind='responsibility_applies_to'
  ) then
    raise exception 'Governed responsibility applicability relation not found.' using errcode='P0002';
  end if;

  return coalesce(v_effective,false);
end
$function$;

revoke all on function reality.responsibility_applicability_effective_at_v1(uuid,text,timestamptz)
  from public,anon,authenticated,service_role;


create or replace function atlas.responsibility_applicability_history_api_v1(
  p_responsibility_entity_id uuid,
  p_target_entity_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_responsibility jsonb;
  v_target jsonb;
  v_relations jsonb:='[]'::jsonb;
  v_captured_at timestamptz:=statement_timestamp();
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_responsibility_entity_id is null then
    raise exception 'Responsibility Entity is required.' using errcode='22023';
  end if;
  if p_target_entity_id is null then
    raise exception 'Target Reality Entity is required.' using errcode='22023';
  end if;
  if p_operation_key is null or btrim(p_operation_key)='' then
    raise exception 'Exact operation key is required.' using errcode='22023';
  end if;

  perform reality.assert_canonical_entity_kind_v1(
    p_responsibility_entity_id,
    'responsibility'
  );

  select jsonb_build_object(
    'id',e.id,
    'stableKey',e.stable_key,
    'kind',e.entity_kind,
    'displayName',e.display_name,
    'identityState',e.identity_state
  )
  into v_responsibility
  from reality.entities e
  where e.id=p_responsibility_entity_id;

  select jsonb_build_object(
    'id',e.id,
    'stableKey',e.stable_key,
    'kind',e.entity_kind,
    'displayName',e.display_name,
    'identityState',e.identity_state
  )
  into v_target
  from reality.entities e
  where e.id=p_target_entity_id;

  if v_target is null then
    raise exception 'Canonical target Reality Entity not found.' using errcode='P0002';
  end if;

  -- LEFT JOIN is intentional. A canonical applicability relation without matching
  -- operation governance must remain visible to the resolver so it can fail closed;
  -- an inner join would erase the missing-governance fact and create a false negative.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'relationId',er.id,
        'relationshipKind',er.relationship_kind,
        'relationshipState',er.relationship_state,
        'responsibilityEntityId',er.subject_entity_id,
        'targetEntityId',er.object_entity_id,
        'validFrom',er.valid_from,
        'validUntil',er.valid_until,
        'evidence',er.evidence,
        'metadata',er.metadata,
        'governance',case
          when rag.id is null then null
          else jsonb_build_object(
            'governanceId',rag.id,
            'operationKey',rag.operation_key,
            'governanceState',rag.governance_state,
            'validFrom',rag.valid_from,
            'validUntil',rag.valid_until,
            'provenance',rag.provenance,
            'createdAt',rag.created_at,
            'updatedAt',rag.updated_at
          )
        end,
        'createdAt',er.created_at,
        'updatedAt',er.updated_at
      )
      order by er.valid_from,er.id,rag.valid_from,rag.id
    ),
    '[]'::jsonb
  )
  into v_relations
  from reality.entity_relationships er
  left join atlas.responsibility_applicability_governance rag
    on rag.applicability_relation_id=er.id
   and rag.operation_key=p_operation_key
  where er.relationship_kind='responsibility_applies_to'
    and er.subject_entity_id=p_responsibility_entity_id
    and er.object_entity_id=p_target_entity_id;

  return jsonb_build_object(
    'contractVersion','responsibility_applicability_history_v1',
    'state','ready',
    'capturedAt',v_captured_at,
    'responsibility',v_responsibility,
    'target',v_target,
    'operationKey',p_operation_key,
    'relations',v_relations,
    'completeness',jsonb_build_object(
      'complete',true,
      'exactResponsibilityEntityId',p_responsibility_entity_id,
      'exactTargetEntityId',p_target_entity_id,
      'exactOperationKey',p_operation_key,
      'relationFamily','responsibility_applies_to',
      'includesAllRelationshipStates',true,
      'includesRelationsWithoutGovernance',true,
      'includesAllMatchingOperationGovernanceStates',true,
      'historicalIntervalsPreserved',true
    ),
    'truthBoundary',jsonb_build_object(
      'readDoesNotCreateReality',true,
      'legacyOrganizationResponsibilityIdsAcceptedAsCanonical',false,
      'executionAuthorityCreated',false,
      'workAllocationCreated',false,
      'principalClaimCreated',false,
      'clockOrTodayStateCreated',false
    )
  );
end
$function$;

revoke all on function atlas.responsibility_applicability_history_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.responsibility_applicability_history_api_v1(uuid,uuid,text)
  to authenticated;

comment on function atlas.responsibility_applicability_history_api_v1(uuid,uuid,text) is
  'Exact canonical Responsibility + target Reality Entity + operation applicability history. Preserves relations even when matching operation governance is missing, preserves governance intervals when present, and does not grant execution authority, Work allocation, Principal claim, or Clock admission.';