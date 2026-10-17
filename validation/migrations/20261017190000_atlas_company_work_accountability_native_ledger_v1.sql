-- AUTHORIZATION ACCEPTANCE: synthetic JWT / auth.session / Person / Principal in a
-- completely isolated production-schema clone, rollback-only, no actual accounts.
-- The trusted SQL harness creates request.jwt.claims as PostgREST would after
-- verifying a JWT; this checks DB authorization and NOT token signature validation.
BEGIN;
DO $setup$
DECLARE
  v_org uuid:=gen_random_uuid(); v_other uuid:=gen_random_uuid();
  v_subject uuid:=gen_random_uuid();v_flower uuid:=gen_random_uuid();
  v_venue uuid:=gen_random_uuid(); v_case_a uuid:=gen_random_uuid();
  v_case_b uuid:=gen_random_uuid();v_work uuid:=gen_random_uuid();
  v_offering uuid:=gen_random_uuid();
  v_owner uuid:=gen_random_uuid();v_member uuid:=gen_random_uuid();
  v_outsider uuid:=gen_random_uuid();
  v_owner_session uuid:=gen_random_uuid();v_member_session uuid:=gen_random_uuid();
  v_outsider_session uuid:=gen_random_uuid();
  v_actor record;
  v_person uuid;
  v_owner_person uuid; v_member_person uuid; v_outsider_person uuid;
  v_owner_principal uuid;v_member_principal uuid;v_outsider_principal uuid;
  v_temp_principal uuid;
  v_unconnected_person uuid:=gen_random_uuid();
  v_staff_unit uuid:=gen_random_uuid();
  v_staff_position uuid:=gen_random_uuid();
BEGIN
  INSERT INTO atlas.organizations(id,stable_key,name)
  VALUES(v_org,'auth-elm-'||v_org::text,'Synthetic Elm Organization'),
        (v_other,'auth-other-'||v_other::text,'Synthetic Separate Organization');
  INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
  VALUES(v_subject,'auth-business-'||v_subject::text,'organization','Synthetic Ledger Subject');
  INSERT INTO ledger.onboarding_cases
    (id,subject_entity_id,desired_ledger_name,onboarding_state,onboarding_basis,case_kind)
  VALUES
    (v_case_a,v_subject,'Synthetic Flowers','ready_to_activate',
     jsonb_build_object('legacyLedgerId',v_flower::text,'migrationAdjudicated',true),
     'legacy_adjudicated_migration'),
    (v_case_b,v_subject,'Synthetic Venue','ready_to_activate',
     jsonb_build_object('legacyLedgerId',v_venue::text,'migrationAdjudicated',true),
     'legacy_adjudicated_migration');
  INSERT INTO ledger.ledgers
    (id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state)
  VALUES(v_flower,v_subject,v_case_a,'auth-flower-'||v_flower::text,'Synthetic Flowers','active'),
        (v_venue,v_subject,v_case_b,'auth-venue-'||v_venue::text,'Synthetic Venue','active');
  INSERT INTO atlas.ledgers
    (id,stable_key,organization_id,ledger_kind,status,name)
  VALUES(v_flower,'auth-legacy-flower-'||v_flower::text,v_org,'governed','active','Synthetic Flowers'),
        (v_venue,'auth-legacy-venue-'||v_venue::text,v_org,'governed','active','Synthetic Venue');
  INSERT INTO atlas.ledger_organization_participations
    (ledger_id,organization_id,participation_kind,is_compatibility_primary)
  VALUES(v_flower,v_org,'governing',true),(v_venue,v_org,'operating',false);
  INSERT INTO ledger.booking_offerings
    (id,ledger_id,stable_key,name,booking_kind,occurrence_type,default_duration_minutes)
  VALUES(v_offering,v_flower,'auth-offer-'||v_offering::text,'Synthetic Offering','event','session',60);
  INSERT INTO atlas.work_items
    (id,organization_id,title,work_state,source_object_type,source_object_id)
  VALUES(v_work,v_org,'Synthetic Ledger-Custodied Work','open',
        'ledger_booking_offering',v_offering);
  FOR v_actor IN
    SELECT v_owner as user_id,'owner'::text as label,v_owner_session as session_id,v_org as org
    UNION ALL SELECT v_member,'seat_only',v_member_session,v_org
    UNION ALL SELECT v_outsider,'outsider',v_outsider_session,v_other
  LOOP
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
    VALUES(v_actor.user_id,'authenticated','authenticated',
      v_actor.label||'-'||v_actor.user_id::text||'@example.invalid',
      '{}'::jsonb,'{}'::jsonb);
    INSERT INTO auth.sessions(id,user_id,not_after)
    VALUES(v_actor.session_id,v_actor.user_id,now()+interval '1 hour');
    INSERT INTO atlas.principals(user_id,organization_id,stable_key,name)
    VALUES(v_actor.user_id,v_actor.org,
      'synthetic-auth-'||v_actor.user_id::text,'Synthetic '||v_actor.label)
    RETURNING id,person_id INTO v_temp_principal,v_person;
    INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
    VALUES(v_person,'synthetic-person-'||v_person::text,'person',
      'Synthetic '||v_actor.label);
    INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id)
    VALUES(v_actor.user_id,v_person);
    INSERT INTO atlas.institutional_person_records(organization_id,person_id)
    VALUES(v_actor.org,v_person);
    CASE v_actor.label
      WHEN 'owner' THEN v_owner_person:=v_person;
      WHEN 'seat_only' THEN v_member_person:=v_person;
      WHEN 'outsider' THEN v_outsider_person:=v_person;
    END CASE;
    CASE v_actor.label
      WHEN 'owner' THEN
        SELECT id INTO v_owner_principal FROM atlas.principals WHERE user_id=v_owner;
      WHEN 'seat_only' THEN
        SELECT id INTO v_member_principal FROM atlas.principals WHERE user_id=v_member;
      WHEN 'outsider' THEN
        SELECT id INTO v_outsider_principal FROM atlas.principals WHERE user_id=v_outsider;
    END CASE;
  END LOOP;
  -- A Person can belong institutionally without any Atlas account.
  INSERT INTO atlas.people(id,display_name)
  VALUES(v_unconnected_person,'Synthetic No Atlas Account');
  INSERT INTO atlas.institutional_person_records(organization_id,person_id)
  VALUES(v_org,v_unconnected_person);
  -- A real position appointment is distinct from a native Ledger seat.
  INSERT INTO atlas.organization_units(id,organization_id,stable_key,name)
  VALUES(v_staff_unit,v_org,'people-dept-'||v_staff_unit::text,'Synthetic Team');
  INSERT INTO atlas.organization_positions(
    id,organization_id,organization_unit_id,stable_key,display_title)
  VALUES(v_staff_position,v_org,v_staff_unit,
         'people-position-'||v_staff_position::text,'Synthetic Steward');
  INSERT INTO atlas.organization_position_appointments(
    organization_id,position_id,institutional_person_record_id,appointment_kind)
  SELECT v_org,v_staff_position,ipr.id,'primary'
  FROM atlas.institutional_person_records ipr
  WHERE ipr.person_id=v_member_person AND ipr.organization_id=v_org;
  INSERT INTO ledger.seats(ledger_id,person_entity_id,seat_basis)
  VALUES (v_flower,v_owner_person,'{"basis":"synthetic_owner"}'::jsonb),
         (v_venue,v_owner_person,'{"basis":"synthetic_owner"}'::jsonb),
         (v_flower,v_member_person,'{"basis":"synthetic_seat_only"}'::jsonb);
  INSERT INTO atlas.principal_ledger_authorities
    (principal_id,ledger_id,authority_kind,basis)
  VALUES(v_owner_principal,v_flower,'root_governing','synthetic root owner'),
        (v_owner_principal,v_venue,'root_governing','synthetic root owner');
  PERFORM set_config('atlas.test_native_work_scope',jsonb_build_object(
    'org',v_org,'other',v_other,'flower',v_flower,'venue',v_venue,
    'work',v_work,'offering',v_offering,
    'owner',v_owner,'seatOnly',v_member,'memberPerson',v_member_person,'outsider',v_outsider,
    'ownerSession',v_owner_session,'seatOnlySession',v_member_session,
    'outsiderSession',v_outsider_session)::text,true);
  RAISE NOTICE 'PASS: synthetic authenticatable owner, seat-only and outsider person/principal/session data created';
END
$setup$;

-- Run real RPC SQL as the PostgREST authenticated database role, not postgres.
SET LOCAL ROLE authenticated;
DO $accept$
DECLARE
  f jsonb:=current_setting('atlas.test_native_work_scope')::jsonb;
  v_org uuid;v_other uuid;v_flower uuid;v_venue uuid;v_work uuid;v_offering uuid;
  v_result jsonb;v_verified uuid;v_attested uuid;
  v_people jsonb;v_venue_people jsonb;
  v_count integer;v_accountability jsonb;v_owner_ledger_seat text;v_unconnected_state text;
  v_member_flower_seat text;v_member_venue_seat text;
BEGIN
  v_org:=(f->>'org')::uuid;v_other:=(f->>'other')::uuid;
  v_flower:=(f->>'flower')::uuid;v_venue:=(f->>'venue')::uuid;
  v_work:=(f->>'work')::uuid;v_offering:=(f->>'offering')::uuid;
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',f->>'owner','role','authenticated',
    'session_id',f->>'ownerSession')::text,true);
  IF (atlas.reality_access_self_api_v1()->>'state')<>'ready' THEN
    RAISE EXCEPTION 'FAIL: synthetic owner session is not ready';
  END IF;
  -- Unattributed work is visible only when the root owner expressly chooses
  -- the institution-wide lens; it cannot leak into Flowers by default.
  v_accountability:=atlas.company_work_accountability_native_ledger_self_api_v1(
    v_org,v_flower,'organization',50,null);
  IF jsonb_array_length(v_accountability->'items')<>1
     OR v_accountability#>>'{items,0,nativeLedgerRelevance}'
        <>'not_established_for_selected_ledger'
     OR v_accountability#>>'{items,0,responsibility,state}'
        <>'no_active_responsible_allocation'
     OR v_accountability#>>'{items,0,workerProjection,state}'
        <>'no_matching_worker_projection_observed' THEN
    RAISE EXCEPTION 'FAIL: pre-attribution institutional Work did not retain separate responsibility, plan and projection state';
  END IF;
  v_accountability:=atlas.company_work_accountability_native_ledger_self_api_v1(
    v_org,v_flower,'native_ledger',50,null);
  IF jsonb_array_length(v_accountability->'items')<>0 THEN
    RAISE EXCEPTION 'FAIL: unattributed Organization Work leaked into Flower Ledger';
  END IF;
  RAISE NOTICE 'PASS: Organization work is observable without manufacturing Flower Ledger association';

  v_people:=atlas.company_people_native_ledger_scope_self_api_v1(
    v_org,v_flower,50,null);
  IF jsonb_array_length(v_people->'items')<>3 THEN
    RAISE EXCEPTION 'FAIL: owner People roster expected 3, got %',
      jsonb_array_length(v_people->'items');
  END IF;
  IF (v_people->'truthBoundary'->>'privatePersonalAtlasNotRead')::boolean
      IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: private Personal Atlas boundary missing';
  END IF;
  SELECT count(*)::integer INTO v_count
  FROM jsonb_array_elements(v_people->'items') x
  WHERE x->>'displayName'='Synthetic No Atlas Account'
    AND x->>'institutionalCredentialState'='no_current_institutional_auth_credential_proven'
    AND jsonb_array_length(x->'positionAppointments')=0;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'FAIL: non-account human incorrectly omitted or given invented role';
  END IF;
  SELECT x->>'nativeLedgerSeatState' INTO v_member_flower_seat
  FROM jsonb_array_elements(v_people->'items') x
  WHERE x->>'displayName'='Synthetic seat_only';
  IF v_member_flower_seat<>'active_participation_only' THEN
    RAISE EXCEPTION 'FAIL: native Flower participant missing';
  END IF;
  v_venue_people:=atlas.company_people_native_ledger_scope_self_api_v1(
    v_org,v_venue,50,null);
  IF jsonb_array_length(v_venue_people->'items')<>3 THEN
    RAISE EXCEPTION 'FAIL: Organization roster changed across two Ledgers';
  END IF;
  SELECT x->>'nativeLedgerSeatState' INTO v_member_venue_seat
  FROM jsonb_array_elements(v_venue_people->'items') x
  WHERE x->>'displayName'='Synthetic seat_only';
  IF v_member_venue_seat<>'not_proven' THEN
    RAISE EXCEPTION 'FAIL: Flower seat falsely admitted as Venue seat';
  END IF;
  SELECT count(*)::integer INTO v_count
  FROM jsonb_array_elements(v_venue_people->'items') x
  WHERE x->>'displayName'='Synthetic seat_only'
    AND jsonb_array_length(x->'positionAppointments')=1
    AND x#>>'{positionAppointments,0,ledgerPositionProof}'
        ='not_established_by_organization_appointment';
  IF v_count<>1 THEN
    RAISE EXCEPTION 'FAIL: institutional appointment was not held separate from exact Ledger proof';
  END IF;
  BEGIN
    PERFORM atlas.company_people_native_ledger_scope_self_api_v1(v_org,v_other,50,null);
    RAISE EXCEPTION 'FAIL: wrong native Ledger context was accepted';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
  RAISE NOTICE 'PASS: owner People sees 3 stable identities, non-account human, one appointment, exact native seat difference, and private boundary';

  v_result:=atlas.establish_company_work_native_ledger_relevance_self_api_v1(
     v_work,v_flower,
     '{"evidenceClass":"owner_attestation","sourceRef":"synthetic owner command","reason":"documented purpose"}'::jsonb);
  IF v_result->>'evidenceKind'<>'owner_attested' OR (v_result->>'alreadyEstablished')::boolean THEN
    RAISE EXCEPTION 'FAIL: owner attestation did not establish independently';
  END IF;
  v_attested:=(v_result->>'attributionId')::uuid;
  v_result:=atlas.establish_company_work_native_ledger_relevance_self_api_v1(
     v_work,v_flower,
     '{"evidenceClass":"owner_attestation","sourceRef":"second request","reason":"duplicate"}'::jsonb);
  IF (v_result->>'alreadyEstablished')::boolean IS DISTINCT FROM true
    OR (v_result->>'attributionId')::uuid<>v_attested THEN
    RAISE EXCEPTION 'FAIL: owner attestation idempotency';
  END IF;
  v_result:=atlas.establish_company_work_native_ledger_relevance_self_api_v1(
     v_work,v_venue,
     '{"evidenceClass":"owner_attestation","sourceRef":"synthetic owner command","reason":"second Ledger purpose"}'::jsonb);
  IF v_result->>'evidenceKind'<>'owner_attested' THEN
    RAISE EXCEPTION 'FAIL: second Ledger purpose was rejected';
  END IF;
  v_result:=atlas.verify_company_work_native_ledger_source_self_api_v1(v_work,v_flower);
  IF v_result->>'evidenceKind'<>'source_verified'
      OR (v_result->>'sourceId')::uuid<>v_offering THEN
    RAISE EXCEPTION 'FAIL: owner source verification lacked exact native source proof';
  END IF;
  v_verified:=(v_result->>'attributionId')::uuid;
  v_result:=atlas.verify_company_work_native_ledger_source_self_api_v1(v_work,v_flower);
  IF (v_result->>'alreadyEstablished')::boolean IS DISTINCT FROM true
    OR (v_result->>'attributionId')::uuid<>v_verified THEN
    RAISE EXCEPTION 'FAIL: source verification idempotency';
  END IF;
  BEGIN
    PERFORM atlas.verify_company_work_native_ledger_source_self_api_v1(v_work,v_venue);
    RAISE EXCEPTION 'FAIL: incorrect Venue source was accepted';
  EXCEPTION WHEN sqlstate '23514' THEN NULL;END;
  v_result:=atlas.company_work_native_ledger_scope_self_api_v1(v_org,v_flower,100,null);
  IF jsonb_array_length(v_result->'items')<>1
    OR jsonb_array_length(v_result#>'{items,0,evidence}')<>2
    OR (v_result#>>'{items,0,has_current_scope}')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: owner read duplicated Work or conflated evidence';
  END IF;
  v_accountability:=atlas.company_work_accountability_native_ledger_self_api_v1(
    v_org,v_flower,'native_ledger',50,null);
  IF jsonb_array_length(v_accountability->'items')<>1
     OR v_accountability#>>'{items,0,workItemId}'<>v_work::text
     OR v_accountability#>>'{items,0,nativeLedgerRelevance}'<>'established_for_selected_ledger'
     OR (v_accountability#>>'{facts,projectionIsNotProofWorkerViewed}')::boolean IS DISTINCT FROM true
     OR (v_accountability#>>'{facts,reportIsNotAcceptance}')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: actual Flower attribution did not reach governed manager accountability';
  END IF;
  v_accountability:=atlas.company_work_accountability_native_ledger_self_api_v1(
    v_org,v_venue,'native_ledger',50,null);
  IF jsonb_array_length(v_accountability->'items')<>1
     OR v_accountability#>>'{items,0,workItemId}'<>v_work::text THEN
    RAISE EXCEPTION 'FAIL: multi-Ledger relevance cloned or lost canonical Work identity';
  END IF;
  BEGIN
    PERFORM atlas.company_work_accountability_native_ledger_self_api_v1(
      v_org,v_flower,'guessed_ledger_scope',50,null);
    RAISE EXCEPTION 'FAIL: arbitrary scope was accepted';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  RAISE NOTICE 'PASS: one exact Work identity in two attested native Ledger lenses, reports not acceptance';

  RAISE NOTICE 'PASS: authenticated root owner can attest two native Ledgers, prove exact source, read one work, and replay idempotently';
  -- An authenticated seat-only member must be denied, despite a real seat.
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',f->>'seatOnly','role','authenticated',
    'session_id',f->>'seatOnlySession')::text,true);
  IF (atlas.reality_access_self_api_v1()->>'state')<>'ready' THEN
    RAISE EXCEPTION 'FAIL: seat-only synthetic session not ready';
  END IF;
  BEGIN
    PERFORM atlas.company_people_native_ledger_scope_self_api_v1(v_org,v_flower,50,null);
    RAISE EXCEPTION 'FAIL: seat-only caller read institution People';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.company_work_native_ledger_scope_self_api_v1(v_org,v_flower,20,null);
    RAISE EXCEPTION 'FAIL: seat-only user read root-owned Work';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.company_work_accountability_native_ledger_self_api_v1(v_org,v_flower,'organization',50,null);
    RAISE EXCEPTION 'FAIL: seat-only user read organization accountability';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.establish_company_work_native_ledger_relevance_self_api_v1(
      v_work,v_flower,'{"evidenceClass":"owner_attestation","sourceRef":"forged","reason":"not root"}'::jsonb);
    RAISE EXCEPTION 'FAIL: seat-only user wrote owner attestation';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  -- Another Organization's native session has no Elm custody.
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',f->>'outsider','role','authenticated',
    'session_id',f->>'outsiderSession')::text,true);
  BEGIN
    PERFORM atlas.company_people_native_ledger_scope_self_api_v1(v_org,v_flower,50,null);
    RAISE EXCEPTION 'FAIL: outsider read Elm People';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.company_work_native_ledger_scope_self_api_v1(v_org,v_flower,20,null);
    RAISE EXCEPTION 'FAIL: outsider read Elm Work';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.company_work_accountability_native_ledger_self_api_v1(v_org,v_flower,'native_ledger',50,null);
    RAISE EXCEPTION 'FAIL: outsider read native Ledger accountability';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.verify_company_work_native_ledger_source_self_api_v1(v_work,v_flower);
    RAISE EXCEPTION 'FAIL: outsider verified Elm Work';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  -- Owner identity with a nonexistent or revoked session must fail.
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',f->>'owner','role','authenticated',
    'session_id',gen_random_uuid()::text)::text,true);
  IF atlas.reality_access_self_api_v1()->>'state'<>'session_invalid' THEN
    RAISE EXCEPTION 'FAIL: invalid session not rejected';
  END IF;
  BEGIN
    PERFORM atlas.company_people_native_ledger_scope_self_api_v1(v_org,v_flower,50,null);
    RAISE EXCEPTION 'FAIL: invalid session read People';
  EXCEPTION WHEN sqlstate '42501' THEN NULL; END;
  BEGIN
    PERFORM atlas.company_work_native_ledger_scope_self_api_v1(v_org,v_flower,20,null);
    RAISE EXCEPTION 'FAIL: invalid session could access Company Work';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  BEGIN
    PERFORM atlas.company_work_accountability_native_ledger_self_api_v1(v_org,v_flower,'organization',50,null);
    RAISE EXCEPTION 'FAIL: invalid session read Company Work accountability';
  EXCEPTION WHEN sqlstate '42501' THEN NULL;END;
  RAISE NOTICE 'PASS: seat-only, other Organization, and invalid sessions denied';
END
$accept$;
-- SECOND ACCEPTANCE: genuinely different identities for authenticated institution
-- owner and worker, two Worker Day dates, and report/acceptance distinctions.
-- All rows below are SYNTHETIC in the disposable clone transaction; never
-- source for production backfill, employee schedules, or real user state.
RESET ROLE;
DO $worker_setup$
DECLARE
 f jsonb:=current_setting('atlas.test_native_work_scope')::jsonb;
 v_org uuid:=(f->>'org')::uuid;
 v_work uuid:=(f->>'work')::uuid;
 v_worker uuid:=(f->>'seatOnly')::uuid;
 v_subject uuid;v_org_membership uuid;v_ipr uuid;v_farm uuid;v_farm_membership uuid;
 v_unit uuid;v_seat uuid;v_plan uuid;v_today_projection uuid;
 v_future_projection uuid;v_today date:=(now() AT TIME ZONE 'America/Chicago')::date;
 v_policy text:='synthetic-company-work-attested-'||substr(gen_random_uuid()::text,1,8);
BEGIN
 SELECT ou.id INTO v_unit FROM atlas.organization_units ou
 WHERE ou.organization_id=v_org AND ou.name='Synthetic Team' LIMIT 1;
 SELECT ipr.id INTO v_ipr
 FROM atlas.institutional_person_records ipr
 JOIN reality.auth_person_bindings b ON b.person_entity_id=ipr.person_id
 WHERE b.auth_user_id=v_worker AND ipr.organization_id=v_org;
 IF v_unit IS NULL OR v_ipr IS NULL THEN
   RAISE EXCEPTION 'FAIL: synthetic worker unit or institutional Person missing';
 END IF;
 INSERT INTO atlas.identity_subjects(organization_id,creation_basis)
 VALUES(v_org,'{"synthetic":"Build3 rollback-only worker delivery validation"}'::jsonb)
 RETURNING id INTO v_subject;
 INSERT INTO atlas.organization_memberships(
   organization_id,user_id,role,identity_subject_id,institutional_person_record_id)
 VALUES(v_org,v_worker,'member',v_subject,v_ipr)
 RETURNING id INTO v_org_membership;
 INSERT INTO atlas.farms(
   organization_id,organization_unit_id,stable_key,name,metadata)
 VALUES(v_org,v_unit,'synthetic-work-farm-'||gen_random_uuid()::text,
   'Synthetic work delivery farm','{"timezone":"America/Chicago"}'::jsonb)
 RETURNING id INTO v_farm;
 INSERT INTO atlas.farm_memberships(farm_id,user_id,role,identity_subject_id)
 VALUES(v_farm,v_worker,'farm_hand',v_subject)
 RETURNING id INTO v_farm_membership;
 UPDATE atlas.organization_position_appointments
 SET organization_membership_id=v_org_membership,identity_subject_id=v_subject
 WHERE organization_id=v_org AND institutional_person_record_id=v_ipr;
 IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: synthetic worker appointment missing';END IF;
 INSERT INTO atlas.organization_employee_seats(
   organization_id,organization_membership_id,identity_subject_id,
   institutional_person_record_id,seat_class,status,billing_state)
 VALUES(v_org,v_org_membership,v_subject,v_ipr,'employee','active','waived')
 RETURNING id INTO v_seat;
 INSERT INTO atlas.organization_member_credentials(
   organization_id,organization_membership_id,employee_seat_id,
   identity_subject_id,credential_kind,auth_user_id,issued_by_organization_id)
 VALUES(v_org,v_org_membership,v_seat,v_subject,'auth_user',v_worker,v_org);
 INSERT INTO atlas.work_result_contract_policies(contract_key,source_domain,acceptance_mode)
 VALUES(v_policy,'synthetic_institutional_work','worker_attestation');
 UPDATE atlas.work_items SET organization_unit_id=v_unit,result_contract_key=v_policy
 WHERE id=v_work AND organization_id=v_org;
 -- Establish test responsibility through the EXISTING governed internal
 -- receiver-uptake basis constructor, not by forging an ad-hoc allocation row.
 -- This fixture never commits and is not an employee delegation.
 PERFORM atlas.set_company_work_responsibility_with_basis_internal_v2(
   v_work,v_org_membership,v_org_membership,'self_adoption',
   jsonb_build_object('sourceKind','synthetic_rollback_only_validation',
                      'sourceId',v_work::text),
   'Synthetic source responsibility acceptance test',
   '{"source":"rollback_only_source_validation","synthetic":true}'::jsonb
 );
 INSERT INTO atlas.worker_week_projection(
    organization_id,organization_membership_id,farm_id,membership_id,
    planned_date,source_kind,source_id,title,plan_state,locked,delivery_payload)
 VALUES(v_org,v_org_membership,v_farm,v_farm_membership,v_today,
   'work_item',v_work,'Synthetic work today','planned',true,
   '{"projectionAuthority":"work_execution_plans","synthetic":true}'::jsonb)
 RETURNING id INTO v_today_projection;
 INSERT INTO atlas.worker_week_projection_sources(
   projection_id,work_item_id,source_role)
 VALUES(v_today_projection,v_work,'required');
 INSERT INTO atlas.worker_week_projection(
    organization_id,organization_membership_id,farm_id,membership_id,
    planned_date,source_kind,source_id,title,plan_state,locked,delivery_payload)
 VALUES(v_org,v_org_membership,v_farm,v_farm_membership,v_today+1,
   'work_item',v_work,'Synthetic work tomorrow','planned',true,
   '{"projectionAuthority":"work_execution_plans","synthetic":true}'::jsonb)
 RETURNING id INTO v_future_projection;
 INSERT INTO atlas.worker_week_projection_sources(projection_id,work_item_id,source_role)
 VALUES(v_future_projection,v_work,'required');
 PERFORM set_config('atlas.test_worker_case',jsonb_build_object(
   'org',v_org,'work',v_work,'worker',v_worker,
   'workerSession',f->>'seatOnlySession','orgMembership',v_org_membership,
   'farm',v_farm,'farmMembership',v_farm_membership,
   'today',v_today,'todayProjection',v_today_projection,
   'futureProjection',v_future_projection,'policy',v_policy
 )::text,true);
 RAISE NOTICE 'PASS: source-distinct synthetic institutional worker, appointment, active seat, current and future projections, no plan yet';
END
$worker_setup$;

SET LOCAL ROLE service_role;
DO $worker_negative_before_plan$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_context jsonb;v_feed jsonb;v_result jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'worker','role','authenticated','session_id',f->>'workerSession'
 )::text,true);
 v_context:=atlas.organization_employee_worker_context_self_v1(
   (f->>'farm')::uuid,(f->>'farmMembership')::uuid);
 IF (v_context->>'ok')::boolean IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'FAIL: real employee context not established by synthetic identity/seat/appointment/credential: %',v_context;
 END IF;
 v_feed:=atlas.company_work_worker_day_self_api_v1((f->>'today')::date,2);
 IF jsonb_array_length(v_feed->'items')<>2 THEN
   RAISE EXCEPTION 'FAIL: current and future worker projections not visible in bounded employee self read';
 END IF;
 SELECT item->'resultReporting' INTO v_result FROM jsonb_array_elements(v_feed->'items') item
 WHERE (item->>'projectionId')::uuid=(f->>'futureProjection')::uuid;
 IF v_result->>'state'<>'not_current_service_day'
    OR (v_result->>'reportable')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: future projection mislabeled currently reportable: %',v_result;
 END IF;
 RAISE NOTICE 'PASS: service-authorized Worker Day read preserved employee identity, two dates and denied future reporting';
END
$worker_negative_before_plan$;

SET LOCAL ROLE authenticated;
DO $worker_preplan_denial$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'worker','role','authenticated','session_id',f->>'workerSession'
 )::text,true);
 BEGIN
   PERFORM atlas.worker_report_company_work_projection_self_api_v1(
     (f->>'todayProjection')::uuid,'completed',
     'synthetic-unplanned-'||gen_random_uuid()::text,'{}'::jsonb);
   RAISE EXCEPTION 'FAIL: unplanned worker completion succeeded';
 EXCEPTION WHEN sqlstate '23514' THEN NULL; END;

 RAISE NOTICE 'PASS: authenticated employee cannot report from an unplanned projection';
END
$worker_preplan_denial$;

RESET ROLE;
DO $plan_fixture$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_allocation uuid;v_plan uuid;
BEGIN
 SELECT a.id INTO v_allocation FROM atlas.work_allocations a
 WHERE a.work_item_id=(f->>'work')::uuid AND a.state='active'
 AND a.assignee_membership_id=(f->>'orgMembership')::uuid;
 INSERT INTO atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,plan_state,first_planned_service_date,
    planned_service_date,exposure_service_date,metadata)
 VALUES((f->>'org')::uuid,(f->>'work')::uuid,v_allocation,
   (f->>'orgMembership')::uuid,'active',
   (f->>'today')::date,(f->>'today')::date,(f->>'today')::date,
   '{"synthetic":true,"validationOnly":true}'::jsonb)
 RETURNING id INTO v_plan;
 UPDATE atlas.worker_week_projection
 SET delivery_payload=delivery_payload||jsonb_build_object('managerPlanId',v_plan)
 WHERE id=(f->>'todayProjection')::uuid;
 PERFORM set_config('atlas.test_worker_plan',v_plan::text,true);
 RAISE NOTICE 'PASS: separate active management plan established in rollback fixture';
END
$plan_fixture$;

SET LOCAL ROLE authenticated;
DO $owner_current_plan_proof$
DECLARE
 f jsonb:=current_setting('atlas.test_native_work_scope')::jsonb;
 w jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_row jsonb;v_result jsonb;v_person uuid;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'owner','role','authenticated','session_id',f->>'ownerSession'
 )::text,true);
 v_person:=(f->>'memberPerson')::uuid;
 v_result:=atlas.company_work_accountability_native_ledger_self_api_v1(
   (w->>'org')::uuid,(f->>'flower')::uuid,'native_ledger',50,null);
 v_row:=v_result#>'{items,0}';
 IF v_row#>>'{responsibility,assigneePersonId}' IS DISTINCT FROM v_person::text
   OR v_row#>>'{responsibility,personProvenance}'<>'active_allocation_to_membership_institutional_person'
   OR v_row#>>'{planning,planState}'<>'active'
   OR v_row#>>'{workerProjection,state}'<>'legacy_or_unverified_projection_observed'
   OR (v_row#>>'{workerProjection,canonicalProjectionCount}')::int<>0
   OR v_row#>>'{workerProjection,workerViewedReceipt}'<>'not_proven'
   OR v_row#>>'{workerProjection,currentExecutionWarrant}'<>'not_proven_by_projection' THEN
   RAISE EXCEPTION 'FAIL: owner plan, sourced Person and projection non-collapse were not proven: %',v_row;
 END IF;
 RAISE NOTICE 'PASS: owner exact Person resolution and scheduled/projection states agree without claiming viewed receipt or lease';
END
$owner_current_plan_proof$;

SET LOCAL ROLE service_role;
DO $worker_current_feed$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_feed jsonb;v_reporting jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'worker','role','authenticated','session_id',f->>'workerSession'
 )::text,true);
 v_feed:=atlas.company_work_worker_day_self_api_v1((f->>'today')::date,2);
 SELECT item->'resultReporting' INTO v_reporting
 FROM jsonb_array_elements(v_feed->'items') item
 WHERE (item->>'projectionId')::uuid=(f->>'todayProjection')::uuid;
 IF v_reporting->>'state'<>'reportable'
   OR (v_reporting->>'reportable')::boolean IS DISTINCT FROM true
   OR v_reporting->>'workItemId'<>f->>'work' THEN
   RAISE EXCEPTION 'FAIL: governed current plan not reportable in true worker self context: %',v_reporting;
 END IF;
 SELECT item->'resultReporting' INTO v_reporting
 FROM jsonb_array_elements(v_feed->'items') item
 WHERE (item->>'projectionId')::uuid=(f->>'futureProjection')::uuid;
 IF v_reporting->>'state'<>'not_current_service_day' THEN
   RAISE EXCEPTION 'FAIL: future line became currently reportable from a current plan';
 END IF;
 RAISE NOTICE 'PASS: server-authorized worker read: today reportable and future projection not_current_service_day';
END
$worker_current_feed$;

SET LOCAL ROLE authenticated;
DO $worker_current_proof$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_result jsonb;v_blocked_id uuid;v_completed_id uuid;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'worker','role','authenticated','session_id',f->>'workerSession'
 )::text,true);
 BEGIN
   PERFORM atlas.worker_report_company_work_projection_self_api_v1(
     (f->>'futureProjection')::uuid,'completed',
     'synthetic-future-'||gen_random_uuid()::text,'{}'::jsonb);
   RAISE EXCEPTION 'FAIL: future-dated projection used as todays completion';
 EXCEPTION WHEN sqlstate '23514' THEN NULL; END;
 v_result:=atlas.worker_report_company_work_projection_self_api_v1(
    (f->>'todayProjection')::uuid,'blocked',
    'synthetic-blocked-'||gen_random_uuid()::text,
    '{"sourceObservation":"synthetic prerequisite unavailable"}'::jsonb);
 IF v_result->>'state'<>'reported' OR v_result->>'resultKind'<>'blocked'
 OR NULLIF(v_result->>'acceptanceDecision','') IS NOT NULL THEN
   RAISE EXCEPTION 'FAIL: blocked worker report was promoted to accepted completion: %',v_result;
 END IF;
 v_blocked_id:=(v_result->>'resultId')::uuid;
 v_result:=atlas.worker_report_company_work_projection_self_api_v1(
    (f->>'todayProjection')::uuid,'completed',
    'synthetic-completed-'||gen_random_uuid()::text,'{}'::jsonb);
 IF v_result->>'state'<>'reported_and_accepted'
    OR v_result->>'companyWorkState'<>'completed'
    OR v_result->>'acceptanceDecision'<>'accepted' THEN
   RAISE EXCEPTION 'FAIL: worker attestation report did not separately establish accepted completion: %',v_result;
 END IF;
 v_completed_id:=(v_result->>'resultId')::uuid;
 PERFORM set_config('atlas.test_worker_results',jsonb_build_object(
   'blockedResult',v_blocked_id,'completedResult',v_completed_id
 )::text,true);
 RAISE NOTICE 'PASS: future-report denied, worker blocked report preserved unaccepted, current report accepted per explicit result policy';
END
$worker_current_proof$;

DO $owner_after_worker$
DECLARE
 f jsonb:=current_setting('atlas.test_native_work_scope')::jsonb;
 w jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 r jsonb:=current_setting('atlas.test_worker_results')::jsonb;
 v_accountability jsonb;v_row jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'owner','role','authenticated','session_id',f->>'ownerSession'
 )::text,true);
 v_accountability:=atlas.company_work_accountability_native_ledger_self_api_v1(
 (w->>'org')::uuid,(f->>'flower')::uuid,'native_ledger',50,null);
 IF jsonb_array_length(v_accountability->'items')<>1 THEN
   RAISE EXCEPTION 'FAIL: owner lost the source Work identity following worker result';
 END IF;
 v_row:=v_accountability#>'{items,0}';
 IF v_row->>'workState'<>'completed'
  OR v_row#>>'{latestAcceptedResult,resultId}'<>r->>'completedResult'
  OR v_row#>>'{latestAcceptedResult,decision}'<>'accepted'
  OR v_row#>>'{latestAcceptedResult,resultKind}'<>'completed'
  OR (v_row->>'reportedResultCount')::integer<>2
  OR (v_row#>>'{latestWorkerReport,reportsSharingLatestTimestamp}')::integer<>2
  OR (v_row#>>'{latestWorkerReport,exactOrderWithinTimestampProven}')::boolean IS DISTINCT FROM false
  OR (v_accountability#>>'{facts,managerDoesNotImpersonateWorker}')::boolean IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'FAIL: manager view lost accepted consequence or invented chronological report order: %',v_row;
 END IF;
 IF (SELECT count(*) FROM atlas.work_execution_results x
     WHERE x.work_item_id=(w->>'work')::uuid)<>2 THEN
   RAISE EXCEPTION 'FAIL: failed future or pre-plan attempts secretly wrote results';
 END IF;
 RAISE NOTICE 'PASS: manager sees exact institution-owned work, worker source report and separate accepted completion; unauthorized attempts wrote nothing';
END
$owner_after_worker$;

RESET ROLE;

-- SOURCE-GENERATED POSITIVE: a distinct synthetic Work ID follows the
-- EXISTING governed responsibility constructor, manager planning constructor,
-- and worker-projection reconciler. This prevents mistaking hand-authored
-- delivery_payload markers for the real generation path. ROLLBACK only.
RESET ROLE;
DO $source_bridge_setup$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_org uuid:=(f->>'org')::uuid;
 v_member uuid:=(f->>'orgMembership')::uuid;
 v_today date:=(f->>'today')::date;
 v_work2 uuid:=gen_random_uuid();
 v_projection2 uuid;v_plan_result jsonb;v_bridge_count integer;
 v_projection atlas.worker_week_projection%rowtype;
 v_unit uuid;
BEGIN
 SELECT organization_unit_id INTO v_unit
 FROM atlas.farms WHERE id=(f->>'farm')::uuid;
 INSERT INTO atlas.work_items(id,organization_id,organization_unit_id,
   title,work_state,result_contract_key,metadata)
 VALUES(v_work2,v_org,v_unit,'Synthetic reconciler-sourced Company Work','open',
   f->>'policy',
   '{"source":"rollback_only_validation","managerSchedulingAuthority":"work_execution_plans"}'::jsonb);
 PERFORM atlas.set_company_work_responsibility_with_basis_internal_v2(
   v_work2,v_member,v_member,'self_adoption',
   jsonb_build_object('sourceKind','synthetic_rollback_only_validation',
                      'sourceId',v_work2::text),
   'Synthetic established responsibility for bridge acceptance',
   '{"source":"rollback_only_source_validation"}'::jsonb
 );
 -- Legacy/unverified EXISTING worker carrier is independently identifiable;
 -- the reconciler must promote rather than clone Company Work.
 INSERT INTO atlas.worker_week_projection(
   organization_id,organization_membership_id,farm_id,membership_id,
   planned_date,source_kind,source_id,title,plan_state,locked,delivery_payload)
 VALUES(v_org,v_member,(f->>'farm')::uuid,(f->>'farmMembership')::uuid,
   v_today,'work_item',v_work2,'Unverified legacy carrier','planned',false,
   '{"source":"synthetic_unverified_legacy_carrier"}'::jsonb)
 RETURNING id INTO v_projection2;
 INSERT INTO atlas.worker_week_projection_sources(projection_id,work_item_id,source_role)
 VALUES(v_projection2,v_work2,'required');
 v_plan_result:=atlas.set_company_work_execution_plan_internal_v1(
   v_work2,v_today,null,'Synthetic lawfully planned worker day',
   '{"source":"rollback_only_source_generated_bridge_validation"}'::jsonb
 );
 IF v_plan_result->>'state'<>'planned'
    OR v_plan_result->>'workItemId'<>v_work2::text THEN
   RAISE EXCEPTION 'FAIL: source manager-plan command did not establish the Work plan: %',v_plan_result;
 END IF;
 v_bridge_count:=atlas.reconcile_company_work_worker_day_projections_v1(
   (f->>'farm')::uuid,(f->>'farmMembership')::uuid,
   v_org,v_member,v_today,1
 );
 IF v_bridge_count<>1 THEN
   RAISE EXCEPTION 'FAIL: source plan worker projection reconciler expected one canonical line, got %',v_bridge_count;
 END IF;
 SELECT * INTO v_projection FROM atlas.worker_week_projection
 WHERE id=v_projection2;
 IF v_projection.id IS NULL
   OR v_projection.source_id<>v_work2
   OR v_projection.planned_date<>v_today
   OR v_projection.delivery_payload->>'projectionAuthority'<>'work_execution_plans'
   OR v_projection.delivery_payload->>'source'<>'company_work_employee_plan_projection_v1'
   OR (v_projection.delivery_payload->>'canonicalCompanyWorkProjection')::boolean IS DISTINCT FROM true
   OR v_projection.delivery_payload->>'managerPlanId' IS DISTINCT FROM (v_plan_result->>'planId') THEN
   RAISE EXCEPTION 'FAIL: canonical reconciler failed to prove source promotion of same projection identity';
 END IF;
 PERFORM set_config('atlas.test_reconciled_worker_case',jsonb_build_object(
   'work',v_work2,'projection',v_projection2,'plan',v_plan_result->>'planId'
 )::text,true);
 RAISE NOTICE 'PASS: governed source writer planned Work, reconciler promoted exact existing projection and retained Work and worker identities';
END
$source_bridge_setup$;

SET LOCAL ROLE authenticated;
DO $source_bridge_manager_proof$
DECLARE
 f jsonb:=current_setting('atlas.test_native_work_scope')::jsonb;
 b jsonb:=current_setting('atlas.test_reconciled_worker_case')::jsonb;
 w jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 v_read jsonb;v_row jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',f->>'owner','role','authenticated','session_id',f->>'ownerSession'
 )::text,true);
 v_read:=atlas.company_work_accountability_native_ledger_self_api_v1(
   (w->>'org')::uuid,(f->>'flower')::uuid,'organization',50,null);
 SELECT item INTO v_row FROM jsonb_array_elements(v_read->'items') item
 WHERE item->>'workItemId'=b->>'work';
 IF v_row IS NULL
    OR v_row#>>'{workerProjection,state}'<>'governed_plan_projection_observed'
    OR (v_row#>>'{workerProjection,canonicalProjectionCount}')::int<>1
    OR (v_row#>>'{workerProjection,otherRelatedProjectionCount}')::int<>0
    OR v_row#>>'{workerProjection,workerViewedReceipt}'<>'not_proven'
    OR v_row#>>'{nativeLedgerRelevance}'<>'not_established_for_selected_ledger' THEN
   RAISE EXCEPTION 'FAIL: generated current-day projection not exactly sourced, or unrelated Work was silently attributed to selected native Ledger: %',v_row;
 END IF;
 RAISE NOTICE 'PASS: canonical manager read requires reconciler source and exact manager plan ID, without inventing native Ledger attribution or viewing receipt';
END
$source_bridge_manager_proof$;

SET LOCAL ROLE service_role;
DO $source_bridge_worker_feed$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 b jsonb:=current_setting('atlas.test_reconciled_worker_case')::jsonb;
 v_feed jsonb;v_row jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
  'sub',f->>'worker','role','authenticated','session_id',f->>'workerSession'
 )::text,true);
 v_feed:=atlas.company_work_worker_day_self_api_v1((f->>'today')::date,1);
 SELECT item INTO v_row
 FROM jsonb_array_elements(v_feed->'items') item
 WHERE item->>'projectionId'=b->>'projection';
 IF v_row IS NULL OR v_row#>>'{resultReporting,state}'<>'reportable'
   OR v_row#>>'{deliveryPayload,managerPlanId}'<>b->>'plan'
   OR v_row#>>'{resultReporting,workItemId}'<>b->>'work' THEN
   RAISE EXCEPTION 'FAIL: worker self read did not contain source-reconciled current-day line: %',v_row;
 END IF;
 RAISE NOTICE 'PASS: authorized server-backed Worker Day self projection returns source-reconciled plan and reportable current work';
END
$source_bridge_worker_feed$;

SET LOCAL ROLE authenticated;
DO $source_bridge_worker_report$
DECLARE
 f jsonb:=current_setting('atlas.test_worker_case')::jsonb;
 b jsonb:=current_setting('atlas.test_reconciled_worker_case')::jsonb;
 v_result jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
  'sub',f->>'worker','role','authenticated','session_id',f->>'workerSession'
 )::text,true);
 v_result:=atlas.worker_report_company_work_projection_self_api_v1(
   (b->>'projection')::uuid,'blocked',
   'synthetic-reconciled-block-'||gen_random_uuid()::text,
   '{"workerObservation":"synthetic lawful current-day prerequisite is blocked"}'::jsonb
 );
 IF v_result->>'state'<>'reported'
   OR v_result->>'workItemId'<>b->>'work'
   OR v_result->>'resultKind'<>'blocked'
   OR v_result->>'companyWorkState'<>'open'
   OR NULLIF(v_result->>'acceptanceDecision','') IS NOT NULL THEN
   RAISE EXCEPTION 'FAIL: reconciled source projection worker blocked report was promoted or lost: %',v_result;
 END IF;
 RAISE NOTICE 'PASS: authenticated worker reported from real reconciler output; report did not become institutional acceptance';
END
$source_bridge_worker_report$;

RESET ROLE;
ROLLBACK;
