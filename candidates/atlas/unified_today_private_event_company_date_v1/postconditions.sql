-- Held read-only postconditions for the P0 source candidate.
-- Run against an EPHEMERAL production-schema clone after candidate.sql.
DO $verify_atlas_today_p0$
DECLARE
 v_index text;
 v_event_actor text;
 v_date_evidence text;
 v_attention text;
 v_schedule text;
 v_event_grant text;
 v_constraint text;
BEGIN
 SELECT pg_get_functiondef('atlas.ledger_occurrence_shared_index_self_api_v1(uuid)'::regprocedure)
   INTO v_index;
 SELECT pg_get_functiondef('atlas.ledger_occurrence_shared_work_actor_self_v1(uuid,uuid,uuid)'::regprocedure)
   INTO v_event_actor;
 SELECT pg_get_functiondef('atlas.ledger_occurrence_date_evidence_self_api_v1(uuid,date,date,text,integer)'::regprocedure)
   INTO v_date_evidence;
 SELECT pg_get_functiondef('atlas.my_ledger_event_work_attention_self_api_v1()'::regprocedure)
   INTO v_attention;
 SELECT pg_get_functiondef('atlas.connected_person_place_work_self_api_v1(uuid,date,text)'::regprocedure)
   INTO v_schedule;
 SELECT pg_get_functiondef('atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)'::regprocedure)
   INTO v_event_grant;
 SELECT pg_get_constraintdef(c.oid) INTO v_constraint
 FROM pg_constraint c WHERE c.conrelid='atlas.subject_disclosure_decision_events_v1'::regclass
   AND c.conname='subject_disclosure_supported_subject_v1';
 IF v_index IS NULL OR position('has_current_subject_disclosure_v1' IN v_index)=0
     OR position('v_is_root' IN v_index)=0
     OR position('when v_is_root' IN lower(v_index))=0 THEN
   RAISE EXCEPTION 'Signed Event index still exposes private Event identity/counts';
 END IF;
 IF v_event_actor IS NULL OR position('has_current_subject_disclosure_v1' IN v_event_actor)=0
     OR position('42501' IN v_event_actor)=0 THEN
   RAISE EXCEPTION 'Event detail source fails to require exact disclosure';
 END IF;
 IF v_date_evidence IS NULL OR position('has_current_subject_disclosure_v1' IN v_date_evidence)=0
     OR v_attention IS NULL OR position('has_current_subject_disclosure_v1' IN v_attention)=0 THEN
   RAISE EXCEPTION 'Alternate occurrence/title reader not covered';
 END IF;
 IF v_schedule IS NULL
     OR position('company_work_native_ledger_owner_self_v1(v_w.organization_id,v_ledger)' IN v_schedule)=0
     OR position('work_execution_plan_events' IN v_schedule)=0 THEN
   RAISE EXCEPTION 'Existing Work plan writer still permits non-governor Person';
 END IF;
 IF v_event_grant IS NULL OR position('p_subject_domain=''event''' IN v_event_grant)=0
     OR position('occurrence_calendar_bindings' IN v_event_grant)=0
     OR position('company_work_native_ledger_owner_self_v1' IN v_event_grant)=0 THEN
   RAISE EXCEPTION 'Original Event disclosure does not require source-bound governor intent';
 END IF;
 IF v_constraint IS NULL OR position('event' IN v_constraint)=0
     OR position('occurrence' IN v_constraint)=0 THEN
   RAISE EXCEPTION 'Original Subject disclosure decision table cannot hold exact Event identity';
 END IF;
 IF has_function_privilege('anon','atlas.ledger_occurrence_shared_index_self_api_v1(uuid)','EXECUTE')
     OR has_function_privilege('anon','atlas.connected_person_place_work_self_api_v1(uuid,date,text)','EXECUTE') THEN
   RAISE EXCEPTION 'Anonymous signed Event or plan endpoints must remain closed';
 END IF;
END $verify_atlas_today_p0$;
