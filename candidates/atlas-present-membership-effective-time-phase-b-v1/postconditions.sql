-- Behavioral postconditions for Present Organization Membership Effective Time Phase B.
-- Run only in a disposable production-schema clone after fixture.sql + candidate.sql.

do $proof$
declare
  main_org constant uuid := 'eb010000-0000-4000-8000-000000000001'::uuid;
  noctx_org constant uuid := 'eb020000-0000-4000-8000-000000000001'::uuid;
  endpoint_id constant uuid := 'eb010000-0000-4000-8000-000000000801'::uuid;
  source_id constant uuid := 'eb010000-0000-4000-8000-000000000701'::uuid;
  work_id constant uuid := 'eb010000-0000-4000-8000-000000000501'::uuid;
  allocation_id constant uuid := 'eb010000-0000-4000-8000-000000000511'::uuid;

  current_uid constant uuid := 'eb100000-0000-4000-8000-000000000001'::uuid;
  owner_uid constant uuid := 'eb200000-0000-4000-8000-000000000001'::uuid;
  future_uid constant uuid := 'eb300000-0000-4000-8000-000000000001'::uuid;
  expired_uid constant uuid := 'eb400000-0000-4000-8000-000000000001'::uuid;
  unbounded_noctx_uid constant uuid := 'eb500000-0000-4000-8000-000000000001'::uuid;
  setup_uid constant uuid := 'eb600000-0000-4000-8000-000000000001'::uuid;
  bounded_noctx_uid constant uuid := 'eb700000-0000-4000-8000-000000000001'::uuid;

  current_member constant uuid := 'eb100000-0000-4000-8000-000000000031'::uuid;
  current_owner constant uuid := 'eb200000-0000-4000-8000-000000000031'::uuid;
  future_owner constant uuid := 'eb300000-0000-4000-8000-000000000031'::uuid;
  expired_member constant uuid := 'eb400000-0000-4000-8000-000000000031'::uuid;
  unbounded_noctx constant uuid := 'eb500000-0000-4000-8000-000000000031'::uuid;
  bounded_noctx constant uuid := 'eb700000-0000-4000-8000-000000000031'::uuid;

  v_result jsonb;
  v_grant jsonb;
  v_upsert jsonb;
  v_compat_grant uuid;
  v_failed boolean;
  v_begin date;
  v_end date;
  v_count integer;
begin
  -- 1. Exact present-effective law: current bounded yes; future/expired no.
  if not atlas.organization_membership_present_effective_at_v1(
       current_member,main_org,now()
     ) then
    raise exception 'Current bounded Membership did not resolve present-effective.';
  end if;

  if atlas.organization_membership_present_effective_at_v1(
       future_owner,main_org,now()
     ) then
    raise exception 'Future-dated Membership resolved present-effective.';
  end if;

  if atlas.organization_membership_present_effective_at_v1(
       expired_member,main_org,now()
     ) then
    raise exception 'Expired Membership resolved present-effective.';
  end if;

  -- 2. Unbounded Membership needs no calendar context; bounded Membership does.
  if not atlas.organization_membership_present_effective_at_v1(
       unbounded_noctx,noctx_org,now()
     ) then
    raise exception 'Unbounded active Membership incorrectly required Calendar Context.';
  end if;

  if atlas.organization_membership_present_effective_at_v1(
       bounded_noctx,noctx_org,now()
     ) then
    raise exception 'Bounded Membership without Calendar Context did not fail closed.';
  end if;

  -- 3. Both current Membership resolvers share the same present law.
  perform set_config('request.jwt.claim.sub',current_uid::text,true);
  if atlas.current_effective_organization_membership_v1(main_org) is distinct from current_member
     or atlas.current_organization_membership_v1(main_org) is distinct from current_member then
    raise exception 'Current bounded Membership did not resolve through both current helpers.';
  end if;

  perform set_config('request.jwt.claim.sub',future_uid::text,true);
  if atlas.current_effective_organization_membership_v1(main_org) is not null
     or atlas.current_organization_membership_v1(main_org) is not null then
    raise exception 'Future Membership leaked through a current Membership resolver.';
  end if;

  perform set_config('request.jwt.claim.sub',expired_uid::text,true);
  if atlas.current_effective_organization_membership_v1(main_org) is not null
     or atlas.current_organization_membership_v1(main_org) is not null then
    raise exception 'Expired Membership leaked through a current Membership resolver.';
  end if;

  perform set_config('request.jwt.claim.sub',unbounded_noctx_uid::text,true);
  if atlas.current_effective_organization_membership_v1(noctx_org) is distinct from unbounded_noctx
     or atlas.current_organization_membership_v1(noctx_org) is distinct from unbounded_noctx then
    raise exception 'Unbounded no-context Membership did not resolve current.';
  end if;

  perform set_config('request.jwt.claim.sub',bounded_noctx_uid::text,true);
  if atlas.current_effective_organization_membership_v1(noctx_org) is not null
     or atlas.current_organization_membership_v1(noctx_org) is not null then
    raise exception 'Bounded no-context Membership leaked through current resolver.';
  end if;

  -- 4. Owner Membership authority uses present effectiveness; Principal root governance remains independent.
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  if not atlas.is_organization_owner(main_org)
     or not atlas.is_effective_organization_owner_v1(main_org) then
    raise exception 'Current bounded owner lost lawful Organization governance.';
  end if;

  perform set_config('request.jwt.claim.sub',future_uid::text,true);
  if atlas.is_organization_owner(main_org) then
    raise exception 'Future owner Membership was treated as current owner.';
  end if;
  if not atlas.is_effective_organization_owner_v1(main_org) then
    raise exception 'Independent Principal Ledger root governance was collapsed into Membership.';
  end if;

  -- 5. Explicit service-date eligibility is unchanged.
  select eligibility_begins_on,eligibility_ends_on
    into v_begin,v_end
  from atlas.organization_memberships
  where id=current_member;

  if atlas.organization_membership_eligible_on_date_v1(
       current_member,main_org,v_begin-1
     )
     or not atlas.organization_membership_eligible_on_date_v1(
       current_member,main_org,v_begin
     )
     or not atlas.organization_membership_eligible_on_date_v1(
       current_member,main_org,v_end
     )
     or atlas.organization_membership_eligible_on_date_v1(
       current_member,main_org,v_end+1
     ) then
    raise exception 'Explicit service-date Membership eligibility semantics changed.';
  end if;

  -- 6. Exact Endpoint capability composes with present-effective Membership.
  if not atlas.communication_endpoint_membership_has_capability_v1(
       endpoint_id,current_member,'view'
     ) then
    raise exception 'Exact Endpoint grant + current bounded Membership was denied.';
  end if;

  if atlas.communication_endpoint_membership_has_capability_v1(
       endpoint_id,future_owner,'view'
     ) then
    raise exception 'Exact Endpoint grant resurrected future Membership authority.';
  end if;

  if atlas.communication_endpoint_membership_has_capability_v1(
       endpoint_id,expired_member,'view'
     ) then
    raise exception 'Exact Endpoint grant resurrected expired Membership authority.';
  end if;

  -- 7. New authority cannot be granted to a future Membership.
  v_failed:=false;
  begin
    insert into atlas.communication_endpoint_member_grants(
      communication_endpoint_id,membership_id,capability,grant_state,
      granted_by_membership_id,grant_basis_kind,metadata
    ) values (
      endpoint_id,future_owner,'send','active',
      current_owner,'explicit_owner_grant',
      '{"validation_fixture":true,"attempt":"future_grant"}'::jsonb
    );
  exception when sqlstate '23514' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Future Membership received new Endpoint authority.';
  end if;

  -- 8. Present-effective bounded owner may govern Endpoint grants.
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  v_grant:=atlas.set_communication_endpoint_member_capability_self_api_v1(
    endpoint_id,current_member,'send',true,'phase b validation'
  );
  if coalesce((v_grant->>'enabled')::boolean,false) is not true
     or not atlas.communication_endpoint_membership_has_capability_v1(
       endpoint_id,current_member,'send'
     ) then
    raise exception 'Current bounded owner could not grant exact Endpoint authority: %',v_grant;
  end if;

  -- Stale grants may still be revoked even when the target is no longer present-effective.
  v_grant:=atlas.set_communication_endpoint_member_capability_self_api_v1(
    endpoint_id,future_owner,'view',false,'revoke stale future grant'
  );
  if exists(
    select 1 from atlas.communication_endpoint_member_grants
    where communication_endpoint_id=endpoint_id
      and membership_id=future_owner
      and capability='view'
      and grant_state='active'
  ) then
    raise exception 'Current owner could not revoke stale future-member Endpoint grant.';
  end if;

  -- 9. Present-effective bounded owner may configure a new Endpoint.
  v_upsert:=atlas.upsert_communication_endpoint_self_api_v1(
    main_org,null,'email','phase-b-bounded-owner@example.test',
    'Phase B Bounded Owner Endpoint','{"validation_fixture":true}'::jsonb
  );
  if coalesce((v_upsert->>'created')::boolean,false) is not true then
    raise exception 'Current bounded owner could not configure Endpoint: %',v_upsert;
  end if;

  -- 10. Owner compatibility grant is terminal across a temporal gap.
  insert into atlas.communication_endpoint_member_grants(
    communication_endpoint_id,membership_id,capability,grant_state,
    granted_by_membership_id,grant_basis_kind,metadata
  ) values (
    endpoint_id,current_owner,'admin','active',
    null,'organization_owner_compatibility_cutover',
    '{"validation_fixture":true,"continuity_test":true}'::jsonb
  )
  returning id into v_compat_grant;

  update atlas.organization_memberships
  set eligibility_begins_on=current_date+40,
      eligibility_ends_on=current_date+80
  where id=current_owner;

  if not exists(
    select 1 from atlas.communication_endpoint_member_grants
    where id=v_compat_grant
      and grant_state='revoked'
      and revoked_at is not null
  ) then
    raise exception 'Owner compatibility grant survived loss of present-effective Membership.';
  end if;

  update atlas.organization_memberships
  set eligibility_begins_on=current_date-30,
      eligibility_ends_on=current_date+30
  where id=current_owner;

  if exists(
    select 1 from atlas.communication_endpoint_member_grants
    where id=v_compat_grant and grant_state='active'
  ) then
    raise exception 'Owner compatibility grant resurrected after a temporal gap.';
  end if;

  -- 11. Connected Source read and management remain distinct.
  perform set_config('request.jwt.claim.sub',current_uid::text,true);
  select count(*)::integer into v_count
  from atlas.connected_sources_self_api_v1()
  where source_id=source_id;
  if v_count<>1 then
    raise exception 'Present-effective ordinary member lost Organization Connected Source read visibility.';
  end if;

  perform set_config('request.jwt.claim.sub',future_uid::text,true);
  select count(*)::integer into v_count
  from atlas.connected_sources_self_api_v1()
  where source_id=source_id;
  if v_count<>0 then
    raise exception 'Future Membership could read Organization Connected Source.';
  end if;
  if atlas.organization_connected_source_authorized_self_v1(main_org) then
    raise exception 'Future owner/root Principal incorrectly gained Connected Source management authority.';
  end if;

  perform set_config('request.jwt.claim.sub',setup_uid::text,true);
  select count(*)::integer into v_count
  from atlas.connected_sources_self_api_v1()
  where source_id=source_id;
  if v_count<>1
     or not atlas.organization_connected_source_authorized_self_v1(main_org) then
    raise exception 'Active setup_actor lost lawful Connected Source onboarding authority/read.';
  end if;

  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  if not atlas.organization_connected_source_authorized_self_v1(main_org) then
    raise exception 'Current bounded owner lost Connected Source management authority.';
  end if;

  -- 12. Employee credentials/seats/appointments cannot resurrect future Membership.
  v_result:=atlas.organization_employee_appointments_by_auth_user_v1(
    current_uid,main_org
  );
  if jsonb_array_length(v_result->'items')<>1 then
    raise exception 'Current bounded employee appointment did not project: %',v_result;
  end if;

  v_result:=atlas.organization_employee_appointments_by_auth_user_v1(
    future_uid,main_org
  );
  if jsonb_array_length(v_result->'items')<>0 then
    raise exception 'Future Membership leaked through employee appointment projection: %',v_result;
  end if;

  -- 13. Organization employee access projection follows the same Membership law.
  perform set_config('request.jwt.claim.sub',current_uid::text,true);
  v_result:=atlas.organization_access_physical_compatibility_internal_v1();
  if jsonb_array_length(v_result->'items')<>1 then
    raise exception 'Current bounded employee access did not project: %',v_result;
  end if;

  perform set_config('request.jwt.claim.sub',future_uid::text,true);
  v_result:=atlas.organization_access_physical_compatibility_internal_v1();
  if jsonb_array_length(v_result->'items')<>0 then
    raise exception 'Future Membership leaked through Organization access: %',v_result;
  end if;

  if pg_get_functiondef(
       'atlas.current_session_context_physical_compatibility_internal_v1()'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%' then
    raise exception 'Current session Organization Membership projection did not bind to present-effective law.';
  end if;

  -- 14. Company Work present-action seams use present-effective Membership.
  perform set_config('request.jwt.claim.sub',owner_uid::text,true);
  if not atlas.can_schedule_company_work_v1(work_id)
     or not atlas.can_adjudicate_company_work_v1(work_id)
     or atlas.company_work_planning_actor_membership_v1(work_id) is distinct from current_owner then
    raise exception 'Current bounded owner could not perform present Company Work governance/planning.';
  end if;

  perform set_config('request.jwt.claim.sub',future_uid::text,true);
  if atlas.can_schedule_company_work_v1(work_id)
     or atlas.can_adjudicate_company_work_v1(work_id)
     or atlas.company_work_planning_actor_membership_v1(work_id) is not null then
    raise exception 'Future Membership leaked through Company Work present-action authority.';
  end if;

  -- 15. Historical Work allocation identity survives the cutover unchanged.
  if not exists(
    select 1
    from atlas.work_allocations a
    where a.id=allocation_id
      and a.organization_id=main_org
      and a.work_item_id=work_id
      and a.assignee_membership_id=expired_member
      and a.assigned_by_membership_id=current_owner
      and a.allocation_role='responsible'
      and a.state='completed'
      and a.completed_at is not null
      and a.metadata->>'historical_truth'='true'
  ) then
    raise exception 'Historical Work allocation was rewritten or lost.';
  end if;

  -- 16. Canonical predicate remains internal and has no ambient timezone fallback.
  if has_function_privilege(
       'authenticated',
       'atlas.organization_membership_present_effective_at_v1(uuid,uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Exact present-effective Membership predicate leaked to browser role.';
  end if;

  if pg_get_functiondef(
       'atlas.organization_membership_present_effective_at_v1(uuid,uuid,timestamptz)'::regprocedure
     ) not ilike '%organization_membership_calendar_date_at_v1%'
     or pg_get_functiondef(
       'atlas.organization_membership_present_effective_at_v1(uuid,uuid,timestamptz)'::regprocedure
     ) ilike '%principal_authoritative_timezone%'
     or pg_get_functiondef(
       'atlas.organization_membership_present_effective_at_v1(uuid,uuid,timestamptz)'::regprocedure
     ) ilike '%current_date%' then
    raise exception 'Present Membership law did not use exact governed calendar context cleanly.';
  end if;

  -- 17. Interim Endpoint bounded-Membership fence is gone from the exact capability resolver.
  if pg_get_functiondef(
       'atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text)'::regprocedure
     ) ilike '%eligibility_begins_on is null%'
     or pg_get_functiondef(
       'atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%' then
    raise exception 'Endpoint capability resolver retained the interim bounded-Membership fence.';
  end if;

  if pg_get_functiondef(
       'atlas.can_schedule_company_work_v1(uuid)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%'
     or pg_get_functiondef(
       'atlas.can_adjudicate_company_work_v1(uuid)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%' then
    raise exception 'Company Work direct present-action bypass survived Phase B.';
  end if;
end;
$proof$;
