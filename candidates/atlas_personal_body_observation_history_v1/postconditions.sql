-- Structural checks run only on an authorized disposable production-schema clone.
DO $verify$
DECLARE
  inner_fn regprocedure :=
    to_regprocedure('atlas.personal_body_observation_history_self_api_v1(integer,text,text,text)');
  outer_fn regprocedure :=
    to_regprocedure('public.personal_body_observation_history_self_api_v1(integer,text,text,text)');
  definition text;
BEGIN
  IF inner_fn IS NULL OR outer_fn IS NULL THEN
    RAISE EXCEPTION 'Personal body history RPC is missing';
  END IF;
  IF has_function_privilege('anon',outer_fn::oid,'EXECUTE')
    OR NOT has_function_privilege('authenticated',outer_fn::oid,'EXECUTE')
    OR has_function_privilege('anon',inner_fn::oid,'EXECUTE')
    OR has_function_privilege('authenticated',inner_fn::oid,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Body history function access grants are wrong';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid = inner_fn::oid AND prosecdef AND provolatile = 's'
  ) THEN RAISE EXCEPTION 'Body history reader must be STABLE and guarded'; END IF;
  definition := pg_catalog.pg_get_functiondef(inner_fn);
  IF position('c.scope_kind = ''person''' IN definition) = 0
    OR position('c.scope_id = v_user' IN definition) = 0
    OR position('cap.owner_user_id = v_user' IN definition) = 0
    OR position('cap.principal_id = v_principal' IN definition) = 0
    OR position('c.source_kind = ''personal_reality_claim''' IN definition) = 0
    OR position('c.lifecycle_state IN' IN definition) = 0
    OR position('cap.captured_at AT TIME ZONE p_timezone' IN definition) = 0
    OR position('practice.' IN definition) <> 0
    OR position('INSERT INTO' IN upper(definition)) <> 0
  THEN RAISE EXCEPTION 'Self-only, source/time, or read-only guarantee weakened'; END IF;
END
$verify$;
