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
