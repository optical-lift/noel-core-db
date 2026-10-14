-- Non-mutating schema contract proofs for disposable clone.
DO $$
BEGIN
 IF to_regprocedure('atlas.household_identity_received_links_self_v1()') IS NULL OR
    to_regprocedure('atlas.atlas_notebook_index_self_api_v1()') IS NULL
 THEN RAISE EXCEPTION 'Missing reciprocal Family read contracts'; END IF;
 IF position('relationshipAsRecorded' in pg_get_functiondef('atlas.household_identity_received_links_self_v1()'::regprocedure))=0
 OR position('household_identity_link' in pg_get_functiondef('atlas.atlas_notebook_index_self_api_v1()'::regprocedure))=0
 THEN RAISE EXCEPTION 'Reciprocal projection has not been installed'; END IF;
END;
$$;