-- REVIEW CANDIDATE ONLY: not a production migration.
-- Atlas's first universal-shaped task entry is exactly one sentence + one due date.
-- Owners are authenticated established Principals; no inferred project or farm relation.
-- Release path: generate an atlas_-prefixed canonical migration through the
-- reviewed noel-core-db migration workflow, test in disposable clone, promote manually.
-- Does NOT mutate or copy legacy atlas.tasks records.

create table atlas.task_entries (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  sentence text not null check (length(btrim(sentence)) between 1 and 500),
  due_date date not null,
  status text not null default 'open' check (status in ('open','done')),
  source_action_id text not null check (length(btrim(source_action_id)) between 1 and 128),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint task_entries_completion_consistency check (
    (status='open' and completed_at is null)
    or (status='done' and completed_at is not null)
  ),
  constraint task_entries_authoring_idempotency unique (owner_user_id,source_action_id)
);
create index task_entries_day_owner_idx on atlas.task_entries(owner_user_id,due_date,created_at,id);
alter table atlas.task_entries enable row level security;
-- No direct Data API exposure. Authenticated access is only via verified RPCs.
revoke all on table atlas.task_entries from public,anon,authenticated;

create or replace function atlas.require_active_task_principal_v1()
returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user uuid := auth.uid();
  v_principal uuid;
  v_access jsonb;
begin
  if v_user is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  v_access := atlas.personal_atlas_access_status_self_api_v1();
  if not coalesce((v_access->>'eligible')::boolean,false)
     or coalesce(v_access->>'accessState','locked')='locked' then
    raise exception 'Active Personal Atlas access required.' using errcode='42501';
  end if;
  select p.id into v_principal
  from atlas.principals p
  where p.user_id=v_user and p.status='active'
  order by p.id limit 1;
  if v_principal is null then
    raise exception 'Established Principal required.' using errcode='42501';
  end if;
  return v_principal;
end;
$$;

create or replace function atlas.atlas_task_day_self_api_v1(p_date date)
returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_rows jsonb;
begin
  if p_date is null then raise exception 'Date is required.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'sentence', t.sentence,
    'dueDate', t.due_date,
    'status', t.status
  ) order by case when t.status='open' then 0 else 1 end, t.created_at, t.id),'[]'::jsonb)
  into v_rows
  from atlas.task_entries t
  where t.owner_user_id=auth.uid()
    and t.principal_id=v_principal
    and t.due_date=p_date;
  return jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
end;
$$;

create or replace function atlas.create_atlas_task_self_api_v1(
  p_sentence text, p_due_date date, p_source_action_id text
)
returns jsonb
language plpgsql volatile security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_user uuid := auth.uid();
  v_sentence text := btrim(coalesce(p_sentence,''));
  v_key text := btrim(coalesce(p_source_action_id,''));
  v_task atlas.task_entries%rowtype;
begin
  if length(v_sentence) not between 1 and 500 then
    raise exception 'Enter one sentence (1-500 characters).' using errcode='22023';
  end if;
  if p_due_date is null then raise exception 'Choose a date.' using errcode='22023'; end if;
  if length(v_key) not between 1 and 128 then
    raise exception 'Source action ID is required.' using errcode='22023';
  end if;

  insert into atlas.task_entries(owner_user_id,principal_id,sentence,due_date,source_action_id)
  values (v_user,v_principal,v_sentence,p_due_date,v_key)
  on conflict (owner_user_id,source_action_id) do nothing
  returning * into v_task;

  if v_task.id is null then
    select * into v_task from atlas.task_entries
      where owner_user_id=v_user and source_action_id=v_key;
    if v_task.id is null or v_task.principal_id<>v_principal
       or v_task.sentence<>v_sentence or v_task.due_date<>p_due_date then
      raise exception 'The submission key belongs to a different task.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
end;
$$;

create or replace function atlas.set_atlas_task_done_self_api_v1(
  p_task_id uuid, p_done boolean
)
returns jsonb
language plpgsql volatile security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_task atlas.task_entries%rowtype;
begin
  if p_task_id is null or p_done is null then
    raise exception 'Task and completion state are required.' using errcode='22023';
  end if;
  update atlas.task_entries
     set status=case when p_done then 'done' else 'open' end,
         completed_at=case when p_done then now() else null end
   where id=p_task_id and owner_user_id=auth.uid() and principal_id=v_principal
   returning * into v_task;
  if v_task.id is null then
    raise exception 'Task not found.' using errcode='42501';
  end if;
  return jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
end;
$$;

-- The Atlas schema remains private. Public functions expose only authenticated
-- self-scoped commands and never accept an owner_user_id/principal_id argument.
create or replace function public.atlas_task_day_self_api_v1(p_date date)
returns jsonb language sql stable security definer
set search_path = pg_catalog
as $$ select atlas.atlas_task_day_self_api_v1(p_date); $$;

create or replace function public.create_atlas_task_self_api_v1(
  p_sentence text,p_due_date date,p_source_action_id text
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $$ select atlas.create_atlas_task_self_api_v1(p_sentence,p_due_date,p_source_action_id); $$;

create or replace function public.set_atlas_task_done_self_api_v1(
  p_task_id uuid,p_done boolean
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $$ select atlas.set_atlas_task_done_self_api_v1(p_task_id,p_done); $$;

revoke execute on function atlas.require_active_task_principal_v1() from public,anon,authenticated;
revoke execute on function atlas.atlas_task_day_self_api_v1(date) from public,anon,authenticated;
revoke execute on function atlas.create_atlas_task_self_api_v1(text,date,text) from public,anon,authenticated;
revoke execute on function atlas.set_atlas_task_done_self_api_v1(uuid,boolean) from public,anon,authenticated;
revoke execute on function public.atlas_task_day_self_api_v1(date) from public,anon;
revoke execute on function public.create_atlas_task_self_api_v1(text,date,text) from public,anon;
revoke execute on function public.set_atlas_task_done_self_api_v1(uuid,boolean) from public,anon;
grant execute on function public.atlas_task_day_self_api_v1(date) to authenticated;
grant execute on function public.create_atlas_task_self_api_v1(text,date,text) to authenticated;
grant execute on function public.set_atlas_task_done_self_api_v1(uuid,boolean) to authenticated;

-- Disposable clone acceptance, not production:
-- (1) anon denied; authenticated without Principal denied; locked Principal denied
-- (2) user A can write/read/complete only A's task; B cannot guess A's ID
-- (3) repeated source_action_id is idempotent, distinct payload conflicts
-- (4) due date retrieves exactly that date, including completed rows
-- (5) user supplied plain sentence is preserved unchanged except outer whitespace
-- (6) a reload or account switch does not lose or leak the task
-- (7) no old farm/project task or task trigger is altered or reinterpreted
