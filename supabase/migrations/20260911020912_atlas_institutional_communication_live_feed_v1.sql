begin;

create table atlas.institutional_communication_live_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id) on delete cascade,
  institutional_conversation_id uuid references atlas.institutional_conversations(id) on delete cascade,
  communication_event_id uuid references atlas.communication_events(id) on delete cascade,
  response_case_id uuid references atlas.institutional_conversation_response_cases(id) on delete cascade,
  event_kind text not null check (event_kind in ('message_admitted','attention_changed','response_changed','transport_changed')),
  actor_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  foreign key (organization_id,organization_unit_id) references atlas.organization_units(organization_id,id) on delete restrict
);
create index institutional_communication_live_events_endpoint_idx on atlas.institutional_communication_live_events(communication_endpoint_id,id desc);
comment on table atlas.institutional_communication_live_events is 'Minimal append-only Realtime wake-up feed for institutional communication UI. It carries IDs and change kinds, not message bodies; clients re-read governed inbox/detail RPCs after a permitted event.';

create trigger institutional_communication_live_events_append_only_v1 before update or delete on atlas.institutional_communication_live_events for each row execute function atlas.prevent_institutional_response_history_mutation_v1();

create or replace function atlas.emit_institutional_communication_live_event_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_conv_id uuid; v_endpoint_id uuid; v_org_id uuid; v_unit_id uuid; v_event_id uuid; v_case_id uuid; v_actor uuid; v_kind text;
begin
  if tg_table_name='institutional_conversation_messages' then
    v_conv_id:=new.institutional_conversation_id; v_endpoint_id:=new.communication_endpoint_id; v_event_id:=new.communication_event_id; v_kind:='message_admitted';
    select organization_id,organization_unit_id into v_org_id,v_unit_id from atlas.institutional_conversations where id=v_conv_id;
  elsif tg_table_name='communication_attention_events' then
    v_conv_id:=new.institutional_conversation_id; v_event_id:=new.communication_event_id; v_actor:=new.membership_id; v_kind:='attention_changed';
    select c.organization_id,c.organization_unit_id,ce.communication_endpoint_id into v_org_id,v_unit_id,v_endpoint_id
    from atlas.institutional_conversations c
    join lateral (select communication_endpoint_id from atlas.institutional_conversation_endpoints x where x.institutional_conversation_id=c.id order by case x.endpoint_role when 'primary' then 0 else 1 end,x.created_at limit 1) ce on true
    where c.id=v_conv_id;
  elsif tg_table_name='institutional_conversation_response_events' then
    v_conv_id:=new.institutional_conversation_id; v_event_id:=new.related_communication_event_id; v_case_id:=new.response_case_id; v_actor:=new.actor_membership_id; v_kind:='response_changed';
    select c.organization_id,c.organization_unit_id,ce.communication_endpoint_id into v_org_id,v_unit_id,v_endpoint_id
    from atlas.institutional_conversations c
    join lateral (select communication_endpoint_id from atlas.institutional_conversation_endpoints x where x.institutional_conversation_id=c.id order by case x.endpoint_role when 'primary' then 0 else 1 end,x.created_at limit 1) ce on true
    where c.id=v_conv_id;
  else
    return new;
  end if;
  if v_endpoint_id is not null and v_org_id is not null then
    insert into atlas.institutional_communication_live_events(organization_id,organization_unit_id,communication_endpoint_id,institutional_conversation_id,communication_event_id,response_case_id,event_kind,actor_membership_id,metadata)
    values(v_org_id,v_unit_id,v_endpoint_id,v_conv_id,v_event_id,v_case_id,v_kind,v_actor,jsonb_build_object('sourceTable',tg_table_name));
  end if;
  return new;
end;$function$;

drop trigger if exists institutional_conversation_message_live_event_v1 on atlas.institutional_conversation_messages;
create trigger institutional_conversation_message_live_event_v1 after insert on atlas.institutional_conversation_messages for each row execute function atlas.emit_institutional_communication_live_event_v1();
drop trigger if exists communication_attention_live_event_v1 on atlas.communication_attention_events;
create trigger communication_attention_live_event_v1 after insert on atlas.communication_attention_events for each row execute function atlas.emit_institutional_communication_live_event_v1();
drop trigger if exists institutional_response_live_event_v1 on atlas.institutional_conversation_response_events;
create trigger institutional_response_live_event_v1 after insert on atlas.institutional_conversation_response_events for each row execute function atlas.emit_institutional_communication_live_event_v1();

alter table atlas.institutional_communication_live_events enable row level security;
create policy institutional_communication_live_events_member_read
on atlas.institutional_communication_live_events for select to authenticated
using (
  exists(
    select 1 from atlas.organization_memberships om
    where om.organization_id=institutional_communication_live_events.organization_id
      and om.user_id=auth.uid() and om.active
      and atlas.communication_endpoint_membership_has_capability_v1(institutional_communication_live_events.communication_endpoint_id,om.id,'view')
  )
);
revoke all on atlas.institutional_communication_live_events from public,anon;
grant select on atlas.institutional_communication_live_events to authenticated;
grant all on atlas.institutional_communication_live_events to service_role;

revoke all on function atlas.emit_institutional_communication_live_event_v1() from public,anon,authenticated;
grant execute on function atlas.emit_institutional_communication_live_event_v1() to service_role;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
    select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='atlas' and tablename='institutional_communication_live_events'
  ) then
    execute 'alter publication supabase_realtime add table atlas.institutional_communication_live_events';
  end if;
end $$;

commit;