-- HELD: postcondition for genuinely current-schema disposable synthetic test ONLY.
-- The source DO deletion is complete; all predicates below are read-only.
DO $check$
BEGIN
 IF EXISTS (SELECT 1 FROM atlas.organizations WHERE stable_key='feast_guild')
   OR EXISTS (SELECT 1 FROM atlas.ledgers WHERE stable_key='feast_guild')
   OR EXISTS (SELECT 1 FROM atlas.principal_ledger_authorities
       WHERE id='a5000000-0000-4000-8000-000000000001'::uuid)
   OR EXISTS (SELECT 1 FROM atlas.ledger_organization_participations
       WHERE id='a4000000-0000-4000-8000-000000000001'::uuid)
 THEN RAISE EXCEPTION 'Synthetic Feast Guild test graph was not fully removed.'; END IF;

 IF (SELECT count(*) FROM atlas.organizations WHERE id='a2000000-0000-4000-8000-000000000002'::uuid AND stable_key='elm_farm')<>1
 OR (SELECT count(*) FROM atlas.ledgers WHERE id='a3000000-0000-4000-8000-000000000002'::uuid AND stable_key='elm_farm')<>1
 OR (SELECT count(*) FROM atlas.ledger_organization_participations WHERE id='a4000000-0000-4000-8000-000000000002'::uuid)<>1
 OR (SELECT count(*) FROM atlas.principal_ledger_authorities WHERE id='a5000000-0000-4000-8000-000000000002'::uuid)<>1
 OR (SELECT count(*) FROM atlas.principals WHERE id='a1000000-0000-4000-8000-000000000001'::uuid AND status='active')<>1
 OR (SELECT count(*) FROM auth.users WHERE id='a0000000-0000-4000-8000-000000000001'::uuid)<>1
 THEN RAISE EXCEPTION 'Synthetic protected Elm/Principal/Person identity changed.'; END IF;
 RAISE NOTICE 'PASS held Feast Guild deletion on current-schema synthetic fixture; protected Elm and Principal remain.';
END
$check$;
