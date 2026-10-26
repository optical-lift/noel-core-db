DO $proof$ BEGIN
 IF has_function_privilege('anon',
  'public.owner_original_subject_choices_for_work_self_api_v1(uuid,uuid,uuid,integer,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous subject-choice enumeration'; END IF;
 IF has_function_privilege('authenticated',
  'atlas.owner_original_subject_choices_for_work_self_api_v1(uuid,uuid,uuid,integer,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Direct internal subject-choice enumeration'; END IF;
END $proof$;
-- Signed non-governor must be forbidden; no cross-Ledger choices.
