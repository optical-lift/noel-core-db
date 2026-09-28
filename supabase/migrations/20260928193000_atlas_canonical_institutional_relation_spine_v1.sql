-- Atlas Canonical Institutional Relation Spine v1
--
-- Canonical institutional structure over Reality identities and relationships.
-- This tranche establishes relationship truth only. It does not infer execution
-- authority, Work allocation, applicability, Principal claims, or Clock admission.

create or replace function reality.normalize_institution_key_v1(p_key text)
returns text
language plpgsql
immutable
set search_path=''
as $function$
declare
  v_key text;
begin
  v_key:=lower(regexp_replace(btrim(coalesce(p_key,'')),'[^a-zA-Z0-9._-]+','_','g'));
  v_key:=regexp_replace(v_key,'(^_+|_+$)','','g');
  if v_key='' then
    raise exception 'Institution-local key is required.' using errcode='22023';
  end if;
  return v_key;
end
$function$;

revoke all on function reality.normalize_institution_key_v1(text)
  from public,anon,authenticated,service_role;


create or replace function reality.assert_canonical_entity_kind_v1(
  p_entity_id uuid,
  p_entity_kind text
)
returns void
language plpgsql
stable
set search_path=''
as $function$
declare
  v_kind text;
  v_state text;
begin
  select e.entity_kind,e.identity_state
  into v_kind,v_state
  from reality.entities e
  where e.id=p_entity_id;

  if v_kind is null then
    raise exception 'Reality Entity not found.' using errcode='P0002';
  end if;

  if v_state<>'canonical' or v_kind<>p_entity_kind then
    raise exception 'Canonical Reality Entity of kind % required.',p_entity_kind
      using errcode='23514';
  end if;
end
$function$;

revoke all on function reality.assert_canonical_entity_kind_v1(uuid,text)
  from public,anon,authenticated,service_role;


create or replace function reality.assert_institution_subject_v1(p_entity_id uuid)
returns void
language plpgsql
stable
set search_path=''
as $function$
declare
  v_kind text;
  v_state text;
begin
  select e.entity_kind,e.identity_state
  into v_kind,v_state
  from reality.entities e
  where e.id=p_entity_id;

  if v_kind is null then
    raise exception 'Institution Reality Entity not found.' using errcode='P0002';
  end if;

  if v_state<>'canonical' then
    raise exception 'Canonical institution Reality Entity required.' using errcode='23514';
  end if;

  if v_kind in ('person','position','responsibility') then
    raise exception 'Person, Position, or Responsibility cannot be the institution subject in v1.'
      using errcode='23514';
  end if;
end
$function$;

revoke all on function reality.assert_institution_subject_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function reality.resolve_institution_relation_v1(
  p_subject_entity_id uuid,
  p_relationship_kind text,
  p_object_entity_id uuid,
  p_as_of timestamptz default now()
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select er.id
  from reality.entity_relationships er
  join reality.entities s
    on s.id=er.subject_entity_id
   and s.identity_state='canonical'
  join reality.entities o
    on o.id=er.object_entity_id
   and o.identity_state='canonical'
  where er.subject_entity_id=p_subject_entity_id
    and er.relationship_kind=p_relationship_kind
    and er.object_entity_id=p_object_entity_id
    and er.relationship_state='established'
    and er.valid_from<=coalesce(p_as_of,now())
    and (er.valid_until is null or er.valid_until>coalesce(p_as_of,now()))
    and er.relationship_kind in (
      'institutional_standing',
      'institution_has_position',
      'institution_has_responsibility',
      'occupies_position',
      'position_carries_responsibility'
    )
  order by er.valid_from desc,er.id
  limit 1;
$function$;

revoke all on function reality.resolve_institution_relation_v1(uuid,text,uuid,timestamptz)
  from public,anon,authenticated,service_role;


create or replace function reality.institution_for_position_v1(
  p_position_entity_id uuid,
  p_as_of timestamptz default now()
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select er.subject_entity_id
  from reality.entity_relationships er
  join reality.entities institution
    on institution.id=er.subject_entity_id
   and institution.identity_state='canonical'
  join reality.entities position_entity
    on position_entity.id=er.object_entity_id
   and position_entity.entity_kind='position'
   and position_entity.identity_state='canonical'
  where er.object_entity_id=p_position_entity_id
    and er.relationship_kind='institution_has_position'
    and er.relationship_state='established'
    and er.valid_from<=coalesce(p_as_of,now())
    and (er.valid_until is null or er.valid_until>coalesce(p_as_of,now()))
  order by er.valid_from desc,er.id
  limit 1;
$function$;

revoke all on function reality.institution_for_position_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;


create or replace function reality.institution_for_responsibility_v1(
  p_responsibility_entity_id uuid,
  p_as_of timestamptz default now()
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select er.subject_entity_id
  from reality.entity_relationships er
  join reality.entities institution
    on institution.id=er.subject_entity_id
   and institution.identity_state='canonical'
  join reality.entities responsibility_entity
    on responsibility_entity.id=er.object_entity_id
   and responsibility_entity.entity_kind='responsibility'
   and responsibility_entity.identity_state='canonical'
  where er.object_entity_id=p_responsibility_entity_id
    and er.relationship_kind='institution_has_responsibility'
    and er.relationship_state='established'
    and er.valid_from<=coalesce(p_as_of,now())
    and (er.valid_until is null or er.valid_until>coalesce(p_as_of,now()))
  order by er.valid_from desc,er.id
  limit 1;
$function$;

revoke all on function reality.institution_for_responsibility_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;


create or replace function reality.require_institution_structure_authority_v1(
  p_actor_person_entity_id uuid,
  p_institution_entity_id uuid,
  p_operation_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_relation_id uuid;
begin
  perform reality.assert_person_entity_v1(p_actor_person_entity_id);
  perform reality.assert_institution_subject_v1(p_institution_entity_id);

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    p_actor_person_entity_id,
    'institution_structure_governance',
    p_operation_key,
    'entity',
    p_institution_entity_id,
    null,
    '{}'::jsonb
  );

  if v_relation_id is null then
    raise exception 'Institution structure authority is required for operation %.',p_operation_key
      using errcode='42501';
  end if;

  return v_relation_id;
end
$function$;

revoke all on function reality.require_institution_structure_authority_v1(uuid,uuid,text)
  from public,anon,authenticated,service_role;


create unique index reality_institutional_standing_open_key_idx
  on reality.entity_relationships(
    subject_entity_id,
    object_entity_id,
    (metadata->>'standingKey')
  )
  where relationship_kind='institutional_standing'
    and relationship_state='established'
    and valid_until is null;

create unique index reality_institution_position_open_key_idx
  on reality.entity_relationships(
    subject_entity_id,
    (metadata->>'positionKey')
  )
  where relationship_kind='institution_has_position'
    and relationship_state='established'
    and valid_until is null;

create unique index reality_position_open_scope_idx
  on reality.entity_relationships(object_entity_id)
  where relationship_kind='institution_has_position'
    and relationship_state='established'
    and valid_until is null;

create unique index reality_institution_responsibility_open_key_idx
  on reality.entity_relationships(
    subject_entity_id,
    (metadata->>'responsibilityKey')
  )
  where relationship_kind='institution_has_responsibility'
    and relationship_state='established'
    and valid_until is null;

create unique index reality_responsibility_open_scope_idx
  on reality.entity_relationships(object_entity_id)
  where relationship_kind='institution_has_responsibility'
    and relationship_state='established'
    and valid_until is null;

create unique index reality_position_appointment_open_pair_idx
  on reality.entity_relationships(subject_entity_id,object_entity_id)
  where relationship_kind='occupies_position'
    and relationship_state='established'
    and valid_until is null;

create unique index reality_position_responsibility_open_pair_idx
  on reality.entity_relationships(subject_entity_id,object_entity_id)
  where relationship_kind='position_carries_responsibility'
    and relationship_state='established'
    and valid_until is null;


create or replace function reality.guard_institution_relation_spine_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_institution uuid;
  v_other_institution uuid;
  v_key text;
  v_expected_operation text;
  v_actor uuid;
  v_authority uuid;
  v_resolved_authority uuid;
  v_operation text;
begin
  if tg_op='UPDATE'
     and old.relationship_kind not in (
       'institutional_standing',
       'institution_has_position',
       'institution_has_responsibility',
       'occupies_position',
       'position_carries_responsibility'
     )
     and new.relationship_kind not in (
       'institutional_standing',
       'institution_has_position',
       'institution_has_responsibility',
       'occupies_position',
       'position_carries_responsibility'
     ) then
    return new;
  end if;

  if new.relationship_kind not in (
    'institutional_standing',
    'institution_has_position',
    'institution_has_responsibility',
    'occupies_position',
    'position_carries_responsibility'
  ) then
    if tg_op='UPDATE' and old.relationship_kind in (
      'institutional_standing',
      'institution_has_position',
      'institution_has_responsibility',
      'occupies_position',
      'position_carries_responsibility'
    ) then
      raise exception 'Governed institutional relationship kind is immutable.' using errcode='23514';
    end if;
    return new;
  end if;

  if tg_op='UPDATE' then
    if old.relationship_kind not in (
      'institutional_standing',
      'institution_has_position',
      'institution_has_responsibility',
      'occupies_position',
      'position_carries_responsibility'
    ) then
      raise exception 'Generic relationship cannot be converted into governed institutional structure by update.'
        using errcode='23514';
    end if;

    if old.subject_entity_id is distinct from new.subject_entity_id
       or old.object_entity_id is distinct from new.object_entity_id
       or old.relationship_kind is distinct from new.relationship_kind
       or old.relationship_state is distinct from new.relationship_state
       or old.valid_from is distinct from new.valid_from
       or old.evidence is distinct from new.evidence then
      raise exception 'Institutional relationship identity and establishment evidence are immutable.'
        using errcode='23514';
    end if;

    if new.relationship_state<>'established' then
      raise exception 'Ordinary institutional history remains established; dispute/retirement requires reconciliation.'
        using errcode='23514';
    end if;

    if old.valid_until is not null then
      if new.valid_until is distinct from old.valid_until
         or new.metadata is distinct from old.metadata then
        raise exception 'Ended institutional relationship is immutable.' using errcode='23514';
      end if;
      new.updated_at:=now();
      return new;
    end if;

    if new.valid_until is null then
      if new.metadata is distinct from old.metadata then
        raise exception 'Institutional relationship metadata is immutable before ending.'
          using errcode='23514';
      end if;
      new.updated_at:=now();
      return new;
    end if;

    if new.valid_until<=old.valid_from then
      raise exception 'Institutional relationship end must be after valid_from.' using errcode='23514';
    end if;

    if (new.metadata - 'ending') is distinct from (old.metadata - 'ending')
       or jsonb_typeof(new.metadata->'ending')<>'object' then
      raise exception 'Ending may only append structured ending provenance.' using errcode='23514';
    end if;

    begin
      v_actor:=nullif(new.metadata#>>'{ending,actorPersonEntityId}','')::uuid;
      v_authority:=nullif(new.metadata#>>'{ending,authorityResponsibilityRelationId}','')::uuid;
    exception when others then
      raise exception 'Valid ending actor and authority UUIDs are required.' using errcode='22023';
    end;

    v_operation:=nullif(new.metadata#>>'{ending,operationKey}','');
    if v_actor is null or v_authority is null or v_operation<>'institution_relation.end' then
      raise exception 'Governed institutional relation ending provenance is incomplete.'
        using errcode='23514';
    end if;

    case old.relationship_kind
      when 'institutional_standing' then
        v_institution:=old.object_entity_id;
      when 'institution_has_position' then
        v_institution:=old.subject_entity_id;
      when 'institution_has_responsibility' then
        v_institution:=old.subject_entity_id;
      when 'occupies_position' then
        v_institution:=reality.institution_for_position_v1(old.object_entity_id,old.valid_from);
      when 'position_carries_responsibility' then
        v_institution:=reality.institution_for_position_v1(old.subject_entity_id,old.valid_from);
    end case;

    if v_institution is null then
      raise exception 'Institution scope cannot be resolved for relationship ending.' using errcode='23514';
    end if;

    v_resolved_authority:=reality.require_institution_structure_authority_v1(
      v_actor,v_institution,'institution_relation.end'
    );

    if v_resolved_authority is distinct from v_authority then
      raise exception 'Ending provenance does not identify the authority relation actually resolved.'
        using errcode='23514';
    end if;

    if old.relationship_kind='institution_has_position' then
      if exists(
        select 1
        from reality.entity_relationships dep
        where dep.relationship_state='established'
          and dep.relationship_kind in ('occupies_position','position_carries_responsibility')
          and (
            (dep.relationship_kind='occupies_position' and dep.object_entity_id=old.object_entity_id)
            or
            (dep.relationship_kind='position_carries_responsibility' and dep.subject_entity_id=old.object_entity_id)
          )
          and (dep.valid_until is null or dep.valid_until>new.valid_until)
      ) then
        raise exception 'Position scope cannot end before dependent appointments or responsibilities end.'
          using errcode='23514';
      end if;
    end if;

    if old.relationship_kind='institution_has_responsibility' then
      if exists(
        select 1
        from reality.entity_relationships dep
        where dep.relationship_state='established'
          and dep.relationship_kind='position_carries_responsibility'
          and dep.object_entity_id=old.object_entity_id
          and (dep.valid_until is null or dep.valid_until>new.valid_until)
      ) then
        raise exception 'Responsibility scope cannot end before dependent Position relations end.'
          using errcode='23514';
      end if;
    end if;

    new.updated_at:=now();
    return new;
  end if;

  if new.relationship_state<>'established'
     or new.valid_from is null
     or new.valid_until is not null then
    raise exception 'New institutional spine relations must begin as open established intervals.'
      using errcode='23514';
  end if;

  if jsonb_typeof(new.evidence->'establishment')<>'object' then
    raise exception 'Structured establishment evidence is required.' using errcode='23514';
  end if;

  begin
    v_actor:=nullif(new.evidence#>>'{establishment,actorPersonEntityId}','')::uuid;
    v_authority:=nullif(new.evidence#>>'{establishment,authorityResponsibilityRelationId}','')::uuid;
  exception when others then
    raise exception 'Valid establishment actor and authority UUIDs are required.' using errcode='22023';
  end;
  v_operation:=nullif(new.evidence#>>'{establishment,operationKey}','');

  if v_actor is null or v_authority is null or v_operation is null then
    raise exception 'Institutional establishment provenance is incomplete.' using errcode='23514';
  end if;

  case new.relationship_kind
    when 'institutional_standing' then
      perform reality.assert_person_entity_v1(new.subject_entity_id);
      perform reality.assert_institution_subject_v1(new.object_entity_id);
      v_institution:=new.object_entity_id;
      v_expected_operation:='institutional_standing.establish';
      v_key:=reality.normalize_institution_key_v1(new.metadata->>'standingKey');
      if new.metadata->>'standingKey'<>v_key then
        raise exception 'standingKey must be normalized.' using errcode='23514';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institutional_standing'
          and er.relationship_state='established'
          and er.subject_entity_id=new.subject_entity_id
          and er.object_entity_id=new.object_entity_id
          and er.metadata->>'standingKey'=v_key
          and coalesce(er.valid_until,'infinity'::timestamptz)>new.valid_from
      ) then
        raise exception 'Institutional standing interval overlaps existing standing.' using errcode='23505';
      end if;

    when 'institution_has_position' then
      perform reality.assert_institution_subject_v1(new.subject_entity_id);
      perform reality.assert_canonical_entity_kind_v1(new.object_entity_id,'position');
      v_institution:=new.subject_entity_id;
      v_expected_operation:='institution_position.establish';
      v_key:=reality.normalize_institution_key_v1(new.metadata->>'positionKey');
      if new.metadata->>'positionKey'<>v_key then
        raise exception 'positionKey must be normalized.' using errcode='23514';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institution_has_position'
          and er.relationship_state='established'
          and er.object_entity_id=new.object_entity_id
          and er.subject_entity_id<>new.subject_entity_id
      ) then
        raise exception 'Position identity cannot move between institutions.' using errcode='23514';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institution_has_position'
          and er.relationship_state='established'
          and er.subject_entity_id=new.subject_entity_id
          and er.metadata->>'positionKey'=v_key
          and er.object_entity_id<>new.object_entity_id
      ) then
        raise exception 'Position key already identifies another Position in this institution.'
          using errcode='23505';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institution_has_position'
          and er.relationship_state='established'
          and er.object_entity_id=new.object_entity_id
          and coalesce(er.valid_until,'infinity'::timestamptz)>new.valid_from
      ) then
        raise exception 'Position scope interval overlaps existing scope.' using errcode='23505';
      end if;

    when 'institution_has_responsibility' then
      perform reality.assert_institution_subject_v1(new.subject_entity_id);
      perform reality.assert_canonical_entity_kind_v1(new.object_entity_id,'responsibility');
      v_institution:=new.subject_entity_id;
      v_expected_operation:='institution_responsibility.establish';
      v_key:=reality.normalize_institution_key_v1(new.metadata->>'responsibilityKey');
      if new.metadata->>'responsibilityKey'<>v_key then
        raise exception 'responsibilityKey must be normalized.' using errcode='23514';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institution_has_responsibility'
          and er.relationship_state='established'
          and er.object_entity_id=new.object_entity_id
          and er.subject_entity_id<>new.subject_entity_id
      ) then
        raise exception 'Responsibility identity cannot move between institutions.' using errcode='23514';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institution_has_responsibility'
          and er.relationship_state='established'
          and er.subject_entity_id=new.subject_entity_id
          and er.metadata->>'responsibilityKey'=v_key
          and er.object_entity_id<>new.object_entity_id
      ) then
        raise exception 'Responsibility key already identifies another Responsibility in this institution.'
          using errcode='23505';
      end if;
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='institution_has_responsibility'
          and er.relationship_state='established'
          and er.object_entity_id=new.object_entity_id
          and coalesce(er.valid_until,'infinity'::timestamptz)>new.valid_from
      ) then
        raise exception 'Responsibility scope interval overlaps existing scope.' using errcode='23505';
      end if;

    when 'occupies_position' then
      perform reality.assert_person_entity_v1(new.subject_entity_id);
      perform reality.assert_canonical_entity_kind_v1(new.object_entity_id,'position');
      v_institution:=reality.institution_for_position_v1(new.object_entity_id,new.valid_from);
      if v_institution is null then
        raise exception 'Position must belong to an effective institution before appointment.'
          using errcode='23514';
      end if;
      v_expected_operation:='position_appointment.establish';
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='occupies_position'
          and er.relationship_state='established'
          and er.subject_entity_id=new.subject_entity_id
          and er.object_entity_id=new.object_entity_id
          and coalesce(er.valid_until,'infinity'::timestamptz)>new.valid_from
      ) then
        raise exception 'Position appointment interval overlaps existing appointment.' using errcode='23505';
      end if;

    when 'position_carries_responsibility' then
      perform reality.assert_canonical_entity_kind_v1(new.subject_entity_id,'position');
      perform reality.assert_canonical_entity_kind_v1(new.object_entity_id,'responsibility');
      v_institution:=reality.institution_for_position_v1(new.subject_entity_id,new.valid_from);
      v_other_institution:=reality.institution_for_responsibility_v1(new.object_entity_id,new.valid_from);
      if v_institution is null or v_other_institution is null or v_institution<>v_other_institution then
        raise exception 'Position and Responsibility must be effective in the same institution.'
          using errcode='23514';
      end if;
      v_expected_operation:='position_responsibility.establish';
      if exists(
        select 1
        from reality.entity_relationships er
        where er.relationship_kind='position_carries_responsibility'
          and er.relationship_state='established'
          and er.subject_entity_id=new.subject_entity_id
          and er.object_entity_id=new.object_entity_id
          and coalesce(er.valid_until,'infinity'::timestamptz)>new.valid_from
      ) then
        raise exception 'Position Responsibility interval overlaps existing relation.' using errcode='23505';
      end if;
  end case;

  if v_operation<>v_expected_operation then
    raise exception 'Establishment operation % does not match relationship family %.',
      v_operation,new.relationship_kind using errcode='23514';
  end if;

  v_resolved_authority:=reality.require_institution_structure_authority_v1(
    v_actor,v_institution,v_expected_operation
  );

  if v_resolved_authority is distinct from v_authority then
    raise exception 'Establishment provenance does not identify the authority relation actually resolved.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger reality_institution_relation_spine_guard_v1
before insert or update on reality.entity_relationships
for each row execute function reality.guard_institution_relation_spine_v1();

revoke all on function reality.guard_institution_relation_spine_v1()
  from public,anon,authenticated,service_role;


create or replace function atlas.establish_institutional_standing_api_v1(
  p_institution_entity_id uuid,
  p_person_entity_id uuid,
  p_standing_key text,
  p_standing_label text default null,
  p_basis jsonb default '{}'::jsonb,
  p_valid_from timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid;
  v_authority uuid;
  v_key text;
  v_from timestamptz:=coalesce(p_valid_from,now());
  v_relation_id uuid;
  v_metadata jsonb;
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

  perform reality.assert_institution_subject_v1(p_institution_entity_id);
  perform reality.assert_person_entity_v1(p_person_entity_id);
  v_key:=reality.normalize_institution_key_v1(p_standing_key);
  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,p_institution_entity_id,'institutional_standing.establish'
  );

  select er.id into v_relation_id
  from reality.entity_relationships er
  where er.relationship_kind='institutional_standing'
    and er.relationship_state='established'
    and er.subject_entity_id=p_person_entity_id
    and er.object_entity_id=p_institution_entity_id
    and er.metadata->>'standingKey'=v_key
    and er.valid_from<=v_from
    and (er.valid_until is null or er.valid_until>v_from)
  order by er.valid_from desc,er.id
  limit 1;

  if v_relation_id is not null then
    return jsonb_build_object(
      'contractVersion','institutional_standing_establish_v1',
      'relationId',v_relation_id,
      'created',false,
      'personEntityId',p_person_entity_id,
      'institutionEntityId',p_institution_entity_id,
      'standingKey',v_key,
      'executionAuthorityCreated',false
    );
  end if;

  v_metadata:=jsonb_build_object('standingKey',v_key);
  if nullif(btrim(coalesce(p_standing_label,'')),'') is not null then
    v_metadata:=v_metadata || jsonb_build_object('standingLabel',btrim(p_standing_label));
  end if;

  insert into reality.entity_relationships(
    subject_entity_id,relationship_kind,object_entity_id,relationship_state,
    valid_from,evidence,metadata
  ) values (
    p_person_entity_id,'institutional_standing',p_institution_entity_id,'established',
    v_from,
    jsonb_build_object('establishment',jsonb_build_object(
      'actorPersonEntityId',v_actor,
      'authorityResponsibilityRelationId',v_authority,
      'operationKey','institutional_standing.establish',
      'basis',coalesce(p_basis,'{}'::jsonb)
    )),
    v_metadata
  ) returning id into v_relation_id;

  return jsonb_build_object(
    'contractVersion','institutional_standing_establish_v1',
    'relationId',v_relation_id,
    'created',true,
    'personEntityId',p_person_entity_id,
    'institutionEntityId',p_institution_entity_id,
    'standingKey',v_key,
    'executionAuthorityCreated',false
  );
end
$function$;

revoke all on function atlas.establish_institutional_standing_api_v1(
  uuid,uuid,text,text,jsonb,timestamptz
) from public,anon,service_role;
grant execute on function atlas.establish_institutional_standing_api_v1(
  uuid,uuid,text,text,jsonb,timestamptz
) to authenticated;


create or replace function atlas.establish_institution_position_api_v1(
  p_institution_entity_id uuid,
  p_position_key text,
  p_title text,
  p_basis jsonb default '{}'::jsonb,
  p_valid_from timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid;
  v_authority uuid;
  v_key text;
  v_title text:=nullif(btrim(coalesce(p_title,'')),'');
  v_from timestamptz:=coalesce(p_valid_from,now());
  v_stable_key text;
  v_position_id uuid;
  v_relation_id uuid;
  v_created_entity boolean:=false;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  if v_actor is null then
    raise exception 'Canonical Reality Person binding required.' using errcode='42501';
  end if;
  if v_title is null then
    raise exception 'Position title is required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_basis,'{}'::jsonb))<>'object' then
    raise exception 'basis must be an object.' using errcode='22023';
  end if;

  perform reality.assert_institution_subject_v1(p_institution_entity_id);
  v_key:=reality.normalize_institution_key_v1(p_position_key);
  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,p_institution_entity_id,'institution_position.establish'
  );
  v_stable_key:='institution_position:'||p_institution_entity_id::text||':'||v_key;

  insert into reality.entities(stable_key,entity_kind,display_name,metadata)
  values(
    v_stable_key,'position',v_title,
    jsonb_build_object('institutionEntityId',p_institution_entity_id,'positionKey',v_key)
  )
  on conflict(stable_key) do nothing
  returning id into v_position_id;

  if v_position_id is not null then
    v_created_entity:=true;
  else
    select e.id into v_position_id
    from reality.entities e
    where e.stable_key=v_stable_key;
  end if;

  perform reality.assert_canonical_entity_kind_v1(v_position_id,'position');

  select er.id into v_relation_id
  from reality.entity_relationships er
  where er.relationship_kind='institution_has_position'
    and er.relationship_state='established'
    and er.subject_entity_id=p_institution_entity_id
    and er.object_entity_id=v_position_id
    and er.metadata->>'positionKey'=v_key
    and er.valid_from<=v_from
    and (er.valid_until is null or er.valid_until>v_from)
  order by er.valid_from desc,er.id
  limit 1;

  if v_relation_id is null then
    insert into reality.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,relationship_state,
      valid_from,evidence,metadata
    ) values (
      p_institution_entity_id,'institution_has_position',v_position_id,'established',
      v_from,
      jsonb_build_object('establishment',jsonb_build_object(
        'actorPersonEntityId',v_actor,
        'authorityResponsibilityRelationId',v_authority,
        'operationKey','institution_position.establish',
        'basis',coalesce(p_basis,'{}'::jsonb)
      )),
      jsonb_build_object('positionKey',v_key)
    ) returning id into v_relation_id;
  end if;

  return jsonb_build_object(
    'contractVersion','institution_position_establish_v1',
    'positionEntityId',v_position_id,
    'relationId',v_relation_id,
    'positionKey',v_key,
    'entityCreated',v_created_entity,
    'executionAuthorityCreated',false
  );
end
$function$;

revoke all on function atlas.establish_institution_position_api_v1(
  uuid,text,text,jsonb,timestamptz
) from public,anon,service_role;
grant execute on function atlas.establish_institution_position_api_v1(
  uuid,text,text,jsonb,timestamptz
) to authenticated;


create or replace function atlas.establish_institution_responsibility_api_v1(
  p_institution_entity_id uuid,
  p_responsibility_key text,
  p_title text,
  p_basis jsonb default '{}'::jsonb,
  p_valid_from timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid;
  v_authority uuid;
  v_key text;
  v_title text:=nullif(btrim(coalesce(p_title,'')),'');
  v_from timestamptz:=coalesce(p_valid_from,now());
  v_stable_key text;
  v_responsibility_id uuid;
  v_relation_id uuid;
  v_created_entity boolean:=false;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  if v_actor is null then
    raise exception 'Canonical Reality Person binding required.' using errcode='42501';
  end if;
  if v_title is null then
    raise exception 'Responsibility title is required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_basis,'{}'::jsonb))<>'object' then
    raise exception 'basis must be an object.' using errcode='22023';
  end if;

  perform reality.assert_institution_subject_v1(p_institution_entity_id);
  v_key:=reality.normalize_institution_key_v1(p_responsibility_key);
  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,p_institution_entity_id,'institution_responsibility.establish'
  );
  v_stable_key:='institution_responsibility:'||p_institution_entity_id::text||':'||v_key;

  insert into reality.entities(stable_key,entity_kind,display_name,metadata)
  values(
    v_stable_key,'responsibility',v_title,
    jsonb_build_object('institutionEntityId',p_institution_entity_id,'responsibilityKey',v_key)
  )
  on conflict(stable_key) do nothing
  returning id into v_responsibility_id;

  if v_responsibility_id is not null then
    v_created_entity:=true;
  else
    select e.id into v_responsibility_id
    from reality.entities e
    where e.stable_key=v_stable_key;
  end if;

  perform reality.assert_canonical_entity_kind_v1(v_responsibility_id,'responsibility');

  select er.id into v_relation_id
  from reality.entity_relationships er
  where er.relationship_kind='institution_has_responsibility'
    and er.relationship_state='established'
    and er.subject_entity_id=p_institution_entity_id
    and er.object_entity_id=v_responsibility_id
    and er.metadata->>'responsibilityKey'=v_key
    and er.valid_from<=v_from
    and (er.valid_until is null or er.valid_until>v_from)
  order by er.valid_from desc,er.id
  limit 1;

  if v_relation_id is null then
    insert into reality.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,relationship_state,
      valid_from,evidence,metadata
    ) values (
      p_institution_entity_id,'institution_has_responsibility',v_responsibility_id,'established',
      v_from,
      jsonb_build_object('establishment',jsonb_build_object(
        'actorPersonEntityId',v_actor,
        'authorityResponsibilityRelationId',v_authority,
        'operationKey','institution_responsibility.establish',
        'basis',coalesce(p_basis,'{}'::jsonb)
      )),
      jsonb_build_object('responsibilityKey',v_key)
    ) returning id into v_relation_id;
  end if;

  return jsonb_build_object(
    'contractVersion','institution_responsibility_establish_v1',
    'responsibilityEntityId',v_responsibility_id,
    'relationId',v_relation_id,
    'responsibilityKey',v_key,
    'entityCreated',v_created_entity,
    'executionAuthorityCreated',false
  );
end
$function$;

revoke all on function atlas.establish_institution_responsibility_api_v1(
  uuid,text,text,jsonb,timestamptz
) from public,anon,service_role;
grant execute on function atlas.establish_institution_responsibility_api_v1(
  uuid,text,text,jsonb,timestamptz
) to authenticated;


create or replace function atlas.establish_position_appointment_api_v1(
  p_position_entity_id uuid,
  p_person_entity_id uuid,
  p_basis jsonb default '{}'::jsonb,
  p_valid_from timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid;
  v_authority uuid;
  v_institution uuid;
  v_from timestamptz:=coalesce(p_valid_from,now());
  v_relation_id uuid;
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

  perform reality.assert_canonical_entity_kind_v1(p_position_entity_id,'position');
  perform reality.assert_person_entity_v1(p_person_entity_id);
  v_institution:=reality.institution_for_position_v1(p_position_entity_id,v_from);
  if v_institution is null then
    raise exception 'Position has no effective institutional scope at appointment time.'
      using errcode='23514';
  end if;
  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,v_institution,'position_appointment.establish'
  );

  select er.id into v_relation_id
  from reality.entity_relationships er
  where er.relationship_kind='occupies_position'
    and er.relationship_state='established'
    and er.subject_entity_id=p_person_entity_id
    and er.object_entity_id=p_position_entity_id
    and er.valid_from<=v_from
    and (er.valid_until is null or er.valid_until>v_from)
  order by er.valid_from desc,er.id
  limit 1;

  if v_relation_id is null then
    insert into reality.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,relationship_state,
      valid_from,evidence,metadata
    ) values (
      p_person_entity_id,'occupies_position',p_position_entity_id,'established',
      v_from,
      jsonb_build_object('establishment',jsonb_build_object(
        'actorPersonEntityId',v_actor,
        'authorityResponsibilityRelationId',v_authority,
        'operationKey','position_appointment.establish',
        'basis',coalesce(p_basis,'{}'::jsonb)
      )),
      '{}'::jsonb
    ) returning id into v_relation_id;
  end if;

  return jsonb_build_object(
    'contractVersion','position_appointment_establish_v1',
    'relationId',v_relation_id,
    'personEntityId',p_person_entity_id,
    'positionEntityId',p_position_entity_id,
    'institutionEntityId',v_institution,
    'executionAuthorityCreated',false
  );
end
$function$;

revoke all on function atlas.establish_position_appointment_api_v1(
  uuid,uuid,jsonb,timestamptz
) from public,anon,service_role;
grant execute on function atlas.establish_position_appointment_api_v1(
  uuid,uuid,jsonb,timestamptz
) to authenticated;


create or replace function atlas.establish_position_responsibility_api_v1(
  p_position_entity_id uuid,
  p_responsibility_entity_id uuid,
  p_basis jsonb default '{}'::jsonb,
  p_valid_from timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_actor uuid;
  v_authority uuid;
  v_institution uuid;
  v_responsibility_institution uuid;
  v_from timestamptz:=coalesce(p_valid_from,now());
  v_relation_id uuid;
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

  perform reality.assert_canonical_entity_kind_v1(p_position_entity_id,'position');
  perform reality.assert_canonical_entity_kind_v1(p_responsibility_entity_id,'responsibility');
  v_institution:=reality.institution_for_position_v1(p_position_entity_id,v_from);
  v_responsibility_institution:=reality.institution_for_responsibility_v1(
    p_responsibility_entity_id,v_from
  );
  if v_institution is null or v_responsibility_institution is null
     or v_institution<>v_responsibility_institution then
    raise exception 'Position and Responsibility must be effective in the same institution.'
      using errcode='23514';
  end if;
  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,v_institution,'position_responsibility.establish'
  );

  select er.id into v_relation_id
  from reality.entity_relationships er
  where er.relationship_kind='position_carries_responsibility'
    and er.relationship_state='established'
    and er.subject_entity_id=p_position_entity_id
    and er.object_entity_id=p_responsibility_entity_id
    and er.valid_from<=v_from
    and (er.valid_until is null or er.valid_until>v_from)
  order by er.valid_from desc,er.id
  limit 1;

  if v_relation_id is null then
    insert into reality.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,relationship_state,
      valid_from,evidence,metadata
    ) values (
      p_position_entity_id,'position_carries_responsibility',p_responsibility_entity_id,'established',
      v_from,
      jsonb_build_object('establishment',jsonb_build_object(
        'actorPersonEntityId',v_actor,
        'authorityResponsibilityRelationId',v_authority,
        'operationKey','position_responsibility.establish',
        'basis',coalesce(p_basis,'{}'::jsonb)
      )),
      '{}'::jsonb
    ) returning id into v_relation_id;
  end if;

  return jsonb_build_object(
    'contractVersion','position_responsibility_establish_v1',
    'relationId',v_relation_id,
    'positionEntityId',p_position_entity_id,
    'responsibilityEntityId',p_responsibility_entity_id,
    'institutionEntityId',v_institution,
    'executionAuthorityCreated',false
  );
end
$function$;

revoke all on function atlas.establish_position_responsibility_api_v1(
  uuid,uuid,jsonb,timestamptz
) from public,anon,service_role;
grant execute on function atlas.establish_position_responsibility_api_v1(
  uuid,uuid,jsonb,timestamptz
) to authenticated;


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

  if v_relation.valid_until is not null then
    return jsonb_build_object(
      'contractVersion','institution_relation_end_v1',
      'relationId',v_relation.id,
      'changed',false,
      'validUntil',v_relation.valid_until,
      'relationshipKind',v_relation.relationship_kind
    );
  end if;

  if v_until<=v_relation.valid_from then
    raise exception 'valid_until must be after valid_from.' using errcode='22023';
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

  v_authority:=reality.require_institution_structure_authority_v1(
    v_actor,v_institution,'institution_relation.end'
  );

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


insert into atlas.workbench_operation_registry(
  operation_key,route_class,destination_membrane,destination_operation,
  requires_destination_input,requires_operation_contract,truth_boundary
) values
(
  'establish.institutional_standing','ESTABLISH','reality.institutional_structure','institutional_standing.establish',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"workbenchAuthorityDoesNotGrantInstitutionAuthority":true,"standingDoesNotGrantExecutionAuthority":true}'::jsonb
),
(
  'establish.institution_position','ESTABLISH','reality.institutional_structure','institution_position.establish',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"positionIsRealityIdentity":true,"positionDoesNotGrantExecutionAuthority":true}'::jsonb
),
(
  'establish.institution_responsibility','ESTABLISH','reality.institutional_structure','institution_responsibility.establish',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"responsibilityDefinitionIsNotExecutionAuthority":true}'::jsonb
),
(
  'establish.position_appointment','ESTABLISH','reality.institutional_structure','position_appointment.establish',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"appointmentDoesNotGrantExecutionAuthority":true,"targetPersonAuthRequired":false}'::jsonb
),
(
  'establish.position_responsibility','ESTABLISH','reality.institutional_structure','position_responsibility.establish',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"positionResponsibilityDoesNotMintResponsibilityRelation":true}'::jsonb
),
(
  'establish.institution_relation_end','ESTABLISH','reality.institutional_structure','institution_relation.end',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"historyIsPreserved":true,"normalEndingDoesNotRetireTruth":true}'::jsonb
)
on conflict(operation_key) do nothing;


comment on function reality.resolve_institution_relation_v1(uuid,text,uuid,timestamptz) is
  'Resolves one exact effective canonical institutional relation as_of a supplied coordinate. It grants no execution authority.';

comment on function atlas.establish_position_appointment_api_v1(uuid,uuid,jsonb,timestamptz) is
  'Establishes Person occupies Position under exact institution-structure authority. Target Person does not need an Auth account; appointment grants no execution authority.';

comment on function atlas.establish_position_responsibility_api_v1(uuid,uuid,jsonb,timestamptz) is
  'Establishes Position carries Responsibility definition. This does not create or imply reality.responsibility_relations execution authority.';
