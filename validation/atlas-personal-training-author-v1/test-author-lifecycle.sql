-- Synthetic author and foreign-user exercise of four public Program commands.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
DO $test$
DECLARE
 p jsonb; first jsonb; again jsonb; edited jsonb; approved jsonb;
 approved_again jsonb; latest jsonb; second_version jsonb; program_id uuid;
BEGIN
 p := jsonb_build_object(
  'contract','personal_training_program_author_source_v1',
  'title','Synthetic trail preparation',
  'purpose','Develop controlled movement on steps.',
  'approvalStanding','draft_requires_governed_human_review',
  'sources',jsonb_build_array(
    jsonb_build_object('key','instruction','locator','synthetic:author-instruction',
       'disclosure','recipient_disclosed'),
    jsonb_build_object('key','research','locator','synthetic:unshared-reference',
       'disclosure','author_private')),
  'components',jsonb_build_array(jsonb_build_object(
    'key','A1','kind','session','label','Controlled step practice',
    'instructions','Practice a stable small step.',
    'sourceKeys',jsonb_build_array('instruction'),
    'function',jsonb_build_object('key','downhill_control',
       'intendedChange','Practice controlled lowering.'),
    'alternatives',jsonb_build_array(jsonb_build_object(
      'key','press','instructions','Use a leg press.',
      'relation','partial_author_claim','authorApproved',false,
      'rationale','Force contribution does not establish downhill equivalence.'))))
 );
 first := public.personal_training_author_create_self_api_v1(p,'create-synthetic-001');
 program_id := (first->>'programId')::uuid;
 IF first->>'standing'<>'author_draft' OR first->>'draftRevision'<>'1'
 THEN RAISE EXCEPTION 'Create did not return draft'; END IF;
 again := public.personal_training_author_create_self_api_v1(p,'create-synthetic-001');
 IF again->>'programId'<>first->>'programId'
 THEN RAISE EXCEPTION 'Create not idempotent'; END IF;
 latest := public.personal_training_author_read_self_api_v1(program_id);
 IF latest->'draftPacket' <> p OR jsonb_array_length(latest->'versions')<>0
 THEN RAISE EXCEPTION 'Draft read or no-automatic-review failed'; END IF;
 BEGIN
   PERFORM public.personal_training_author_approve_self_api_v1(program_id,1,repeat('0',64),'approve-synthetic-001');
   RAISE EXCEPTION 'Mismatched digest improperly approved';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 approved := public.personal_training_author_approve_self_api_v1(program_id,1,
   first->>'packetDigest','approve-synthetic-001');
 IF approved->>'versionNumber'<>'1'
 THEN RAISE EXCEPTION 'First version missing'; END IF;
 approved_again := public.personal_training_author_approve_self_api_v1(program_id,1,
   first->>'packetDigest','approve-synthetic-001');
 IF approved_again->>'versionId'<>approved->>'versionId'
 THEN RAISE EXCEPTION 'Approval retry changed version'; END IF;
 edited := public.personal_training_author_save_self_api_v1(program_id,1,
  jsonb_set(p,'{components,0,instructions}','"Practice a controlled small step twice."'::jsonb),
  'edit-synthetic-001');
 IF edited->>'draftRevision'<>'2'
 THEN RAISE EXCEPTION 'Expected revision 2'; END IF;
 latest := public.personal_training_author_read_self_api_v1(program_id);
 IF latest->'versions'->0->'packet'<>p
 THEN RAISE EXCEPTION 'Original version overwritten'; END IF;
 again := public.personal_training_author_create_self_api_v1(p,'create-synthetic-001');
 IF again->>'programId'<>first->>'programId'
 THEN RAISE EXCEPTION 'Create retry lost identity after edit'; END IF;
 BEGIN
  PERFORM public.personal_training_author_save_self_api_v1(program_id,1,p,'edit-synthetic-002');
  RAISE EXCEPTION 'Stale revision accepted';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 second_version := public.personal_training_author_approve_self_api_v1(program_id,2,
  edited->>'packetDigest','approve-synthetic-002');
 IF second_version->>'versionNumber'<>'2'
 THEN RAISE EXCEPTION 'Second version missing'; END IF;
 latest := public.personal_training_author_read_self_api_v1(program_id);
 IF jsonb_array_length(latest->'versions')<>2 OR latest->'versions'->1->'packet'<>p
 THEN RAISE EXCEPTION 'Original version not preserved'; END IF;
 IF latest->'versions'->0->'packet'->'components'->0->'alternatives'->0->>'relation'
  <> 'partial_author_claim'
 THEN RAISE EXCEPTION 'Lost author-claimed relation'; END IF;
 PERFORM set_config('test.program_id',program_id::text,false);
END;
$test$;
COMMIT;

-- Another signed-in Principal must not see or change the author's Program.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000202';
DO $test$
BEGIN
 BEGIN
  PERFORM public.personal_training_author_read_self_api_v1(current_setting('test.program_id')::uuid);
  RAISE EXCEPTION 'Cross-person read succeeded';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_training_author_approve_self_api_v1(
    current_setting('test.program_id')::uuid,1,repeat('0',64),'stranger-approve-001');
  RAISE EXCEPTION 'Cross-person approval succeeded';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
SET LOCAL test.personal_access='locked';
DO $test$
BEGIN
 BEGIN
  PERFORM public.personal_training_author_read_self_api_v1(NULL);
  RAISE EXCEPTION 'Locked access incorrectly read Program';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
COMMIT;

-- Privileged edits must not rewrite approved history.
DO $test$
BEGIN
 BEGIN
  UPDATE atlas.personal_training_program_versions SET approved_packet='{}'::jsonb
   WHERE program_id=current_setting('test.program_id')::uuid;
  RAISE EXCEPTION 'Approved version was mutable';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END;
$test$;
