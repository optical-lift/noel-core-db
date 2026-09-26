-- Root Reality promotion membrane for the Implementation Workbench.
--
-- This finishes a missing layer between a practitioner-authored Reality Candidate
-- and canonical Reality truth. The first slice is deliberately narrow:
--   1) establish/reuse a non-human Reality Entity;
--   2) establish/reuse a typed relationship between canonical Reality Entities;
--   3) establish/reuse a Reality responsibility carried by a canonical Person.
--
-- No candidate promotes implicitly. Preview is read-only. Promotion requires an
-- assigned practitioner, an open Implementation Case, and a verified setup sponsor.

alter table atlas.implementation_reality_candidates
  drop constraint implementation_reality_candidates_operation_check,
  drop constraint implementation_reality_candidates_operation_shape;

alter table atlas.implementation_reality_candidates
  add constraint implementation_reality_candidates_operation_check
  check (operation_id = any (array[
    'organization.establish'::text,
    'person.establish'::text,
    'institutional_person_record.establish'::text,
    'organization_unit.establish'::text,
    'organization_position.establish'::text,
    'organization_responsibility.establish'::text,
    'position_responsibility_definition.establish'::text,
    'person_position_appointment.establish'::text,
    'reality_entity.establish'::text,
    'reality_entity_relationship.establish'::text,
    'reality_responsibility.establish'::text
  ])),
  add constraint implementation_reality_candidates_operation_shape
  check (
    case operation_id
      when 'organization.establish' then
        (subject_binding->>'kind'='organization' and object_binding is null and context_binding is null)
      when 'person.establish' then
        (subject_binding->>'kind'='person' and object_binding is null and context_binding is null)
      when 'institutional_person_record.establish' then
        (subject_binding->>'kind'='person' and object_binding is not null and object_binding->>'kind'='organization' and context_binding is null)
      when 'organization_unit.establish' then
        (subject_binding->>'kind'='organization_unit' and object_binding is not null and object_binding->>'kind'='organization'
          and (context_binding is null or context_binding->>'kind'='organization_unit'))
      when 'organization_position.establish' then
        (subject_binding->>'kind'='organization_position' and object_binding is not null and object_binding->>'kind'='organization_unit' and context_binding is null)
      when 'organization_responsibility.establish' then
        (subject_binding->>'kind'='organization_responsibility' and object_binding is not null and object_binding->>'kind'='organization' and context_binding is null)
      when 'position_responsibility_definition.establish' then
        (subject_binding->>'kind'='organization_position' and object_binding is not null and object_binding->>'kind'='organization_responsibility'
          and context_binding is not null and context_binding->>'kind'='organization')
      when 'person_position_appointment.establish' then
        (subject_binding->>'kind'='person' and object_binding is not null and object_binding->>'kind'='organization_position'
          and context_binding is not null and context_binding->>'kind'='organization')
      when 'reality_entity.establish' then
        (subject_binding->>'kind'='reality_entity' and object_binding is null and context_binding is null)
      when 'reality_entity_relationship.establish' then
        (subject_binding->>'kind'='reality_entity' and object_binding is not null and object_binding->>'kind'='reality_entity' and context_binding is null)
      when 'reality_responsibility.establish' then
        (subject_binding->>'kind'='person' and object_binding is not null and object_binding->>'kind'='reality_entity' and context_binding is null)
      else false
    end
  );

create or replace function atlas.implementation_verified_setup_sponsor_person_v1(
  p_implementation_case_id uuid
)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
  select binding.person_entity_id
  from atlas.implementation_case_participants participant
  join reality.auth_person_bindings binding
    on binding.auth_user_id=participant.human_user_id
   and binding.binding_state='active'
   and binding.retired_at is null
  join reality.entities person
    on person.id=binding.person_entity_id
   and person.entity_kind='person'
   and person.identity_state='canonical'
  where participant.implementation_case_id=p_implementation_case_id
    and participant.relationship_kind='setup_sponsor'
    and participant.active
    and participant.ended_at is null
    and participant.verified_at is not null
  order by participant.started_at,participant.id,binding.bound_at desc,binding.id
  limit 1;
$function$;

create or replace function atlas.implementation_reality_basis_allowed_v1(p_basis jsonb)
returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select p_basis is not null
     and jsonb_typeof(p_basis)='object'
     and p_basis->>'kind' in (
       'explicit_acceptance',
       'standing_intake',
       'reconstruction_of_existing_reality',
       'adjudicated_existing_reality',
       'other_governed_basis'
     );
$function$;

create or replace function atlas.preview_implementation_reality_entity_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_entity_kind text;
  v_stable_key text;
  v_display_name text;
  v_metadata jsonb;
  v_existing reality.entities%rowtype;
  v_name_matches jsonb;
  v_sponsor_person uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select candidate.* into v_candidate
  from atlas.implementation_reality_candidates candidate
  join atlas.implementation_cases implementation_case
    on implementation_case.id=candidate.implementation_case_id
   and implementation_case.state not in ('closed','cancelled')
  where candidate.id=p_candidate_id;

  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;

  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','already_promoted','canPromote',false,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref
    );
  end if;

  if v_candidate.operation_id<>'reality_entity.establish' then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','unsupported_operation','canPromote',false);
  end if;
  if v_candidate.candidate_state not in ('proposed','unresolved') then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','candidate_not_promotable','canPromote',false);
  end if;
  if v_candidate.subject_binding->>'resolution' not in ('proposed','unresolved') then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','subject_must_be_new_or_unresolved','canPromote',false);
  end if;
  if not atlas.implementation_reality_basis_allowed_v1(v_candidate.establishment_basis) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'state','establishment_basis_required','canPromote',false,
      'allowedBasisKinds',jsonb_build_array('explicit_acceptance','standing_intake','reconstruction_of_existing_reality','adjudicated_existing_reality','other_governed_basis')
    );
  end if;

  v_sponsor_person:=atlas.implementation_verified_setup_sponsor_person_v1(v_candidate.implementation_case_id);
  if v_sponsor_person is null then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','verified_setup_sponsor_reality_person_required','canPromote',false);
  end if;

  v_entity_kind:=lower(btrim(coalesce(v_candidate.semantic_payload->>'entityKind','')));
  v_stable_key:=lower(btrim(coalesce(v_candidate.semantic_payload->>'stableKey','')));
  v_display_name:=btrim(coalesce(v_candidate.semantic_payload->>'displayName',v_candidate.subject_binding->>'label',''));
  v_metadata:=coalesce(v_candidate.semantic_payload->'metadata','{}'::jsonb);

  if v_entity_kind not in ('business','organization') then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','unsupported_entity_kind','canPromote',false,'allowedEntityKinds',jsonb_build_array('business','organization'));
  end if;
  if v_stable_key='' or char_length(v_stable_key)>200 or v_stable_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','stable_key_required','canPromote',false);
  end if;
  if v_display_name='' or char_length(v_display_name)>300 then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','display_name_required','canPromote',false);
  end if;
  if jsonb_typeof(v_metadata)<>'object' then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','metadata_must_be_object','canPromote',false);
  end if;

  select * into v_existing from reality.entities where stable_key=v_stable_key;
  if v_existing.id is not null then
    if v_existing.identity_state='canonical'
       and v_existing.entity_kind=v_entity_kind
       and lower(btrim(v_existing.display_name))=lower(v_display_name) then
      return jsonb_build_object(
        'ok',true,'candidateId',v_candidate.id,'state','ready','canPromote',true,
        'mode','reuse_existing','setupSponsorPersonEntityId',v_sponsor_person,
        'entity',jsonb_build_object('id',v_existing.id,'stableKey',v_existing.stable_key,'entityKind',v_existing.entity_kind,'displayName',v_existing.display_name)
      );
    end if;
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'state','stable_key_conflict','canPromote',false,
      'existingEntity',jsonb_build_object('id',v_existing.id,'stableKey',v_existing.stable_key,'entityKind',v_existing.entity_kind,'displayName',v_existing.display_name,'identityState',v_existing.identity_state)
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',entity.id,'stableKey',entity.stable_key,'entityKind',entity.entity_kind,'displayName',entity.display_name,'identityState',entity.identity_state
  ) order by entity.display_name,entity.id),'[]'::jsonb)
  into v_name_matches
  from reality.entities entity
  where entity.identity_state<>'retired'
    and entity.entity_kind=v_entity_kind
    and lower(btrim(entity.display_name))=lower(v_display_name);

  if jsonb_array_length(v_name_matches)>0 then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'state','identity_resolution_required','canPromote',false,
      'reason','same_kind_same_display_name_already_exists','matches',v_name_matches
    );
  end if;

  return jsonb_build_object(
    'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
    'state','ready','canPromote',true,'mode','create_entity',
    'setupSponsorPersonEntityId',v_sponsor_person,
    'entity',jsonb_build_object('stableKey',v_stable_key,'entityKind',v_entity_kind,'displayName',v_display_name),
    'truthBoundary',jsonb_build_object('previewOnly',true,'canonicalMutation',false,'identityCollisionChecked',true)
  );
end;
$function$;

create or replace function atlas.promote_implementation_reality_entity_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_entity reality.entities%rowtype;
  v_entity_id uuid;
  v_entity_kind text;
  v_stable_key text;
  v_display_name text;
  v_metadata jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select candidate.* into v_candidate
  from atlas.implementation_reality_candidates candidate
  join atlas.implementation_cases implementation_case
    on implementation_case.id=candidate.implementation_case_id
   and implementation_case.state not in ('closed','cancelled')
  where candidate.id=p_candidate_id
  for update of candidate;

  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;

  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object(
      'ok',true,'promoted',true,'alreadyPromoted',true,'candidateId',v_candidate.id,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref
    );
  end if;

  v_preview:=atlas.preview_implementation_reality_entity_promotion_self_api_v1(v_candidate.id);
  if coalesce(v_preview->>'state','')<>'ready' then
    update atlas.implementation_reality_candidates
    set candidate_state=case when candidate_state='proposed' then 'unresolved' else candidate_state end,updated_at=now()
    where id=v_candidate.id;
    return jsonb_build_object('ok',false,'promoted',false,'candidateId',v_candidate.id,'preview',v_preview);
  end if;

  v_entity_kind:=lower(btrim(v_candidate.semantic_payload->>'entityKind'));
  v_stable_key:=lower(btrim(v_candidate.semantic_payload->>'stableKey'));
  v_display_name:=btrim(coalesce(v_candidate.semantic_payload->>'displayName',v_candidate.subject_binding->>'label'));
  v_metadata:=coalesce(v_candidate.semantic_payload->'metadata','{}'::jsonb);

  if v_preview->>'mode'='reuse_existing' then
    v_entity_id:=(v_preview->'entity'->>'id')::uuid;
    select * into v_entity from reality.entities where id=v_entity_id;
  else
    insert into reality.entities(stable_key,entity_kind,display_name,identity_state,metadata)
    values(
      v_stable_key,v_entity_kind,v_display_name,'canonical',
      v_metadata||jsonb_build_object(
        'establishedFrom','implementation_reality_candidate',
        'implementationCaseId',v_candidate.implementation_case_id,
        'realityCandidateId',v_candidate.id,
        'literalStatement',v_candidate.literal_statement,
        'evidenceRefs',v_candidate.evidence_refs,
        'establishmentBasis',v_candidate.establishment_basis,
        'setupSponsorPersonEntityId',v_preview->>'setupSponsorPersonEntityId'
      )
    ) returning * into v_entity;
    v_entity_id:=v_entity.id;
  end if;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',
      canonical_consequence_kind='reality_entity',
      canonical_consequence_ref=v_entity_id::text,
      promoted_at=now(),
      promoted_by_user_id=auth.uid(),
      provenance=provenance||jsonb_build_object(
        'promotionContract','implementation_reality_entity_promotion_v1',
        'promotionMode',v_preview->>'mode',
        'promotedEntityId',v_entity_id
      ),
      updated_at=now()
  where id=v_candidate.id;

  return jsonb_build_object(
    'ok',true,'promoted',true,'alreadyPromoted',false,'candidateId',v_candidate.id,
    'canonicalConsequenceKind','reality_entity','canonicalConsequenceRef',v_entity_id::text,
    'entity',jsonb_build_object('id',v_entity.id,'stableKey',v_entity.stable_key,'entityKind',v_entity.entity_kind,'displayName',v_entity.display_name,'identityState',v_entity.identity_state),
    'truthBoundary',jsonb_build_object('candidatePreservedAsProvenance',true,'identityCollisionCheckedBeforeInsert',true)
  );
end;
$function$;

create or replace function atlas.preview_implementation_reality_entity_relationship_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_subject uuid;
  v_object uuid;
  v_kind text;
  v_subject_entity reality.entities%rowtype;
  v_object_entity reality.entities%rowtype;
  v_existing reality.entity_relationships%rowtype;
  v_conflict_count integer;
  v_sponsor_person uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select candidate.* into v_candidate
  from atlas.implementation_reality_candidates candidate
  join atlas.implementation_cases implementation_case on implementation_case.id=candidate.implementation_case_id and implementation_case.state not in ('closed','cancelled')
  where candidate.id=p_candidate_id;
  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then raise exception 'Assigned practitioner authority required.' using errcode='42501'; end if;

  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','already_promoted','canPromote',false,'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,'canonicalConsequenceRef',v_candidate.canonical_consequence_ref);
  end if;
  if v_candidate.operation_id<>'reality_entity_relationship.establish' then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','unsupported_operation','canPromote',false); end if;
  if v_candidate.candidate_state not in ('proposed','unresolved') then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','candidate_not_promotable','canPromote',false); end if;
  if not atlas.implementation_reality_basis_allowed_v1(v_candidate.establishment_basis) then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','establishment_basis_required','canPromote',false); end if;
  if v_candidate.subject_binding->>'resolution'<>'canonical' or v_candidate.object_binding->>'resolution'<>'canonical' then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','identity_resolution_required','canPromote',false);
  end if;

  begin
    v_subject:=(v_candidate.subject_binding->>'canonicalId')::uuid;
    v_object:=(v_candidate.object_binding->>'canonicalId')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_binding_invalid','canPromote',false);
  end;
  if v_subject=v_object then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','self_relationship_not_allowed','canPromote',false); end if;

  select * into v_subject_entity from reality.entities where id=v_subject and identity_state='canonical';
  select * into v_object_entity from reality.entities where id=v_object and identity_state='canonical';
  if v_subject_entity.id is null or v_object_entity.id is null then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_entity_unavailable','canPromote',false); end if;

  v_kind:=btrim(coalesce(v_candidate.semantic_payload->>'relationshipKind',''));
  if v_kind='' or char_length(v_kind)>160 then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','relationship_kind_required','canPromote',false); end if;

  v_sponsor_person:=atlas.implementation_verified_setup_sponsor_person_v1(v_candidate.implementation_case_id);
  if v_sponsor_person is null then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','verified_setup_sponsor_reality_person_required','canPromote',false); end if;

  select * into v_existing
  from reality.entity_relationships relation
  where relation.subject_entity_id=v_subject
    and relation.object_entity_id=v_object
    and relation.relationship_kind=v_kind
    and relation.relationship_state='established'
    and (relation.valid_until is null or relation.valid_until>now())
  order by relation.created_at,relation.id
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'state','ready','canPromote',true,'mode','reuse_existing',
      'setupSponsorPersonEntityId',v_sponsor_person,
      'relationship',jsonb_build_object('id',v_existing.id,'subjectEntityId',v_subject,'objectEntityId',v_object,'relationshipKind',v_kind,'relationshipState',v_existing.relationship_state)
    );
  end if;

  select count(*)::integer into v_conflict_count
  from reality.entity_relationships relation
  where relation.subject_entity_id=v_subject
    and relation.object_entity_id=v_object
    and relation.relationship_kind=v_kind
    and relation.relationship_state in ('observed','disputed')
    and (relation.valid_until is null or relation.valid_until>now());

  if v_conflict_count>0 then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','relationship_adjudication_required','canPromote',false,'conflictingRelationCount',v_conflict_count);
  end if;

  return jsonb_build_object(
    'ok',true,'candidateId',v_candidate.id,'state','ready','canPromote',true,'mode','create_relationship',
    'setupSponsorPersonEntityId',v_sponsor_person,
    'relationship',jsonb_build_object(
      'subjectEntity',jsonb_build_object('id',v_subject_entity.id,'displayName',v_subject_entity.display_name,'entityKind',v_subject_entity.entity_kind),
      'objectEntity',jsonb_build_object('id',v_object_entity.id,'displayName',v_object_entity.display_name,'entityKind',v_object_entity.entity_kind),
      'relationshipKind',v_kind
    ),
    'truthBoundary',jsonb_build_object('previewOnly',true,'relationshipDirectionPreserved',true,'relationshipMeaningNotInferred',true)
  );
end;
$function$;

create or replace function atlas.promote_implementation_reality_entity_relationship_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_relation reality.entity_relationships%rowtype;
  v_relation_id uuid;
  v_subject uuid;
  v_object uuid;
  v_kind text;
  v_relationship_metadata jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select candidate.* into v_candidate
  from atlas.implementation_reality_candidates candidate
  join atlas.implementation_cases implementation_case on implementation_case.id=candidate.implementation_case_id and implementation_case.state not in ('closed','cancelled')
  where candidate.id=p_candidate_id
  for update of candidate;
  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then raise exception 'Assigned practitioner authority required.' using errcode='42501'; end if;
  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object('ok',true,'promoted',true,'alreadyPromoted',true,'candidateId',v_candidate.id,'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,'canonicalConsequenceRef',v_candidate.canonical_consequence_ref);
  end if;

  v_preview:=atlas.preview_implementation_reality_entity_relationship_promotion_self_api_v1(v_candidate.id);
  if coalesce(v_preview->>'state','')<>'ready' then
    update atlas.implementation_reality_candidates set candidate_state=case when candidate_state='proposed' then 'unresolved' else candidate_state end,updated_at=now() where id=v_candidate.id;
    return jsonb_build_object('ok',false,'promoted',false,'candidateId',v_candidate.id,'preview',v_preview);
  end if;

  if v_preview->>'mode'='reuse_existing' then
    v_relation_id:=(v_preview->'relationship'->>'id')::uuid;
    select * into v_relation from reality.entity_relationships where id=v_relation_id;
  else
    v_subject:=(v_candidate.subject_binding->>'canonicalId')::uuid;
    v_object:=(v_candidate.object_binding->>'canonicalId')::uuid;
    v_kind:=btrim(v_candidate.semantic_payload->>'relationshipKind');
    v_relationship_metadata:=coalesce(v_candidate.semantic_payload->'metadata','{}'::jsonb);
    if jsonb_typeof(v_relationship_metadata)<>'object' then raise exception 'Relationship metadata must be an object.' using errcode='22023'; end if;

    insert into reality.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,relationship_state,
      valid_from,valid_until,evidence,metadata
    ) values(
      v_subject,v_kind,v_object,'established',
      nullif(v_candidate.semantic_payload->>'validFrom','')::timestamptz,
      nullif(v_candidate.semantic_payload->>'validUntil','')::timestamptz,
      jsonb_build_object(
        'source','implementation_reality_candidate',
        'implementationCaseId',v_candidate.implementation_case_id,
        'realityCandidateId',v_candidate.id,
        'literalStatement',v_candidate.literal_statement,
        'evidenceRefs',v_candidate.evidence_refs,
        'establishmentBasis',v_candidate.establishment_basis,
        'setupSponsorPersonEntityId',v_preview->>'setupSponsorPersonEntityId'
      ),
      v_relationship_metadata
    ) returning * into v_relation;
    v_relation_id:=v_relation.id;
  end if;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',canonical_consequence_kind='reality_entity_relationship',canonical_consequence_ref=v_relation_id::text,
      promoted_at=now(),promoted_by_user_id=auth.uid(),
      provenance=provenance||jsonb_build_object('promotionContract','implementation_reality_entity_relationship_promotion_v1','promotionMode',v_preview->>'mode','promotedRelationshipId',v_relation_id),
      updated_at=now()
  where id=v_candidate.id;

  return jsonb_build_object(
    'ok',true,'promoted',true,'alreadyPromoted',false,'candidateId',v_candidate.id,
    'canonicalConsequenceKind','reality_entity_relationship','canonicalConsequenceRef',v_relation_id::text,
    'relationship',jsonb_build_object('id',v_relation.id,'subjectEntityId',v_relation.subject_entity_id,'relationshipKind',v_relation.relationship_kind,'objectEntityId',v_relation.object_entity_id,'relationshipState',v_relation.relationship_state),
    'truthBoundary',jsonb_build_object('candidatePreservedAsProvenance',true,'relationshipDirectionPreserved',true)
  );
end;
$function$;

create or replace function atlas.preview_implementation_reality_responsibility_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_carrier uuid;
  v_jurisdiction uuid;
  v_key text;
  v_title text;
  v_operations text[];
  v_scope jsonb;
  v_carrier_entity reality.entities%rowtype;
  v_jurisdiction_entity reality.entities%rowtype;
  v_existing reality.responsibility_relations%rowtype;
  v_sponsor_person uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select candidate.* into v_candidate
  from atlas.implementation_reality_candidates candidate
  join atlas.implementation_cases implementation_case on implementation_case.id=candidate.implementation_case_id and implementation_case.state not in ('closed','cancelled')
  where candidate.id=p_candidate_id;
  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then raise exception 'Assigned practitioner authority required.' using errcode='42501'; end if;
  if v_candidate.candidate_state='promoted' then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','already_promoted','canPromote',false,'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,'canonicalConsequenceRef',v_candidate.canonical_consequence_ref); end if;
  if v_candidate.operation_id<>'reality_responsibility.establish' then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','unsupported_operation','canPromote',false); end if;
  if v_candidate.candidate_state not in ('proposed','unresolved') then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','candidate_not_promotable','canPromote',false); end if;
  if not atlas.implementation_reality_basis_allowed_v1(v_candidate.establishment_basis) then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','establishment_basis_required','canPromote',false); end if;
  if v_candidate.subject_binding->>'resolution'<>'canonical' or v_candidate.object_binding->>'resolution'<>'canonical' then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','identity_resolution_required','canPromote',false); end if;

  begin
    v_carrier:=(v_candidate.subject_binding->>'canonicalId')::uuid;
    v_jurisdiction:=(v_candidate.object_binding->>'canonicalId')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_binding_invalid','canPromote',false);
  end;

  select * into v_carrier_entity from reality.entities where id=v_carrier and entity_kind='person' and identity_state='canonical';
  select * into v_jurisdiction_entity from reality.entities where id=v_jurisdiction and identity_state='canonical';
  if v_carrier_entity.id is null then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_person_unavailable','canPromote',false); end if;
  if v_jurisdiction_entity.id is null then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_jurisdiction_entity_unavailable','canPromote',false); end if;

  v_key:=btrim(coalesce(v_candidate.semantic_payload->>'responsibilityKey',''));
  v_title:=btrim(coalesce(v_candidate.semantic_payload->>'title',''));
  v_scope:=coalesce(v_candidate.semantic_payload->'scope','{}'::jsonb);
  if v_key='' or char_length(v_key)>160 then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','responsibility_key_required','canPromote',false); end if;
  if v_title='' or char_length(v_title)>300 then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','responsibility_title_required','canPromote',false); end if;
  if jsonb_typeof(v_scope)<>'object' then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','responsibility_scope_must_be_object','canPromote',false); end if;
  if jsonb_typeof(coalesce(v_candidate.semantic_payload->'permittedOperations','[]'::jsonb))<>'array' then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','permitted_operations_must_be_array','canPromote',false); end if;

  select array_agg(distinct btrim(value) order by btrim(value)) into v_operations
  from jsonb_array_elements_text(coalesce(v_candidate.semantic_payload->'permittedOperations','[]'::jsonb)) value
  where btrim(value)<>'';
  if coalesce(cardinality(v_operations),0)=0 then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','permitted_operations_required','canPromote',false); end if;

  v_sponsor_person:=atlas.implementation_verified_setup_sponsor_person_v1(v_candidate.implementation_case_id);
  if v_sponsor_person is null then return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','verified_setup_sponsor_reality_person_required','canPromote',false); end if;

  select * into v_existing
  from reality.responsibility_relations relation
  where relation.carrier_person_entity_id=v_carrier
    and relation.responsibility_key=v_key
    and relation.relation_state='active'
    and relation.jurisdiction_kind='entity'
    and relation.jurisdiction_entity_id=v_jurisdiction
    and relation.began_at<=now()
    and relation.ended_at is null
  order by relation.began_at desc,relation.id
  limit 1;

  if v_existing.id is not null then
    if v_existing.permitted_operations @> v_operations and v_existing.scope @> v_scope then
      return jsonb_build_object(
        'ok',true,'candidateId',v_candidate.id,'state','ready','canPromote',true,'mode','reuse_existing',
        'setupSponsorPersonEntityId',v_sponsor_person,
        'responsibility',jsonb_build_object('id',v_existing.id,'carrierPersonEntityId',v_carrier,'responsibilityKey',v_existing.responsibility_key,'jurisdictionEntityId',v_jurisdiction,'permittedOperations',to_jsonb(v_existing.permitted_operations),'scope',v_existing.scope)
      );
    end if;
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'state','responsibility_scope_conflict','canPromote',false,
      'existingResponsibilityId',v_existing.id,'existingPermittedOperations',to_jsonb(v_existing.permitted_operations),'existingScope',v_existing.scope
    );
  end if;

  return jsonb_build_object(
    'ok',true,'candidateId',v_candidate.id,'state','ready','canPromote',true,'mode','create_responsibility',
    'setupSponsorPersonEntityId',v_sponsor_person,
    'responsibility',jsonb_build_object(
      'carrierPersonEntity',jsonb_build_object('id',v_carrier_entity.id,'displayName',v_carrier_entity.display_name),
      'responsibilityKey',v_key,'title',v_title,
      'jurisdictionEntity',jsonb_build_object('id',v_jurisdiction_entity.id,'displayName',v_jurisdiction_entity.display_name,'entityKind',v_jurisdiction_entity.entity_kind),
      'permittedOperations',to_jsonb(v_operations),'scope',v_scope
    ),
    'truthBoundary',jsonb_build_object('previewOnly',true,'responsibilityIsAuthorityNotIdentity',true,'jurisdictionIsExplicit',true)
  );
end;
$function$;

create or replace function atlas.promote_implementation_reality_responsibility_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_relation reality.responsibility_relations%rowtype;
  v_relation_id uuid;
  v_carrier uuid;
  v_jurisdiction uuid;
  v_key text;
  v_title text;
  v_operations text[];
  v_scope jsonb;
  v_sponsor_person uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select candidate.* into v_candidate
  from atlas.implementation_reality_candidates candidate
  join atlas.implementation_cases implementation_case on implementation_case.id=candidate.implementation_case_id and implementation_case.state not in ('closed','cancelled')
  where candidate.id=p_candidate_id
  for update of candidate;
  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then raise exception 'Assigned practitioner authority required.' using errcode='42501'; end if;
  if v_candidate.candidate_state='promoted' then return jsonb_build_object('ok',true,'promoted',true,'alreadyPromoted',true,'candidateId',v_candidate.id,'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,'canonicalConsequenceRef',v_candidate.canonical_consequence_ref); end if;

  v_preview:=atlas.preview_implementation_reality_responsibility_promotion_self_api_v1(v_candidate.id);
  if coalesce(v_preview->>'state','')<>'ready' then
    update atlas.implementation_reality_candidates set candidate_state=case when candidate_state='proposed' then 'unresolved' else candidate_state end,updated_at=now() where id=v_candidate.id;
    return jsonb_build_object('ok',false,'promoted',false,'candidateId',v_candidate.id,'preview',v_preview);
  end if;

  if v_preview->>'mode'='reuse_existing' then
    v_relation_id:=(v_preview->'responsibility'->>'id')::uuid;
    select * into v_relation from reality.responsibility_relations where id=v_relation_id;
  else
    v_carrier:=(v_candidate.subject_binding->>'canonicalId')::uuid;
    v_jurisdiction:=(v_candidate.object_binding->>'canonicalId')::uuid;
    v_key:=btrim(v_candidate.semantic_payload->>'responsibilityKey');
    v_title:=btrim(v_candidate.semantic_payload->>'title');
    v_scope:=coalesce(v_candidate.semantic_payload->'scope','{}'::jsonb);
    select array_agg(distinct btrim(value) order by btrim(value)) into v_operations
    from jsonb_array_elements_text(v_candidate.semantic_payload->'permittedOperations') value
    where btrim(value)<>'';
    v_sponsor_person:=atlas.implementation_verified_setup_sponsor_person_v1(v_candidate.implementation_case_id);

    insert into reality.responsibility_relations(
      carrier_person_entity_id,responsibility_key,title,relation_state,
      jurisdiction_kind,jurisdiction_entity_id,jurisdiction_domain,permitted_operations,scope,
      establishment_kind,source_person_entity_id,establishment_basis,began_at
    ) values(
      v_carrier,v_key,v_title,'active',
      'entity',v_jurisdiction,null,v_operations,v_scope,
      'implementation_setup_sponsor',v_sponsor_person,
      jsonb_build_object(
        'source','implementation_reality_candidate',
        'implementationCaseId',v_candidate.implementation_case_id,
        'realityCandidateId',v_candidate.id,
        'literalStatement',v_candidate.literal_statement,
        'evidenceRefs',v_candidate.evidence_refs,
        'candidateEstablishmentBasis',v_candidate.establishment_basis
      ),
      now()
    ) returning * into v_relation;
    v_relation_id:=v_relation.id;
  end if;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',canonical_consequence_kind='reality_responsibility_relation',canonical_consequence_ref=v_relation_id::text,
      promoted_at=now(),promoted_by_user_id=auth.uid(),
      provenance=provenance||jsonb_build_object('promotionContract','implementation_reality_responsibility_promotion_v1','promotionMode',v_preview->>'mode','promotedResponsibilityRelationId',v_relation_id),
      updated_at=now()
  where id=v_candidate.id;

  return jsonb_build_object(
    'ok',true,'promoted',true,'alreadyPromoted',false,'candidateId',v_candidate.id,
    'canonicalConsequenceKind','reality_responsibility_relation','canonicalConsequenceRef',v_relation_id::text,
    'responsibility',jsonb_build_object(
      'id',v_relation.id,'carrierPersonEntityId',v_relation.carrier_person_entity_id,'responsibilityKey',v_relation.responsibility_key,
      'title',v_relation.title,'jurisdictionEntityId',v_relation.jurisdiction_entity_id,
      'permittedOperations',to_jsonb(v_relation.permitted_operations),'scope',v_relation.scope,'relationState',v_relation.relation_state
    ),
    'truthBoundary',jsonb_build_object('candidatePreservedAsProvenance',true,'responsibilityIsAuthorityNotIdentity',true)
  );
end;
$function$;

revoke all on function atlas.implementation_verified_setup_sponsor_person_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.implementation_reality_basis_allowed_v1(jsonb) from public,anon,authenticated,service_role;
revoke all on function atlas.preview_implementation_reality_entity_promotion_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.promote_implementation_reality_entity_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.preview_implementation_reality_entity_relationship_promotion_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.promote_implementation_reality_entity_relationship_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.preview_implementation_reality_responsibility_promotion_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.promote_implementation_reality_responsibility_self_api_v1(uuid) from public,anon,service_role;

grant execute on function atlas.preview_implementation_reality_entity_promotion_self_api_v1(uuid) to authenticated;
grant execute on function atlas.promote_implementation_reality_entity_self_api_v1(uuid) to authenticated;
grant execute on function atlas.preview_implementation_reality_entity_relationship_promotion_self_api_v1(uuid) to authenticated;
grant execute on function atlas.promote_implementation_reality_entity_relationship_self_api_v1(uuid) to authenticated;
grant execute on function atlas.preview_implementation_reality_responsibility_promotion_self_api_v1(uuid) to authenticated;
grant execute on function atlas.promote_implementation_reality_responsibility_self_api_v1(uuid) to authenticated;

comment on function atlas.preview_implementation_reality_entity_promotion_self_api_v1(uuid) is
  'Read-only preview for establishing or reusing a canonical non-human Reality Entity from an Implementation Reality Candidate.';
comment on function atlas.promote_implementation_reality_entity_self_api_v1(uuid) is
  'Explicit practitioner promotion of a root Reality Entity candidate after collision checks and verified setup-sponsor proof.';
comment on function atlas.preview_implementation_reality_entity_relationship_promotion_self_api_v1(uuid) is
  'Read-only preview for a typed directional relationship between two canonical Reality Entities.';
comment on function atlas.promote_implementation_reality_entity_relationship_self_api_v1(uuid) is
  'Explicit practitioner promotion of a typed directional Reality Entity relationship.';
comment on function atlas.preview_implementation_reality_responsibility_promotion_self_api_v1(uuid) is
  'Read-only preview for explicit Person-carried authority over a canonical Reality Entity jurisdiction.';
comment on function atlas.promote_implementation_reality_responsibility_self_api_v1(uuid) is
  'Explicit practitioner promotion of a Reality responsibility relation under verified setup-sponsor authority.';
