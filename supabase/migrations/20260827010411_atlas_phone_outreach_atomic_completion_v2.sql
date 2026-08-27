create or replace function atlas.record_phone_outreach_result_and_complete_v2(
  p_task_id uuid,
  p_contact_result text,
  p_reached_name text,
  p_notes text,
  p_effective_membership_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_parent atlas.tasks%rowtype;
  v_role text;
  v_campaign_contact local_intel.campaign_contacts%rowtype;
  v_contact_point local_intel.contact_points%rowtype;
  v_entity_id uuid;
  v_campaign_contact_id uuid;
  v_contact_point_id uuid;
  v_contact_state text;
  v_result jsonb;
  v_history jsonb;
  v_transition jsonb;
  v_scoped_key text;
  v_existing_transition atlas.task_transitions%rowtype;
  v_summary text;
begin
  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then
    raise exception using errcode='22023', message='A phone-call submission key is required.';
  end if;
  if length(p_idempotency_key) > 160 then
    raise exception using errcode='22023', message='The phone-call submission key is too long.';
  end if;
  if p_contact_result not in ('agreed','maybe','not_interested','voicemail','no_answer','wrong_contact') then
    raise exception using errcode='22023', message='Choose what happened on the call.';
  end if;
  if p_contact_result in ('agreed','maybe','not_interested','wrong_contact')
     and nullif(btrim(coalesce(p_reached_name,'')),'') is null then
    raise exception using errcode='22023', message='Add who you talked to.';
  end if;
  if p_contact_result in ('agreed','maybe','not_interested','wrong_contact')
     and nullif(btrim(coalesce(p_notes,'')),'') is null then
    raise exception using errcode='22023', message='Add what they said.';
  end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if not found then
    raise exception using errcode='P0002', message='Phone outreach task not found.';
  end if;
  if coalesce(v_task.metadata->>'subtask_kind','') <> 'phone_outreach_contact' then
    raise exception using errcode='22023', message='This task is not a phone outreach contact.';
  end if;
  if v_task.parent_task_id is null then
    raise exception using errcode='22023', message='This phone call is not attached to an outreach batch.';
  end if;

  select * into v_parent from atlas.tasks where id=v_task.parent_task_id for update;
  if not found or coalesce(v_parent.metadata->>'phone_outreach_master_task','false') <> 'true' then
    raise exception using errcode='22023', message='This phone call is not attached to a governed phone-outreach task.';
  end if;

  select role into v_role
  from atlas.farm_memberships
  where id=p_effective_membership_id and farm_id=v_task.farm_id and active=true;
  if v_role is null then
    raise exception using errcode='42501', message='No active farm membership is available.';
  end if;
  if v_role not in ('owner','manager') then
    if v_parent.assigned_membership_id is distinct from p_effective_membership_id then
      raise exception using errcode='42501', message='This phone-outreach batch belongs to another worker.';
    end if;
    if v_task.assigned_membership_id is not null
       and v_task.assigned_membership_id is distinct from p_effective_membership_id then
      raise exception using errcode='42501', message='This phone call belongs to another worker.';
    end if;
  end if;

  v_campaign_contact_id := nullif(v_task.metadata->>'local_intel_campaign_contact_id','')::uuid;
  v_entity_id := nullif(v_task.metadata->>'local_intel_entity_id','')::uuid;
  v_contact_point_id := nullif(v_task.metadata->>'local_intel_contact_point_id','')::uuid;
  if v_campaign_contact_id is null or v_entity_id is null or v_contact_point_id is null then
    raise exception using errcode='22023', message='This phone call is missing a canonical marketing-intelligence contact.';
  end if;

  select * into v_campaign_contact
  from local_intel.campaign_contacts
  where id=v_campaign_contact_id and entity_id=v_entity_id
  for update;
  if not found then
    raise exception using errcode='P0002', message='The linked marketing-intelligence contact was not found.';
  end if;
  if v_campaign_contact.campaign_id is distinct from nullif(v_parent.metadata->>'local_intel_campaign_id','')::uuid then
    raise exception using errcode='22023', message='The linked contact does not belong to this outreach campaign.';
  end if;
  if v_campaign_contact.contact_point_id is distinct from v_contact_point_id then
    raise exception using errcode='22023', message='The campaign contact does not match the released phone number.';
  end if;

  select * into v_contact_point
  from local_intel.contact_points
  where id=v_contact_point_id
    and entity_id=v_entity_id
    and contact_type='phone'
    and visibility='public'
    and marketing_status not in ('suppressed','do_not_contact')
  limit 1;
  if not found then
    raise exception using errcode='22023', message='The released phone number is not a canonical callable contact.';
  end if;

  v_scoped_key := v_task.id::text || ':' || md5(p_idempotency_key);
  select * into v_existing_transition
  from atlas.task_transitions
  where task_id=v_task.id and idempotency_key=v_scoped_key
  order by created_at desc limit 1;
  if v_existing_transition.id is not null then
    return jsonb_build_object(
      'ok',true,
      'taskId',v_task.id,
      'campaignContactId',v_campaign_contact_id,
      'entityId',v_entity_id,
      'deduplicated',true,
      'result',coalesce(v_task.metadata->'phone_outreach_result','{}'::jsonb),
      'transitionId',v_existing_transition.id,
      'status',v_task.status
    );
  end if;

  v_contact_state := case p_contact_result
    when 'agreed' then 'converted'
    when 'not_interested' then 'not_interested'
    when 'voicemail' then 'contacted'
    when 'no_answer' then 'contacted'
    else 'responded'
  end;

  v_result := jsonb_build_object(
    'contact_result',p_contact_result,
    'reached_name',nullif(btrim(coalesce(p_reached_name,'')),''),
    'notes',nullif(btrim(coalesce(p_notes,'')),''),
    'recorded_at',now(),
    'atlas_task_id',v_task.id,
    'atlas_parent_task_id',v_parent.id,
    'entity_id',v_entity_id,
    'campaign_contact_id',v_campaign_contact_id,
    'contact_point_id',v_contact_point_id,
    'phone_number',v_contact_point.contact_value,
    'idempotency_key',p_idempotency_key
  );

  select case when jsonb_typeof(coalesce(metadata->'call_history','[]'::jsonb))='array'
    then coalesce(metadata->'call_history','[]'::jsonb) else '[]'::jsonb end
  into v_history
  from local_intel.campaign_contacts where id=v_campaign_contact_id;

  update local_intel.campaign_contacts
  set state=v_contact_state,
      last_action_at=now(),
      metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{call_history}',v_history||jsonb_build_array(v_result),true)
        || jsonb_build_object(
          'last_phone_outreach_result',v_result,
          'last_contact_result',p_contact_result,
          'last_reached_name',nullif(btrim(coalesce(p_reached_name,'')),''),
          'last_contact_notes',nullif(btrim(coalesce(p_notes,'')),''),
          'last_called_at',now(),
          'last_atlas_task_id',v_task.id
        ),
      updated_at=now()
  where id=v_campaign_contact_id;

  update atlas.tasks
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'phone_outreach_result',v_result,
        'checklist_status','done',
        'result_storage','local_intel.campaign_contacts'
      ),
      updated_at=now()
  where id=v_task.id;

  v_summary := concat_ws(E'\n',
    'Result: '||p_contact_result,
    case when nullif(btrim(coalesce(p_reached_name,'')),'') is not null then 'Reached: '||btrim(p_reached_name) end,
    case when nullif(btrim(coalesce(p_notes,'')),'') is not null then 'Said: '||btrim(p_notes) end
  );

  v_transition := atlas.record_task_transition_v1(
    v_task.id,
    'checklist_done',
    p_idempotency_key,
    null,
    v_summary,
    null,
    'network',
    'phone_call_result',
    jsonb_build_object(
      'completion_source','phone_outreach_atomic_v2',
      'parent_task_id',v_parent.id,
      'local_intel_entity_id',v_entity_id,
      'local_intel_campaign_contact_id',v_campaign_contact_id,
      'local_intel_contact_point_id',v_contact_point_id,
      'contact_result',p_contact_result,
      'actor_membership_id',p_effective_membership_id,
      'actor_role',v_role
    ),
    null
  );

  return jsonb_build_object(
    'ok',true,
    'taskId',v_task.id,
    'entityId',v_entity_id,
    'campaignId',v_campaign_contact.campaign_id,
    'campaignContactId',v_campaign_contact_id,
    'contactPointId',v_contact_point_id,
    'contactState',v_contact_state,
    'deduplicated',false,
    'result',v_result,
    'transition',v_transition
  );
end;
$function$;

grant execute on function atlas.record_phone_outreach_result_and_complete_v2(uuid,text,text,text,uuid,text) to authenticated;

create or replace function atlas.guard_phone_outreach_parent_completion_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_expected integer;
  v_active integer;
begin
  if new.status='done'
     and old.status is distinct from 'done'
     and coalesce(new.metadata->>'phone_outreach_master_task','false')='true' then
    begin
      v_expected := nullif(new.metadata->>'expected_call_count','')::integer;
    exception when others then
      v_expected := null;
    end;

    select count(*) into v_active
    from atlas.tasks child
    where child.parent_task_id=new.id
      and child.status<>'archived'
      and coalesce(child.metadata->>'subtask_kind','')='phone_outreach_contact';

    if v_active=0 or (v_expected is not null and v_active < v_expected) then
      raise exception using errcode='22023', message='Done rejected: the released phone-outreach contact set is incomplete.';
    end if;

    if exists(
      select 1 from atlas.tasks child
      where child.parent_task_id=new.id
        and child.status<>'archived'
        and coalesce(child.metadata->>'subtask_kind','')='phone_outreach_contact'
        and (
          child.status<>'done'
          or coalesce(child.metadata->'phone_outreach_result','null'::jsonb)='null'::jsonb
          or nullif(child.metadata#>>'{phone_outreach_result,contact_result}','') is null
        )
    ) then
      raise exception using errcode='22023', message='Done rejected: record a call result for every released contact first.';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists guard_phone_outreach_parent_completion_v1 on atlas.tasks;
create trigger guard_phone_outreach_parent_completion_v1
before update of status on atlas.tasks
for each row execute function atlas.guard_phone_outreach_parent_completion_v1();