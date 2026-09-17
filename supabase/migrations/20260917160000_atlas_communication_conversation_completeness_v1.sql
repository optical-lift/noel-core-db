begin;

-- Communications convergence Stage 1.
-- Common Communication Conversation becomes unavoidable before the
-- Institutional Conversation compatibility / responsibility carrier.

-- 20260911174500 introduced this horizontal event-membership primitive in
-- canonical source but never released to production. Carry it forward at a
-- releasable timestamp without assuming the stale migration ran.
create table if not exists atlas.communication_conversation_events (
  id uuid primary key default gen_random_uuid(),
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  communication_event_id uuid not null unique references atlas.communication_events(id) on delete restrict,
  communication_endpoint_id uuid references atlas.communication_endpoints(id) on delete restrict,
  continuity_basis text not null check (btrim(continuity_basis)<>''),
  occurred_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);

create index if not exists communication_conversation_events_conversation_idx
  on atlas.communication_conversation_events(communication_conversation_id,occurred_at,id);

comment on table atlas.communication_conversation_events is
'Provider-independent event membership for one durable Atlas Communication Conversation. Source-local thread identity remains evidence beneath that root.';

create or replace function atlas.guard_communication_conversation_event_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_conversation atlas.communication_conversations%rowtype;
  v_event atlas.communication_events%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
begin
  select * into v_conversation from atlas.communication_conversations where id=new.communication_conversation_id;
  select * into v_event from atlas.communication_events where id=new.communication_event_id;

  if v_conversation.id is null or v_event.id is null then
    raise exception 'Conversation and event are required.' using errcode='23514';
  end if;

  if v_conversation.principal_id is not null then
    if v_event.principal_id is distinct from v_conversation.principal_id
       or v_event.organization_id is not null then
      raise exception 'Conversation event must share Principal custody.' using errcode='23514';
    end if;
  elsif v_event.organization_id is distinct from v_conversation.organization_id
        or v_event.organization_unit_id is distinct from v_conversation.organization_unit_id
        or v_event.principal_id is not null then
    raise exception 'Conversation event must share Organization/unit custody.' using errcode='23514';
  end if;

  if new.communication_endpoint_id is not null then
    select * into v_endpoint from atlas.communication_endpoints where id=new.communication_endpoint_id;
    if v_endpoint.id is null then
      raise exception 'Conversation event endpoint is unavailable.' using errcode='23514';
    end if;
    if v_conversation.principal_id is not null
       and v_endpoint.principal_id is distinct from v_conversation.principal_id then
      raise exception 'Conversation event endpoint is outside Principal custody.' using errcode='23514';
    end if;
    if v_conversation.organization_id is not null
       and (v_endpoint.organization_id is distinct from v_conversation.organization_id
            or v_endpoint.organization_unit_id is distinct from v_conversation.organization_unit_id) then
      raise exception 'Conversation event endpoint is outside Organization custody.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists communication_conversation_event_guard_v1 on atlas.communication_conversation_events;
create trigger communication_conversation_event_guard_v1
before insert or update on atlas.communication_conversation_events
for each row execute function atlas.guard_communication_conversation_event_v1();

revoke all on table atlas.communication_conversation_events from public,anon,authenticated;
grant all on table atlas.communication_conversation_events to service_role;
alter table atlas.communication_conversation_events enable row level security;

-- Provider-independent Organization admission. This creates continuity only:
-- no Response Case, Company Work, assignment, read state, or business truth.
create or replace function atlas.ensure_organization_communication_conversation_service_v1(
  p_communication_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_endpoint_id uuid;
  v_candidate_count int;
  v_conversation_id uuid;
  v_existing_id uuid;
  v_stable_key text;
  v_subject text;
  v_created boolean:=false;
begin
  select * into v_event
  from atlas.communication_events
  where id=p_communication_event_id
  for update;

  if v_event.id is null then
    raise exception 'Communication event not found.' using errcode='P0002';
  end if;

  if v_event.organization_id is null or v_event.principal_id is not null then
    return jsonb_build_object(
      'contractVersion','organization_communication_conversation_admission_v1',
      'state','not_organization',
      'communicationEventId',v_event.id
    );
  end if;

  select count(*),(array_agg(ep.id order by ep.id))[1]
  into v_candidate_count,v_endpoint_id
  from atlas.communication_endpoint_source_bindings b
  join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
  where b.connected_source_id=v_event.connected_source_id
    and b.binding_state='active'
    and ep.endpoint_state='active'
    and ep.organization_id=v_event.organization_id
    and ep.organization_unit_id is not distinct from v_event.organization_unit_id
    and (b.binding_role='send_receive'
      or (v_event.direction='incoming' and b.binding_role='receive')
      or (v_event.direction='outgoing' and b.binding_role='send')
      or v_event.direction='unknown')
    and exists(
      select 1
      from atlas.communication_event_participants p
      where p.communication_event_id=v_event.id
        and p.is_self
        and p.address_normalized=ep.address_normalized
        and ((ep.endpoint_kind='email' and p.address_kind='email')
          or (ep.endpoint_kind in ('phone','sms','voice') and p.address_kind='phone')
          or ep.endpoint_kind not in ('email','phone','sms','voice'))
    );

  if v_candidate_count=0 then
    select count(*),(array_agg(ep.id order by ep.id))[1]
    into v_candidate_count,v_endpoint_id
    from atlas.communication_endpoint_source_bindings b
    join atlas.communication_endpoints ep on ep.id=b.communication_endpoint_id
    where b.connected_source_id=v_event.connected_source_id
      and b.binding_state='active'
      and ep.endpoint_state='active'
      and ep.organization_id=v_event.organization_id
      and ep.organization_unit_id is not distinct from v_event.organization_unit_id
      and (b.binding_role='send_receive'
        or (v_event.direction='incoming' and b.binding_role='receive')
        or (v_event.direction='outgoing' and b.binding_role='send')
        or v_event.direction='unknown');
  end if;

  if v_candidate_count<>1 then
    return jsonb_build_object(
      'contractVersion','organization_communication_conversation_admission_v1',
      'state',case when v_candidate_count=0 then 'no_endpoint' else 'ambiguous_endpoint' end,
      'communicationEventId',v_event.id,
      'candidateCount',v_candidate_count
    );
  end if;

  select communication_conversation_id
  into v_conversation_id
  from atlas.communication_conversation_events
  where communication_event_id=v_event.id;

  if v_conversation_id is not null then
    if not exists(
      select 1 from atlas.communication_conversations cc
      where cc.id=v_conversation_id
        and cc.principal_id is null
        and cc.organization_id=v_event.organization_id
        and cc.organization_unit_id is not distinct from v_event.organization_unit_id
    ) then
      raise exception 'Existing Communication Event membership conflicts with Organization custody.'
        using errcode='23514';
    end if;

    insert into atlas.communication_conversation_endpoints(
      communication_conversation_id,communication_endpoint_id,endpoint_role
    ) values(v_conversation_id,v_endpoint_id,'participant')
    on conflict (communication_conversation_id,communication_endpoint_id) do nothing;

    return jsonb_build_object(
      'contractVersion','organization_communication_conversation_admission_v1',
      'state','admitted',
      'communicationEventId',v_event.id,
      'communicationConversationId',v_conversation_id,
      'communicationEndpointId',v_endpoint_id,
      'conversationCreated',false
    );
  end if;

  if v_event.thread_id is not null then
    -- Same source thread must serialize onto one common root.
    perform 1 from atlas.communication_threads where id=v_event.thread_id for update;
    select communication_conversation_id
    into v_conversation_id
    from atlas.communication_conversation_source_threads
    where communication_thread_id=v_event.thread_id;

    if v_conversation_id is not null and not exists(
      select 1 from atlas.communication_conversations cc
      where cc.id=v_conversation_id
        and cc.principal_id is null
        and cc.organization_id=v_event.organization_id
        and cc.organization_unit_id is not distinct from v_event.organization_unit_id
    ) then
      raise exception 'Source thread is bridged outside Organization custody.'
        using errcode='23514';
    end if;
  end if;

  if v_conversation_id is null then
    v_stable_key:=case
      when v_event.thread_id is not null
        then 'source-thread:'||v_event.connected_source_id::text||':'||v_event.thread_id::text
      else 'source-event:'||v_event.id::text
    end;
    v_subject:=coalesce(
      nullif(btrim(v_event.canonical_event->>'subject'),''),
      nullif(btrim(v_event.canonical_event#>>'{sourcePayload,subject}'),''),
      'Conversation'
    );

    insert into atlas.communication_conversations(
      principal_id,organization_id,organization_unit_id,stable_key,subject,
      opened_at,last_activity_at,metadata
    ) values(
      null,v_event.organization_id,v_event.organization_unit_id,v_stable_key,v_subject,
      coalesce(v_event.occurred_at,v_event.captured_at),
      coalesce(v_event.occurred_at,v_event.captured_at),
      jsonb_build_object('createdFromCommunicationEventId',v_event.id)
    )
    on conflict (organization_id,stable_key) where organization_id is not null
    do update set
      last_activity_at=greatest(atlas.communication_conversations.last_activity_at,excluded.last_activity_at),
      updated_at=now()
    returning id into v_conversation_id;

    v_created:=true;

    insert into atlas.communication_conversation_endpoints(
      communication_conversation_id,communication_endpoint_id,endpoint_role
    ) values(v_conversation_id,v_endpoint_id,'primary')
    on conflict (communication_conversation_id,communication_endpoint_id) do nothing;

    if v_event.thread_id is not null then
      insert into atlas.communication_conversation_source_threads(
        communication_conversation_id,communication_thread_id,connected_source_id,
        continuity_basis,metadata
      ) values(
        v_conversation_id,v_event.thread_id,v_event.connected_source_id,
        'source_thread',jsonb_build_object('firstCommunicationEventId',v_event.id)
      )
      on conflict (communication_thread_id) do nothing;

      select communication_conversation_id
      into v_existing_id
      from atlas.communication_conversation_source_threads
      where communication_thread_id=v_event.thread_id;

      if v_existing_id is distinct from v_conversation_id then
        raise exception 'Source thread continuity resolved to a different Communication Conversation.'
          using errcode='23514';
      end if;
    end if;
  else
    update atlas.communication_conversations
    set last_activity_at=greatest(last_activity_at,coalesce(v_event.occurred_at,v_event.captured_at)),
        updated_at=now()
    where id=v_conversation_id;

    insert into atlas.communication_conversation_endpoints(
      communication_conversation_id,communication_endpoint_id,endpoint_role
    ) values(v_conversation_id,v_endpoint_id,'participant')
    on conflict (communication_conversation_id,communication_endpoint_id) do nothing;
  end if;

  insert into atlas.communication_conversation_events(
    communication_conversation_id,communication_event_id,communication_endpoint_id,
    continuity_basis,occurred_at,metadata
  ) values(
    v_conversation_id,v_event.id,v_endpoint_id,
    case when v_event.thread_id is null then 'source_event' else 'source_thread' end,
    v_event.occurred_at,
    jsonb_build_object(
      'connectedSourceId',v_event.connected_source_id,
      'sourceEventRef',v_event.source_event_ref
    )
  )
  on conflict (communication_event_id) do nothing;

  select communication_conversation_id
  into v_existing_id
  from atlas.communication_conversation_events
  where communication_event_id=v_event.id;

  if v_existing_id is distinct from v_conversation_id then
    raise exception 'Communication Event is attached to a different Communication Conversation.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','organization_communication_conversation_admission_v1',
    'state','admitted',
    'communicationEventId',v_event.id,
    'communicationConversationId',v_conversation_id,
    'communicationEndpointId',v_endpoint_id,
    'conversationCreated',v_created
  );
end;
$function$;

revoke all on function atlas.ensure_organization_communication_conversation_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.ensure_organization_communication_conversation_service_v1(uuid)
  to service_role;

-- Compatibility-root custody is now enforced, not merely assumed.
create or replace function atlas.guard_institutional_conversation_root_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_institutional atlas.institutional_conversations%rowtype;
  v_common atlas.communication_conversations%rowtype;
begin
  if tg_op='UPDATE'
     and (new.institutional_conversation_id is distinct from old.institutional_conversation_id
          or new.communication_conversation_id is distinct from old.communication_conversation_id) then
    raise exception 'Institutional compatibility roots are immutable once established.'
      using errcode='55000';
  end if;

  select * into v_institutional
  from atlas.institutional_conversations
  where id=new.institutional_conversation_id;
  select * into v_common
  from atlas.communication_conversations
  where id=new.communication_conversation_id;

  if v_institutional.id is null or v_common.id is null then
    raise exception 'Institutional and common Communication Conversation are required.'
      using errcode='23514';
  end if;

  if v_common.principal_id is not null
     or v_common.organization_id is distinct from v_institutional.organization_id
     or v_common.organization_unit_id is distinct from v_institutional.organization_unit_id then
    raise exception 'Institutional compatibility root must share Organization/unit custody.'
      using errcode='23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists institutional_conversation_root_guard_v1 on atlas.institutional_conversation_roots;
create trigger institutional_conversation_root_guard_v1
before insert or update on atlas.institutional_conversation_roots
for each row execute function atlas.guard_institutional_conversation_root_v1();

-- Backfill common roots from already-governed Institutional continuity. This
-- deliberately does not re-resolve old messages against today's provider state.
do $backfill$
declare
  v_ic atlas.institutional_conversations%rowtype;
  v_common_id uuid;
  v_existing_root uuid;
  v_thread_ids uuid[];
  v_thread_count int;
begin
  for v_ic in select * from atlas.institutional_conversations order by created_at,id loop
    select communication_conversation_id
    into v_existing_root
    from atlas.institutional_conversation_roots
    where institutional_conversation_id=v_ic.id;

    v_common_id:=v_existing_root;

    if v_common_id is null then
      select
        coalesce(array_agg(distinct cst.communication_conversation_id)
          filter (where cst.communication_conversation_id is not null),'{}'::uuid[]),
        count(distinct cst.communication_conversation_id)
          filter (where cst.communication_conversation_id is not null)
      into v_thread_ids,v_thread_count
      from atlas.institutional_conversation_source_threads ist
      left join atlas.communication_conversation_source_threads cst
        on cst.communication_thread_id=ist.communication_thread_id
      where ist.institutional_conversation_id=v_ic.id;

      if v_thread_count>1 then
        raise exception 'Institutional Conversation % spans multiple common roots.',
          v_ic.id using errcode='23514';
      end if;

      if v_thread_count=1 then
        v_common_id:=v_thread_ids[1];
      else
        insert into atlas.communication_conversations(
          principal_id,organization_id,organization_unit_id,stable_key,subject,
          conversation_state,opened_at,last_activity_at,metadata,created_at,updated_at
        ) values(
          null,v_ic.organization_id,v_ic.organization_unit_id,
          'institutional:'||v_ic.id::text,
          v_ic.subject,v_ic.conversation_state,v_ic.opened_at,v_ic.last_activity_at,
          coalesce(v_ic.metadata,'{}'::jsonb)
            || jsonb_build_object(
              'institutionalConversationId',v_ic.id,
              'compatibilityBackfill','communication_conversation_completeness_v1'
            ),
          v_ic.created_at,v_ic.updated_at
        )
        on conflict (organization_id,stable_key) where organization_id is not null
        do update set
          last_activity_at=greatest(atlas.communication_conversations.last_activity_at,excluded.last_activity_at),
          updated_at=greatest(atlas.communication_conversations.updated_at,excluded.updated_at)
        returning id into v_common_id;
      end if;

      insert into atlas.institutional_conversation_roots(
        institutional_conversation_id,communication_conversation_id,created_at
      ) values(v_ic.id,v_common_id,v_ic.created_at)
      on conflict (institutional_conversation_id) do nothing;

      select communication_conversation_id
      into v_existing_root
      from atlas.institutional_conversation_roots
      where institutional_conversation_id=v_ic.id;

      if v_existing_root is distinct from v_common_id then
        raise exception 'Institutional Conversation % root conflicts during backfill.',
          v_ic.id using errcode='23514';
      end if;
    end if;

    insert into atlas.communication_conversation_endpoints(
      communication_conversation_id,communication_endpoint_id,endpoint_role,metadata,created_at
    )
    select
      v_common_id,ice.communication_endpoint_id,
      case when ice.endpoint_role='primary' then 'primary' else 'participant' end,
      jsonb_build_object(
        'institutionalConversationEndpointBridge',true,
        'compatibilityBackfill','communication_conversation_completeness_v1'
      ),
      ice.created_at
    from atlas.institutional_conversation_endpoints ice
    where ice.institutional_conversation_id=v_ic.id
    on conflict (communication_conversation_id,communication_endpoint_id) do nothing;

    insert into atlas.communication_conversation_source_threads(
      communication_conversation_id,communication_thread_id,connected_source_id,
      continuity_basis,metadata,created_at
    )
    select
      v_common_id,ist.communication_thread_id,ist.connected_source_id,
      'institutional_compatibility:'||ist.continuity_basis,
      coalesce(ist.metadata,'{}'::jsonb)
        || jsonb_build_object(
          'institutionalConversationSourceThreadBridge',true,
          'compatibilityBackfill','communication_conversation_completeness_v1'
        ),
      ist.created_at
    from atlas.institutional_conversation_source_threads ist
    where ist.institutional_conversation_id=v_ic.id
    on conflict (communication_thread_id) do nothing;

    if exists(
      select 1
      from atlas.institutional_conversation_source_threads ist
      join atlas.communication_conversation_source_threads cst
        on cst.communication_thread_id=ist.communication_thread_id
      where ist.institutional_conversation_id=v_ic.id
        and cst.communication_conversation_id<>v_common_id
    ) then
      raise exception 'Institutional Conversation % thread bridge conflicts with its common root.',
        v_ic.id using errcode='23514';
    end if;
  end loop;
end;
$backfill$;

insert into atlas.communication_conversation_events(
  communication_conversation_id,communication_event_id,communication_endpoint_id,
  continuity_basis,occurred_at,metadata,created_at
)
select
  root.communication_conversation_id,
  message.communication_event_id,
  message.communication_endpoint_id,
  'institutional_compatibility:'||message.continuity_basis,
  message.occurred_at,
  coalesce(message.metadata,'{}'::jsonb)
    || jsonb_build_object(
      'institutionalConversationId',message.institutional_conversation_id,
      'compatibilityBackfill','communication_conversation_completeness_v1'
    ),
  message.created_at
from atlas.institutional_conversation_messages message
join atlas.institutional_conversation_roots root
  on root.institutional_conversation_id=message.institutional_conversation_id
on conflict (communication_event_id) do nothing;

do $event_guard$
begin
  if exists(
    select 1
    from atlas.institutional_conversation_messages message
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=message.institutional_conversation_id
    join atlas.communication_conversation_events event_link
      on event_link.communication_event_id=message.communication_event_id
    where event_link.communication_conversation_id<>root.communication_conversation_id
  ) then
    raise exception 'Historical event membership conflicts with Institutional compatibility root.'
      using errcode='23514';
  end if;
end;
$event_guard$;

-- Preserve the original Institutional admission implementation byte-for-byte
-- as a compatibility carrier, then put common admission in front of it.
alter function atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid)
  rename to ensure_institutional_conversation_compatibility_service_v1;

create or replace function atlas.ensure_institutional_conversation_for_communication_event_service_v1(
  p_communication_event_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_common jsonb;
  v_compat jsonb;
  v_common_id uuid;
  v_institutional_id uuid;
  v_existing_root uuid;
begin
  v_common:=atlas.ensure_organization_communication_conversation_service_v1(
    p_communication_event_id
  );

  -- Preserve old admission-review behavior for unresolved evidence.
  if v_common->>'state' is distinct from 'admitted' then
    return atlas.ensure_institutional_conversation_compatibility_service_v1(
      p_communication_event_id
    );
  end if;

  v_compat:=atlas.ensure_institutional_conversation_compatibility_service_v1(
    p_communication_event_id
  );

  if v_compat->>'state' is distinct from 'admitted' then
    raise exception 'Institutional compatibility admission disagrees with common Conversation admission.'
      using errcode='55000';
  end if;

  v_common_id:=(v_common->>'communicationConversationId')::uuid;
  v_institutional_id:=(v_compat->>'institutionalConversationId')::uuid;

  if (v_common->>'communicationEndpointId')::uuid
     is distinct from (v_compat->>'communicationEndpointId')::uuid then
    raise exception 'Common and Institutional endpoint resolution disagree.'
      using errcode='23514';
  end if;

  select communication_conversation_id
  into v_existing_root
  from atlas.institutional_conversation_roots
  where institutional_conversation_id=v_institutional_id;

  if v_existing_root is not null and v_existing_root is distinct from v_common_id then
    raise exception 'Institutional Conversation already points to a different common root.'
      using errcode='23514';
  end if;

  insert into atlas.institutional_conversation_roots(
    institutional_conversation_id,communication_conversation_id
  ) values(v_institutional_id,v_common_id)
  on conflict (institutional_conversation_id) do nothing;

  return v_compat || jsonb_build_object(
    'communicationConversationId',v_common_id,
    'commonConversationCreated',coalesce((v_common->>'conversationCreated')::boolean,false)
  );
end;
$function$;

revoke all on function atlas.ensure_institutional_conversation_compatibility_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.ensure_institutional_conversation_compatibility_service_v1(uuid)
  to service_role;

revoke all on function atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid)
  to service_role;

-- No future transaction may commit an Institutional Conversation without one
-- common root, even if a service caller bypasses normal admission.
create or replace function atlas.assert_institutional_conversation_common_root_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_common atlas.communication_conversations%rowtype;
begin
  select cc.*
  into v_common
  from atlas.institutional_conversation_roots root
  join atlas.communication_conversations cc on cc.id=root.communication_conversation_id
  where root.institutional_conversation_id=new.id;

  if v_common.id is null then
    raise exception 'Institutional Conversation % requires one common Communication Conversation root.',
      new.id using errcode='23514';
  end if;

  if v_common.principal_id is not null
     or v_common.organization_id is distinct from new.organization_id
     or v_common.organization_unit_id is distinct from new.organization_unit_id then
    raise exception 'Institutional Conversation % common root has incompatible custody.',
      new.id using errcode='23514';
  end if;
  return null;
end;
$function$;

drop trigger if exists institutional_conversation_common_root_required_v1
  on atlas.institutional_conversations;
create constraint trigger institutional_conversation_common_root_required_v1
after insert or update on atlas.institutional_conversations
deferrable initially deferred
for each row execute function atlas.assert_institutional_conversation_common_root_v1();

create or replace function atlas.assert_institutional_root_delete_safe_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if exists(
    select 1 from atlas.institutional_conversations
    where id=old.institutional_conversation_id
  ) and not exists(
    select 1 from atlas.institutional_conversation_roots
    where institutional_conversation_id=old.institutional_conversation_id
  ) then
    raise exception 'Cannot leave an Institutional Conversation without a common root.'
      using errcode='23514';
  end if;
  return null;
end;
$function$;

drop trigger if exists institutional_conversation_root_delete_required_v1
  on atlas.institutional_conversation_roots;
create constraint trigger institutional_conversation_root_delete_required_v1
after delete on atlas.institutional_conversation_roots
deferrable initially deferred
for each row execute function atlas.assert_institutional_root_delete_safe_v1();

revoke all on function atlas.guard_communication_conversation_event_v1() from public,anon,authenticated;
revoke all on function atlas.guard_institutional_conversation_root_v1() from public,anon,authenticated;
revoke all on function atlas.assert_institutional_conversation_common_root_v1() from public,anon,authenticated;
revoke all on function atlas.assert_institutional_root_delete_safe_v1() from public,anon,authenticated;

grant execute on function atlas.guard_communication_conversation_event_v1() to service_role;
grant execute on function atlas.guard_institutional_conversation_root_v1() to service_role;
grant execute on function atlas.assert_institutional_conversation_common_root_v1() to service_role;
grant execute on function atlas.assert_institutional_root_delete_safe_v1() to service_role;

commit;
