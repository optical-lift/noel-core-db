do $validation$
declare
  v_org uuid:=gen_random_uuid();
  v_endpoint uuid:=gen_random_uuid();
  v_source uuid:=gen_random_uuid();

  v_owner_user uuid:=gen_random_uuid();
  v_admin_user uuid:=gen_random_uuid();
  v_admin_sender_user uuid:=gen_random_uuid();
  v_viewer_user uuid:=gen_random_uuid();
  v_responsible_user uuid:=gen_random_uuid();

  v_owner_member uuid;
  v_admin_member uuid;
  v_admin_sender_member uuid;
  v_viewer_member uuid;
  v_responsible_member uuid;

  v_conversation uuid;
  v_case uuid;
  v_work uuid;
  v_result jsonb;
  v_identity uuid;
  v_operation uuid;
  v_count integer;
begin
  insert into auth.users(id,email,created_at,updated_at)
  values
    (v_owner_user,'authority-owner-'||substr(v_owner_user::text,1,8)||'@example.test',now(),now()),
    (v_admin_user,'authority-admin-'||substr(v_admin_user::text,1,8)||'@example.test',now(),now()),
    (v_admin_sender_user,'authority-admin-sender-'||substr(v_admin_sender_user::text,1,8)||'@example.test',now(),now()),
    (v_viewer_user,'authority-viewer-'||substr(v_viewer_user::text,1,8)||'@example.test',now(),now()),
    (v_responsible_user,'authority-responsible-'||substr(v_responsible_user::text,1,8)||'@example.test',now(),now());

  insert into atlas.organizations(id,stable_key,name)
  values(v_org,'authority-dimensions-proof-'||substr(v_org::text,1,8),'Authority Dimensions Proof');

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_owner_user,'owner',true)
  returning id into v_owner_member;

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_admin_user,'member',true)
  returning id into v_admin_member;

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_admin_sender_user,'member',true)
  returning id into v_admin_sender_member;

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_viewer_user,'member',true)
  returning id into v_viewer_member;

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_responsible_user,'member',true)
  returning id into v_responsible_member;

  insert into atlas.communication_endpoints(
    id,organization_id,endpoint_kind,address,address_normalized,display_name,endpoint_state
  ) values(
    v_endpoint,v_org,'email',
    'authority-'||substr(v_endpoint::text,1,8)||'@example.test',
    'authority-'||substr(v_endpoint::text,1,8)||'@example.test',
    'Authority Endpoint','active'
  );

  insert into atlas.communication_endpoint_member_grants(
    communication_endpoint_id,membership_id,capability,granted_by_membership_id
  ) values
    (v_endpoint,v_admin_member,'admin',v_owner_member),
    (v_endpoint,v_admin_sender_member,'admin',v_owner_member),
    (v_endpoint,v_admin_sender_member,'send',v_owner_member),
    (v_endpoint,v_viewer_member,'view',v_owner_member),
    (v_endpoint,v_responsible_member,'send',v_owner_member);

  -- Admin is exact configuration authority, not a wildcard.
  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_admin_member,'admin') then
    raise exception 'Explicit Endpoint admin grant was lost.';
  end if;

  if atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_admin_member,'view')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_admin_member,'send')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_admin_member,'claim')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_admin_member,'handoff')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_admin_member,'close') then
    raise exception 'Endpoint admin still implies a sibling Communication capability.';
  end if;

  -- Exact grants do not leak sideways.
  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_viewer_member,'view')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_viewer_member,'send')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_viewer_member,'admin') then
    raise exception 'Endpoint view capability is not exact.';
  end if;

  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_responsible_member,'send')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_responsible_member,'view')
     or atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_responsible_member,'claim') then
    raise exception 'Endpoint send capability is not exact.';
  end if;

  -- Owner wildcard is deliberately retained as first-slice compatibility.
  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner_member,'view')
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner_member,'send')
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner_member,'claim')
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner_member,'handoff')
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner_member,'close')
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint,v_owner_member,'admin') then
    raise exception 'First-slice Organization owner compatibility changed unexpectedly.';
  end if;

  -- Authenticated self helper follows the same exact-capability law.
  perform set_config('request.jwt.claim.sub',v_admin_user::text,true);
  if not atlas.communication_endpoint_authorized_self_v1(v_endpoint,'admin')
     or atlas.communication_endpoint_authorized_self_v1(v_endpoint,'view')
     or atlas.communication_endpoint_authorized_self_v1(v_endpoint,'send') then
    raise exception 'Authenticated Endpoint admin remains a wildcard.';
  end if;

  perform set_config('request.jwt.claim.sub',v_viewer_user::text,true);
  if not atlas.communication_endpoint_authorized_self_v1(v_endpoint,'view')
     or atlas.communication_endpoint_authorized_self_v1(v_endpoint,'admin')
     or atlas.communication_endpoint_authorized_self_v1(v_endpoint,'send') then
    raise exception 'Authenticated Endpoint view grant is not exact.';
  end if;

  perform set_config('request.jwt.claim.sub',v_owner_user::text,true);
  if not atlas.communication_endpoint_authorized_self_v1(v_endpoint,'view')
     or not atlas.communication_endpoint_authorized_self_v1(v_endpoint,'admin') then
    raise exception 'Authenticated Organization owner compatibility changed unexpectedly.';
  end if;

  -- Configuration administration remains available without Correspondence view.
  perform set_config('request.jwt.claim.sub',v_admin_user::text,true);
  v_result:=atlas.create_correspondence_identity_for_endpoint_self_api_v1(
    v_endpoint,'Authority Configuration Proof',null
  );
  v_identity:=(v_result->>'correspondenceIdentityId')::uuid;

  if v_identity is null
     or not atlas.correspondence_identity_manage_authorized_self_v1(v_identity)
     or atlas.communication_endpoint_authorized_self_v1(v_endpoint,'view') then
    raise exception 'Configuration administration is not independent from content visibility.';
  end if;

  -- Admin alone may not claim response responsibility.
  insert into atlas.institutional_conversations(
    organization_id,stable_key,subject,conversation_state,opened_at,last_activity_at
  ) values(
    v_org,'authority-response-'||substr(gen_random_uuid()::text,1,8),
    'Authority response proof','open',now(),now()
  ) returning id into v_conversation;

  insert into atlas.institutional_conversation_endpoints(
    institutional_conversation_id,communication_endpoint_id,endpoint_role
  ) values(v_conversation,v_endpoint,'primary');

  insert into atlas.institutional_conversation_response_cases(
    institutional_conversation_id,organization_id,case_number,case_state
  ) values(v_conversation,v_org,1,'needs_response')
  returning id into v_case;

  begin
    perform atlas.claim_institutional_conversation_self_api_v1(
      v_conversation,'admin must not imply claim'
    );
    raise exception 'Endpoint admin silently granted response-claim authority.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Build real response Work and exact responsibility.
  insert into atlas.work_items(
    organization_id,title,instructions,work_state,operation_class,jurisdiction_key,
    source_object_type,source_object_id,stable_key,metadata
  ) values(
    v_org,'Respond: authority proof',
    'Prove response responsibility is distinct from Endpoint administration.',
    'open','communication_response','communication:endpoint:'||v_endpoint::text,
    'institutional_conversation_response_case',v_case,
    'authority-response-work:'||v_case::text,
    jsonb_build_object('institutionalConversationId',v_conversation,'communicationEndpointId',v_endpoint)
  ) returning id into v_work;

  insert into atlas.institutional_conversation_response_work_bindings(
    response_case_id,work_item_id
  ) values(v_case,v_work);

  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
    allocation_role,state,metadata
  ) values(
    v_org,v_work,v_responsible_member,v_owner_member,
    'responsible','active','{"source":"authority_dimensions_clone_proof"}'::jsonb
  );

  -- Admin alone may not hand off another person's response responsibility.
  perform set_config('request.jwt.claim.sub',v_admin_user::text,true);
  begin
    perform atlas.handoff_institutional_conversation_self_api_v1(
      v_conversation,v_admin_member,'admin must not imply handoff'
    );
    raise exception 'Endpoint admin silently granted response-handoff authority.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Install one real send transport for the actual send-command proof.
  insert into atlas.connected_sources(
    id,custodian_organization_id,provider_key,provider_account_key,
    authorization_state,capabilities,metadata
  ) values(
    v_source,v_org,'authority_fixture_provider',
    'authority-account-'||substr(v_source::text,1,8),
    'connected','{"communicationSend":true}'::jsonb,
    '{"source":"authority_dimensions_clone_proof"}'::jsonb
  );

  insert into atlas.communication_endpoint_source_bindings(
    communication_endpoint_id,connected_source_id,binding_role,binding_state,transport_metadata
  ) values(
    v_endpoint,v_source,'send','active',
    '{"source":"authority_dimensions_clone_proof"}'::jsonb
  );

  -- Admin alone cannot send because admin no longer implies send.
  begin
    perform atlas.prepare_institutional_email_send_internal_v2(
      v_admin_member,v_endpoint,v_conversation,
      '[{"address":"recipient@example.test"}]'::jsonb,
      '[]'::jsonb,'[]'::jsonb,
      'Admin-only send must fail','No send authority',null,
      '[]'::jsonb,null,
      'authority-admin-only-'||substr(gen_random_uuid()::text,1,8),
      'authority_dimensions_clone_proof'
    );
    raise exception 'Endpoint admin alone silently granted send authority.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Responsible member with exact send authority may send.
  v_result:=atlas.prepare_institutional_email_send_internal_v2(
    v_responsible_member,v_endpoint,v_conversation,
    '[{"address":"recipient@example.test"}]'::jsonb,
    '[]'::jsonb,'[]'::jsonb,
    'Responsible send proof','Responsible member may send',null,
    '[]'::jsonb,null,
    'authority-responsible-'||substr(gen_random_uuid()::text,1,8),
    'authority_dimensions_clone_proof'
  );
  v_operation:=(v_result->>'outboundOperationId')::uuid;

  if v_operation is null or not exists(
    select 1
    from atlas.communication_outbound_operations o
    where o.id=v_operation
      and o.initiated_by_membership_id=v_responsible_member
      and o.operation_state='authorized'
  ) then
    raise exception 'Responsible member with exact send authority could not authorize send.';
  end if;

  -- send + admin still may not override somebody else's responsibility.
  begin
    perform atlas.prepare_institutional_email_send_internal_v2(
      v_admin_sender_member,v_endpoint,v_conversation,
      '[{"address":"recipient@example.test"}]'::jsonb,
      '[]'::jsonb,'[]'::jsonb,
      'Admin override must fail','Administration is not response takeover',null,
      '[]'::jsonb,null,
      'authority-admin-override-'||substr(gen_random_uuid()::text,1,8),
      'authority_dimensions_clone_proof'
    );
    raise exception 'Endpoint admin bypassed another member''s active response responsibility.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Lawful collaboration, not administration, permits a second sender.
  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
    allocation_role,state,metadata
  ) values(
    v_org,v_work,v_admin_sender_member,v_responsible_member,
    'participant','active','{"source":"authority_dimensions_clone_proof"}'::jsonb
  );

  v_result:=atlas.prepare_institutional_email_send_internal_v2(
    v_admin_sender_member,v_endpoint,v_conversation,
    '[{"address":"recipient@example.test"}]'::jsonb,
    '[]'::jsonb,'[]'::jsonb,
    'Collaborator send proof','Participant may send because responsibility seam admits collaboration',null,
    '[]'::jsonb,null,
    'authority-collaborator-'||substr(gen_random_uuid()::text,1,8),
    'authority_dimensions_clone_proof'
  );

  if (v_result->>'outboundOperationId') is null then
    raise exception 'Lawful response collaborator with send authority could not send.';
  end if;

  -- No hidden rewrite of responsibility occurred.
  select count(*) into v_count
  from atlas.work_allocations
  where work_item_id=v_work
    and allocation_role='responsible'
    and state='active'
    and assignee_membership_id=v_responsible_member;

  if v_count<>1 then
    raise exception 'Authority repair rewrote exact response responsibility.';
  end if;

  if exists(
    select 1
    from atlas.work_allocations
    where work_item_id=v_work
      and allocation_role='responsible'
      and state='active'
      and assignee_membership_id=v_admin_sender_member
  ) then
    raise exception 'Administration/collaboration silently became responsibility.';
  end if;

  -- Static guard: the send function must not reintroduce admin as responsibility override.
  if pg_get_functiondef(
      'atlas.prepare_institutional_email_send_internal_v2(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text)'::regprocedure
    ) ilike '%v_is_collaborator and not atlas.communication_endpoint_membership_has_capability_v1%admin%' then
    raise exception 'Send function still contains Endpoint admin responsibility override.';
  end if;
end;
$validation$;
