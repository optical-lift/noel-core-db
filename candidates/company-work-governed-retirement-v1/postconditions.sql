-- Source-level invariants only. Clone acceptance must exercise actual owner and
-- worker sessions, relation impacts, source task archiving and re-materialization.
DO $verify$
DECLARE v_name text;
BEGIN
 FOREACH v_name IN ARRAY ARRAY[
   'company_work_retirement_review_self_api_v1',
   'retire_company_work_from_active_self_api_v1'
 ] LOOP
   IF NOT EXISTS(
     SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=v_name
       AND NOT p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
   ) THEN RAISE EXCEPTION 'Missing guarded authenticated retirement transport: %',v_name; END IF;
 END LOOP;
 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)'::regprocedure))=0
 OR position('company_work_native_ledger_owner_self_v1' IN
   pg_get_functiondef('atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Root Ledger owner authority required at review and commit'; END IF;
 IF position('work_item_relations' IN
   pg_get_functiondef('atlas.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)'::regprocedure))=0
 OR position('activeSourceRequirementLinksCount' IN
   pg_get_functiondef('atlas.company_work_retirement_review_self_api_v1(uuid,uuid,uuid)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Removal preview must expose links and source ownership'; END IF;
 IF position('p_acknowledge_related_work' IN
   pg_get_functiondef('atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)'::regprocedure))=0
 OR position('organization_management_adjudicate_company_work_api_v1' IN
   pg_get_functiondef('atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)'::regprocedure))=0
 OR position('offer_state=''stale''' IN
   pg_get_functiondef('atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Removal lacks acknowledged impact, governed cancellation or offer cleanup'; END IF;
 IF position('DELETE FROM' IN upper(
   pg_get_functiondef('atlas.retire_company_work_from_active_self_api_v1(uuid,uuid,uuid,text,boolean)'::regprocedure)))>0
 THEN RAISE EXCEPTION 'Retirement must not hard-delete audit or Work history'; END IF;
END
$verify$;
