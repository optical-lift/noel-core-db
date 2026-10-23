-- Synthetic schema only; disposable Postgres, never the live Noel database.
create schema auth;
create schema atlas;
create role anon nologin;
create role authenticated nologin;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
create function atlas.require_active_task_principal_v1() returns uuid language sql stable as $$
 select nullif(current_setting('atlas.fixture_principal',true),'')::uuid
$$;
create table atlas.evidence_records(
 id uuid primary key,scope_kind text,scope_id uuid,observed_at timestamptz,
 provenance jsonb not null default '{}'::jsonb);
create table atlas.personal_reality_captures(
 id uuid primary key,owner_user_id uuid,principal_id uuid,evidence_id uuid,
 testimony text,source_surface text,metadata jsonb,capture_context jsonb,
 captured_at timestamptz,capture_state text);
create table atlas.task_entries(
 id uuid primary key,owner_user_id uuid,principal_id uuid,
 completed_at timestamptz,status text,sentence text);
insert into auth.users values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222');
insert into atlas.evidence_records(id,scope_kind,scope_id,observed_at,provenance)
values
 ('e0000000-0000-4000-8000-000000000001','person','11111111-1111-4111-8111-111111111111',null,'{}'),
 ('e0000000-0000-4000-8000-000000000002','person','11111111-1111-4111-8111-111111111111',null,'{}'),
 ('e0000000-0000-4000-8000-000000000003','person','22222222-2222-4222-8222-222222222222',null,'{}');
insert into atlas.personal_reality_captures
 (id,owner_user_id,principal_id,evidence_id,testimony,source_surface,metadata,
 capture_context,captured_at,capture_state)
values
 ('00000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','e0000000-0000-4000-8000-000000000001',
 'I weighed 172 pounds this morning.','personal_notebook_daily_log',
 '{"notebookEntryKind":"raw_note"}','{"notebookDate":"2026-10-23"}','2026-10-23T12:00:00Z','captured'),
 ('00000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','e0000000-0000-4000-8000-000000000002',
 'I noticed a leak.','personal_notebook_daily_log',
 '{"notebookEntryKind":"raw_note"}','{"notebookDate":"2026-10-22"}','2026-10-22T13:00:00Z','captured'),
 ('00000000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','e0000000-0000-4000-8000-000000000003',
 'Private other Person observation','personal_notebook_daily_log',
 '{"notebookEntryKind":"raw_note"}','{"notebookDate":"2026-10-23"}','2026-10-23T15:00:00Z','captured');
insert into atlas.task_entries
 (id,owner_user_id,principal_id,completed_at,status,sentence)
values
 ('a0000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','2026-10-23T09:00:00Z','done','Mark shopping complete'),
 ('a0000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',null,'open','Still outstanding'),
 ('a0000000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','2026-10-23T17:00:00Z','done','Other Person work');
