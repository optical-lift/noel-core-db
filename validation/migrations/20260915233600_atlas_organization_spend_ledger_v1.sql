-- Postconditions for Atlas Organization Spend — Ledger-Custodied v1.

-- Record one member-funded MXN Spend through the governed core membrane.
do $$
declare
  v_result jsonb;
begin
  v_result:=atlas.record_organization_spend_core_v1(
    '95336000-0000-4000-8000-000000000040'::uuid,
    '95336000-0000-4000-8000-000000000010'::uuid,
    '95336000-0000-4000-8000-000000000050'::uuid,
    '95336000-0000-4000-8000-000000000030'::uuid,
    '95336000-0000-4000-8000-000000000020'::uuid,
    '2026-09-15'::date,
    '2026-09-16 04:30:00+00'::timestamptz,
    1650.00,
    'mxn',
    'organization_member',
    '95336000-0000-4000-8000-000000000030'::uuid,
    '95336000-0000-4000-8000-000000000062'::uuid,
    'Fixture Vendor A',
    'personal_card',
    'validation_fixture',
    'mxn-spend-1',
    '[
      {"amount":1000,"organizationUnitId":"95336000-0000-4000-8000-000000000020","operationalPurpose":"building maintenance","subjectDomain":"company_work","subjectKind":"project","subjectId":"los-domos"},
      {"amount":500,"operationalPurpose":"program supplies"}
    ]'::jsonb,
    '{"validation_fixture":true}'::jsonb,
    '{"validation_fixture":true}'::jsonb
  );

  if v_result->>'state'<>'admitted' then
    raise exception 'Spend core did not admit the fixture occurrence.';
  end if;
end;
$$;

-- Local observed date remains independent from UTC/session-date interpretation.
do $$
declare
  v_on date;
  v_at timestamptz;
  v_currency text;
  v_allocated numeric;
  v_unallocated numeric;
  v_count bigint;
begin
  select occurred_on,occurred_at,currency,allocated_amount,unallocated_amount,active_allocation_count
  into v_on,v_at,v_currency,v_allocated,v_unallocated,v_count
  from atlas.organization_spend_position_v1
  where ledger_id='95336000-0000-4000-8000-000000000040'::uuid
    and source_kind='validation_fixture'
    and source_key='mxn-spend-1';

  if v_on<>'2026-09-15'::date
     or v_at<>'2026-09-16 04:30:00+00'::timestamptz
     or v_currency<>'MXN'
     or v_allocated<>1500
     or v_unallocated<>150
     or v_count<>2 then
    raise exception 'Initial Spend position is incorrect.';
  end if;
end;
$$;

-- Exact source retry is idempotent.
do $$
declare
  v_result jsonb;
  v_count integer;
begin
  v_result:=atlas.record_organization_spend_core_v1(
    '95336000-0000-4000-8000-000000000040'::uuid,
    '95336000-0000-4000-8000-000000000010'::uuid,
    '95336000-0000-4000-8000-000000000050'::uuid,
    '95336000-0000-4000-8000-000000000030'::uuid,
    '95336000-0000-4000-8000-000000000020'::uuid,
    '2026-09-15'::date,
    '2026-09-16 04:30:00+00'::timestamptz,
    1650.00,
    'MXN',
    'organization_member',
    '95336000-0000-4000-8000-000000000030'::uuid,
    '95336000-0000-4000-8000-000000000062'::uuid,
    'Fixture Vendor A',
    'personal_card',
    'validation_fixture',
    'mxn-spend-1',
    null,
    '{"validation_fixture":true}'::jsonb,
    '{"validation_fixture":true}'::jsonb
  );

  select count(*) into v_count
  from atlas.organization_spend_occurrences
  where ledger_id='95336000-0000-4000-8000-000000000040'::uuid
    and source_kind='validation_fixture'
    and source_key='mxn-spend-1';

  if v_result->>'state'<>'unchanged' or v_count<>1 then
    raise exception 'Exact Spend retry is not idempotent.';
  end if;
end;
$$;

-- Conflicting retry under one source identity fails.
do $$
begin
  begin
    perform atlas.record_organization_spend_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000010'::uuid,
      '95336000-0000-4000-8000-000000000050'::uuid,
      '95336000-0000-4000-8000-000000000030'::uuid,
      '95336000-0000-4000-8000-000000000020'::uuid,
      '2026-09-15'::date,
      '2026-09-16 04:30:00+00'::timestamptz,
      1600.00,'MXN','organization_member',
      '95336000-0000-4000-8000-000000000030'::uuid,
      '95336000-0000-4000-8000-000000000062'::uuid,
      'Fixture Vendor A','personal_card',
      'validation_fixture','mxn-spend-1',null,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Conflicting Spend retry unexpectedly succeeded.';
  exception when sqlstate '23514' then
    null;
  end;
end;
$$;

-- Ledger/Organization custody cannot be crossed.
do $$
begin
  begin
    perform atlas.record_organization_spend_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000011'::uuid,
      null,null,null,'2026-09-15',null,25,'USD','organization',null,null,
      'Cross custody',null,'validation_fixture','cross-custody',null,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Cross-Ledger Organization Spend unexpectedly succeeded.';
  exception when sqlstate '23503' then
    null;
  end;
end;
$$;

-- Foreign Unit, payer membership, and payee relationship cannot cross Organization custody.
do $$
begin
  begin
    perform atlas.record_organization_spend_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000010'::uuid,
      null,null,
      '95336000-0000-4000-8000-000000000021'::uuid,
      '2026-09-15',null,25,'USD','organization',null,null,
      'Foreign unit',null,'validation_fixture','foreign-unit',null,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Foreign Spend Unit unexpectedly succeeded.';
  exception when sqlstate '23503' then null;
  end;

  begin
    perform atlas.record_organization_spend_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000010'::uuid,
      null,null,null,'2026-09-15',null,25,'USD','organization_member',
      '95336000-0000-4000-8000-000000000031'::uuid,null,
      'Foreign payer',null,'validation_fixture','foreign-payer',null,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Foreign payer membership unexpectedly succeeded.';
  exception when sqlstate '23503' then null;
  end;

  begin
    perform atlas.record_organization_spend_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000010'::uuid,
      null,null,null,'2026-09-15',null,25,'USD','organization',null,
      '95336000-0000-4000-8000-000000000063'::uuid,
      'Foreign payee',null,'validation_fixture','foreign-payee',null,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Foreign payee relationship unexpectedly succeeded.';
  exception when sqlstate '23503' then null;
  end;
end;
$$;

-- Allocation sum cannot exceed gross amount.
do $$
begin
  begin
    perform atlas.record_organization_spend_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000010'::uuid,
      null,null,null,'2026-09-15',null,100,'USD','organization',null,null,
      'Over allocation',null,'validation_fixture','over-allocated',
      '[{"amount":60},{"amount":50}]'::jsonb,'{}'::jsonb,'{}'::jsonb
    );
    raise exception 'Over-allocation unexpectedly succeeded.';
  exception when sqlstate '23514' then null;
  end;

  if exists (
    select 1 from atlas.organization_spend_occurrences
    where ledger_id='95336000-0000-4000-8000-000000000040'::uuid
      and source_kind='validation_fixture' and source_key='over-allocated'
  ) then
    raise exception 'Failed over-allocation left a partial Spend occurrence.';
  end if;
end;
$$;

-- Evidence under the governing Principal may attach; foreign-Ledger Principal evidence may not.
do $$
declare
  v_spend_id uuid;
  v_link_id uuid;
begin
  select id into v_spend_id
  from atlas.organization_spend_occurrences
  where ledger_id='95336000-0000-4000-8000-000000000040'::uuid
    and source_kind='validation_fixture' and source_key='mxn-spend-1';

  v_link_id:=atlas.link_organization_spend_evidence_core_v1(
    '95336000-0000-4000-8000-000000000040'::uuid,
    '95336000-0000-4000-8000-000000000010'::uuid,
    v_spend_id,null,
    '95336000-0000-4000-8000-000000000070'::uuid,
    'receipt',
    '95336000-0000-4000-8000-000000000050'::uuid,
    '95336000-0000-4000-8000-000000000030'::uuid,
    '{"validation_fixture":true}'::jsonb
  );

  if v_link_id is null then raise exception 'Valid Spend evidence link was not created.'; end if;

  begin
    perform atlas.link_organization_spend_evidence_core_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,
      '95336000-0000-4000-8000-000000000010'::uuid,
      v_spend_id,null,
      '95336000-0000-4000-8000-000000000071'::uuid,
      'receipt',null,null,'{}'::jsonb
    );
    raise exception 'Foreign Principal evidence unexpectedly linked to Spend.';
  exception when sqlstate '23503' then null;
  end;
end;
$$;

-- Simulate authenticated Principal A and replace allocations through the self membrane.
do $$
declare
  v_spend_id uuid;
  v_result jsonb;
  v_active integer;
  v_superseded integer;
  v_replaced_events integer;
begin
  perform set_config('request.jwt.claim.sub','95336000-0000-4000-8000-000000000001',true);

  select id into v_spend_id
  from atlas.organization_spend_occurrences
  where ledger_id='95336000-0000-4000-8000-000000000040'::uuid
    and source_kind='validation_fixture' and source_key='mxn-spend-1';

  v_result:=atlas.replace_organization_spend_allocations_self_api_v1(
    v_spend_id,
    'replace-1',
    '[{"amount":900,"operationalPurpose":"facilities"},{"amount":600,"operationalPurpose":"program supplies"}]'::jsonb,
    'Fixture reallocation'
  );

  select count(*) filter (where allocation_state='active'),
         count(*) filter (where allocation_state='superseded')
  into v_active,v_superseded
  from atlas.organization_spend_allocations
  where spend_occurrence_id=v_spend_id;

  select count(*) into v_replaced_events
  from atlas.organization_spend_events
  where spend_occurrence_id=v_spend_id and event_kind='allocations_replaced';

  if v_result->>'state'<>'replaced' or v_active<>2 or v_superseded<>2 or v_replaced_events<>1 then
    raise exception 'Allocation replacement did not preserve superseded history.';
  end if;
end;
$$;

-- Correction is audited and cannot reduce gross below active allocations.
do $$
declare
  v_spend_id uuid;
  v_result jsonb;
  v_gross numeric;
  v_events integer;
begin
  perform set_config('request.jwt.claim.sub','95336000-0000-4000-8000-000000000001',true);
  select id into v_spend_id from atlas.organization_spend_occurrences
  where ledger_id='95336000-0000-4000-8000-000000000040'::uuid
    and source_kind='validation_fixture' and source_key='mxn-spend-1';

  begin
    perform atlas.correct_organization_spend_self_api_v1(
      v_spend_id,'bad-correction','2026-09-15','2026-09-16 04:30:00+00',1400,'MXN',
      '95336000-0000-4000-8000-000000000062'::uuid,'Fixture Vendor A','personal_card','Too low'
    );
    raise exception 'Correction below active allocation unexpectedly succeeded.';
  exception when sqlstate '23514' then null;
  end;

  v_result:=atlas.correct_organization_spend_self_api_v1(
    v_spend_id,'correct-1','2026-09-15','2026-09-16 04:30:00+00',1800,'MXN',
    '95336000-0000-4000-8000-000000000062'::uuid,'Fixture Vendor A','personal_card','Fixture amount correction'
  );

  select gross_amount into v_gross from atlas.organization_spend_occurrences where id=v_spend_id;
  select count(*) into v_events from atlas.organization_spend_events where spend_occurrence_id=v_spend_id and event_kind='corrected';

  if v_result->>'state'<>'corrected' or v_gross<>1800 or v_events<>1 then
    raise exception 'Spend correction did not establish the expected audited position.';
  end if;
end;
$$;

-- Create a second self-captured Spend and void it without claiming a refund.
do $$
declare
  v_result jsonb;
  v_spend_id uuid;
  v_state text;
  v_active integer;
  v_void_events integer;
begin
  perform set_config('request.jwt.claim.sub','95336000-0000-4000-8000-000000000001',true);

  v_result:=atlas.record_organization_spend_self_api_v1(
    '95336000-0000-4000-8000-000000000040'::uuid,
    '95336000-0000-4000-8000-000000000010'::uuid,
    'self-spend-void-1',
    null,'2026-09-15',null,75,'USD','organization',null,null,
    'Fixture void candidate','cash','[{"amount":75,"operationalPurpose":"supplies"}]'::jsonb,
    '{"validation_fixture":true}'::jsonb
  );

  v_spend_id:=(v_result->>'spendOccurrenceId')::uuid;
  perform atlas.void_organization_spend_self_api_v1(v_spend_id,'void-1','Fixture mistaken duplicate');

  select truth_state into v_state from atlas.organization_spend_occurrences where id=v_spend_id;
  select count(*) into v_active from atlas.organization_spend_allocations where spend_occurrence_id=v_spend_id and allocation_state='active';
  select count(*) into v_void_events from atlas.organization_spend_events where spend_occurrence_id=v_spend_id and event_kind='voided';

  if v_state<>'voided' or v_active<>0 or v_void_events<>1 then
    raise exception 'Spend void did not establish the expected current/audit state.';
  end if;
end;
$$;

-- History tables reject mutation.
do $$
declare
  v_event_id uuid;
begin
  select id into v_event_id from atlas.organization_spend_events order by created_at,id limit 1;
  begin
    update atlas.organization_spend_events set reason='mutated' where id=v_event_id;
    raise exception 'Spend event update unexpectedly succeeded.';
  exception when sqlstate '55000' then null;
  end;
end;
$$;

-- Root Ledger authority gates browser reads.
do $$
declare
  v_payload jsonb;
begin
  perform set_config('request.jwt.claim.sub','95336000-0000-4000-8000-000000000001',true);
  v_payload:=atlas.organization_spend_window_self_api_v1(
    '95336000-0000-4000-8000-000000000040'::uuid,'2026-09-01','2026-09-30'
  );
  if jsonb_array_length(v_payload->'spend')<>2 then
    raise exception 'Authorized Spend window did not return both fixture occurrences.';
  end if;

  perform set_config('request.jwt.claim.sub','95336000-0000-4000-8000-000000000002',true);
  begin
    perform atlas.organization_spend_window_self_api_v1(
      '95336000-0000-4000-8000-000000000040'::uuid,'2026-09-01','2026-09-30'
    );
    raise exception 'Foreign Principal unexpectedly read Spend Ledger.';
  exception when sqlstate '42501' then null;
  end;
end;
$$;

-- Direct table access is unavailable; only governed command/read seams are granted.
do $$
begin
  if has_table_privilege('authenticated','atlas.organization_spend_occurrences','SELECT')
     or has_table_privilege('authenticated','atlas.organization_spend_occurrences','INSERT')
     or has_table_privilege('service_role','atlas.organization_spend_occurrences','SELECT')
     or has_table_privilege('service_role','atlas.organization_spend_occurrences','INSERT') then
    raise exception 'Direct Spend table privilege leaked.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'atlas.organization_spend_window_self_api_v1(uuid,date,date)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated Spend read membrane is missing.';
  end if;

  if has_function_privilege(
    'anon',
    'atlas.organization_spend_window_self_api_v1(uuid,date,date)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous Spend read privilege leaked.';
  end if;

  if not has_function_privilege(
    'service_role',
    'atlas.record_organization_spend_core_v1(uuid,uuid,uuid,uuid,uuid,date,timestamp with time zone,numeric,text,text,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Service Spend core command privilege is missing.';
  end if;
end;
$$;

-- Existing Package 5 Commercial Financial Reality and Package 4 Flower writer remain intact.
do $$
begin
  if to_regclass('atlas.commercial_financial_position_v1') is null then
    raise exception 'Commercial Financial Reality view disappeared.';
  end if;

  if to_regprocedure('atlas.record_flower_sale_core_v2(uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text,boolean)') is null then
    raise exception 'Current Package-4 Flower Sale v2 writer disappeared.';
  end if;
end;
$$;
