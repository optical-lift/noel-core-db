-- ACCESS-01 candidate postconditions for an isolated, reviewed schema clone.
-- These structural assertions are NOT a substitute for genuine signed root,
-- Event-only recipient, outsider, revoked or cross-Ledger negative tests.
DO $audit$
DECLARE
 v_name text;
 v_def text;
 v_reg regprocedure;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY[
   'atlas.event_existing_work_choices_self_api_v1(uuid,uuid,uuid,text)',
   'atlas.ledger_event_attention_people_self_api_v1(uuid,uuid,uuid)'
 ]) LOOP
   v_reg := to_regprocedure(v_name);
   IF v_reg IS NULL THEN
     RAISE EXCEPTION 'ACCESS-01 function identity missing';
   END IF;
   SELECT pg_get_functiondef(v_reg) INTO v_def;
   IF position('atlas.ledger_occurrence_shared_work_actor_self_v1' in v_def)=0
      OR position('atlas.capability_root_authority_context_self_v1(p_ledger_id)' in v_def)=0
      OR position('PERFORM 1 FROM atlas.capability_root_authority_context_self_v1' in v_def)=0
      OR position('RAISE EXCEPTION' in v_def)=0
      OR position('SECURITY DEFINER' in v_def)=0
      OR position('SET search_path TO ''''' in v_def)=0
      OR position('PERFORM 1 FROM atlas.capability_root_authority_context_self_v1' in v_def)
         > position('SELECT coalesce(jsonb_agg' in v_def)
   THEN
     RAISE EXCEPTION 'ACCESS-01 guarded source or ordering mismatch';
   END IF;
 END LOOP;
END
$audit$;
