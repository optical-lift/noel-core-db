begin;

-- The public browser wrappers are SECURITY INVOKER by design. Allow the
-- authenticated browser role to enter only these two internal v2 read
-- projections; each projection still requires auth.uid() and endpoint view
-- capability before returning institutional communication data. The atlas
-- schema itself remains outside the exposed Data API schema list.
revoke all on function atlas.institutional_shared_inbox_self_v2(uuid, integer)
  from public, anon;
revoke all on function atlas.institutional_conversation_detail_self_v2(uuid)
  from public, anon;

grant execute on function atlas.institutional_shared_inbox_self_v2(uuid, integer)
  to authenticated, service_role;
grant execute on function atlas.institutional_conversation_detail_self_v2(uuid)
  to authenticated, service_role;

comment on function atlas.institutional_shared_inbox_self_v2(uuid, integer) is
  'Authenticated institutional inbox v2 projection. Direct execution still self-authorizes by auth.uid() and endpoint view capability; public browser access is through the public SECURITY INVOKER membrane.';

comment on function atlas.institutional_conversation_detail_self_v2(uuid) is
  'Authenticated institutional conversation detail v2 projection. Direct execution still self-authorizes by auth.uid() and endpoint view capability; public browser access is through the public SECURITY INVOKER membrane.';

commit;
