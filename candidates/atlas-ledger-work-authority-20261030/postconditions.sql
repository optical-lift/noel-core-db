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
