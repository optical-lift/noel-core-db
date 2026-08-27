create or replace function atlas.record_phone_outreach_result_v1(
  p_task_id uuid,
  p_contact_result text,
  p_reached_name text,
  p_notes text,
  p_effective_membership_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'local_intel'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_role text;
  v_campaign_contact_id uuid;
  v_entity_id uuid;
  v_campaign_id uuid;
  v_contact_state text;
  v_result jsonb;
  v_history jsonb;
begin
  if p_contact_result not in ('agreed','maybe','not_interested','voicemail','no_answer','wrong_contact') then
    raise exception using errcode = '22023', message = 'Choose what happened on the call.';
  end if;

  if p_contact_result in ('agreed','maybe','not_interested','wrong_contact')
     and nullif(btrim(coalesce(p_reached_name,'')),'') is null then
    raise exception using errcode = '22023', message = 'Add who you talked to.';
  end if;

  if p_contact_result in ('agreed','maybe','not_interested','wrong_contact')
     and nullif(btrim(coalesce(p_notes,'')),'') is null then
    raise exception using errcode = '22023', message = 'Add what they said.';
  end if;

  select * into v_task
  from atlas.tasks
  where id = p_task_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Phone outreach task not found.';
  end if;

  if coalesce(v_task.metadata->>'subtask_kind','') <> 'phone_outreach_contact' then
    raise exception using errcode = '22023', message = 'This task is not a phone outreach contact.';
  end if;

  select role into v_role
  from atlas.farm_memberships
  where id = p_effective_membership_id
    and farm_id = v_task.farm_id
    and active = true;

  if v_role is null then
    raise exception using errcode = '42501', message = 'No active farm membership is available.';
  end if;

  if p_effective_membership_id is distinct from v_task.assigned_membership_id
     and v_role not in ('owner','manager') then
    raise exception using errcode = '42501', message = 'This phone outreach contact belongs to another worker.';
  end if;

  v_campaign_contact_id := nullif(v_task.metadata->>'local_intel_campaign_contact_id','')::uuid;
  v_entity_id := nullif(v_task.metadata->>'local_intel_entity_id','')::uuid;

  if v_campaign_contact_id is null or v_entity_id is null then
    raise exception using errcode = '22023', message = 'This phone outreach contact is not linked to marketing intelligence.';
  end if;

  select campaign_id into v_campaign_id
  from local_intel.campaign_contacts
  where id = v_campaign_contact_id
    and entity_id = v_entity_id
  for update;

  if v_campaign_id is null then
    raise exception using errcode = 'P0002', message = 'The linked marketing-intelligence contact was not found.';
  end if;

  v_contact_state := case p_contact_result
    when 'agreed' then 'converted'
    when 'not_interested' then 'not_interested'
    when 'voicemail' then 'contacted'
    when 'no_answer' then 'contacted'
    else 'responded'
  end;

  v_result := jsonb_build_object(
    'contact_result', p_contact_result,
    'reached_name', nullif(btrim(coalesce(p_reached_name,'')),''),
    'notes', nullif(btrim(coalesce(p_notes,'')),''),
    'recorded_at', now(),
    'atlas_task_id', v_task.id,
    'atlas_parent_task_id', v_task.parent_task_id,
    'entity_id', v_entity_id,
    'campaign_contact_id', v_campaign_contact_id
  );

  update atlas.tasks
  set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('phone_outreach_result', v_result),
      updated_at = now()
  where id = v_task.id;

  select case
    when jsonb_typeof(coalesce(metadata->'call_history','[]'::jsonb)) = 'array'
      then coalesce(metadata->'call_history','[]'::jsonb)
    else '[]'::jsonb
  end
  into v_history
  from local_intel.campaign_contacts
  where id = v_campaign_contact_id;

  update local_intel.campaign_contacts
  set state = v_contact_state,
      last_action_at = now(),
      metadata = jsonb_set(
        coalesce(metadata,'{}'::jsonb),
        '{call_history}',
        v_history || jsonb_build_array(v_result),
        true
      ) || jsonb_build_object(
        'last_phone_outreach_result', v_result,
        'last_contact_result', p_contact_result,
        'last_reached_name', nullif(btrim(coalesce(p_reached_name,'')),''),
        'last_contact_notes', nullif(btrim(coalesce(p_notes,'')),''),
        'last_called_at', now(),
        'last_atlas_task_id', v_task.id
      ),
      updated_at = now()
  where id = v_campaign_contact_id;

  return jsonb_build_object(
    'ok', true,
    'taskId', v_task.id,
    'entityId', v_entity_id,
    'campaignId', v_campaign_id,
    'campaignContactId', v_campaign_contact_id,
    'contactState', v_contact_state,
    'result', v_result
  );
end;
$function$;

revoke all on function atlas.record_phone_outreach_result_v1(uuid,text,text,text,uuid) from public;
grant execute on function atlas.record_phone_outreach_result_v1(uuid,text,text,text,uuid) to authenticated, service_role;