select
  (atlas.current_institutional_communication_context_self_api_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f'
  )->'operations'->'message.send'->>'allowed')::boolean as send_allowed,
  (atlas.current_institutional_communication_context_self_api_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f'
  )->'operations'->'conversation.claim'->>'allowed')::boolean as claim_allowed,
  atlas.current_institutional_communication_context_self_api_v1(
    '7617a7b1-8713-4520-923f-51a15c6b2d7f'
  )->'operations'->'conversation.claim'->>'reason' as claim_reason;

select
  pg_get_functiondef(
    'atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text)'::regprocedure
  ) not ilike '%organization_memberships%' as send_edge_no_membership,
  pg_get_functiondef(
    'atlas.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb)'::regprocedure
  ) not ilike '%organization_memberships%' as attachment_prepare_no_membership,
  pg_get_functiondef(
    'atlas.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint)'::regprocedure
  ) not ilike '%organization_memberships%' as attachment_confirm_no_membership,
  pg_get_functiondef(
    'atlas.communication_outbound_attachment_storage_authorized_self_v1(text,text,text)'::regprocedure
  ) not ilike '%organization_memberships%' as attachment_storage_no_membership,
  pg_get_functiondef(
    'atlas.save_communication_email_draft_compatibility_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)'::regprocedure
  ) not ilike '%organization_memberships%' as draft_write_no_membership;
