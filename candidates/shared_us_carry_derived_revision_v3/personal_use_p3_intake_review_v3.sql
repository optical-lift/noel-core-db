-- HELD P3 source custody. Apply after P2. No migration or real source access.
BEGIN;
CREATE TABLE us.carry_intake_packets_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 stream_id uuid NOT NULL REFERENCES us.carry_case_streams_v1(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 owner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 packet_key text NOT NULL CHECK(length(btrim(packet_key)) BETWEEN 8 AND 160),
 packet_digest text NOT NULL CHECK(packet_digest ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(stream_id,packet_key)
);
CREATE TABLE us.carry_intake_witnesses_v3 (
 packet_id uuid NOT NULL REFERENCES us.carry_intake_packets_v3(id) ON DELETE RESTRICT,
 witness_key text NOT NULL CHECK(length(btrim(witness_key)) BETWEEN 8 AND 160),
 body_key text NOT NULL CHECK(length(btrim(body_key)) BETWEEN 8 AND 160),
 provider text NOT NULL CHECK(length(btrim(provider)) BETWEEN 8 AND 160),
 file_key text NOT NULL CHECK(length(btrim(file_key)) BETWEEN 8 AND 160),
 content_digest text NOT NULL CHECK(content_digest ~ '^[0-9a-f]{64}$'),
 period_start date NOT NULL,period_end date NOT NULL,
 captured_at timestamptz NOT NULL,
 record_type text NOT NULL CHECK(record_type IN ('statement','receipt','invoice','contract','manual_note')),
 certainty text NOT NULL CHECK(certainty IN ('original','extracted','manual')),
 PRIMARY KEY(packet_id,witness_key),
 CHECK(period_start >= DATE '2025-01-01' AND period_end<=DATE '2026-12-31' AND period_start<=period_end)
);
CREATE TABLE us.carry_intake_items_v3 (
 packet_id uuid NOT NULL REFERENCES us.carry_intake_packets_v3(id) ON DELETE RESTRICT,
 item_key text NOT NULL CHECK(length(btrim(item_key)) BETWEEN 8 AND 160),
 witness_key text NOT NULL,
 body_key text NOT NULL CHECK(length(btrim(body_key)) BETWEEN 8 AND 160),
 economic_key text NOT NULL CHECK(length(btrim(economic_key)) BETWEEN 8 AND 160),
 item_digest text NOT NULL CHECK(item_digest ~ '^[0-9a-f]{64}$'),
 claim_kind text NOT NULL CHECK(claim_kind IN ('transaction','obligation','debt','cash')),
 claim_state text NOT NULL CHECK(claim_state IN ('held','committed','conditional','projected','unknown')),
 amount numeric(18,2),currency text,
 knowledge_on date NOT NULL,
 PRIMARY KEY(packet_id,item_key),
 FOREIGN KEY(packet_id,witness_key) REFERENCES us.carry_intake_witnesses_v3(packet_id,witness_key) ON DELETE RESTRICT,
 CHECK((amount IS NULL AND currency IS NULL AND claim_state='unknown') OR
       (amount>=0 AND currency ~ '^[A-Z]{3}$'))
);
CREATE TABLE us.carry_intake_decisions_v3 (
 packet_id uuid NOT NULL,item_key text NOT NULL,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 decision_key text NOT NULL CHECK(length(btrim(decision_key)) BETWEEN 8 AND 160),
 expected_item_digest text NOT NULL CHECK(expected_item_digest ~ '^[0-9a-f]{64}$'),
 choice text NOT NULL CHECK(choice IN ('accept','correct','unknown')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 400),
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(packet_id,item_key),UNIQUE(owner_auth_user_id,decision_key),
 FOREIGN KEY(packet_id,item_key) REFERENCES us.carry_intake_items_v3(packet_id,item_key) ON DELETE RESTRICT
);
DO $x$ DECLARE n text; BEGIN
 FOREACH n IN ARRAY ARRAY['carry_intake_packets_v3','carry_intake_witnesses_v3','carry_intake_items_v3','carry_intake_decisions_v3'] LOOP
  EXECUTE pg_catalog.format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON us.%I FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1()',n||'_immutable',n);
  EXECUTE pg_catalog.format('ALTER TABLE us.%I ENABLE ROW LEVEL SECURITY',n);
  EXECUTE pg_catalog.format('ALTER TABLE us.%I FORCE ROW LEVEL SECURITY',n);
  EXECUTE pg_catalog.format('REVOKE ALL ON us.%I FROM PUBLIC,anon,authenticated,service_role,us_carry_backend',n);
 END LOOP;
END $x$;

-- One packet submission is atomic. The server computes SHA-256 of the full
-- canonical JSON input; source recomputes it. Exact witnesses/items are
-- provided by the restricted backend after its bytes-to-claims validation.
CREATE FUNCTION us.carry_stage_intake_v3(
 p_owner uuid,p_stream uuid,p_packet_key text,p_packet_digest text,
 p_witnesses jsonb,p_items jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_person uuid;v_old us.carry_intake_packets_v3%ROWTYPE;
 v_id uuid;v_w jsonb;v_i jsonb;v_count integer;v_digest text;
BEGIN
 IF p_owner IS NULL OR p_stream IS NULL OR p_packet_key IS NULL
  OR length(btrim(p_packet_key)) NOT BETWEEN 8 AND 160
  OR p_packet_digest IS NULL OR p_packet_digest !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(p_witnesses) IS DISTINCT FROM 'array'
  OR jsonb_typeof(p_items) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_witnesses) NOT BETWEEN 1 AND 100
  OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 500
 THEN RAISE EXCEPTION 'Bounded exact intake required' USING ERRCODE='22023'; END IF;
 v_person:=us.carry_live_canonical_person_v3(p_owner);
 PERFORM 1 FROM us.carry_case_streams_v1 s WHERE s.id=p_stream
  AND s.owner_auth_user_id=p_owner AND s.subject_kind='financial_expectation' FOR UPDATE;
 IF NOT FOUND OR v_person IS NULL OR NOT EXISTS(
  SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
  WHERE d.canonical_stream_id=p_stream AND d.owner_auth_user_id=p_owner
   AND d.owner_person_entity_id=v_person)
 THEN RAISE EXCEPTION 'Approved owner Case required' USING ERRCODE='42501'; END IF;
 v_digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
   jsonb_build_array(p_stream,p_witnesses,p_items)::text,'UTF8'),'sha256'),'hex');
 IF p_packet_digest IS DISTINCT FROM v_digest THEN
  RAISE EXCEPTION 'Intake packet digest mismatch' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_old FROM us.carry_intake_packets_v3 p
 WHERE p.stream_id=p_stream AND p.packet_key=p_packet_key FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.owner_auth_user_id IS DISTINCT FROM p_owner
   OR v_old.owner_person_entity_id IS DISTINCT FROM v_person
   OR v_old.packet_digest IS DISTINCT FROM p_packet_digest
  THEN RAISE EXCEPTION 'Conflicting intake packet key' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('packet_id',v_old.id,'replayed',true,'canonical_event_created',false);
 END IF;
 INSERT INTO us.carry_intake_packets_v3(stream_id,owner_auth_user_id,owner_person_entity_id,packet_key,packet_digest)
 VALUES(p_stream,p_owner,v_person,p_packet_key,p_packet_digest) RETURNING id INTO v_id;
 FOR v_w IN SELECT value FROM jsonb_array_elements(p_witnesses) LOOP
  IF (SELECT count(*) FROM jsonb_object_keys(v_w))<>10 OR
   (SELECT count(*) FROM jsonb_object_keys(v_w) k WHERE k=ANY(ARRAY[
    'witness_key','body_key','provider','file_key','content_digest',
    'period_start','period_end','captured_at','record_type','certainty']))<>10
  THEN RAISE EXCEPTION 'Exact witness fields required' USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_intake_witnesses_v3
   (packet_id,witness_key,body_key,provider,file_key,content_digest,
    period_start,period_end,captured_at,record_type,certainty)
  VALUES(v_id,v_w->>'witness_key',v_w->>'body_key',v_w->>'provider',
   v_w->>'file_key',v_w->>'content_digest',(v_w->>'period_start')::date,
   (v_w->>'period_end')::date,(v_w->>'captured_at')::timestamptz,
   v_w->>'record_type',v_w->>'certainty');
 END LOOP;
 FOR v_i IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  IF (SELECT count(*) FROM jsonb_object_keys(v_i))<>10 OR
   (SELECT count(*) FROM jsonb_object_keys(v_i) k WHERE k=ANY(ARRAY[
    'item_key','witness_key','body_key','economic_key','item_digest',
    'claim_kind','claim_state','amount','currency','knowledge_on']))<>10
  THEN RAISE EXCEPTION 'Exact item fields required' USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_intake_items_v3
   (packet_id,item_key,witness_key,body_key,economic_key,item_digest,
    claim_kind,claim_state,amount,currency,knowledge_on)
  VALUES(v_id,v_i->>'item_key',v_i->>'witness_key',v_i->>'body_key',
   v_i->>'economic_key',v_i->>'item_digest',v_i->>'claim_kind',
   v_i->>'claim_state',(v_i->>'amount')::numeric,v_i->>'currency',
   (v_i->>'knowledge_on')::date);
 END LOOP;
 IF EXISTS(SELECT 1 FROM us.carry_intake_items_v3 i
  JOIN us.carry_intake_witnesses_v3 w ON w.packet_id=i.packet_id AND w.witness_key=i.witness_key
  WHERE i.packet_id=v_id AND (i.body_key<>w.body_key OR i.knowledge_on<w.captured_at::date
   OR (i.claim_kind='cash' AND i.claim_state='held'
       AND (w.certainty<>'original' OR w.record_type<>'statement'))))
 THEN RAISE EXCEPTION 'Unproved intake claim' USING ERRCODE='22023'; END IF;
 SELECT count(*) INTO v_count FROM us.carry_intake_items_v3 WHERE packet_id=v_id;
 RETURN jsonb_build_object('packet_id',v_id,'item_count',v_count,
  'replayed',false,'canonical_event_created',false);
END $fn$;

CREATE FUNCTION us.carry_decide_intake_item_v3(
 p_owner uuid,p_packet uuid,p_item_key text,p_item_digest text,
 p_decision_key text,p_choice text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_intake_packets_v3%ROWTYPE;
 v_i us.carry_intake_items_v3%ROWTYPE;v_d us.carry_intake_decisions_v3%ROWTYPE;
BEGIN
 SELECT * INTO v_p FROM us.carry_intake_packets_v3 WHERE id=p_packet AND owner_auth_user_id=p_owner FOR UPDATE;
 IF v_p.id IS NULL OR us.carry_live_canonical_person_v3(p_owner) IS DISTINCT FROM v_p.owner_person_entity_id
 THEN RAISE EXCEPTION 'Current packet owner required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_i FROM us.carry_intake_items_v3 WHERE packet_id=p_packet AND item_key=p_item_key;
 IF v_i.item_key IS NULL OR v_i.item_digest IS DISTINCT FROM p_item_digest
 THEN RAISE EXCEPTION 'Exact item unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_d FROM us.carry_intake_decisions_v3 WHERE packet_id=p_packet AND item_key=p_item_key;
 IF v_d.item_key IS NOT NULL THEN
  IF v_d.owner_auth_user_id IS DISTINCT FROM p_owner OR v_d.decision_key IS DISTINCT FROM p_decision_key
   OR v_d.expected_item_digest IS DISTINCT FROM p_item_digest OR v_d.choice IS DISTINCT FROM p_choice
   OR v_d.reason IS DISTINCT FROM p_reason
  THEN RAISE EXCEPTION 'Different item decision already recorded' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('packet_id',p_packet,'item_key',p_item_key,'choice',p_choice,'replayed',true);
 END IF;
 INSERT INTO us.carry_intake_decisions_v3(packet_id,item_key,owner_auth_user_id,
  decision_key,expected_item_digest,choice,reason)
 VALUES(p_packet,p_item_key,p_owner,p_decision_key,p_item_digest,p_choice,p_reason);
 RETURN jsonb_build_object('packet_id',p_packet,'item_key',p_item_key,'choice',p_choice,
  'replayed',false,'canonical_event_created',false);
END $fn$;

CREATE FUNCTION us.carry_intake_review_state_v3(p_owner uuid,p_packet uuid)
 RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_intake_packets_v3%ROWTYPE;v_total integer;v_decided integer;v_blocked integer;
BEGIN
 SELECT * INTO v_p FROM us.carry_intake_packets_v3 WHERE id=p_packet AND owner_auth_user_id=p_owner;
 IF v_p.id IS NULL OR us.carry_live_canonical_person_v3(p_owner) IS DISTINCT FROM v_p.owner_person_entity_id
 THEN RAISE EXCEPTION 'Current packet owner required' USING ERRCODE='42501'; END IF;
 SELECT count(*),count(d.item_key),count(*) FILTER(WHERE i.claim_state='unknown'
  OR d.choice IS DISTINCT FROM 'accept') INTO v_total,v_decided,v_blocked
 FROM us.carry_intake_items_v3 i LEFT JOIN us.carry_intake_decisions_v3 d
  ON d.packet_id=i.packet_id AND d.item_key=i.item_key WHERE i.packet_id=p_packet;
 RETURN jsonb_build_object('packet_id',p_packet,'item_count',v_total,
  'decided_count',v_decided,'ready_for_independent_adoption',v_total>0
   AND v_total=v_decided AND v_blocked=0,'canonical_event_created',false);
END $fn$;
REVOKE ALL ON FUNCTION
 us.carry_stage_intake_v3(uuid,uuid,text,text,jsonb,jsonb),
 us.carry_decide_intake_item_v3(uuid,uuid,text,text,text,text,text),
 us.carry_intake_review_state_v3(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION
 us.carry_stage_intake_v3(uuid,uuid,text,text,jsonb,jsonb),
 us.carry_decide_intake_item_v3(uuid,uuid,text,text,text,text,text),
 us.carry_intake_review_state_v3(uuid,uuid) TO us_carry_backend;
COMMIT;
