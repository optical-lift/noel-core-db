-- NOEL MARK-LED REALITY POOL REGISTRY, CANDIDATE v2, 2026-10-15
-- REVIEW-ONLY STRUCTURAL SOURCE. NOT DEPLOYED. NOT A PRODUCTION MIGRATION VERSION.
-- Governance: optical-lift/noel-core-db; reviewed `noel_` source-first release required.
-- Scope: Hebrew R2 exact forms and versioned consonantal projections ONLY; NO R0/R1 claims.
-- This source contains no founder-authored research, no private data, and no grants.
BEGIN;

CREATE FUNCTION draft.noel_mark_form_id_v1(
    p_script_code text,
    p_representation_rank text,
    p_representation_contract_key text,
    p_exact_surface text
) RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $function$
  SELECT 'NMF-' || encode(
    sha256(convert_to(
      'NMF1' || chr(31) || p_script_code || chr(31) ||
      p_representation_rank || chr(31) ||
      p_representation_contract_key || chr(31) || p_exact_surface,
      'UTF8'
    )),
    'hex'
  );
$function$;

-- Admission v1 supports only the confirmed normalized MT token-surface layer.
-- New representation types require later independently governed admission rules.
CREATE TABLE draft.noel_mark_forms (
    form_id text GENERATED ALWAYS AS (
      draft.noel_mark_form_id_v1(script_code, representation_rank,
                                 representation_contract_key, exact_surface)
    ) STORED PRIMARY KEY,
    script_code text NOT NULL DEFAULT 'Hebr' CHECK (script_code = 'Hebr'),
    representation_rank text NOT NULL DEFAULT 'R2' CHECK (representation_rank = 'R2'),
    representation_contract_key text NOT NULL
      CHECK (representation_contract_key = 'mt_noel_current_exact_surface_v1'),
    exact_surface text COLLATE "C" NOT NULL
      CHECK (exact_surface <> '' AND position(chr(31) IN exact_surface) = 0),
    authority_limit text NOT NULL DEFAULT
      'R2 derived token stream, not witnessed physical/diplomatic marks'
      CHECK (authority_limit = 'R2 derived token stream, not witnessed physical/diplomatic marks'),
    admitted_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_forms_exact_identity_uq UNIQUE
      (script_code, representation_rank, representation_contract_key, exact_surface),
    -- Enforces matching exact source surface when occurrence bindings reference forms.
    CONSTRAINT noel_mark_forms_id_surface_uq UNIQUE (form_id, exact_surface)
);

CREATE FUNCTION draft.noel_mark_reject_form_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  RAISE EXCEPTION 'Noel mark form identities are immutable; admit a versioned replacement and explicit relation'
    USING ERRCODE = 'integrity_constraint_violation';
END;
$function$;

CREATE TRIGGER noel_mark_forms_immutable
BEFORE UPDATE OR DELETE ON draft.noel_mark_forms
FOR EACH ROW EXECUTE FUNCTION draft.noel_mark_reject_form_mutation_v1();

-- A source occurrence remains a different identity from a written form.
-- Source bytes are held as a snapshot; source tokens and historical labels are unmodified.
CREATE TABLE draft.noel_mark_occurrence_bindings (
    witness_key text NOT NULL,
    source_token_id text NOT NULL,
    representation_rank text NOT NULL DEFAULT 'R2'
      CHECK (representation_rank = 'R2'),
    representation_contract_key text NOT NULL
      CHECK (representation_contract_key = 'mt_noel_current_exact_surface_v1'),
    form_id text NOT NULL,
    source_surface text COLLATE "C" NOT NULL CHECK (source_surface <> ''),
    source_provenance_status text NOT NULL CHECK (source_provenance_status = 'verified'),
    bound_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_occurrence_bindings_pk
      PRIMARY KEY (witness_key, source_token_id,
                   representation_rank, representation_contract_key),
    CONSTRAINT noel_mark_occurrence_identity_check
      CHECK (form_id = draft.noel_mark_form_id_v1(
        'Hebr', representation_rank, representation_contract_key, source_surface)),
    CONSTRAINT noel_mark_occurrence_form_exact_fk
      FOREIGN KEY (form_id, source_surface)
      REFERENCES draft.noel_mark_forms(form_id, exact_surface),
    CONSTRAINT noel_mark_occurrence_binding_route_uq
      UNIQUE (witness_key, source_token_id, representation_contract_key, form_id)
);

-- Frozen source-occurrence bindings must never be retargeted in place.
CREATE TRIGGER noel_mark_occurrences_immutable
BEFORE UPDATE OR DELETE ON draft.noel_mark_occurrence_bindings
FOR EACH ROW EXECUTE FUNCTION draft.noel_mark_reject_form_mutation_v1();

-- A proposed relation is not a form merge. It needs explicit evidence.
CREATE TABLE draft.noel_mark_form_relations (
    relation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_form_id text NOT NULL REFERENCES draft.noel_mark_forms(form_id),
    to_form_id text NOT NULL REFERENCES draft.noel_mark_forms(form_id),
    relation_kind text NOT NULL CHECK (relation_kind IN (
      'transcription_projection', 'consonantal_projection',
      'manuscript_variant', 'supersedes')),
    evidence_locator text NOT NULL CHECK (length(trim(evidence_locator)) > 0),
    review_state text NOT NULL DEFAULT 'proposed' CHECK (review_state IN (
      'proposed', 'source_verified', 'steward_ratified')),
    decision_id bigint REFERENCES draft.noel_reality_decisions(decision_id),
    notes text,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_form_relations_no_self CHECK (from_form_id <> to_form_id),
    CONSTRAINT noel_mark_form_relations_ratification_gate CHECK (
      review_state <> 'steward_ratified' OR decision_id IS NOT NULL),
    CONSTRAINT noel_mark_form_relations_evidence_uq
      UNIQUE (from_form_id, to_form_id, relation_kind, evidence_locator)
);

-- NMI: one operational investigation identity per DECLARED R2 consonantal projection.
-- This is NOT an assertion of original-script physical equivalence or shared semantic function.
-- The combination of codepoints and transformation rules is part of the identity contract.
CREATE FUNCTION draft.noel_mark_mt_consonantal_projection_v1(p_surface text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $function$
  SELECT regexp_replace(replace(p_surface, '/', ''), '[֑-ׇֽֿׁׂׅׄ]', '', 'g');
$function$;

CREATE FUNCTION draft.noel_mark_identity_id_v1(
    p_script_code text,
    p_representation_rank text,
    p_identity_contract_key text,
    p_projected_surface text
) RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
AS $function$
  SELECT 'NMI-' || encode(sha256(convert_to(
    'NMI1' || chr(31) || p_script_code || chr(31) ||
    p_representation_rank || chr(31) || p_identity_contract_key || chr(31) ||
    p_projected_surface, 'UTF8')), 'hex');
$function$;

CREATE TABLE draft.noel_mark_identities (
    identity_id text GENERATED ALWAYS AS (
      draft.noel_mark_identity_id_v1(script_code, representation_rank,
                                       identity_contract_key, projected_surface)
    ) STORED PRIMARY KEY,
    script_code text NOT NULL DEFAULT 'Hebr' CHECK (script_code = 'Hebr'),
    representation_rank text NOT NULL DEFAULT 'R2'
      CHECK (representation_rank = 'R2'),
    identity_contract_key text NOT NULL
      CHECK (identity_contract_key = 'mt_noel_current_consonantal_projection_v1'),
    projected_surface text COLLATE "C" NOT NULL
      CHECK (projected_surface ~ '^[א-ת]+$'),
    evidence_limit text NOT NULL DEFAULT
      'Derived R2 consonantal comparison key; not R0/R1 and not a proven function',
    admitted_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_identities_projection_uq
      UNIQUE (script_code, representation_rank, identity_contract_key, projected_surface),
    CONSTRAINT noel_mark_identities_id_projected_uq
      UNIQUE (identity_id, projected_surface)
);
CREATE TRIGGER noel_mark_identities_immutable
BEFORE UPDATE OR DELETE ON draft.noel_mark_identities
FOR EACH ROW EXECUTE FUNCTION draft.noel_mark_reject_form_mutation_v1();

-- Mechanical, versioned mapping between exact source forms and comparison identities.
-- One NMF can belong to one NMI under this contract; no semantic ratification is implied.
CREATE TABLE draft.noel_mark_identity_forms (
    identity_id text NOT NULL,
    form_id text NOT NULL,
    exact_surface text COLLATE "C" NOT NULL,
    projected_surface text COLLATE "C" NOT NULL,
    identity_contract_key text NOT NULL
      CHECK (identity_contract_key = 'mt_noel_current_consonantal_projection_v1'),
    projection_state text NOT NULL DEFAULT 'corpus_derived'
      CHECK (projection_state = 'corpus_derived'),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_identity_forms_pk
      PRIMARY KEY (form_id, identity_contract_key),
    CONSTRAINT noel_mark_identity_forms_pair_uq
      UNIQUE (identity_id, form_id),
    CONSTRAINT noel_mark_identity_forms_projection_check
      CHECK (projected_surface = draft.noel_mark_mt_consonantal_projection_v1(exact_surface)),
    CONSTRAINT noel_mark_identity_forms_id_check
      CHECK (identity_id = draft.noel_mark_identity_id_v1(
        'Hebr', 'R2', identity_contract_key, projected_surface)),
    CONSTRAINT noel_mark_identity_forms_form_fk
      FOREIGN KEY (form_id, exact_surface)
      REFERENCES draft.noel_mark_forms(form_id, exact_surface),
    CONSTRAINT noel_mark_identity_forms_identity_fk
      FOREIGN KEY (identity_id, projected_surface)
      REFERENCES draft.noel_mark_identities(identity_id, projected_surface)
);
CREATE TRIGGER noel_mark_identity_forms_immutable
BEFORE UPDATE OR DELETE ON draft.noel_mark_identity_forms
FOR EACH ROW EXECUTE FUNCTION draft.noel_mark_reject_form_mutation_v1();
CREATE INDEX noel_mark_identity_forms_identity_idx
    ON draft.noel_mark_identity_forms(identity_id);

-- Mark-first routing for existing lexical Reality Pools. No legacy node IDs are renamed.
-- Multiple candidate historical pools may initially point to one NMI; promotion must
-- reconcile them rather than overwrite founder authority or delete historical nodes.
CREATE TABLE draft.noel_mark_pool_identity_links (
    link_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    identity_id text NOT NULL REFERENCES draft.noel_mark_identities(identity_id),
    node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
    link_role text NOT NULL CHECK (link_role IN (
      'candidate_legacy_pool', 'primary_lexical_pool', 'supplementary_evidence')),
    review_state text NOT NULL DEFAULT 'proposed' CHECK (review_state IN (
      'proposed','source_verified','steward_ratified')),
    evidence_locator text NOT NULL CHECK (length(trim(evidence_locator)) > 0),
    decision_id bigint REFERENCES draft.noel_reality_decisions(decision_id),
    review_note text,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_pool_identity_ratification_check CHECK (
      link_role <> 'primary_lexical_pool' OR
        (review_state = 'steward_ratified' AND decision_id IS NOT NULL)),
    CONSTRAINT noel_mark_pool_identity_evidence_uq
      UNIQUE (identity_id,node_id,link_role,evidence_locator),
    CONSTRAINT noel_mark_pool_identity_pair_uq
      UNIQUE (identity_id,node_id)
);
-- On acceptance, an NMI has at most one primary lexical pool; a lexical pool
-- has at most one governing NMI. Multiple source labels may remain on both sides.
CREATE UNIQUE INDEX noel_mark_pool_identity_one_primary_per_identity
  ON draft.noel_mark_pool_identity_links(identity_id)
  WHERE link_role = 'primary_lexical_pool';
CREATE UNIQUE INDEX noel_mark_pool_identity_one_primary_per_pool
  ON draft.noel_mark_pool_identity_links(node_id)
  WHERE link_role = 'primary_lexical_pool';
CREATE INDEX noel_mark_pool_identity_by_pool_idx
  ON draft.noel_mark_pool_identity_links(node_id,link_role);

-- Prevent nonlexical categories from being declared the primary lexical pool.
CREATE FUNCTION draft.noel_mark_require_lexical_pool_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER AS $function$
DECLARE v_kind text;
BEGIN
  SELECT node_kind INTO v_kind
    FROM draft.noel_reality_nodes WHERE node_id=NEW.node_id;
  IF v_kind IS DISTINCT FROM 'lexical_pool' THEN
    RAISE EXCEPTION 'Noel primary mark identity requires an existing lexical_pool';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER noel_mark_require_lexical_pool
  BEFORE INSERT OR UPDATE ON draft.noel_mark_pool_identity_links
  FOR EACH ROW EXECUTE FUNCTION draft.noel_mark_require_lexical_pool_v1();

-- Detailed functional evidence routes. A historical source-label is never ratified by
-- inference. A source-verified occurrence is bound to an exact form and its NMI.
CREATE TABLE draft.noel_mark_pool_routes (
    route_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    identity_id text NOT NULL REFERENCES draft.noel_mark_identities(identity_id),
    node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
    form_id text,
    route_kind text NOT NULL CHECK (route_kind IN (
      'historic_dictionary_association', 'source_verified_occurrence',
      'proposed_function', 'steward_ratified_function')),
    route_basis_key text NOT NULL CHECK (length(trim(route_basis_key)) > 0),
    witness_key text,
    source_token_id text,
    representation_contract_key text,
    decision_id bigint REFERENCES draft.noel_reality_decisions(decision_id),
    evidence_note text,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT noel_mark_pool_routes_source_complete CHECK (
      (witness_key IS NULL AND source_token_id IS NULL
        AND representation_contract_key IS NULL)
      OR
      (witness_key IS NOT NULL AND source_token_id IS NOT NULL
        AND representation_contract_key IS NOT NULL AND form_id IS NOT NULL)),
    CONSTRAINT noel_mark_pool_routes_source_required CHECK (
      route_kind <> 'source_verified_occurrence' OR source_token_id IS NOT NULL),
    CONSTRAINT noel_mark_pool_routes_ratification_gate CHECK (
      route_kind <> 'steward_ratified_function' OR decision_id IS NOT NULL),
    CONSTRAINT noel_mark_pool_routes_member_fk
      FOREIGN KEY (identity_id, form_id)
      REFERENCES draft.noel_mark_identity_forms(identity_id, form_id),
    CONSTRAINT noel_mark_pool_routes_verified_binding_fk
      FOREIGN KEY (witness_key,source_token_id,representation_contract_key,form_id)
      REFERENCES draft.noel_mark_occurrence_bindings
        (witness_key,source_token_id,representation_contract_key,form_id),
    CONSTRAINT noel_mark_pool_routes_basis_uq
      UNIQUE (identity_id,node_id,route_kind,route_basis_key)
);
CREATE INDEX noel_mark_pool_routes_by_node_idx
  ON draft.noel_mark_pool_routes(node_id,route_kind);

CREATE INDEX noel_mark_occurrence_by_form_idx
    ON draft.noel_mark_occurrence_bindings(form_id, witness_key);
CREATE INDEX noel_mark_relations_reverse_idx
    ON draft.noel_mark_form_relations(to_form_id);

-- Private mark-first projections. No public API grants.
-- Strong's / NH annotations are read from the *source occurrence*, not copied as
-- a new permanent label authority or used to decide identity membership.
CREATE VIEW intelligence.v_noel_mark_identity_historic_labels_v1
WITH (security_invoker = true)
AS
SELECT DISTINCT m.identity_id, o.form_id, o.witness_key,
  o.source_token_id, s.strong_id,
  t.governance_id AS historic_governance_id
FROM draft.noel_mark_identity_forms m
JOIN draft.noel_mark_occurrence_bindings o ON o.form_id=m.form_id
JOIN intelligence.v_canon_source_text_spine s
 ON s.witness_key=o.witness_key AND s.source_token_id=o.source_token_id
 AND s.surface_text=o.source_surface
LEFT JOIN draft.ot_canonical_tokens_stage t
 ON o.witness_key='mt_noel_current' AND t.source_token_id=o.source_token_id
WHERE o.representation_contract_key='mt_noel_current_exact_surface_v1';

CREATE VIEW intelligence.v_noel_mark_primary_pool_v1
WITH (security_invoker = true)
AS
SELECT i.identity_id, i.projected_surface, l.node_id,
 l.link_role, l.review_state, l.decision_id, n.display_name,
 n.authority_state AS legacy_node_authority_state
FROM draft.noel_mark_identities i
LEFT JOIN draft.noel_mark_pool_identity_links l ON l.identity_id=i.identity_id
LEFT JOIN draft.noel_reality_nodes n ON n.node_id=l.node_id;

REVOKE ALL ON intelligence.v_noel_mark_identity_historic_labels_v1,
 intelligence.v_noel_mark_primary_pool_v1 FROM PUBLIC,anon,authenticated;

-- Private research custody: no new browser/public grants, no public research publication.
ALTER TABLE draft.noel_mark_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft.noel_mark_occurrence_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft.noel_mark_form_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft.noel_mark_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft.noel_mark_identity_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft.noel_mark_pool_identity_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE draft.noel_mark_pool_routes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE draft.noel_mark_forms,draft.noel_mark_occurrence_bindings,
  draft.noel_mark_form_relations,draft.noel_mark_identities,
  draft.noel_mark_identity_forms,draft.noel_mark_pool_identity_links,
  draft.noel_mark_pool_routes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION draft.noel_mark_form_id_v1(text,text,text,text),
  draft.noel_mark_reject_form_mutation_v1(),
  draft.noel_mark_mt_consonantal_projection_v1(text),
  draft.noel_mark_identity_id_v1(text,text,text,text),
  draft.noel_mark_require_lexical_pool_v1()
  FROM PUBLIC,anon,authenticated;
-- No backfill, inherited alias rewrites, definition mutation, or reader cutover in DDL.
COMMIT;
