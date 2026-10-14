-- NON-MUTATING schema postconditions. Synthetic authorized/negative actor
-- acceptance tests must also run on disposable schema clone before release.
DO $$
BEGIN
 IF to_regprocedure('public.household_identity_invite_create_self_api_v1(uuid)') IS NULL
 OR to_regprocedure('public.household_identity_invite_accept_self_api_v1(text)') IS NULL
 OR to_regprocedure('public.household_identity_link_status_self_api_v1(uuid)') IS NULL
 OR to_regprocedure('public.household_identity_invite_preview_self_api_v1(text)') IS NULL
 OR to_regprocedure('public.household_identity_link_disconnect_self_api_v1(uuid)') IS NULL
 OR to_regprocedure('public.household_identity_received_links_self_api_v1()') IS NULL
 THEN RAISE EXCEPTION 'identity-only connection RPC missing'; END IF;
 IF has_function_privilege('anon','public.household_identity_invite_accept_self_api_v1(text)','EXECUTE')
 OR has_function_privilege('anon','public.household_identity_invite_create_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.household_identity_invite_accept_self_api_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'invalid identity-only RPC permissions'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='atlas' AND indexname='household_identity_active_person_in_house_idx')
 OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='atlas' AND indexname='household_identity_active_member_idx')
 THEN RAISE EXCEPTION 'identity-only uniqueness protections absent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='atlas' AND c.relname='household_member_identity_links' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'identity-only links must use RLS'; END IF;
END;
$$;
