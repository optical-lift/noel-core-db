-- Disposable PostgreSQL harness. Only synthetic identities; never connected to Noel.
create schema auth;
create schema atlas;
create role anon nologin;
create role authenticated nologin;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $func$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$func$;
create function atlas.require_active_task_principal_v1() returns uuid language sql stable as $func$
 select nullif(current_setting('atlas.fixture_principal',true),'')::uuid
$func$;
create table atlas.personal_reality_captures (
 id uuid primary key,
 owner_user_id uuid not null references auth.users(id),
 principal_id uuid not null,
 evidence_id uuid not null,
 source_surface text not null,
 metadata jsonb not null,
 testimony text not null,
 capture_context jsonb not null,
 captured_at timestamptz not null
);
