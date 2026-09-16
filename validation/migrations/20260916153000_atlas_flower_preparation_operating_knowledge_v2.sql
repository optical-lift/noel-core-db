do $validation$
declare
  v_v1_oid oid;
  v_v2_oid oid;
  v_v1_def text;
  v_v2_def text;
  v_v1_secdef boolean;
  v_v2_secdef boolean;
  v_unit_id uuid;
  v_org_id uuid;
  v_binding_count integer;
  v_rule_count integer;
  v_named_count integer;
  v_drift integer;
  v_effect jsonb;
  v_context jsonb;
  v_teddy_id uuid;
  v_celosia_id uuid;
begin
  if to_regclass('atlas.flower_operating_knowledge_crop_bindings') is null then
    raise exception 'Expected Flower Operating Knowledge crop binding seam.';
  end if;
  if to_regclass('atlas.flower_preparation_directive_line_knowledge_provenance') is null then
    raise exception 'Expected immutable Flower Preparation knowledge provenance relation.';
  end if;

  v_v1_oid := to_regprocedure('atlas.record_flower_preparation_directive_v1(uuid,jsonb,text,text)');
  v_v2_oid := to_regprocedure('atlas.record_flower_preparation_directive_v2(uuid,jsonb,text,text)');

  if v_v1_oid is null then
    raise exception 'Existing Flower Preparation directive v1 authority disappeared.';
  end if;
  if v_v2_oid is null then
    raise exception 'Expected Flower Preparation directive v2.';
  end if;

  select p.prosecdef, pg_get_functiondef(p.oid)
    into v_v1_secdef, v_v1_def
  from pg_proc p where p.oid = v_v1_oid;

  select p.prosecdef, pg_get_functiondef(p.oid)
    into v_v2_secdef, v_v2_def
  from pg_proc p where p.oid = v_v2_oid;

  if not v_v1_secdef or not v_v2_secdef then
    raise exception 'Flower Preparation directive v1 and v2 must remain SECURITY DEFINER authorities.';
  end if;
  if pg_get_function_result(v_v1_oid) <> 'jsonb' or pg_get_function_result(v_v2_oid) <> 'jsonb' then
    raise exception 'Flower Preparation directive v1/v2 must return jsonb.';
  end if;

  -- v1 must remain the original explicit-Owner contract. v2 delegates to it;
  -- Operating Knowledge must not have been spliced into v1.
  if position('A bundle direction requires a whole-number stems-per-bundle value.' in v_v1_def) = 0 then
    raise exception 'Flower Preparation v1 explicit bundle-size invariant drifted.';
  end if;
  if position('resolve_company_operating_knowledge_v1' in v_v1_def) > 0
     or position('flower_operating_knowledge_crop_bindings' in v_v1_def) > 0 then
    raise exception 'Flower Preparation v1 was mutated to depend on Operating Knowledge.';
  end if;
  if position('atlas.record_flower_preparation_directive_v1(' in v_v2_def) = 0 then
    raise exception 'Flower Preparation v2 no longer delegates final authority/release to v1.';
  end if;
  if position('atlas.resolve_company_operating_knowledge_v1(' in v_v2_def) = 0 then
    raise exception 'Flower Preparation v2 is not resolving established Operating Knowledge.';
  end if;
  if position('flower_operating_knowledge_crop_bindings' in v_v2_def) = 0 then
    raise exception 'Flower Preparation v2 lost canonical crop-to-rule product binding.';
  end if;
  if position('v_stems_text = ''''' in v_v2_def) = 0 then
    raise exception 'Flower Preparation v2 must resolve defaults only when stemsPerUnit is omitted.';
  end if;

  if not has_function_privilege('authenticated', v_v1_oid, 'EXECUTE')
     or not has_function_privilege('authenticated', v_v2_oid, 'EXECUTE') then
    raise exception 'authenticated must execute both Flower Preparation v1 and v2.';
  end if;
  if has_function_privilege('anon', v_v2_oid, 'EXECUTE') then
    raise exception 'anon must not execute Flower Preparation v2.';
  end if;
  if has_function_privilege('service_role', v_v2_oid, 'EXECUTE') then
    raise exception 'service_role must not execute Flower Preparation v2; Owner/manager auth is required.';
  end if;

  select count(*) into v_named_count
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas' and p.proname = 'record_flower_preparation_directive_v2';
  if v_named_count <> 1 then
    raise exception 'Expected exactly one Flower Preparation directive v2 overload; found %.', v_named_count;
  end if;

  if has_table_privilege('authenticated', 'atlas.flower_operating_knowledge_crop_bindings', 'SELECT') then
    raise exception 'Browser/authenticated role must not read the internal Flower Operating Knowledge binding table directly.';
  end if;
  if not has_table_privilege('service_role', 'atlas.flower_operating_knowledge_crop_bindings', 'SELECT') then
    raise exception 'service_role must retain read access to Flower Operating Knowledge bindings.';
  end if;
  if not has_table_privilege('authenticated', 'atlas.flower_preparation_directive_line_knowledge_provenance', 'SELECT') then
    raise exception 'Authenticated farm members must be able to read governed Flower Preparation provenance through RLS.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'atlas'
      and c.relname = 'flower_preparation_directive_line_knowledge_provenance'
      and t.tgname = 'flower_preparation_directive_line_knowledge_provenance_immutable_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Flower Preparation Operating Knowledge provenance lost immutability trigger.';
  end if;

  select f.organization_id, f.organization_unit_id
    into v_org_id, v_unit_id
  from atlas.farms f
  where f.stable_key = 'elm_farm'
    and f.status = 'active';

  if v_org_id is null or v_unit_id is null then
    raise exception 'Elm Farm canonical Organization/Unit custody is required for validation.';
  end if;

  select cp.id into v_teddy_id
  from atlas.crop_profiles cp
  where cp.stable_key = 'sunflower_teddy';
  select cp.id into v_celosia_id
  from atlas.crop_profiles cp
  where cp.stable_key = 'celosia_cut_flower';

  if v_teddy_id is null or v_celosia_id is null then
    raise exception 'Expected Teddy sunflower and Celosia canonical crop profiles.';
  end if;

  select count(*)::integer into v_binding_count
  from atlas.flower_operating_knowledge_crop_bindings b
  where b.organization_unit_id = v_unit_id;
  if v_binding_count <> 2 then
    raise exception 'Initial Elm Flower Operating Knowledge binding count must be exactly 2; found %.', v_binding_count;
  end if;

  if not exists (
    select 1 from atlas.flower_operating_knowledge_crop_bindings b
    where b.organization_unit_id = v_unit_id
      and b.crop_profile_id = v_teddy_id
      and b.category_key = 'cut_flower'
      and b.product_key = 'sunflower'
  ) then
    raise exception 'Teddy sunflower must bind explicitly to Operating Knowledge product=sunflower.';
  end if;

  if not exists (
    select 1 from atlas.flower_operating_knowledge_crop_bindings b
    where b.organization_unit_id = v_unit_id
      and b.crop_profile_id = v_celosia_id
      and b.category_key = 'cut_flower'
      and b.product_key = 'celosia'
  ) then
    raise exception 'Celosia must bind explicitly to Operating Knowledge product=celosia.';
  end if;

  if exists (
    select 1 from atlas.flower_operating_knowledge_crop_bindings b
    where b.organization_unit_id = v_unit_id
      and b.product_key = 'goldenrod'
  ) then
    raise exception 'Goldenrod must remain unbound until canonical crop identity exists; explicit Owner bundle size remains required.';
  end if;

  -- The established Operating Knowledge rows are not part of this migration.
  select count(*)::integer into v_rule_count
  from atlas.company_operating_knowledge k
  where k.organization_id = v_org_id
    and k.status = 'established';
  if v_rule_count <> 3 then
    raise exception 'Elm established Operating Knowledge count changed; expected 3, found %.', v_rule_count;
  end if;

  if not exists (
    select 1 from atlas.company_operating_knowledge k
    where k.organization_id = v_org_id
      and k.stable_key = 'elm.cut_flower.bunch.default'
      and k.knowledge_kind = 'standard'
      and k.scope_match = '{"operation":"bunch","category":"cut_flower"}'::jsonb
      and k.effect = '{"sales_unit":"bunch","quantity_per_unit":10,"quantity_unit":"stem"}'::jsonb
      and k.status = 'established'
  ) then
    raise exception 'Elm generic 10-stem established rule drifted.';
  end if;

  if not exists (
    select 1 from atlas.company_operating_knowledge k
    where k.organization_id = v_org_id
      and k.stable_key = 'elm.cut_flower.bunch.goldenrod'
      and k.knowledge_kind = 'standard'
      and k.scope_match = '{"operation":"bunch","category":"cut_flower","product":"goldenrod"}'::jsonb
      and k.effect = '{"sales_unit":"bunch","quantity_per_unit":5,"quantity_unit":"stem"}'::jsonb
      and k.status = 'established'
  ) then
    raise exception 'Elm Goldenrod 5-stem established rule drifted.';
  end if;

  if not exists (
    select 1 from atlas.company_operating_knowledge k
    where k.organization_id = v_org_id
      and k.stable_key = 'elm.cut_flower.bunch.sunflower'
      and k.knowledge_kind = 'standard'
      and k.scope_match = '{"operation":"bunch","category":"cut_flower","product":"sunflower"}'::jsonb
      and k.effect = '{"sales_unit":"bunch","quantity_per_unit":5,"quantity_unit":"stem"}'::jsonb
      and k.status = 'established'
  ) then
    raise exception 'Elm Sunflower 5-stem established rule drifted.';
  end if;

  -- Read-only semantic proof of resolver ranking over the exact governed context
  -- v2 will supply. This deliberately does not fabricate Owner tasks or directives.
  v_context := jsonb_build_object(
    'organization_unit_id', v_unit_id,
    'operation', 'bunch',
    'category', 'cut_flower',
    'product', 'celosia'
  );
  select k.effect into v_effect
  from atlas.company_operating_knowledge k
  where k.organization_id = v_org_id
    and k.knowledge_kind = 'standard'
    and k.status = 'established'
    and (k.organization_unit_id is null or k.organization_unit_id = v_unit_id)
    and v_context @> k.scope_match
  order by (select count(*) from jsonb_object_keys(k.scope_match)) desc,
           k.precedence desc,
           k.version desc
  limit 1;
  if coalesce((v_effect->>'quantity_per_unit')::integer, -1) <> 10 then
    raise exception 'Celosia context must resolve the generic 10-stem rule; got %.', v_effect;
  end if;

  v_context := jsonb_build_object(
    'organization_unit_id', v_unit_id,
    'operation', 'bunch',
    'category', 'cut_flower',
    'product', 'sunflower'
  );
  select k.effect into v_effect
  from atlas.company_operating_knowledge k
  where k.organization_id = v_org_id
    and k.knowledge_kind = 'standard'
    and k.status = 'established'
    and (k.organization_unit_id is null or k.organization_unit_id = v_unit_id)
    and v_context @> k.scope_match
  order by (select count(*) from jsonb_object_keys(k.scope_match)) desc,
           k.precedence desc,
           k.version desc
  limit 1;
  if coalesce((v_effect->>'quantity_per_unit')::integer, -1) <> 5 then
    raise exception 'Teddy sunflower context must resolve the specific 5-stem rule; got %.', v_effect;
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry r
    where r.signature = 'atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)'
      and r.classification = 'app_endpoint'
      and r.review_status = 'active'
      and r.authenticated_execute_expected
      and not r.anonymous_execute_expected
      and r.security_definer_expected
      and not r.service_execute_expected
  ) then
    raise exception 'Flower Preparation v2 authenticated RPC registry contract is missing or incorrect.';
  end if;

  select count(*)::integer into v_drift
  from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift <> 0 then
    raise exception 'Flower Preparation v2 ended with % authenticated RPC registry drift rows.', v_drift;
  end if;
end;
$validation$;
