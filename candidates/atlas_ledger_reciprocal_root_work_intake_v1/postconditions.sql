-- Source-only postconditions for the protected disposable clone.
-- THESE ARE STRUCTURAL checks; separately prove signed worker/root/revoked denies.
DO $check$
DECLARE s text;
BEGIN
  s:=pg_get_functiondef('atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)'::regprocedure);
  IF position('capability_root_authority_context_self_v1(p_ledger_id)' IN s)=0
    OR position('rootAuthorityNotRequired' IN s)=0
    OR position('''rootAuthorityNotRequired'',false' IN s)=0
  THEN RAISE EXCEPTION 'Personnel disclosure source gate missing';END IF;
  s:=pg_get_functiondef('atlas.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer)'::regprocedure);
  IF position('IF p_person_id IS DISTINCT FROM v_self THEN' IN s)=0
    OR position('capability_root_authority_context_self_v1(p_ledger_id)' IN s)=0
    OR position('PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id)' IN s)=0
  THEN RAISE EXCEPTION 'Another Person agenda must require exact Ledger root';END IF;
  s:=pg_get_functiondef('atlas.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)'::regprocedure);
  IF position('capability_root_authority_context_self_v1(p_ledger_id)' IN s)=0
  THEN RAISE EXCEPTION 'Peer direct assignment gate missing';END IF;
  s:=pg_get_functiondef('atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)'::regprocedure);
  IF position('capability_root_authority_context_self_v1(p_ledger_id)' IN s)=0
  THEN RAISE EXCEPTION 'Person-targeted notice gate missing';END IF;
  s:=pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure);
  IF position('capability_root_authority_context_self_v1((v_basis->>''nativeLedgerId'')::uuid)' IN s)=0
  THEN RAISE EXCEPTION 'Connected responsibility source guard missing';END IF;
  -- The dated public writer must enter the same guarded source writer.
  s:=pg_get_functiondef('atlas.connected_ledger_send_dated_self_api_v1(uuid,uuid,text,text,text,date)'::regprocedure);
  IF position('atlas.connected_ledger_send_self_api_v1(' IN s)=0
  THEN RAISE EXCEPTION 'Dated dispatch bypasses guarded core';END IF;

  s:=pg_get_functiondef('public.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer)'::regprocedure);
  IF position('atlas.connected_ledger_person_agenda_self_api_v1(' IN s)=0
  THEN RAISE EXCEPTION 'Public connected Person agenda facade source drift';END IF;

  -- Verify all exposed facades still delegate rather than implement a
  -- separate unguarded authorization or personnel enumeration path.
  s:=pg_get_functiondef('public.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)'::regprocedure);
  IF position('atlas.connected_ledger_person_choices_self_api_v1(' IN s)=0
  THEN RAISE EXCEPTION 'Public personnel facade source drift';END IF;
  s:=pg_get_functiondef('public.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)'::regprocedure);
  IF position('atlas.connected_ledger_direct_assign_self_api_v1(' IN s)=0
  THEN RAISE EXCEPTION 'Public assignment facade source drift';END IF;
  s:=pg_get_functiondef('public.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)'::regprocedure);
  IF position('atlas.connected_ledger_send_self_api_v1(' IN s)=0
  THEN RAISE EXCEPTION 'Public person-targeted dispatch facade source drift';END IF;
  s:=pg_get_functiondef('public.connected_ledger_send_dated_self_api_v1(uuid,uuid,text,text,text,date)'::regprocedure);
  IF position('atlas.connected_ledger_send_dated_self_api_v1(' IN s)=0
  THEN RAISE EXCEPTION 'Public dated-dispatch facade source drift';END IF;
END;
$check$;
-- STRUCTURAL postconditions only. Signed clone required for authority/privacy.
DO $check$
DECLARE total integer; submit_source text;
BEGIN
 SELECT count(*) INTO total FROM information_schema.tables
 WHERE table_schema='atlas' AND table_name IN
 ('ledger_work_intakes','ledger_work_intake_decisions');
 IF total<>2 THEN RAISE EXCEPTION 'Missing native intake source tables';END IF;
 SELECT count(*) INTO total FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('submit_ledger_work_self_api_v1','ledger_work_inbox_root_self_api_v1',
  'ledger_work_submission_status_self_api_v1','decide_ledger_work_intake_root_self_api_v1');
 IF total<>4 THEN RAISE EXCEPTION 'Native Ledger intake public facades missing';END IF;
 -- PostgREST named-argument routing must match the actual signed caller
 -- payload. A function present in pg_proc but with unnamed arguments yields
 -- PGRST202 instead of executing the source permission gate (not 42501).
 IF NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='submit_ledger_work_self_api_v1'
     AND p.proargnames=ARRAY['p_ledger_id','p_title','p_attention_date_proposal','p_source_action_id']::text[]
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ledger_work_inbox_root_self_api_v1'
     AND p.proargnames=ARRAY['p_ledger_id','p_limit']::text[]
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ledger_work_submission_status_self_api_v1'
     AND p.proargnames=ARRAY['p_intake_id']::text[]
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='decide_ledger_work_intake_root_self_api_v1'
     AND p.proargnames=ARRAY['p_intake_id','p_decision','p_expected_revision','p_reason']::text[]
 ) THEN RAISE EXCEPTION 'Native Ledger intake named RPC arguments mismatch REST caller';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='atlas' AND c.relname='ledger_work_intakes' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'Private intake must be RLS-enabled';END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='atlas' AND c.relname IN ('ledger_work_intakes','ledger_work_intake_decisions')
     AND has_table_privilege('authenticated',c.oid,'SELECT'))
 THEN RAISE EXCEPTION 'No direct employee table access';END IF;
 -- General original Work must not duplicate the submitter's Person identifier,
 -- raw action key, or Ledger identity in freeform metadata. Restricted intake
 -- and exact native Ledger relevance remain the only identity-bearing custody.
 submit_source:=pg_get_functiondef('atlas.submit_ledger_work_self_api_v1(uuid,text,date,text)'::regprocedure);
 IF position('''submittedByPersonId''' IN submit_source)>0
    OR position('''sourceActionId''' IN submit_source)>0
    OR position('''nativeLedgerId''' IN submit_source)>0
 THEN RAISE EXCEPTION 'Sensitive identity copied into original Work metadata';END IF;
END;
$check$;
