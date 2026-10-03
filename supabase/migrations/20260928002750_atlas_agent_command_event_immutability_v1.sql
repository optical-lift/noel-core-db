create or replace function atlas.reject_agent_command_event_mutation_v1()
returns trigger
language plpgsql
as $$
begin
  raise exception 'agent command invocation events are append-only';
end;
$$;

drop trigger if exists agent_command_invocation_events_immutable on atlas.agent_command_invocation_events;
create trigger agent_command_invocation_events_immutable
before update or delete on atlas.agent_command_invocation_events
for each row execute function atlas.reject_agent_command_event_mutation_v1();