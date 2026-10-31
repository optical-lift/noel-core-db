-- Postconditions for governed root intake disposition v2; READ ONLY.
DO $check$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.ledger_work_intakes'::regclass
    AND conname='ledger_work_intakes_review_state_check'
    AND pg_get_constraintdef(oid) LIKE '%rejected%')
 THEN RAISE EXCEPTION 'Root intake rejection state missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.ledger_work_intake_decisions'::regclass
    AND conname='ledger_work_intake_decisions_decision_check'
    AND pg_get_constraintdef(oid) LIKE '%rejected%')
 THEN RAISE EXCEPTION 'Root decision rejection history missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_attribute
   WHERE attrelid='atlas.ledger_work_intake_decisions'::regclass
     AND attname='title_before' AND NOT attisdropped)
 THEN RAISE EXCEPTION 'Before-title edit provenance missing';END IF;
 IF to_regprocedure('public.ledger_work_review_queue_root_self_api_v2(uuid,integer)') IS NULL OR
 to_regprocedure('public.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'Root signed intake review endpoints missing';END IF;
 IF has_function_privilege('anon',
   'public.ledger_work_review_queue_root_self_api_v2(uuid,integer)'::regprocedure,
   'EXECUTE') OR
 has_function_privilege('anon',
   'public.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text)'::regprocedure,
   'EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous execution unexpectedly granted';END IF;
 IF NOT has_function_privilege('authenticated',
   'public.ledger_work_review_queue_root_self_api_v2(uuid,integer)'::regprocedure,
   'EXECUTE') OR
 NOT has_function_privilege('authenticated',
   'public.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text)'::regprocedure,
   'EXECUTE')
 THEN RAISE EXCEPTION 'Signed root entrypoint not callable';END IF;
END
$check$;
