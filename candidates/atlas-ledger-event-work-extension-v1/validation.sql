-- Schema assertions only; protects the proposed candidate against
-- accidental PUBLIC grants and mistaken second Work storage.
DO $proof$
BEGIN
 IF to_regclass('atlas.ledger_occurrence_work_actions_v1') IS NULL
  OR to_regclass('atlas.ledger_occurrence_work_attention_v1') IS NULL THEN
  RAISE EXCEPTION 'Source-owned action/attention tables missing';
 END IF;
 IF to_regprocedure('atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)') IS NULL
 OR to_regprocedure('atlas.link_existing_ledger_event_work_self_api_v1(uuid,uuid,uuid,uuid,text)') IS NULL
 OR to_regprocedure('atlas.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text)') IS NULL
 OR to_regprocedure('atlas.direct_ledger_event_work_attention_self_api_v1(uuid,uuid,uuid,uuid,uuid,boolean,text)') IS NULL
 OR to_regprocedure('atlas.my_ledger_event_work_attention_self_api_v1()') IS NULL
 OR to_regprocedure('atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.ledger_occurrence_work_extension_self_api_v1(uuid,uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'Missing shared-work extension API';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='guard_blocked_ledger_occurrence_completion_v1')
 THEN RAISE EXCEPTION 'Blocked Work does not protect source Done RPC'; END IF;
 IF has_table_privilege('authenticated','atlas.ledger_occurrence_work_actions_v1','SELECT')
  OR has_table_privilege('authenticated','atlas.ledger_occurrence_work_attention_v1','SELECT')
  OR has_function_privilege('anon','atlas.my_ledger_event_work_attention_self_api_v1()','EXECUTE')
  OR has_function_privilege('anon','atlas.change_ledger_event_ordinary_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,text)','EXECUTE')
  OR has_function_privilege('authenticated','atlas.assert_ledger_occurrence_work_link_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Direct table/internal or anonymous access leaked'; END IF;
 IF NOT has_function_privilege('authenticated',
  'atlas.my_ledger_event_work_attention_self_api_v1()','EXECUTE')
  OR NOT has_function_privilege('authenticated',
  'atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Personal attention or existing Work contract missing'; END IF;
 IF (SELECT count(*) FROM information_schema.columns
  WHERE table_schema='atlas' AND table_name='ledger_occurrence_work_attention_v1'
   AND column_name='person_entity_id')<>1
 THEN RAISE EXCEPTION 'Personal attention not connected to canonical Person'; END IF;
END
$proof$;
