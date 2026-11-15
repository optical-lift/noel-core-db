-- Public-safe structural postconditions for the private Noel Mark photo-review candidate.
-- Run ONLY on the disposable full-schema validation clone after candidate.sql.
-- Never use these checks as a substitute for genuine owner/outsider/anon signed tests.
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  WHERE s.nspname='mark' AND c.relkind='r' AND c.relname IN
   ('photo_component_catalogues','photo_component_proposals',
    'photo_catalogue_admissions','photo_owner_review_events','photo_owner_review_decisions')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF n<>5 THEN RAISE EXCEPTION 'The five private photo evidence tables must have enforced RLS'; END IF;

  SELECT count(*) INTO n
  FROM pg_trigger t JOIN pg_class rel ON rel.oid=t.tgrelid
   JOIN pg_namespace ns ON ns.oid=rel.relnamespace
  WHERE ns.nspname='mark' AND rel.relname IN
   ('photo_component_catalogues','photo_component_proposals',
    'photo_catalogue_admissions','photo_owner_review_events','photo_owner_review_decisions')
    AND NOT t.tgisinternal AND t.tgname LIKE 'photo_%';
  IF n<>11 THEN RAISE EXCEPTION 'Missing append-only, source or complete-event triggers'; END IF;
  SELECT count(*) INTO n
  FROM pg_trigger t JOIN pg_class rel ON rel.oid=t.tgrelid
   JOIN pg_namespace ns ON ns.oid=rel.relnamespace
  WHERE ns.nspname='mark' AND rel.relname='photo_owner_review_events'
    AND t.tgname='photo_review_event_requires_decisions'
    AND t.tgdeferrable AND t.tginitdeferred;
  IF n<>1 THEN RAISE EXCEPTION 'Incomplete owner-review event must be refused at commit'; END IF;

  SELECT count(*) INTO n
  FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='mark' AND p.proname IN
   ('photo_verify_catalogue_source','photo_verify_component_source',
    'photo_verify_catalogue_admission','photo_verify_owner_event',
    'photo_verify_review_rectangle','photo_verify_review_event_complete',
    'photo_deny_evidence_mutation') AND NOT p.prosecdef;
  IF n<>7 THEN RAISE EXCEPTION 'Photo guard functions must not run with definer rights'; END IF;

  IF has_schema_privilege('anon','mark','USAGE') OR
     has_schema_privilege('authenticated','mark','USAGE') OR
     has_schema_privilege('service_role','mark','USAGE') THEN
     RAISE EXCEPTION 'Private mark schema access was broadened';
  END IF;
  IF has_table_privilege('anon','mark.photo_owner_review_decisions','SELECT') OR
     has_table_privilege('authenticated','mark.photo_owner_review_decisions','SELECT') OR
     has_table_privilege('service_role','mark.photo_owner_review_decisions','SELECT') OR
     has_table_privilege('anon','mark.photo_component_proposals','INSERT') OR
     has_table_privilege('authenticated','mark.photo_owner_review_events','INSERT') THEN
     RAISE EXCEPTION 'Unauthenticated or broad application direct table rights detected';
  END IF;
  IF has_table_privilege('anon','mark.photo_owner_current_reviews','SELECT') OR
     has_table_privilege('authenticated','mark.photo_owner_current_reviews','SELECT') THEN
     RAISE EXCEPTION 'Owner review current view must not be publicly readable';
  END IF;

  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  WHERE s.nspname='mark' AND c.relname='photo_owner_current_reviews'
    AND c.relkind='v' AND 'security_invoker=true'=ANY(c.reloptions);
  IF n<>1 THEN RAISE EXCEPTION 'Private current owner review view must be invoker-mode'; END IF;

  -- SQL structural postconditions do NOT verify user-session identity, row
  -- authorization, source rights, actual ink masks or learning quality.
END $$;


-- Synthetic private-custody lifecycle tests, executed ONLY inside disposable
-- production-schema clone. This verifies PostgreSQL data constraints, NOT a
-- genuine signed owner session. Original photographs and user research absent.
DO $$
DECLARE
 c_id uuid := gen_random_uuid();
 e_first bigint;
 e_second bigint;
 n bigint;
 err text;
BEGIN
  -- A wrong SHA cannot be linked to a verified original source.
  BEGIN
   INSERT INTO mark.photo_component_catalogues
    (capture_id,capture_sha256,image_width,image_height,catalogue_digest,algorithm_key,expected_count)
   VALUES (9200000001,repeat('c',64),200,120,repeat('b',64),'synthetic_test_v1',2);
   RAISE EXCEPTION 'Missing expected capture SHA refusal';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Original source capture hash/dimensions mismatch%' THEN
    RAISE EXCEPTION 'Incorrect capture integrity result: %',err;
   END IF;
  END;

  INSERT INTO mark.photo_component_catalogues
   (catalogue_id,capture_id,capture_sha256,image_width,image_height,
    catalogue_digest,algorithm_key,expected_count)
  VALUES (c_id,9200000001,repeat('a',64),200,120,
    repeat('b',64),'synthetic_test_v1',2);
  INSERT INTO mark.photo_component_proposals
   (catalogue_id,component_id,original_x,original_y,original_width,
    original_height,kind,machine_group,feature_version)
  VALUES (c_id,1,10,10,26,52,'SINGLE_COMPONENT_SHAPE_CANDIDATE','T-001','synthetic_v1');

  -- A catalogue cannot be admitted before all source proposals exist.
  BEGIN
   INSERT INTO mark.photo_catalogue_admissions
    (catalogue_id,verified_sha256,verified_digest,verified_count,verified_by,verification_receipt)
   VALUES (c_id,repeat('a',64),repeat('b',64),2,'clone_operator','synthetic_fixture_pass');
   RAISE EXCEPTION 'Missing expected component census refusal';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Original component inventory incomplete%' THEN
    RAISE EXCEPTION 'Incorrect admission census result: %',err;
   END IF;
  END;

  BEGIN
   INSERT INTO mark.photo_component_proposals
    (catalogue_id,component_id,original_x,original_y,original_width,
     original_height,kind,feature_version)
   VALUES (c_id,3,190,10,20,30,'SINGLE_COMPONENT_SHAPE_CANDIDATE','synthetic_v1');
   RAISE EXCEPTION 'Missing source edge refusal';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Original component rectangle outside capture%' THEN
    RAISE EXCEPTION 'Incorrect component bounds result: %',err;
   END IF;
  END;

  INSERT INTO mark.photo_component_proposals
   (catalogue_id,component_id,original_x,original_y,original_width,
    original_height,kind,machine_group,feature_version)
  VALUES (c_id,2,70,20,24,58,'SINGLE_COMPONENT_SHAPE_CANDIDATE','T-001','synthetic_v1');

  INSERT INTO mark.photo_catalogue_admissions
   (catalogue_id,verified_sha256,verified_digest,verified_count,verified_by,verification_receipt)
  VALUES (c_id,repeat('a',64),repeat('b',64),2,'clone_operator','synthetic_fixture_pass');

  -- An admitted machine proposal is immutable even for the clone operator.
  BEGIN
   UPDATE mark.photo_component_proposals SET original_x=12
    WHERE catalogue_id=c_id AND component_id=1;
   RAISE EXCEPTION 'Missing original source immutability';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Immutable photo evidence%' THEN
    RAISE EXCEPTION 'Incorrect source-immutability result: %',err;
   END IF;
  END;

  BEGIN
   INSERT INTO mark.photo_component_proposals
    (catalogue_id,component_id,original_x,original_y,original_width,
     original_height,kind,feature_version)
   VALUES (c_id,3,120,20,20,60,'SINGLE_COMPONENT_SHAPE_CANDIDATE','synthetic_v1');
   RAISE EXCEPTION 'Missing post-admission original catalogue freeze';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Admitted component catalogue is frozen%' THEN
    RAISE EXCEPTION 'Incorrect post-admission result: %',err;
   END IF;
  END;

  -- A naked ASSIGN header cannot commit without an owner decision.
  -- Check the deferred commit-time constraint using a savepoint-like block.
  BEGIN
   INSERT INTO mark.photo_owner_review_events
    (catalogue_id,action,owner_actor_key,verified_auth_receipt_key,
     client_event_id,client_sequence,original_capture_sha256,event_scope)
   VALUES (c_id,'ASSIGN','synthetic_owner','clone_no_auth_session',
    gen_random_uuid(),50,repeat('a',64),'synthetic_empty_review');
   SET CONSTRAINTS ALL IMMEDIATE;
   RAISE EXCEPTION 'Missing required 1-to-600 event-decision count';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%requires 1 to 600 source decisions%' THEN
    RAISE EXCEPTION 'Incorrect event completeness result: %',err;
   END IF;
  END;

  -- First review: owner-adjusted rectangle is evidence, not ink authority.
  INSERT INTO mark.photo_owner_review_events
   (catalogue_id,action,owner_actor_key,verified_auth_receipt_key,
    client_event_id,client_sequence,original_capture_sha256,event_scope)
  VALUES (c_id,'ASSIGN','synthetic_owner','clone_no_auth_session',
   gen_random_uuid(),1,repeat('a',64),'synthetic_first_review')
  RETURNING event_id INTO e_first;
  INSERT INTO mark.photo_owner_review_decisions
   (catalogue_id,event_id,component_id,reviewed_x,reviewed_y,reviewed_width,
    reviewed_height,verdict,family_tag)
  VALUES (c_id,e_first,1,8,9,31,56,'VISUAL_FAMILY','F_SYN');

  BEGIN
   INSERT INTO mark.photo_owner_review_decisions
    (catalogue_id,event_id,component_id,reviewed_x,reviewed_y,
     reviewed_width,reviewed_height,verdict,family_tag)
   VALUES (c_id,e_first,2,196,20,24,50,'UNKNOWN',NULL);
   RAISE EXCEPTION 'Missing owner adjusted rectangle bounds refusal';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Owner review rectangle outside capture%' THEN
    RAISE EXCEPTION 'Incorrect reviewed rectangle result: %',err;
   END IF;
  END;

  BEGIN
   INSERT INTO mark.photo_owner_review_decisions
    (catalogue_id,event_id,component_id,reviewed_x,reviewed_y,
     reviewed_width,reviewed_height,verdict,family_tag,training_authorized)
   VALUES (c_id,e_first,2,70,20,24,58,'UNKNOWN',NULL,true);
   RAISE EXCEPTION 'Missing training authority refusal';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%training_authorized%' THEN
    RAISE EXCEPTION 'Incorrect unauthorized training result: %',err;
   END IF;
  END;

  INSERT INTO mark.photo_owner_review_events
   (catalogue_id,action,owner_actor_key,verified_auth_receipt_key,
    client_event_id,client_sequence,original_capture_sha256,event_scope)
  VALUES (c_id,'ASSIGN','synthetic_owner','clone_no_auth_session',
   gen_random_uuid(),2,repeat('a',64),'synthetic_reclassification')
  RETURNING event_id INTO e_second;
  INSERT INTO mark.photo_owner_review_decisions
   (catalogue_id,event_id,component_id,reviewed_x,reviewed_y,reviewed_width,
    reviewed_height,verdict,family_tag)
  VALUES (c_id,e_second,1,8,9,31,56,'DAMAGE',NULL);

  SELECT count(*) INTO n FROM mark.photo_owner_current_reviews
  WHERE catalogue_id=c_id AND component_id=1 AND verdict='DAMAGE';
  IF n<>1 THEN RAISE EXCEPTION 'Latest synthetic review must be current'; END IF;

  BEGIN
   INSERT INTO mark.photo_owner_review_events
    (catalogue_id,action,owner_actor_key,verified_auth_receipt_key,
     client_event_id,client_sequence,undo_of_event_id,original_capture_sha256,event_scope)
   VALUES (c_id,'UNDO','synthetic_outsider','clone_no_auth_session',
    gen_random_uuid(),1,e_second,repeat('a',64),'synthetic_forbidden_undo');
   RAISE EXCEPTION 'Missing outsider undo rejection';
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
   IF err NOT LIKE '%Undo not authorized for this actor/source%' THEN
    RAISE EXCEPTION 'Incorrect cross-owner undo result: %',err;
   END IF;
  END;

  INSERT INTO mark.photo_owner_review_events
   (catalogue_id,action,owner_actor_key,verified_auth_receipt_key,
    client_event_id,client_sequence,undo_of_event_id,original_capture_sha256,event_scope)
  VALUES (c_id,'UNDO','synthetic_owner','clone_no_auth_session',
   gen_random_uuid(),3,e_second,repeat('a',64),'synthetic_owner_undo');

  SELECT count(*) INTO n FROM mark.photo_owner_current_reviews
  WHERE catalogue_id=c_id AND component_id=1 AND verdict='VISUAL_FAMILY'
    AND family_tag='F_SYN' AND reviewed_width=31 AND reviewed_height=56;
  IF n<>1 THEN RAISE EXCEPTION 'Undo failed to restore earlier owner visual review'; END IF;

  -- Reclassification and UNDO must never mutate existing review history.
  SELECT count(*) INTO n FROM mark.photo_owner_review_events WHERE catalogue_id=c_id;
  IF n<>3 THEN RAISE EXCEPTION 'Append-only owner event history changed unexpectedly'; END IF;
END $$;
