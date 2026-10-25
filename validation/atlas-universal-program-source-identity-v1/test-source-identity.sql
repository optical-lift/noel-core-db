BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
DO $t$
DECLARE p jsonb; q jsonb; first jsonb; replay jsonb; fork jsonb;
 source_set jsonb; entries jsonb;
BEGIN
 source_set:=jsonb_build_array(jsonb_build_object('key','one','title','Synthetic lesson',
  'locator','synthetic:lesson','sha256',repeat('a',64),'disclosure','author_private'));
 p:=jsonb_build_object(
  'contract','personal_program_author_source_v2','title','Synthetic education Program',
  'purpose','Practice a chosen learning outcome.','domain','education',
  'approvalStanding','draft_requires_governed_human_review',
  'sources',source_set,'goals',jsonb_build_array(),
  'reconciliations',jsonb_build_array(),
  'components',jsonb_build_array(jsonb_build_object(
   'key','lesson-a','kind','action','label','Practice a lesson',
   'instructions','Review one short fictional text.','sourceKeys',jsonb_build_array('one'),
   'sourceExcerpt','| Lesson A | Review one text |',
   'function',jsonb_build_object('key','learning-intent',
    'intendedChange','Develop familiarity with a chosen example.',
    'standing','author_intent'),
   'window',jsonb_build_object('kind','unscheduled','start',null,'end',null,
     'timezone',null,'note','No fixed meeting scheduled'),
   'quantities',jsonb_build_array(),'prerequisites',jsonb_build_array(),
   'alternatives',jsonb_build_array(),'optional',false)));
 first:=public.personal_program_author_create_self_api_v2(p,'identity-create-original-001');
 replay:=public.personal_program_author_create_self_api_v2(p,'identity-create-original-001');
 IF first->>'programId'<>replay->>'programId'
 THEN RAISE EXCEPTION 'Exact request retry created duplicate'; END IF;

 -- Edit source set before any author version was approved.
 -- The original source identity must still be discoverable and protected.
 q:=jsonb_set(p,'{sources,0,sha256}',to_jsonb(repeat('b',64)));
 replay:=public.personal_program_author_save_self_api_v2(
  (first->>'programId')::uuid,1,q,'identity-save-with-new-source-001');
 IF replay->>'draftRevision'<>'2'
 THEN RAISE EXCEPTION 'Source-edit revision was not established'; END IF;
 entries:=public.personal_program_author_same_sources_self_api_v1(source_set);
 IF jsonb_array_length(entries->'items')<>1
 THEN RAISE EXCEPTION 'Original source identity lost after unapproved source edit'; END IF;
 entries:=public.personal_program_author_same_sources_self_api_v1(q->'sources');
 IF jsonb_array_length(entries->'items')<>1
 THEN RAISE EXCEPTION 'Edited source identity was not preserved'; END IF;
 BEGIN
  PERFORM public.personal_program_author_create_self_api_v2(p,'identity-create-unwanted-002');
  RAISE EXCEPTION 'Duplicate same source was accepted without explicit distinct decision';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
 q:=jsonb_set(p,'{title}','"Changed display title"'::jsonb);
 BEGIN
  PERFORM public.personal_program_author_create_self_api_v2(q,'identity-create-unwanted-003');
  RAISE EXCEPTION 'Changed display title bypassed source identity';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
 entries:=public.personal_program_author_same_sources_self_api_v1(source_set);
 IF jsonb_array_length(entries->'items')<>1
 THEN RAISE EXCEPTION 'Expected one author-owned Program with matching source'; END IF;
 BEGIN
  PERFORM public.personal_program_author_create_distinct_self_api_v1(p,
   'identity-fork-test-001','short');
  RAISE EXCEPTION 'A fork was permitted without accountable author rationale';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 fork:=public.personal_program_author_create_distinct_self_api_v1(
   q,'identity-fork-test-002','A separately scoped learning endeavor is intended.');
 IF fork->>'programId'=first->>'programId'
 THEN RAISE EXCEPTION 'Explicit distinct endeavor reused first Program ID'; END IF;
 -- An ordinary SAVE cannot become an accidental second Program from an
 -- already owned source set; only explicit author fork creates such cases.
 BEGIN
  PERFORM public.personal_program_author_save_self_api_v2(
   (fork->>'programId')::uuid,1,
   jsonb_set(p,'{sources,0,sha256}',to_jsonb(repeat('b',64))),
   'identity-forbidden-overlap-save-001');
  RAISE EXCEPTION 'Overlapping source save was silently permitted';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
 replay:=public.personal_program_author_create_distinct_self_api_v1(
   q,'identity-fork-test-002','A separately scoped learning endeavor is intended.');
 IF replay->>'programId'<>fork->>'programId'
 THEN RAISE EXCEPTION 'Exact fork retry duplicated Program'; END IF;
 entries:=public.personal_program_author_same_sources_self_api_v1(source_set);
 IF jsonb_array_length(entries->'items')<>2
 THEN RAISE EXCEPTION 'Author source lookup did not show original and explicit fork'; END IF;
 BEGIN
  PERFORM public.personal_program_author_create_distinct_self_api_v1(q,
   'identity-fork-test-002','A changed fork rationale should cause a conflict.');
  RAISE EXCEPTION 'Fork audit rationale could be rewritten';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
END;
$t$;
COMMIT;
-- Independently authorized Principal may use identical fictional source.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000202';
DO $t$
DECLARE p jsonb; r jsonb;
BEGIN
 p:=jsonb_build_object(
 'contract','personal_program_author_source_v2','title','Other fictional learning',
 'purpose','Independent author-controlled objective.','domain','education',
 'approvalStanding','draft_requires_governed_human_review',
 'sources',jsonb_build_array(jsonb_build_object(
  'key','one','title','Synthetic lesson','locator','synthetic:lesson',
  'sha256',repeat('a',64),'disclosure','author_private')),
 'goals',jsonb_build_array(),'reconciliations',jsonb_build_array(),
 'components',jsonb_build_array(jsonb_build_object(
  'key','lesson-a','kind','action','label','Another lesson',
  'instructions','Review a fictional example.',
  'sourceKeys',jsonb_build_array('one'),'sourceExcerpt','| Lesson | Review |',
  'function',jsonb_build_object('key','other-intent',
   'intendedChange','Support independent learner familiarity.','standing','author_intent'),
  'window',jsonb_build_object('kind','unscheduled','start',null,'end',null,
   'timezone',null,'note','No scheduled date'),
  'quantities',jsonb_build_array(),'prerequisites',jsonb_build_array(),
  'alternatives',jsonb_build_array(),'optional',false)));
 r:=public.personal_program_author_create_self_api_v2(p,'identity-other-principal-01');
 IF r->>'standing'<>'author_draft'
 THEN RAISE EXCEPTION 'Other author blocked from their own distinct Program'; END IF;
 IF jsonb_array_length((public.personal_program_author_same_sources_self_api_v1(p->'sources'))->'items')<>1
 THEN RAISE EXCEPTION 'Source lookup leaked another Principal identity'; END IF;
END;
$t$;
COMMIT;
