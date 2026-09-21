-- Atlas Reality Sentence Establishment Kernel v1
-- EXECUTABLE ARCHITECTURE CANDIDATE ONLY.
-- Intentionally outside supabase/migrations/. Do not apply directly.
-- Product authority: PMD-025 / IMPLEMENTATION-REALITY-AUTHORING-CONTRACT.md
-- Dependency: atlas_institutional_person_record_v1 must be live before release.

begin;

-- Existing Implementation establishment custody becomes the candidate shell.
alter table atlas.implementation_establishment_items
  drop constraint implementation_establishment_items_category_check;

alter table atlas.implementation_establishment_items
  add constraint implementation_establishment_items_category_check
  check (category in (
    'institution','ledger_scope','people_authority','implementation_authority',
    'boundary','unresolved','reality_sentence'
  ));

alter table atlas.implementation_establishment_items
  add column source_finding_id uuid references atlas.implementation_findings(id) on delete set null,
  add column reality_operation_key text,
  add column semantic_bindings jsonb,
  add column resolution_state text,
  add column canonical_consequence jsonb,
  add column established_by_user_id uuid references auth.users(id) on delete restrict,
  add column established_at timestamptz;

alter table atlas.implementation_establishment_items
  add constraint implementation_reality_bindings_object_check
    check (semantic_bindings is null or jsonb_typeof(semantic_bindings)='object'),
  add constraint implementation_reality_consequence_object_check
    check (canonical_consequence is null or jsonb_typeof(canonical_consequence)='object'),
  add constraint implementation_reality_resolution_state_check
    check (
      resolution_state is null or resolution_state in (
        'draft','ready','unresolved_identity','unsupported_operation',
        'missing_required_binding','requires_principal_self_establishment',
        'implementation_scope_unbound','outside_implementation_scope',
        'canonical_conflict','prerequisite_not_live','established','superseded'
      )
    );

create index implementation_reality_sentence_case_idx
  on atlas.implementation_establishment_items(
    implementation_case_id,status,created_at,id
  )
  where category='reality_sentence';

create or replace function atlas.guard_implementation_reality_sentence_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.category<>'reality_sentence' then return new; end if;

  if nullif(btrim(coalesce(new.reality_operation_key,'')),'') is null then
    raise exception 'Reality Sentence requires an establishment operation key.'
      using errcode='23514';
  end if;
  if new.semantic_bindings is null or jsonb_typeof(new.semantic_bindings)<>'object' then
    raise exception 'Reality Sentence requires structured semantic bindings.'
      using errcode='23514';
  end if;

  if new.status='established' then
    if new.resolution_state<>'established'
       or coalesce(new.canonical_consequence,'{}'::jsonb)='{}'::jsonb
       or new.established_by_user_id is null
       or new.established_at is null then
      raise exception 'Established Reality Sentence requires canonical consequence receipt.'
        using errcode='23514';
    end if;
  elsif new.canonical_consequence is not null
     or new.established_by_user_id is not null
     or new.established_at is not null then
    raise exception 'Unestablished Reality Sentence cannot carry canonical consequence.'
      using errcode='23514';
  end if;

  if tg_op='UPDATE' and old.category='reality_sentence' and old.status='established' then
    if new.status not in ('established','superseded') then
      raise exception 'Established Reality Sentence may only remain established or be superseded.'
        using errcode='23514';
    end if;
    if new.reality_operation_key is distinct from old.reality_operation_key
       or new.semantic_bindings is distinct from old.semantic_bindings
       or new.canonical_consequence is distinct from old.canonical_consequence
       or new.established_by_user_id is distinct from old.established_by_user_id
       or new.established_at is distinct from old.established_at then
      raise exception 'Established Reality Sentence provenance is immutable.'
        using errcode='23514';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;

revoke all on function atlas.guard_implementation_reality_sentence_v1()
  from public,anon,authenticated,service_role;

create trigger implementation_reality_sentence_guard_v1
before insert or update on atlas.implementation_establishment_items
for each row execute function atlas.guard_implementation_reality_sentence_v1();

-- One command universe. This is command metadata, not truth data.
create or replace function atlas.reality_establishment_registry_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
select jsonb_build_object(
  'contractVersion','reality_establishment_registry_v1',
  'operations',jsonb_build_array(
    jsonb_build_object(
      'operationKey','organization.establish.v1',
      'executionClass','principal_self',
      'owningDomain','organization_ledger',
      'canonicalCommand','establish_organization_ledger_self_api_v1',
      'consequenceKind','organization_ledger',
      'renderGrammar','{Organization} exists.'
    ),
    jsonb_build_object(
      'operationKey','organization_unit.establish.v1',
      'executionClass','implementation_practitioner',
      'owningDomain','organization_structure',
      'canonicalCommand','establish_organization_unit_internal_v1',
      'consequenceKind','organization_unit',
      'renderGrammar','{Organization} has {Organization Unit}.'
    ),
    jsonb_build_object(
      'operationKey','institutional_person.establish.v1',
      'executionClass','implementation_practitioner',
      'owningDomain','person_institution_relationship',
      'canonicalCommand','establish_institutional_person_record_internal_v1',
      'consequenceKind','institutional_person_record',
      'renderGrammar','{Person} is known to {Organization}.'
    ),
    jsonb_build_object(
      'operationKey','organization_position.establish.v1',
      'executionClass','implementation_practitioner',
      'owningDomain','organization_structure',
      'canonicalCommand','establish_organization_position_internal_v1',
      'consequenceKind','organization_position',
      'renderGrammar','{Position} exists in {Organization Unit}.'
    ),
    jsonb_build_object(
      'operationKey','organization_responsibility.establish.v1',
      'executionClass','implementation_practitioner',
      'owningDomain','organization_structure',
      'canonicalCommand','establish_organization_responsibility_internal_v1',
      'consequenceKind','organization_responsibility',
      'renderGrammar','{Responsibility} is a responsibility of {Organization}.'
    ),
    jsonb_build_object(
      'operationKey','position_responsibility.establish.v1',
      'executionClass','implementation_practitioner',
      'owningDomain','organization_structure',
      'canonicalCommand','establish_position_responsibility_internal_v1',
      'consequenceKind','position_responsibility',
      'renderGrammar','{Position} carries {Responsibility}.'
    ),
    jsonb_build_object(
      'operationKey','position_appointment.establish.v1',
      'executionClass','implementation_practitioner',
      'owningDomain','organization_structure',
      'canonicalCommand','establish_position_appointment_internal_v1',
      'consequenceKind','organization_position_appointment',
      'renderGrammar','{Person} occupies {Position}.'
    )
  )
);
$function$;

revoke all on function atlas.reality_establishment_registry_v1()
  from public,anon,authenticated;
grant execute on function atlas.reality_establishment_registry_v1()
  to service_role;

create or replace function atlas.reality_establishment_operation_exists_v1(p_operation_key text)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
select exists(
  select 1
  from jsonb_array_elements(atlas.reality_establishment_registry_v1()->'operations') op
  where op->>'operationKey'=p_operation_key
);
$function$;

revoke all on function atlas.reality_establishment_operation_exists_v1(text)
  from public,anon,authenticated;
grant execute on function atlas.reality_establishment_operation_exists_v1(text)
  to service_role;

-- Domain command: Person + Organization -> Institutional Person Record.
-- Name never silently resolves identity.
create or replace function atlas.establish_institutional_person_record_internal_v1(
  p_organization_id uuid,
  p_identity_mode text,
  p_person_id uuid,
  p_display_name text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_person atlas.people%rowtype;
  v_record atlas.institutional_person_records%rowtype;
  v_name text:=nullif(btrim(coalesce(p_display_name,'')),'');
begin
  if not exists(
    select 1 from atlas.organizations o
    where o.id=p_organization_id and o.status='active'
  ) then
    raise exception 'Active Organization required.' using errcode='23503';
  end if;

  if p_identity_mode='existing_person' then
    select * into v_person from atlas.people p
    where p.id=p_person_id and p.status='active';
    if v_person.id is null then
      raise exception 'Active existing Person required.' using errcode='23503';
    end if;
  elsif p_identity_mode='new_person' then
    if p_person_id is not null or v_name is null then
      raise exception 'Explicit new Person requires display name and no existing Person id.'
        using errcode='22023';
    end if;
    insert into atlas.people(display_name,status,metadata)
    values(v_name,'active',jsonb_build_object(
      'establishmentBasis','implementation_reality_sentence',
      'createdWithoutCredential',true
    ))
    returning * into v_person;
  else
    raise exception 'Identity mode must be existing_person or new_person.'
      using errcode='22023';
  end if;

  select * into v_record
  from atlas.institutional_person_records r
  where r.organization_id=p_organization_id and r.person_id=v_person.id
  for update;

  if v_record.id is not null then
    if v_record.status<>'active' then
      raise exception 'Institutional Person Record exists but is not active.'
        using errcode='23514';
    end if;
    return jsonb_build_object(
      'state','unchanged','consequenceKind','institutional_person_record',
      'organizationId',p_organization_id,'personId',v_person.id,
      'institutionalPersonRecordId',v_record.id
    );
  end if;

  insert into atlas.institutional_person_records(
    organization_id,person_id,status,establishment_basis
  ) values(
    p_organization_id,v_person.id,'active',
    coalesce(p_establishment_basis,'{}'::jsonb) || jsonb_build_object(
      'source','establish_institutional_person_record_internal_v1',
      'identityMode',p_identity_mode
    )
  )
  returning * into v_record;

  return jsonb_build_object(
    'state','established','consequenceKind','institutional_person_record',
    'organizationId',p_organization_id,'personId',v_person.id,
    'institutionalPersonRecordId',v_record.id
  );
end;
$function$;

create or replace function atlas.establish_organization_unit_internal_v1(
  p_organization_id uuid,
  p_parent_unit_id uuid,
  p_stable_key text,
  p_name text,
  p_unit_kind text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.organization_units%rowtype;
  v_unit atlas.organization_units%rowtype;
  v_key text:=nullif(btrim(coalesce(p_stable_key,'')),'');
  v_name text:=nullif(btrim(coalesce(p_name,'')),'');
  v_kind text:=nullif(btrim(coalesce(p_unit_kind,'')),'');
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Active Organization required.' using errcode='23503';
  end if;
  if v_key is null or v_name is null or v_kind is null then
    raise exception 'Organization Unit stable key, name, and kind required.' using errcode='22023';
  end if;
  if p_parent_unit_id is not null and not exists(
    select 1 from atlas.organization_units u
    where u.id=p_parent_unit_id and u.organization_id=p_organization_id and u.status='active'
  ) then
    raise exception 'Parent Unit must be active in the same Organization.' using errcode='23514';
  end if;

  select * into v_existing from atlas.organization_units u
  where u.organization_id=p_organization_id and u.stable_key=v_key for update;

  if v_existing.id is not null then
    if v_existing.status='active'
       and v_existing.name=v_name
       and v_existing.unit_kind=v_kind
       and v_existing.parent_unit_id is not distinct from p_parent_unit_id then
      return jsonb_build_object(
        'state','unchanged','consequenceKind','organization_unit',
        'organizationId',p_organization_id,'organizationUnitId',v_existing.id
      );
    end if;
    raise exception 'Organization Unit stable key conflicts with canonical reality.'
      using errcode='23505';
  end if;

  insert into atlas.organization_units(
    organization_id,parent_unit_id,stable_key,name,unit_kind,status,metadata
  ) values(
    p_organization_id,p_parent_unit_id,v_key,v_name,v_kind,'active',
    jsonb_build_object('establishmentSource','reality_sentence',
      'establishmentBasis',coalesce(p_establishment_basis,'{}'::jsonb))
  )
  returning * into v_unit;

  return jsonb_build_object(
    'state','established','consequenceKind','organization_unit',
    'organizationId',p_organization_id,'organizationUnitId',v_unit.id
  );
end;
$function$;

create or replace function atlas.establish_organization_position_internal_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_stable_key text,
  p_display_title text,
  p_position_kind text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.organization_positions%rowtype;
  v_position atlas.organization_positions%rowtype;
  v_key text:=nullif(btrim(coalesce(p_stable_key,'')),'');
  v_title text:=nullif(btrim(coalesce(p_display_title,'')),'');
  v_kind text:=nullif(btrim(coalesce(p_position_kind,'')),'');
begin
  if not exists(
    select 1 from atlas.organization_units u
    where u.id=p_organization_unit_id and u.organization_id=p_organization_id and u.status='active'
  ) then
    raise exception 'Active Organization Unit in target Organization required.' using errcode='23514';
  end if;
  if v_key is null or v_title is null or v_kind is null then
    raise exception 'Position stable key, title, and kind required.' using errcode='22023';
  end if;

  select * into v_existing from atlas.organization_positions p
  where p.organization_id=p_organization_id
    and p.organization_unit_id=p_organization_unit_id
    and p.stable_key=v_key
  for update;

  if v_existing.id is not null then
    if v_existing.status='active'
       and v_existing.display_title=v_title
       and v_existing.position_kind=v_kind then
      return jsonb_build_object(
        'state','unchanged','consequenceKind','organization_position',
        'organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,
        'positionId',v_existing.id
      );
    end if;
    raise exception 'Position stable key conflicts with canonical reality.' using errcode='23505';
  end if;

  insert into atlas.organization_positions(
    organization_id,organization_unit_id,stable_key,display_title,position_kind,status,metadata
  ) values(
    p_organization_id,p_organization_unit_id,v_key,v_title,v_kind,'active',
    jsonb_build_object('establishmentSource','reality_sentence',
      'establishmentBasis',coalesce(p_establishment_basis,'{}'::jsonb))
  )
  returning * into v_position;

  return jsonb_build_object(
    'state','established','consequenceKind','organization_position',
    'organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,
    'positionId',v_position.id
  );
end;
$function$;

create or replace function atlas.establish_organization_responsibility_internal_v1(
  p_organization_id uuid,
  p_stable_key text,
  p_name text,
  p_responsibility_kind text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.organization_responsibilities%rowtype;
  v_responsibility atlas.organization_responsibilities%rowtype;
  v_key text:=nullif(btrim(coalesce(p_stable_key,'')),'');
  v_name text:=nullif(btrim(coalesce(p_name,'')),'');
  v_kind text:=nullif(btrim(coalesce(p_responsibility_kind,'')),'');
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Active Organization required.' using errcode='23503';
  end if;
  if v_key is null or v_name is null or v_kind is null then
    raise exception 'Responsibility stable key, name, and kind required.' using errcode='22023';
  end if;

  select * into v_existing from atlas.organization_responsibilities r
  where r.organization_id=p_organization_id and r.stable_key=v_key for update;

  if v_existing.id is not null then
    if v_existing.status='active'
       and v_existing.name=v_name
       and v_existing.responsibility_kind=v_kind then
      return jsonb_build_object(
        'state','unchanged','consequenceKind','organization_responsibility',
        'organizationId',p_organization_id,'responsibilityId',v_existing.id
      );
    end if;
    raise exception 'Responsibility stable key conflicts with canonical reality.' using errcode='23505';
  end if;

  insert into atlas.organization_responsibilities(
    organization_id,stable_key,name,responsibility_kind,status,metadata
  ) values(
    p_organization_id,v_key,v_name,v_kind,'active',
    jsonb_build_object('establishmentSource','reality_sentence',
      'establishmentBasis',coalesce(p_establishment_basis,'{}'::jsonb))
  )
  returning * into v_responsibility;

  return jsonb_build_object(
    'state','established','consequenceKind','organization_responsibility',
    'organizationId',p_organization_id,'responsibilityId',v_responsibility.id
  );
end;
$function$;

create or replace function atlas.establish_position_responsibility_internal_v1(
  p_organization_id uuid,
  p_position_id uuid,
  p_responsibility_id uuid,
  p_relationship_kind text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_kind text:=nullif(btrim(coalesce(p_relationship_kind,'')),'');
begin
  if v_kind is null then
    raise exception 'Position Responsibility relationship kind required.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.organization_positions p
    where p.id=p_position_id and p.organization_id=p_organization_id and p.status='active'
  ) or not exists(
    select 1 from atlas.organization_responsibilities r
    where r.id=p_responsibility_id and r.organization_id=p_organization_id and r.status='active'
  ) then
    raise exception 'Active Position and Responsibility in same Organization required.' using errcode='23514';
  end if;

  if exists(
    select 1 from atlas.organization_position_responsibilities pr
    where pr.position_id=p_position_id and pr.responsibility_id=p_responsibility_id
      and pr.relationship_kind=v_kind
  ) then
    return jsonb_build_object(
      'state','unchanged','consequenceKind','position_responsibility',
      'organizationId',p_organization_id,'positionId',p_position_id,
      'responsibilityId',p_responsibility_id,'relationshipKind',v_kind
    );
  end if;

  if exists(
    select 1 from atlas.organization_position_responsibilities pr
    where pr.position_id=p_position_id and pr.responsibility_id=p_responsibility_id
  ) then
    raise exception 'Position and Responsibility already have a different relationship kind.'
      using errcode='23505';
  end if;

  insert into atlas.organization_position_responsibilities(
    position_id,responsibility_id,relationship_kind
  ) values(p_position_id,p_responsibility_id,v_kind);

  return jsonb_build_object(
    'state','established','consequenceKind','position_responsibility',
    'organizationId',p_organization_id,'positionId',p_position_id,
    'responsibilityId',p_responsibility_id,'relationshipKind',v_kind
  );
end;
$function$;

create or replace function atlas.establish_position_appointment_internal_v1(
  p_organization_id uuid,
  p_institutional_person_record_id uuid,
  p_position_id uuid,
  p_appointment_kind text,
  p_begins_at timestamptz,
  p_ends_at timestamptz,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.organization_position_appointments%rowtype;
  v_appointment atlas.organization_position_appointments%rowtype;
  v_kind text:=nullif(btrim(coalesce(p_appointment_kind,'')),'');
begin
  if v_kind is null or p_begins_at is null or (p_ends_at is not null and p_ends_at<p_begins_at) then
    raise exception 'Valid appointment kind and time window required.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.institutional_person_records r
    where r.id=p_institutional_person_record_id
      and r.organization_id=p_organization_id and r.status='active'
  ) then
    raise exception 'Active Institutional Person Record in target Organization required.' using errcode='23514';
  end if;
  if not exists(
    select 1 from atlas.organization_positions p
    where p.id=p_position_id and p.organization_id=p_organization_id and p.status='active'
  ) then
    raise exception 'Active Position in target Organization required.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.organization_position_appointments a
  where a.organization_id=p_organization_id
    and a.position_id=p_position_id
    and a.institutional_person_record_id=p_institutional_person_record_id
    and a.status='active' and a.ends_at is null
  order by a.begins_at,a.id
  limit 1 for update;

  if v_existing.id is not null then
    if v_existing.appointment_kind=v_kind
       and v_existing.begins_at=p_begins_at
       and v_existing.ends_at is not distinct from p_ends_at then
      return jsonb_build_object(
        'state','unchanged','consequenceKind','organization_position_appointment',
        'organizationId',p_organization_id,
        'institutionalPersonRecordId',p_institutional_person_record_id,
        'positionId',p_position_id,'appointmentId',v_existing.id
      );
    end if;
    raise exception 'Active appointment already exists with different canonical appointment semantics.'
      using errcode='23505';
  end if;

  insert into atlas.organization_position_appointments(
    organization_id,position_id,institutional_person_record_id,
    appointment_kind,status,begins_at,ends_at,metadata
  ) values(
    p_organization_id,p_position_id,p_institutional_person_record_id,
    v_kind,'active',p_begins_at,p_ends_at,
    jsonb_build_object('establishmentSource','reality_sentence',
      'establishmentBasis',coalesce(p_establishment_basis,'{}'::jsonb))
  )
  returning * into v_appointment;

  return jsonb_build_object(
    'state','established','consequenceKind','organization_position_appointment',
    'organizationId',p_organization_id,
    'institutionalPersonRecordId',p_institutional_person_record_id,
    'positionId',p_position_id,'appointmentId',v_appointment.id
  );
end;
$function$;

revoke all on function atlas.establish_institutional_person_record_internal_v1(uuid,text,uuid,text,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.establish_organization_unit_internal_v1(uuid,uuid,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.establish_organization_position_internal_v1(uuid,uuid,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.establish_organization_responsibility_internal_v1(uuid,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.establish_position_responsibility_internal_v1(uuid,uuid,uuid,text,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.establish_position_appointment_internal_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,jsonb)
  from public,anon,authenticated;

grant execute on function atlas.establish_institutional_person_record_internal_v1(uuid,text,uuid,text,jsonb)
  to service_role;
grant execute on function atlas.establish_organization_unit_internal_v1(uuid,uuid,text,text,text,jsonb)
  to service_role;
grant execute on function atlas.establish_organization_position_internal_v1(uuid,uuid,text,text,text,jsonb)
  to service_role;
grant execute on function atlas.establish_organization_responsibility_internal_v1(uuid,text,text,text,jsonb)
  to service_role;
grant execute on function atlas.establish_position_responsibility_internal_v1(uuid,uuid,uuid,text,jsonb)
  to service_role;
grant execute on function atlas.establish_position_appointment_internal_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,jsonb)
  to service_role;

commit;
