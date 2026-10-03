begin;
select set_config('request.jwt.claim.sub','4cd799e2-16d4-4020-9d21-ccf1a2b98553',true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','4cd799e2-16d4-4020-9d21-ccf1a2b98553',
    'role','authenticated',
    'session_id','4c765d6f-833d-4e4e-bb3f-f685682eab16'
  )::text,
  true
);

select
  (atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','message.send'
  )->>'allowed')::boolean as send_allowed,
  not (atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','conversation.claim'
  )->>'allowed')::boolean as claim_blocked,
  atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','conversation.claim'
  )->>'reason' as claim_reason;

select
  pg_get_functiondef(
    'atlas.communication_email_drafts_self_v1(uuid,uuid)'::regprocedure
  ) not ilike '%communication_endpoint_membership_has_capability_v1%' as draft_read_cut,
  pg_get_functiondef(
    'atlas.save_communication_email_draft_compatibility_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamp with time zone,jsonb)'::regprocedure
  ) not ilike '%communication_endpoint_membership_has_capability_v1%' as draft_write_cut,
  pg_get_functiondef(
    'atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text)'::regprocedure
  ) not ilike '%organization_memberships%' as common_send_cut,
  pg_get_functiondef(
    'atlas.prepare_institutional_email_send_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text)'::regprocedure
  ) not ilike '%organization_memberships%' as institutional_send_cut;

rollback;
