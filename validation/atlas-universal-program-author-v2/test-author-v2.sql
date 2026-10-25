-- Isolated fictional proof for the *same* Program storage with two domains.
-- No private source file, real participant, admission, assignment or execution rows.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
DO $test$
DECLARE
 v_source jsonb; v_budget jsonb; v_movement jsonb;
 v_first jsonb; v_replay jsonb; v_saved jsonb; v_v1 jsonb; v_v2 jsonb; v_history jsonb;
 v_id uuid; v_budget_id uuid; v_v1_legacy jsonb; v_legacy_id uuid;
BEGIN
 v_source:=jsonb_build_object(
 'contract','personal_program_author_source_v2',
 'title','Synthetic personal budget','purpose','Maintain an allocation intention.',
 'domain','budget','approvalStanding','draft_requires_governed_human_review',
 'sources',jsonb_build_array(jsonb_build_object(
   'key','budget-doc','title','Fictional budget.md','locator','synthetic:private-budget-reference',
   'sha256',repeat('a',64),'disclosure','author_private')),
 'goals',jsonb_build_array(jsonb_build_object(
   'key','household-allocation','label','Allocate a category',
   'successCriterion','Review allocation without asserting actual spending.',
   'sourceKeys',jsonb_build_array('budget-doc'),
   'quantity',jsonb_build_object('key','planned-allocation',
     'value',350,'unit','USD','comparison','exact','standing','author_intent'))),
 'components',jsonb_build_array(jsonb_build_object(
   'key','allocation-review','kind','action','label','Review planned allocation',
   'instructions','Review available categories and selected budget.',
   'sourceKeys',jsonb_build_array('budget-doc'),
   'sourceExcerpt','| Groceries | $350 | Monthly |',
   'function',jsonb_build_object('key','allocation-review','intendedChange',
     'Assess planned allocation without inventing expenditures.',
     'standing','author_intent'),
   'window',jsonb_build_object('kind','unscheduled','start',null,'end',null,
     'timezone',null,'note','A participant may select the date later'),
   'quantities',jsonb_build_array(jsonb_build_object('key','planned',
      'value',350,'unit','USD','comparison','exact','standing','author_intent')),
   'prerequisites',jsonb_build_array(),
   'alternatives',jsonb_build_array(),
   'optional',false)),
 'reconciliations',jsonb_build_array());
 v_budget:=v_source;
 v_first:=public.personal_program_author_create_self_api_v2(v_budget,'v2-budget-create-001');
 v_budget_id:=(v_first->>'programId')::uuid;
 IF v_first->>'standing'<>'author_draft' OR v_first->>'draftRevision'<>'1'
 THEN RAISE EXCEPTION 'Budget draft was not established'; END IF;
 v_replay:=public.personal_program_author_create_self_api_v2(v_budget,'v2-budget-create-001');
 IF v_replay->>'programId'<>v_first->>'programId'
 THEN RAISE EXCEPTION 'Budget same-source replay duplicated'; END IF;
 v_v1:=public.personal_program_author_approve_self_api_v2(v_budget_id,1,
   v_first->>'packetDigest','v2-budget-approve-001');
 IF v_v1->>'versionNumber'<>'1' OR v_v1->>'standing'<>'author_reviewed'
 THEN RAISE EXCEPTION 'Budget version approval missing'; END IF;
 v_saved:=public.personal_program_author_save_self_api_v2(v_budget_id,1,
   jsonb_set(v_budget,'{components,0,instructions}',
     '"Compare the author-selected categories without inferring actuals."'::jsonb),
   'v2-budget-save-001');
 IF v_saved->>'draftRevision'<>'2'
 THEN RAISE EXCEPTION 'Budget revision did not advance'; END IF;
 v_v2:=public.personal_program_author_approve_self_api_v2(v_budget_id,2,
   v_saved->>'packetDigest','v2-budget-approve-002');
 IF v_v2->>'versionNumber'<>'2'
 THEN RAISE EXCEPTION 'Budget second version approval missing'; END IF;
 v_history:=public.personal_program_author_read_self_api_v2(v_budget_id);
 IF jsonb_array_length(v_history->'versions')<>2
   OR v_history->'versions'->1->'packet'<>v_budget
 THEN RAISE EXCEPTION 'Budget immutable original source lost'; END IF;

 -- A different domain uses the exact same Program writer and tables, not a new gym schema.
 v_movement:=jsonb_set(v_source,'{title}','"Synthetic movement practice"'::jsonb);
 v_movement:=jsonb_set(v_movement,'{domain}','"movement"'::jsonb);
 v_first:=public.personal_program_author_create_self_api_v2(v_movement,'v2-move-create-001');
 v_id:=(v_first->>'programId')::uuid;
 IF v_id=v_budget_id THEN RAISE EXCEPTION 'Independent Program identities collided'; END IF;
 v_history:=public.personal_program_author_read_self_api_v2(NULL);
 IF jsonb_array_length(v_history->'items')<2
 THEN RAISE EXCEPTION 'Author cannot list both domains under one authority'; END IF;

 -- A v2 command cannot silently overwrite the older v1 training source.
 v_v1_legacy:=public.personal_training_author_create_self_api_v1(
  jsonb_build_object('contract','personal_training_program_author_source_v1',
   'title','Fictional legacy training','purpose','Legacy author source v1.',
   'approvalStanding','draft_requires_governed_human_review',
   'sources',jsonb_build_array(jsonb_build_object(
     'key','legacy','locator','synthetic:legacy-source',
     'disclosure','author_private')),
   'components',jsonb_build_array(jsonb_build_object(
     'key','legacy-one','kind','session','label','A legacy activity',
     'instructions','Practice on a stable supported surface.',
     'sourceKeys',jsonb_build_array('legacy'),
     'function',jsonb_build_object('key','legacy-fn',
       'intendedChange','Maintain comfort with supported motion.'),
     'alternatives',jsonb_build_array()))),
  'v2-legacy-create-001');
 v_legacy_id:=(v_v1_legacy->>'programId')::uuid;
 BEGIN
  PERFORM public.personal_program_author_save_self_api_v2(
    v_legacy_id,1,v_movement,'v2-wrong-contract-001');
  RAISE EXCEPTION 'v2 incorrectly overwrote a v1 authored source';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;

 -- No client actuals or private recipient facts in author packet.
 BEGIN
  PERFORM public.personal_program_author_create_self_api_v2(
    v_movement||jsonb_build_object('actual',jsonb_build_object('quantity',2)),
    'v2-false-actual-001');
  RAISE EXCEPTION 'v2 accepted actual participant data';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_create_self_api_v2(
    jsonb_set(v_movement,'{components,0,function,standing}',
      '"observed_mechanism"'::jsonb),'v2-false-mechanism-001');
  RAISE EXCEPTION 'v2 accepted unverified function standing';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 PERFORM set_config('test.v2_budget_id',v_budget_id::text,false);
END;
$test$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000202';
DO $test$
BEGIN
 BEGIN
  PERFORM public.personal_program_author_read_self_api_v2(
    current_setting('test.v2_budget_id')::uuid);
  RAISE EXCEPTION 'Another Principal accessed the budget Program';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_approve_self_api_v2(
   current_setting('test.v2_budget_id')::uuid,2,repeat('a',64),'v2-stranger-approval');
  RAISE EXCEPTION 'Another Principal approved author source';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
COMMIT;
