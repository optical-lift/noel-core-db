-- Scheduled Mailroom delivery must be an explicit action against an activated send transport.
-- A legitimately scheduled draft may wait through a later outage, but no latent schedule may be
-- created while the endpoint has no connected communicationSend transport.

begin;

create or replace function atlas.guard_communication_email_draft_schedule_activation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
begin
  if new.draft_state = 'scheduled' then
    if new.send_after is null or new.send_after <= now() then
      raise exception 'Scheduled mail requires a future send time.' using errcode='22023';
    end if;

    if not exists (
      select 1
      from atlas.communication_endpoint_source_bindings b
      join atlas.connected_sources s on s.id = b.connected_source_id
      where b.communication_endpoint_id = new.communication_endpoint_id
        and b.binding_state = 'active'
        and b.binding_role in ('send','send_receive')
        and s.authorization_state = 'connected'
        and s.capabilities @> '{"communicationSend":true}'::jsonb
    ) then
      raise exception 'Sending must be activated before a draft can be scheduled.' using errcode='55000';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_communication_email_draft_schedule_activation_v1() from public, anon, authenticated;

drop trigger if exists communication_email_drafts_schedule_activation_v1 on atlas.communication_email_drafts;
create trigger communication_email_drafts_schedule_activation_v1
before insert or update of draft_state, send_after on atlas.communication_email_drafts
for each row
execute function atlas.guard_communication_email_draft_schedule_activation_v1();

commit;
