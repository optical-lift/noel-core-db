-- Smart Contacts saved-search / dynamic-audience v1 validation.
-- Read-only production assertions.

select
  to_regclass('atlas.smart_contact_saved_searches') as saved_searches,
  to_regclass('atlas.smart_contact_saved_search_runs') as runs,
  to_regclass('atlas.smart_contact_saved_search_run_items') as run_items,
  to_regclass('atlas.smart_contact_saved_search_run_deltas') as run_deltas,
  to_regprocedure('atlas.create_smart_contact_saved_search_service_v1(uuid,text,jsonb,text,text,integer,boolean,text,jsonb,uuid,uuid)') as create_contract,
  to_regprocedure('atlas.run_smart_contact_saved_search_service_v1(uuid)') as run_contract,
  to_regprocedure('atlas.smart_contact_saved_search_service_v1(uuid)') as read_contract,
  to_regprocedure('atlas.create_contact_selection_packet_from_saved_search_run_service_v1(uuid,uuid,uuid)') as packet_from_run_contract;

select
  s.stable_key,
  s.name,
  s.watch_enabled,
  s.watch_cadence,
  s.last_run_at,
  r.run_number,
  r.result_count,
  r.new_count,
  r.updated_count,
  r.removed_count,
  r.completed_at
from atlas.smart_contact_saved_searches s
left join lateral (
  select *
  from atlas.smart_contact_saved_search_runs r
  where r.saved_search_id=s.id and r.run_state='completed'
  order by r.run_number desc
  limit 1
) r on true
where s.organization_id=(select id from atlas.organizations where stable_key='feast_guild')
order by s.stable_key;

select
  tgrelid::regclass::text as relation_name,
  tgname,
  pg_get_triggerdef(oid) as trigger_def
from pg_trigger
where tgrelid in (
  'atlas.smart_contact_saved_search_runs'::regclass,
  'atlas.smart_contact_saved_search_run_items'::regclass,
  'atlas.smart_contact_saved_search_run_deltas'::regclass
)
and not tgisinternal
order by relation_name,tgname;

select count(er.id) as feast_guild_relationships
from atlas.organizations o
left join atlas.external_relationships er on er.organization_id=o.id
where o.stable_key='feast_guild';
