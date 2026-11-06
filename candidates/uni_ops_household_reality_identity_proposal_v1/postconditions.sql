-- Run only AFTER candidate.sql on an isolated disposable schema clone.
-- Hard structural + security checks; no source data mutation.
DO $postconditions$
DECLARE
  v_table regclass := to_regclass('atlas.uni_ops_household_reality_identity_proposals_v1');
  v_writer regprocedure := to_regprocedure(
    'atlas.uni_ops_propose_household_reality_identity_internal_v1(uuid,uuid,uuid,uuid,text)');
  v_guard regprocedure := to_regprocedure(
    'atlas.uni_ops_household_reality_proposal_immutable_guard_v1()');
  v_role text;
BEGIN
  IF v_table IS NULL OR v_writer IS NULL OR v_guard IS NULL THEN
    RAISE EXCEPTION 'Candidate table/private functions absent';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid=v_table AND relrowsecurity=true) THEN
    RAISE EXCEPTION 'Source proposal table must have RLS';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid=v_table AND tgisinternal=false
      AND tgname='uni_ops_household_reality_proposal_history_v1'
      AND (tgtype::int & 2)=2 AND (tgtype::int & 8)=8
  ) THEN
    RAISE EXCEPTION 'Append-only update/delete trigger absent';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE oid=v_writer AND prosecdef=true
      AND proconfig @> ARRAY['search_path=']
  ) THEN
    RAISE EXCEPTION 'Private writer definer/search_path shape changed';
  END IF;
  FOR v_role IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
    IF has_function_privilege(v_role,v_writer,'EXECUTE') OR
       has_function_privilege(v_role,v_guard,'EXECUTE') OR
       has_table_privilege(v_role,v_table,'SELECT') OR
       has_table_privilege(v_role,v_table,'INSERT') OR
       has_table_privilege(v_role,v_table,'UPDATE') OR
       has_table_privilege(v_role,v_table,'DELETE') THEN
      RAISE EXCEPTION 'Candidate source unexpectedly public to role %',v_role;
    END IF;
  END LOOP;
  IF has_function_privilege('public',v_writer,'EXECUTE') THEN
    RAISE EXCEPTION 'PUBLIC has EXECUTE on private writer';
  END IF;
END;
$postconditions$;