do $validation$
declare
  v_uid uuid := gen_random_uuid();
  v_email text := 'organization-ledger-durable-proof-'||substr(replace(v_uid::text,'-',''),1,8)||'@example.test';
  v_checkout text := 'cs_test_org_ledger_durable_'||substr(replace(v_uid::text,'-',''),1,10);
  v_subscription text := 'sub_test_org_ledger_durable_'||substr(replace(v_uid::text,'-',''),1,10);
  v_bootstrap jsonb;
  v_established jsonb;
  v_index jsonb;
  v_shell jsonb;
  v_recent jsonb;
  v_principal_id uuid;
  v_person_id uuid;
  v_household_id uuid;
  v_organization_id uuid;
  v_ledger_id uuid;
  v_membership_id uuid;
  v_spread_id uuid;
  v_reopened_spread_id uuid;
  v_count integer;
begin
  if to_regprocedure('atlas.principal_has_organization_owner_access_v1(uuid,uuid)') is null then
    raise exception 'Organization Ledger Principal owner-access helper is missing.';
  end if;
  if to_regprocedure('atlas.sync_organization_owner_ledger_spread_v1(uuid,uuid)') is null then
    raise exception 'Organization Ledger durable spread sync helper is missing.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.principal_has_organization_owner_access_v1(uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.principal_has_organization_owner_access_v1(uuid,uuid)',
       'execute'
     ) then
    raise exception 'Internal Organization Ledger authority helper became browser-callable.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.sync_organization_owner_ledger_spread_v1(uuid,uuid)',
       'execute'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.sync_organization_owner_ledger_spread_v1(uuid,uuid)',
       'execute'
     ) then
    raise exception 'Organization Ledger spread sync helper became browser-callable.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal
      and n.nspname='atlas'
      and c.relname='organization_memberships'
      and t.tgname='trg_sync_organization_owner_ledger_spread_v1'
  ) then
    raise exception 'Organization membership -> Ledger spread sync trigger is missing.';
  end if;

  insert into auth.users(id,email,created_at,updated_at)
  values(v_uid,v_email,now(),now());

  insert into atlas.personal_atlas_purchases(
    provider,
    provider_checkout_session_id,
    provider_subscription_id,
    purchaser_email,
    offer_key,
    purchase_state,
    purchased_at,
    metadata
  ) values (
    'stripe',
    v_checkout,
    v_subscription,
    v_email,
    'personal_atlas',
    'active',
    now(),
    jsonb_build_object('testMode',true,'proof','organization-ledger-durable-spread-v1')
  );

  perform set_config('request.jwt.claim.sub',v_uid::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_uid::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Organization Ledger Durable Proof',
    'America/Chicago'
  );
  v_principal_id := (v_bootstrap->>'principalId')::uuid;
  v_household_id := (v_bootstrap->>'householdId')::uuid;
  v_person_id := atlas.current_person_id_v1();

  if v_principal_id is null
     or v_household_id is null
     or v_person_id is null
     or atlas.current_principal_id_v1() <> v_principal_id then
    raise exception 'Personal Atlas proof bootstrap did not establish stable Person/Principal identity: %',v_bootstrap;
  end if;

  v_established := atlas.establish_organization_ledger_self_api_v1(
    'Ledger Durable Proof Organization',
    true,
    false
  );

  v_organization_id := (v_established->'organization'->>'id')::uuid;
  v_ledger_id := (v_established->'ledger'->>'id')::uuid;
  v_membership_id := (v_established->'membership'->>'id')::uuid;

  if v_organization_id is null
     or v_ledger_id is null
     or v_membership_id is null then
    raise exception 'Organization establishment did not return Organization/Ledger/owner membership: %',v_established;
  end if;

  if not atlas.principal_has_organization_owner_access_v1(
    v_principal_id,
    v_organization_id
  ) then
    raise exception 'New owner membership did not establish Principal owner authority.';
  end if;

  select s.id
    into v_spread_id
  from atlas.notebook_spread_instances s
  where s.principal_id=v_principal_id
    and s.spread_key='ledger:'||v_organization_id::text
    and s.scope_kind='organization'
    and s.scope_id=v_organization_id::text
    and s.subject_domain='organization'
    and s.subject_kind='organization_ledger'
    and s.subject_id=v_organization_id::text
    and s.spread_state='open';

  if v_spread_id is null then
    raise exception 'Owner organization did not receive a durable Ledger spread.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_source_bindings b
    where b.spread_instance_id=v_spread_id
      and b.source_domain='organization'
      and b.source_kind='ledger_recent_v1'
      and b.source_id=v_organization_id::text
      and b.relationship_kind='evidence'
      and b.binding_state='active'
      and b.retired_at is null
  ) then
    raise exception 'Organization Ledger spread did not retain the governed recent-Ledger source binding.';
  end if;

  v_index := atlas.atlas_notebook_index_self_api_v1();

  select count(*)
    into v_count
  from jsonb_array_elements(coalesce(v_index->'items','[]'::jsonb)) item
  where item->>'spreadKey'='ledger:'||v_organization_id::text
    and item->'scope'->>'kind'='organization'
    and item->'scope'->>'id'=v_organization_id::text
    and item->'subject'->>'domain'='organization'
    and item->'subject'->>'kind'='organization_ledger';

  if v_count <> 1 then
    raise exception 'Authorized owner Index did not expose exactly one durable Ledger descriptor: %',v_index;
  end if;

  v_shell := atlas.notebook_spread_instance_self_api_v1(
    'ledger:'||v_organization_id::text
  );

  if (v_shell->'spread'->>'spreadInstanceId')::uuid <> v_spread_id
     or v_shell->'spread'->'scope'->>'id' <> v_organization_id::text
     or v_shell->'spread'->'subject'->>'kind' <> 'organization_ledger'
     or v_shell->'spread'->'compositionContract'->'forms'->0->>'formFamily' <> 'log' then
    raise exception 'Authorized owner Ledger spread shell is malformed: %',v_shell;
  end if;

  if (
    select count(*)
    from jsonb_array_elements(coalesce(v_shell->'sourceBindings','[]'::jsonb)) binding
    where binding->>'sourceDomain'='organization'
      and binding->>'sourceKind'='ledger_recent_v1'
      and binding->>'sourceId'=v_organization_id::text
      and binding->>'relationshipKind'='evidence'
  ) <> 1 then
    raise exception 'Authorized owner Ledger shell does not expose the exact governed source binding: %',v_shell;
  end if;

  v_recent := atlas.organization_ledger_owner_recent_api_v1(
    v_organization_id,
    50
  );

  if v_recent->>'organizationId' <> v_organization_id::text
     or v_recent->>'contractVersion' <> 'organization_ledger_owner_recent_api_v1' then
    raise exception 'Owner Ledger read membrane did not resolve the same Organization: %',v_recent;
  end if;

  if atlas.current_principal_id_v1() <> v_principal_id then
    raise exception 'Entering Organization Ledger changed the authenticated Principal identity.';
  end if;

  -- Revoke owner authority. Durable identity/history remains, but the current
  -- Principal may no longer discover or directly read the owner-only spread.
  update atlas.organization_memberships
  set role='member',
      updated_at=now()
  where id=v_membership_id;

  if atlas.principal_has_organization_owner_access_v1(
    v_principal_id,
    v_organization_id
  ) then
    raise exception 'Downgraded membership still satisfies owner authority.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    where s.id=v_spread_id
      and s.spread_state='closed'
      and s.closed_at is not null
  ) then
    raise exception 'Loss of owner authority did not close the durable Ledger spread.';
  end if;

  if exists (
    select 1
    from atlas.notebook_spread_source_bindings b
    where b.spread_instance_id=v_spread_id
      and b.source_domain='organization'
      and b.source_kind='ledger_recent_v1'
      and b.source_id=v_organization_id::text
      and b.binding_state='active'
      and b.retired_at is null
  ) then
    raise exception 'Loss of owner authority left the Ledger source binding active.';
  end if;

  v_index := atlas.atlas_notebook_index_self_api_v1();
  if exists (
    select 1
    from jsonb_array_elements(coalesce(v_index->'items','[]'::jsonb)) item
    where item->>'spreadKey'='ledger:'||v_organization_id::text
  ) then
    raise exception 'Non-owner Index still exposes the owner-only Ledger descriptor: %',v_index;
  end if;

  begin
    perform atlas.notebook_spread_instance_self_api_v1(
      'ledger:'||v_organization_id::text
    );
    raise exception 'Non-owner direct Ledger spread read unexpectedly succeeded.';
  exception
    when sqlstate 'P0002' then
      null;
  end;

  begin
    perform atlas.organization_ledger_owner_recent_api_v1(
      v_organization_id,
      50
    );
    raise exception 'Non-owner underlying Ledger read unexpectedly succeeded.';
  exception
    when sqlstate '42501' then
      null;
  end;

  -- Restore owner authority. The same durable spread identity must reopen.
  update atlas.organization_memberships
  set role='owner',
      updated_at=now()
  where id=v_membership_id;

  if not atlas.principal_has_organization_owner_access_v1(
    v_principal_id,
    v_organization_id
  ) then
    raise exception 'Restored owner membership did not restore owner authority.';
  end if;

  select s.id
    into v_reopened_spread_id
  from atlas.notebook_spread_instances s
  where s.principal_id=v_principal_id
    and s.spread_key='ledger:'||v_organization_id::text
    and s.spread_state='open';

  if v_reopened_spread_id is null or v_reopened_spread_id <> v_spread_id then
    raise exception 'Restored owner authority did not reopen the same durable Ledger identity.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_source_bindings b
    where b.spread_instance_id=v_spread_id
      and b.source_domain='organization'
      and b.source_kind='ledger_recent_v1'
      and b.source_id=v_organization_id::text
      and b.relationship_kind='evidence'
      and b.binding_state='active'
      and b.retired_at is null
  ) then
    raise exception 'Restored owner authority did not reactivate the governed Ledger source binding.';
  end if;

  v_index := atlas.atlas_notebook_index_self_api_v1();
  if (
    select count(*)
    from jsonb_array_elements(coalesce(v_index->'items','[]'::jsonb)) item
    where item->>'spreadKey'='ledger:'||v_organization_id::text
  ) <> 1 then
    raise exception 'Restored owner Index did not re-admit the durable Ledger descriptor: %',v_index;
  end if;

  v_shell := atlas.notebook_spread_instance_self_api_v1(
    'ledger:'||v_organization_id::text
  );
  if (v_shell->'spread'->>'spreadInstanceId')::uuid <> v_spread_id then
    raise exception 'Restored owner direct Ledger read did not return the same spread identity: %',v_shell;
  end if;
end;
$validation$;
