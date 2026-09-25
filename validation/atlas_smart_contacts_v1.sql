-- Atlas Smart Contacts v1 production validation.
-- Read-only.

with fg as (
  select id from atlas.organizations where stable_key='feast_guild' and status='active'
)
select atlas.smart_contacts_search_service_v1(
  fg.id,
  jsonb_build_object(
    'entityTypes',jsonb_build_array('business'),
    'signalKeys',jsonb_build_array('local_sourcing','commercial_buyer'),
    'signalMode','all',
    'requireNamedPerson',true,
    'requiredContactTypes',jsonb_build_array('email'),
    'relationship','unrelated'
  ),
  10
)
from fg;

with fg as (
  select id from atlas.organizations where stable_key='feast_guild' and status='active'
)
select atlas.smart_contacts_search_service_v1(
  fg.id,
  jsonb_build_object(
    'entityTypes',jsonb_build_array('business'),
    'signalKeys',jsonb_build_array('wholesale_supplier'),
    'signalMode','all',
    'relationship','unrelated'
  ),
  20
)
from fg;

with fg as (
  select id from atlas.organizations where stable_key='feast_guild' and status='active'
)
select count(er.id) as feast_guild_relationships_after_read_only_search
from fg
left join atlas.external_relationships er on er.organization_id=fg.id;

select
  to_regprocedure('atlas.smart_contacts_search_service_v1(uuid,jsonb,integer)') as service_contract,
  to_regprocedure('atlas.smart_contacts_search_self_api_v1(uuid,jsonb,integer)') as authenticated_contract,
  to_regclass('local_intel.v_smart_contact_signals_v1') as semantic_signal_projection;
