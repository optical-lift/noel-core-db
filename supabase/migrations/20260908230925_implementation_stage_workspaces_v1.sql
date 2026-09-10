create table if not exists atlas.implementation_establishment_items (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete cascade,
  category text not null check (category in ('institution','ledger_scope','people_authority','implementation_authority','boundary','unresolved')),
  title text not null check (length(btrim(title)) > 0),
  detail text not null default '',
  status text not null default 'proposed' check (status in ('proposed','established','unresolved','superseded')),
  author_user_id uuid not null,
  basis jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists implementation_establishment_items_case_idx
  on atlas.implementation_establishment_items(implementation_case_id, category, created_at);

create table if not exists atlas.implementation_threads (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete cascade,
  work_area text not null check (work_area in ('people','work','time','money','things_places','systems_evidence','access_authority','handoffs_completion','structure_mismatch','other_unresolved')),
  title text not null check (length(btrim(title)) > 0),
  state text not null default 'open' check (state in ('open','resolved','closed')),
  author_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists implementation_threads_case_idx
  on atlas.implementation_threads(implementation_case_id, work_area, created_at);

create table if not exists atlas.implementation_notes (
  id uuid primary key default gen_random_uuid(),
  implementation_thread_id uuid not null references atlas.implementation_threads(id) on delete cascade,
  body text not null check (length(btrim(body)) > 0),
  author_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists implementation_notes_thread_idx
  on atlas.implementation_notes(implementation_thread_id, created_at);

create table if not exists atlas.implementation_evidence_refs (
  id uuid primary key default gen_random_uuid(),
  implementation_thread_id uuid not null references atlas.implementation_threads(id) on delete cascade,
  evidence_kind text not null default 'other' check (evidence_kind in ('testimony','document','system','practitioner_observation','photo','record','other')),
  label text not null check (length(btrim(label)) > 0),
  detail text not null default '',
  reference_uri text,
  author_user_id uuid not null,
  created_at timestamptz not null default now()
);

create index if not exists implementation_evidence_refs_thread_idx
  on atlas.implementation_evidence_refs(implementation_thread_id, created_at);

create table if not exists atlas.implementation_findings (
  id uuid primary key default gen_random_uuid(),
  implementation_thread_id uuid not null references atlas.implementation_threads(id) on delete cascade,
  statement text not null check (length(btrim(statement)) > 0),
  status text not null default 'proposed' check (status in ('proposed','governed','rejected','superseded','unresolved')),
  author_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists implementation_findings_thread_idx
  on atlas.implementation_findings(implementation_thread_id, status, created_at);

create table if not exists atlas.implementation_requests (
  id uuid primary key default gen_random_uuid(),
  implementation_thread_id uuid not null references atlas.implementation_threads(id) on delete cascade,
  request_text text not null check (length(btrim(request_text)) > 0),
  status text not null default 'open' check (status in ('open','answered','closed')),
  author_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists implementation_requests_thread_idx
  on atlas.implementation_requests(implementation_thread_id, status, created_at);

alter table atlas.implementation_establishment_items enable row level security;
alter table atlas.implementation_threads enable row level security;
alter table atlas.implementation_notes enable row level security;
alter table atlas.implementation_evidence_refs enable row level security;
alter table atlas.implementation_findings enable row level security;
alter table atlas.implementation_requests enable row level security;

create or replace function atlas.implementation_case_workspace_self_api_v1(p_implementation_case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required');
  end if;

  if not exists (select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id) then
    return jsonb_build_object('ok',false,'code','case_not_found');
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_case_workspace_self_api_v1',
    'establishmentItems',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'category',e.category,'title',e.title,'detail',e.detail,'status',e.status,
        'createdAt',e.created_at,'updatedAt',e.updated_at
      ) order by e.created_at,e.id)
      from atlas.implementation_establishment_items e
      where e.implementation_case_id=p_implementation_case_id and e.status<>'superseded'
    ),'[]'::jsonb),
    'threads',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',t.id,'workArea',t.work_area,'title',t.title,'state',t.state,'createdAt',t.created_at,
        'notes',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'body',n.body,'createdAt',n.created_at) order by n.created_at,n.id) from atlas.implementation_notes n where n.implementation_thread_id=t.id),'[]'::jsonb),
        'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'kind',e.evidence_kind,'label',e.label,'detail',e.detail,'referenceUri',e.reference_uri,'createdAt',e.created_at) order by e.created_at,e.id) from atlas.implementation_evidence_refs e where e.implementation_thread_id=t.id),'[]'::jsonb),
        'findings',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'statement',f.statement,'status',f.status,'createdAt',f.created_at) order by f.created_at,f.id) from atlas.implementation_findings f where f.implementation_thread_id=t.id),'[]'::jsonb),
        'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'requestText',r.request_text,'status',r.status,'createdAt',r.created_at) order by r.created_at,r.id) from atlas.implementation_requests r where r.implementation_thread_id=t.id),'[]'::jsonb)
      ) order by t.created_at,t.id)
      from atlas.implementation_threads t
      where t.implementation_case_id=p_implementation_case_id
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function atlas.save_implementation_establishment_item_self_api_v1(
  p_implementation_case_id uuid,
  p_category text,
  p_title text,
  p_detail text default '',
  p_status text default 'proposed'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;
  if not exists (select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id and c.state not in ('closed','cancelled')) then
    raise exception 'Open implementation case not found.' using errcode='23503';
  end if;
  if p_category not in ('institution','ledger_scope','people_authority','implementation_authority','boundary','unresolved') then
    raise exception 'Invalid establishment category.' using errcode='22023';
  end if;
  if p_status not in ('proposed','established','unresolved') then
    raise exception 'Invalid establishment status.' using errcode='22023';
  end if;
  insert into atlas.implementation_establishment_items(
    implementation_case_id,category,title,detail,status,author_user_id,basis
  ) values (
    p_implementation_case_id,p_category,btrim(p_title),coalesce(p_detail,''),p_status,auth.uid(),
    jsonb_build_object('source','practitioner_workbench')
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end;
$$;

create or replace function atlas.create_implementation_thread_self_api_v1(
  p_implementation_case_id uuid,
  p_work_area text,
  p_title text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;
  if not exists (select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id and c.state not in ('closed','cancelled')) then
    raise exception 'Open implementation case not found.' using errcode='23503';
  end if;
  if p_work_area not in ('people','work','time','money','things_places','systems_evidence','access_authority','handoffs_completion','structure_mismatch','other_unresolved') then
    raise exception 'Invalid implementation work area.' using errcode='22023';
  end if;
  insert into atlas.implementation_threads(implementation_case_id,work_area,title,author_user_id)
  values(p_implementation_case_id,p_work_area,btrim(p_title),auth.uid()) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end;
$$;

create or replace function atlas.add_implementation_note_self_api_v1(p_implementation_thread_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists (select 1 from atlas.implementation_threads t join atlas.implementation_cases c on c.id=t.implementation_case_id where t.id=p_implementation_thread_id and c.state not in ('closed','cancelled')) then raise exception 'Open implementation thread not found.' using errcode='23503'; end if;
  insert into atlas.implementation_notes(implementation_thread_id,body,author_user_id) values(p_implementation_thread_id,btrim(p_body),auth.uid()) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function atlas.add_implementation_evidence_ref_self_api_v1(p_implementation_thread_id uuid,p_evidence_kind text,p_label text,p_detail text default '',p_reference_uri text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if p_evidence_kind not in ('testimony','document','system','practitioner_observation','photo','record','other') then raise exception 'Invalid evidence kind.' using errcode='22023'; end if;
  if not exists (select 1 from atlas.implementation_threads t join atlas.implementation_cases c on c.id=t.implementation_case_id where t.id=p_implementation_thread_id and c.state not in ('closed','cancelled')) then raise exception 'Open implementation thread not found.' using errcode='23503'; end if;
  insert into atlas.implementation_evidence_refs(implementation_thread_id,evidence_kind,label,detail,reference_uri,author_user_id) values(p_implementation_thread_id,p_evidence_kind,btrim(p_label),coalesce(p_detail,''),nullif(btrim(coalesce(p_reference_uri,'')),''),auth.uid()) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function atlas.add_implementation_finding_self_api_v1(p_implementation_thread_id uuid,p_statement text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists (select 1 from atlas.implementation_threads t join atlas.implementation_cases c on c.id=t.implementation_case_id where t.id=p_implementation_thread_id and c.state not in ('closed','cancelled')) then raise exception 'Open implementation thread not found.' using errcode='23503'; end if;
  insert into atlas.implementation_findings(implementation_thread_id,statement,author_user_id) values(p_implementation_thread_id,btrim(p_statement),auth.uid()) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function atlas.add_implementation_request_self_api_v1(p_implementation_thread_id uuid,p_request_text text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare v_id uuid;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then raise exception 'Practitioner authority required.' using errcode='42501'; end if;
  if not exists (select 1 from atlas.implementation_threads t join atlas.implementation_cases c on c.id=t.implementation_case_id where t.id=p_implementation_thread_id and c.state not in ('closed','cancelled')) then raise exception 'Open implementation thread not found.' using errcode='23503'; end if;
  insert into atlas.implementation_requests(implementation_thread_id,request_text,author_user_id) values(p_implementation_thread_id,btrim(p_request_text),auth.uid()) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end; $$;

create or replace function public.implementation_case_workspace_self_api_v1(p_implementation_case_id uuid)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.implementation_case_workspace_self_api_v1(p_implementation_case_id); $$;
create or replace function public.save_implementation_establishment_item_self_api_v1(p_implementation_case_id uuid,p_category text,p_title text,p_detail text default '',p_status text default 'proposed')
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.save_implementation_establishment_item_self_api_v1(p_implementation_case_id,p_category,p_title,p_detail,p_status); $$;
create or replace function public.create_implementation_thread_self_api_v1(p_implementation_case_id uuid,p_work_area text,p_title text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.create_implementation_thread_self_api_v1(p_implementation_case_id,p_work_area,p_title); $$;
create or replace function public.add_implementation_note_self_api_v1(p_implementation_thread_id uuid,p_body text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.add_implementation_note_self_api_v1(p_implementation_thread_id,p_body); $$;
create or replace function public.add_implementation_evidence_ref_self_api_v1(p_implementation_thread_id uuid,p_evidence_kind text,p_label text,p_detail text default '',p_reference_uri text default null)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.add_implementation_evidence_ref_self_api_v1(p_implementation_thread_id,p_evidence_kind,p_label,p_detail,p_reference_uri); $$;
create or replace function public.add_implementation_finding_self_api_v1(p_implementation_thread_id uuid,p_statement text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.add_implementation_finding_self_api_v1(p_implementation_thread_id,p_statement); $$;
create or replace function public.add_implementation_request_self_api_v1(p_implementation_thread_id uuid,p_request_text text)
returns jsonb language sql security definer set search_path=pg_catalog as $$ select atlas.add_implementation_request_self_api_v1(p_implementation_thread_id,p_request_text); $$;

revoke all on function public.implementation_case_workspace_self_api_v1(uuid) from public;
revoke all on function public.save_implementation_establishment_item_self_api_v1(uuid,text,text,text,text) from public;
revoke all on function public.create_implementation_thread_self_api_v1(uuid,text,text) from public;
revoke all on function public.add_implementation_note_self_api_v1(uuid,text) from public;
revoke all on function public.add_implementation_evidence_ref_self_api_v1(uuid,text,text,text,text) from public;
revoke all on function public.add_implementation_finding_self_api_v1(uuid,text) from public;
revoke all on function public.add_implementation_request_self_api_v1(uuid,text) from public;

grant execute on function public.implementation_case_workspace_self_api_v1(uuid) to authenticated;
grant execute on function public.save_implementation_establishment_item_self_api_v1(uuid,text,text,text,text) to authenticated;
grant execute on function public.create_implementation_thread_self_api_v1(uuid,text,text) to authenticated;
grant execute on function public.add_implementation_note_self_api_v1(uuid,text) to authenticated;
grant execute on function public.add_implementation_evidence_ref_self_api_v1(uuid,text,text,text,text) to authenticated;
grant execute on function public.add_implementation_finding_self_api_v1(uuid,text) to authenticated;
grant execute on function public.add_implementation_request_self_api_v1(uuid,text) to authenticated;