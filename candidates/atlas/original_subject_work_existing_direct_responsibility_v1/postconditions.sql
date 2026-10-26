-- Schema-clone assertions after the reviewed source candidates are applied.
DO $proof$
BEGIN
 IF has_function_privilege('anon',
  'public.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)',
  'EXECUTE') THEN
   RAISE EXCEPTION 'Anonymous original Work assignment exposed';
 END IF;
 IF has_function_privilege('authenticated',
  'atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)',
  'EXECUTE') THEN
   RAISE EXCEPTION 'Internal direct assignment helper exposed';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid='atlas.work_allocations'::regclass
    AND c.conname='work_allocations_exact_assignee_carrier_v1'
    AND pg_get_constraintdef(c.oid) LIKE '%original_subject_direct_assignment_v1%'
 ) THEN RAISE EXCEPTION 'Original Work direct Person carrier rejected by table source';END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='owner_original_split_work_part_self_api_v1'
    AND p.prosecdef
 ) THEN RAISE EXCEPTION 'Missing governor source proof of original Work part';END IF;
END $proof$;

-- Sign-in integration cases REQUIRED before any release:
-- Governor reads exact original split Bed 3 and Bed 4 IDs;
-- independent result policy review (worker attestation vs manager acceptance);
-- issue one direct allocation + plan for Anna without new Work/task/offer;
-- retry with same action returns same allocation & plan;
-- changed Person/date/action or another active responsible Person is denied;
-- Anna signed in sees exact original Bed 3 through my_work/day/Today,
-- confirms her own physical work with source-specific accepted result;
-- recipient cannot discover other Beds, owner private information or all crops;
-- unconnected Person, unrelated Ledger governor, anon all denied;
-- Event original Work and other preexisting Person assignment flows unchanged.
