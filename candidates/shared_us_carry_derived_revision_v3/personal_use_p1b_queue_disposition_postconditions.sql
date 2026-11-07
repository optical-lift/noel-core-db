-- Gate G1 nomination-only negative/grants test. Disposable PG only.
BEGIN;
INSERT INTO auth.users(id) VALUES
 ('aaaaaaaa-3333-4333-8333-333333333333'),
 ('bbbbbbbb-3333-4333-8333-333333333333'),
 ('cccccccc-3333-4333-8333-333333333333'),
 ('dddddddd-3333-4333-8333-333333333333');
INSERT INTO reality.entities(id,entity_kind,identity_state) VALUES
 ('11111111-3333-4333-8333-333333333333','person','canonical'),
 ('22222222-3333-4333-8333-333333333333','person','canonical'),
 ('33333333-3333-4333-8333-333333333333','person','disputed'),
 ('44444444-3333-4333-8333-333333333333','person','canonical');
INSERT INTO reality.auth_person_bindings
 (id,auth_user_id,person_entity_id,binding_state) VALUES
 ('eeeeeeee-3333-4333-8333-333333333333',
  'aaaaaaaa-3333-4333-8333-333333333333',
  '11111111-3333-4333-8333-333333333333','active'),
 ('eeeeeeee-4444-4444-8444-444444444444',
  'bbbbbbbb-3333-4333-8333-333333333333',
  '22222222-3333-4333-8333-333333333333','active'),
 ('eeeeeeee-5555-4555-8555-555555555555',
  'cccccccc-3333-4333-8333-333333333333',
  '33333333-3333-4333-8333-333333333333','active'),
 ('eeeeeeee-6666-4666-8666-666666666666',
  'dddddddd-3333-4333-8333-333333333333',
  '44444444-3333-4333-8333-333333333333','retired');

INSERT INTO us.financial_expectation_plans
 (id,owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
 VALUES('99999999-3333-4333-8333-333333333333',
        'aaaaaaaa-3333-4333-8333-333333333333',
        'synthetic_nominate_01','Synthetic nomination-only source',
        '2027-01-01','2027-03-31','synthetic:native:source');
INSERT INTO us.financial_expectation_revisions
 (id,owner_auth_user_id,plan_id,revision,standing,source_ref)
 VALUES('88888888-3333-4333-8333-333333333333',
        'aaaaaaaa-3333-4333-8333-333333333333',
        '99999999-3333-4333-8333-333333333333',
        1,'draft','synthetic:native:revision');
INSERT INTO us.financial_expectation_lines
 (owner_auth_user_id,revision_id,period_month,line_key,
  economic_scope,money_role,expectation_state,forecast_amount)
 VALUES('aaaaaaaa-3333-4333-8333-333333333333',
        '88888888-3333-4333-8333-333333333333',
        '2027-01-01','source_income','household','available_inflow','estimated',20);

-- Synthetic legacy adopted original, not possible as an independent
-- application operation. Re-enable source trigger immediately.
ALTER TABLE us.financial_expectation_revisions
 DISABLE TRIGGER financial_revisions_immutable;
UPDATE us.financial_expectation_revisions SET standing='adopted'
 WHERE id='88888888-3333-4333-8333-333333333333';
ALTER TABLE us.financial_expectation_revisions
 ENABLE TRIGGER financial_revisions_immutable;


-- All following operations are synthetic and roll back on exit.
DO $grants$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
 'us.carry_authorize_primary_open_approval_v3(uuid,uuid,text,timestamptz)',
 'us.carry_approve_and_open_primary_v3(uuid,uuid,text)'
 ] LOOP
  IF NOT has_function_privilege('us_carry_backend',sig,'EXECUTE')
    OR has_function_privilege('service_role',sig,'EXECUTE')
    OR has_function_privilege('authenticated',sig,'EXECUTE')
    OR has_function_privilege('anon',sig,'EXECUTE')
  THEN RAISE EXCEPTION 'G3 function privilege failed: %',sig; END IF;
 END LOOP;
 IF has_table_privilege('us_carry_backend','us.carry_case_events_v1','INSERT')
  OR has_table_privilege('us_carry_backend','us.carry_case_streams_v1','INSERT')
  OR has_table_privilege('us_carry_backend','us.carry_primary_open_approval_grants_v3','INSERT')
  OR has_table_privilege('us_carry_backend','us.carry_primary_open_approval_decisions_v3','SELECT')
  OR has_function_privilege('us_carry_backend',
   'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'Dedicated backend acquired direct writer or reader'; END IF;
END $grants$;

SET LOCAL ROLE us_carry_backend;
DO $g3$
DECLARE o uuid:='aaaaaaaa-3333-4333-8333-333333333333';
 r uuid:='bbbbbbbb-3333-4333-8333-333333333333';
 req jsonb; nom jsonb; consent jsonb; read_grant jsonb;
 approval_grant jsonb; decision jsonb; replay jsonb;
 n uuid; exp timestamptz; st uuid;
BEGIN
 req:=us.carry_request_financial_open_v3(
  o,'synthetic_nominate_01','synthetic_req_01','primary');
 nom:=us.carry_nominate_primary_reviewer_v3(
  o,(req->>'request_id')::uuid,'22222222-3333-4333-8333-333333333333',
  'nominate-reviewer-01');
 n:=(nom->>'nomination_id')::uuid;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(r,n,'approval-without-grant-01');
  RAISE EXCEPTION 'G1 nomination alone opened canonical Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 consent:=us.carry_accept_primary_reviewer_v3(r,n,'g3-independent-consent-001');
 IF consent->>'approval_authority_granted'<>'false'
 THEN RAISE EXCEPTION 'Acceptance already grants approval'; END IF;
 exp:=pg_catalog.now()+interval '2 hours';
 read_grant:=us.carry_grant_primary_attestation_v3(o,n,'g3-read-scope-001',exp);
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(r,n,'approval-read-only-01');
  RAISE EXCEPTION 'G2 attestation alone opened Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_authorize_primary_open_approval_v3(
   r,n,'nominee-self-authorize-001',exp);
  RAISE EXCEPTION 'Nominee granted own opening approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_authorize_primary_open_approval_v3(
   o,n,'too-long-approval-001',pg_catalog.now()+interval '6 days');
  RAISE EXCEPTION 'G3 expiry exceeded G2 expiry';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 approval_grant:=us.carry_authorize_primary_open_approval_v3(
   o,n,'owner-explicit-g3-approval-001',pg_catalog.now()+interval '1 hour');
 IF approval_grant->>'scope'<>'open_primary_case_and_import_attested_baseline'
 OR approval_grant->>'decision_recorded'<>'false'
 OR approval_grant->>'case_opened'<>'false'
 OR approval_grant->>'recorded_event'<>'false'
 OR approval_grant->>'replayed'<>'false'
 OR approval_grant->>'expires_at' IS NULL
 THEN RAISE EXCEPTION 'G3 grant did not remain non-durable: %',approval_grant; END IF;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(o,n,'owner-self-approve-001');
  RAISE EXCEPTION 'Owner signed own approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(
   'cccccccc-3333-4333-8333-333333333333',n,'outsider-approve-001');
  RAISE EXCEPTION 'Outsider approved primary Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 decision:=us.carry_approve_and_open_primary_v3(r,n,'approver-signed-g3-001');
 IF decision->>'status'<>'approved_primary_opened'
 OR (decision->>'event_count')::integer<>2
 OR decision->>'replayed'<>'false'
 OR decision->>'stream_id' IS NULL OR decision->>'approval_decision_id' IS NULL
 THEN RAISE EXCEPTION 'Independent approval did not atomically open history: %',decision; END IF;
 st:=(decision->>'stream_id')::uuid;
 replay:=us.carry_approve_and_open_primary_v3(r,n,'approver-signed-g3-001');
 IF replay->>'replayed'<>'true' OR replay->>'stream_id'<>st::text
 OR replay->>'approval_decision_id'<>decision->>'approval_decision_id'
 THEN RAISE EXCEPTION 'G3 signed replay was not idempotent: %',replay; END IF;
 BEGIN
  PERFORM us.carry_approve_and_open_primary_v3(r,n,'different-decision-g3-001');
  RAISE EXCEPTION 'Changed decision key created another approval';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM us.carry_authorize_primary_open_approval_v3(
   o,n,'new-grant-after-opening-001',pg_catalog.now()+interval '30 minutes');
  RAISE EXCEPTION 'Owner reopened grant for already opened Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_append_event_v1(
    st,'direct-appender-should-deny-001','FACT_ASSERTED',NULL,
    'USER_ASSERTED','us:forbidden:direct',
    '{"reason":"Bypass prohibited","value":true}'::jsonb,3);
  RAISE EXCEPTION 'Backend gained legacy event append';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $g3$;
RESET ROLE;

-- Capture the canonical G3 stream in a synthetic session setting, without
-- granting the test backend SELECT on any source custody table.
SELECT pg_catalog.set_config('p1.synthetic_stream',
 (SELECT canonical_stream_id::text
  FROM us.carry_primary_open_approval_decisions_v3 LIMIT 1),true);
-- A second canonical reviewer demonstrates one event may be offered to
-- multiple eligible Persons, but only ONE may ever approve that event.
INSERT INTO auth.users(id) VALUES('ffffeeee-3333-4333-8333-333333333333');
INSERT INTO reality.entities(id,entity_kind,identity_state)
 VALUES('55555555-3333-4333-8333-333333333333','person','canonical');
INSERT INTO reality.auth_person_bindings
 (id,auth_user_id,person_entity_id,binding_state)
 VALUES('eeeeeeee-7777-4777-8777-777777777777',
        'ffffeeee-3333-4333-8333-333333333333',
        '55555555-3333-4333-8333-333333333333','active');

DO $priv$
DECLARE sig text; role_name text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
  'us.carry_propose_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb)',
  'us.carry_grant_ordinary_review_v3(uuid,uuid,uuid,text,timestamptz)',
  'us.carry_revoke_ordinary_review_v3(uuid,uuid,text,text)',
  'us.carry_read_ordinary_review_packet_v3(uuid,uuid)',
  'us.carry_approve_ordinary_event_v3(uuid,uuid,text,text)'
 ] LOOP
  IF NOT has_function_privilege('us_carry_backend',sig,'EXECUTE')
  THEN RAISE EXCEPTION 'P1 narrow backend procedure missing: %',sig; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(role_name,sig,'EXECUTE')
   THEN RAISE EXCEPTION 'P1 private function exposed: % to %',sig,role_name; END IF;
  END LOOP;
 END LOOP;
 IF has_table_privilege('us_carry_backend','us.carry_ordinary_proposals_v3','SELECT')
 OR has_table_privilege('us_carry_backend','us.carry_ordinary_proposals_v3','INSERT')
 OR has_table_privilege('us_carry_backend','us.carry_ordinary_approved_decisions_v3','INSERT')
 OR has_function_privilege('us_carry_backend',
  'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'P1 direct writer or table bypass detected'; END IF;
END $priv$;

SET LOCAL ROLE us_carry_backend;
DO $p1$
DECLARE o uuid:='aaaaaaaa-3333-4333-8333-333333333333';
 r uuid:='bbbbbbbb-3333-4333-8333-333333333333';
 r2 uuid:='ffffeeee-3333-4333-8333-333333333333';
 outsider uuid:='cccccccc-3333-4333-8333-333333333333';
 stream uuid:=pg_catalog.current_setting('p1.synthetic_stream')::uuid;
 p jsonb; p2 jsonb; g jsonb; g2 jsonb; packet jsonb;
 decided jsonb; again jsonb; revoke_result jsonb;
 pid uuid; pid2 uuid; gid uuid; exp timestamptz;
 amount jsonb:='{"reason":"Owner noted an upcoming household obligation","value":{"reference":"manual-only"}}'::jsonb;
BEGIN
 BEGIN
  PERFORM us.carry_propose_ordinary_event_v3(
   outsider,stream,'p1-outsider-proposal-001','FACT_ASSERTED',NULL,
   'USER_ASSERTED','us:self:manual-p1',amount);
  RAISE EXCEPTION 'Outsider proposed in owner Case';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 p:=us.carry_propose_ordinary_event_v3(
   o,stream,'p1-owner-proposal-001','FACT_ASSERTED',NULL,
   'USER_ASSERTED','us:self:manual-p1',amount);
 IF p->>'state'<>'pending_separate_review'
  OR p->>'event_created'<>'false'
  OR p->>'replayed'<>'false'
 THEN RAISE EXCEPTION 'Submission wrote a canonical event: %',p; END IF;
 pid:=(p->>'proposal_id')::uuid;
 -- Same intent and stable owner key never creates another proposal.
 again:=us.carry_propose_ordinary_event_v3(
   o,stream,'p1-owner-proposal-001','FACT_ASSERTED',NULL,
   'USER_ASSERTED','us:self:manual-p1',amount);
 IF again->>'proposal_id'<>pid::text OR again->>'replayed'<>'true'
 THEN RAISE EXCEPTION 'Source proposal not idempotent'; END IF;
 BEGIN
  PERFORM us.carry_propose_ordinary_event_v3(
   o,stream,'p1-owner-proposal-001','FACT_ASSERTED',NULL,
   'USER_ASSERTED','us:self:manual-p1',
   '{"reason":"Changed after submission","value":{"reference":"different"}}'::jsonb);
  RAISE EXCEPTION 'Changed proposal key accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;

 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(r,pid);
  RAISE EXCEPTION 'Ungrantable proposal leaked to reviewer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(r,pid,'no-grant-approve-001',repeat('0',64));
  RAISE EXCEPTION 'Reviewer approved without exact source digest/grant';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_grant_ordinary_review_v3(
    o,pid,'11111111-3333-4333-8333-333333333333',
    'p1-owner-self-grant-001',pg_catalog.now()+interval '1 day');
  RAISE EXCEPTION 'Owner made self a separate reviewer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 exp:=pg_catalog.now()+interval '1 day';
 g:=us.carry_grant_ordinary_review_v3(
  o,pid,'22222222-3333-4333-8333-333333333333',
  'p1-grant-reviewer-one',exp);
 gid:=(g->>'grant_id')::uuid;
 IF g->>'scope'<>'this_proposal_only'
  OR g->>'event_approved'<>'false' OR g->>'case_reader_granted'<>'false'
 THEN RAISE EXCEPTION 'Grant exceeds one proposal: %',g; END IF;
 g2:=us.carry_grant_ordinary_review_v3(
  o,pid,'55555555-3333-4333-8333-333333333333',
  'p1-grant-reviewer-two',exp);
 IF g2->>'scope'<>'this_proposal_only'
 THEN RAISE EXCEPTION 'Second reviewer grant invalid'; END IF;
 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(o,pid);
  RAISE EXCEPTION 'Owner impersonated granted reviewer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(outsider,pid);
  RAISE EXCEPTION 'Outsider saw private proposal';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 packet:=us.carry_read_ordinary_review_packet_v3(r,pid);
 IF packet->>'scope'<>'this_proposal_only'
  OR packet->>'full_case_visible'<>'false'
  OR packet->'payload'<>amount
  OR length(packet->>'envelope_digest')<>64
  OR (packet->>'expected_sequence')::int<>3
 THEN RAISE EXCEPTION 'Review packet incomplete or overly broad: %',packet; END IF;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(
   o,pid,'p1-owner-self-decision',packet->>'envelope_digest');
  RAISE EXCEPTION 'Owner self-approved an ordinary event';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(
   r,pid,'p1-tampered-digest-001',repeat('0',64));
  RAISE EXCEPTION 'Tampered proposal digest approved';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 decided:=us.carry_approve_ordinary_event_v3(
  r,pid,'p1-independent-approve-001',packet->>'envelope_digest');
 IF decided->>'state'<>'approved_event_recorded'
 OR (decided->>'event_sequence')::int<>3
 OR decided->>'replayed'<>'false'
 THEN RAISE EXCEPTION 'First independent ordinary approval failed: %',decided; END IF;
 again:=us.carry_approve_ordinary_event_v3(
  r,pid,'p1-independent-approve-001',packet->>'envelope_digest');
 IF again->>'replayed'<>'true'
  OR again->>'event_id'<>decided->>'event_id'
  OR again->>'decision_id'<>decided->>'decision_id'
 THEN RAISE EXCEPTION 'Identical decision did not replay'; END IF;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(
   r2,pid,'p1-second-reviewer-001',packet->>'envelope_digest');
  RAISE EXCEPTION 'Two reviewers approved the same event';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(r,pid);
  RAISE EXCEPTION 'Approved packet still exposed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 -- New independent event after first approved action: revocation prevents
 -- another permanent event even with an otherwise valid grant.
 p2:=us.carry_propose_ordinary_event_v3(
  o,stream,'p1-second-proposal-001','DECISION_RECORDED',NULL,
  'USER_ASSERTED','us:self:manual-p1',
  '{"reason":"A second independent proposal","value":"not approved"}'::jsonb);
 pid2:=(p2->>'proposal_id')::uuid;
 g:=us.carry_grant_ordinary_review_v3(
  o,pid2,'22222222-3333-4333-8333-333333333333',
  'p1-second-grant-001',pg_catalog.now()+interval '1 day');
 packet:=us.carry_read_ordinary_review_packet_v3(r,pid2);
 revoke_result:=us.carry_revoke_ordinary_review_v3(
  o,(g->>'grant_id')::uuid,'p1-revoke-grant-001',
  'Owner withdrew this exact review permission');
 IF revoke_result->>'state'<>'revoked' THEN
  RAISE EXCEPTION 'Revocation not durable'; END IF;
 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(r,pid2);
  RAISE EXCEPTION 'Revoked reviewer still saw packet';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(
    r,pid2,'p1-approve-after-revoke',packet->>'envelope_digest');
  RAISE EXCEPTION 'Revoked reviewer committed second event';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $p1$;
RESET ROLE;
DO $audit$
DECLARE n integer;v us.carry_ordinary_approved_decisions_v3%ROWTYPE;
 s uuid:=pg_catalog.current_setting('p1.synthetic_stream')::uuid;
BEGIN
 SELECT count(*) INTO n FROM us.carry_ordinary_proposals_v3;
 IF n<>2 THEN RAISE EXCEPTION 'Expected exactly two immutable proposals'; END IF;
 SELECT count(*) INTO n FROM us.carry_ordinary_review_grants_v3;
 IF n<>3 THEN RAISE EXCEPTION 'Expected two eligible reviewers plus a later scoped grant'; END IF;
 SELECT count(*) INTO n FROM us.carry_ordinary_review_revocations_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Expected one immutable revocation'; END IF;
 SELECT count(*) INTO n FROM us.carry_ordinary_approved_decisions_v3;
 IF n<>1 THEN RAISE EXCEPTION 'Expected exactly one independent event decision'; END IF;
 SELECT * INTO v FROM us.carry_ordinary_approved_decisions_v3 LIMIT 1;
 IF v.owner_auth_user_id=v.approver_auth_user_id
 OR v.owner_person_entity_id=v.approver_person_entity_id
 OR v.event_sequence<>3
 OR NOT EXISTS(SELECT 1 FROM us.carry_case_events_v1 e
  WHERE e.id=v.event_id AND e.stream_id=s AND e.stream_sequence=3
   AND e.actor_auth_user_id=v.owner_auth_user_id
   AND e.event_type='FACT_ASSERTED')
 THEN RAISE EXCEPTION 'P1 provenance or immutable canonical event mismatch'; END IF;
 SELECT count(*) INTO n FROM us.carry_case_events_v1 WHERE stream_id=s;
 IF n<>3 THEN RAISE EXCEPTION 'P1 bypass or duplicate canonical event'; END IF;
END $audit$;

-- P1B additional synthetic assertions, inside the original P1A disposable
-- transaction. A run must apply P1A and then P1B source before this file.
DO $priv_p1b$
DECLARE sig text; role_name text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
  'us.carry_owner_ordinary_queue_v3(uuid,uuid,uuid,integer)',
  'us.carry_reviewer_ordinary_queue_v3(uuid,uuid,integer)',
  'us.carry_dispose_ordinary_proposal_v3(uuid,uuid,text,text,text,text)'
 ] LOOP
  IF NOT has_function_privilege('us_carry_backend',sig,'EXECUTE')
  THEN RAISE EXCEPTION 'Missing narrow P1B port: %',sig; END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(role_name,sig,'EXECUTE')
   THEN RAISE EXCEPTION 'Private P1B function leaked to %',role_name; END IF;
  END LOOP;
 END LOOP;
 IF has_table_privilege('us_carry_backend','us.carry_ordinary_dispositions_v3','SELECT')
  OR has_table_privilege('us_carry_backend','us.carry_ordinary_dispositions_v3','INSERT')
  OR has_table_privilege('service_role','us.carry_ordinary_dispositions_v3','SELECT')
 THEN RAISE EXCEPTION 'Terminal table direct privilege leaked'; END IF;
END $priv_p1b$;
SET LOCAL ROLE us_carry_backend;
DO $p1b$
DECLARE o uuid:='aaaaaaaa-3333-4333-8333-333333333333';
 r uuid:='bbbbbbbb-3333-4333-8333-333333333333';
 outsider uuid:='cccccccc-3333-4333-8333-333333333333';
 stream uuid:=pg_catalog.current_setting('p1.synthetic_stream')::uuid;
 p jsonb;p2 jsonb;g jsonb;packet jsonb;wpacket jsonb;
 owner_page jsonb;review_page jsonb;decision jsonb;replay jsonb;
 pid uuid;wid uuid;dig text;
BEGIN
 BEGIN
  PERFORM us.carry_owner_ordinary_queue_v3(outsider,stream,NULL,20);
  RAISE EXCEPTION 'Outsider enumerated owner queue';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_reviewer_ordinary_queue_v3(outsider,NULL,20);
  RAISE EXCEPTION 'Noncanonical outsider received reviewer queue';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 owner_page:=us.carry_owner_ordinary_queue_v3(o,stream,NULL,20);
 IF owner_page->>'scope'<>'owner_selected_case_proposals_only'
  OR owner_page->>'full_case_visible'<>'false'
  OR jsonb_array_length(owner_page->'items')<>2
  OR owner_page ? 'total_count'
  OR (owner_page::text LIKE '%manual-p1%')
 THEN RAISE EXCEPTION 'Owner queue exceeded bounded identifiers: %',owner_page; END IF;
 review_page:=us.carry_reviewer_ordinary_queue_v3(r,NULL,20);
 IF jsonb_array_length(review_page->'items')<>0
 THEN RAISE EXCEPTION 'Approved or revoked proposal appeared in reviewer queue'; END IF;
 p:=us.carry_propose_ordinary_event_v3(
   o,stream,'p1b-decline-proposal-001','FACT_ASSERTED',NULL,
   'UNKNOWN','us:self:p1b-manual',
   '{"reason":"Synthetic decline before event","value":"unverified"}'::jsonb);
 pid:=(p->>'proposal_id')::uuid;
 g:=us.carry_grant_ordinary_review_v3(
   o,pid,'22222222-3333-4333-8333-333333333333',
   'p1b-decline-grant-001',pg_catalog.now()+interval '1 hour');
 packet:=us.carry_read_ordinary_review_packet_v3(r,pid);
 dig:=packet->>'envelope_digest';
 review_page:=us.carry_reviewer_ordinary_queue_v3(r,NULL,20);
 IF jsonb_array_length(review_page->'items')<>1
  OR review_page->'items'->0->>'proposal_id'<>pid::text
  OR review_page ? 'total_count'
  OR review_page::text LIKE '%unverified%'
 THEN RAISE EXCEPTION 'Reviewer queue revealed ungranted or Case data: %',review_page; END IF;
 BEGIN
  PERFORM us.carry_dispose_ordinary_proposal_v3(
   o,pid,'declined','p1b-owner-self-decline-01',dig,
   'Owner cannot pretend to be an independent reviewer');
  RAISE EXCEPTION 'Owner self-declined reviewer decision';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_dispose_ordinary_proposal_v3(
   r,pid,'declined','p1b-tampered-decline-01',repeat('0',64),
   'Reject a changed source digest');
  RAISE EXCEPTION 'Changed digest declined';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 decision:=us.carry_dispose_ordinary_proposal_v3(
  r,pid,'declined','p1b-decision-decline-01',dig,
  'Independent reviewer declined original unresolved claim');
 IF decision->>'state'<>'declined' OR decision->>'event_created'<>'false'
  OR decision->>'full_case_visible'<>'false'
 THEN RAISE EXCEPTION 'Decline modified event history: %',decision; END IF;
 replay:=us.carry_dispose_ordinary_proposal_v3(
  r,pid,'declined','p1b-decision-decline-01',dig,
  'Independent reviewer declined original unresolved claim');
 IF replay->>'replayed'<>'true' OR replay->>'decision_id'<>decision->>'decision_id'
 THEN RAISE EXCEPTION 'Decline replay did not preserve decision identity'; END IF;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(
   r,pid,'p1b-after-decline-001',dig);
  RAISE EXCEPTION 'Approval resurrected declined proposal';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(r,pid);
  RAISE EXCEPTION 'Declined original remained accessible';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_grant_ordinary_review_v3(
   o,pid,'55555555-3333-4333-8333-333333333333',
   'p1b-after-decline-grant-01',pg_catalog.now()+interval '1 hour');
  RAISE EXCEPTION 'Declined proposal gained new reviewer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 p2:=us.carry_propose_ordinary_event_v3(
  o,stream,'p1b-withdraw-proposal-01','DECISION_RECORDED',NULL,
  'USER_ASSERTED','us:self:p1b-manual',
  '{"reason":"Owner must retract exact submitted claim","value":"tentative"}'::jsonb);
 wid:=(p2->>'proposal_id')::uuid;
 g:=us.carry_grant_ordinary_review_v3(
  o,wid,'22222222-3333-4333-8333-333333333333',
  'p1b-withdraw-grant-01',pg_catalog.now()+interval '1 hour');
 wpacket:=us.carry_read_ordinary_review_packet_v3(r,wid);
 BEGIN
  PERFORM us.carry_dispose_ordinary_proposal_v3(
   r,wid,'withdrawn','p1b-reviewer-withdraw-01',
   wpacket->>'envelope_digest','Reviewer cannot withdraw owner original');
  RAISE EXCEPTION 'Reviewer withdrew owner proposal';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 decision:=us.carry_dispose_ordinary_proposal_v3(
  o,wid,'withdrawn','p1b-owner-withdraw-01',
  wpacket->>'envelope_digest','Owner withdrew the pending original claim');
 IF decision->>'state'<>'withdrawn' OR decision->>'event_created'<>'false'
 THEN RAISE EXCEPTION 'Withdrawal created canonical event'; END IF;
 BEGIN
  PERFORM us.carry_dispose_ordinary_proposal_v3(
   r,wid,'declined','p1b-late-decline-001',
   wpacket->>'envelope_digest','Reviewer tried to decline withdrawn original');
  RAISE EXCEPTION 'Withdrawal lost terminal decision race';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM us.carry_approve_ordinary_event_v3(
   r,wid,'p1b-after-withdraw-001',wpacket->>'envelope_digest');
  RAISE EXCEPTION 'Approval committed withdrawn proposal';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_ordinary_review_packet_v3(r,wid);
  RAISE EXCEPTION 'Withdrawn original remained readable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 owner_page:=us.carry_owner_ordinary_queue_v3(o,stream,NULL,20);
 IF jsonb_array_length(owner_page->'items')<>4
  OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(owner_page->'items') e
    WHERE e->>'proposal_id'=pid::text AND e->>'state'='declined')
  OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(owner_page->'items') e
    WHERE e->>'proposal_id'=wid::text AND e->>'state'='withdrawn')
 THEN RAISE EXCEPTION 'Owner queue did not preserve terminal states: %',owner_page; END IF;
 review_page:=us.carry_reviewer_ordinary_queue_v3(r,NULL,20);
 IF jsonb_array_length(review_page->'items')<>0
 THEN RAISE EXCEPTION 'Terminal original remained in reviewer queue'; END IF;
END $p1b$;
RESET ROLE;
DO $audit_p1b$
DECLARE s uuid:=pg_catalog.current_setting('p1.synthetic_stream')::uuid;
BEGIN
 IF (SELECT count(*) FROM us.carry_case_events_v1 WHERE stream_id=s)<>3
  OR (SELECT count(*) FROM us.carry_ordinary_approved_decisions_v3)<>1
  OR (SELECT count(*) FROM us.carry_ordinary_dispositions_v3)<>2
 THEN RAISE EXCEPTION 'P1B emitted event or changed prior approval'; END IF;
 IF NOT EXISTS(SELECT 1 FROM us.carry_ordinary_dispositions_v3
   WHERE disposition='declined' AND grant_id IS NOT NULL)
  OR NOT EXISTS(SELECT 1 FROM us.carry_ordinary_dispositions_v3
   WHERE disposition='withdrawn' AND grant_id IS NULL)
 THEN RAISE EXCEPTION 'Disposition provenance or grant scope missing'; END IF;
END $audit_p1b$;
ROLLBACK;
