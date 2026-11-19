-- W07 DIRECT ORIGINAL disposable-clone restore parity ONLY, never a migration.
-- Match exact released function bodies and signed-only production ACLs before
-- the correction is applied. Reject every unexpected ACL/source/inheritance.
-- Only explicitly present, directly granted anon/service_role EXECUTE on
-- these eight known public REST wrappers can be removed. The clone's local
-- default privileges can otherwise retain access that the live dump omits.
-- Never add privilege, rewrite a body, touch an internal function or change
-- any production object. Pin this helper to the exact local candidate package.
BEGIN;
DO $parity$
DECLARE
  rec record;
  v_native oid;
  v_rest oid;
  v_role text;
  v_extra int:=0;
BEGIN
  IF current_setting('w07.direct_disposable_clone',true) IS DISTINCT FROM 'true'
     OR current_database()<>'postgres'
     OR inet_server_addr() IS NULL
     OR NOT (inet_server_addr() << inet '10.0.0.0/8'
             OR inet_server_addr() << inet '172.16.0.0/12'
             OR inet_server_addr() << inet '192.168.0.0/16'
             OR inet_server_addr() << inet '127.0.0.0/8') THEN
    RAISE EXCEPTION 'REFUSE W07 parity outside disposable clone';
  END IF;
  FOR rec IN SELECT * FROM (VALUES
    ('connected_person_my_work_self_api_v2(integer,uuid)','f8c680621bf442d4e968f9875ccdb68f','c87120df34c1971d33b1823ddf42db3c','s'),
    ('owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid)','ce1c786a80d555b8a8660c0ea593008f','9e8c86638fb6d0ca6cdff589c8fb1e52','s'),
    ('owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)','f64e26569a154476038eb93e044b1b1e','10e19f901338ef91bcad25618b84d22b','v'),
    ('native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)','cf4a73412533201819a7fc2001f56612','4d4ff90a7145379191e9d3661c2631a8','s'),
    ('join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','5d661a5c45a708ee26a640fd7f885436','8e5c9d28ba539d3efbd2f9e0bb3df6ab','v'),
    ('leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','e97f72d27d71505b47434271fa8345e9','2fec3df76e819176b08a373b76e0ba9b','v'),
    ('append_native_original_work_comment_self_api_v1(uuid,uuid,uuid,uuid,text)','0ba73f1b7ae6192d7fc16705ab07a07f','b3eb1e415ef0328270e3cd77ee855df8','v'),
    ('read_native_original_work_comments_self_api_v1(uuid,uuid,uuid,integer,timestamptz,uuid)','88306705562c33da7778bfda38470d57','c78df20ac5bcb73f159491938823438d','s')
  ) AS f(sig,native_hash,rest_hash,volatility)
  LOOP
    v_native:=to_regprocedure('atlas.'||rec.sig);
    v_rest:=to_regprocedure('public.'||rec.sig);
    IF v_native IS NULL OR v_rest IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.oid=v_native
        AND md5(p.prosrc)=rec.native_hash AND p.prosecdef
        AND p.provolatile::text=rec.volatility AND p.prorettype='jsonb'::regtype
        AND p.proconfig=ARRAY['search_path=""']
        AND p.proowner='postgres'::regrole AND p.proacl IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
          WHERE a.grantee<>'postgres'::regrole::oid
             OR a.grantor<>'postgres'::regrole::oid
             OR a.privilege_type<>'EXECUTE' OR a.is_grantable)
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')
    ) THEN RAISE EXCEPTION 'REFUSE W07 unexpected internal source or ACL: %',rec.sig; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.oid=v_rest
        AND md5(p.prosrc)=rec.rest_hash AND p.prosecdef
        AND p.provolatile::text=rec.volatility AND p.prorettype='jsonb'::regtype
        AND p.proconfig=ARRAY['search_path=""']
        AND p.proowner='postgres'::regrole AND p.proacl IS NOT NULL
        AND EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
          WHERE a.grantee='authenticated'::regrole::oid AND a.privilege_type='EXECUTE')
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
          WHERE a.grantee NOT IN ('postgres'::regrole::oid,'authenticated'::regrole::oid,
                                   'anon'::regrole::oid,'service_role'::regrole::oid)
             OR a.grantor<>'postgres'::regrole::oid
             OR a.privilege_type<>'EXECUTE' OR a.is_grantable)
    ) THEN RAISE EXCEPTION 'REFUSE W07 unexpected REST source or ACL: %',rec.sig; END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','service_role'] LOOP
      IF has_function_privilege(v_role,v_rest,'EXECUTE') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a
           WHERE p.oid=v_rest AND a.grantee=v_role::regrole::oid
             AND a.grantor='postgres'::regrole::oid AND a.privilege_type='EXECUTE'
             AND NOT a.is_grantable) THEN
          RAISE EXCEPTION 'REFUSE W07 inherited REST privilege: %',rec.sig;
        END IF;
        RAISE NOTICE 'W07 clone observed extra direct EXECUTE: % %',rec.sig,v_role;
        EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%s FROM %I',rec.sig,v_role);
        v_extra:=v_extra+1;
      END IF;
    END LOOP;
    IF has_function_privilege('anon',v_rest,'EXECUTE')
       OR has_function_privilege('service_role',v_rest,'EXECUTE')
       OR NOT has_function_privilege('authenticated',v_rest,'EXECUTE')
       OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(p.proacl) a
          WHERE p.oid=v_rest AND (a.grantee NOT IN ('postgres'::regrole::oid,'authenticated'::regrole::oid)
                OR a.grantor<>'postgres'::regrole::oid OR a.privilege_type<>'EXECUTE' OR a.is_grantable))
    THEN RAISE EXCEPTION 'REFUSE W07 REST parity failed: %',rec.sig; END IF;
  END LOOP;
  RAISE NOTICE 'PASS W07 exact eight REST ACLs restored to released signed-only parity; removed % direct extra grant(s)',v_extra;
END
$parity$;
COMMIT;
