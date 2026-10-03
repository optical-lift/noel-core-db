-- Atlas Reality responsibility authority v1 validation

select
  count(*) as active_responsibilities
from reality.responsibility_relations
where relation_state='active';

select
  responsibility_key,
  jurisdiction_kind,
  jurisdiction_entity_id,
  jurisdiction_domain,
  permitted_operations,
  scope
from reality.responsibility_relations
where carrier_person_entity_id=(
  select id from reality.entities where stable_key='lex'
)
order by responsibility_key;

select
  reality.resolve_responsibility_relation_v1(
    (select id from reality.entities where stable_key='lex'),
    'reality_identity_adjudication',
    'identity_review.adjudicate',
    'domain',
    null,
    'reality.identity_resolution',
    '{"reviewKinds":["entity_merge"]}'::jsonb
  ) is not null as identity_adjudication_resolves,
  reality.resolve_responsibility_relation_v1(
    (select id from reality.entities where stable_key='lex'),
    'reality_identity_adjudication',
    'canonical_merge.execute',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  ) is null as canonical_merge_not_granted;

select
  reality.resolve_responsibility_relation_v1(
    (select id from reality.entities where stable_key='lex'),
    'institutional_worker_capacity_truth',
    'worker_day_shape.author',
    'entity',
    (select id from reality.entities where stable_key='elm-farm'),
    null,
    jsonb_build_object('farmIds',jsonb_build_array('6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'))
  ) is not null as elm_capacity_resolves,
  reality.resolve_responsibility_relation_v1(
    (select id from reality.entities where stable_key='lex'),
    'institutional_worker_capacity_truth',
    'worker_day_shape.author',
    'entity',
    (select id from reality.entities where stable_key='elm-farm'),
    null,
    jsonb_build_object('farmIds',jsonb_build_array('f6592422-cf2b-4375-ba8f-f00828a05c18'))
  ) is null as waiting_room_not_granted;

select
  pg_get_functiondef('atlas.entity_identity_adjudicate_api_v2(jsonb)'::regprocedure)
    not ilike '%organization_memberships%' as identity_v2_no_org_membership,
  pg_get_functiondef('atlas.entity_identity_adjudicate_api_v2(jsonb)'::regprocedure)
    not ilike '%current_principal_id_v1%' as identity_v2_no_principal,
  pg_get_functiondef(
    'atlas.institutional_worker_day_shape_set_self_api_v1(uuid,uuid,smallint[],time without time zone,time without time zone,date,text)'::regprocedure
  ) not ilike '%is_farm_owner%' as capacity_v1_no_owner_helper;

select
  p.proname,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'current_responsibility_context_self_api_v1',
    'entity_identity_review_queue_api_v2',
    'entity_identity_adjudicate_api_v2',
    'institutional_worker_day_shape_set_self_api_v1'
  )
order by p.proname;
