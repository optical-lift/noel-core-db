-- Atlas custody candidate v1: run AFTER candidate DDL in disposable clone only.
-- No production DDL, fabricated historical work, person, seat or Ledger rows.

do $structural$
declare
  v_rows bigint;
  v_index text;
  v_check text;
begin
  select count(*) into v_rows from atlas.company_work_native_ledger_relevance;
  if v_rows <> 0 then
    raise exception 'FAIL: candidate backfilled historical Company Work (% links)',v_rows;
  end if;

  if not (select relrowsecurity from pg_class
      where oid='atlas.company_work_native_ledger_relevance'::regclass) then
    raise exception 'FAIL: RLS must be enabled';
  end if;
  if has_table_privilege('authenticated','atlas.company_work_native_ledger_relevance','SELECT')
    or has_table_privilege('authenticated','atlas.company_work_native_ledger_relevance','INSERT')
    or has_table_privilege('authenticated','atlas.company_work_native_ledger_relevance','UPDATE')
    or has_table_privilege('anon','atlas.company_work_native_ledger_relevance','SELECT') then
    raise exception 'FAIL: table access leaked';
  end if;

  select pg_get_indexdef(i.indexrelid) into v_index
  from pg_index i where i.indexrelid=
    'atlas.company_work_native_ledger_evidence_active_once_v1'::regclass;
  if v_index not like '%(work_item_id, ledger_id, evidence_kind)%'
    or v_index not like '%attribution_state = %' then
    raise exception 'FAIL: independent evidence-class uniqueness missing';
  end if;

  select pg_get_constraintdef(c.oid) into v_check from pg_constraint c
  where c.conrelid='atlas.company_work_native_ledger_relevance'::regclass
    and c.conname='company_work_relevance_evidence_separation_v1';
  if v_check is null or v_check not like '%owner_attested%'
    or v_check not like '%source_verified%' then
    raise exception 'FAIL: attestation/verification separation check absent';
  end if;

  if has_function_privilege('anon',
       'atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)','EXECUTE')
    or has_function_privilege('anon',
       'atlas.verify_company_work_native_ledger_source_self_api_v1(uuid,uuid)','EXECUTE')
    or has_function_privilege('authenticated',
       'atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)','EXECUTE')
    or has_function_privilege('authenticated',
       'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)','EXECUTE') then
    raise exception 'FAIL: private helper or anonymous RPC privilege leaked';
  end if;
  if not has_function_privilege('authenticated',
       'atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)','EXECUTE')
    or not has_function_privilege('authenticated',
       'atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)','EXECUTE')
    or not has_function_privilege('authenticated',
       'atlas.verify_company_work_native_ledger_source_self_api_v1(uuid,uuid)','EXECUTE')
    or not has_function_privilege('authenticated',
       'atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(uuid,text)','EXECUTE') then
    raise exception 'FAIL: required authenticated gated RPC missing';
  end if;
  raise notice 'PASS: zero-backfill, split evidence, scoped grants, RLS and uniqueness';
end
$structural$;

do $no_source$
declare v_w uuid:=gen_random_uuid();v_l uuid:=gen_random_uuid();
begin
  if exists (
    select 1 from atlas.company_work_native_ledger_exact_source_v1(v_w,v_l)
  ) then
    raise exception 'FAIL: nonexistent source incorrectly verified';
  end if;
  begin
    perform atlas.verify_company_work_native_ledger_source_self_api_v1(v_w,v_l);
    raise exception 'FAIL: unbound, unauthenticated verification permitted';
  exception when sqlstate '42501' then
    raise notice 'PASS: unauthenticated verification fails closed';
  end;
  begin
    perform atlas.establish_company_work_native_ledger_relevance_self_api_v1(
       v_w,v_l,'{"evidenceClass":"source_verified","sourceRef":"made-up","reason":"not proof"}'::jsonb);
    raise exception 'FAIL: fabricated source-verified attestation permitted';
  exception when sqlstate '42501' then
    raise notice 'PASS: unauthenticated invented attestation denied';
  end;
end
$no_source$;

-- Required protected identity fixtures before release (not simulated here):
-- 1. Exact authorized Elm Principal + valid native seat attests one Work to both
--    Flower and Venue without a second atlas.work_items row; 2 evidence rows.
-- 2. Same pair can hold BOTH owner_attested and source_verified, preserving each
--    actor, evidence and timestamp; idempotency cannot rewrite either.
-- 3. A future work_item.source_object_type='ledger_booking_request' WITH the
--    exact ledger.booking_requests.id + ledger_id passes source verification.
-- 4. A wrong source type/ID or a booking request in a different Ledger fails.
-- 5. Source row later changed or removed: currentSourceProof=false and
--    hasCurrentScope=false absent independent attestation; historical record stays.
-- 6. Anonymous, seat-only, wrong-organization Principal and expired session denied.
-- 7. Owner withdrawal preserves source and evidence, no work completion or deletion.
-- 8. Historic Elm+Waiting Room Work remains unknown; no source from labels/units.
-- 9. Optical Lift work never appears in Elm scope or via cross-company adjacency.
