-- Fictional, disposable Postgres fixture: NEVER connect to Noel production.
create schema auth;
create schema atlas;
create role anon nologin;
create role authenticated nologin;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable set search_path to ''
as $body$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $body$;

create table atlas.principals(
 id uuid primary key default gen_random_uuid(),
 user_id uuid unique references auth.users(id),
 status text not null default 'active',
 home_timezone text not null default 'UTC',
 name text,
 created_at timestamptz not null default now()
);
create function atlas.require_active_task_principal_v1()
returns uuid language plpgsql stable security definer set search_path to ''
as $body$
declare v uuid;
begin
 select id into v from atlas.principals where user_id=auth.uid() and status='active';
 if v is null then raise exception 'Active principal required' using errcode='42501'; end if;
 return v;
end
$body$;

create table atlas.personal_reality_captures (
 id uuid primary key default gen_random_uuid(),
 principal_id uuid not null references atlas.principals(id),
 owner_user_id uuid not null references auth.users(id),
 source_action_id text not null,
 testimony text not null,
 evidence_id uuid not null,
 capture_state text not null default 'captured',
 source_surface text not null,
 capture_context jsonb not null default '{}'::jsonb,
 metadata jsonb not null default '{}'::jsonb,
 captured_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table atlas.notebook_spread_instances (
 id uuid primary key default gen_random_uuid(),
 principal_id uuid not null references atlas.principals(id),
 spread_key text not null,
 scope_kind text not null,
 scope_id text not null,
 subject_domain text not null,
 subject_kind text not null,
 subject_id text not null,
 purpose_key text not null,
 horizon_key text not null,
 thread_key text not null,
 recipe_key text,
 creation_mode text not null check(creation_mode in ('resolved','explicit','continuation')),
 spread_state text not null check(spread_state in ('open','closed')),
 title text not null,
 section_key text not null,
 composition_contract jsonb not null default '{}'::jsonb,
 basis jsonb not null default '{}'::jsonb,
 metadata jsonb not null default '{}'::jsonb,
 opened_at timestamptz not null default now(),
 closed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(principal_id,spread_key),
 unique(principal_id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,purpose_key,horizon_key)
);
create table atlas.notebook_spread_source_bindings (
 id uuid primary key default gen_random_uuid(),
 spread_instance_id uuid not null references atlas.notebook_spread_instances(id),
 source_domain text not null,
 source_kind text not null,
 source_id text not null,
 relationship_kind text not null,
 binding_state text not null check(binding_state in ('active','retired')),
 basis jsonb not null default '{}'::jsonb,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 retired_at timestamptz,
 updated_at timestamptz not null default now(),
 unique(spread_instance_id,source_domain,source_kind,source_id,relationship_kind)
);
create function atlas.bind_notebook_spread_source_v1(
 p_spread_instance_id uuid,p_source_domain text,p_source_kind text,p_source_id text,
 p_relationship_kind text,p_binding_state text,p_basis jsonb,p_metadata jsonb
) returns uuid language plpgsql security definer set search_path to ''
as $body$
declare id0 uuid;
begin
 insert into atlas.notebook_spread_source_bindings(
   spread_instance_id,source_domain,source_kind,source_id,relationship_kind,
   binding_state,basis,metadata,retired_at
 ) values (p_spread_instance_id,p_source_domain,p_source_kind,p_source_id,
   p_relationship_kind,p_binding_state,p_basis,p_metadata,
   case when p_binding_state='retired' then now() else null end)
 on conflict(spread_instance_id,source_domain,source_kind,source_id,relationship_kind)
 do update set binding_state=excluded.binding_state,
 basis=excluded.basis,metadata=excluded.metadata,retired_at=excluded.retired_at,updated_at=now()
 returning id into id0;
 return id0;
end;
$body$;
create table atlas.person_recognition_rule_permissions_v1 (
 owner_user_id uuid not null references auth.users(id),
 rule_key text not null,
 rule_version integer not null,
 approved_capture_id uuid not null references atlas.personal_reality_captures(id),
 approved_at timestamptz not null default now(),
 revoked_at timestamptz,
 primary key(owner_user_id,rule_key,rule_version)
);
-- Minimal stand-in for already-released conservative v1 recognition:
-- only explicit 172 pounds example matches; unknown text never matches.
create function atlas.recognize_body_weight_sentence_v1(p_text text)
returns jsonb language sql immutable set search_path to ''
as $body$
 select case when p_text='I weighed 172 pounds this morning.'
   then jsonb_build_object('ruleKey','measure.body_weight.reported','ruleVersion',1)
   else null::jsonb end
$body$;
insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222');
insert into atlas.principals(id,user_id,status) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','active'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','active');
insert into atlas.personal_reality_captures(
 id,principal_id,owner_user_id,source_action_id,testimony,evidence_id,
 capture_state,source_surface,metadata
) values
 ('00000000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111',
  'fixture-1','I weighed 172 pounds this morning.',
  'e0000000-0000-4000-8000-000000000001','captured',
  'personal_notebook_daily_log','{"notebookEntryKind":"raw_note"}'),
 ('00000000-0000-4000-8000-000000000002',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222',
  'fixture-2','My knee hurts.',
  'e0000000-0000-4000-8000-000000000002','captured',
  'personal_notebook_daily_log','{"notebookEntryKind":"raw_note"}');
