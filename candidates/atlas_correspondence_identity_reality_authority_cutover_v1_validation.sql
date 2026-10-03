select
  rr.id,rr.responsibility_key,rr.jurisdiction_entity_id,rr.permitted_operations,rr.scope
from reality.responsibility_relations rr
where rr.responsibility_key='institutional_correspondence_administration'
  and rr.relation_state='active';

select
  pg_get_functiondef(
    'atlas.correspondence_identity_manage_authorized_self_v1(uuid)'::regprocedure
  ) not ilike '%organization_memberships%' as manage_no_org_membership,
  pg_get_functiondef(
    'atlas.correspondence_identity_read_authorized_self_v1(uuid)'::regprocedure
  ) not ilike '%organization_memberships%' as read_no_org_membership,
  pg_get_functiondef(
    'atlas.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text)'::regprocedure
  ) not ilike '%organization_memberships%' as create_no_org_membership,
  pg_get_functiondef(
    'atlas.bind_correspondence_identity_endpoint_self_api_v1(uuid,uuid)'::regprocedure
  ) not ilike '%organization_memberships%' as bind_no_org_membership;
