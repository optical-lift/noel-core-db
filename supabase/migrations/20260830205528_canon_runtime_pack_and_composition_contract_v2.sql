create table if not exists draft.canon_runtime_packs (
  id uuid primary key default gen_random_uuid(),
  pack_key text not null,
  version integer not null check (version > 0),
  pack_name text not null,
  status text not null check (status in ('candidate','shadow','retired')),
  contract_version text not null,
  activation_contract jsonb not null default '{}'::jsonb,
  fruit_contract jsonb not null default '{}'::jsonb,
  prohibitions text[] not null default '{}'::text[],
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (pack_key, version)
);

create table if not exists draft.canon_runtime_pack_members (
  pack_id uuid not null references draft.canon_runtime_packs(id) on delete cascade,
  song_adjudication_id bigint not null references draft.reality_song_adjudications(song_adjudication_id) on delete restrict,
  sequence_no integer not null check (sequence_no > 0),
  member_role text not null,
  required_adjudication_status text not null,
  required_canon_support_state text not null,
  adjudication_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  primary key (pack_id, song_adjudication_id),
  unique (pack_id, sequence_no)
);

alter table draft.canon_runtime_packs enable row level security;
alter table draft.canon_runtime_pack_members enable row level security;

create or replace function atlas.create_shadow_composition_run_v2(
  p_organization_id uuid,
  p_source_domain text,
  p_source_ref text,
  p_packet jsonb,
  p_canon_basis_refs text[] default array['adjudication:18','adjudication:19','adjudication:20','adjudication:21']::text[]
) returns uuid
language plpgsql
set search_path = pg_catalog
as $function$
declare
  v_run_id uuid;
  v_pack_id uuid;
  v_pack_key text;
  v_pack_version integer;
  v_fruit_mode text;
  v_member_count integer;
  v_valid_member_count integer;
  v_v1_packet jsonb;
begin
  if p_packet is null then
    raise exception 'composition packet is required';
  end if;

  if not (p_packet ?& array['contract_version','canon_runtime_pack','present_state','intended_fruit','protected_claims','required_operations','journey_steps','branches','excluded_candidates','terminal']) then
    raise exception 'composition packet missing required v2 contract fields';
  end if;

  if p_packet->>'contract_version' <> 'recursive_condition_bound_composition_v2' then
    raise exception 'unsupported composition contract version: %', p_packet->>'contract_version';
  end if;

  v_pack_key := p_packet->'canon_runtime_pack'->>'pack_key';
  v_pack_version := nullif(p_packet->'canon_runtime_pack'->>'version','')::integer;
  if v_pack_key is null or v_pack_version is null then
    raise exception 'canon_runtime_pack pack_key and version are required';
  end if;

  select id into v_pack_id
  from draft.canon_runtime_packs
  where pack_key=v_pack_key and version=v_pack_version and status='shadow' and contract_version='recursive_condition_bound_composition_v2';
  if v_pack_id is null then
    raise exception 'shadow canon runtime pack not found: % v%', v_pack_key, v_pack_version;
  end if;

  select count(*), count(*) filter (
    where a.adjudication_status in ('provisionally_resolved','resolved')
      and a.canon_support_state in ('supported','controlling')
      and a.adjudication_status = m.required_adjudication_status
      and a.canon_support_state = m.required_canon_support_state
  ) into v_member_count, v_valid_member_count
  from draft.canon_runtime_pack_members m
  join draft.reality_song_adjudications a on a.song_adjudication_id=m.song_adjudication_id
  where m.pack_id=v_pack_id;

  if v_member_count < 4 or v_member_count <> v_valid_member_count then
    raise exception 'canon runtime pack member custody failed: %/% valid', v_valid_member_count, v_member_count;
  end if;

  v_fruit_mode := p_packet->'intended_fruit'->>'mode';
  if v_fruit_mode not in ('controlling','bounded_discretion') then
    raise exception 'intended_fruit.mode must be controlling or bounded_discretion';
  end if;

  if v_fruit_mode='controlling' then
    if coalesce(p_packet->'intended_fruit'->>'fruit_key', p_packet->'intended_fruit'->>'description') is null then
      raise exception 'controlling intended_fruit requires fruit_key or description';
    end if;
  else
    if p_packet->'intended_fruit'->>'selection_authority' <> 'delegated_composition' then
      raise exception 'bounded_discretion requires selection_authority=delegated_composition';
    end if;
    if coalesce((p_packet->'intended_fruit'->>'not_unique_moral_route')::boolean,false) is not true then
      raise exception 'bounded_discretion requires not_unique_moral_route=true';
    end if;
    if jsonb_typeof(coalesce(p_packet->'intended_fruit'->'lawful_field_basis','null'::jsonb)) <> 'array' then
      raise exception 'bounded_discretion requires lawful_field_basis array';
    end if;
    if not exists (
      select 1 from draft.canon_runtime_pack_members m where m.pack_id=v_pack_id and m.song_adjudication_id=21
    ) then
      raise exception 'bounded_discretion requires adjudication 21 in runtime pack';
    end if;
  end if;

  v_v1_packet := jsonb_set(p_packet,'{contract_version}','"recursive_condition_bound_composition_v1"'::jsonb,false);
  v_run_id := atlas.create_shadow_composition_run_v1(p_organization_id,p_source_domain,p_source_ref,v_v1_packet,p_canon_basis_refs);

  update atlas.composition_runs
  set contract_version='recursive_condition_bound_composition_v2',
      intended_fruit=p_packet->'intended_fruit',
      source_payload=p_packet,
      metadata=metadata || jsonb_build_object(
        'canon_runtime_pack',p_packet->'canon_runtime_pack',
        'intended_fruit_mode',v_fruit_mode,
        'v2_validated',true
      ),
      updated_at=now()
  where id=v_run_id;

  update atlas.composition_journeys
  set metadata=metadata || jsonb_build_object('contract_version','recursive_condition_bound_composition_v2','intended_fruit_mode',v_fruit_mode),
      updated_at=now()
  where run_id=v_run_id;

  return v_run_id;
end;
$function$;

revoke all on function atlas.create_shadow_composition_run_v2(uuid,text,text,jsonb,text[]) from public;
