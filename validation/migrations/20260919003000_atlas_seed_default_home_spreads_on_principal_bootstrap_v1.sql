do $validation$
declare
  v_uid constant uuid := 'f1900000-0000-4000-8000-000000000001'::uuid;
  v_email constant text := 'first-user-home-spread-proof@example.test';
  v_checkout constant text := 'cs_test_first_user_home_spread_seed_v1';
  v_subscription constant text := 'sub_test_first_user_home_spread_seed_v1';
  v_bootstrap jsonb;
  v_index jsonb;
  v_shell jsonb;
  v_rhythm jsonb;
  v_laundry jsonb;
  v_care jsonb;
  v_principal_id uuid;
  v_household_id uuid;
  v_count integer;
begin
  if to_regprocedure('atlas.ensure_principal_default_home_spreads_v1(uuid,uuid)') is null then
    raise exception 'Default Home spread seed helper is missing.';
  end if;

  if has_function_privilege('anon','atlas.ensure_principal_default_home_spreads_v1(uuid,uuid)','execute')
     or has_function_privilege('authenticated','atlas.ensure_principal_default_home_spreads_v1(uuid,uuid)','execute') then
    raise exception 'Default Home spread seed helper became browser-callable.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal
      and n.nspname='atlas'
      and c.relname='principals'
      and t.tgname='trg_seed_default_home_spreads_for_principal_v1'
  ) then
    raise exception 'Principal default Home spread seed trigger is missing.';
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
    jsonb_build_object('testMode',true,'proof','first-user-home-spread-seed-v1')
  );

  perform set_config('request.jwt.claim.sub',v_uid::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_uid::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'First User Home Spread Proof',
    'America/Chicago'
  );
  v_principal_id := (v_bootstrap->>'principalId')::uuid;
  v_household_id := (v_bootstrap->>'householdId')::uuid;

  if v_principal_id is null or v_household_id is null then
    raise exception 'Personal Atlas bootstrap did not establish Principal + household: %',v_bootstrap;
  end if;

  select count(*) into v_count
  from atlas.notebook_spread_instances s
  where s.principal_id=v_principal_id
    and s.spread_key in ('household-rhythm','laundry','home-care')
    and s.scope_kind='household'
    and s.scope_id=v_household_id::text
    and s.spread_state='open';

  if v_count <> 3 then
    raise exception 'New Principal did not receive all three durable Home spreads; found %.',v_count;
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
    where s.principal_id=v_principal_id
      and s.spread_key='household-rhythm'
      and b.source_domain='household'
      and b.source_kind='rhythm_snapshot_v1'
      and b.source_id=v_household_id::text
      and b.relationship_kind='cadence'
      and b.binding_state='active'
  ) then
    raise exception 'Household Rhythm did not retain governed rhythm source custody.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
    where s.principal_id=v_principal_id
      and s.spread_key='laundry'
      and b.source_domain='household'
      and b.source_kind='laundry_kernel_v1'
      and b.source_id=v_household_id::text
      and b.relationship_kind='sequence'
      and b.binding_state='active'
  ) then
    raise exception 'Laundry did not retain governed kernel source custody.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances s
    join atlas.notebook_spread_source_bindings b on b.spread_instance_id=s.id
    where s.principal_id=v_principal_id
      and s.spread_key='home-care'
      and b.source_domain='household'
      and b.source_kind='care_snapshot_v1'
      and b.source_id=v_household_id::text
      and b.relationship_kind='state'
      and b.binding_state='active'
  ) then
    raise exception 'Home Care did not retain governed care source custody.';
  end if;

  v_index := atlas.atlas_notebook_index_self_api_v1();

  if (v_index->>'principalId')::uuid <> v_principal_id
     or (v_index->>'householdId')::uuid <> v_household_id then
    raise exception 'Notebook Index did not resolve the bootstrapped Principal/household: %',v_index;
  end if;

  if (
    select count(*)
    from jsonb_array_elements(coalesce(v_index->'items','[]'::jsonb)) item
    where item->>'spreadKey' in ('household-rhythm','laundry','home-care')
  ) <> 3 then
    raise exception 'Notebook Index did not expose all three bootstrapped Home spreads: %',v_index;
  end if;

  v_shell := atlas.notebook_spread_instance_self_api_v1('household-rhythm');
  if v_shell->'spread'->>'spreadKey' <> 'household-rhythm'
     or v_shell->'spread'->'scope'->>'id' <> v_household_id::text then
    raise exception 'Household Rhythm shell did not resolve through Principal-scoped spread read: %',v_shell;
  end if;

  v_shell := atlas.notebook_spread_instance_self_api_v1('laundry');
  if v_shell->'spread'->>'spreadKey' <> 'laundry'
     or v_shell->'spread'->'scope'->>'id' <> v_household_id::text then
    raise exception 'Laundry shell did not resolve through Principal-scoped spread read: %',v_shell;
  end if;

  v_shell := atlas.notebook_spread_instance_self_api_v1('home-care');
  if v_shell->'spread'->>'spreadKey' <> 'home-care'
     or v_shell->'spread'->'scope'->>'id' <> v_household_id::text then
    raise exception 'Home Care shell did not resolve through Principal-scoped spread read: %',v_shell;
  end if;

  v_rhythm := public.personal_setup_self_api_v1();
  if v_rhythm->'household'->>'id' <> v_household_id::text then
    raise exception 'Household Rhythm governed read did not resolve the active household: %',v_rhythm;
  end if;

  v_laundry := atlas.personal_laundry_kernel_self_api_v1();
  if v_laundry->>'householdId' <> v_household_id::text then
    raise exception 'Laundry governed read did not resolve the active household: %',v_laundry;
  end if;

  v_care := atlas.principal_household_care_snapshot_v1();
  if v_care->'household'->>'id' <> v_household_id::text then
    raise exception 'Home Care governed read did not resolve the active household: %',v_care;
  end if;

  -- The helper is idempotent for the same durable identity.
  perform atlas.ensure_principal_default_home_spreads_v1(v_principal_id,v_household_id);

  select count(*) into v_count
  from atlas.notebook_spread_instances s
  where s.principal_id=v_principal_id
    and s.spread_key in ('household-rhythm','laundry','home-care');

  if v_count <> 3 then
    raise exception 'Default Home spread seed replay duplicated durable spread identity; found %.',v_count;
  end if;
end;
$validation$;
