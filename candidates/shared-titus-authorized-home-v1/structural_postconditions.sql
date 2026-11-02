-- Structural assertions for a disposable production-shaped clone after applying
-- candidates/shared-titus-authorized-home-v1/candidate.sql.
-- This is NOT a signed Person/browser acceptance test. No real account secrets.
do $verify$
declare
  v_oid oid := to_regprocedure('public.titus_authorized_home_self_api_v1()');
  v_def text;
begin
  if v_oid is null then
    raise exception 'Missing authorized Titus home self API';
  end if;
  if not (select p.prosecdef from pg_proc p where p.oid = v_oid) then
    raise exception 'Canonical self RPC must have reviewed definer-based transport';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') or
     has_function_privilege('service_role', v_oid, 'EXECUTE') or
     exists (
       select 1 from pg_proc p,
         lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
       where p.oid = v_oid and acl.grantee = 0
         and acl.privilege_type = 'EXECUTE'
     ) then
    raise exception 'Unexpected broad RPC EXECUTE permission';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'Signed current-User self RPC unavailable';
  end if;
  if not exists (
    select 1 from pg_proc p where p.oid=v_oid
      and 'search_path=pg_catalog'=any(p.proconfig)
  ) then
    raise exception 'Search path not pinned';
  end if;
  v_def := lower(regexp_replace(pg_get_functiondef(v_oid), '[[:space:]]+', '', 'g'));
  if position('titus.current_authenticated_person_entity_id_v1()' in v_def)=0 or
     position('auth.uid()' in v_def)=0 or
     position('auth.jwt()' in v_def)=0 or
     position('atlas.person_auth_credentials' in v_def)=0 or
     position('credential.auth_user_id=v_uid' in v_def)=0 or
     position('credential.person_id=v_person' in v_def)=0 or
     position('credential.retired_atisnull' in v_def)=0 or
     position('person.status=''active''' in v_def)=0 or
     position('atlas.teaching_enrollments' in v_def)=0 or
     position('e.state=''active''' in v_def)=0 or
     position('o.state=''open''' in v_def)=0 or
     position('v.published_atisnotnull' in v_def)=0 then
    raise exception 'Reviewed source gates do not match candidate';
  end if;
  raise notice 'STRUCTURAL CONTRACT ONLY: signed-user and denial tests still required';
end;
$verify$;
