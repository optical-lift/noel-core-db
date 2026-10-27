-- Assert all eight additional original SECURITY DEFINER readers enforce native governor access before legacy membership.
DO $residual_gate0$
DECLARE v_name text; v_body text;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['farm_day_task_cards_v1','home_task_cards_v2','seed_inventory_dashboard_v1','task_cards_v1','tending_task_context_v1','tending_task_context_v2','worker_day_state_transition_cards_v1','worker_future_day_projection_source_v1']::text[]) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_body FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname=v_name AND p.prosecdef LIMIT 1;
  IF v_body IS NULL OR position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);' IN v_body)=0 THEN
   RAISE EXCEPTION 'Legacy full-farm reader % missing original native-governor source guard',v_name;
  END IF;
 END LOOP;
END;
$residual_gate0$;
