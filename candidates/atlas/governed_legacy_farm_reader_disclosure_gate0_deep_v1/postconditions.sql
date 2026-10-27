DO $deep_gate0$
DECLARE
 v_name text;
 v_body text;
 v_found integer;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['object_workbench_v1','farm_continuity_audit_v6','farm_continuity_audit_v7','farm_continuity_audit_v8','crop_cycle_profile_source_state_v1','crop_cycle_stage_continuity_state_v1','crop_cycle_biological_progression_state_v1','crop_cycle_postproduction_state_v1','crop_cycle_lawful_dwell_state_v1','farm_goal_list_v1','flower_sale_buyer_options_v1','home_task_cards_v1','task_plant_contents_v1']::text[]) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_body
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname=v_name
   LIMIT 1;
  IF v_body IS NULL
    OR position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(' IN v_body)=0
    OR position('SECURITY DEFINER' IN v_body)=0 THEN
    RAISE EXCEPTION 'Gate0 additional inherited reader % is not source-guarded',v_name;
  END IF;
 END LOOP;
 SELECT count(*) INTO v_found FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname=ANY(ARRAY['object_workbench_v1','farm_continuity_audit_v6','farm_continuity_audit_v7','farm_continuity_audit_v8','crop_cycle_profile_source_state_v1','crop_cycle_stage_continuity_state_v1','crop_cycle_biological_progression_state_v1','crop_cycle_postproduction_state_v1','crop_cycle_lawful_dwell_state_v1','farm_goal_list_v1','flower_sale_buyer_options_v1','home_task_cards_v1','task_plant_contents_v1']::text[]);
 IF v_found<>13 THEN
   RAISE EXCEPTION 'Gate0 deep source reader coverage incomplete (% of 13)',v_found;
 END IF;
END;
$deep_gate0$;
