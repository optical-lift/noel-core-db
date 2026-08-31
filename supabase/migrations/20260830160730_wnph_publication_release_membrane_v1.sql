create table if not exists wnph.publication_releases (
  id uuid primary key default gen_random_uuid(),
  release_key text not null unique,
  public_slug text not null,
  work_id uuid not null references wnph.historical_works(id),
  expression_id uuid not null references wnph.expressions(id),
  release_sequence integer not null check (release_sequence > 0),
  release_state text not null check (release_state in ('released','withdrawn')),
  render_master_sha256 text not null check (render_master_sha256 ~ '^[0-9a-f]{64}$'),
  public_payload jsonb,
  payload_sha256 text check (payload_sha256 is null or payload_sha256 ~ '^[0-9a-f]{64}$'),
  supersedes_release_id uuid references wnph.publication_releases(id),
  decision_basis jsonb not null default '{}'::jsonb,
  released_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  constraint wnph_publication_release_payload_state_ck check (
    (release_state='released' and public_payload is not null and payload_sha256 is not null)
    or (release_state='withdrawn' and public_payload is null and payload_sha256 is null)
  ),
  constraint wnph_publication_release_sequence_uq unique (work_id, release_sequence)
);

create unique index if not exists wnph_publication_releases_supersession_no_fork_uq
  on wnph.publication_releases(supersedes_release_id)
  where supersedes_release_id is not null;

create index if not exists wnph_publication_releases_public_slug_idx
  on wnph.publication_releases(public_slug, release_sequence desc);

alter table wnph.publication_releases enable row level security;
revoke all on wnph.publication_releases from public, anon, authenticated;

create or replace function wnph.guard_publication_release_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','wnph'
as $fn$
begin
  raise exception 'WNPH publication releases are append-only; create a superseding release decision instead' using errcode='55000';
end;
$fn$;

drop trigger if exists wnph_publication_releases_immutable_v1 on wnph.publication_releases;
create trigger wnph_publication_releases_immutable_v1
before update or delete on wnph.publication_releases
for each row execute function wnph.guard_publication_release_immutable_v1();

create or replace function public.wnph_create_publication_release_v1(
  p_expression_key text,
  p_public_slug text,
  p_release_key text,
  p_supersedes_release_key text default null,
  p_decision_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public','extensions'
as $fn$
declare
  v_expr wnph.expressions%rowtype;
  v_work wnph.historical_works%rowtype;
  v_packet jsonb;
  v_snapshot jsonb;
  v_prior wnph.publication_releases%rowtype;
  v_active wnph.publication_releases%rowtype;
  v_release_sequence integer;
  v_released_at timestamptz := clock_timestamp();
  v_public_media jsonb;
  v_public_rights jsonb;
  v_payload jsonb;
  v_payload_sha text;
  v_new_id uuid;
begin
  if p_public_slug is null or p_public_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'WNPH publication release: invalid public slug' using errcode='22023';
  end if;
  if p_release_key is null or btrim(p_release_key)='' then
    raise exception 'WNPH publication release: release key required' using errcode='22023';
  end if;

  select * into v_expr from wnph.expressions where canonical_key=p_expression_key;
  if v_expr.id is null then
    raise exception 'WNPH publication release: Expression not found' using errcode='P0002';
  end if;
  select * into v_work from wnph.historical_works where id=v_expr.work_id;

  v_packet := public.wnph_publication_render_packet_v2(p_expression_key);
  v_snapshot := v_packet->'master_snapshot';

  if coalesce((v_packet->>'reproducible_build_ready')::boolean,false) is not true
     or coalesce((v_snapshot->>'unreceipted_media_count')::integer,0) <> 0 then
    raise exception 'WNPH publication release: Expression is not reproducible-build ready' using errcode='55000';
  end if;

  select r.* into v_active
  from wnph.publication_releases r
  where r.work_id=v_work.id
    and not exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id)
  order by r.release_sequence desc
  limit 1;

  if p_supersedes_release_key is null then
    if v_active.id is not null then
      raise exception 'WNPH publication release: active release exists; explicit supersession required' using errcode='55000';
    end if;
    v_release_sequence := 1;
  else
    select * into v_prior from wnph.publication_releases where release_key=p_supersedes_release_key;
    if v_prior.id is null then
      raise exception 'WNPH publication release: superseded release not found' using errcode='P0002';
    end if;
    if v_prior.work_id <> v_work.id then
      raise exception 'WNPH publication release: supersession cannot cross Works' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=v_prior.id) then
      raise exception 'WNPH publication release: superseded release is no longer active' using errcode='55000';
    end if;
    if v_active.id is distinct from v_prior.id then
      raise exception 'WNPH publication release: supersession target is not the active Work release' using errcode='55000';
    end if;
    v_release_sequence := v_prior.release_sequence + 1;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'placement_key',m->>'placement_key',
      'sequence_ordinal',(m->>'sequence_ordinal')::integer,
      'media_role',m->>'media_role',
      'anchor_kind',m->>'anchor_kind',
      'anchor_block_key',m->'anchor_block_key',
      'anchor_data',coalesce(m->'anchor_data','{}'::jsonb),
      'placement_policy',coalesce(m->'placement_policy','{}'::jsonb),
      'accessibility',coalesce(m->'accessibility','{}'::jsonb),
      'image',jsonb_build_object(
        'url',m#>>'{publication_raster,fetch_uri}',
        'media_type',m#>>'{publication_raster,media_type}',
        'byte_length',(m#>>'{publication_raster,byte_length}')::bigint,
        'sha256',m#>>'{publication_raster,sha256}'
      )
    ) order by (m->>'sequence_ordinal')::integer, m->>'placement_key'
  ),'[]'::jsonb)
  into v_public_media
  from jsonb_array_elements(v_packet->'media_placements') m;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'component_type',r->>'component_type',
      'status',r->>'component_status',
      'use_scope',r->>'use_scope'
    ) order by r->>'component_type'
  ),'[]'::jsonb)
  into v_public_rights
  from jsonb_array_elements(v_packet->'rights') r;

  v_payload := jsonb_build_object(
    'contract_version','wnph_publication_public_release_payload_v1',
    'release',jsonb_build_object(
      'release_key',p_release_key,
      'public_slug',p_public_slug,
      'release_sequence',v_release_sequence,
      'released_at',to_jsonb(v_released_at),
      'render_master_sha256',v_snapshot->>'render_master_sha256',
      'frozen',true,
      'read_only',true
    ),
    'bibliographic',v_packet->'bibliographic',
    'rights',v_public_rights,
    'chapters',v_packet->'chapters',
    'ordered_blocks',v_packet->'ordered_blocks',
    'media_placements',v_public_media,
    'public_provenance',jsonb_build_object(
      'publisher','Write Now Publishing House',
      'publication_expression_is_private_authority',true,
      'public_release_is_downstream_manifestation',true,
      'source_and_editorial_custody_not_exposed',true,
      'content_addressed_master',true
    )
  );

  v_payload_sha := encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');

  insert into wnph.publication_releases(
    release_key,public_slug,work_id,expression_id,release_sequence,release_state,
    render_master_sha256,public_payload,payload_sha256,supersedes_release_id,
    decision_basis,released_at
  ) values (
    p_release_key,p_public_slug,v_work.id,v_expr.id,v_release_sequence,'released',
    v_snapshot->>'render_master_sha256',v_payload,v_payload_sha,v_prior.id,
    coalesce(p_decision_basis,'{}'::jsonb),v_released_at
  ) returning id into v_new_id;

  return jsonb_build_object(
    'release_id',v_new_id,
    'release_key',p_release_key,
    'release_sequence',v_release_sequence,
    'render_master_sha256',v_snapshot->>'render_master_sha256',
    'payload_sha256',v_payload_sha,
    'public_slug',p_public_slug
  );
end;
$fn$;

create or replace function public.wnph_withdraw_publication_release_v1(
  p_release_key text,
  p_withdrawal_key text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public'
as $fn$
declare
  v_prior wnph.publication_releases%rowtype;
  v_new_id uuid;
begin
  select * into v_prior from wnph.publication_releases where release_key=p_release_key;
  if v_prior.id is null then raise exception 'WNPH publication withdrawal: release not found' using errcode='P0002'; end if;
  if exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=v_prior.id) then
    raise exception 'WNPH publication withdrawal: release is no longer active' using errcode='55000';
  end if;
  if p_reason is null or btrim(p_reason)='' then raise exception 'WNPH publication withdrawal: reason required' using errcode='22023'; end if;

  insert into wnph.publication_releases(
    release_key,public_slug,work_id,expression_id,release_sequence,release_state,
    render_master_sha256,public_payload,payload_sha256,supersedes_release_id,
    decision_basis,released_at
  ) values (
    p_withdrawal_key,v_prior.public_slug,v_prior.work_id,v_prior.expression_id,
    v_prior.release_sequence+1,'withdrawn',v_prior.render_master_sha256,null,null,v_prior.id,
    jsonb_build_object('withdrawal_reason',p_reason,'withdraws_release_key',p_release_key),clock_timestamp()
  ) returning id into v_new_id;

  return jsonb_build_object('withdrawal_id',v_new_id,'withdrawal_key',p_withdrawal_key,'withdrawn_release_key',p_release_key);
end;
$fn$;

create or replace function public.wnph_publication_release_v1(p_public_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','wnph','public'
as $fn$
declare
  v_release wnph.publication_releases%rowtype;
begin
  select r.* into v_release
  from wnph.publication_releases r
  where r.public_slug=p_public_slug
    and not exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id)
  order by r.release_sequence desc
  limit 1;

  if v_release.id is null or v_release.release_state <> 'released' then
    raise exception 'WNPH public release not found' using errcode='P0002';
  end if;

  return jsonb_build_object(
    'contract_version','wnph_publication_release_v1',
    'payload_sha256',v_release.payload_sha256,
    'payload',v_release.public_payload
  );
end;
$fn$;

revoke all on function public.wnph_create_publication_release_v1(text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.wnph_withdraw_publication_release_v1(text,text,text) from public, anon, authenticated;
grant execute on function public.wnph_create_publication_release_v1(text,text,text,text,jsonb) to service_role;
grant execute on function public.wnph_withdraw_publication_release_v1(text,text,text) to service_role;

revoke all on function public.wnph_publication_release_v1(text) from public;
grant execute on function public.wnph_publication_release_v1(text) to anon, authenticated, service_role;
