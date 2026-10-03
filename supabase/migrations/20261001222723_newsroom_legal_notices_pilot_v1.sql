create schema if not exists newsroom;

create table if not exists newsroom.legal_notice_jobs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references transcript_core.workspaces(id) on delete cascade,
  title text not null,
  customer text,
  notice_type text,
  case_number text,
  first_run_date date,
  run_count integer not null default 1 check (run_count between 1 and 52),
  proof_state text not null default 'needed' check (proof_state in ('needed','ready','sent','revision_requested')),
  approval_state text not null default 'waiting' check (approval_state in ('waiting','approved')),
  approval_method text check (approval_method is null or approval_method in ('email','phone','other')),
  approved_at timestamptz,
  approval_note text,
  payment_state text not null default 'pending' check (payment_state in ('pending','paid_online','paid_phone','not_required')),
  payment_at timestamptz,
  payment_note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists legal_notice_jobs_workspace_first_run_idx
  on newsroom.legal_notice_jobs(workspace_id, first_run_date, created_at desc);

create table if not exists newsroom.legal_notice_proofs (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references newsroom.legal_notice_jobs(id) on delete cascade,
  version integer not null check (version > 0),
  file_name text not null,
  storage_path text not null unique,
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(job_id, version)
);

alter table newsroom.legal_notice_jobs enable row level security;
alter table newsroom.legal_notice_proofs enable row level security;

insert into storage.buckets (id, name, public)
values ('newsroom-legal-proofs', 'newsroom-legal-proofs', false)
on conflict (id) do update set public = false;

-- Browser access to proof files is limited to authenticated members of the
-- workspace encoded as the first path segment: <workspace>/<job>/vN/file.pdf.
drop policy if exists "newsroom legal proofs read" on storage.objects;
create policy "newsroom legal proofs read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'newsroom-legal-proofs'
  and public.transcript_core_is_workspace_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "newsroom legal proofs insert" on storage.objects;
create policy "newsroom legal proofs insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'newsroom-legal-proofs'
  and public.transcript_core_is_workspace_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "newsroom legal proofs update" on storage.objects;
create policy "newsroom legal proofs update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'newsroom-legal-proofs'
  and public.transcript_core_is_workspace_member(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'newsroom-legal-proofs'
  and public.transcript_core_is_workspace_member(((storage.foldername(name))[1])::uuid)
);

create or replace function public.newsroom_list_legal_notice_jobs(target_workspace uuid)
returns table (
  id uuid,
  title text,
  customer text,
  notice_type text,
  case_number text,
  first_run_date date,
  run_count integer,
  proof_state text,
  approval_state text,
  approval_method text,
  approved_at timestamptz,
  payment_state text,
  payment_at timestamptz,
  latest_proof_version integer,
  latest_proof_file_name text,
  latest_proof_storage_path text,
  ready boolean,
  next_action text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.transcript_core_is_workspace_member(target_workspace) then
    raise exception 'not authorized';
  end if;

  return query
  select
    j.id,
    j.title,
    j.customer,
    j.notice_type,
    j.case_number,
    j.first_run_date,
    j.run_count,
    j.proof_state,
    j.approval_state,
    j.approval_method,
    j.approved_at,
    j.payment_state,
    j.payment_at,
    p.version,
    p.file_name,
    p.storage_path,
    (j.approval_state = 'approved' and j.payment_state in ('paid_online','paid_phone','not_required')) as ready,
    case
      when p.id is null then 'add_proof'
      when j.proof_state = 'revision_requested' then 'upload_revision'
      when j.proof_state = 'ready' then 'send_proof'
      when j.approval_state <> 'approved' then 'get_approval'
      when j.payment_state = 'pending' then 'collect_payment'
      else 'ready'
    end as next_action,
    j.created_at,
    j.updated_at
  from newsroom.legal_notice_jobs j
  left join lateral (
    select lp.id, lp.version, lp.file_name, lp.storage_path
    from newsroom.legal_notice_proofs lp
    where lp.job_id = j.id
    order by lp.version desc
    limit 1
  ) p on true
  where j.workspace_id = target_workspace
  order by coalesce(j.first_run_date, date '9999-12-31'), j.created_at desc;
end;
$$;

create or replace function public.newsroom_create_legal_notice_job(
  target_workspace uuid,
  target_title text,
  target_customer text default null,
  target_notice_type text default null,
  target_case_number text default null,
  target_first_run_date date default null,
  target_run_count integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null or not public.transcript_core_is_workspace_member(target_workspace) then
    raise exception 'not authorized';
  end if;
  if nullif(btrim(target_title), '') is null then
    raise exception 'title is required';
  end if;

  insert into newsroom.legal_notice_jobs (
    workspace_id, title, customer, notice_type, case_number,
    first_run_date, run_count, created_by
  ) values (
    target_workspace,
    btrim(target_title),
    nullif(btrim(target_customer), ''),
    nullif(btrim(target_notice_type), ''),
    nullif(btrim(target_case_number), ''),
    target_first_run_date,
    greatest(1, least(coalesce(target_run_count, 1), 52)),
    auth.uid()
  ) returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.newsroom_register_legal_notice_proof(
  target_job uuid,
  target_file_name text,
  target_storage_path text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_workspace uuid;
  next_version integer;
begin
  select j.workspace_id into target_workspace
  from newsroom.legal_notice_jobs j
  where j.id = target_job;

  if target_workspace is null or auth.uid() is null
     or not public.transcript_core_is_workspace_member(target_workspace) then
    raise exception 'not authorized';
  end if;

  select coalesce(max(p.version), 0) + 1 into next_version
  from newsroom.legal_notice_proofs p
  where p.job_id = target_job;

  insert into newsroom.legal_notice_proofs (
    job_id, version, file_name, storage_path, uploaded_by
  ) values (
    target_job, next_version, target_file_name, target_storage_path, auth.uid()
  );

  update newsroom.legal_notice_jobs
  set proof_state = 'ready',
      approval_state = 'waiting',
      approval_method = null,
      approved_at = null,
      approval_note = null,
      updated_at = now()
  where id = target_job;

  return next_version;
end;
$$;

create or replace function public.newsroom_legal_notice_action(
  target_job uuid,
  target_action text,
  target_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_workspace uuid;
  current_proof_state text;
  current_approval_state text;
begin
  select j.workspace_id, j.proof_state, j.approval_state
    into target_workspace, current_proof_state, current_approval_state
  from newsroom.legal_notice_jobs j
  where j.id = target_job;

  if target_workspace is null or auth.uid() is null
     or not public.transcript_core_is_workspace_member(target_workspace) then
    raise exception 'not authorized';
  end if;

  if target_action = 'proof_sent' then
    if current_proof_state <> 'ready' then raise exception 'proof is not ready to send'; end if;
    update newsroom.legal_notice_jobs
      set proof_state='sent', updated_at=now()
      where id=target_job;
  elsif target_action = 'revision_requested' then
    update newsroom.legal_notice_jobs
      set proof_state='revision_requested', approval_state='waiting', approval_method=null,
          approved_at=null, approval_note=target_note, updated_at=now()
      where id=target_job;
  elsif target_action in ('approved_email','approved_phone','approved_other') then
    if current_proof_state <> 'sent' then raise exception 'proof has not been sent'; end if;
    update newsroom.legal_notice_jobs
      set approval_state='approved',
          approval_method=case target_action when 'approved_email' then 'email' when 'approved_phone' then 'phone' else 'other' end,
          approved_at=now(), approval_note=target_note, updated_at=now()
      where id=target_job;
  elsif target_action in ('paid_online','paid_phone','payment_not_required') then
    if current_approval_state <> 'approved' then raise exception 'proof is not approved'; end if;
    update newsroom.legal_notice_jobs
      set payment_state=case target_action when 'paid_online' then 'paid_online' when 'paid_phone' then 'paid_phone' else 'not_required' end,
          payment_at=case when target_action='payment_not_required' then null else now() end,
          payment_note=target_note, updated_at=now()
      where id=target_job;
  else
    raise exception 'unknown action';
  end if;
end;
$$;

revoke all on function public.newsroom_list_legal_notice_jobs(uuid) from public;
revoke all on function public.newsroom_create_legal_notice_job(uuid,text,text,text,text,date,integer) from public;
revoke all on function public.newsroom_register_legal_notice_proof(uuid,text,text) from public;
revoke all on function public.newsroom_legal_notice_action(uuid,text,text) from public;

grant execute on function public.newsroom_list_legal_notice_jobs(uuid) to authenticated;
grant execute on function public.newsroom_create_legal_notice_job(uuid,text,text,text,text,date,integer) to authenticated;
grant execute on function public.newsroom_register_legal_notice_proof(uuid,text,text) to authenticated;
grant execute on function public.newsroom_legal_notice_action(uuid,text,text) to authenticated;