-- Security and malformed-source negatives in the isolated fictional fixture.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
DO $test$
DECLARE
 p jsonb; v jsonb; id uuid; d text; prior jsonb;
BEGIN
 p := jsonb_build_object('contract','personal_training_program_author_source_v1',
  'title','Synthetic mechanics program','purpose','Practice controlled lowering.',
  'approvalStanding','draft_requires_governed_human_review',
  'sources',jsonb_build_array(jsonb_build_object('key','s1',
    'locator','synthetic:reference','disclosure','recipient_disclosed')),
  'components',jsonb_build_array(jsonb_build_object(
   'key','c1','kind','session','label','Controlled lowering',
   'instructions','Practice a low step.',
   'sourceKeys',jsonb_build_array('s1'),
   'function',jsonb_build_object('key','lowering','intendedChange','Build controlled lowering.'),
   'alternatives',jsonb_build_array(jsonb_build_object(
    'key','a1','instructions','Use a leg press.','relation','partial_author_claim',
    'authorApproved',false,'rationale','Partial force overlap only.')))));
 -- Missing disclosure is NOT treated as a valid source.
 BEGIN
  PERFORM public.personal_training_author_create_self_api_v1(
   jsonb_set(p,'{sources,0}',(p->'sources'->0)-'disclosure'),'negative-privacy-001');
  RAISE EXCEPTION 'Missing source disclosure was accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 -- Missing relationship classification cannot be interpreted as equivalent.
 BEGIN
  PERFORM public.personal_training_author_create_self_api_v1(
   jsonb_set(p,'{components,0,alternatives,0}',(p->'components'->0->'alternatives'->0)-'relation'),
   'negative-standing-001');
  RAISE EXCEPTION 'Missing alternative standing was accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 -- Client-declared recipient/participant actuals are forbidden at author-source layer.
 BEGIN
  PERFORM public.personal_training_author_create_self_api_v1(
    p || jsonb_build_object('actual',jsonb_build_object('distanceKm',5.2)),'negative-actual-001');
  RAISE EXCEPTION 'Participant actual was admitted into authored source';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 -- Invalid source relations fail rather than create guessed source identity.
 BEGIN
  PERFORM public.personal_training_author_create_self_api_v1(
    jsonb_set(p,'{components,0,sourceKeys}','["missing"]'::jsonb),'negative-key-001');
  RAISE EXCEPTION 'Nonexistent source reference was accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 -- Creation replay with same key and different source is an error, not overwrite.
 v := public.personal_training_author_create_self_api_v1(p,'safe-create-replay-001');
 id := (v->>'programId')::uuid;
 BEGIN
   PERFORM public.personal_training_author_create_self_api_v1(
    jsonb_set(p,'{title}','"Different title"'::jsonb),'safe-create-replay-001');
   RAISE EXCEPTION 'Conflicting create replay was accepted';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
 prior := public.personal_training_author_approve_self_api_v1(
  id,1,v->>'packetDigest','safe-approve-replay-001');
 d := (public.personal_training_author_save_self_api_v1(id,1,
   jsonb_set(p,'{title}','"Revised synthetic mechanics"'::jsonb),'safe-edit-replay-001'))->>'packetDigest';
 BEGIN
  PERFORM public.personal_training_author_approve_self_api_v1(
   id,2,d,'safe-approve-replay-001');
  RAISE EXCEPTION 'Approval request key re-used for different version';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
 -- An exact retry while the returned revision is current is idempotent.
 IF (public.personal_training_author_save_self_api_v1(id,1,
   jsonb_set(p,'{title}','"Revised synthetic mechanics"'::jsonb),'safe-edit-replay-001')
   ->>'draftRevision') <> '2'
 THEN RAISE EXCEPTION 'Current edit replay did not preserve revision'; END IF;
 -- A later edit must not permit an earlier request key to mutate history.
 PERFORM public.personal_training_author_save_self_api_v1(id,2,
   jsonb_set(p,'{title}','"Third synthetic mechanics"'::jsonb),'safe-edit-replay-002');
 BEGIN
  PERFORM public.personal_training_author_save_self_api_v1(id,1,
    jsonb_set(p,'{title}','"Revised synthetic mechanics"'::jsonb),'safe-edit-replay-001');
  RAISE EXCEPTION 'Historic request replay incorrectly claimed latest revision';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 BEGIN
  PERFORM public.personal_training_author_save_self_api_v1(id,3,p,'safe-edit-replay-001');
  RAISE EXCEPTION 'Reused historical edit key with changed content was accepted';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
END;
$test$;
COMMIT;

-- Privileged row edits cannot rewrite idempotent request history.
DO $test$
BEGIN
 BEGIN
  UPDATE atlas.personal_training_program_edit_receipts
    SET packet_digest=repeat('0',64)
    WHERE request_key='safe-edit-replay-001';
  RAISE EXCEPTION 'Historical edit receipt was mutable';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END;
$test$;

-- There is no raw select path for an authenticated person.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
DO $test$
BEGIN
 BEGIN
  EXECUTE 'SELECT count(*) FROM atlas.personal_training_programs';
  RAISE EXCEPTION 'Raw table access incorrectly allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
COMMIT;

-- An anonymous caller lacks execute authority on the public command.
BEGIN;
SET LOCAL ROLE anon;
DO $test$
BEGIN
 BEGIN
  PERFORM public.personal_training_author_read_self_api_v1(NULL);
  RAISE EXCEPTION 'Anonymous author read incorrectly allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
COMMIT;
