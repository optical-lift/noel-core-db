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
    position('w.work_state=''open''' IN def)=0 OR
    position('rel.attribution_state=''active''' IN def)=0 OR
    position('rel.evidence_kind=''participant_attested''' IN def)=0
 THEN RAISE EXCEPTION 'Root disposition/original evidence proof incomplete'; END IF;

 SELECT pg_get_functiondef('atlas.require_native_original_work_text_owner_v1(uuid,uuid,uuid)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('company_work_native_ledger_owner_self_v1' IN def)=0
 THEN RAISE EXCEPTION 'Original-Work owner edit law not source-gated'; END IF;

 SELECT pg_get_functiondef('atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('company_work_native_ledger_owner_self_v1' IN def)=0 OR
    position('v_scope.accepted_by_person_id' IN def)=0 OR
    position($intake_mandatory$IF v_work.source_object_type='ledger_work_intake'$intake_mandatory$ IN def)=0
 THEN RAISE EXCEPTION 'Accepted standing scope path weakened or missing'; END IF;

 IF to_regprocedure('atlas.respond_native_ledger_standing_scope_self_api_v1(uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'Existing signed native Person consent writer missing'; END IF;
 SELECT pg_get_functiondef(
  'atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('company_work_native_ledger_owner_self_v1' IN def)=0 OR
    position('person_has_native_ledger_connection_v1' IN def)=0 OR
    position($intake_mandatory$IF v_work.source_object_type='ledger_work_intake'$intake_mandatory$ IN def)=0
 THEN RAISE EXCEPTION 'Native exact Work proposal is not source-guarded'; END IF;
 SELECT pg_get_functiondef('atlas.offer_unallocated_company_work_self_api_v1(uuid,uuid,uuid,text)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0 OR
    position('organization_membership_present_effective_at_v1' IN def)=0
 THEN RAISE EXCEPTION 'Legacy membership-bound offer path must remain guarded'; END IF;
 -- The existing allocation guard must itself admit this exact accepted
 -- intake source while continuing to reject misrepresented Event and connected
 -- Person provenance. A writer-only change is insufficient.
 SELECT pg_get_functiondef(
   'atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure)
 INTO def;
 IF position('accepted_ledger_intake_original_direct_assignment_v1' IN def)=0
    OR position('accepted_ledger_intake_original_evidence_v1' IN def)=0
    OR position('governor_exact_existing_original_work' IN def)=0
    OR position('company_work_native_ledger_owner_self_v1' IN def)=0
    OR position('ledger_connected_direct_assignment_v1' IN def)=0
    OR position('original_subject_direct_assignment_v1' IN def)=0
    OR position($intake_mandatory$work.source_object_type IS DISTINCT FROM 'ledger_work_intake'$intake_mandatory$ IN def)=0
    OR position($expected_scope$relevance.evidence_kind='participant_attested'
           and atlas.accepted_ledger_intake_original_evidence_v1($expected_scope$ IN def)=0
 THEN RAISE EXCEPTION 'Exact accepted-original allocation guard missing or older admission law weakened'; END IF;

 -- Both native responsibility models remain independent: direct obligation
 -- is never forced through a consent scope and never duplicates original Work.
 IF to_regprocedure('atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'Existing direct-original Work writer missing'; END IF;
 SELECT pg_get_functiondef(
 'atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)'::regprocedure) INTO def;
 IF position('accepted_ledger_intake_original_evidence_v1' IN def)=0
    OR position('original_work_assignment_actor_self_v1' IN def)=0
    OR position('person_has_native_ledger_connection_v1' IN def)=0
    OR position('v_basis:=''ledger_connection_direct_assignment''' IN def)=0
    OR position('v_basis:=''original_subject_direct_assignment_v1''' IN def)=0
    OR position('p_service_date IS NOT NULL' IN def)=0
    OR position('newWorkCreated' IN def)=0
    OR position('acceptanceQuestionCreated' IN def)=0
 THEN RAISE EXCEPTION 'Lawful direct original Work offer/date distinction weakened'; END IF;

 -- Owner Work collection already takes participant-attested exact evidence
 -- on one UUID; no new personal or intake-only Work store is introduced.
 SELECT pg_get_functiondef(
 'atlas.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)'::regprocedure) INTO def;
 IF position('participant_attested' IN def)=0
    OR position('company_work_native_ledger_owner_self_v1' IN def)=0
    OR position('from atlas.work_items' IN lower(def))=0
    OR position('p_scope<>''native_ledger''' IN def)=0
    OR position('accepted_ledger_intake_original_evidence_v1' IN def)=0
 THEN RAISE EXCEPTION 'Accepted original missing from normal governor Ledger Work'; END IF;

 -- Responsibility never itself authorizes a worker to rewrite Company time.
 SELECT pg_get_functiondef(
 'atlas.connected_person_place_work_self_api_v1(uuid,date,text)'::regprocedure) INTO def;
 IF position('company_work_native_ledger_owner_self_v1' IN def)=0
 THEN RAISE EXCEPTION 'Current governor-only Company schedule boundary missing'; END IF;

 -- A connected Ledger seat alone never publishes private Event identity.
 SELECT pg_get_functiondef('atlas.ledger_occurrence_shared_index_self_api_v1(uuid)'::regprocedure) INTO def;
 IF position('has_current_subject_disclosure_v1' IN def)=0
    OR position('organization_count=1' IN def)=0
 THEN RAISE EXCEPTION 'Event identity source gate missing'; END IF;

 IF to_regprocedure('public.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'Signed owner accepted-original preflight missing'; END IF;
 IF has_function_privilege('anon',
    'public.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid)'::regprocedure,'EXECUTE')
 THEN RAISE EXCEPTION 'Anon cannot inspect accepted original assignment capability'; END IF;
 SELECT pg_get_functiondef(
 'atlas.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid)'::regprocedure) INTO def;
 IF position('company_work_native_ledger_owner_self_v1' IN def)=0
    OR position('accepted_ledger_intake_original_evidence_v1' IN def)=0
    OR position('authorityNotDelegated' IN def)=0
 THEN RAISE EXCEPTION 'Direct assignment preflight must be a signed root decision'; END IF;

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
    position('p_limit NOT BETWEEN 1 AND 100' IN def)=0 OR
    position('JOIN atlas.work_items w' IN def)=0
 THEN RAISE EXCEPTION 'Author own-status must be exact source-filtered and bounded'; END IF;
 IF to_regprocedure(
   'public.ledger_accepted_original_needs_assignment_root_self_api_v1(uuid,integer,uuid)')
   IS NULL THEN RAISE EXCEPTION 'Exact Needs Assignment source wrapper missing'; END IF;
 IF has_function_privilege('anon',
   'public.ledger_accepted_original_needs_assignment_root_self_api_v1(uuid,integer,uuid)'::regprocedure,
   'EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous cannot enumerate accepted unassigned Work'; END IF;
 SELECT pg_get_functiondef(
   'atlas.accepted_ledger_intake_needs_assignment_root_self_api_v1(uuid,integer,uuid)'::regprocedure)
 INTO def;
 IF position('capability_root_authority_context_self_v1' IN def)=0
    OR position('accepted_ledger_intake_original_evidence_v1' IN def)=0
    OR position($source_match$w.source_object_type='ledger_work_intake'$source_match$ IN def)=0
    OR position($not_allocated$a.allocation_role='responsible' AND a.state='active'$not_allocated$ IN def)=0
    OR position('p_after_work_item_id' IN def)=0
    OR position('notificationDeliveryClaimed' IN def)=0
 THEN RAISE EXCEPTION 'Needs Assignment must be root-only, source-filtered and paginated'; END IF;
END;
$check$;

-- R02A structural custody. Real signed lifecycle cases run separately.
DO $delegation_check$
DECLARE relation regclass; item regprocedure; role_name text; def text;
BEGIN
 relation:=to_regclass('atlas.ledger_original_work_assignment_delegation_events_v1');
 IF relation IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class
   WHERE oid=relation AND relrowsecurity AND relforcerowsecurity) THEN
   RAISE EXCEPTION 'Delegation history requires forced RLS';
 END IF;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_table_privilege(role_name,relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
     RAISE EXCEPTION 'Raw delegation history privilege leaked to %',role_name;
   END IF;
 END LOOP;
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid=relation AND NOT tgisinternal
     AND tgfoid='atlas.guard_work_assignment_delegation_history_v1()'::regprocedure)<>2 THEN
   RAISE EXCEPTION 'Row and truncate immutability guards required';
 END IF;
 FOREACH item IN ARRAY ARRAY[
   'atlas.require_work_assignment_delegation_session_v1()'::regprocedure,
   'atlas.work_assignment_delegation_event_effective_v1(uuid)'::regprocedure,
   'atlas.original_work_assignment_actor_self_v1(uuid,uuid)'::regprocedure,
   'atlas.guard_work_assignment_delegation_history_v1()'::regprocedure] LOOP
   FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
     IF has_function_privilege(role_name,item,'EXECUTE') THEN
       RAISE EXCEPTION 'Internal delegation helper exposed: % / %',item,role_name;
     END IF;
   END LOOP;
 END LOOP;
 FOREACH item IN ARRAY ARRAY[
   'atlas.decide_original_work_assignment_delegation_self_api_v1(uuid,uuid,uuid,text,integer,timestamptz,uuid,text)'::regprocedure,
   'public.decide_original_work_assignment_delegation_self_api_v1(uuid,uuid,uuid,text,integer,timestamptz,uuid,text)'::regprocedure,
   'atlas.original_work_assignment_delegation_self_api_v1(uuid,uuid)'::regprocedure,
   'public.original_work_assignment_delegation_self_api_v1(uuid,uuid)'::regprocedure] LOOP
   IF NOT has_function_privilege('authenticated',item,'EXECUTE')
      OR has_function_privilege('anon',item,'EXECUTE')
      OR has_function_privilege('service_role',item,'EXECUTE') THEN
     RAISE EXCEPTION 'Signed delegation membrane ACL invalid: %',item;
   END IF;
   IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=item AND proconfig @> ARRAY['search_path=""']) THEN
     RAISE EXCEPTION 'Delegation membrane requires an empty search path: %',item;
   END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid IN (
   'public.decide_original_work_assignment_delegation_self_api_v1(uuid,uuid,uuid,text,integer,timestamptz,uuid,text)'::regprocedure,
   'public.original_work_assignment_delegation_self_api_v1(uuid,uuid)'::regprocedure) AND prosecdef) THEN
   RAISE EXCEPTION 'Public delegation wrappers must remain invokers';
 END IF;
 SELECT pg_get_functiondef('atlas.work_assignment_delegation_event_effective_v1(uuid)'::regprocedure) INTO def;
 IF position('newer.revision>e.revision' IN def)=0
    OR position('native_root_authority_id' IN def)=0
    OR position('institutional_root_authority_id' IN def)=0
    OR position('person_has_native_ledger_connection_v1' IN def)=0 THEN
   RAISE EXCEPTION 'Delegation must recheck latest decision and current source authority';
 END IF;
 SELECT pg_get_functiondef('atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)'::regprocedure) INTO def;
 IF position('original_work_assignment_actor_self_v1' IN def)=0
    OR position('v_delegated AND p_service_date IS NOT NULL' IN def)=0
    OR position('v_work.source_object_type IS DISTINCT FROM ''ledger_work_intake''' IN def)=0
    OR position('delegationEventId' IN def)=0
    OR position('delegationRevision' IN def)=0
    OR position('senderPersonId' IN def)=0 THEN
   RAISE EXCEPTION 'R02B writer requires exact authority, provenance and no delegated schedule';
 END IF;
 SELECT pg_get_functiondef('atlas.original_work_assignment_actor_self_v1(uuid,uuid)'::regprocedure) INTO def;
 IF position('company_work_native_ledger_owner_self_v1' IN def)=0
    OR position('require_work_assignment_delegation_session_v1' IN def)=0
    OR position('work_assignment_delegation_event_effective_v1' IN def)=0
    OR position('atlas.work_assignment_delegation.scope:' IN def)=0
    OR position('ORDER BY e.revision DESC LIMIT 1' IN def)=0 THEN
   RAISE EXCEPTION 'R02B must serialize and resolve only current exact operation authority';
 END IF;
 SELECT pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure) INTO def;
 IF position('original_work_assignment_actor_self_v1' IN def)=0
    OR position('checked->>''delegationEventId''' IN def)=0
    OR position('checked->>''delegationRevision''' IN def)=0
    OR position('requestedServiceDate' IN def)=0 THEN
   RAISE EXCEPTION 'R02B allocation guard must independently verify exact grant provenance';
 END IF;
 SELECT pg_get_functiondef('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)'::regprocedure) INTO def;
 IF position('original_work_assignment_actor_self_v1' IN def)>0
    OR position('work_assignment_delegation_event_effective_v1' IN def)>0 THEN
   RAISE EXCEPTION 'Shared root authority must not consume this operation grant';
 END IF;
END;
$delegation_check$;

-- R02C: bounded capability read; no changes to the existing root-only read.
DO $preflight_check$
DECLARE item regprocedure; def text;
BEGIN
 FOREACH item IN ARRAY ARRAY[
   'atlas.accepted_ledger_intake_assignment_preflight_self_api_v1(uuid,uuid,uuid,uuid)'::regprocedure,
   'public.accepted_ledger_intake_assignment_preflight_self_api_v1(uuid,uuid,uuid,uuid)'::regprocedure] LOOP
   IF NOT has_function_privilege('authenticated',item,'EXECUTE')
      OR has_function_privilege('anon',item,'EXECUTE')
      OR has_function_privilege('service_role',item,'EXECUTE') THEN
     RAISE EXCEPTION 'Preflight requires authenticated-only entry: %',item;
   END IF;
   IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=item
     AND proconfig @> ARRAY['search_path=""'] AND pronargdefaults=1 AND provolatile='v') THEN
     RAISE EXCEPTION 'Preflight requires safe search path, current authority and optional recipient: %',item;
   END IF;
 END LOOP;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=
   'public.accepted_ledger_intake_assignment_preflight_self_api_v1(uuid,uuid,uuid,uuid)'::regprocedure) THEN
   RAISE EXCEPTION 'Public preflight must remain an invoker';
 END IF;
 SELECT pg_get_functiondef(
   'atlas.accepted_ledger_intake_assignment_preflight_self_api_v1(uuid,uuid,uuid,uuid)'::regprocedure) INTO def;
 IF position('original_work_assignment_actor_self_v1' IN def)=0
    OR position('accepted_ledger_intake_original_evidence_v1' IN def)=0
    OR position('person_has_native_ledger_connection_v1' IN def)=0
    OR position('a.allocation_role=''responsible''' IN def)=0
    OR position('o.offer_state=''offered''' IN def)=0
    OR position('recipientChecked' IN def)=0
    OR position('requiresRevalidationOnAssignment' IN def)=0
    OR position('workPayloadDisclosed' IN def)=0 THEN
   RAISE EXCEPTION 'Preflight must verify exact source, recipient and current assignment availability';
 END IF;
 SELECT pg_get_functiondef(
   'atlas.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid)'::regprocedure) INTO def;
 IF position('company_work_native_ledger_owner_self_v1' IN def)=0
    OR position('authorityNotDelegated' IN def)=0
    OR position('original_work_assignment_actor_self_v1' IN def)>0 THEN
   RAISE EXCEPTION 'Original owner preflight must remain root-only';
 END IF;
 SELECT pg_get_functiondef(
   'atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)'::regprocedure) INTO def;
 IF position('original_work_assignment_actor_self_v1' IN def)=0
    OR position('accepted_ledger_intake_assignment_preflight_self_api_v1' IN def)>0 THEN
   RAISE EXCEPTION 'Writer must revalidate source authority independently of any preflight receipt';
 END IF;
END;
$preflight_check$;
