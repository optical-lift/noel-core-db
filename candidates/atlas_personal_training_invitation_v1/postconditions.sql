-- Structural postconditions for disposable production-schema clone only.
-- This does not create test people, send invitations or mutate production records.
BEGIN;
DO $validation$
DECLARE r record; p record;
BEGIN
 FOR r IN SELECT unnest(ARRAY[
  'personal_training_programs','personal_training_invitations','personal_training_participations'
 ]) AS rel LOOP
   IF NOT EXISTS(
     SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='atlas' AND c.relname=r.rel AND c.relkind='r' AND c.relrowsecurity
   ) THEN RAISE EXCEPTION 'Missing table or RLS: atlas.%',r.rel; END IF;
   IF has_table_privilege('authenticated',format('atlas.%I',r.rel),'SELECT') OR
      has_table_privilege('authenticated',format('atlas.%I',r.rel),'INSERT') OR
      has_table_privilege('authenticated',format('atlas.%I',r.rel),'UPDATE') OR
      has_table_privilege('authenticated',format('atlas.%I',r.rel),'DELETE') OR
      has_table_privilege('anon',format('atlas.%I',r.rel),'SELECT')
   THEN RAISE EXCEPTION 'Direct table privilege leaked: atlas.%',r.rel; END IF;
 END LOOP;

 FOR p IN SELECT unnest(ARRAY[
  'atlas.personal_training_create_self_api_v1(text,jsonb,jsonb,date,boolean,text)',
  'atlas.personal_training_invite_self_api_v1(uuid,text,text)',
  'atlas.personal_training_pending_self_api_v1()',
  'atlas.personal_training_decide_self_api_v1(uuid,text)',
  'atlas.personal_training_revoke_self_api_v1(uuid)',
  'atlas.personal_training_withdraw_self_api_v1(uuid)'
 ]) AS signature LOOP
   IF to_regprocedure(p.signature) IS NULL
   THEN RAISE EXCEPTION 'Missing RPC: %',p.signature; END IF;
   IF NOT (SELECT f.prosecdef FROM pg_proc f WHERE f.oid=to_regprocedure(p.signature))
   THEN RAISE EXCEPTION 'RPC not definer-guarded: %',p.signature; END IF;
   IF NOT EXISTS(
     SELECT 1 FROM pg_proc f, unnest(f.proconfig) AS cfg
     WHERE f.oid=to_regprocedure(p.signature)
       AND cfg LIKE 'search_path=pg_catalog,atlas,auth%'
   ) THEN RAISE EXCEPTION 'RPC search_path not pinned: %',p.signature; END IF;
   IF NOT has_function_privilege('authenticated',p.signature,'EXECUTE')
      OR has_function_privilege('anon',p.signature,'EXECUTE')
   THEN RAISE EXCEPTION 'Incorrect callable grants: %',p.signature; END IF;
 END LOOP;

 IF NOT EXISTS (
    SELECT 1 FROM pg_attribute a
    JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas' AND c.relname='personal_training_participations'
      AND a.attname='share_progress' AND a.attnotnull
 ) THEN RAISE EXCEPTION 'Missing explicit private-by-default sharing field'; END IF;

 RAISE NOTICE 'STRUCTURAL PRECONDITIONS PASS — role-switched behavioral clone tests are still required';
END;$validation$;
ROLLBACK;
