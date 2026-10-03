-- Smart Contacts selection packet v1 validation.
-- Read-only checks against deployed production contracts.
-- The end-to-end mutation/freeze proof is designed to run inside BEGIN/ROLLBACK when executed manually.

select
  to_regclass('atlas.contact_selection_packets') as packets_table,
  to_regclass('atlas.contact_selection_packet_items') as packet_items_table,
  to_regclass('atlas.contact_selection_packet_events') as packet_events_table,
  to_regprocedure('atlas.create_contact_selection_packet_service_v1(uuid,jsonb,integer,uuid)') as create_service,
  to_regprocedure('atlas.set_contact_selection_packet_selection_service_v1(uuid,uuid[],integer,uuid)') as edit_service,
  to_regprocedure('atlas.confirm_contact_selection_packet_service_v1(uuid,integer,uuid)') as confirm_service,
  to_regprocedure('atlas.prepare_contact_set_execution_from_selection_packet_service_v1(uuid)') as handoff_service,
  to_regprocedure('atlas.contact_selection_packet_self_api_v1(uuid)') as read_self_api;

select
  tgname,
  pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid in (
  'atlas.contact_selection_packets'::regclass,
  'atlas.contact_selection_packet_items'::regclass
)
and not tgisinternal
order by tgrelid::regclass::text,tgname;

select
  c.relname,
  c.relrowsecurity
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='atlas'
  and c.relname in (
    'contact_selection_packets',
    'contact_selection_packet_items',
    'contact_selection_packet_events'
  )
order by c.relname;

select count(er.id) as feast_guild_relationships
from atlas.organizations o
left join atlas.external_relationships er on er.organization_id=o.id
where o.stable_key='feast_guild';
