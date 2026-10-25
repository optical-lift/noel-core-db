-- Atlas universal authored Program packet v2 (source-only candidate, do not run live).
-- Source/draft/approval share the released single Program tables.

-- Atlas domain: single existing Program record authority; no parallel Program store.
-- This candidate extends the released training-domain author packet with a general
-- typed author-source v2 packet while preserving v1 validation and stored history.
BEGIN;

CREATE FUNCTION atlas.personal_program_validate_quantity_v2(p_q jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
 IF p_q IS NULL OR jsonb_typeof(p_q)<>'object'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_q) k
    WHERE k NOT IN ('key','value','unit','comparison','standing'))
  OR length(btrim(coalesce(p_q->>'key',''))) NOT BETWEEN 1 AND 120
  OR length(btrim(coalesce(p_q->>'unit',''))) NOT BETWEEN 1 AND 80
  OR coalesce(p_q->>'comparison','') NOT IN
    ('exact','range_min','range_max','at_least','at_most')
  OR p_q->>'standing' IS DISTINCT FROM 'author_intent'
  OR jsonb_typeof(p_q->'value') IS DISTINCT FROM 'number'
  OR (p_q->>'value')::numeric<0
 THEN RAISE EXCEPTION 'Invalid intended numeric quantity' USING ERRCODE='22023'; END IF;
END;
$fn$;

CREATE FUNCTION atlas.personal_program_validate_author_packet_v2(p_packet jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE
 v_source jsonb; v_goal jsonb; v_component jsonb; v_alt jsonb;
 v_q jsonb; v_correction jsonb; v_ref jsonb; v_f jsonb; v_w jsonb;
 v_keys text[] := ARRAY[]::text[];
 v_goals text[] := ARRAY[]::text[];
 v_components text[] := ARRAY[]::text[];
 v_corrections text[] := ARRAY[]::text[];
 v_alts text[];
 v_n integer;
BEGIN
 IF p_packet IS NULL OR jsonb_typeof(p_packet)<>'object'
  OR octet_length(p_packet::text)>250000
  OR p_packet->>'contract' IS DISTINCT FROM 'personal_program_author_source_v2'
  OR p_packet->>'approvalStanding' IS DISTINCT FROM 'draft_requires_governed_human_review'
  OR length(btrim(coalesce(p_packet->>'title',''))) NOT BETWEEN 3 AND 160
  OR length(btrim(coalesce(p_packet->>'purpose',''))) NOT BETWEEN 3 AND 1600
  OR length(btrim(coalesce(p_packet->>'domain',''))) NOT BETWEEN 1 AND 100
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_packet) k WHERE k NOT IN
    ('contract','title','purpose','domain','sources','goals','components','reconciliations','approvalStanding'))
 THEN RAISE EXCEPTION 'Invalid universal author packet' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_packet->'sources') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_packet->'goals') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_packet->'components') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_packet->'reconciliations') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Universal source collections are required' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_packet->'sources') NOT BETWEEN 1 AND 100
   OR jsonb_array_length(p_packet->'goals')>100
   OR jsonb_array_length(p_packet->'components') NOT BETWEEN 1 AND 300
   OR jsonb_array_length(p_packet->'reconciliations')>200
 THEN RAISE EXCEPTION 'Universal packet collection bounds exceeded' USING ERRCODE='22023'; END IF;
 FOR v_source IN SELECT value FROM jsonb_array_elements(p_packet->'sources') LOOP
  IF jsonb_typeof(v_source)<>'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_source) k WHERE k NOT IN
       ('key','title','locator','sha256','disclosure'))
   OR length(btrim(coalesce(v_source->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_source->>'title',''))) NOT BETWEEN 1 AND 240
   OR length(btrim(coalesce(v_source->>'locator',''))) NOT BETWEEN 1 AND 1600
   OR coalesce(v_source->>'sha256','') !~ '^[a-f0-9]{64}$'
   OR coalesce(v_source->>'disclosure','') NOT IN ('author_private','proposed_disclosure')
  THEN RAISE EXCEPTION 'Invalid source manifest' USING ERRCODE='22023'; END IF;
  IF v_source->>'key'=ANY(v_keys)
  THEN RAISE EXCEPTION 'Duplicate source identity' USING ERRCODE='22023'; END IF;
  v_keys:=array_append(v_keys,v_source->>'key');
 END LOOP;
 FOR v_goal IN SELECT value FROM jsonb_array_elements(p_packet->'goals') LOOP
  IF jsonb_typeof(v_goal)<>'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_goal) k WHERE k NOT IN
       ('key','label','successCriterion','sourceKeys','quantity'))
   OR length(btrim(coalesce(v_goal->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_goal->>'label',''))) NOT BETWEEN 1 AND 200
   OR length(btrim(coalesce(v_goal->>'successCriterion',''))) NOT BETWEEN 1 AND 1800
   OR jsonb_typeof(v_goal->'sourceKeys') IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'Invalid intended goal' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(v_goal->'sourceKeys') NOT BETWEEN 1 AND 100
  THEN RAISE EXCEPTION 'Goal source identity required' USING ERRCODE='22023'; END IF;
  FOR v_ref IN SELECT value FROM jsonb_array_elements(v_goal->'sourceKeys') LOOP
   IF jsonb_typeof(v_ref)<>'string' OR v_ref #>> '{}' <> ALL(v_keys)
   THEN RAISE EXCEPTION 'Unknown goal source identity' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF v_goal->'quantity' IS NOT NULL AND v_goal->'quantity'<>'null'::jsonb THEN
   PERFORM atlas.personal_program_validate_quantity_v2(v_goal->'quantity');
  END IF;
  IF v_goal->>'key'=ANY(v_goals)
  THEN RAISE EXCEPTION 'Duplicate intended goal' USING ERRCODE='22023'; END IF;
  v_goals:=array_append(v_goals,v_goal->>'key');
 END LOOP;
 FOR v_component IN SELECT value FROM jsonb_array_elements(p_packet->'components') LOOP
  IF jsonb_typeof(v_component)<>'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_component) k WHERE k NOT IN
       ('key','kind','label','instructions','sourceKeys','sourceExcerpt',
        'function','window','quantities','prerequisites','alternatives','optional'))
   OR length(btrim(coalesce(v_component->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_component->>'label',''))) NOT BETWEEN 3 AND 200
   OR length(btrim(coalesce(v_component->>'instructions',''))) NOT BETWEEN 3 AND 8000
   OR length(btrim(coalesce(v_component->>'sourceExcerpt',''))) NOT BETWEEN 3 AND 8000
   OR coalesce(v_component->>'kind','') NOT IN ('action','observation','decision','review','reference')
   OR jsonb_typeof(v_component->'sourceKeys') IS DISTINCT FROM 'array'
   OR jsonb_typeof(v_component->'function') IS DISTINCT FROM 'object'
   OR jsonb_typeof(v_component->'window') IS DISTINCT FROM 'object'
   OR jsonb_typeof(v_component->'quantities') IS DISTINCT FROM 'array'
   OR jsonb_typeof(v_component->'prerequisites') IS DISTINCT FROM 'array'
   OR jsonb_typeof(v_component->'alternatives') IS DISTINCT FROM 'array'
   OR jsonb_typeof(v_component->'optional') IS DISTINCT FROM 'boolean'
  THEN RAISE EXCEPTION 'Invalid source-derived component' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(v_component->'sourceKeys') NOT BETWEEN 1 AND 100
   OR jsonb_array_length(v_component->'quantities')>30
   OR jsonb_array_length(v_component->'prerequisites')>30
   OR jsonb_array_length(v_component->'alternatives')>30
  THEN RAISE EXCEPTION 'Component list bounds exceeded' USING ERRCODE='22023'; END IF;
  FOR v_ref IN SELECT value FROM jsonb_array_elements(v_component->'sourceKeys') LOOP
   IF jsonb_typeof(v_ref)<>'string' OR v_ref #>> '{}' <> ALL(v_keys)
   THEN RAISE EXCEPTION 'Unknown component source identity' USING ERRCODE='22023'; END IF;
  END LOOP;
  v_f:=v_component->'function';
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_f) k WHERE k NOT IN ('key','intendedChange','standing'))
   OR length(btrim(coalesce(v_f->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_f->>'intendedChange',''))) NOT BETWEEN 3 AND 1200
   OR v_f->>'standing' IS DISTINCT FROM 'author_intent'
  THEN RAISE EXCEPTION 'Function is an explicit author intention, not verified mechanism' USING ERRCODE='22023'; END IF;
  v_w:=v_component->'window';
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_w) k WHERE k NOT IN
     ('kind','start','end','timezone','note'))
   OR coalesce(v_w->>'kind','') NOT IN ('unscheduled','date_range','relative')
   OR length(btrim(coalesce(v_w->>'note',''))) NOT BETWEEN 1 AND 1000
  THEN RAISE EXCEPTION 'Invalid authored time window' USING ERRCODE='22023'; END IF;
  IF v_w->>'kind'='date_range' THEN
   IF coalesce(v_w->>'start','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OR coalesce(v_w->>'end','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OR (v_w->>'start') > (v_w->>'end')
    OR length(btrim(coalesce(v_w->>'timezone',''))) NOT BETWEEN 1 AND 120
   THEN RAISE EXCEPTION 'Date window requires explicitly ordered local dates and timezone' USING ERRCODE='22023'; END IF;
  ELSIF v_w->'start' IS DISTINCT FROM 'null'::jsonb
    OR v_w->'end' IS DISTINCT FROM 'null'::jsonb
  THEN RAISE EXCEPTION 'Unscheduled windows cannot imply exact dates' USING ERRCODE='22023'; END IF;
  FOR v_q IN SELECT value FROM jsonb_array_elements(v_component->'quantities') LOOP
   PERFORM atlas.personal_program_validate_quantity_v2(v_q);
  END LOOP;
  FOR v_ref IN SELECT value FROM jsonb_array_elements(v_component->'prerequisites') LOOP
   IF jsonb_typeof(v_ref)<>'string'
    OR length(btrim(v_ref #>> '{}')) NOT BETWEEN 1 AND 1000
   THEN RAISE EXCEPTION 'Invalid prerequisite' USING ERRCODE='22023'; END IF;
  END LOOP;
  v_alts:=ARRAY[]::text[];
  FOR v_alt IN SELECT value FROM jsonb_array_elements(v_component->'alternatives') LOOP
   IF jsonb_typeof(v_alt)<>'object'
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_alt) k WHERE k NOT IN
      ('key','instructions','relation','authorApproved','rationale'))
    OR length(btrim(coalesce(v_alt->>'key',''))) NOT BETWEEN 1 AND 120
    OR length(btrim(coalesce(v_alt->>'instructions',''))) NOT BETWEEN 3 AND 8000
    OR length(btrim(coalesce(v_alt->>'rationale',''))) NOT BETWEEN 3 AND 1200
    OR coalesce(v_alt->>'relation','') NOT IN
      ('direct_author_claim','partial_author_claim','unresolved')
    OR jsonb_typeof(v_alt->'authorApproved') IS DISTINCT FROM 'boolean'
   THEN RAISE EXCEPTION 'Alternative is not an approved equivalence' USING ERRCODE='22023'; END IF;
   IF v_alt->>'key'=ANY(v_alts)
   THEN RAISE EXCEPTION 'Duplicate component alternative' USING ERRCODE='22023'; END IF;
   v_alts:=array_append(v_alts,v_alt->>'key');
  END LOOP;
  IF v_component->>'key'=ANY(v_components)
  THEN RAISE EXCEPTION 'Duplicate Program component key' USING ERRCODE='22023'; END IF;
  v_components:=array_append(v_components,v_component->>'key');
 END LOOP;
 FOR v_correction IN SELECT value FROM jsonb_array_elements(p_packet->'reconciliations') LOOP
  IF jsonb_typeof(v_correction)<>'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_correction) k WHERE k NOT IN
     ('key','sourceKey','candidateKey','line','field','from','to',
      'decision','rationale','originalExcerpt','authority'))
   OR length(btrim(coalesce(v_correction->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_correction->>'candidateKey',''))) NOT BETWEEN 1 AND 240
   OR length(btrim(coalesce(v_correction->>'from',''))) NOT BETWEEN 1 AND 4000
   OR length(btrim(coalesce(v_correction->>'to',''))) NOT BETWEEN 1 AND 4000
   OR length(btrim(coalesce(v_correction->>'rationale',''))) NOT BETWEEN 1 AND 1200
   OR length(btrim(coalesce(v_correction->>'originalExcerpt',''))) NOT BETWEEN 1 AND 8000
   OR v_correction->>'sourceKey' <> ALL(v_keys)
   OR coalesce(v_correction->>'field','') NOT IN
     ('instructions','label','function.intendedChange','window.start',
      'window.end','quantity.value','quantity.unit','goal.target')
   OR coalesce(v_correction->>'decision','') NOT IN ('resolved','open','not_applicable')
   OR v_correction->>'authority' IS DISTINCT FROM 'author_reconciliation_proposal'
   OR jsonb_typeof(v_correction->'line') IS DISTINCT FROM 'number'
   OR (v_correction->>'line')::integer<1
   OR strpos(coalesce(v_correction->>'originalExcerpt',''),
             coalesce(v_correction->>'from',''))=0
  THEN RAISE EXCEPTION 'Invalid author source reconciliation' USING ERRCODE='22023'; END IF;
  IF v_correction->>'key'=ANY(v_corrections)
  THEN RAISE EXCEPTION 'Duplicate author source reconciliation' USING ERRCODE='22023'; END IF;
  v_corrections:=array_append(v_corrections,v_correction->>'key');
 END LOOP;
END;
$fn$;

CREATE OR REPLACE FUNCTION atlas.personal_training_validate_author_packet_v1(p_packet jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE
 v_source jsonb; v_component jsonb; v_alt jsonb; v_key text;
 v_keys text[] := ARRAY[]::text[];
 v_component_keys text[] := ARRAY[]::text[];
 v_alternative_keys text[]; v_item text;
BEGIN
 IF p_packet->>'contract'='personal_program_author_source_v2' THEN
  PERFORM atlas.personal_program_validate_author_packet_v2(p_packet);
  RETURN;
 END IF;
 IF p_packet IS NULL OR jsonb_typeof(p_packet)<>'object'
  OR octet_length(p_packet::text)>250000
  OR p_packet->>'contract' IS DISTINCT FROM 'personal_training_program_author_source_v1'
  OR p_packet->>'approvalStanding' IS DISTINCT FROM 'draft_requires_governed_human_review'
  OR length(btrim(coalesce(p_packet->>'title',''))) NOT BETWEEN 3 AND 160
  OR length(btrim(coalesce(p_packet->>'purpose',''))) NOT BETWEEN 3 AND 1600
  OR jsonb_typeof(p_packet->'sources') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_packet->'sources') NOT BETWEEN 1 AND 100
  OR jsonb_typeof(p_packet->'components') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_packet->'components') NOT BETWEEN 1 AND 300
  OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_packet) k
             WHERE k NOT IN ('contract','title','purpose','sources','components','approvalStanding'))
 THEN RAISE EXCEPTION 'Invalid authored Program source shape' USING ERRCODE='22023'; END IF;
 FOR v_source IN SELECT value FROM jsonb_array_elements(p_packet->'sources') LOOP
  IF jsonb_typeof(v_source)<>'object'
   OR length(btrim(coalesce(v_source->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_source->>'locator',''))) NOT BETWEEN 3 AND 1600
   OR coalesce(v_source->>'disclosure','') NOT IN ('author_private','recipient_disclosed')
   OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_source) k
              WHERE k NOT IN ('key','locator','disclosure'))
  THEN RAISE EXCEPTION 'Invalid source manifest entry' USING ERRCODE='22023'; END IF;
  v_key := v_source->>'key';
  IF v_key=ANY(v_keys) THEN RAISE EXCEPTION 'Duplicate source key' USING ERRCODE='22023'; END IF;
  v_keys := array_append(v_keys,v_key);
 END LOOP;
 FOR v_component IN SELECT value FROM jsonb_array_elements(p_packet->'components') LOOP
  IF jsonb_typeof(v_component)<>'object'
   OR length(btrim(coalesce(v_component->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_component->>'label',''))) NOT BETWEEN 3 AND 200
   OR length(btrim(coalesce(v_component->>'instructions',''))) NOT BETWEEN 3 AND 8000
   OR coalesce(v_component->>'kind','') NOT IN ('session','method','capacity_test','review','reference')
   OR jsonb_typeof(v_component->'sourceKeys') IS DISTINCT FROM 'array'
   OR jsonb_array_length(v_component->'sourceKeys')<1
   OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_component->'sourceKeys') x WHERE jsonb_typeof(x.value)<>'string')
   OR jsonb_typeof(v_component->'function') IS DISTINCT FROM 'object'
   OR length(btrim(coalesce(v_component->'function'->>'key',''))) NOT BETWEEN 1 AND 120
   OR length(btrim(coalesce(v_component->'function'->>'intendedChange',''))) NOT BETWEEN 3 AND 1200
   OR jsonb_typeof(v_component->'alternatives') IS DISTINCT FROM 'array'
   OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_component) k
               WHERE k NOT IN ('key','kind','label','instructions','sourceKeys','function','alternatives'))
   OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_component->'function') k
               WHERE k NOT IN ('key','intendedChange'))
  THEN RAISE EXCEPTION 'Invalid Program component' USING ERRCODE='22023'; END IF;
  v_key := v_component->>'key';
  IF v_key=ANY(v_component_keys) THEN RAISE EXCEPTION 'Duplicate component key' USING ERRCODE='22023'; END IF;
  v_component_keys := array_append(v_component_keys,v_key);
  FOR v_item IN SELECT value #>> '{}' FROM jsonb_array_elements(v_component->'sourceKeys') LOOP
   IF v_item <> ALL(v_keys) OR v_item IS NULL
   THEN RAISE EXCEPTION 'Unknown component source reference' USING ERRCODE='22023'; END IF;
  END LOOP;
  v_alternative_keys := ARRAY[]::text[];
  FOR v_alt IN SELECT value FROM jsonb_array_elements(v_component->'alternatives') LOOP
   IF jsonb_typeof(v_alt)<>'object'
    OR length(btrim(coalesce(v_alt->>'key',''))) NOT BETWEEN 1 AND 120
    OR length(btrim(coalesce(v_alt->>'instructions',''))) NOT BETWEEN 3 AND 8000
    OR length(btrim(coalesce(v_alt->>'rationale',''))) NOT BETWEEN 3 AND 1200
    OR coalesce(v_alt->>'relation','') NOT IN ('direct_author_claim','partial_author_claim','unresolved')
    OR jsonb_typeof(v_alt->'authorApproved') IS DISTINCT FROM 'boolean'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_alt) k
              WHERE k NOT IN ('key','instructions','rationale','relation','authorApproved'))
   THEN RAISE EXCEPTION 'Invalid alternative source statement' USING ERRCODE='22023'; END IF;
   IF v_alt->>'key'=ANY(v_alternative_keys)
   THEN RAISE EXCEPTION 'Duplicate alternative key' USING ERRCODE='22023'; END IF;
   v_alternative_keys := array_append(v_alternative_keys,v_alt->>'key');
  END LOOP;
 END LOOP;
END;
$fn$;


-- The v2 membrane uses the SAME v1 canonical authored Program tables, edit
-- receipts and immutable version writer. No Program-store duplication.
CREATE FUNCTION public.personal_program_author_create_self_api_v2(p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 PERFORM atlas.personal_program_validate_author_packet_v2(p_packet);
 RETURN atlas.personal_training_author_create_self_api_v1(p_packet,p_request_key);
END;
$fn$;

CREATE FUNCTION public.personal_program_author_save_self_api_v2(
 p_program_id uuid,p_expected_revision integer,p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_existing jsonb;
BEGIN
 PERFORM atlas.personal_program_validate_author_packet_v2(p_packet);
 v_existing:=atlas.personal_training_author_read_self_api_v1(p_program_id);
 IF v_existing->'draftPacket'->>'contract' IS DISTINCT FROM 'personal_program_author_source_v2'
 THEN RAISE EXCEPTION 'Program unavailable for v2 edit' USING ERRCODE='42501'; END IF;
 RETURN atlas.personal_training_author_save_self_api_v1(
   p_program_id,p_expected_revision,p_packet,p_request_key);
END;
$fn$;

CREATE FUNCTION public.personal_program_author_approve_self_api_v2(
 p_program_id uuid,p_expected_revision integer,p_expected_digest text,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_existing jsonb;
BEGIN
 v_existing:=atlas.personal_training_author_read_self_api_v1(p_program_id);
 IF v_existing->'draftPacket'->>'contract' IS DISTINCT FROM 'personal_program_author_source_v2'
 THEN RAISE EXCEPTION 'Program unavailable for v2 approval' USING ERRCODE='42501'; END IF;
 RETURN atlas.personal_training_author_approve_self_api_v1(
   p_program_id,p_expected_revision,p_expected_digest,p_request_key);
END;
$fn$;

CREATE FUNCTION public.personal_program_author_read_self_api_v2(p_program_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_principal uuid; v_rows jsonb; v_details jsonb;
BEGIN
 v_principal:=atlas.personal_training_author_guard_v1();
 IF p_program_id IS NULL THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'programId',id,'title',draft_packet->>'title','draftRevision',draft_revision,
    'updatedAt',updated_at) ORDER BY updated_at DESC,id DESC),'[]'::jsonb)
  INTO v_rows FROM (SELECT id,draft_packet,draft_revision,updated_at
     FROM atlas.personal_training_programs
     WHERE owner_principal_id=v_principal
       AND draft_packet->>'contract'='personal_program_author_source_v2'
     ORDER BY updated_at DESC,id DESC LIMIT 100) t;
  RETURN jsonb_build_object('ok',true,'items',v_rows,'coverage','latest_100_author_owned_v2');
 END IF;
 v_details:=atlas.personal_training_author_read_self_api_v1(p_program_id);
 IF v_details->'draftPacket'->>'contract' IS DISTINCT FROM 'personal_program_author_source_v2'
 THEN RAISE EXCEPTION 'Program unavailable for v2 read' USING ERRCODE='42501'; END IF;
 RETURN v_details;
END;
$fn$;

REVOKE ALL ON FUNCTION atlas.personal_program_validate_quantity_v2(jsonb),
 atlas.personal_program_validate_author_packet_v2(jsonb),
 public.personal_program_author_create_self_api_v2(jsonb,text),
 public.personal_program_author_save_self_api_v2(uuid,integer,jsonb,text),
 public.personal_program_author_approve_self_api_v2(uuid,integer,text,text),
 public.personal_program_author_read_self_api_v2(uuid)
 FROM PUBLIC,anon,authenticated;

GRANT EXECUTE ON FUNCTION
 public.personal_program_author_create_self_api_v2(jsonb,text),
 public.personal_program_author_save_self_api_v2(uuid,integer,jsonb,text),
 public.personal_program_author_approve_self_api_v2(uuid,integer,text,text),
 public.personal_program_author_read_self_api_v2(uuid)
 TO authenticated;
COMMIT;
