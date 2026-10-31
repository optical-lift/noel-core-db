-- Read-only postconditions for a disposable post-v2 production-schema clone.
DO $check$
DECLARE def text;
BEGIN
 IF to_regprocedure('atlas.accepted_ledger_intake_original_evidence_v1(uuid,uuid,uuid)') IS NULL THEN
   RAISE EXCEPTION 'Accepted same-original evidence predicate missing';
 END IF;
 IF has_function_privilege('authenticated',
   'atlas.accepted_ledger_intake_original_evidence_v1(uuid,uuid,uuid)'::regprocedure,'EXECUTE')
   OR has_function_privilege('anon',
   'atlas.accepted_ledger_intake_original_evidence_v1(uuid,uuid,uuid)'::regprocedure,'EXECUTE')
 THEN RAISE EXCEPTION 'Internal evidence check must not be an application API'; END IF;
 IF to_regprocedure('atlas.review_ledger_work_intake_root_self_api_v2(uuid,text,integer,text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'Required separately released v2 source missing'; END IF;

 SELECT pg_get_functiondef('atlas.accepted_ledger_intake_original_evidence_v1(uuid,uuid,uuid)'::regprocedure) INTO def;
 IF position('accepted_for_ledger' IN def)=0 OR
    position('d.reviewer_principal_id=i.reviewed_by_principal_id' IN def)=0 OR
    position('w.source_object_type=''ledger_work_intake''' IN def)=0 OR
    position('w.work_state=''open''' IN def)=0
 THEN RAISE EXCEPTION 'Root disposition/original evidence proof incomplete'; END IF;

 SELECT pg_get_functiondef('atlas.require_native_original_work_text_owner_v1(uuid,uuid,uuid)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('company_work_native_ledger_owner_self_v1' IN def)=0
 THEN RAISE EXCEPTION 'Original-Work owner edit law not source-gated'; END IF;

 SELECT pg_get_functiondef('atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('company_work_native_ledger_owner_self_v1' IN def)=0 OR
    position('v_scope.accepted_by_person_id' IN def)=0
 THEN RAISE EXCEPTION 'Accepted standing scope path weakened or missing'; END IF;

 IF to_regprocedure('atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'Existing signed native Person consent writer missing'; END IF;
 SELECT pg_get_functiondef(
  'atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('company_work_native_ledger_owner_self_v1' IN def)=0 OR
    position('person_has_native_ledger_connection_v1' IN def)=0
 THEN RAISE EXCEPTION 'Native exact Work proposal is not source-guarded'; END IF;
 SELECT pg_get_functiondef('atlas.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('organization_membership_present_effective_at_v1' IN def)=0
 THEN RAISE EXCEPTION 'Legacy membership-bound offer path must remain guarded'; END IF;
 IF to_regprocedure('public.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid)') IS NULL
 THEN RAISE EXCEPTION 'Signed submitter own-status RPC missing'; END IF;
 IF has_function_privilege('anon',
   'public.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid)'::regprocedure,'EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous must not read authored Work status'; END IF;
 IF NOT has_function_privilege('authenticated',
   'public.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid)'::regprocedure,'EXECUTE')
 THEN RAISE EXCEPTION 'Signed canonical submitter API unavailable'; END IF;
 SELECT pg_get_functiondef(
   'atlas.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid)'::regprocedure) INTO def;
 IF position('i.submitted_by_person_id=who' IN def)=0 OR
    position('person_has_native_ledger_connection_v1' IN def)=0 OR
    position('principal_has_ledger_authority_v1' IN def)=0 OR
    position('notificationDeliveryClaimed' IN def)=0 OR
    position('p_limit NOT BETWEEN 1 AND 100' IN def)=0
 THEN RAISE EXCEPTION 'Author own-status must be exact source-filtered and bounded'; END IF;
END;
$check$;