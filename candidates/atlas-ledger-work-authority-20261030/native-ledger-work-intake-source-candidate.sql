-- SOURCE-ONLY PROPOSAL. NOT A DEPLOYMENT OR APPROVED MIGRATION.
-- Requires exact full-schema PG17 clone, real signed callers, rollback.
-- Extends the existing atlas.work_items identity, not another Work store.
BEGIN;

CREATE TABLE atlas.ledger_work_intakes_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL UNIQUE REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  submitted_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  source_action_id text NOT NULL,
  attention_date_proposal date,
  review_state text NOT NULL DEFAULT 'submitted'
    CHECK (review_state IN ('submitted','accepted_for_ledger','needs_details','declined','assigned')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (submitted_by_person_id,source_action_id)
);
CREATE INDEX ledger_work_intakes_current_ledger_v1
  ON atlas.ledger_work_intakes_v1(ledger_id,review_state,created_at,id);
ALTER TABLE atlas.ledger_work_intakes_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.ledger_work_intakes_v1 FROM PUBLIC,anon,authenticated;

-- "Queued" is an in-product Ledger inbox event, NOT proof of remote
-- push, email or notification delivery. Exact current root grant rechecked
-- by reader at time of access; event never conveys standing authority.
CREATE TABLE atlas.ledger_work_intake_root_events_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_id uuid NOT NULL REFERENCES atlas.ledger_work_intakes_v1(id) ON DELETE RESTRICT,
  root_authority_id uuid NOT NULL REFERENCES atlas.principal_ledger_authorities(id) ON DELETE RESTRICT,
  event_state text NOT NULL DEFAULT 'queued' CHECK (event_state='queued'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(intake_id,root_authority_id)
);
ALTER TABLE atlas.ledger_work_intake_root_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.ledger_work_intake_root_events_v1 FROM PUBLIC,anon,authenticated;

-- Extend existing canonical SOURCE-VERIFIED Ledger relevance; preserve
-- booking_requests and booking_offerings exactly as they already operate.
DO $source_drift$
DECLARE definition text;
BEGIN
  definition:=pg_get_functiondef(
    'atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)'::regprocedure);
  IF position('ledger.booking_requests' IN definition)=0
     OR position('ledger.booking_offerings' IN definition)=0
     OR position('atlas.ledger_work_intakes_v1' IN definition)>0
  THEN RAISE EXCEPTION 'STOP: exact Ledger source verifier has drifted'; END IF;
END $source_drift$;

ALTER TABLE atlas.company_work_native_ledger_relevance
  DROP CONSTRAINT company_work_relevance_evidence_separation_v1;
ALTER TABLE atlas.company_work_native_ledger_relevance
  ADD CONSTRAINT company_work_relevance_evidence_separation_v1
  CHECK (
    (
      evidence_kind IN ('owner_attested','participant_attested')
      AND nullif(btrim(attestation_source_ref),'') IS NOT NULL
      AND nullif(btrim(attestation_reason),'') IS NOT NULL
      AND source_schema IS NULL AND source_table IS NULL
      AND source_id IS NULL AND verified_at IS NULL
    ) OR (
      evidence_kind='source_verified'
      AND attestation_source_ref IS NULL AND attestation_reason IS NULL
      AND source_id IS NOT NULL AND verified_at IS NOT NULL
      AND (
        (source_schema='ledger' AND source_table IN ('booking_requests','booking_offerings'))
        OR (source_schema='atlas' AND source_table='ledger_work_intakes_v1')
      )
    )
  );

CREATE OR REPLACE FUNCTION atlas.company_work_native_ledger_exact_source_v1(
  p_work_item_id uuid,p_ledger_id uuid
) RETURNS TABLE(source_schema text,source_table text,source_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT 'ledger'::text,'booking_requests'::text,b.id
  FROM atlas.work_items w JOIN ledger.booking_requests b
    ON w.source_object_type='ledger_booking_request'
   AND w.source_object_id=b.id
  WHERE w.id=p_work_item_id AND b.ledger_id=p_ledger_id
  UNION ALL
  SELECT 'ledger'::text,'booking_offerings'::text,o.id
  FROM atlas.work_items w JOIN ledger.booking_offerings o
    ON w.source_object_type='ledger_booking_offering'
   AND w.source_object_id=o.id
  WHERE w.id=p_work_item_id AND o.ledger_id=p_ledger_id
  UNION ALL
  SELECT 'atlas'::text,'ledger_work_intakes_v1'::text,i.id
  FROM atlas.work_items w JOIN atlas.ledger_work_intakes_v1 i
    ON w.source_object_type='ledger_work_submission_v1'
   AND w.source_object_id=i.id AND w.id=i.work_item_id
   AND w.organization_id=i.organization_id
  WHERE w.id=p_work_item_id AND i.ledger_id=p_ledger_id;
$function$;

CREATE FUNCTION atlas.submit_ledger_work_self_api_v1(
  p_ledger_id uuid,p_title text,
  p_attention_date_proposal date,p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_sender uuid;v_title text:=nullif(btrim(coalesce(p_title,'')),'');
  v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_org uuid;v_count integer;v_work uuid;v_intake uuid;
  v_prior atlas.ledger_work_intakes_v1%rowtype;v_prior_title text;
  v_root_events integer;v_key text;
BEGIN
  IF auth.uid() IS NULL OR
    (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
  THEN RAISE EXCEPTION 'Signed canonical Person required' USING ERRCODE='42501';END IF;
  v_sender:=atlas.current_person_id_v1();
  IF v_sender IS NULL OR p_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Ledger submission unavailable' USING ERRCODE='42501'; END IF;
  IF v_title IS NULL OR length(v_title)>500 OR
    v_action IS NULL OR length(v_action)>128 THEN
    RAISE EXCEPTION 'Original title and source action required' USING ERRCODE='22023'; END IF;
  -- Verify current seat, current native ledger, one unambiguous company,
  -- not inherited authority over anyone else's personal Notebook.
  PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
  SELECT count(*),(array_agg(lop.organization_id))[1] INTO v_count,v_org
  FROM atlas.ledger_organization_participations lop
  JOIN atlas.ledgers al ON al.id=lop.ledger_id AND al.status='active'
  JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
    AND nl.ledger_state='active' AND nl.retired_at IS NULL
  WHERE lop.ledger_id=p_ledger_id AND lop.status='active'
    AND lop.ended_at IS NULL AND lop.participation_kind IN ('governing','operating');
  IF v_count<>1 OR NOT atlas.person_has_native_ledger_connection_v1(
    v_org,p_ledger_id,v_sender)
    OR NOT EXISTS(SELECT 1 FROM ledger.seats s
      WHERE s.ledger_id=p_ledger_id AND s.person_entity_id=v_sender
        AND s.seat_state='active' AND s.ended_at IS NULL)
  THEN RAISE EXCEPTION 'Exact current Ledger participation required'
    USING ERRCODE='42501'; END IF;
  v_key:='ledger-work-intake:'||v_sender::text||':'||md5(v_action);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_key,0));
  SELECT * INTO v_prior FROM atlas.ledger_work_intakes_v1 i
  WHERE i.submitted_by_person_id=v_sender AND i.source_action_id=v_action
  FOR UPDATE;
  IF v_prior.id IS NOT NULL THEN
    SELECT w.title INTO v_prior_title FROM atlas.work_items w
      WHERE w.id=v_prior.work_item_id;
    IF v_prior.ledger_id IS DISTINCT FROM p_ledger_id OR
      v_prior_title IS DISTINCT FROM v_title OR
      v_prior.attention_date_proposal IS DISTINCT FROM p_attention_date_proposal
    THEN RAISE EXCEPTION 'Source action replay conflicts with original intake'
      USING ERRCODE='23505'; END IF;
    v_work:=v_prior.work_item_id;v_intake:=v_prior.id;
  ELSE
    v_work:=gen_random_uuid();v_intake:=gen_random_uuid();
    INSERT INTO atlas.work_items(
      id,organization_id,title,work_state,source_object_type,
      source_object_id,created_by_user_id,stable_key,metadata
    ) VALUES(
      v_work,v_org,v_title,'open','ledger_work_submission_v1',
      v_intake,auth.uid(),v_key,
      jsonb_build_object('sourceContract','ledger_work_intake_v1',
        'custody','institutional','submittedByPersonId',v_sender,
        'nativeLedgerId',p_ledger_id,'individualAssigned',false,
        'personDayPlacementEstablished',false,
        'attentionDateIsProposalOnly',true)
    );
    INSERT INTO atlas.ledger_work_intakes_v1(
      id,organization_id,ledger_id,work_item_id,submitted_by_person_id,
      source_action_id,attention_date_proposal
    ) VALUES(v_intake,v_org,p_ledger_id,v_work,v_sender,v_action,p_attention_date_proposal);
    INSERT INTO atlas.company_work_native_ledger_relevance(
      organization_id,work_item_id,ledger_id,evidence_kind,
      source_schema,source_table,source_id,verified_at,established_by_person_id
    ) VALUES(
      v_org,v_work,p_ledger_id,'source_verified','atlas',
      'ledger_work_intakes_v1',v_intake,now(),v_sender
    );
    INSERT INTO atlas.ledger_work_intake_root_events_v1(intake_id,root_authority_id)
    SELECT v_intake,a.id FROM atlas.principal_ledger_authorities a
      JOIN atlas.principals p ON p.id=a.principal_id AND p.status='active'
    WHERE a.ledger_id=p_ledger_id AND a.authority_kind='root_governing'
      AND a.status='active' AND a.ended_at IS NULL
      AND atlas.principal_has_ledger_authority_v1(a.principal_id,p_ledger_id)
    ON CONFLICT(intake_id,root_authority_id) DO NOTHING;
    GET DIAGNOSTICS v_root_events=ROW_COUNT;
    IF v_root_events=0 THEN
      RAISE EXCEPTION 'Current Ledger root inbox unavailable' USING ERRCODE='23514';
    END IF;
  END IF;
  -- Do not reveal identities, recipient count, or private root names.
  RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_intake_v1',
    'ledgerId',p_ledger_id,'workItemId',v_work,'intakeId',v_intake,
    'attentionDateProposal',p_attention_date_proposal,
    'assignedToPerson',false,'personDayPlacementEstablished',false,
    'notificationStatus','inbox_queued_not_delivered');
END
$function$;

-- The submitter may see only their own original and intake state, with
-- neither root identities nor other submissions, allocation or count.
CREATE FUNCTION atlas.ledger_work_submission_status_self_api_v1(p_intake_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_sender uuid;v_intake atlas.ledger_work_intakes_v1%rowtype;
 v_title text;v_work_state text;
BEGIN
 IF auth.uid() IS NULL OR
   (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Signed canonical Person required' USING ERRCODE='42501';END IF;
 v_sender:=atlas.current_person_id_v1();
 SELECT * INTO v_intake FROM atlas.ledger_work_intakes_v1
 WHERE id=p_intake_id AND submitted_by_person_id=v_sender;
 IF v_intake.id IS NULL OR
   NOT atlas.person_has_native_ledger_connection_v1(
     v_intake.organization_id,v_intake.ledger_id,v_sender)
 THEN RAISE EXCEPTION 'Ledger submission unavailable' USING ERRCODE='42501';END IF;
 SELECT title,work_state INTO v_title,v_work_state FROM atlas.work_items
 WHERE id=v_intake.work_item_id AND organization_id=v_intake.organization_id;
 IF v_title IS NULL THEN RAISE EXCEPTION 'Original Work unavailable' USING ERRCODE='23514';END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','ledger_work_submission_status_v1',
   'ledgerId',v_intake.ledger_id,'workItemId',v_intake.work_item_id,
   'intakeId',v_intake.id,'title',v_title,
   'attentionDateProposal',v_intake.attention_date_proposal,
   'reviewState',v_intake.review_state,'workState',v_work_state);
END
$function$;

-- Current governors of THIS exact Ledger receive the queue. Rights
-- are rechecked on each read; historical event recipient is not authority.
CREATE FUNCTION atlas.ledger_work_root_inbox_self_api_v1(
  p_ledger_id uuid,p_limit integer DEFAULT 50,p_after_intake_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_items jsonb;
BEGIN
 PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'Page size out of range' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'intakeId',s.id,'workItemId',s.work_item_id,'ledgerId',s.ledger_id,
   'title',s.title,'reviewState',s.review_state,
   'attentionDateProposal',s.attention_date_proposal,
   'createdAt',s.created_at) ORDER BY s.id),'[]'::jsonb)
 INTO v_items FROM (
   SELECT i.id,i.work_item_id,i.ledger_id,w.title,i.review_state,
     i.attention_date_proposal,i.created_at
   FROM atlas.ledger_work_intakes_v1 i
   JOIN atlas.work_items w ON w.id=i.work_item_id
     AND w.organization_id=i.organization_id
   WHERE i.ledger_id=p_ledger_id
     AND (p_after_intake_id IS NULL OR i.id>p_after_intake_id)
   ORDER BY i.id LIMIT p_limit
 ) s;
 RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_root_inbox_v1',
   'ledgerId',p_ledger_id,'items',v_items);
END
$function$;

-- Existing Data API uses public facades; always let atlas source govern.
CREATE FUNCTION public.submit_ledger_work_self_api_v1(
 p_ledger_id uuid,p_title text,p_attention_date_proposal date,p_source_action_id text
) RETURNS jsonb LANGUAGE sql SET search_path TO 'pg_catalog'
AS $function$
 SELECT atlas.submit_ledger_work_self_api_v1($1,$2,$3,$4);
$function$;
CREATE FUNCTION public.ledger_work_submission_status_self_api_v1(p_intake_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog'
AS $function$
 SELECT atlas.ledger_work_submission_status_self_api_v1($1);
$function$;
CREATE FUNCTION public.ledger_work_root_inbox_self_api_v1(
 p_ledger_id uuid,p_limit integer DEFAULT 50,p_after_intake_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog'
AS $function$
 SELECT atlas.ledger_work_root_inbox_self_api_v1($1,$2,$3);
$function$;
REVOKE ALL ON FUNCTION atlas.submit_ledger_work_self_api_v1(uuid,text,date,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.ledger_work_submission_status_self_api_v1(uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.ledger_work_root_inbox_self_api_v1(uuid,integer,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.submit_ledger_work_self_api_v1(uuid,text,date,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.ledger_work_submission_status_self_api_v1(uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.ledger_work_root_inbox_self_api_v1(uuid,integer,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.submit_ledger_work_self_api_v1(uuid,text,date,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ledger_work_submission_status_self_api_v1(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ledger_work_root_inbox_self_api_v1(uuid,integer,uuid)
  TO authenticated;
COMMIT;
