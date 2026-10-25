-- SOURCE-ONLY disposable-clone postconditions.
-- No synthetic human authorization or source grant is inferred from this.
DO $check$
DECLARE body text;
BEGIN
 IF to_regprocedure('atlas.implementation_foundry_discovery_inventory_self_api_v1()') IS NULL
 OR to_regprocedure('public.implementation_foundry_discovery_inventory_self_api_v1()') IS NULL
 THEN RAISE EXCEPTION 'Atlas Proper discovery inventory API missing'; END IF;
 IF has_function_privilege('anon',
      'public.implementation_foundry_discovery_inventory_self_api_v1()','EXECUTE')
 OR has_function_privilege('service_role',
      'public.implementation_foundry_discovery_inventory_self_api_v1()','EXECUTE')
 OR NOT has_function_privilege('authenticated',
      'public.implementation_foundry_discovery_inventory_self_api_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'Discovery inventory API grant boundary incorrect'; END IF;

 SELECT pg_get_functiondef(
 'atlas.implementation_foundry_discovery_inventory_self_api_v1()'::regprocedure)
 INTO body;
 IF body NOT ILIKE '%implementation_practitioner_authorized_self_v1%'
    OR body NOT ILIKE '%auth.sessions%'
    OR body NOT ILIKE '%sourceReadAuthorized%'
    OR body NOT ILIKE '%originalTestimonyIncluded%'
    OR body NOT ILIKE '%ledger.ledgers%'
    OR body NOT ILIKE '%foundry.events%'
 THEN RAISE EXCEPTION 'Signed-only metadata and canonical-source contract missing'; END IF;
 BEGIN
  PERFORM atlas.implementation_foundry_discovery_inventory_self_api_v1();
  RAISE EXCEPTION 'Unsigned user unexpectedly enumerated source metadata';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $check$;
