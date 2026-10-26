-- Disposable-clone only, synthetic Program. Never run against production.
-- This is functional contract coverage, NOT genuine independent GoTrue tokens.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='61000000-0000-4000-8000-000000000001';
DO $test$
DECLARE
 v_source jsonb; v_created jsonb; v_approved jsonb; v_read jsonb;
 v_note jsonb; v_replay jsonb; v_revised jsonb; v_notes jsonb;
 v_program uuid; v_version uuid; v_note_id uuid;
 v_version_count integer;
BEGIN
 PERFORM atlas.begin_personal_atlas_self_api_v1('Synthetic program notebook author','America/Chicago');
 v_source := jsonb_build_object(
  'contract','personal_program_author_source_v2',
  'title','Synthetic reading plan','purpose','Prepare source-intended reading.',
  'domain','independent_learning','approvalStanding','draft_requires_governed_human_review',
  'sources',jsonb_build_array(jsonb_build_object(
   'key','original','title','Fictional reference','locator','synthetic:nonprivate',
   'sha256',repeat('a',64),'disclosure','author_private')),
  'goals',jsonb_build_array(jsonb_build_object(
   'key','study','label','Review source','successCriterion','Source can be read.',
   'sourceKeys',jsonb_build_array('original'),'quantity',null)),
  'components',jsonb_build_array(jsonb_build_object(
   'key','day-a','kind','action','label','Read original notes',
   'instructions','Walk the same plan with care.',
   'sourceKeys',jsonb_build_array('original'),
   'sourceExcerpt','Walk the same plan with care.',
   'function',jsonb_build_object('key','reading','intendedChange',
    'Prepare an intended reading session.','standing','author_intent'),
   'window',jsonb_build_object('kind','unscheduled','start',null,'end',null,
    'timezone',null,'note','No date selected'),
   'quantities',jsonb_build_array(),'prerequisites',jsonb_build_array(),
   'alternatives',jsonb_build_array(),'optional',false)),
  'reconciliations',jsonb_build_array());
 v_created:=public.personal_program_author_create_self_api_v2(v_source,'synthetic-notes-prog-1');
 v_program:=(v_created->>'programId')::uuid;
 v_approved:=public.personal_program_author_approve_self_api_v2(
  v_program,1,v_created->>'packetDigest','synthetic-notes-approve-1');
 v_read:=public.personal_program_author_read_self_api_v2(v_program);
 v_version:=(v_read#>>'{versions,0,versionId}')::uuid;
 SELECT count(*) INTO v_version_count FROM atlas.personal_training_program_versions
  WHERE program_id=v_program;
 v_note:=public.personal_program_author_note_create_self_api_v1(
  v_program,v_version,'day-a','Walk the same plan',
  'Explain the intended sequencing.','synthetic-note-create-1');
 v_note_id:=(v_note->>'noteId')::uuid;
 v_replay:=public.personal_program_author_note_create_self_api_v1(
  v_program,v_version,'day-a','Walk the same plan',
  'Explain the intended sequencing.','synthetic-note-create-1');
 IF v_replay->>'noteId'<>v_note_id::text OR v_replay->>'replay'<>'true'
 THEN RAISE EXCEPTION 'Annotation create replay failed'; END IF;
 v_revised:=public.personal_program_author_note_revise_self_api_v1(
  v_program,v_note_id,1,'Sequencing explained to the author.','resolved',
  'synthetic-note-revise-1');
 IF v_revised->>'revision'<>'2' THEN RAISE EXCEPTION 'Revision missing'; END IF;
 BEGIN
  PERFORM public.personal_program_author_note_revise_self_api_v1(
   v_program,v_note_id,1,'Stale edit','open','synthetic-note-stale-1');
  RAISE EXCEPTION 'Stale write was accepted';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_create_self_api_v1(
   v_program,v_version,'does-not-exist',null,'Wrong anchor','synthetic-note-invalid-1');
  RAISE EXCEPTION 'Unknown component accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 v_notes:=public.personal_program_author_notes_read_self_api_v1(v_program);
 IF v_notes->>'total'<>'1'
  OR v_notes#>>'{items,0,revision}'<>'2'
  OR v_notes#>>'{items,0,standing}'<>'resolved'
  OR jsonb_array_length(v_notes#>'{items,0,history}')<>2
 THEN RAISE EXCEPTION 'Notes did not persist independent revision history'; END IF;
 SELECT count(*) INTO v_version_count FROM atlas.personal_training_program_versions
  WHERE program_id=v_program;
 IF v_version_count<>1 OR
  (SELECT approved_packet FROM atlas.personal_training_program_versions WHERE id=v_version)<>v_source
 THEN RAISE EXCEPTION 'Note mutated immutable approved Program version'; END IF;
 PERFORM set_config('test.program_note_program',v_program::text,false);
 PERFORM set_config('test.program_note_id',v_note_id::text,false);
END;
$test$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='61000000-0000-4000-8000-000000000002';
DO $test$
DECLARE v_program uuid; v_note uuid;
BEGIN
 PERFORM atlas.begin_personal_atlas_self_api_v1('Synthetic other notebook author','America/Chicago');
 v_program:=current_setting('test.program_note_program')::uuid;
 v_note:=current_setting('test.program_note_id')::uuid;
 BEGIN
  PERFORM public.personal_program_author_notes_read_self_api_v1(v_program);
  RAISE EXCEPTION 'Other signed-in author read private note';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_revise_self_api_v1(
   v_program,v_note,2,'Unauthorized change','open','synthetic-foreign-revise');
  RAISE EXCEPTION 'Other author revised private note';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
ROLLBACK; -- Synthetic A still exists in disposable clone only.
