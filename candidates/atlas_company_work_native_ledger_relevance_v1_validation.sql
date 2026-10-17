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


-- Source and relationship acceptance on synthetic data, disposable clone only.
BEGIN;
DO $fixture$
DECLARE
  org uuid:=gen_random_uuid(); other_org uuid:=gen_random_uuid();
  subj uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
  flower uuid:=gen_random_uuid(); venue uuid:=gen_random_uuid();
  case_a uuid:=gen_random_uuid(); case_b uuid:=gen_random_uuid();
  task uuid:=gen_random_uuid(); offering uuid:=gen_random_uuid();
  verified_id uuid;
BEGIN
  INSERT INTO atlas.organizations(id,stable_key,name)
  VALUES(org,'clone-org-'||org::text,'Clone Institution'),
        (other_org,'clone-other-'||other_org::text,'Clone Other Institution');
  INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state)
  VALUES(subj,'clone-subject-'||subj::text,'organization','Clone Institution','canonical'),
        (actor,'clone-actor-'||actor::text,'person','Clone Actor','canonical');
  INSERT INTO ledger.onboarding_cases
    (id,subject_entity_id,desired_ledger_name,onboarding_state,onboarding_basis,case_kind)
  VALUES(case_a,subj,'Clone Flower','ready_to_activate',
         jsonb_build_object('legacyLedgerId',flower::text,'migrationAdjudicated',true),
         'legacy_adjudicated_migration'),
        (case_b,subj,'Clone Venue','ready_to_activate',
         jsonb_build_object('legacyLedgerId',venue::text,'migrationAdjudicated',true),
         'legacy_adjudicated_migration');
  INSERT INTO ledger.ledgers
    (id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state)
  VALUES(flower,subj,case_a,'clone-flower-'||flower::text,'Clone Flower','active'),
        (venue,subj,case_b,'clone-venue-'||venue::text,'Clone Venue','active');
  INSERT INTO atlas.ledgers(id,stable_key,organization_id,ledger_kind,status,name)
  VALUES(flower,'clone-legacy-flower-'||flower::text,org,'governed_reality','active','Clone Flower'),
        (venue,'clone-legacy-venue-'||venue::text,org,'governed_reality','active','Clone Venue');
  INSERT INTO atlas.ledger_organization_participations
    (ledger_id,organization_id,participation_kind,is_compatibility_primary)
  VALUES(flower,org,'governing',true),(venue,org,'operating',false);
  INSERT INTO ledger.booking_offerings
    (id,ledger_id,stable_key,name,booking_kind,occurrence_type,default_duration_minutes)
  VALUES(offering,flower,'clone-offering-'||offering::text,'Clone Event','event','session',60);
  INSERT INTO atlas.work_items
    (id,organization_id,title,work_state,source_object_type,source_object_id)
  VALUES(task,org,'Clone Work','open','ledger_booking_offering',offering);
  IF (SELECT count(*) FROM atlas.company_work_native_ledger_exact_source_v1(task,flower))<>1
      OR EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(task,venue)) THEN
    RAISE EXCEPTION 'FAIL: source evidence was not Ledger-exact';
  END IF;
  INSERT INTO atlas.company_work_native_ledger_relevance
    (organization_id,work_item_id,ledger_id,evidence_kind,attestation_source_ref,
     attestation_reason,established_by_person_id)
  VALUES(org,task,flower,'owner_attested','synthetic','owner relevance',actor),
        (org,task,venue,'owner_attested','synthetic','second purpose',actor);
  INSERT INTO atlas.company_work_native_ledger_relevance
    (organization_id,work_item_id,ledger_id,evidence_kind,
     source_schema,source_table,source_id,verified_at,established_by_person_id)
  VALUES(org,task,flower,'source_verified','ledger','booking_offerings',
         offering,now(),actor) RETURNING id INTO verified_id;
  IF (SELECT count(*) FROM atlas.company_work_native_ledger_relevance
      WHERE work_item_id=task AND attribution_state='active')<>3 THEN
    RAISE EXCEPTION 'FAIL: independent class and cross-Ledger relevance';
  END IF;
  BEGIN
    INSERT INTO atlas.company_work_native_ledger_relevance
      (organization_id,work_item_id,ledger_id,evidence_kind,
       source_schema,source_table,source_id,verified_at,established_by_person_id)
    VALUES(org,task,venue,'source_verified','ledger','booking_offerings',
           offering,now(),actor);
    RAISE EXCEPTION 'FAIL: wrong native Ledger source was accepted';
  EXCEPTION WHEN sqlstate '23514' THEN NULL; END;
  BEGIN
    INSERT INTO atlas.company_work_native_ledger_relevance
      (organization_id,work_item_id,ledger_id,evidence_kind,attestation_source_ref,
       attestation_reason,established_by_person_id)
    VALUES(other_org,task,flower,'owner_attested','synthetic','wrong owner',actor);
    RAISE EXCEPTION 'FAIL: source Organization contradicted';
  EXCEPTION WHEN sqlstate '23514' THEN NULL; END;
  BEGIN
    UPDATE atlas.company_work_native_ledger_relevance
    SET evidence_kind='owner_attested',source_schema=null,source_table=null,
        source_id=null,verified_at=null,attestation_source_ref='changed',
        attestation_reason='forged' WHERE id=verified_id;
    RAISE EXCEPTION 'FAIL: original evidence was mutable';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
  UPDATE atlas.company_work_native_ledger_relevance
  SET attribution_state='withdrawn',withdrawn_at=now(),
      withdrawn_by_person_id=actor,withdrawal_reason='synthetic correction'
  WHERE id=verified_id;
  IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance
    WHERE id=verified_id AND attribution_state='withdrawn'
      AND evidence_kind='source_verified' AND source_id=offering) THEN
    RAISE EXCEPTION 'FAIL: correction lost source history';
  END IF;
  RAISE NOTICE 'PASS: synthetic evidence separation, two Ledger purposes, exact source, isolation and correction';
END
$fixture$;
ROLLBACK;
