do $validation$
declare
  v_org uuid:=gen_random_uuid();
  v_owner_user uuid:=gen_random_uuid();
  v_a_user uuid:=gen_random_uuid();
  v_b_user uuid:=gen_random_uuid();
  v_owner uuid;
  v_a uuid;
  v_b uuid;
  v_work_self uuid:=gen_random_uuid();
  v_work_claim uuid:=gen_random_uuid();
  v_work_outbound uuid:=gen_random_uuid();
  v_work_derived uuid:=gen_random_uuid();
  v_work_owner uuid:=gen_random_uuid();
  v_work_handoff uuid:=gen_random_uuid();
  v_work_release uuid:=gen_random_uuid();
  v_work_legacy_weekly uuid:=gen_random_uuid();
  v_work_legacy_task uuid:=gen_random_uuid();
  v_result jsonb;
  v_allocation uuid;
  v_count integer;
  v_v2_oid oid;
begin
  -- Historical allocation survives without invented establishment provenance.
  if not exists(
    select 1
    from atlas.work_allocations
    where id='95000000-0000-0000-0000-000000000001'::uuid
      and state='active'
      and allocation_role='responsible'
      and establishment_basis_kind is null
      and establishment_basis is null
  ) then
    raise exception 'Historical responsibility was rewritten or lost during establishment-basis migration.';
  end if;

  update atlas.work_allocations
  set metadata=metadata||'{"postMigrationTouched":true}'::jsonb
  where id='95000000-0000-0000-0000-000000000001'::uuid;

  if not exists(
    select 1 from atlas.work_allocations
    where id='95000000-0000-0000-0000-000000000001'::uuid
      and establishment_basis_kind is null
      and establishment_basis is null
  ) then
    raise exception 'Ordinary update fabricated historical responsibility provenance.';
  end if;

  v_result:=atlas.set_company_work_responsibility_with_basis_internal_v2(
    '94000000-0000-0000-0000-000000000001'::uuid,
    '93000000-0000-0000-0000-000000000001'::uuid,
    '93000000-0000-0000-0000-000000000001'::uuid,
    'self_adoption',
    jsonb_build_object('sourceKind','later_affirmation','sourceId',gen_random_uuid()),
    'later self affirmation must not rewrite historical origin',
    '{"source":"historical_affirmation_proof"}'::jsonb
  );

  if v_result->>'state'<>'already_responsible_historical'
     or exists(
       select 1 from atlas.work_allocations
       where id='95000000-0000-0000-0000-000000000001'::uuid
         and (establishment_basis_kind is not null or establishment_basis is not null)
     ) then
    raise exception 'Later self affirmation rewrote historical responsibility origin.';
  end if;

  v_v2_oid:=to_regprocedure(
    'atlas.set_company_work_responsibility_with_basis_internal_v2(uuid,uuid,uuid,text,jsonb,text,jsonb)'
  );
  if v_v2_oid is null then
    raise exception 'Versioned exact Work responsibility establishment writer is missing.';
  end if;
  if has_function_privilege('anon',v_v2_oid,'execute')
     or has_function_privilege('authenticated',v_v2_oid,'execute')
     or not has_function_privilege('service_role',v_v2_oid,'execute') then
    raise exception 'Responsibility establishment v2 must remain service-only.';
  end if;

  insert into auth.users(id,email,created_at,updated_at)
  values
    (v_owner_user,'work-basis-owner-'||substr(v_owner_user::text,1,8)||'@example.test',now(),now()),
    (v_a_user,'work-basis-a-'||substr(v_a_user::text,1,8)||'@example.test',now(),now()),
    (v_b_user,'work-basis-b-'||substr(v_b_user::text,1,8)||'@example.test',now(),now());

  insert into atlas.organizations(id,stable_key,name)
  values(v_org,'work-basis-'||substr(v_org::text,1,8),'Work Basis Proof');

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_owner_user,'owner',true)
  returning id into v_owner;

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_a_user,'member',true)
  returning id into v_a;

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values(v_org,v_b_user,'member',true)
  returning id into v_b;

  insert into atlas.work_items(id,organization_id,title,work_state,operation_class,jurisdiction_key,stable_key)
  values
    (v_work_self,v_org,'Self adoption','open','fixture','fixture.self','work-self-'||v_work_self::text),
    (v_work_claim,v_org,'Self claim','open','fixture','fixture.claim','work-claim-'||v_work_claim::text),
    (v_work_outbound,v_org,'Outbound follow-up','open','fixture','fixture.outbound','work-outbound-'||v_work_outbound::text),
    (v_work_derived,v_org,'Derived self work','open','fixture','fixture.derived','work-derived-'||v_work_derived::text),
    (v_work_owner,v_org,'Owner proposed work','open','fixture','fixture.owner','work-owner-'||v_work_owner::text),
    (v_work_handoff,v_org,'Handoff work','open','fixture','fixture.handoff','work-handoff-'||v_work_handoff::text),
    (v_work_release,v_org,'Release work','open','fixture','fixture.release','work-release-'||v_work_release::text),
    (v_work_legacy_weekly,v_org,'Legacy weekly reconstruction','open','fixture','fixture.legacy','work-legacy-weekly-'||v_work_legacy_weekly::text),
    (v_work_legacy_task,v_org,'Legacy task reconstruction','open','fixture','fixture.legacy','work-legacy-task-'||v_work_legacy_task::text);

  -- Collaboration is not responsibility and remains unaffected.
  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
    allocation_role,state,metadata
  ) values(
    v_org,v_work_self,v_b,v_a,'participant','active',
    '{"source":"responsibility_basis_proof_participant"}'::jsonb
  );

  -- Unqualified new responsibility fails at the table boundary.
  begin
    insert into atlas.work_allocations(
      organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
      allocation_role,state,metadata
    ) values(
      v_org,v_work_owner,v_b,v_owner,'responsible','active',
      '{"source":"unqualified_direct_assignment"}'::jsonb
    );
    raise exception 'Unqualified active responsibility insert unexpectedly succeeded.';
  exception when sqlstate '23514' then
    null;
  end;

  -- Named legacy reconstruction carriers continue without code changes.
  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,
    allocation_role,state,metadata
  ) values(
    v_org,v_work_legacy_weekly,v_a,
    'responsible','active',
    jsonb_build_object(
      'source','legacy_weekly_harvest_occurrence_assignment',
      'plannedOccurrenceId',gen_random_uuid()
    )
  ) returning id into v_allocation;

  if not exists(
    select 1 from atlas.work_allocations
    where id=v_allocation
      and establishment_basis_kind='legacy_governed_reconstruction'
      and establishment_basis->>'legacySource'='legacy_weekly_harvest_occurrence_assignment'
  ) then
    raise exception 'Weekly-harvest legacy reconstruction was not normalized to a governed basis.';
  end if;

  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,
    allocation_role,state,metadata
  ) values(
    v_org,v_work_legacy_task,v_a,
    'responsible','active',
    jsonb_build_object(
      'source','explicit_worker_task_company_work_adoption_v2',
      'legacyTaskId',gen_random_uuid()
    )
  ) returning id into v_allocation;

  if not exists(
    select 1 from atlas.work_allocations
    where id=v_allocation
      and establishment_basis_kind='legacy_governed_reconstruction'
      and establishment_basis->>'legacySource'='explicit_worker_task_company_work_adoption_v2'
  ) then
    raise exception 'Legacy task reconstruction was not normalized to a governed basis.';
  end if;

  -- The forward v2 seam accepts truthful self-adoption.
  v_result:=atlas.set_company_work_responsibility_with_basis_internal_v2(
    v_work_self,v_a,v_a,'self_adoption',
    jsonb_build_object('sourceKind','proof_subject','sourceId',gen_random_uuid()),
    'self adoption proof',
    '{"source":"responsibility_basis_clone_proof"}'::jsonb
  );
  v_allocation:=(v_result->>'allocationId')::uuid;

  if not exists(
    select 1 from atlas.work_allocations
    where id=v_allocation
      and assignee_membership_id=v_a
      and assigned_by_membership_id=v_a
      and state='active'
      and allocation_role='responsible'
      and establishment_basis_kind='self_adoption'
      and establishment_basis->>'actorMembershipId'=v_a::text
      and establishment_basis->>'assigneeMembershipId'=v_a::text
  ) then
    raise exception 'Truthful self-adoption did not establish exact Work responsibility.';
  end if;

  begin
    perform atlas.set_company_work_responsibility_with_basis_internal_v2(
      v_work_owner,v_a,v_b,'self_adoption',
      jsonb_build_object('sourceKind','proof_subject','sourceId',gen_random_uuid()),
      'invalid cross-person self adoption',
      '{}'::jsonb
    );
    raise exception 'Cross-Person self-adoption unexpectedly succeeded.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    perform atlas.set_company_work_responsibility_with_basis_internal_v2(
      v_work_owner,v_a,v_a,'owner_selected',
      '{}'::jsonb,
      'unsupported basis',
      '{}'::jsonb
    );
    raise exception 'Unsupported responsibility establishment kind unexpectedly succeeded.';
  exception when sqlstate '22023' then
    null;
  end;

  -- Existing v1 callers are routed only when their semantics prove self uptake.
  v_result:=atlas.set_company_work_responsibility_internal_v1(
    v_work_claim,v_a,v_a,'conversation claimed',
    jsonb_build_object(
      'source','claim_institutional_conversation_self_api_v1',
      'institutionalConversationId',gen_random_uuid(),
      'responseCaseId',gen_random_uuid()
    )
  );

  if (v_result->>'establishmentBasisKind')<>'self_claim' then
    raise exception 'Claim compatibility path did not resolve to self_claim basis.';
  end if;

  v_result:=atlas.set_company_work_responsibility_internal_v1(
    v_work_outbound,v_a,v_a,'outbound initiated',
    jsonb_build_object(
      'source','ensure_outbound_conversation_responsibility_service_v1',
      'outboundOperationId',gen_random_uuid()
    )
  );

  if (v_result->>'establishmentBasisKind')<>'self_initiated_outbound' then
    raise exception 'Outbound compatibility path did not resolve to self_initiated_outbound basis.';
  end if;

  v_result:=atlas.set_company_work_responsibility_internal_v1(
    v_work_derived,v_a,v_a,'derived work self adoption',
    jsonb_build_object(
      'source','create_communication_derived_work_self_api_v1',
      'derivedWorkLinkId',gen_random_uuid()
    )
  );

  if (v_result->>'establishmentBasisKind')<>'self_adoption' then
    raise exception 'Communication-derived self assignment did not resolve to self_adoption basis.';
  end if;

  -- Owner selection cannot create another member's responsibility.
  begin
    perform atlas.set_company_work_responsibility_internal_v1(
      v_work_owner,v_b,v_owner,'owner selected member',
      jsonb_build_object(
        'source','organization_owner_set_company_work_responsibility_api_v1',
        'actorUserId',v_owner_user
      )
    );
    raise exception 'Owner selection unexpectedly created receiver responsibility.';
  exception when sqlstate '0A000' then
    null;
  end;

  if exists(
    select 1 from atlas.work_allocations
    where work_item_id=v_work_owner
      and allocation_role='responsible'
      and state='active'
  ) then
    raise exception 'Failed owner assignment left active receiver responsibility.';
  end if;

  -- A failed cross-Person handoff cannot release the current carrier.
  perform atlas.set_company_work_responsibility_with_basis_internal_v2(
    v_work_handoff,v_a,v_a,'self_adoption',
    jsonb_build_object('sourceKind','proof_subject','sourceId',gen_random_uuid()),
    'establish current carrier',
    '{"source":"responsibility_basis_clone_proof"}'::jsonb
  );

  begin
    perform atlas.set_company_work_responsibility_internal_v1(
      v_work_handoff,v_b,v_a,'handoff attempted',
      jsonb_build_object(
        'source','handoff_communication_derived_work_self_api_v1',
        'derivedWorkLinkId',gen_random_uuid()
      )
    );
    raise exception 'Cross-Person handoff unexpectedly created responsibility.';
  exception when sqlstate '0A000' then
    null;
  end;

  select count(*) into v_count
  from atlas.work_allocations
  where work_item_id=v_work_handoff
    and allocation_role='responsible'
    and state='active'
    and assignee_membership_id=v_a;

  if v_count<>1 then
    raise exception 'Failed handoff changed or released the current responsible carrier.';
  end if;

  if exists(
    select 1 from atlas.work_allocations
    where work_item_id=v_work_handoff
      and allocation_role='responsible'
      and state='active'
      and assignee_membership_id=v_b
  ) then
    raise exception 'Failed handoff created target responsibility.';
  end if;

  -- Compatibility release remains possible and does not require a new basis.
  perform atlas.set_company_work_responsibility_with_basis_internal_v2(
    v_work_release,v_a,v_a,'self_adoption',
    jsonb_build_object('sourceKind','proof_subject','sourceId',gen_random_uuid()),
    'establish then release',
    '{"source":"responsibility_basis_clone_proof"}'::jsonb
  );

  v_result:=atlas.set_company_work_responsibility_internal_v1(
    v_work_release,null,v_a,'responsibility released',
    '{"source":"responsibility_basis_clone_proof_release"}'::jsonb
  );

  if (v_result->>'state')<>'released'
     or exists(
       select 1 from atlas.work_allocations
       where work_item_id=v_work_release
         and allocation_role='responsible'
         and state='active'
     ) then
    raise exception 'Compatibility release path no longer releases exact Work responsibility.';
  end if;

  -- Historical responsibility cannot be reassigned by direct mutation without basis.
  insert into auth.users(id,email,created_at,updated_at)
  values(
    '91000000-0000-0000-0000-000000000002'::uuid,
    'historical-responsibility-target@example.test',
    now(),now()
  );

  insert into atlas.organization_memberships(
    organization_id,user_id,role,active
  ) values(
    '92000000-0000-0000-0000-000000000001'::uuid,
    '91000000-0000-0000-0000-000000000002'::uuid,
    'member',true
  ) returning id into v_allocation;

  begin
    update atlas.work_allocations
    set assignee_membership_id=v_allocation
    where id='95000000-0000-0000-0000-000000000001'::uuid;
    raise exception 'Historical responsibility was reassigned without an establishment basis.';
  exception when sqlstate '23514' then
    null;
  end;

  if not exists(
    select 1 from atlas.work_allocations
    where id='95000000-0000-0000-0000-000000000001'::uuid
      and assignee_membership_id='93000000-0000-0000-0000-000000000001'::uuid
      and state='active'
  ) then
    raise exception 'Failed historical reassignment mutated the existing carrier.';
  end if;

  -- Current cross-Person domain wrappers remain bound to the compatibility
  -- writer, whose new law now fails them closed transactionally.
  if pg_get_functiondef(
       'atlas.organization_owner_set_company_work_responsibility_api_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%set_company_work_responsibility_internal_v1%'
     or pg_get_functiondef(
       'atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%set_company_work_responsibility_internal_v1%'
     or pg_get_functiondef(
       'atlas.handoff_communication_derived_work_self_api_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%set_company_work_responsibility_internal_v1%' then
    raise exception 'Cross-Person compatibility wrappers no longer terminate at the governed v1 fail-closed boundary.';
  end if;

  if pg_get_functiondef(
       'atlas.ensure_weekly_harvest_company_work_v1(uuid)'::regprocedure
     ) not ilike '%legacy_weekly_harvest_occurrence_assignment%'
     or pg_get_functiondef(
       'atlas.sync_explicit_worker_task_company_work_v2(uuid)'::regprocedure
     ) not ilike '%explicit_worker_task_company_work_adoption_v2%' then
    raise exception 'Named legacy reconstruction adapters changed unexpectedly.';
  end if;

  if not exists(
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.set_company_work_responsibility_with_basis_internal_v2(uuid,uuid,uuid,text,jsonb,text,jsonb)'
      and classification='service_internal'
      and not authenticated_execute_expected
      and service_execute_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Responsibility establishment v2 RPC registry entry is missing.';
  end if;
end;
$validation$;
