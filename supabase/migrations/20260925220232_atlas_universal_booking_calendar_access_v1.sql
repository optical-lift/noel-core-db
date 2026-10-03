
create or replace function atlas.require_ledger_schedule_responsibility_v1(
  p_ledger_id uuid,
  p_operation_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_person_id uuid;
  v_subject_entity_id uuid;
  v_ledger_state text;
  v_relation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  select l.subject_entity_id,l.ledger_state
    into v_subject_entity_id,v_ledger_state
  from ledger.ledgers l
  where l.id=p_ledger_id;

  if v_subject_entity_id is null or v_ledger_state<>'active' then
    raise exception 'Active Ledger not found.' using errcode='P0002';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'institutional_schedule_operations',
    p_operation_key,
    'entity',
    v_subject_entity_id,
    null,
    jsonb_build_object('ledgerIds',jsonb_build_array(p_ledger_id::text))
  );

  if v_relation_id is null then
    raise exception 'Institutional schedule responsibility required.'
      using errcode='42501';
  end if;

  return v_relation_id;
end;
$$;

create or replace function atlas.ledger_resources_service_v1(
  p_ledger_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_subject uuid;
  v_result jsonb;
begin
  select l.subject_entity_id into v_subject
  from ledger.ledgers l
  where l.id=p_ledger_id and l.ledger_state='active';

  if v_subject is null then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;

  select jsonb_build_object(
    'contractVersion','ledger_resources_v1',
    'ledgerId',p_ledger_id,
    'subjectEntityId',v_subject,
    'resources',coalesce(jsonb_agg(
      jsonb_build_object(
        'resourceId',r.id,
        'parentResourceId',r.parent_resource_id,
        'stableKey',r.stable_key,
        'label',r.label,
        'resourceKind',r.resource_kind,
        'resourceState',r.resource_state,
        'reservable',r.reservable,
        'capacityMode',r.capacity_mode,
        'capacityQuantity',r.capacity_quantity,
        'capacityUnit',r.capacity_unit,
        'timezoneName',r.timezone_name,
        'metadata',r.metadata
      )
      order by case when r.parent_resource_id is null then 0 else 1 end,r.label,r.id
    ),'[]'::jsonb)
  )
  into v_result
  from reality.resources r
  where r.owner_entity_id=v_subject
    and r.resource_state<>'retired';

  return v_result;
end;
$$;

create or replace function atlas.ledger_resources_self_api_v1(
  p_ledger_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'resource.read');
  return atlas.ledger_resources_service_v1(p_ledger_id);
end;
$$;

create or replace function atlas.ledger_resource_calendar_self_api_v1(
  p_ledger_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'calendar.read');
  return atlas.ledger_resource_calendar_service_v1(p_ledger_id,p_window_start,p_window_end);
end;
$$;

create or replace function atlas.ledger_resource_availability_self_api_v1(
  p_ledger_id uuid,
  p_resource_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_requested_claim_kind text default 'exclusive',
  p_requested_quantity numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'availability.read');
  return atlas.ledger_resource_availability_service_v1(
    p_ledger_id,p_resource_id,p_starts_at,p_ends_at,p_requested_claim_kind,p_requested_quantity
  );
end;
$$;

revoke execute on function atlas.require_ledger_schedule_responsibility_v1(uuid,text)
  from public,anon,authenticated;
revoke execute on function atlas.ledger_resources_service_v1(uuid)
  from public,anon,authenticated;
revoke execute on function atlas.ledger_resources_self_api_v1(uuid)
  from public,anon;
revoke execute on function atlas.ledger_resource_calendar_self_api_v1(uuid,timestamptz,timestamptz)
  from public,anon;
revoke execute on function atlas.ledger_resource_availability_self_api_v1(uuid,uuid,timestamptz,timestamptz,text,numeric)
  from public,anon;

grant execute on function atlas.ledger_resources_self_api_v1(uuid) to authenticated;
grant execute on function atlas.ledger_resource_calendar_self_api_v1(uuid,timestamptz,timestamptz) to authenticated;
grant execute on function atlas.ledger_resource_availability_self_api_v1(uuid,uuid,timestamptz,timestamptz,text,numeric) to authenticated;

comment on function atlas.require_ledger_schedule_responsibility_v1(uuid,text) is
'Reality-responsibility membrane for universal Ledger schedule/calendar operations; does not depend on legacy organization membership.';
