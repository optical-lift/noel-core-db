-- Contract integration tests for disposable database only.
-- Uses two roles' JWT claim contexts and fixture identity, not real users.
begin;
do $harness$
declare
  v_issued jsonb;
  v_wrong jsonb;
  v_redeemed jsonb;
  v_other jsonb;
  v_access jsonb;
  v_code text;
  v_token text;
  v_expired_code text;
  v_state text:=repeat('a',64);
  v_verifier text:='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  v_challenge text:=encode(extensions.digest(v_verifier,'sha256'),'hex');
  v_unit uuid:='00000000-0000-4000-8000-000000000015';
begin
  -- Anonymous and invalid request parameters fail closed.
  perform set_config('request.jwt.claim.role','anon',true);
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  v_other:=public.titus_issue_atlas_handoff_self_api_v1(v_state,v_challenge);
  if v_other->>'state'<>'unauthorized' then
    raise exception 'Anonymous issuance unexpectedly allowed: %',v_other;
  end if;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
  perform set_config('request.jwt.claims',
    '{"session_id":"00000000-0000-4000-8000-000000000012"}',true);
  v_other:=public.titus_issue_atlas_handoff_self_api_v1('bad',v_challenge);
  if v_other->>'state'<>'invalid_request' then raise exception 'Malformed state accepted'; end if;

  v_issued:=public.titus_issue_atlas_handoff_self_api_v1(v_state,v_challenge);
  if v_issued->>'state'<>'issued' then raise exception 'Valid Atlas issuance failed: %',v_issued; end if;
  v_code:=v_issued->>'code';
  if v_code !~ '^[A-Za-z0-9_-]{43}$' then raise exception 'Issued handoff code has wrong entropy/encoding'; end if;

  -- Bearer code cannot redeem without matching cookies/state and service role.
  v_other:=public.titus_redeem_atlas_handoff_service_api_v1(v_code,v_state,v_verifier);
  if v_other->>'state'<>'unauthorized' then raise exception 'Authenticated user redeemed service code'; end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_wrong:=public.titus_redeem_atlas_handoff_service_api_v1(v_code,repeat('b',64),v_verifier);
  if v_wrong->>'state'<>'invalid_grant' then raise exception 'Wrong initiating state redeemed'; end if;
  v_wrong:=public.titus_redeem_atlas_handoff_service_api_v1(v_code,v_state,
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');
  if v_wrong->>'state'<>'invalid_grant' then raise exception 'Wrong browser verifier redeemed'; end if;

  v_redeemed:=public.titus_redeem_atlas_handoff_service_api_v1(v_code,v_state,v_verifier);
  if v_redeemed->>'state'<>'established' then
    raise exception 'Bound redemption failed: %',v_redeemed;
  end if;
  v_token:=v_redeemed->>'sessionToken';
  if v_token !~ '^[A-Za-z0-9_-]{43}$' then raise exception 'Session token malformed'; end if;
  v_wrong:=public.titus_redeem_atlas_handoff_service_api_v1(v_code,v_state,v_verifier);
  if v_wrong->>'state'<>'invalid_grant' then raise exception 'One-time grant replay succeeded'; end if;

  -- No teacher relationship is established by signing into Atlas.
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'teacher_binding_required' then
    raise exception 'Unbound Atlas Person received Titus faculty rights: %',v_access;
  end if;
  insert into titus.teacher_person_bindings(teacher_id,person_entity_id,binding_state)
  values('00000000-0000-4000-8000-000000000014',
         '00000000-0000-4000-8000-000000000013','active');
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'unit_not_ready' then
    raise exception 'Draft formation content exposed: %',v_access;
  end if;
  update titus.formation_units set formation_state='learner_ready' where formation_unit_id=v_unit;
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'ready' then raise exception 'Ready teacher view not admitted'; end if;
  update titus.formation_units set review_state='needs_review' where formation_unit_id=v_unit;
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'unit_not_ready' then raise exception 'Stale formation content exposed'; end if;
  update titus.formation_units set review_state='current' where formation_unit_id=v_unit;

  -- Active issuer session and Person binding are checked on every read.
  delete from auth.sessions where id='00000000-0000-4000-8000-000000000012';
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'unauthorized' then raise exception 'Revoked Atlas session still valid'; end if;
  insert into auth.sessions(id,user_id) values
    ('00000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000011');
  update reality.auth_person_bindings set binding_state='retired',
    retired_at=now()
  where auth_user_id='00000000-0000-4000-8000-000000000011';
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'unauthorized' then raise exception 'Retired Person binding still valid'; end if;
  update reality.auth_person_bindings set binding_state='active',retired_at=null
  where auth_user_id='00000000-0000-4000-8000-000000000011';
  update titus.teacher_person_bindings set binding_state='retired',retired_at=now();
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'teacher_binding_required' then
    raise exception 'Retired teacher binding still authorized';
  end if;

  -- Expired code cannot be exchanged.
  perform set_config('request.jwt.claim.role','authenticated',true);
  v_issued:=public.titus_issue_atlas_handoff_self_api_v1(repeat('c',64),v_challenge);
  if v_issued->>'state'<>'issued' then raise exception 'Second issuance denied unexpectedly'; end if;
  v_expired_code:=v_issued->>'code';
  update titus.atlas_titus_handoff_grants_v1
    set issued_at=now()-interval '4 minutes',
        expires_at=now()-interval '2 minutes'
    where code_hash=encode(extensions.digest(v_expired_code,'sha256'),'hex');
  perform set_config('request.jwt.claim.role','service_role',true);
  v_wrong:=public.titus_redeem_atlas_handoff_service_api_v1(
    v_expired_code,repeat('c',64),v_verifier);
  if v_wrong->>'state'<>'invalid_grant' then raise exception 'Expired handoff redeemed'; end if;

  -- Different authenticated Person with an active different Teacher profile
  -- MUST NOT inherit Marlene's teacher entitlement or first Formation Unit.
  insert into auth.users(id) values('00000000-0000-4000-8000-000000000021');
  insert into auth.sessions(id,user_id) values
    ('00000000-0000-4000-8000-000000000022','00000000-0000-4000-8000-000000000021');
  insert into reality.entities(id,entity_kind,identity_state) values
    ('00000000-0000-4000-8000-000000000023','person','canonical');
  insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state)
  values('00000000-0000-4000-8000-000000000021',
         '00000000-0000-4000-8000-000000000023','active');
  insert into titus.teachers(teacher_id,teacher_key,status)
  values('00000000-0000-4000-8000-000000000024','different_teacher','active');
  insert into titus.teacher_person_bindings(teacher_id,person_entity_id,binding_state)
  values('00000000-0000-4000-8000-000000000024',
         '00000000-0000-4000-8000-000000000023','active');
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
  perform set_config('request.jwt.claims',
    '{"session_id":"00000000-0000-4000-8000-000000000022"}',true);
  v_issued:=public.titus_issue_atlas_handoff_self_api_v1(repeat('d',64),v_challenge);
  if v_issued->>'state'<>'issued' then raise exception 'Second Person could not issue a general Atlas handoff'; end if;
  perform set_config('request.jwt.claim.role','service_role',true);
  v_other:=public.titus_redeem_atlas_handoff_service_api_v1(
    v_issued->>'code',repeat('d',64),v_verifier);
  if v_other->>'state'<>'established' then raise exception 'Second Person redemption unexpectedly failed'; end if;
  v_access:=public.titus_atlas_session_access_service_api_v1(
    v_other->>'sessionToken',v_unit);
  if v_access->>'state'<>'teacher_binding_required' then
    raise exception 'Cross-Person teacher entitlement leaked: %',v_access;
  end if;

  -- Titus signout revokes even a valid session.
  v_other:=public.titus_revoke_atlas_browser_session_service_api_v1(v_token);
  if v_other->>'state'<>'revoked' then raise exception 'Session revoke failed'; end if;
  v_access:=public.titus_atlas_session_access_service_api_v1(v_token,v_unit);
  if v_access->>'state'<>'unauthorized' then raise exception 'Revoked Titus session remained active'; end if;
  raise notice 'PASS: anonymous, malformed, wrong state/verifier, replay, expiry, issuer revoke, Person revoke, teacher deny, draft/stale deny and Titus signout';
end;
$harness$;
rollback;
