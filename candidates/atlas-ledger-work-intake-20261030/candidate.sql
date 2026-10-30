-- SOURCE-ONLY candidate. Disposable-clone and genuine signed-person validation first.
-- No new Person, Principal, membership, root grant, individual assignment or Work date.
BEGIN;
CREATE TABLE atlas.ledger_work_intakes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
 work_item_id uuid NOT NULL UNIQUE REFERENCES atlas.work_items(id),
 submitted_by_person_id uuid NOT NULL REFERENCES reality.entities(id),
 source_action_id text NOT NULL CHECK (length(btrim(source_action_id)) BETWEEN 1 AND 128),
 attention_date_proposal date,
 review_state text NOT NULL DEFAULT 'submitted'
   CHECK (review_state IN ('submitted','accepted_for_ledger','needs_details')),
 revision integer NOT NULL DEFAULT 0 CHECK (revision>=0),
 reviewed_by_principal_id uuid REFERENCES atlas.principals(id),
 reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (submitted_by_person_id,source_action_id)
);
CREATE INDEX ledger_work_intakes_root_queue_idx
 ON atlas.ledger_work_intakes(ledger_id,review_state,created_at,id);
ALTER TABLE atlas.ledger_work_intakes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.ledger_work_intakes FROM PUBLIC,anon,authenticated;

CREATE TABLE atlas.ledger_work_intake_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 intake_id uuid NOT NULL REFERENCES atlas.ledger_work_intakes(id),
 reviewer_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 decision text NOT NULL CHECK (decision IN ('accepted_for_ledger','needs_details')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 1000),
 revision integer NOT NULL CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(intake_id,revision)
);
ALTER TABLE atlas.ledger_work_intake_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.ledger_work_intake_decisions FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.submit_ledger_work_self_api_v1(
 p_ledger_id uuid,p_title text,p_attention_date_proposal date,p_source_action_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE who uuid;principal uuid;organization uuid;n integer;
 t text:=nullif(btrim(coalesce(p_title,'')),'');
 action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
 intake atlas.ledger_work_intakes%rowtype;work atlas.work_items%rowtype;
 new_now boolean:=false;stable text;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Signed canonical Person required' USING errcode='42501';END IF;
 who:=atlas.current_person_id_v1();
 principal:=atlas.current_principal_id_v1();
 IF who IS NULL OR principal IS NULL
 THEN RAISE EXCEPTION 'Existing canonical Person and Principal required' USING errcode='42501';END IF;
 IF p_ledger_id IS NULL OR t IS NULL OR length(t)>500
    OR action IS NULL OR length(action)>128
 THEN RAISE EXCEPTION 'Exact Ledger, task text and source action required' USING errcode='22023';END IF;
 IF NOT atlas.principal_has_ledger_authority_v1(principal,p_ledger_id)
 THEN PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);END IF;
 SELECT count(*),(array_agg(lop.organization_id))[1] INTO n,organization
 FROM atlas.ledger_organization_participations lop
 JOIN atlas.ledgers l ON l.id=lop.ledger_id AND l.status='active'
 JOIN ledger.ledgers nl ON nl.id=lop.ledger_id AND nl.ledger_state='active' AND nl.retired_at IS NULL
 WHERE lop.ledger_id=p_ledger_id AND lop.status='active' AND lop.ended_at IS NULL
   AND lop.participation_kind IN ('governing','operating');
 IF n<>1 OR NOT(
    atlas.person_has_native_ledger_connection_v1(organization,p_ledger_id,who)
    OR atlas.principal_has_ledger_authority_v1(principal,p_ledger_id))
 THEN RAISE EXCEPTION 'Not admitted to exact Ledger' USING errcode='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.principal_ledger_authorities a
   JOIN atlas.principals p ON p.id=a.principal_id AND p.status='active'
   WHERE a.ledger_id=p_ledger_id AND a.authority_kind='root_governing' AND a.status='active')
 THEN RAISE EXCEPTION 'Ledger has no active root review' USING errcode='23514';END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_result_contract_policies policy
   WHERE policy.contract_key='ordinary_company_work_worker_attestation_v1'
   AND policy.active AND policy.source_domain='organization'
   AND policy.acceptance_mode='worker_attestation')
 THEN RAISE EXCEPTION 'Original Work contract unavailable' USING errcode='23514';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.ledger.intake:'||who||':'||action,0));
 SELECT * INTO intake FROM atlas.ledger_work_intakes
   WHERE submitted_by_person_id=who AND source_action_id=action FOR UPDATE;
 IF intake.id IS NULL THEN
   new_now:=true;
   stable:='ledger-intake:'||md5(who::text||':'||action);
   intake.id:=gen_random_uuid();
   INSERT INTO atlas.work_items(organization_id,title,work_state,source_object_type,
     source_object_id,created_by_user_id,stable_key,metadata,result_contract_key)
   VALUES(organization,t,'open','ledger_work_intake',intake.id,auth.uid(),stable,
     jsonb_build_object('sourceContract','ledger_work_intake_v1','custody','institutional',
       'unassignedAtIntake',true,'attentionDateIsProposalOnly',true),
     'ordinary_company_work_worker_attestation_v1') RETURNING * INTO work;
   INSERT INTO atlas.company_work_native_ledger_relevance(
     organization_id,work_item_id,ledger_id,evidence_kind,attestation_source_ref,
     attestation_reason,established_by_person_id)
   VALUES(organization,work.id,p_ledger_id,'participant_attested',
     'atlas.work_items:'||work.id::text,
     'A signed canonical Person submitted unassigned Work to the exact Ledger.',who);
   INSERT INTO atlas.company_work_result_contract_bindings_v1(
     organization_id,ledger_id,work_item_id,actor_person_id,actor_membership_id,
     contract_key,reason)
   VALUES(organization,p_ledger_id,work.id,who,NULL,
     'ordinary_company_work_worker_attestation_v1',
     'Original unassigned Ledger Work submitted for root review.');
   INSERT INTO atlas.ledger_work_intakes(id,organization_id,ledger_id,work_item_id,
     submitted_by_person_id,source_action_id,attention_date_proposal)
   VALUES(intake.id,organization,p_ledger_id,work.id,who,action,p_attention_date_proposal)
   RETURNING * INTO intake;
 ELSE
   SELECT * INTO work FROM atlas.work_items WHERE id=intake.work_item_id;
   IF intake.organization_id IS DISTINCT FROM organization
       OR intake.ledger_id IS DISTINCT FROM p_ledger_id
       OR intake.attention_date_proposal IS DISTINCT FROM p_attention_date_proposal
       OR work.title IS DISTINCT FROM t OR work.work_state IS DISTINCT FROM 'open'
   THEN RAISE EXCEPTION 'Source action belongs to different original Work' USING errcode='23505';END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_intake_v1',
   'intakeId',intake.id,'workItemId',work.id,'ledgerId',p_ledger_id,
   'attentionDateProposal',intake.attention_date_proposal,
   'reviewState',intake.review_state,'createdNow',new_now,
   'newPersonCreated',false,'assignedToPerson',false,
   'personDayPlacementEstablished',false,
   'notificationKind','private_ledger_root_inbox');
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.ledger_work_inbox_root_self_api_v1(
 p_ledger_id uuid,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE root_principal uuid;items jsonb;total integer;
BEGIN
 SELECT principal_id INTO root_principal
   FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);
 IF root_principal IS NULL
 THEN RAISE EXCEPTION 'Exact Ledger root required' USING errcode='42501';END IF;
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Page size invalid' USING errcode='22023';END IF;
 SELECT count(*) INTO total FROM atlas.ledger_work_intakes i
 JOIN atlas.work_items w ON w.id=i.work_item_id AND w.work_state='open'
 WHERE i.ledger_id=p_ledger_id AND i.review_state='submitted';
 SELECT coalesce(jsonb_agg(jsonb_build_object('intakeId',x.id,
   'workItemId',x.work_item_id,'title',x.title,'submittedAt',x.created_at,
   'attentionDateProposal',x.attention_date_proposal,'reviewState',x.review_state)
   ORDER BY x.created_at,x.id),'[]'::jsonb) INTO items
 FROM (SELECT i.id,i.work_item_id,i.created_at,i.attention_date_proposal,
   i.review_state,w.title FROM atlas.ledger_work_intakes i
   JOIN atlas.work_items w ON w.id=i.work_item_id AND w.work_state='open'
   WHERE i.ledger_id=p_ledger_id AND i.review_state='submitted'
   ORDER BY i.created_at,i.id LIMIT p_limit) x;
 RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_root_inbox_v1',
   'ledgerId',p_ledger_id,'items',items,'pendingCount',total,
   'isPersonalWorkObligation',false,'notificationDeliveryClaimed',false);
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.ledger_work_submission_status_self_api_v1(p_intake_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE who uuid;intake atlas.ledger_work_intakes%rowtype;work atlas.work_items%rowtype;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Signed Person required' USING errcode='42501';END IF;
 who:=atlas.current_person_id_v1();
 SELECT * INTO intake FROM atlas.ledger_work_intakes i
 WHERE i.id=p_intake_id AND i.submitted_by_person_id=who;
 IF intake.id IS NULL OR NOT(
   atlas.person_has_native_ledger_connection_v1(intake.organization_id,intake.ledger_id,who)
   OR atlas.principal_has_ledger_authority_v1(atlas.current_principal_id_v1(),intake.ledger_id))
 THEN RAISE EXCEPTION 'Original submission undisclosed' USING errcode='42501';END IF;
 SELECT * INTO work FROM atlas.work_items WHERE id=intake.work_item_id;
 RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_submission_status_v1',
   'intakeId',intake.id,'workItemId',work.id,'ledgerId',intake.ledger_id,
   'title',work.title,'reviewState',intake.review_state,
   'attentionDateProposal',intake.attention_date_proposal);
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.decide_ledger_work_intake_root_self_api_v1(
 p_intake_id uuid,p_decision text,p_expected_revision integer,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE intake atlas.ledger_work_intakes%rowtype;root_principal uuid;
 reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF p_decision NOT IN ('accepted_for_ledger','needs_details')
   OR p_expected_revision IS NULL OR reason IS NULL OR length(reason)>1000
 THEN RAISE EXCEPTION 'Unsupported decision, revision or reason' USING errcode='22023';END IF;
 SELECT * INTO intake FROM atlas.ledger_work_intakes WHERE id=p_intake_id FOR UPDATE;
 IF intake.id IS NULL THEN RAISE EXCEPTION 'Intake unavailable' USING errcode='42501';END IF;
 SELECT principal_id INTO root_principal
   FROM atlas.capability_root_authority_context_self_v1(intake.ledger_id);
 IF root_principal IS NULL THEN RAISE EXCEPTION 'Exact root required' USING errcode='42501';END IF;
 IF intake.revision<>p_expected_revision OR intake.review_state NOT IN ('submitted','needs_details')
 THEN RAISE EXCEPTION 'Stale Work review' USING errcode='40001';END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_items w WHERE w.id=intake.work_item_id AND w.work_state='open')
 THEN RAISE EXCEPTION 'Original Work not open' USING errcode='23514';END IF;
 UPDATE atlas.ledger_work_intakes SET review_state=p_decision,
   revision=revision+1,reviewed_by_principal_id=root_principal,
   reviewed_at=now(),updated_at=now() WHERE id=intake.id RETURNING * INTO intake;
 INSERT INTO atlas.ledger_work_intake_decisions(intake_id,reviewer_principal_id,
   decision,reason,revision)
 VALUES(intake.id,root_principal,p_decision,reason,intake.revision);
 RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_intake_decision_v1',
   'intakeId',intake.id,'workItemId',intake.work_item_id,'ledgerId',intake.ledger_id,
   'reviewState',intake.review_state,'revision',intake.revision,
   'personWorkAssignmentCreated',false,'personalTodayChanged',false);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.submit_ledger_work_self_api_v1(uuid,text,date,text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT atlas.submit_ledger_work_self_api_v1($1,$2,$3,$4);
$fn$;
CREATE OR REPLACE FUNCTION public.ledger_work_inbox_root_self_api_v1(uuid,integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT atlas.ledger_work_inbox_root_self_api_v1($1,$2);
$fn$;
CREATE OR REPLACE FUNCTION public.ledger_work_submission_status_self_api_v1(uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT atlas.ledger_work_submission_status_self_api_v1($1);
$fn$;
CREATE OR REPLACE FUNCTION public.decide_ledger_work_intake_root_self_api_v1(uuid,text,integer,text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
 SELECT atlas.decide_ledger_work_intake_root_self_api_v1($1,$2,$3,$4);
$fn$;
REVOKE ALL ON FUNCTION public.submit_ledger_work_self_api_v1(uuid,text,date,text),
 public.ledger_work_inbox_root_self_api_v1(uuid,integer),
 public.ledger_work_submission_status_self_api_v1(uuid),
 public.decide_ledger_work_intake_root_self_api_v1(uuid,text,integer,text),
 atlas.submit_ledger_work_self_api_v1(uuid,text,date,text),
 atlas.ledger_work_inbox_root_self_api_v1(uuid,integer),
 atlas.ledger_work_submission_status_self_api_v1(uuid),
 atlas.decide_ledger_work_intake_root_self_api_v1(uuid,text,integer,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_ledger_work_self_api_v1(uuid,text,date,text),
 public.ledger_work_inbox_root_self_api_v1(uuid,integer),
 public.ledger_work_submission_status_self_api_v1(uuid),
 public.decide_ledger_work_intake_root_self_api_v1(uuid,text,integer,text),
 atlas.submit_ledger_work_self_api_v1(uuid,text,date,text),
 atlas.ledger_work_inbox_root_self_api_v1(uuid,integer),
 atlas.ledger_work_submission_status_self_api_v1(uuid),
 atlas.decide_ledger_work_intake_root_self_api_v1(uuid,text,integer,text)
 TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
