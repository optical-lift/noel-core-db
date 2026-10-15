-- Public-safe candidate postconditions. Clone-only, before any real production backfill.
-- Logs must report invariant counts, never founder lexical content or pool membership.
DO $verify$
DECLARE
  v_tables integer;
  v_views integer;
  v_unprotected integer;
  v_public_privileges integer;
BEGIN
  SELECT count(*) INTO v_tables FROM information_schema.tables
  WHERE table_schema='draft' AND table_name IN
    ('noel_mark_forms','noel_mark_occurrence_bindings','noel_mark_form_relations',
     'noel_mark_identities','noel_mark_identity_forms',
     'noel_mark_pool_identity_links','noel_mark_pool_routes');
  IF v_tables <> 7 THEN RAISE EXCEPTION 'Expected 7 Noel mark registry tables, got %',v_tables; END IF;
  SELECT count(*) INTO v_views FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='intelligence' AND c.relname IN
     ('v_noel_mark_identity_historic_labels_v1','v_noel_mark_primary_pool_v1')
     AND c.relkind='v' AND 'security_invoker=true'=ANY(coalesce(c.reloptions,array[]::text[]));
  IF v_views <> 2 THEN RAISE EXCEPTION 'Expected 2 security-invoker private views, got %',v_views; END IF;
  SELECT count(*) INTO v_unprotected FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='draft' AND c.relname LIKE 'noel_mark_%'
    AND c.relkind='r' AND NOT c.relrowsecurity;
  IF v_unprotected <> 0 THEN RAISE EXCEPTION 'Unprotected Noel mark tables: %',v_unprotected; END IF;
  SELECT count(*) INTO v_public_privileges
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN (VALUES ('anon'),('authenticated')) roles(role_name)
  WHERE ((n.nspname='draft' AND c.relname LIKE 'noel_mark_%' AND c.relkind='r')
    OR (n.nspname='intelligence' AND c.relname IN
      ('v_noel_mark_identity_historic_labels_v1','v_noel_mark_primary_pool_v1')))
   AND has_table_privilege(roles.role_name,c.oid,'SELECT');
  IF v_public_privileges > 0 THEN RAISE EXCEPTION 'Client-readable Noel mark registry surfaces detected'; END IF;
END;
$verify$;
-- No private pool contents or association rows should be emitted to build logs.


-- Disposable-clone behavioral checks using wholly synthetic identifiers.
-- This section never belongs in production release SQL and emits no research.
-- Explicit ROLLBACK leaves the clone schema/data untouched after inspection.
BEGIN;
DO $behavior$
DECLARE
  v_id text;
  v_form_a text;
  v_form_b text;
  v_node_a text := '__noel_mark_clone_fixture_a__';
  v_node_b text := '__noel_mark_clone_fixture_b__';
  v_bad_decision bigint;
  v_valid_decision bigint;
  v_other_decision bigint;
  v_rejected boolean;
BEGIN
  v_id := draft.noel_mark_identity_id_v1(
    'Hebr','R2','mt_noel_current_consonantal_projection_v1','אב');
  v_form_a := draft.noel_mark_form_id_v1(
    'Hebr','R2','mt_noel_current_exact_surface_v1','אָב');
  v_form_b := draft.noel_mark_form_id_v1(
    'Hebr','R2','mt_noel_current_exact_surface_v1','אַב');
  IF v_form_a = v_form_b OR
     draft.noel_mark_mt_consonantal_projection_v1('אָב') <> 'אב' OR
     draft.noel_mark_mt_consonantal_projection_v1('אַב') <> 'אב' THEN
    RAISE EXCEPTION 'Exact form/projection separation failed';
  END IF;

  INSERT INTO draft.noel_mark_forms (
    script_code,representation_rank,representation_contract_key,exact_surface
  ) VALUES
    ('Hebr','R2','mt_noel_current_exact_surface_v1','אָב'),
    ('Hebr','R2','mt_noel_current_exact_surface_v1','אַב');
  INSERT INTO draft.noel_mark_identities (
    script_code,representation_rank,identity_contract_key,projected_surface
  ) VALUES (
    'Hebr','R2','mt_noel_current_consonantal_projection_v1','אב'
  );
  INSERT INTO draft.noel_mark_identity_forms (
    identity_id,form_id,exact_surface,projected_surface,identity_contract_key
  ) VALUES
    (v_id,v_form_a,'אָב','אב','mt_noel_current_consonantal_projection_v1'),
    (v_id,v_form_b,'אַב','אב','mt_noel_current_consonantal_projection_v1');

  IF (SELECT count(*) FROM draft.noel_mark_identity_forms
      WHERE identity_id = v_id) <> 2 THEN
    RAISE EXCEPTION 'Two exact forms did not resolve to the same NMI';
  END IF;

  v_rejected := false;
  BEGIN
    UPDATE draft.noel_mark_forms SET exact_surface = 'אב'
    WHERE form_id = v_form_a;
  EXCEPTION WHEN integrity_constraint_violation THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Immutable form update was permitted';
  END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO draft.noel_mark_occurrence_bindings (
      witness_key,source_token_id,representation_rank,
      representation_contract_key,form_id,source_surface,source_provenance_status
    ) VALUES (
      'unreviewed_witness','__synthetic__','R2',
      'mt_noel_current_exact_surface_v1',v_form_a,'אָב','verified'
    );
  EXCEPTION WHEN check_violation THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Unadmitted non-MT witness was accepted';
  END IF;

  INSERT INTO draft.noel_reality_nodes (
    node_id,node_kind,display_name,authority_state,authority_basis
  ) VALUES
    (v_node_a,'lexical_pool','Synthetic test A','indexed_attested','clone_only'),
    (v_node_b,'lexical_pool','Synthetic test B','indexed_attested','clone_only');

  -- An unrelated steward decision must not be usable to promote an NMI/pool.
  INSERT INTO draft.noel_reality_decisions (
    subject_kind,subject_id,action,resulting_state,
    decision_basis,actor_label,extra
  ) VALUES (
    'node',v_node_a,'ratify','steward_governed',
    'synthetic_negative_control','project_steward',
    jsonb_build_object(
      'mark_identity_id','NMI-unrelated',
      'operation','ratify_primary_lexical_pool')
  ) RETURNING decision_id INTO v_bad_decision;

  v_rejected := false;
  BEGIN
    INSERT INTO draft.noel_mark_pool_identity_links (
      identity_id,node_id,link_role,review_state,evidence_locator,decision_id
    ) VALUES (
      v_id,v_node_a,'primary_lexical_pool','steward_ratified',
      'clone_fixture_unrelated_decision',v_bad_decision
    );
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'NMI primary lexical pool requires%' THEN RAISE; END IF;
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Unrelated decision illegally promoted a primary lexical pool';
  END IF;

  -- Only a node-scoped, NMI-scoped steward decision may establish primary.
  INSERT INTO draft.noel_reality_decisions (
    subject_kind,subject_id,action,resulting_state,
    decision_basis,actor_label,extra
  ) VALUES (
    'node',v_node_a,'ratify','steward_governed',
    'synthetic_positive_control','project_steward',
    jsonb_build_object(
      'mark_identity_id',v_id,
      'operation','ratify_primary_lexical_pool')
  ) RETURNING decision_id INTO v_valid_decision;

  INSERT INTO draft.noel_mark_pool_identity_links (
    identity_id,node_id,link_role,review_state,evidence_locator,decision_id
  ) VALUES (
    v_id,v_node_a,'primary_lexical_pool','steward_ratified',
    'clone_fixture_scoped_decision',v_valid_decision
  );

  -- A second validly ratified pool still cannot become primary for that NMI.
  INSERT INTO draft.noel_reality_decisions (
    subject_kind,subject_id,action,resulting_state,
    decision_basis,actor_label,extra
  ) VALUES (
    'node',v_node_b,'ratify','steward_governed',
    'synthetic_unique_control','project_steward',
    jsonb_build_object(
      'mark_identity_id',v_id,
      'operation','ratify_primary_lexical_pool')
  ) RETURNING decision_id INTO v_other_decision;

  v_rejected := false;
  BEGIN
    INSERT INTO draft.noel_mark_pool_identity_links (
      identity_id,node_id,link_role,review_state,evidence_locator,decision_id
    ) VALUES (
      v_id,v_node_b,'primary_lexical_pool','steward_ratified',
      'clone_fixture_second_primary',v_other_decision
    );
  EXCEPTION WHEN unique_violation THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Multiple primary pools admitted for a single NMI';
  END IF;
END;
$behavior$;
ROLLBACK;

-- Structural security gates and behavior were validated only on this
-- disposable clone. This file must never be run on production.
