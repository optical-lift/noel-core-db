-- Us-only synthetic postconditions for event custody. Entire test is rollback-only.
BEGIN;
DO $test$
DECLARE
 v_a uuid := pg_catalog.gen_random_uuid();
 v_b uuid := pg_catalog.gen_random_uuid();
 p_a uuid; p_b uuid; r_a uuid; stream_a uuid; stream_b uuid;
 a_first uuid; a_second uuid; seq bigint; dig text; replay boolean;
 n int; standing text; rejected boolean; expected_digest text;
BEGIN
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
  WHERE ns.nspname='us' AND c.relname IN ('carry_case_streams_v1','carry_case_events_v1')
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
 ) THEN RAISE EXCEPTION 'Us Carry missing forced RLS'; END IF;
 IF pg_catalog.has_table_privilege('anon','us.carry_case_events_v1','SELECT')
 OR pg_catalog.has_table_privilege('authenticated','us.carry_case_events_v1','SELECT')
 OR pg_catalog.has_table_privilege('authenticated','us.carry_case_events_v1','INSERT')
 OR pg_catalog.has_function_privilege('authenticated',
   'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'Unauthorized client event access'; END IF;
 IF pg_catalog.has_table_privilege('service_role','us.carry_case_events_v1','INSERT')
 OR NOT pg_catalog.has_function_privilege('service_role',
   'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'Event writer bypass exposed or append unavailable'; END IF;

 INSERT INTO us.financial_expectation_plans
 (owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
 VALUES (v_a,'synthetic:carry_plan_one','Synthetic private Carry plan','2027-01-01','2027-08-31','synthetic:plan-source')
 RETURNING id INTO p_a;
 INSERT INTO us.financial_expectation_revisions
 (owner_auth_user_id,plan_id,revision,standing,source_ref)
 VALUES(v_a,p_a,1,'draft','synthetic:first-revision')
 RETURNING id INTO r_a;
 INSERT INTO us.financial_expectation_lines
 (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,money_role,
  expectation_state,forecast_amount)
 VALUES(v_a,r_a,'2027-01-01','basic_income','household','available_inflow','estimated',500);
 INSERT INTO us.carry_case_streams_v1
 (owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
 VALUES(v_a,'synthetic:carry_main','financial_expectation',p_a)
 RETURNING id INTO stream_a;

 SELECT event_id,event_sequence,digest,replayed INTO a_first,seq,dig,replay
 FROM us.carry_append_event_v1(stream_a,'synthetic:case_open','CASE_OPENED',
 '2026-12-01','USER_ASSERTED','synthetic:source-open',
 '{"question":"Can this source carry a due responsibility?"}'::jsonb,1);
 IF seq<>1 OR replay OR length(dig)<>64 THEN
  RAISE EXCEPTION 'Opening event not produced correctly'; END IF;
 SELECT event_id,event_sequence,digest,replayed INTO a_second,seq,dig,replay
 FROM us.carry_append_event_v1(stream_a,'synthetic:case_open','CASE_OPENED',
 '2026-12-01','USER_ASSERTED','synthetic:source-open',
 '{"question":"Can this source carry a due responsibility?"}'::jsonb,1);
 IF a_second<>a_first OR seq<>1 OR NOT replay THEN
  RAISE EXCEPTION 'Repeat opening duplicated event'; END IF;

 rejected:=false;
 BEGIN
  PERFORM us.carry_append_event_v1(stream_a,'synthetic:case_open','CASE_OPENED',
    '2026-12-01','USER_ASSERTED','synthetic:source-open',
    '{"question":"Different intent is forbidden."}'::jsonb,1);
 EXCEPTION WHEN unique_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Changed event reused identical action key'; END IF;

 SELECT event_id,event_sequence,digest,replayed INTO a_second,seq,dig,replay
 FROM us.carry_append_event_v1(stream_a,'synthetic:scenario_1','SCENARIO_CREATED',
 '2027-01-01','PROJECTED','synthetic:source-scenario',
 '{"reason":"Explore alternate assumptions","value":{"scope":"housing"}}'::jsonb,2);
 IF seq<>2 OR replay THEN RAISE EXCEPTION 'Scenario event append failed'; END IF;

 rejected:=false;
 BEGIN
  PERFORM us.carry_append_event_v1(stream_a,'synthetic:wrong_seq','FACT_ASSERTED',
    '2027-01-01','USER_ASSERTED','synthetic:source-event',
    '{"reason":"Known separately","value":100}'::jsonb,2);
 EXCEPTION WHEN serialization_failure THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Stale event sequence accepted'; END IF;

 SELECT event_id,event_sequence,digest,replayed INTO a_second,seq,dig,replay
 FROM us.carry_append_event_v1(stream_a,'synthetic:seal_revision_1','REVISION_SEALED',
 '2027-01-01','COMMITTED','synthetic:source-seal',
 jsonb_build_object('revision_id',r_a::text),3);
 IF seq<>3 OR replay THEN RAISE EXCEPTION 'Seal append failed'; END IF;
 SELECT r.standing INTO standing FROM us.financial_expectation_revisions r WHERE id=r_a;
 IF standing<>'adopted' THEN RAISE EXCEPTION 'Sealed revision was not adopted'; END IF;

 SELECT event_id,event_sequence,digest,replayed INTO a_first,seq,dig,replay
 FROM us.carry_append_event_v1(stream_a,'synthetic:seal_revision_1','REVISION_SEALED',
 '2027-01-01','COMMITTED','synthetic:source-seal',
 jsonb_build_object('revision_id',r_a::text),3);
 IF NOT replay OR seq<>3 OR a_second<>a_first THEN
  RAISE EXCEPTION 'Idempotent adopted-revision seal retry failed'; END IF;

 rejected:=false;
 BEGIN
  INSERT INTO us.financial_expectation_lines
  (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,money_role,
   expectation_state,forecast_amount)
  VALUES(v_a,r_a,'2027-02-01','late_append','household','available_inflow','target',10);
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Historical adopted revision accepted new line'; END IF;

 rejected:=false;
 BEGIN
  UPDATE us.financial_expectation_revisions SET narrative='{"changed":true}' WHERE id=r_a;
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Immutable revision accepted changed content'; END IF;

 -- Baseline is an honest recorded import of the adopted historic revision, not
 -- a fictional history of changes that preceded event custody.
 rejected:=false;
 BEGIN
  INSERT INTO us.carry_case_streams_v1
  (owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
  VALUES(v_a,'synthetic:duplicate_stream','financial_expectation',p_a);
 EXCEPTION WHEN unique_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'A plan acquired duplicate financial history streams'; END IF;
 -- Synthetic import of the now-adopted revision; production cutover imports
 -- the existing adopted historical revision directly after CASE_OPENED.
 PERFORM us.carry_append_event_v1(stream_a,'synthetic:baseline_import','BASELINE_IMPORTED',
  '2027-01-01','OBSERVED','synthetic:source-baseline',
  jsonb_build_object('revision_id',r_a::text),4);
 SELECT count(*),max(ev.payload->>'snapshot_digest') INTO n,expected_digest
 FROM us.carry_case_events_v1 ev
 WHERE ev.stream_id=stream_a AND ev.event_type='BASELINE_IMPORTED';
 IF n<>1 OR length(expected_digest)<>64 THEN
  RAISE EXCEPTION 'Historic baseline digest missing'; END IF;

 rejected:=false;
 BEGIN
  PERFORM us.carry_append_event_v1(stream_a,'synthetic:second_import','BASELINE_IMPORTED',
  '2027-01-01','OBSERVED','synthetic:source-baseline',
  jsonb_build_object('revision_id',r_a::text),5);
 EXCEPTION WHEN unique_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Duplicated baseline accepted'; END IF;

 INSERT INTO us.financial_expectation_plans
 (owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
 VALUES(v_b,'synthetic:another_private','Other synthetic owner','2027-01-01','2027-08-31','synthetic:other-source')
 RETURNING id INTO p_b;
 rejected:=false;
 BEGIN
  INSERT INTO us.carry_case_streams_v1
   (owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
  VALUES(v_b,'synthetic:wrong_owner','financial_expectation',p_a);
 EXCEPTION WHEN foreign_key_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Another owner was allowed to join private source plan'; END IF;

 rejected:=false;
 BEGIN
  UPDATE us.carry_case_events_v1 SET payload='{}'::jsonb WHERE id=a_first;
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Event mutation was accepted'; END IF;

 -- Chain continuity checked independently of the appender.
 SELECT count(*) INTO n FROM (
 SELECT ev.stream_sequence,
        lag(ev.event_digest) OVER(ORDER BY ev.stream_sequence) AS expected_previous,
        ev.previous_event_digest
 FROM us.carry_case_events_v1 ev WHERE ev.stream_id=stream_a
 ) ordered
 WHERE expected_previous IS DISTINCT FROM previous_event_digest;
 IF n<>0 THEN RAISE EXCEPTION 'Replay chain continuity broken'; END IF;
 SELECT count(*) INTO n FROM us.financial_expectation_lines WHERE revision_id=r_a;
 IF n<>1 THEN RAISE EXCEPTION 'Historical line count changed'; END IF;
END;
$test$;
ROLLBACK;
