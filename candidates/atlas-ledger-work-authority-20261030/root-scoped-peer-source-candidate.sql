-- SOURCE-ONLY. No production SQL application is authorized by this file.
-- Exact canonical Person -> existing Principal -> exact Ledger authority.
-- Gate with full-schema PG17 clone and signed worker/root/outsider/revoked cases.
BEGIN;
DO $patch$
DECLARE s text; before_anchor text; after_anchor text;
BEGIN
  -- An active Ledger seat alone MUST NOT disclose a personnel directory.
  s:=pg_get_functiondef('atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)'::regprocedure);
  before_anchor:='perform atlas.current_active_ledger_seat_v1(p_ledger_id);';
  after_anchor:=before_anchor||E'\n PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);\n IF NOT FOUND THEN RAISE EXCEPTION ''Exact Ledger governing authority required'' USING errcode=''42501'';END IF;';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP personnel reader source drift';END IF;
  s:=replace(s,before_anchor,after_anchor);
  before_anchor:='''rootAuthorityNotRequired'',true';
  after_anchor:='''rootAuthorityNotRequired'',false';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP personnel receipt drift';END IF;
  EXECUTE replace(s,before_anchor,after_anchor);

  -- A person's day is not a seat-enumeration endpoint. A connected
  -- non-governor can read only their own active Ledger agenda; querying
  -- another Person requires the exact Ledger's current governing root.
  -- This preserves self work while closing guessed-Person membership probes.
  s:=pg_get_functiondef('atlas.connected_ledger_person_agenda_self_api_v1(uuid,uuid,date,integer)'::regprocedure);
  before_anchor:='v_self:=atlas.current_person_id_v1();'||E'\n perform atlas.current_active_ledger_seat_v1(p_ledger_id);';
  after_anchor:='v_self:=atlas.current_person_id_v1();'||E'\n IF p_person_id IS DISTINCT FROM v_self THEN\n  PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);\n  IF NOT FOUND THEN RAISE EXCEPTION ''Exact Ledger root required to read another Person agenda'' USING errcode=''42501'';END IF;\n ELSE\n  PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);\n END IF;';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP Person agenda peer-read source drift';END IF;
  EXECUTE replace(s,before_anchor,after_anchor);

  -- No compulsory Work assignment on mere mutually active connections.
  s:=pg_get_functiondef('atlas.connected_ledger_direct_assign_self_api_v1(uuid,uuid,text,date,text)'::regprocedure);
  before_anchor:='perform atlas.current_active_ledger_seat_v1(p_ledger_id);';
  after_anchor:=before_anchor||E'\n PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);\n IF NOT FOUND THEN RAISE EXCEPTION ''Exact Ledger governing authority required'' USING errcode=''42501'';END IF;';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP direct assignment source drift';END IF;
  EXECUTE replace(s,before_anchor,after_anchor);

  -- No recipient probing through the legacy person-targeted dispatch.
  s:=pg_get_functiondef('atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)'::regprocedure);
  before_anchor:='perform atlas.current_active_ledger_seat_v1(p_ledger_id);';
  after_anchor:=before_anchor||E'\n PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);\n IF NOT FOUND THEN RAISE EXCEPTION ''Exact Ledger governing authority required'' USING errcode=''42501'';END IF;';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP person dispatch source drift';END IF;
  s:=replace(s,before_anchor,after_anchor);
  before_anchor:='''rootAuthorityRequired'',false';
  after_anchor:='''rootAuthorityRequired'',true';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP dispatch receipt source drift';END IF;
  EXECUTE replace(s,before_anchor,after_anchor);

  -- The integrity trigger is also an authority boundary. Guard the specific
  -- establishment basis, never historical allocations by role/general status.
  s:=pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure);
  -- The trigger has three independent sender-Person checks: original Work,
  -- existing Event, and legacy connection-direct. The only source to
  -- restrict here is the legacy connection-direct responsibility path.
  -- Anchor its unique exact-source rejection AFTER structural basis checks;
  -- fail closed if it has changed rather than rewriting other paths.
  before_anchor:='then raise exception ''Connected direct assignment requires exact original Person and Ledger source'' using errcode=''23514'';end if;';
  after_anchor:=before_anchor||E'\n    IF NOT EXISTS (SELECT 1 FROM atlas.capability_root_authority_context_self_v1((v_basis->>''nativeLedgerId'')::uuid))\n    THEN RAISE EXCEPTION ''Exact Ledger root required for connection-direct responsibility'' USING errcode=''42501'';END IF;';
  IF length(s)-length(replace(s,before_anchor,''))<>length(before_anchor)
  THEN RAISE EXCEPTION 'STOP connection-direct allocation-establishment guard source drift';END IF;
  EXECUTE replace(s,before_anchor,after_anchor);
END;
$patch$;
COMMIT;
