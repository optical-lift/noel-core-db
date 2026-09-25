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

select atlas.current_institutional_communication_context_self_api_v1(
  '7617a7b1-8713-4520-923f-51a15c6b2d7f'
) as context;

select
  (atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','message.send'
  )->>'allowed')::boolean as send_allowed,
  (atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','draft.write'
  )->>'allowed')::boolean as draft_write_allowed,
  not (atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','conversation.claim'
  )->>'allowed')::boolean as claim_blocked,
  atlas.resolve_institutional_communication_operation_self_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f','conversation.claim'
  )->>'reason' as claim_reason;

rollback;
