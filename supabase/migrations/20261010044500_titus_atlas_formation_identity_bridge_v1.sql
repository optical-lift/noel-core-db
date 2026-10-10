-- New authored Titus migration. The 2026-10-03 foundation migrations remain immutable.
-- A short-lived, one-time Atlas credential -> Titus session transition.
-- NOT an Atlas identity duplication, generic OAuth provider, or faculty entitlement.
create table titus.atlas_titus_handoff_grants_v1 (
  handoff_grant_id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  request_state text not null,
  verifier_challenge text not null,
  audience text not null default 'titus_formation_v1'
    check (audience = 'titus_formation_v1'),
  auth_user_id uuid not null,
  source_auth_session_id uuid not null,
  person_entity_id uuid not null references reality.entities(id),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  check (expires_at > issued_at and expires_at <= issued_at + interval '3 minutes')
);
create index atlas_titus_handoff_grants_expiry_v1
  on titus.atlas_titus_handoff_grants_v1(expires_at);
create index atlas_titus_handoff_grants_issuer_v1
  on titus.atlas_titus_handoff_grants_v1(auth_user_id, issued_at desc);

create table titus.atlas_titus_browser_sessions_v1 (
  titus_browser_session_id uuid primary key default gen_random_uuid(),
  session_hash text not null unique,
  handoff_grant_id uuid not null unique
    references titus.atlas_titus_handoff_grants_v1(handoff_grant_id),
  auth_user_id uuid not null,
  source_auth_session_id uuid not null,
  person_entity_id uuid not null references reality.entities(id),
  audience text not null default 'titus_formation_v1'
    check (audience = 'titus_formation_v1'),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  check (expires_at > issued_at and expires_at <= issued_at + interval '45 minutes')
);
create index atlas_titus_browser_sessions_expiry_v1
  on titus.atlas_titus_browser_sessions_v1(expires_at);
create index atlas_titus_browser_sessions_person_v1
  on titus.atlas_titus_browser_sessions_v1(person_entity_id, expires_at);

alter table titus.atlas_titus_handoff_grants_v1 enable row level security;
alter table titus.atlas_titus_browser_sessions_v1 enable row level security;
revoke all on titus.atlas_titus_handoff_grants_v1 from public, anon, authenticated;
revoke all on titus.atlas_titus_browser_sessions_v1 from public, anon, authenticated;
grant select, insert, update on titus.atlas_titus_handoff_grants_v1 to service_role;
grant select, insert, update on titus.atlas_titus_browser_sessions_v1 to service_role;

-- Hashing/token generation is internal to the governed membrane.
-- Issue MUST run with the real Atlas Supabase user session, not service-role.
create or replace function public.titus_issue_atlas_handoff_self_api_v1(
  p_request_state text,
  p_verifier_challenge text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, reality, titus, extensions
as $$
declare
  v_person uuid;
  v_user uuid := auth.uid();
  v_source_session uuid;
  v_code text;
  v_now timestamptz := now();
begin
  if auth.role() <> 'authenticated' or v_user is null then
    return jsonb_build_object('state','unauthorized');
  end if;
  if p_request_state is null or p_request_state !~ '^[a-f0-9]{64}$'
     or p_verifier_challenge is null or p_verifier_challenge !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('state','invalid_request');
  end if;
  v_person := titus.current_authenticated_person_entity_id_v1();
  if v_person is null then
    return jsonb_build_object('state','identity_not_ready');
  end if;
  begin
    v_source_session := nullif(auth.jwt()->>'session_id','')::uuid;
  exception when others then
    return jsonb_build_object('state','unauthorized');
  end;
  if v_source_session is null then
    return jsonb_build_object('state','unauthorized');
  end if;
  -- Limit even legitimate callers to avoid unbounded bearer creation.
  if (select count(*) from titus.atlas_titus_handoff_grants_v1
      where auth_user_id = v_user and issued_at > v_now - interval '1 minute') >= 6 then
    return jsonb_build_object('state','try_later');
  end if;
  v_code := translate(rtrim(encode(extensions.gen_random_bytes(32),'base64'),'='),'+/','-_');
  insert into titus.atlas_titus_handoff_grants_v1 (
    code_hash, request_state, verifier_challenge,
    auth_user_id, source_auth_session_id, person_entity_id, expires_at
  ) values (
    encode(extensions.digest(v_code,'sha256'),'hex'),
    p_request_state, p_verifier_challenge,
    v_user, v_source_session, v_person, v_now + interval '2 minutes'
  );
  return jsonb_build_object('state','issued','code',v_code,'expiresInSeconds',120);
end;
$$;
revoke all on function public.titus_issue_atlas_handoff_self_api_v1(text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.titus_issue_atlas_handoff_self_api_v1(text,text)
  to authenticated;

-- Only a trusted Titus server with service-role transport can redeem.
-- An opaque code is insufficient without BOTH state and verifier cookie.
create or replace function public.titus_redeem_atlas_handoff_service_api_v1(
  p_code text, p_request_state text, p_verifier text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, reality, titus, extensions
as $$
declare
  v_grant titus.atlas_titus_handoff_grants_v1%rowtype;
  v_now timestamptz := now();
  v_token text;
  v_source_alive boolean;
begin
  if auth.role() <> 'service_role' then
    return jsonb_build_object('state','unauthorized');
  end if;
  if p_code is null or p_code !~ '^[A-Za-z0-9_-]{43}$'
     or p_request_state is null or p_request_state !~ '^[a-f0-9]{64}$'
     or p_verifier is null or p_verifier !~ '^[A-Za-z0-9_-]{43}$' then
    return jsonb_build_object('state','invalid_grant');
  end if;
  select * into v_grant
  from titus.atlas_titus_handoff_grants_v1
  where code_hash = encode(extensions.digest(p_code,'sha256'),'hex')
  for update;
  if not found or v_grant.redeemed_at is not null or v_grant.expires_at <= v_now
     or v_grant.audience <> 'titus_formation_v1'
     or v_grant.request_state <> p_request_state
     or v_grant.verifier_challenge <> encode(extensions.digest(p_verifier,'sha256'),'hex') then
    return jsonb_build_object('state','invalid_grant');
  end if;
  select exists (
    select 1 from auth.sessions s
    join auth.users u on u.id = s.user_id
    join reality.auth_person_bindings b on b.auth_user_id = s.user_id
      and b.person_entity_id = v_grant.person_entity_id
      and b.binding_state='active' and b.retired_at is null
    join reality.entities e on e.id = b.person_entity_id
      and e.entity_kind='person' and e.identity_state='canonical'
    where s.id = v_grant.source_auth_session_id and s.user_id = v_grant.auth_user_id
      and (s.not_after is null or s.not_after > v_now)
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until <= v_now)
  ) into v_source_alive;
  if not v_source_alive then
    return jsonb_build_object('state','invalid_grant');
  end if;
  update titus.atlas_titus_handoff_grants_v1
  set redeemed_at = v_now
  where handoff_grant_id = v_grant.handoff_grant_id and redeemed_at is null;
  v_token := translate(rtrim(encode(extensions.gen_random_bytes(32),'base64'),'='),'+/','-_');
  insert into titus.atlas_titus_browser_sessions_v1(
    session_hash,handoff_grant_id,auth_user_id,
    source_auth_session_id,person_entity_id,expires_at
  ) values (
    encode(extensions.digest(v_token,'sha256'),'hex'),
    v_grant.handoff_grant_id, v_grant.auth_user_id,
    v_grant.source_auth_session_id,v_grant.person_entity_id,
    v_now + interval '45 minutes'
  );
  return jsonb_build_object('state','established','sessionToken',v_token,'expiresInSeconds',2700);
end;
$$;
revoke all on function public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.titus_redeem_atlas_handoff_service_api_v1(text,text,text)
  to service_role;

-- Security-definer internal resolver. Never expose token -> Person as a client RPC.
create or replace function titus.resolve_atlas_titus_browser_session_v1(p_token text)
returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, auth, reality, titus, extensions
as $$
declare
  v_person uuid;
begin
  if auth.role() <> 'service_role'
    or p_token is null or p_token !~ '^[A-Za-z0-9_-]{43}$' then
    return null;
  end if;
  select s.person_entity_id into v_person
  from titus.atlas_titus_browser_sessions_v1 s
  join auth.sessions a on a.id = s.source_auth_session_id
    and a.user_id=s.auth_user_id
    and (a.not_after is null or a.not_after > now())
  join auth.users u on u.id=s.auth_user_id
    and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= now())
  join reality.auth_person_bindings b on b.auth_user_id=s.auth_user_id
    and b.person_entity_id=s.person_entity_id
    and b.binding_state='active' and b.retired_at is null
  join reality.entities e on e.id=s.person_entity_id
    and e.entity_kind='person' and e.identity_state='canonical'
  where s.session_hash=encode(extensions.digest(p_token,'sha256'),'hex')
    and s.audience='titus_formation_v1'
    and s.revoked_at is null and s.expires_at > now()
  limit 1;
  return v_person;
end;
$$;
revoke all on function titus.resolve_atlas_titus_browser_session_v1(text)
  from public, anon, authenticated, service_role;

-- Narrow entitlement/readiness projection, never academic/canon source authority.
create or replace function public.titus_atlas_session_access_service_api_v1(
  p_session_token text,
  p_formation_unit_id uuid
) returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, auth, reality, titus, extensions
as $$
declare
  v_person uuid;
  v_teacher uuid;
  v_state text;
  v_review text;
begin
  if auth.role()<>'service_role' then
    return jsonb_build_object('state','unauthorized');
  end if;
  v_person := titus.resolve_atlas_titus_browser_session_v1(p_session_token);
  if v_person is null then
    return jsonb_build_object('state','unauthorized');
  end if;
  select b.teacher_id into v_teacher
  from titus.teacher_person_bindings b
  join titus.teachers t on t.teacher_id=b.teacher_id and t.status='active'
  where b.person_entity_id=v_person
    and b.binding_state='active' and b.retired_at is null
    and t.teacher_key='marlene_mcmillan'
  limit 1;
  if v_teacher is null then
    return jsonb_build_object('state','teacher_binding_required');
  end if;
  select fu.formation_state,fu.review_state into v_state,v_review
  from titus.formation_units fu
  where fu.formation_unit_id=p_formation_unit_id and fu.teacher_id=v_teacher;
  if not found then
    return jsonb_build_object('state','not_found_or_unauthorized');
  end if;
  if v_review<>'current' or v_state not in (
    'learner_ready','encountered','teachback_pending','teachback_received',
    'teachback_reviewed','transfer_pending','transfer_reviewed','integrated') then
    return jsonb_build_object('state','unit_not_ready',
      'formationState',v_state,'reviewState',v_review);
  end if;
  return jsonb_build_object('state','ready',
    'formationState',v_state,'reviewState',v_review);
end;
$$;
revoke all on function public.titus_atlas_session_access_service_api_v1(text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.titus_atlas_session_access_service_api_v1(text,uuid)
  to service_role;

create or replace function public.titus_revoke_atlas_browser_session_service_api_v1(
  p_session_token text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, auth, reality, titus, extensions
as $$
begin
  if auth.role()<>'service_role' then return jsonb_build_object('state','unauthorized'); end if;
  if p_session_token is null or p_session_token !~ '^[A-Za-z0-9_-]{43}$' then
    return jsonb_build_object('state','invalid');
  end if;
  update titus.atlas_titus_browser_sessions_v1
  set revoked_at=now()
  where session_hash=encode(extensions.digest(p_session_token,'sha256'),'hex')
    and revoked_at is null;
  return jsonb_build_object('state','revoked');
end;
$$;
revoke all on function public.titus_revoke_atlas_browser_session_service_api_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.titus_revoke_atlas_browser_session_service_api_v1(text)
  to service_role;

comment on table titus.atlas_titus_handoff_grants_v1 is
  'One-use origin-bound Atlas-authenticated browser handoff; stores only hashes of grants.';
comment on table titus.atlas_titus_browser_sessions_v1 is
  'Short lived Titus-only authentication continuity. Teacher entitlement and formation release are independently rechecked.';
