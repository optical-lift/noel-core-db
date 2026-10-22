-- Run on disposable production-schema clone, NOT on production as a test writer.
DO $check$
DECLARE
  inner_fn regprocedure :=
    to_regprocedure('atlas.connection_inspection_self_api_v1(text,uuid)');
  outer_fn regprocedure :=
    to_regprocedure('public.connection_inspection_self_api_v1(text,uuid)');
  definition text;
  denied boolean := false;
BEGIN
  IF inner_fn IS NULL OR outer_fn IS NULL THEN
    RAISE EXCEPTION 'Universal connection reader not installed';
  END IF;
  IF has_function_privilege('anon',outer_fn::oid,'EXECUTE')
    OR NOT has_function_privilege('authenticated',outer_fn::oid,'EXECUTE')
    OR has_function_privilege('anon',inner_fn::oid,'EXECUTE')
    OR has_function_privilege('authenticated',inner_fn::oid,'EXECUTE')
  THEN RAISE EXCEPTION 'Connection reader grants fail'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid=inner_fn::oid AND prosecdef AND provolatile='s'
  ) THEN RAISE EXCEPTION 'Private reader must be guarded and stable'; END IF;
  definition := pg_catalog.pg_get_functiondef(inner_fn);
  IF position('atlas.reality_access_self_api_v1()' IN definition)=0
    OR position('s.person_entity_id=v_person' IN definition)=0
    OR position('sa.person_entity_id=v_person' IN definition)=0
    OR position('sb.person_entity_id=v_person' IN definition)=0
    OR position('r.subject_entity_id=v_person OR r.object_entity_id=v_person' IN definition)=0
    OR position('recordAccessNotGranted' IN definition)=0
    OR position('INSERT INTO' IN pg_catalog.upper(definition))<>0
    OR position('UPDATE ' IN pg_catalog.upper(definition))<>0
    OR position('DELETE FROM' IN pg_catalog.upper(definition))<>0
  THEN RAISE EXCEPTION 'Read-only or source authorization boundary weakened'; END IF;

  -- Sessionless call must not expose data. This is a structural negative
  -- test, not a substitute for two real authenticated accounts.
  BEGIN
    PERFORM public.connection_inspection_self_api_v1(
      'ledger_person_seat','11111111-1111-4111-8111-111111111111'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'Sessionless inspection was not denied';
  END IF;
END
$check$;
