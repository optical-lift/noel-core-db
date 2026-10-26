DO $proof$
DECLARE n text; src text;
BEGIN
 FOR n IN SELECT unnest(ARRAY['manual_task_context_v1','maintenance_directive_context_v1','resolve_effective_rhythm_rule_v1','task_schedule_v1','tending_bed_v1','weed_selected_crop_turnover_focus_v1','worker_hand_context_v1','worker_day_operational_task_cards_v1']) LOOP
   SELECT pg_get_functiondef(p.oid) INTO src FROM pg_proc p
   JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='atlas' AND p.proname=n LIMIT 1;
   IF src IS NULL OR position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(' in src)=0
   THEN RAISE EXCEPTION 'Legacy broad context read not source-guarded: %',n;END IF;
 END LOOP;
END $proof$;
-- Signed owner, former farm_hand, manager, unconnected Person and anon
-- must be tested for absence of roster/card/crop existence side channels.
-- Old worker-specific paths intentionally do not substitute for a modern
-- canonical Work+Subject+field decision.
