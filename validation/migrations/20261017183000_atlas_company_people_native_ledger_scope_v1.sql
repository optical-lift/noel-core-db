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
    'owner',v_owner,'seatOnly',v_member,'outsider',v_outsider,
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
  v_count integer;v_owner_ledger_seat text;v_unconnected_state text;
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
  RAISE NOTICE 'PASS: seat-only, other Organization, and invalid sessions denied';
END
$accept$;
RESET ROLE;
ROLLBACK;
