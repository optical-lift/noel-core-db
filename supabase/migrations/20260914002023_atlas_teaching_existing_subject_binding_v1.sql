-- Atlas Teaching Existing Subject Binding v1.
-- Gate A.1: allow Teaching v1 to attach to an existing, same-Ledger Organization Ledger entry
-- and let a Course preserve that exact source through capability_activation_id.

begin;

update atlas.capability_definitions
set eligible_subject_kinds=array['ledger','organization_ledger_entry']::text[]
where capability_key='teaching' and capability_version=1 and status='active';

do $proof$
begin
  if not exists(
    select 1
    from atlas.capability_definitions d
    where d.capability_key='teaching' and d.capability_version=1 and d.status='active'
      and d.eligible_subject_kinds @> array['ledger','organization_ledger_entry']::text[]
  ) then
    raise exception 'Active Teaching v1 capability definition required before existing-subject binding.';
  end if;
end;
$proof$;

create or replace function atlas.capability_subject_valid_v1(
  p_capability_key text,p_capability_version integer,p_subject_ledger_id uuid,
  p_subject_kind text,p_subject_id uuid,p_subject_key text,p_subject_path text
)
returns boolean language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_key text:=btrim(coalesce(p_capability_key,'')); v_kind text:=btrim(coalesce(p_subject_kind,''));
begin
  if not exists(
    select 1 from atlas.capability_definitions d
    where d.capability_key=v_key and d.capability_version=p_capability_version
      and d.status='active' and v_kind=any(d.eligible_subject_kinds)
  ) then return false; end if;

  if v_key='teaching' and p_capability_version=1 then
    if v_kind='ledger' then
      return p_subject_ledger_id is not null
        and p_subject_id=p_subject_ledger_id
        and p_subject_key is null
        and p_subject_path is null
        and exists(select 1 from atlas.ledgers l where l.id=p_subject_ledger_id and l.status='active');
    end if;

    if v_kind='organization_ledger_entry' then
      return p_subject_ledger_id is not null
        and p_subject_id is not null
        and p_subject_key is null
        and p_subject_path is null
        and exists(
          select 1
          from atlas.organization_ledger_entries e
          join atlas.ledgers l on l.id=e.ledger_id and l.status='active'
          where e.id=p_subject_id and e.ledger_id=p_subject_ledger_id
        );
    end if;
  end if;

  return false;
end;
$function$;
revoke all on function atlas.capability_subject_valid_v1(text,integer,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.capability_subject_valid_v1(text,integer,uuid,text,uuid,text,text) to service_role;

create or replace function atlas.capability_subject_governed_v1(
  p_ledger_id uuid,p_capability_key text,p_capability_version integer,p_subject_ledger_id uuid,
  p_subject_kind text,p_subject_id uuid,p_subject_key text,p_subject_path text
)
returns boolean language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_key text:=btrim(coalesce(p_capability_key,''));
begin
  if not atlas.capability_subject_valid_v1(
    v_key,p_capability_version,p_subject_ledger_id,p_subject_kind,p_subject_id,p_subject_key,p_subject_path
  ) then return false; end if;

  -- Teaching v1 acts only on truth governed by the same Ledger.
  -- Cross-Ledger source reality must be represented through the Ledger correlation contract first.
  if v_key='teaching' and p_capability_version=1 then
    return p_ledger_id is not null and p_subject_ledger_id=p_ledger_id;
  end if;

  return true;
end;
$function$;
revoke all on function atlas.capability_subject_governed_v1(uuid,text,integer,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.capability_subject_governed_v1(uuid,text,integer,uuid,text,uuid,text,text) to service_role;

create or replace function atlas.create_capability_activation_self_api_v1(
  p_ledger_id uuid,p_capability_key text,p_capability_version integer,p_subject_ledger_id uuid,
  p_subject_kind text,p_subject_id uuid,p_subject_key text default null,p_subject_path text default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_person uuid; v_principal uuid; v_authority uuid; v_key text:=btrim(coalesce(p_capability_key,''));
  v_kind text:=btrim(coalesce(p_subject_kind,'')); v_existing atlas.capability_activations%rowtype; v_created atlas.capability_activations%rowtype;
begin
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;
  if not atlas.capability_definition_active_v1(v_key,p_capability_version) then raise exception 'Active governed capability definition required.' using errcode='23514'; end if;
  if not atlas.capability_subject_governed_v1(
      p_ledger_id,v_key,p_capability_version,p_subject_ledger_id,v_kind,p_subject_id,p_subject_key,p_subject_path
    ) then
    raise exception 'Capability subject is invalid or outside this capability''s governing Ledger.' using errcode='23514';
  end if;
  select * into v_existing from atlas.capability_activations a
  where a.ledger_id=p_ledger_id and a.capability_key=v_key and a.capability_version=p_capability_version
    and a.subject_ledger_id=p_subject_ledger_id and a.subject_kind=v_kind
    and a.subject_id is not distinct from p_subject_id and a.subject_key is not distinct from p_subject_key
    and a.subject_path is not distinct from p_subject_path and a.state<>'retired' limit 1;
  if v_existing.id is not null then
    return jsonb_build_object('contractVersion','capability_activation_create_self_v1','state','ready','alreadyExists',true,
      'activationId',v_existing.id,'activationState',v_existing.state,'ledgerId',v_existing.ledger_id);
  end if;
  insert into atlas.capability_activations(
    ledger_id,capability_key,capability_version,subject_ledger_id,subject_kind,subject_id,subject_key,subject_path,
    state,created_by_person_id,created_by_principal_id
  ) values (
    p_ledger_id,v_key,p_capability_version,p_subject_ledger_id,v_kind,p_subject_id,p_subject_key,p_subject_path,
    'draft',v_person,v_principal
  ) returning * into v_created;
  insert into atlas.capability_activation_events(
    capability_activation_id,ledger_id,actor_person_id,actor_principal_id,principal_ledger_authority_id,
    from_state,to_state,event_kind,basis
  ) values (v_created.id,p_ledger_id,v_person,v_principal,v_authority,null,'draft','created',jsonb_build_object('source','create_capability_activation_self_api_v1'));
  return jsonb_build_object('contractVersion','capability_activation_create_self_v1','state','ready','alreadyExists',false,
    'activationId',v_created.id,'activationState','draft','ledgerId',p_ledger_id);
end;
$function$;
revoke all on function atlas.create_capability_activation_self_api_v1(uuid,text,integer,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.create_capability_activation_self_api_v1(uuid,text,integer,uuid,text,uuid,text,text) to authenticated;

create or replace function atlas.transition_capability_activation_self_api_v1(
  p_capability_activation_id uuid,p_to_state text,p_reason text default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_activation atlas.capability_activations%rowtype; v_target text:=btrim(coalesce(p_to_state,''));
  v_person uuid; v_principal uuid; v_authority uuid; v_event text;
begin
  if p_capability_activation_id is null then raise exception 'Capability activation required.' using errcode='22023'; end if;
  select * into v_activation from atlas.capability_activations where id=p_capability_activation_id for update;
  if v_activation.id is null then raise exception 'Capability activation not found.' using errcode='P0002'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_activation.ledger_id) c;
  if v_target=v_activation.state then
    return jsonb_build_object('contractVersion','capability_activation_transition_self_v1','state','ready','alreadyInState',true,
      'activationId',v_activation.id,'activationState',v_activation.state,'ledgerId',v_activation.ledger_id);
  end if;
  if not atlas.capability_activation_transition_allowed_v1(v_activation.state,v_target) then raise exception 'Illegal capability activation transition.' using errcode='23514'; end if;
  if v_target<>'retired' and not atlas.capability_subject_governed_v1(
      v_activation.ledger_id,v_activation.capability_key,v_activation.capability_version,v_activation.subject_ledger_id,
      v_activation.subject_kind,v_activation.subject_id,v_activation.subject_key,v_activation.subject_path
    ) then raise exception 'Capability definition or subject is no longer valid for governed active behavior.' using errcode='23514'; end if;
  v_event:=case when v_activation.state='draft' and v_target='active' then 'activated'
    when v_activation.state='active' and v_target='paused' then 'paused'
    when v_activation.state='paused' and v_target='active' then 'resumed'
    when v_target='retired' then 'retired' else null end;
  if v_event is null then raise exception 'Unsupported capability transition event.' using errcode='23514'; end if;
  update atlas.capability_activations set state=v_target,retired_at=case when v_target='retired' then now() else null end where id=v_activation.id;
  insert into atlas.capability_activation_events(
    capability_activation_id,ledger_id,actor_person_id,actor_principal_id,principal_ledger_authority_id,
    from_state,to_state,event_kind,reason,basis
  ) values (
    v_activation.id,v_activation.ledger_id,v_person,v_principal,v_authority,v_activation.state,v_target,v_event,
    nullif(btrim(coalesce(p_reason,'')),''),jsonb_build_object('source','transition_capability_activation_self_api_v1')
  );
  return jsonb_build_object('contractVersion','capability_activation_transition_self_v1','state','ready','alreadyInState',false,
    'activationId',v_activation.id,'fromState',v_activation.state,'activationState',v_target,'ledgerId',v_activation.ledger_id,'eventKind',v_event);
end;
$function$;
revoke all on function atlas.transition_capability_activation_self_api_v1(uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.transition_capability_activation_self_api_v1(uuid,text,text) to authenticated;

create or replace function atlas.teaching_activation_active_v1(p_ledger_id uuid,p_capability_activation_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select exists(
    select 1
    from atlas.capability_activations a
    join atlas.capability_definitions d
      on d.capability_key=a.capability_key and d.capability_version=a.capability_version
    where a.id=p_capability_activation_id
      and a.ledger_id=p_ledger_id
      and a.capability_key='teaching'
      and a.capability_version=1
      and a.state='active'
      and d.status='active'
      and atlas.capability_subject_governed_v1(
        a.ledger_id,a.capability_key,a.capability_version,a.subject_ledger_id,
        a.subject_kind,a.subject_id,a.subject_key,a.subject_path
      )
      and atlas.capability_active_for_subject_v1(
        a.ledger_id,a.capability_key,a.capability_version,a.subject_ledger_id,
        a.subject_kind,a.subject_id,a.subject_key,a.subject_path
      )
  );
$function$;
revoke all on function atlas.teaching_activation_active_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.teaching_activation_active_v1(uuid,uuid) to service_role;

create or replace function atlas.guard_teaching_course_activation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_activation atlas.capability_activations%rowtype;
begin
  select * into v_activation from atlas.capability_activations where id=new.capability_activation_id;
  if v_activation.id is null
     or v_activation.ledger_id<>new.ledger_id
     or v_activation.capability_key<>'teaching'
     or v_activation.capability_version<>1
     or not atlas.capability_subject_governed_v1(
       v_activation.ledger_id,v_activation.capability_key,v_activation.capability_version,v_activation.subject_ledger_id,
       v_activation.subject_kind,v_activation.subject_id,v_activation.subject_key,v_activation.subject_path
     ) then
    raise exception 'Course must bind to a valid Teaching v1 activation governed by the same Ledger.' using errcode='23514';
  end if;
  if tg_op='INSERT' and not atlas.teaching_activation_active_v1(new.ledger_id,new.capability_activation_id) then
    raise exception 'Active Teaching v1 capability required to create Course.' using errcode='23514';
  end if;
  return new;
end;
$function$;
revoke all on function atlas.guard_teaching_course_activation_v1() from public,anon,authenticated;

create or replace function atlas.create_teaching_course_from_activation_self_api_v1(
  p_capability_activation_id uuid,p_course_key text,p_name text
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_person uuid; v_principal uuid; v_authority uuid;
  v_key text:=lower(btrim(coalesce(p_course_key,''))); v_name text:=btrim(coalesce(p_name,''));
  v_activation atlas.capability_activations%rowtype; v_existing atlas.teaching_courses%rowtype; v_created atlas.teaching_courses%rowtype;
begin
  if p_capability_activation_id is null then raise exception 'Teaching capability activation required.' using errcode='22023'; end if;
  if v_key='' or v_name='' then raise exception 'Course key and name are required.' using errcode='22023'; end if;

  select * into v_activation
  from atlas.capability_activations a
  where a.id=p_capability_activation_id
  for share;
  if v_activation.id is null then raise exception 'Teaching capability activation not found.' using errcode='P0002'; end if;

  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_activation.ledger_id) c;

  if not atlas.teaching_activation_active_v1(v_activation.ledger_id,v_activation.id) then
    raise exception 'Active governed Teaching v1 activation required.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.teaching_courses t
  where t.ledger_id=v_activation.ledger_id and lower(t.course_key)=v_key
  limit 1;
  if v_existing.id is not null then
    if v_existing.name<>v_name or v_existing.capability_activation_id<>v_activation.id then
      raise exception 'Course key already identifies a different Course source or name.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'contractVersion','teaching_course_create_from_activation_self_v1','state','ready','alreadyExists',true,
      'courseId',v_existing.id,'ledgerId',v_existing.ledger_id,'courseState',v_existing.status,
      'capabilityActivationId',v_existing.capability_activation_id,
      'sourceSubjectLedgerId',v_activation.subject_ledger_id,'sourceSubjectKind',v_activation.subject_kind,'sourceSubjectId',v_activation.subject_id
    );
  end if;

  insert into atlas.teaching_courses(
    ledger_id,capability_activation_id,course_key,name,status,created_by_person_id,created_by_principal_id
  ) values (
    v_activation.ledger_id,v_activation.id,v_key,v_name,'active',v_person,v_principal
  ) returning * into v_created;

  return jsonb_build_object(
    'contractVersion','teaching_course_create_from_activation_self_v1','state','ready','alreadyExists',false,
    'courseId',v_created.id,'ledgerId',v_created.ledger_id,'courseState',v_created.status,
    'capabilityActivationId',v_created.capability_activation_id,
    'sourceSubjectLedgerId',v_activation.subject_ledger_id,'sourceSubjectKind',v_activation.subject_kind,'sourceSubjectId',v_activation.subject_id
  );
end;
$function$;
revoke all on function atlas.create_teaching_course_from_activation_self_api_v1(uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.create_teaching_course_from_activation_self_api_v1(uuid,text,text) to authenticated;

commit;
