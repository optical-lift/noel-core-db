-- Atlas Buyer Relationship Notebook v1 disposable fixture
-- Proves event chronology, explicit scheduling, Task -> Company Work convergence,
-- exact idempotent replay, conflicting replay rejection, one-active-follow-up,
-- completion chronology, and later rescheduling. This script MUST roll back.

begin;

do $$
declare
  v_farm uuid;
  v_member uuid;
  v_role text;
  v_relationship uuid;
  v_contact uuid;
  v_contact_occurred timestamptz:=now()-interval '2 days';
  v_key text:='relationship-notebook-fixture-'||gen_random_uuid()::text;
  v_key_2 text:='relationship-notebook-fixture-2-'||gen_random_uuid()::text;
  v_result jsonb;
  v_replay jsonb;
  v_second jsonb;
  v_task uuid;
  v_work uuid;
  v_timeline_time timestamptz;
  v_memory text;
  v_count integer;
begin
  select fm.farm_id,fm.id,fm.role
  into v_farm,v_member,v_role
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  where fm.active
    and fm.role in ('owner','manager')
    and f.organization_id is not null
    and f.organization_unit_id is not null
  order by case fm.role when 'owner' then 1 else 2 end,fm.created_at,fm.id
  limit 1;

  if v_farm is null or v_member is null then
    raise exception 'Fixture requires an operating-unit farm with an active Owner or Manager membership.';
  end if;

  insert into atlas.buyer_relationship_reconstruction(
    farm_id,stable_key,business_name,buyer_type,relationship_status,next_action,source_person,source_date,metadata
  ) values (
    v_farm,
    'fixture_relationship_notebook_'||replace(substr(gen_random_uuid()::text,1,8),'-',''),
    'Fixture Relationship Notebook Buyer',
    'florist',
    'interested',
    'Call the fixture buyer Friday',
    'relationship_notebook_fixture',
    current_date,
    jsonb_build_object('fixture','atlas_buyer_relationship_notebook_v1')
  ) returning id into v_relationship;

  insert into atlas.buyer_contact_events(
    farm_id,buyer_relationship_id,occurred_at,contact_method,outcome,contact_name,notes,recorded_by_membership_id,metadata
  ) values (
    v_farm,v_relationship,v_contact_occurred,'phone','interested','Fixture Buyer',
    'Fixture contact happened before it was recorded.',v_member,
    jsonb_build_object('fixture','atlas_buyer_relationship_notebook_v1')
  ) returning id into v_contact;

  select occurred_at into v_timeline_time
  from atlas.buyer_relationship_timeline_v1
  where source_object_type='buyer_contact_event' and source_object_id=v_contact;
  if v_timeline_time is distinct from v_contact_occurred then
    raise exception 'Contact chronology used record time instead of occurred_at: expected %, got %',v_contact_occurred,v_timeline_time;
  end if;

  if not exists(
    select 1 from atlas.buyer_relationship_position_v1
    where buyer_relationship_id=v_relationship
      and remembered_next_action='Call the fixture buyer Friday'
      and needs_next_action_scheduling=true
      and current_next_action_task_id is null
  ) then
    raise exception 'Relationship position did not expose remembered next action as unscheduled memory.';
  end if;

  v_result:=atlas.create_buyer_relationship_next_action_core_v1(
    v_relationship,'Call the fixture buyer Friday',current_date+1,v_member,v_member,v_role,v_key,true
  );
  v_task:=(v_result->>'taskId')::uuid;
  v_work:=(v_result->>'workItemId')::uuid;

  if v_task is null or v_work is null or coalesce((v_result->>'deduplicated')::boolean,true) then
    raise exception 'Initial scheduling did not create one Task and Company Work item: %',v_result;
  end if;

  select next_action into v_memory from atlas.buyer_relationship_reconstruction where id=v_relationship;
  if v_memory is not null then
    raise exception 'Remembered next_action was not cleared after responsibility creation.';
  end if;

  if not exists(
    select 1 from atlas.tasks
    where id=v_task
      and farm_id=v_farm
      and task_scope='farm_operation'
      and metadata->>'relationship_execution_adapter'='legacy_farm_operation_task_v1'
      and metadata->>'relationship_action_kind'='buyer_follow_up'
  ) then
    raise exception 'Follow-up Task did not preserve the explicit execution-adapter boundary.';
  end if;

  if not exists(
    select 1 from atlas.company_work_position_v2
    where work_item_id=v_work
      and source_object_type='legacy_task'
      and source_object_id=v_task
  ) then
    raise exception 'Follow-up Task did not converge to Company Work.';
  end if;

  v_replay:=atlas.create_buyer_relationship_next_action_core_v1(
    v_relationship,'Call the fixture buyer Friday',current_date+1,v_member,v_member,v_role,v_key,true
  );
  if not coalesce((v_replay->>'deduplicated')::boolean,false)
     or (v_replay->>'taskId')::uuid is distinct from v_task then
    raise exception 'Exact idempotent replay did not return the original Task: %',v_replay;
  end if;

  begin
    perform atlas.create_buyer_relationship_next_action_core_v1(
      v_relationship,'Email the fixture buyer instead',current_date+2,v_member,v_member,v_role,v_key,true
    );
    raise exception 'Expected conflicting replay to fail.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform atlas.create_buyer_relationship_next_action_core_v1(
      v_relationship,'Second simultaneous follow-up',current_date+2,v_member,v_member,v_role,v_key_2,true
    );
    raise exception 'Expected one-active-follow-up guard to fail.';
  exception when unique_violation then
    null;
  end;

  if not exists(
    select 1 from atlas.buyer_relationship_timeline_v1
    where buyer_relationship_id=v_relationship
      and event_kind='next_action_scheduled'
      and source_object_id=v_task
      and state='open'
  ) then
    raise exception 'Timeline did not preserve the Task birth event as open.';
  end if;

  perform atlas.record_task_transition_v1_internal(
    v_task,'done','relationship-notebook-fixture-done-'||v_task::text,
    null,'Fixture follow-up completed.',null,'follow_up','communication',
    jsonb_build_object('fixture','atlas_buyer_relationship_notebook_v1'),null
  );

  if not exists(
    select 1 from atlas.buyer_relationship_timeline_v1
    where buyer_relationship_id=v_relationship
      and event_kind='next_action_transition'
      and metadata->>'taskId'=v_task::text
      and state='done'
  ) then
    raise exception 'Task completion did not appear as a later timeline event.';
  end if;

  v_second:=atlas.create_buyer_relationship_next_action_core_v1(
    v_relationship,'Check back after fixture completion',current_date+3,v_member,v_member,v_role,v_key_2,true
  );
  if coalesce((v_second->>'deduplicated')::boolean,true)
     or (v_second->>'taskId')::uuid is null
     or (v_second->>'taskId')::uuid=v_task then
    raise exception 'Relationship could not accept a later explicit next action after completion: %',v_second;
  end if;

  select count(*) into v_count
  from atlas.tasks
  where farm_id=v_farm
    and metadata->>'buyer_relationship_id'=v_relationship::text
    and metadata->>'relationship_action_kind'='buyer_follow_up'
    and status in ('open','blocked');
  if v_count<>1 then
    raise exception 'Expected exactly one active follow-up after the second schedule; got %',v_count;
  end if;
end;
$$;

rollback;
