-- Read-only postconditions for production-shaped disposable clone.
DO $proof$
DECLARE n text; v_src text;
BEGIN
 FOR n IN SELECT unnest(ARRAY['farm_continuity_audit_v2','bed_components_state_v1','farm_continuity_audit_v1','farm_continuity_audit_v3','grow_room_state_v1','mowing_rhythm_dashboard_v1','weeding_cycle_v1','weeding_rhythm_pilot_v1','walkway_cards_v1','tending_board_v1','real_operation_explanation_v1','weed_card_task_focus_v1']) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='atlas' AND p.proname=n LIMIT 1;
  IF v_src IS NULL OR
     position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(' in v_src)=0
  THEN RAISE EXCEPTION 'Unprotected legacy full farm reader %',n;END IF;
 END LOOP;
END $proof$;
-- Required independently signed negative tests:
-- old farm_hand, manager, former worker, unconnected Person, anon:
-- each reader denies before returning object existence/count/metadata.
-- current native Ledger governor may still inspect full farm information.
-- task-scoped worker access instead goes through exact approved original
-- Work, Subject and per-Person field disclosure with signed session.
