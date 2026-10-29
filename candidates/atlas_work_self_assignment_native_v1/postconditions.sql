-- Post-release candidate structural assertions for disposable production-shaped schema.
-- These assertions do not substitute for genuine GoTrue/PostgREST signed positive and negative cases.
DO $postconditions$
DECLARE
  v_choice oid := to_regprocedure('atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)');
  v_assign oid := to_regprocedure('atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)');
  v_choices text;
  v_assignment text;
BEGIN
 IF v_choice IS NULL OR v_assign IS NULL THEN
   RAISE EXCEPTION 'Existing Work source signatures missing' USING ERRCODE='23514';
 END IF;
 v_choices := pg_get_functiondef(v_choice);
 v_assignment := pg_get_functiondef(v_assign);
 IF strpos(v_choices,'e.id<>v_self')>0
    OR strpos(v_assignment,'v_owner=p_target_person_id')>0 THEN
   RAISE EXCEPTION 'Source still excludes authenticated Person from governed assignment' USING ERRCODE='23514';
 END IF;
 IF strpos(v_choices,'atlas.current_active_ledger_seat_v1')=0
    OR strpos(v_choices,'s.seat_state=''active''')=0
    OR strpos(v_choices,'connected_ledger_person_choices_self_api_v1')=0
    OR strpos(v_assignment,'atlas.company_work_native_ledger_owner_self_v1')=0
    OR strpos(v_assignment,'atlas.person_has_native_ledger_connection_v1')=0
    OR strpos(v_assignment,'v_work.source_object_type<>''work_decomposition''')=0
    OR strpos(v_assignment,'Another live responsibility or decision exists')=0 THEN
   RAISE EXCEPTION 'Native identity, Work scope, or pre-existing allocation authority weakened' USING ERRCODE='23514';
 END IF;
 IF NOT (SELECT prosecdef AND provolatile='s' FROM pg_proc WHERE oid=v_choice)
    OR NOT (SELECT prosecdef AND provolatile='v' FROM pg_proc WHERE oid=v_assign) THEN
   RAISE EXCEPTION 'Original security context or volatility changed' USING ERRCODE='23514';
 END IF;
END;
$postconditions$;
