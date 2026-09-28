-- Atlas Canonical Institutional Relation Spine v1 hardening
--
-- Tightens canonical target identity, durable Position/Responsibility scoping,
-- audit-coordinate immutability, and idempotent end-operation authorization.

create or replace function reality.guard_institution_relation_spine_hardening_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if new.relationship_kind not in (
    'institutional_standing',
    'institution_has_position',
    'institution_has_responsibility',
    'occupies_position',
    'position_carries_responsibility'
  ) then
    return new;
  end if;

  if tg_op='UPDATE' and old.created_at is distinct from new.created_at then
    raise exception 'Institutional relationship created_at is immutable.' using errcode='23514';
  end if;

  if new.relationship_kind in ('institutional_standing','occupies_position') then
    perform reality.assert_canonical_entity_kind_v1(new.subject_entity_id,'person');
  end if;

  if new.relationship_kind='institution_has_position' then
    perform reality.assert_canonical_entity_kind_v1(new.object_entity_id,'position');

    if exists(
      select 1
      from reality.entity_relationships er
      where er.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
        and er.relationship_kind='institution_has_position'
        and er.relationship_state='established'
        and er.object_entity_id=new.object_entity_id
        and er.metadata->>'positionKey' is distinct from new.metadata->>'positionKey'
    ) then
      raise exception 'Position identity cannot change its institution-local positionKey across history.'
        using errcode='23514';
    end if;
  end if;

  if new.relationship_kind='institution_has_responsibility' then
    perform reality.assert_canonical_entity_kind_v1(new.object_entity_id,'responsibility');

    if exists(
      select 1
      from reality.entity_relationships er
      where er.id<>coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
        and er.relationship_kind='institution_has_responsibility'
        and er.relationship_state='established'
        and er.object_entity_id=new.object_entity_id
        and er.metadata->>'responsibilityKey' is distinct from new.metadata->>'responsibilityKey'
    ) then
      raise exception 'Responsibility identity cannot change its institution-local responsibilityKey across history.'
        using errcode='23514';
    end if;
  end if;

  return new;
end
$function$;

create trigger reality_institution_relation_spine_hardening_v1
before insert or update on reality.entity_relationships
for each row execute function reality.guard_institution_relation_spine_hardening_v1();

revoke all on function reality.guard_institution_relation_spine_hardening_v1()
  from public,anon,authenticated,service_role;


create or replace function atlas.end_institution_relation_api_v1(
  p_relationship_id uuid,
  p_basis jsonb default '{}'::jsonb,
  p_valid_until timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid;
  v_authority uuid;
  v_relation reality.entity_relationships%rowtype;
  v_institution uuid;
  v_until timestamptz:=coalesce(p_valid_until,now());
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  if v_actor is null then
    raise exception 'Canonical Reality Person binding required.' using errcode='42501';
  end if;
  if jsonb_typeof(coalesce(p_basis,'{}'::jsonb))<>'object' then
    raise exception 'basis must be an object.' using errcode='22023';
  end if;

  select er.* into v_relation
  from reality.entity_relationships er
  where er.id=p_relationship_id
  for update;

  if v_relation.id is null then
    raise exception 'Institutional relationship not found.' using errcode='P0002';
  end if;
  if v_relation.relationship_kind not in (
    'institutional_standing',
    'institution_has_position',
    'institution_has_responsibility',
    'occupies_position',
    'position_carries_responsibility'
  ) or v_relation.relationship_state<>'established' then
    raise exception 'Relationship is not governed by the institutional relation spine.'
      using errcode='23514';
  end if;

  case v_relation.relationship_kind
    when 'institutional_standing' then
      v_institution:=v_relation.object_entity_id;
    when 'institution_has_position' then
      v_institution:=v_relation.subject_entity_id;
    when 'institution_has_responsibility' then
      v_institution:=v_relation.subject_entity_id;
    when 'occupies_position' then
      v_institution:=reality.institution_for_position_v1(
        v_relation.object_entity_id,v_relation.valid_from
      );
    when 'position_carries_responsibility' then
      v_institution:=reality.institution_for_position_v1(
        v_relation.subject_entity_id,v_relation.valid_from
      );
  end case;

  if v_institution is null then
    raise exception 'Institution scope cannot be resolved for relationship.' using errcode='23514';
  end if;

  -- Authorization is required even for an idempotent replay. Knowing a relation ID
  -- must not become a read side-channel for callers without institution authority.
  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,v_institution,'institution_relation.end'
  );

  if v_relation.valid_until is not null then
    return jsonb_build_object(
      'contractVersion','institution_relation_end_v1',
      'relationId',v_relation.id,
      'changed',false,
      'validUntil',v_relation.valid_until,
      'relationshipKind',v_relation.relationship_kind,
      'institutionEntityId',v_institution
    );
  end if;

  if v_until<=v_relation.valid_from then
    raise exception 'valid_until must be after valid_from.' using errcode='22023';
  end if;

  update reality.entity_relationships
  set valid_until=v_until,
      metadata=metadata || jsonb_build_object(
        'ending',jsonb_build_object(
          'actorPersonEntityId',v_actor,
          'authorityResponsibilityRelationId',v_authority,
          'operationKey','institution_relation.end',
          'basis',coalesce(p_basis,'{}'::jsonb)
        )
      )
  where id=v_relation.id;

  return jsonb_build_object(
    'contractVersion','institution_relation_end_v1',
    'relationId',v_relation.id,
    'changed',true,
    'validUntil',v_until,
    'relationshipKind',v_relation.relationship_kind,
    'institutionEntityId',v_institution
  );
end
$function$;

revoke all on function atlas.end_institution_relation_api_v1(
  uuid,jsonb,timestamptz
) from public,anon,service_role;
grant execute on function atlas.end_institution_relation_api_v1(
  uuid,jsonb,timestamptz
) to authenticated;
