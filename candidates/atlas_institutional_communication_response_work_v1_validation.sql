select rr.id,rr.responsibility_key,rr.permitted_operations,rr.scope
from reality.responsibility_relations rr
where rr.responsibility_key='institutional_communication_response_work'
  and rr.relation_state='active';

select
  pg_get_functiondef('atlas.claim_institutional_conversation_self_api_v1(uuid,text)'::regprocedure)
    not ilike '%organization_memberships%' as claim_no_membership_lookup,
  pg_get_functiondef('atlas.claim_institutional_conversation_self_api_v1(uuid,text)'::regprocedure)
    not ilike '%communication_endpoint_membership_has_capability_v1%' as claim_no_legacy_authority,
  pg_get_functiondef('atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)'::regprocedure)
    not ilike '%communication_endpoint_membership_has_capability_v1%' as response_state_no_endpoint_override,
  pg_get_functiondef('atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)'::regprocedure)
    not ilike '%communication_endpoint_membership_has_capability_v1%' as handoff_no_legacy_authority;
