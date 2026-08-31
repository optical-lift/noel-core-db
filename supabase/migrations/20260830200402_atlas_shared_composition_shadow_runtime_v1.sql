create table atlas.composition_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  contract_version text not null,
  mode text not null default 'shadow' check (mode = 'shadow'),
  source_domain text not null,
  source_ref text,
  request_class text,
  present_state jsonb not null,
  intended_fruit jsonb not null,
  protected_claims jsonb not null default '[]'::jsonb,
  constraints jsonb not null default '[]'::jsonb,
  canon_basis_refs text[] not null default '{}'::text[],
  terminal_status text check (terminal_status is null or terminal_status in ('fruit_reached','fruit_sufficiently_reached','lawful_early_exit','rerouted','blocked','unresolved','transferred','stored_for_later_release')),
  status text not null default 'draft' check (status in ('draft','composed','adjudicated','failed')),
  source_payload jsonb not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table atlas.composition_requirements (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.composition_runs(id) on delete cascade,
  requirement_type text not null check (requirement_type in ('required_operation','protected_claim','constraint')),
  requirement_key text not null,
  sequence integer,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table atlas.composition_candidates (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.composition_runs(id) on delete cascade,
  carrier_ref text not null,
  operation_key text,
  candidate_status text not null check (candidate_status in ('selected','eligible','excluded','unresolved','blocked','deferred')),
  source_domain text not null,
  facts jsonb not null default '{}'::jsonb,
  rationale text,
  created_at timestamptz not null default now(),
  unique (run_id, carrier_ref, candidate_status)
);

create table atlas.composition_journeys (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.composition_runs(id) on delete cascade,
  journey_key text not null default 'selected',
  is_selected boolean not null default false,
  terminal_status text check (terminal_status is null or terminal_status in ('fruit_reached','fruit_sufficiently_reached','lawful_early_exit','rerouted','blocked','unresolved','transferred','stored_for_later_release')),
  summary text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (run_id, journey_key)
);

create table atlas.composition_journey_steps (
  id uuid primary key default gen_random_uuid(),
  journey_id uuid not null references atlas.composition_journeys(id) on delete cascade,
  sequence integer not null,
  operation_key text not null,
  carrier_ref text not null,
  before_state jsonb not null,
  expected_after_state jsonb not null,
  entry_condition text not null,
  exit_condition text not null,
  evidence jsonb not null default '[]'::jsonb,
  costs jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (journey_id, sequence)
);

create table atlas.composition_branches (
  id uuid primary key default gen_random_uuid(),
  journey_id uuid not null references atlas.composition_journeys(id) on delete cascade,
  from_sequence integer,
  condition text not null,
  action text not null,
  preserves_fruit boolean not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table atlas.composition_adjudications (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.composition_runs(id) on delete cascade,
  subject_type text not null check (subject_type in ('run','journey','step','candidate','terminal')),
  subject_ref text not null,
  verdict text not null check (verdict in ('selected','eligible','excluded','unresolved','blocked','rerouted','sufficient','failed')),
  rationale text not null,
  evidence jsonb not null default '[]'::jsonb,
  canon_basis_refs text[] not null default '{}'::text[],
  created_at timestamptz not null default now()
);

create index composition_runs_org_created_idx on atlas.composition_runs (organization_id, created_at desc);
create index composition_runs_source_idx on atlas.composition_runs (source_domain, source_ref);
create index composition_requirements_run_idx on atlas.composition_requirements (run_id, requirement_type, sequence);
create index composition_candidates_run_idx on atlas.composition_candidates (run_id, candidate_status);
create index composition_journeys_run_idx on atlas.composition_journeys (run_id, is_selected);
create index composition_steps_journey_idx on atlas.composition_journey_steps (journey_id, sequence);
create index composition_branches_journey_idx on atlas.composition_branches (journey_id, from_sequence);
create index composition_adjudications_run_idx on atlas.composition_adjudications (run_id, subject_type);

alter table atlas.composition_runs enable row level security;
alter table atlas.composition_requirements enable row level security;
alter table atlas.composition_candidates enable row level security;
alter table atlas.composition_journeys enable row level security;
alter table atlas.composition_journey_steps enable row level security;
alter table atlas.composition_branches enable row level security;
alter table atlas.composition_adjudications enable row level security;

create or replace function atlas.create_shadow_composition_run_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_ref text,
  p_packet jsonb,
  p_canon_basis_refs text[] default array['adjudication:18','adjudication:19']::text[]
) returns uuid
language plpgsql
as $$
declare
  v_run_id uuid;
  v_journey_id uuid;
  v_item jsonb;
  v_key text;
  v_terminal text;
begin
  if p_packet is null then
    raise exception 'composition packet is required';
  end if;

  if not (p_packet ?& array['contract_version','present_state','intended_fruit','protected_claims','required_operations','journey_steps','branches','excluded_candidates','terminal']) then
    raise exception 'composition packet missing required contract fields';
  end if;

  if p_packet->>'contract_version' <> 'recursive_condition_bound_composition_v1' then
    raise exception 'unsupported composition contract version: %', p_packet->>'contract_version';
  end if;

  v_terminal := p_packet->'terminal'->>'status';
  if v_terminal is null or v_terminal <> all(array['fruit_reached','fruit_sufficiently_reached','lawful_early_exit','rerouted','blocked','unresolved','transferred','stored_for_later_release']) then
    raise exception 'invalid terminal status: %', v_terminal;
  end if;

  insert into atlas.composition_runs (
    organization_id, contract_version, mode, source_domain, source_ref, request_class,
    present_state, intended_fruit, protected_claims, constraints, canon_basis_refs,
    terminal_status, status, source_payload, metadata
  ) values (
    p_organization_id,
    p_packet->>'contract_version',
    'shadow',
    p_source_domain,
    p_source_ref,
    p_packet->>'request_class',
    p_packet->'present_state',
    p_packet->'intended_fruit',
    coalesce(p_packet->'protected_claims','[]'::jsonb),
    coalesce(p_packet->'constraints','[]'::jsonb),
    p_canon_basis_refs,
    v_terminal,
    'draft',
    p_packet,
    jsonb_build_object('fact_class',p_packet->>'fact_class','fixture_key',p_packet->>'fixture_key')
  ) returning id into v_run_id;

  for v_item in select value from jsonb_array_elements(coalesce(p_packet->'protected_claims','[]'::jsonb)) loop
    v_key := case when jsonb_typeof(v_item)='string' then trim(both '"' from v_item::text) else v_item::text end;
    insert into atlas.composition_requirements(run_id,requirement_type,requirement_key,details)
    values (v_run_id,'protected_claim',v_key,jsonb_build_object('source','packet'));
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_packet->'required_operations','[]'::jsonb)) loop
    v_key := case when jsonb_typeof(v_item)='string' then trim(both '"' from v_item::text) else v_item::text end;
    insert into atlas.composition_requirements(run_id,requirement_type,requirement_key,details)
    values (v_run_id,'required_operation',v_key,jsonb_build_object('source','packet'));
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_packet->'constraints','[]'::jsonb)) loop
    v_key := case when jsonb_typeof(v_item)='string' then trim(both '"' from v_item::text) else coalesce(v_item->>'key',v_item::text) end;
    insert into atlas.composition_requirements(run_id,requirement_type,requirement_key,details)
    values (v_run_id,'constraint',v_key,case when jsonb_typeof(v_item)='object' then v_item else jsonb_build_object('value',v_item) end);
  end loop;

  insert into atlas.composition_journeys(run_id,journey_key,is_selected,terminal_status,summary,metadata)
  values (v_run_id,'selected',true,v_terminal,p_packet->>'fixture_key',jsonb_build_object('contract_version',p_packet->>'contract_version'))
  returning id into v_journey_id;

  for v_item in select value from jsonb_array_elements(p_packet->'journey_steps') loop
    if not (v_item ?& array['sequence','operation_key','carrier_ref','before_state','expected_after_state','entry_condition','exit_condition']) then
      raise exception 'journey step missing required fields: %', v_item;
    end if;

    insert into atlas.composition_candidates(run_id,carrier_ref,operation_key,candidate_status,source_domain,facts,rationale)
    values (v_run_id,v_item->>'carrier_ref',v_item->>'operation_key','selected',p_source_domain,coalesce(v_item->'facts','{}'::jsonb),'selected by supplied composition packet')
    on conflict (run_id,carrier_ref,candidate_status) do nothing;

    insert into atlas.composition_journey_steps(
      journey_id,sequence,operation_key,carrier_ref,before_state,expected_after_state,
      entry_condition,exit_condition,evidence,costs,metadata
    ) values (
      v_journey_id,(v_item->>'sequence')::integer,v_item->>'operation_key',v_item->>'carrier_ref',
      v_item->'before_state',v_item->'expected_after_state',v_item->>'entry_condition',v_item->>'exit_condition',
      coalesce(v_item->'evidence','[]'::jsonb),coalesce(v_item->'costs','{}'::jsonb),
      v_item - array['sequence','operation_key','carrier_ref','before_state','expected_after_state','entry_condition','exit_condition','evidence','costs']
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_packet->'branches') loop
    if not (v_item ?& array['condition','action','preserves_fruit']) then
      raise exception 'branch missing required fields: %', v_item;
    end if;
    insert into atlas.composition_branches(journey_id,from_sequence,condition,action,preserves_fruit,metadata)
    values (v_journey_id,nullif(v_item->>'from_sequence','')::integer,v_item->>'condition',v_item->>'action',(v_item->>'preserves_fruit')::boolean,
      v_item - array['from_sequence','condition','action','preserves_fruit']);
  end loop;

  for v_item in select value from jsonb_array_elements(p_packet->'excluded_candidates') loop
    insert into atlas.composition_candidates(run_id,carrier_ref,operation_key,candidate_status,source_domain,facts,rationale)
    values (v_run_id,v_item->>'carrier_ref',v_item->>'operation_key','excluded',p_source_domain,coalesce(v_item->'facts','{}'::jsonb),coalesce(v_item->>'reason','explicitly excluded by packet'))
    on conflict (run_id,carrier_ref,candidate_status) do nothing;

    insert into atlas.composition_adjudications(run_id,subject_type,subject_ref,verdict,rationale,evidence,canon_basis_refs)
    values (v_run_id,'candidate',v_item->>'carrier_ref','excluded',coalesce(v_item->>'reason','explicitly excluded by packet'),coalesce(v_item->'evidence','[]'::jsonb),p_canon_basis_refs);
  end loop;

  insert into atlas.composition_adjudications(run_id,subject_type,subject_ref,verdict,rationale,evidence,canon_basis_refs)
  values (v_run_id,'terminal','selected',case when v_terminal='rerouted' then 'rerouted' when v_terminal in ('fruit_reached','fruit_sufficiently_reached','lawful_early_exit') then 'sufficient' when v_terminal='blocked' then 'blocked' when v_terminal='unresolved' then 'unresolved' else 'selected' end,
    coalesce(p_packet->'terminal'->>'evidence','terminal state supplied by packet'),'[]'::jsonb,p_canon_basis_refs);

  update atlas.composition_runs set status='composed', updated_at=now() where id=v_run_id;
  return v_run_id;
end;
$$;