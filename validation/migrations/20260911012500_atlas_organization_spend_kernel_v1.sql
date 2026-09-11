-- Canonical postconditions for Atlas Organization Spend Kernel v1.
-- Runs only against the disposable production-schema clone.

do $$
declare
  v_missing text[];
begin
  select array_agg(name order by name) into v_missing
  from (values
    ('atlas.organization_spend_assert_membership_v1(uuid,uuid,text)'),
    ('atlas.organization_spend_assert_unit_v1(uuid,uuid)'),
    ('atlas.organization_spend_occurrence_snapshot_v1(uuid)'),
    ('atlas.organization_spend_parse_allocations_internal_v1(uuid,uuid,uuid,jsonb,jsonb)'),
    ('atlas.record_organization_spend_internal_v1(uuid,uuid,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb)'),
    ('atlas.record_organization_spend_self_api_v1(uuid,text,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,jsonb,jsonb)'),
    ('atlas.replace_organization_spend_allocations_self_api_v1(uuid,text,jsonb,text)'),
    ('atlas.correct_organization_spend_self_api_v1(uuid,text,date,timestamp with time zone,numeric,text,uuid,text,text,text)'),
    ('atlas.void_organization_spend_self_api_v1(uuid,text,text)'),
    ('atlas.organization_spend_window_self_api_v1(uuid,date,date)')
  ) x(name)
  where to_regprocedure(name) is null;
  if v_missing is not null then
    raise exception 'Spend kernel functions missing: %',v_missing;
  end if;

  if to_regclass('atlas.organization_spend_occurrences') is null
     or to_regclass('atlas.organization_spend_allocations') is null
     or to_regclass('atlas.organization_spend_events') is null
     or to_regclass('atlas.organization_spend_evidence_links') is null
     or to_regclass('atlas.organization_spend_position_v1') is null then
    raise exception 'Spend kernel relation set is incomplete.';
  end if;

  if not (select relrowsecurity from pg_class where oid='atlas.organization_spend_occurrences'::regclass)
     or not (select relrowsecurity from pg_class where oid='atlas.organization_spend_allocations'::regclass)
     or not (select relrowsecurity from pg_class where oid='atlas.organization_spend_events'::regclass)
     or not (select relrowsecurity from pg_class where oid='atlas.organization_spend_evidence_links'::regclass) then
    raise exception 'Spend kernel RLS is not enabled on every canonical table.';
  end if;

  if has_table_privilege('authenticated','atlas.organization_spend_occurrences','SELECT')
     or has_table_privilege('authenticated','atlas.organization_spend_occurrences','INSERT')
     or has_table_privilege('authenticated','atlas.organization_spend_allocations','SELECT')
     or has_table_privilege('authenticated','atlas.organization_spend_events','SELECT')
     or has_table_privilege('authenticated','atlas.organization_spend_evidence_links','SELECT') then
    raise exception 'Authenticated role has direct Spend table access.';
  end if;

  if not has_function_privilege('authenticated','atlas.record_organization_spend_self_api_v1(uuid,text,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,jsonb,jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.replace_organization_spend_allocations_self_api_v1(uuid,text,jsonb,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.correct_organization_spend_self_api_v1(uuid,text,date,timestamp with time zone,numeric,text,uuid,text,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.void_organization_spend_self_api_v1(uuid,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_spend_window_self_api_v1(uuid,date,date)','EXECUTE') then
    raise exception 'Authenticated Spend self-API grants are incomplete.';
  end if;

  if has_function_privilege('anon','atlas.record_organization_spend_self_api_v1(uuid,text,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,jsonb,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.record_organization_spend_internal_v1(uuid,uuid,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb)','EXECUTE') then
    raise exception 'Spend internal/write membrane leaked privilege.';
  end if;

  if not has_function_privilege('service_role','atlas.record_organization_spend_internal_v1(uuid,uuid,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb)','EXECUTE') then
    raise exception 'Service role cannot invoke Spend internal admission seam.';
  end if;
end;
$$;

begin;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000501',true);
set local role authenticated;

do $$
declare
  v_record jsonb;
  v_retry jsonb;
  v_replace jsonb;
  v_correct jsonb;
  v_void jsonb;
  v_window jsonb;
  v_spend_id uuid;
  v_conflict_blocked boolean:=false;
  v_cross_unit_blocked boolean:=false;
  v_low_gross_blocked boolean:=false;
begin
  v_record:=atlas.record_organization_spend_self_api_v1(
    '00000000-0000-4000-8000-000000000510'::uuid,
    'fixture-spend-record-1',
    '00000000-0000-4000-8000-000000000511'::uuid,
    date '2026-09-03',
    null,
    1500,
    'MXN',
    'organization_member',
    null,
    null,
    'Fixture Mercado',
    'cash',
    '[{"amount":1000,"operationalPurpose":"building maintenance"},{"amount":500,"operationalPurpose":"program supplies"}]'::jsonb,
    '{"validationFixture":true}'::jsonb
  );

  if v_record->>'state'<>'admitted'
     or (v_record->>'activeAllocationCount')::integer<>2
     or (v_record->>'unallocatedAmount')::numeric<>0 then
    raise exception 'Initial Spend admission did not preserve the 1500 MXN two-allocation split: %',v_record;
  end if;
  v_spend_id:=(v_record->>'spendOccurrenceId')::uuid;

  v_retry:=atlas.record_organization_spend_self_api_v1(
    '00000000-0000-4000-8000-000000000510'::uuid,
    'fixture-spend-record-1',
    '00000000-0000-4000-8000-000000000511'::uuid,
    date '2026-09-03',
    null,
    1500,
    'MXN',
    'organization_member',
    null,
    null,
    'Fixture Mercado',
    'cash',
    '[{"amount":1000,"operationalPurpose":"building maintenance"},{"amount":500,"operationalPurpose":"program supplies"}]'::jsonb,
    '{"validationFixture":true}'::jsonb
  );
  if v_retry->>'state'<>'unchanged' or (v_retry->>'spendOccurrenceId')::uuid<>v_spend_id then
    raise exception 'Exact Spend retry was not idempotent: %',v_retry;
  end if;

  begin
    perform atlas.record_organization_spend_self_api_v1(
      '00000000-0000-4000-8000-000000000510'::uuid,
      'fixture-spend-record-1',
      '00000000-0000-4000-8000-000000000511'::uuid,
      date '2026-09-03',
      null,
      1600,
      'MXN',
      'organization_member',
      null,
      null,
      'Fixture Mercado',
      'cash',
      null,
      '{}'::jsonb
    );
  exception when sqlstate '23514' then
    v_conflict_blocked:=true;
  end;
  if not v_conflict_blocked then raise exception 'Conflicting source-key replay was accepted.'; end if;

  begin
    perform atlas.record_organization_spend_self_api_v1(
      '00000000-0000-4000-8000-000000000510'::uuid,
      'fixture-cross-unit',
      '00000000-0000-4000-8000-000000000521'::uuid,
      date '2026-09-04',
      null,
      100,
      'MXN',
      'organization_member',
      null,
      null,
      'Cross Org Merchant',
      'cash',
      null,
      '{}'::jsonb
    );
  exception when sqlstate '23503' then
    v_cross_unit_blocked:=true;
  end;
  if not v_cross_unit_blocked then raise exception 'Cross-organization unit custody was accepted.'; end if;

  v_replace:=atlas.replace_organization_spend_allocations_self_api_v1(
    v_spend_id,
    'fixture-reallocation-1',
    '[{"amount":1200,"operationalPurpose":"building maintenance"},{"amount":300,"operationalPurpose":"program supplies"}]'::jsonb,
    'Fixture split correction'
  );
  if v_replace->>'state'<>'replaced'
     or (v_replace->>'activeAllocationCount')::integer<>2
     or (v_replace->>'unallocatedAmount')::numeric<>0 then
    raise exception 'Spend reallocation did not establish replacement effective position: %',v_replace;
  end if;

  begin
    perform atlas.correct_organization_spend_self_api_v1(
      v_spend_id,
      'fixture-correction-too-low',
      date '2026-09-03',
      null,
      1400,
      'MXN',
      null,
      'Fixture Mercado',
      'cash',
      'Fixture invalid gross correction'
    );
  exception when sqlstate '23514' then
    v_low_gross_blocked:=true;
  end;
  if not v_low_gross_blocked then raise exception 'Correction below active allocation total was accepted.'; end if;

  v_correct:=atlas.correct_organization_spend_self_api_v1(
    v_spend_id,
    'fixture-correction-1',
    date '2026-09-03',
    null,
    1600,
    'MXN',
    null,
    'Fixture Mercado Corrected',
    'cash',
    'Fixture receipt amount correction'
  );
  if v_correct->>'state'<>'corrected' then raise exception 'Spend correction failed: %',v_correct; end if;

  v_window:=atlas.organization_spend_window_self_api_v1(
    '00000000-0000-4000-8000-000000000510'::uuid,
    date '2026-09-01',
    date '2026-09-30'
  );
  if jsonb_array_length(v_window->'spend')<>1
     or ((v_window->'spend'->0)->>'grossAmount')::numeric<>1600
     or ((v_window->'spend'->0)->>'allocatedAmount')::numeric<>1500
     or ((v_window->'spend'->0)->>'unallocatedAmount')::numeric<>100 then
    raise exception 'Spend self read does not reflect corrected effective position: %',v_window;
  end if;

  v_void:=atlas.void_organization_spend_self_api_v1(
    v_spend_id,
    'fixture-void-1',
    'Fixture duplicate receipt'
  );
  if v_void->>'state'<>'voided' then raise exception 'Spend void failed: %',v_void; end if;

  v_window:=atlas.organization_spend_window_self_api_v1(
    '00000000-0000-4000-8000-000000000510'::uuid,
    date '2026-09-01',
    date '2026-09-30'
  );
  if ((v_window->'spend'->0)->>'truthState')<>'voided'
     or ((v_window->'spend'->0)->>'activeAllocationCount')::integer<>0
     or ((v_window->'spend'->0)->>'unallocatedAmount')::numeric<>0 then
    raise exception 'Voided Spend remained active in current position: %',v_window;
  end if;
end;
$$;

reset role;

do $$
declare
  v_spend_id uuid;
  v_recorded integer;
  v_replaced integer;
  v_corrected integer;
  v_voided integer;
  v_superseded integer;
  v_void_allocations integer;
begin
  select id into v_spend_id
  from atlas.organization_spend_occurrences
  where organization_id='00000000-0000-4000-8000-000000000510'::uuid
    and source_kind='atlas_self_capture'
    and source_key='fixture-spend-record-1';
  if v_spend_id is null then raise exception 'Synthetic Spend occurrence disappeared before audit check.'; end if;

  select count(*) filter(where event_kind='recorded'),
         count(*) filter(where event_kind='allocations_replaced'),
         count(*) filter(where event_kind='corrected'),
         count(*) filter(where event_kind='voided')
  into v_recorded,v_replaced,v_corrected,v_voided
  from atlas.organization_spend_events
  where spend_occurrence_id=v_spend_id;

  if v_recorded<>1 or v_replaced<>1 or v_corrected<>1 or v_voided<>1 then
    raise exception 'Spend audit history is incomplete: recorded %, replaced %, corrected %, voided %',v_recorded,v_replaced,v_corrected,v_voided;
  end if;

  select count(*) filter(where allocation_state='superseded'),
         count(*) filter(where allocation_state='voided')
  into v_superseded,v_void_allocations
  from atlas.organization_spend_allocations
  where spend_occurrence_id=v_spend_id;

  if v_superseded<>2 or v_void_allocations<>2 then
    raise exception 'Spend allocation history was rewritten instead of preserved: superseded %, voided %',v_superseded,v_void_allocations;
  end if;
end;
$$;

rollback;
