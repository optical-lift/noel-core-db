-- Source-only Atlas Build 1 candidate. Do not apply directly to production.
-- One author controls private drafts and reviewed immutable versions.
-- No recipient, offer, measurement, execution, or Clock authority.
BEGIN;

CREATE TABLE atlas.personal_training_programs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 author_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 draft_packet jsonb NOT NULL,
 draft_revision integer NOT NULL DEFAULT 1 CHECK (draft_revision >= 1),
 create_request_key text NOT NULL CHECK (length(create_request_key) BETWEEN 8 AND 160),
 create_packet_digest text NOT NULL CHECK (create_packet_digest ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (owner_principal_id,create_request_key)
);
CREATE INDEX personal_training_programs_author_idx
 ON atlas.personal_training_programs(owner_principal_id,updated_at DESC,id DESC);
CREATE TABLE atlas.personal_training_program_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id) ON DELETE RESTRICT,
 version_number integer NOT NULL CHECK(version_number >= 1),
 approved_draft_revision integer NOT NULL CHECK(approved_draft_revision >= 1),
 approved_packet jsonb NOT NULL,
 packet_digest text NOT NULL CHECK(packet_digest ~ '^[a-f0-9]{64}$'),
 reviewer_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 approval_request_key text NOT NULL CHECK(length(approval_request_key) BETWEEN 8 AND 160),
 approved_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(program_id,version_number),
 UNIQUE(program_id,approved_draft_revision),
 UNIQUE(program_id,approval_request_key)
);

CREATE TABLE atlas.personal_training_program_edit_receipts (
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id) ON DELETE RESTRICT,
 request_key text NOT NULL CHECK(length(request_key) BETWEEN 8 AND 160),
 expected_revision integer NOT NULL CHECK(expected_revision >= 1),
 resulting_revision integer NOT NULL CHECK(resulting_revision > expected_revision),
 packet_digest text NOT NULL CHECK(packet_digest ~ '^[a-f0-9]{64}$'),
 saved_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(program_id,request_key)
);

CREATE FUNCTION atlas.personal_training_version_immutable_v1() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
 RAISE EXCEPTION 'Approved Program versions are immutable' USING ERRCODE='55000';
END;
$fn$;
CREATE TRIGGER personal_training_version_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.personal_training_program_versions
 FOR EACH ROW EXECUTE FUNCTION atlas.personal_training_version_immutable_v1();

ALTER TABLE atlas.personal_training_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.personal_training_program_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.personal_training_program_edit_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_training_programs,atlas.personal_training_program_versions,atlas.personal_training_program_edit_receipts
 FROM PUBLIC,anon,authenticated;

-- This verifies author source shape, NOT source authenticity, safety,
-- clinical correctness, or equivalence among alternatives.
CREATE FUNCTION atlas.personal_training_validate_author_packet_v1(p_packet jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE
 v_source jsonb; v_component jsonb; v_alt jsonb; v_key text;
 v_keys text[] := ARRAY[]::text[];
 v_component_keys text[] := ARRAY[]::text[];
 v_alternative_keys text[]; v_item text;
BEGIN
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

-- Auth and access are resolved on the server. Caller never supplies Principal ID.
CREATE FUNCTION atlas.personal_training_author_guard_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path=pg_catalog,atlas,auth AS $fn$
DECLARE v_principal uuid; v_access jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign-in required' USING ERRCODE='42501'; END IF;
 v_principal := atlas.current_principal_id_v1();
 v_access := atlas.personal_atlas_access_status_self_api_v1();
 IF v_principal IS NULL OR (v_access->>'eligible')::boolean IS DISTINCT FROM true
   OR (v_access->>'hasPrincipal')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Established Personal Atlas required' USING ERRCODE='42501'; END IF;
 RETURN v_principal;
END;
$fn$;

CREATE FUNCTION atlas.personal_training_author_create_self_api_v1(p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path=pg_catalog,atlas,auth,extensions AS $fn$
DECLARE v_principal uuid; v_row atlas.personal_training_programs%ROWTYPE;
 v_receipt atlas.personal_training_program_edit_receipts%ROWTYPE; v_digest text;
BEGIN
 v_principal := atlas.personal_training_author_guard_v1();
 PERFORM atlas.personal_training_validate_author_packet_v1(p_packet);
 IF length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Invalid request key' USING ERRCODE='22023'; END IF;
 v_digest := encode(extensions.digest(p_packet::text,'sha256'),'hex');
 INSERT INTO atlas.personal_training_programs
  (owner_principal_id,author_auth_user_id,draft_packet,create_request_key,create_packet_digest)
 VALUES(v_principal,auth.uid(),p_packet,p_request_key,v_digest)
 ON CONFLICT(owner_principal_id,create_request_key) DO NOTHING;
 SELECT * INTO v_row FROM atlas.personal_training_programs
  WHERE owner_principal_id=v_principal AND create_request_key=p_request_key FOR UPDATE;
 IF v_row.id IS NULL OR v_row.create_packet_digest<>v_digest
 THEN RAISE EXCEPTION 'Create request conflict' USING ERRCODE='23505'; END IF;
 RETURN jsonb_build_object('ok',true,'programId',v_row.id,'draftRevision',v_row.draft_revision,
   'packetDigest',encode(extensions.digest(v_row.draft_packet::text,'sha256'),'hex'),
   'standing','author_draft');
END;
$fn$;

CREATE FUNCTION atlas.personal_training_author_save_self_api_v1(
 p_program_id uuid,p_expected_revision integer,p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path=pg_catalog,atlas,auth,extensions AS $fn$
DECLARE v_principal uuid; v_row atlas.personal_training_programs%ROWTYPE; v_digest text;
BEGIN
 v_principal := atlas.personal_training_author_guard_v1();
 PERFORM atlas.personal_training_validate_author_packet_v1(p_packet);
 IF length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Invalid request key' USING ERRCODE='22023'; END IF;
 v_digest := encode(extensions.digest(p_packet::text,'sha256'),'hex');
 SELECT * INTO v_row FROM atlas.personal_training_programs
  WHERE id=p_program_id AND owner_principal_id=v_principal FOR UPDATE;
 IF v_row.id IS NULL THEN RAISE EXCEPTION 'Program unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_receipt FROM atlas.personal_training_program_edit_receipts
 WHERE program_id=p_program_id AND request_key=p_request_key;
 IF v_receipt.program_id IS NOT NULL THEN
  IF v_receipt.packet_digest IS DISTINCT FROM v_digest
    OR v_receipt.expected_revision IS DISTINCT FROM p_expected_revision
  THEN RAISE EXCEPTION 'Edit request conflict' USING ERRCODE='23505'; END IF;
  IF v_row.draft_revision IS DISTINCT FROM v_receipt.resulting_revision
  THEN RAISE EXCEPTION 'Historical edit replay cannot replace current draft' USING ERRCODE='40001'; END IF;
  RETURN jsonb_build_object('ok',true,'programId',v_row.id,'draftRevision',v_receipt.resulting_revision,
   'packetDigest',v_receipt.packet_digest,'standing','author_draft','replay',true);
 END IF;
 IF p_expected_revision IS DISTINCT FROM v_row.draft_revision
 THEN RAISE EXCEPTION 'Stale draft revision' USING ERRCODE='40001'; END IF;
 UPDATE atlas.personal_training_programs SET
  draft_packet=p_packet,draft_revision=draft_revision+1,updated_at=now()
  WHERE id=p_program_id RETURNING * INTO v_row;
 INSERT INTO atlas.personal_training_program_edit_receipts
 (program_id,request_key,expected_revision,resulting_revision,packet_digest)
 VALUES(p_program_id,p_request_key,p_expected_revision,v_row.draft_revision,v_digest);
 RETURN jsonb_build_object('ok',true,'programId',v_row.id,'draftRevision',v_row.draft_revision,
   'packetDigest',v_digest,'standing','author_draft');
END;
$fn$;

CREATE FUNCTION atlas.personal_training_author_approve_self_api_v1(
 p_program_id uuid,p_expected_revision integer,p_expected_digest text,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path=pg_catalog,atlas,auth,extensions AS $fn$
DECLARE v_principal uuid; v_row atlas.personal_training_programs%ROWTYPE;
 v_old atlas.personal_training_program_versions%ROWTYPE;
 v_ver atlas.personal_training_program_versions%ROWTYPE; v_digest text; v_next integer;
BEGIN
 v_principal := atlas.personal_training_author_guard_v1();
 IF length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Invalid approval request key' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_row FROM atlas.personal_training_programs
  WHERE id=p_program_id AND owner_principal_id=v_principal FOR UPDATE;
 IF v_row.id IS NULL THEN RAISE EXCEPTION 'Program unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM atlas.personal_training_program_versions
  WHERE program_id=p_program_id AND approval_request_key=p_request_key;
 IF v_old.id IS NOT NULL THEN
  IF v_old.approved_draft_revision IS DISTINCT FROM p_expected_revision
    OR v_old.packet_digest IS DISTINCT FROM p_expected_digest
  THEN RAISE EXCEPTION 'Approval request conflict' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'programId',p_program_id,'versionId',v_old.id,
   'versionNumber',v_old.version_number,'packetDigest',v_old.packet_digest,
   'standing','author_reviewed','replay',true);
 END IF;
 IF p_expected_revision IS DISTINCT FROM v_row.draft_revision
 THEN RAISE EXCEPTION 'Stale reviewed source' USING ERRCODE='40001'; END IF;
 PERFORM atlas.personal_training_validate_author_packet_v1(v_row.draft_packet);
 v_digest := encode(extensions.digest(v_row.draft_packet::text,'sha256'),'hex');
 IF p_expected_digest IS DISTINCT FROM v_digest
 THEN RAISE EXCEPTION 'Reviewed content digest mismatch' USING ERRCODE='40001'; END IF;
 SELECT * INTO v_old FROM atlas.personal_training_program_versions
  WHERE program_id=p_program_id AND approved_draft_revision=v_row.draft_revision;
 IF v_old.id IS NOT NULL THEN
  RETURN jsonb_build_object('ok',true,'programId',p_program_id,'versionId',v_old.id,
   'versionNumber',v_old.version_number,'packetDigest',v_old.packet_digest,
   'standing','author_reviewed','replay',true);
 END IF;
 SELECT coalesce(max(version_number),0)+1 INTO v_next FROM atlas.personal_training_program_versions
  WHERE program_id=p_program_id;
 INSERT INTO atlas.personal_training_program_versions
  (program_id,version_number,approved_draft_revision,approved_packet,packet_digest,
   reviewer_auth_user_id,approval_request_key)
 VALUES(p_program_id,v_next,v_row.draft_revision,v_row.draft_packet,v_digest,auth.uid(),p_request_key)
 RETURNING * INTO v_ver;
 RETURN jsonb_build_object('ok',true,'programId',p_program_id,'versionId',v_ver.id,
  'versionNumber',v_ver.version_number,'packetDigest',v_ver.packet_digest,'standing','author_reviewed');
END;
$fn$;

CREATE FUNCTION atlas.personal_training_author_read_self_api_v1(p_program_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,atlas,auth AS $fn$
DECLARE v_principal uuid; v_row atlas.personal_training_programs%ROWTYPE;
 v_versions jsonb; v_programs jsonb;
BEGIN
 v_principal := atlas.personal_training_author_guard_v1();
 IF p_program_id IS NULL THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('programId',id,'title',draft_packet->>'title',
   'draftRevision',draft_revision,'updatedAt',updated_at)
   ORDER BY updated_at DESC,id DESC),'[]'::jsonb) INTO v_programs
  FROM (SELECT id,draft_packet,draft_revision,updated_at FROM atlas.personal_training_programs
    WHERE owner_principal_id=v_principal ORDER BY updated_at DESC,id DESC LIMIT 100) t;
  RETURN jsonb_build_object('ok',true,'items',v_programs,'coverage','latest_100_author_owned');
 END IF;
 SELECT * INTO v_row FROM atlas.personal_training_programs
  WHERE id=p_program_id AND owner_principal_id=v_principal;
 IF v_row.id IS NULL THEN RAISE EXCEPTION 'Program unavailable' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('versionId',id,'versionNumber',version_number,
   'approvedRevision',approved_draft_revision,'packet',approved_packet,
   'packetDigest',packet_digest,'approvedAt',approved_at)
   ORDER BY version_number DESC),'[]'::jsonb) INTO v_versions
 FROM atlas.personal_training_program_versions WHERE program_id=v_row.id;
 RETURN jsonb_build_object('ok',true,'programId',v_row.id,'draftRevision',v_row.draft_revision,
  'draftPacket',v_row.draft_packet,
  'draftDigest',encode(extensions.digest(v_row.draft_packet::text,'sha256'),'hex'),
  'versions',v_versions,'standing','author_private');
END;
$fn$;

-- Only four governed public wrappers are callable by an authenticated author.
CREATE FUNCTION public.personal_training_author_create_self_api_v1(p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $fn$
 SELECT atlas.personal_training_author_create_self_api_v1(p_packet,p_request_key);
$fn$;
CREATE FUNCTION public.personal_training_author_save_self_api_v1(
 p_program_id uuid,p_expected_revision integer,p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $fn$
 SELECT atlas.personal_training_author_save_self_api_v1(p_program_id,p_expected_revision,p_packet,p_request_key);
$fn$;
CREATE FUNCTION public.personal_training_author_approve_self_api_v1(
 p_program_id uuid,p_expected_revision integer,p_expected_digest text,p_request_key text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $fn$
 SELECT atlas.personal_training_author_approve_self_api_v1(p_program_id,p_expected_revision,p_expected_digest,p_request_key);
$fn$;
CREATE FUNCTION public.personal_training_author_read_self_api_v1(p_program_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT atlas.personal_training_author_read_self_api_v1(p_program_id);
$fn$;

REVOKE ALL ON FUNCTION
 atlas.personal_training_validate_author_packet_v1(jsonb),
 atlas.personal_training_author_guard_v1(),
 atlas.personal_training_author_create_self_api_v1(jsonb,text),
 atlas.personal_training_author_save_self_api_v1(uuid,integer,jsonb,text),
 atlas.personal_training_author_approve_self_api_v1(uuid,integer,text,text),
 atlas.personal_training_author_read_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION
 public.personal_training_author_create_self_api_v1(jsonb,text),
 public.personal_training_author_save_self_api_v1(uuid,integer,jsonb,text),
 public.personal_training_author_approve_self_api_v1(uuid,integer,text,text),
 public.personal_training_author_read_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.personal_training_author_create_self_api_v1(jsonb,text),
 public.personal_training_author_save_self_api_v1(uuid,integer,jsonb,text),
 public.personal_training_author_approve_self_api_v1(uuid,integer,text,text),
 public.personal_training_author_read_self_api_v1(uuid)
 TO authenticated;
COMMIT;
