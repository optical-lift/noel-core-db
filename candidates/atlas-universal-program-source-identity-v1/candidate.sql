-- Source-only: canonical v2 author Program source identity and deliberate forks.
-- Uses the EXISTING Program store; no new participant, task or evidence engine.
BEGIN;

CREATE TABLE atlas.personal_program_author_distinct_import_decisions (
 program_id uuid PRIMARY KEY REFERENCES atlas.personal_training_programs(id) ON DELETE RESTRICT,
 owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 author_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 rationale text NOT NULL CHECK(length(btrim(rationale)) BETWEEN 20 AND 1200),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE atlas.personal_program_author_source_receipts (
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id) ON DELETE RESTRICT,
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
 author_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(program_id,source_fingerprint)
);
CREATE INDEX personal_program_source_receipts_owner_idx
 ON atlas.personal_program_author_source_receipts(owner_principal_id,source_fingerprint);
ALTER TABLE atlas.personal_program_author_source_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_program_author_source_receipts
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER personal_program_source_receipts_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.personal_program_author_source_receipts
 FOR EACH ROW EXECUTE FUNCTION atlas.personal_training_history_immutable_v1();

CREATE INDEX personal_program_distinct_owner_idx
 ON atlas.personal_program_author_distinct_import_decisions
 (owner_principal_id,source_fingerprint);
ALTER TABLE atlas.personal_program_author_distinct_import_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_program_author_distinct_import_decisions
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER personal_program_distinct_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.personal_program_author_distinct_import_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.personal_training_history_immutable_v1();

CREATE FUNCTION atlas.personal_program_source_fingerprint_v1(p_sources jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,extensions AS $fn$
DECLARE v_hashes text;
BEGIN
 IF jsonb_typeof(p_sources) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_sources) NOT BETWEEN 1 AND 100
  OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_sources) s
    WHERE jsonb_typeof(s.value) IS DISTINCT FROM 'object'
      OR coalesce(s.value->>'sha256','') !~ '^[a-f0-9]{64}$')
 THEN RAISE EXCEPTION 'Source digests unavailable' USING ERRCODE='22023'; END IF;
 SELECT string_agg(DISTINCT s.value->>'sha256','|' ORDER BY s.value->>'sha256')
 INTO v_hashes FROM jsonb_array_elements(p_sources) s;
 RETURN encode(extensions.digest(v_hashes,'sha256'),'hex');
END;
$fn$;

-- Repeated imports match even after revisions change a draft, because
-- immutable approved source versions are also included in the search.
CREATE FUNCTION atlas.personal_program_same_sources_v1(
 p_owner uuid,p_fingerprint text)
RETURNS TABLE(program_id uuid,program_title text,first_created_at timestamptz)
LANGUAGE sql STABLE SET search_path=pg_catalog AS $fn$
 SELECT p.id,p.draft_packet->>'title',p.created_at
 FROM atlas.personal_training_programs p
 WHERE p.owner_principal_id=p_owner
 AND (
   (p.draft_packet->>'contract'='personal_program_author_source_v2'
    AND atlas.personal_program_source_fingerprint_v1(p.draft_packet->'sources')=p_fingerprint)
   OR EXISTS(
     SELECT 1 FROM atlas.personal_training_program_versions v
     WHERE v.program_id=p.id
       AND v.approved_packet->>'contract'='personal_program_author_source_v2'
       AND atlas.personal_program_source_fingerprint_v1(v.approved_packet->'sources')=p_fingerprint
   )
   OR EXISTS (
     SELECT 1 FROM atlas.personal_program_author_source_receipts r
     WHERE r.program_id=p.id
       AND r.owner_principal_id=p_owner
       AND r.source_fingerprint=p_fingerprint
   ))
 ORDER BY p.created_at,p.id;
$fn$;

CREATE OR REPLACE FUNCTION public.personal_program_author_create_self_api_v2(
 p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_owner uuid; v_fingerprint text; v_prior uuid; v_prior_key text;
 v_created jsonb;
BEGIN
 PERFORM atlas.personal_program_validate_author_packet_v2(p_packet);
 v_owner:=atlas.personal_training_author_guard_v1();
 v_fingerprint:=atlas.personal_program_source_fingerprint_v1(p_packet->'sources');
 -- Serialize the check and creation for identical author + source sets.
 PERFORM pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(v_owner::text||':'||v_fingerprint,0));
 SELECT p.id,p.create_request_key INTO v_prior,v_prior_key
 FROM atlas.personal_training_programs p
 JOIN atlas.personal_program_same_sources_v1(v_owner,v_fingerprint) d ON d.program_id=p.id
 ORDER BY p.created_at,p.id LIMIT 1;
 IF v_prior IS NOT NULL AND v_prior_key IS DISTINCT FROM p_request_key
 THEN RAISE EXCEPTION 'Same author source is already represented by a Program'
   USING ERRCODE='23505'; END IF;
 v_created:=atlas.personal_training_author_create_self_api_v1(p_packet,p_request_key);
 INSERT INTO atlas.personal_program_author_source_receipts
  (program_id,source_fingerprint,owner_principal_id,author_auth_user_id)
 VALUES ((v_created->>'programId')::uuid,v_fingerprint,v_owner,auth.uid())
 ON CONFLICT (program_id,source_fingerprint) DO NOTHING;
 RETURN v_created;
END;
$fn$;

-- Preserve original and later source identities even when an unapproved
-- draft replaces a source set. This is a receipt, not another Program record.
CREATE OR REPLACE FUNCTION public.personal_program_author_save_self_api_v2(
 p_program_id uuid,p_expected_revision integer,p_packet jsonb,p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_owner uuid; v_fingerprint text; v_saved jsonb;
BEGIN
 PERFORM atlas.personal_program_validate_author_packet_v2(p_packet);
 v_owner:=atlas.personal_training_author_guard_v1();
 v_saved:=atlas.personal_training_author_read_self_api_v1(p_program_id);
 IF v_saved->'draftPacket'->>'contract' IS DISTINCT FROM 'personal_program_author_source_v2'
 THEN RAISE EXCEPTION 'Program unavailable for v2 edit' USING ERRCODE='42501'; END IF;
 v_saved:=atlas.personal_training_author_save_self_api_v1(
   p_program_id,p_expected_revision,p_packet,p_request_key);
 v_fingerprint:=atlas.personal_program_source_fingerprint_v1(p_packet->'sources');
 INSERT INTO atlas.personal_program_author_source_receipts
  (program_id,source_fingerprint,owner_principal_id,author_auth_user_id)
 VALUES (p_program_id,v_fingerprint,v_owner,auth.uid())
 ON CONFLICT (program_id,source_fingerprint) DO NOTHING;
 RETURN v_saved;
END;
$fn$;

-- A genuinely distinct endeavor may start from identical sources, but only
-- via a separate, explicitly named act with an immutable author rationale.
CREATE FUNCTION public.personal_program_author_create_distinct_self_api_v1(
 p_packet jsonb,p_request_key text,p_rationale text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_owner uuid; v_fp text; v_created jsonb;
BEGIN
 PERFORM atlas.personal_program_validate_author_packet_v2(p_packet);
 IF length(btrim(coalesce(p_rationale,''))) NOT BETWEEN 20 AND 1200
 THEN RAISE EXCEPTION 'Distinct Program requires explicit author rationale'
  USING ERRCODE='22023'; END IF;
 v_owner:=atlas.personal_training_author_guard_v1();
 v_fp:=atlas.personal_program_source_fingerprint_v1(p_packet->'sources');
 v_created:=atlas.personal_training_author_create_self_api_v1(p_packet,p_request_key);
 INSERT INTO atlas.personal_program_author_source_receipts
  (program_id,source_fingerprint,owner_principal_id,author_auth_user_id)
 VALUES ((v_created->>'programId')::uuid,v_fp,v_owner,auth.uid())
 ON CONFLICT (program_id,source_fingerprint) DO NOTHING;
 INSERT INTO atlas.personal_program_author_distinct_import_decisions
  (program_id,owner_principal_id,author_auth_user_id,source_fingerprint,rationale)
 VALUES ((v_created->>'programId')::uuid,v_owner,auth.uid(),v_fp,p_rationale)
 ON CONFLICT (program_id) DO NOTHING;
 IF NOT EXISTS(
  SELECT 1 FROM atlas.personal_program_author_distinct_import_decisions
   WHERE program_id=(v_created->>'programId')::uuid
     AND owner_principal_id=v_owner AND source_fingerprint=v_fp AND rationale=p_rationale)
 THEN RAISE EXCEPTION 'Distinct Program request conflict' USING ERRCODE='23505'; END IF;
 RETURN v_created||jsonb_build_object('distinctSourceDecisionRecorded',true);
END;
$fn$;

CREATE FUNCTION public.personal_program_author_same_sources_self_api_v1(p_sources jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_owner uuid; v_fingerprint text; v_items jsonb;
BEGIN
 v_owner:=atlas.personal_training_author_guard_v1();
 v_fingerprint:=atlas.personal_program_source_fingerprint_v1(p_sources);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'programId',d.program_id,'title',d.program_title,'createdAt',d.first_created_at)
     ORDER BY d.first_created_at,d.program_id),'[]'::jsonb)
 INTO v_items
 FROM atlas.personal_program_same_sources_v1(v_owner,v_fingerprint) d;
 RETURN jsonb_build_object('ok',true,'fingerprint',v_fingerprint,'items',v_items,
  'standing','author_owned_source_matches');
END;
$fn$;

REVOKE ALL ON FUNCTION
 atlas.personal_program_source_fingerprint_v1(jsonb),
 atlas.personal_program_same_sources_v1(uuid,text),
 public.personal_program_author_create_distinct_self_api_v1(jsonb,text,text),
 public.personal_program_author_same_sources_self_api_v1(jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.personal_program_author_create_distinct_self_api_v1(jsonb,text,text),
 public.personal_program_author_same_sources_self_api_v1(jsonb)
 TO authenticated;
COMMIT;
