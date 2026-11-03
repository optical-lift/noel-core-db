-- R02 held source-only ACL and delegation proof; no irreversible DML.
DO $r02_post$
DECLARE
 sig text; checks text[]:=ARRAY[
  'atlas.governor_rhythm_care_opportunities_adapter_v1(uuid,uuid,uuid,integer,uuid)',
  'atlas.governor_review_rhythm_opportunities_self_api_v1(uuid,uuid,uuid,integer,uuid)',
  'atlas.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)',
  'public.governor_review_rhythm_opportunities_self_api_v1(uuid,uuid,uuid,integer,uuid)',
  'public.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)'
 ];
BEGIN
 FOREACH sig IN ARRAY checks LOOP
  IF to_regprocedure(sig) IS NULL THEN
   RAISE EXCEPTION 'R02 missing exact source function: %',sig;
  END IF;
 END LOOP;
 FOREACH sig IN ARRAY checks[1:3] LOOP
  IF has_function_privilege('authenticated',sig,'EXECUTE')
     OR has_function_privilege('anon',sig,'EXECUTE') THEN
   RAISE EXCEPTION 'R02 private source callable by client: %',sig;
  END IF;
 END LOOP;
 FOREACH sig IN ARRAY checks[4:5] LOOP
  IF NOT has_function_privilege('authenticated',sig,'EXECUTE')
     OR has_function_privilege('anon',sig,'EXECUTE') THEN
   RAISE EXCEPTION 'R02 public source ACL misconfigured: %',sig;
  END IF;
 END LOOP;
 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.governor_rhythm_care_opportunities_adapter_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure))=0
 OR position('has_current_subject_disclosure_v1' IN
   pg_get_functiondef('atlas.governor_rhythm_care_opportunities_adapter_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure))=0
 OR position('owner_establish_standing_continuing_care_work_self_api_v1' IN
   pg_get_functiondef('atlas.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)'::regprocedure))=0
 THEN RAISE EXCEPTION 'R02 source owner/disclosure/writer delegation missing'; END IF;
END;
$r02_post$;

DO $r02_unsigned$
DECLARE v_sqlstate text;
BEGIN
 BEGIN
   PERFORM public.governor_review_rhythm_opportunities_self_api_v1(
    '00000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000001'::uuid,20,NULL);
 EXCEPTION WHEN OTHERS THEN v_sqlstate:=SQLSTATE;
 END;
 IF v_sqlstate IS DISTINCT FROM '42501' THEN
  RAISE EXCEPTION 'R02 unsigned governor preview did not source deny: %',v_sqlstate;
 END IF;
END;
$r02_unsigned$;
