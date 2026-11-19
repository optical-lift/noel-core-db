-- HELD T5 TEST ONLY: shape and ACL; NOT signed behavior, data retention or release.
DO $post$
DECLARE name text;rel regclass;proc regprocedure;role_name text;
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 THEN RAISE EXCEPTION 'scratch test required';END IF;
 FOREACH name IN ARRAY ARRAY['atlas.teaching_course_composition_revisions',
 'atlas.teaching_course_version_curriculum_snapshots',
 'atlas.teaching_course_private_study_invitations',
 'atlas.teaching_course_private_study_responses',
 'atlas.teaching_course_private_study_terminations',
 'atlas.teaching_course_private_study_unit_decisions',
 'atlas.teaching_course_private_study_answer_revisions',
 'atlas.teaching_course_private_answer_submissions',
 'atlas.teaching_course_private_answer_review_events']
 LOOP
  rel:=to_regclass(name);
  IF rel IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=rel AND c.relrowsecurity)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=rel AND NOT t.tgisinternal AND t.tgenabled='O' AND (t.tgtype::integer & 16)=16 AND (t.tgtype::integer & 8)=8)
  THEN RAISE EXCEPTION 'private immutable source shape missing: %',name;END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
   THEN RAISE EXCEPTION 'direct private table grant: %',name;END IF;
  END LOOP;
 END LOOP;
 FOREACH name IN ARRAY ARRAY['public.shared_teaching_course_composition_read_self_api_v1(uuid)',
 'public.shared_teaching_course_composition_save_self_api_v1(uuid,uuid,integer,jsonb)',
 'public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])',
 'public.shared_teaching_course_curriculum_seal_self_api_v1(uuid,uuid,uuid)',
 'public.shared_teaching_course_curriculum_snapshot_self_api_v1(uuid)',
 'public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz)',
 'public.shared_teaching_private_study_offer_read_self_api_v1(uuid)',
 'public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text)',
 'public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)',
 'public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid)',
 'public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)',
 'public.shared_teaching_private_study_index_self_api_v1(uuid)',
 'public.shared_teaching_private_study_delivery_self_api_v1(uuid)',
 'public.shared_teaching_private_study_prepare_edition_self_api_v1(uuid,uuid,text)',
 'public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid)',
 'public.shared_teaching_private_study_answer_save_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,text)',
 'public.shared_teaching_private_answer_submit_self_api_v1(uuid,uuid,uuid)',
 'public.shared_teaching_private_answer_review_event_self_api_v1(uuid,uuid,text,text)',
 'public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text)',
 'public.shared_teaching_private_answer_review_target_self_api_v1(uuid)',
 'public.shared_teaching_private_answer_review_inbox_self_api_v1(uuid,uuid)',
 'public.shared_teaching_private_answer_question_context_self_api_v1(uuid,text)',
 'public.shared_teaching_private_answer_own_history_self_api_v1(uuid)']
 LOOP
  proc:=to_regprocedure(name);
  IF proc IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=proc AND p.prosecdef
    AND p.proconfig @> ARRAY['search_path=pg_catalog'])
   OR NOT has_function_privilege('authenticated',proc,'EXECUTE')
   OR has_function_privilege('anon',proc,'EXECUTE')
  THEN RAISE EXCEPTION 'signed source surface shape failed: %',name;END IF;
 END LOOP;
END $post$;
