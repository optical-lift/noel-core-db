begin;

-- Execute only in a disposable validation clone AFTER installing the candidate migration.
-- No real browser session, Person, teacher binding or existing foundation object is changed.
do $titus_validation$
declare
  v_function text;
  v_oid oid;
  v_def text;
begin
  if to_regclass('titus.atlas_titus_handoff_grants_v1') is null
     or to_regclass('titus.atlas_titus_browser_sessions_v1') is null then
    raise exception 'Titus handoff/session tables absent';
  end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='titus'
      and c.relname='atlas_titus_handoff_grants_v1' and c.relrowsecurity
  ) or not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='titus'
      and c.relname='atlas_titus_browser_sessions_v1' and c.relrowsecurity
  ) then
    raise exception 'Titus handoff/session tables must be RLS protected';
  end if;
  if has_table_privilege('anon','titus.atlas_titus_handoff_grants_v1','SELECT')
     or has_table_privilege('authenticated','titus.atlas_titus_handoff_grants_v1','SELECT')
     or has_table_privilege('anon','titus.atlas_titus_browser_sessions_v1','SELECT')
     or has_table_privilege('authenticated','titus.atlas_titus_browser_sessions_v1','SELECT') then
    raise exception 'Raw handoff/session tables must deny browser roles';
  end if;

  foreach v_function in array array[
    'public.titus_issue_atlas_handoff_self_api_v1(text,text)',
    'public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)',
    'public.titus_atlas_session_access_service_api_v1(text,uuid)',
    'public.titus_revoke_atlas_browser_session_service_api_v1(text)',
    'titus.resolve_atlas_titus_browser_session_v1(text)'
  ] loop
    v_oid := to_regprocedure(v_function);
    if v_oid is null then raise exception 'Required handoff function absent: %',v_function; end if;
    if not (select prosecdef from pg_proc where oid=v_oid) then
      raise exception 'Handoff function must enforce guarded security definer: %',v_function;
    end if;
  end loop;

  if has_function_privilege('anon','public.titus_issue_atlas_handoff_self_api_v1(text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.titus_issue_atlas_handoff_self_api_v1(text,text)','EXECUTE') then
    raise exception 'Atlas issuer must be authenticated only';
  end if;
  if has_function_privilege('anon','public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)','EXECUTE')
    or has_function_privilege('authenticated','public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)','EXECUTE')
    or not has_function_privilege('service_role','public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)','EXECUTE') then
    raise exception 'Handoff redemption must be service only';
  end if;
  if has_function_privilege('anon','public.titus_atlas_session_access_service_api_v1(text,uuid)','EXECUTE')
    or has_function_privilege('authenticated','public.titus_atlas_session_access_service_api_v1(text,uuid)','EXECUTE')
    or has_function_privilege('authenticated','titus.resolve_atlas_titus_browser_session_v1(text)','EXECUTE') then
    raise exception 'Titus session validation must be private';
  end if;
  if has_function_privilege('anon','public.titus_revoke_atlas_browser_session_service_api_v1(text)','EXECUTE')
    or has_function_privilege('authenticated','public.titus_revoke_atlas_browser_session_service_api_v1(text)','EXECUTE') then
    raise exception 'Session revocation is service only';
  end if;
  select pg_get_functiondef(
    'public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)'::regprocedure
  ) into v_def;
  if position('for update' in lower(v_def))=0
    or position('redeemed_at' in lower(v_def))=0
    or position('verifier_challenge' in lower(v_def))=0
    or position('source_auth_session_id' in lower(v_def))=0 then
    raise exception 'Redeemer lacks replay/verifier/session controls';
  end if;
  select pg_get_functiondef(
    'titus.resolve_atlas_titus_browser_session_v1(text)'::regprocedure
  ) into v_def;
  if position('auth.sessions' in lower(v_def))=0
    or position('auth_person_bindings' in lower(v_def))=0
    or position('revoked_at is null' in lower(v_def))=0 then
    raise exception 'Titus session validation lost issuer/revocation or Person proof';
  end if;
  select pg_get_functiondef(
    'public.titus_atlas_session_access_service_api_v1(text,uuid)'::regprocedure
  ) into v_def;
  if position('teacher_person_bindings' in lower(v_def))=0
    or position('review_state' in lower(v_def))=0
    or position('learner_ready' in lower(v_def))=0 then
    raise exception 'Titus session access must enforce teacher and formation readiness';
  end if;
  if (public.titus_issue_atlas_handoff_self_api_v1(
    repeat('a',64),repeat('b',64)
  )->>'state') <> 'unauthorized' then
    raise exception 'Non-user issuance must fail closed';
  end if;
end;
$titus_validation$;

rollback;
