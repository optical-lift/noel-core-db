-- Validate the exposed API and privilege boundary against a real schema clone.
DO $check$
DECLARE
 r record;
 v_public oid;
 v_internal oid;
 v_proc pg_proc%ROWTYPE;
BEGIN
 FOR r IN SELECT * FROM (VALUES
 ('native_connected_ledger_access_self_api_v1','()','s'),
 ('native_ledger_standing_scopes_self_api_v1','()','s'),
 ('native_ledger_company_units_owner_self_api_v1','(uuid,uuid)','s'),
 ('propose_native_ledger_standing_scope_owner_self_api_v1','(uuid,uuid,uuid,uuid,text,text,text,timestamp with time zone)','v'),
 ('respond_native_ledger_standing_scope_self_api_v1','(uuid,text)','v'),
 ('assign_native_ledger_company_work_under_scope_owner_self_api_v1','(uuid,uuid,text)','v')
 ) AS expected(name,args,volatility)
 LOOP
   v_public:=to_regprocedure('public.'||r.name||r.args);
   v_internal:=to_regprocedure('atlas.'||r.name||r.args);
   IF v_public IS NULL OR v_internal IS NULL THEN
     RAISE EXCEPTION 'Missing exact public/internal RPC pair: %', r.name;
   END IF;
   SELECT * INTO v_proc FROM pg_proc WHERE oid=v_public;
   IF v_proc.prosecdef OR v_proc.provolatile<>r.volatility OR
      position('atlas.'||r.name||'(' in pg_get_functiondef(v_public))=0 THEN
     RAISE EXCEPTION 'Public wrapper must be strict invoker delegation: %', r.name;
   END IF;
   IF NOT has_function_privilege('authenticated',v_public,'EXECUTE') OR
      has_function_privilege('anon',v_public,'EXECUTE') THEN
     RAISE EXCEPTION 'Incorrect browser RPC privilege membrane: %', r.name;
   END IF;
 END LOOP;
 IF to_regclass('atlas.organization_employee_seats') IS NULL OR
    to_regclass('atlas.organization_member_credentials') IS NULL OR
    to_regclass('atlas.work_items') IS NULL THEN
   RAISE EXCEPTION 'This release must not retire any historical Person/Work/credential source';
 END IF;
END
$check$;
