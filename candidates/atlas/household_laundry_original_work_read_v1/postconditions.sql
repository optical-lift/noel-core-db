DO $test$ BEGIN
 IF has_function_privilege('anon',
   'public.household_original_work_focus_self_api_v1(uuid,uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Household Work Focus anonymously accessible'; END IF;
 IF has_function_privilege('anon',
   'public.household_laundry_current_self_api_v1()',
   'EXECUTE') THEN RAISE EXCEPTION 'Private Household notebook anonymous'; END IF;
END $test$;
-- Real owner/member/unlinked/anon identity proofs still required, and Work
-- action completion must never read unrelated Household conditions or links.
