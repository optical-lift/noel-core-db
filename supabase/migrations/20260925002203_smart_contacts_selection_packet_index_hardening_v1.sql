create index if not exists contact_selection_packets_org_request_idx
  on atlas.contact_selection_packets(organization_id,request_id);
create index if not exists contact_selection_packets_unit_org_idx
  on atlas.contact_selection_packets(organization_id,organization_unit_id)
  where organization_unit_id is not null;
create index if not exists contact_selection_packets_supersedes_idx
  on atlas.contact_selection_packets(supersedes_packet_id)
  where supersedes_packet_id is not null;
create index if not exists contact_selection_packets_created_membership_idx
  on atlas.contact_selection_packets(created_by_membership_id)
  where created_by_membership_id is not null;
create index if not exists contact_selection_packets_confirmed_membership_idx
  on atlas.contact_selection_packets(confirmed_by_membership_id)
  where confirmed_by_membership_id is not null;
create index if not exists contact_selection_packet_events_org_idx
  on atlas.contact_selection_packet_events(organization_id,created_at);
create index if not exists contact_selection_packet_events_actor_idx
  on atlas.contact_selection_packet_events(actor_membership_id)
  where actor_membership_id is not null;