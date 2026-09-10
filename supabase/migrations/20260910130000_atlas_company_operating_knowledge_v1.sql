-- Atlas Company Operating Knowledge v1
-- Durable institution-specific standards and procedures that may be resolved into execution context.
-- Canonical DB authority: optical-lift/noel-core-db.

create table atlas.company_operating_knowledge (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  organization_unit_id uuid null references atlas.organization_units(id),
  family_key text not null,
  stable_key text not null,
  version integer not null default 1 check (version > 0),
  knowledge_kind text not null check (knowledge_kind in (
    'standard', 'procedure', 'expected_condition', 'substitution',
    'completion_semantics', 'quality_requirement', 'escalation_rule',
    'role_boundary', 'local_terminology', 'handling_instruction', 'policy'
  )),
  title text not null,
  statement text not null,
  scope_match jsonb not null default '{}'::jsonb,
  effect jsonb not null default '{}'::jsonb,
  precedence integer not null default 0,
  status text not null default 'candidate' check (status in (
    'candidate', 'established', 'disputed', 'superseded', 'retired'
  )),
  confidence numeric(5,4) null check (confidence is null or (confidence >= 0 and confidence <= 1)),
  effective_from timestamptz null,
  effective_to timestamptz null,
  supersedes_id uuid null references atlas.company_operating_knowledge(id),
  established_by_user_id uuid null references auth.users(id),
  established_by_label text null,
  established_at timestamptz null,
  review_after timestamptz null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_operating_knowledge_scope_object check (jsonb_typeof(scope_match) = 'object'),
  constraint company_operating_knowledge_effect_object check (jsonb_typeof(effect) = 'object'),
  constraint company_operating_knowledge_effective_window check (effective_to is null or effective_from is null or effective_to > effective_from),
  constraint company_operating_knowledge_established_accounting check (
    status <> 'established'
    or (
      established_at is not null
      and (established_by_user_id is not null or nullif(btrim(established_by_label), '') is not null)
    )
  ),
  unique (organization_id, stable_key, version)
);

comment on table atlas.company_operating_knowledge is
  'Governed institution-specific standards, procedures, and durable operating rules. Candidate/model-inferred items do not govern execution until status=established.';
comment on column atlas.company_operating_knowledge.scope_match is
  'Context predicate for applicability. v1 resolution requires the supplied runtime context JSON to contain this JSON object.';
comment on column atlas.company_operating_knowledge.effect is
  'Structured machine-usable consequence of the knowledge item; human-readable meaning remains in statement.';
comment on column atlas.company_operating_knowledge.precedence is
  'Explicit tie-break priority after scope specificity. Equal specificity and precedence are treated as a conflict, not silently resolved.';

create index company_operating_knowledge_active_lookup_idx
  on atlas.company_operating_knowledge (organization_id, knowledge_kind, status, precedence desc, effective_from desc);

create index company_operating_knowledge_unit_idx
  on atlas.company_operating_knowledge (organization_unit_id)
  where organization_unit_id is not null;

create table atlas.company_operating_knowledge_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  knowledge_id uuid not null references atlas.company_operating_knowledge(id),
  evidence_kind text not null check (evidence_kind in (
    'document', 'interview', 'connected_source_observation', 'canonical_record',
    'transaction_history', 'human_observation', 'model_inference', 'other'
  )),
  interpretation_kind text not null default 'supports' check (interpretation_kind in (
    'originates', 'supports', 'contradicts', 'qualifies'
  )),
  source_locator jsonb not null default '{}'::jsonb,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  note text null,
  observed_at timestamptz null,
  created_by_user_id uuid null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint company_operating_knowledge_evidence_locator_object check (jsonb_typeof(source_locator) = 'object'),
  constraint company_operating_knowledge_evidence_snapshot_object check (jsonb_typeof(evidence_snapshot) = 'object')
);

comment on table atlas.company_operating_knowledge_evidence is
  'Evidence supporting, contradicting, qualifying, or originating a Company Operating Knowledge candidate or established item.';

create index company_operating_knowledge_evidence_knowledge_idx
  on atlas.company_operating_knowledge_evidence (knowledge_id, created_at);

create table atlas.company_operating_knowledge_adjudications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  knowledge_id uuid not null references atlas.company_operating_knowledge(id),
  decision_kind text not null check (decision_kind in (
    'establish', 'reject', 'dispute', 'supersede', 'retire', 'reopen'
  )),
  basis text not null,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  adjudicated_by_user_id uuid null references auth.users(id),
  adjudicated_by_label text not null,
  created_at timestamptz not null default now(),
  constraint company_operating_knowledge_adjudication_snapshot_object check (jsonb_typeof(evidence_snapshot) = 'object')
);

comment on table atlas.company_operating_knowledge_adjudications is
  'Append-only accounting for human/institutional judgments about Company Operating Knowledge.';

create index company_operating_knowledge_adjudications_knowledge_idx
  on atlas.company_operating_knowledge_adjudications (knowledge_id, created_at);

-- Keep every scoped reference inside the owning organization.
create or replace function atlas.guard_company_operating_knowledge_scope_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
declare
  v_organization_id uuid;
begin
  if tg_table_name = 'company_operating_knowledge' then
    if new.organization_unit_id is not null and not exists (
      select 1 from atlas.organization_units u
      where u.id = new.organization_unit_id
        and u.organization_id = new.organization_id
    ) then
      raise exception 'organization unit does not belong to Company Operating Knowledge organization';
    end if;

    if new.supersedes_id is not null and not exists (
      select 1 from atlas.company_operating_knowledge k
      where k.id = new.supersedes_id
        and k.organization_id = new.organization_id
        and k.family_key = new.family_key
    ) then
      raise exception 'superseded Company Operating Knowledge item must belong to the same organization and family';
    end if;

    return new;
  end if;

  select k.organization_id into v_organization_id
  from atlas.company_operating_knowledge k
  where k.id = new.knowledge_id;

  if v_organization_id is null or v_organization_id <> new.organization_id then
    raise exception 'Company Operating Knowledge history must belong to the same organization as its knowledge item';
  end if;

  return new;
end;
$$;

create trigger company_operating_knowledge_scope_guard
before insert or update on atlas.company_operating_knowledge
for each row execute function atlas.guard_company_operating_knowledge_scope_v1();

create trigger company_operating_knowledge_evidence_scope_guard
before insert on atlas.company_operating_knowledge_evidence
for each row execute function atlas.guard_company_operating_knowledge_scope_v1();

create trigger company_operating_knowledge_adjudications_scope_guard
before insert on atlas.company_operating_knowledge_adjudications
for each row execute function atlas.guard_company_operating_knowledge_scope_v1();

-- Established semantics are versioned rather than rewritten in place.
create or replace function atlas.guard_established_company_operating_knowledge_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
begin
  if old.status = 'established' and (
    new.organization_id is distinct from old.organization_id
    or new.organization_unit_id is distinct from old.organization_unit_id
    or new.family_key is distinct from old.family_key
    or new.stable_key is distinct from old.stable_key
    or new.version is distinct from old.version
    or new.knowledge_kind is distinct from old.knowledge_kind
    or new.title is distinct from old.title
    or new.statement is distinct from old.statement
    or new.scope_match is distinct from old.scope_match
    or new.effect is distinct from old.effect
    or new.precedence is distinct from old.precedence
    or new.effective_from is distinct from old.effective_from
    or new.established_by_user_id is distinct from old.established_by_user_id
    or new.established_by_label is distinct from old.established_by_label
    or new.established_at is distinct from old.established_at
  ) then
    raise exception 'established Company Operating Knowledge semantics are immutable; create a new version and supersede the prior item';
  end if;

  return new;
end;
$$;

create trigger company_operating_knowledge_established_semantics_guard
before update on atlas.company_operating_knowledge
for each row execute function atlas.guard_established_company_operating_knowledge_mutation_v1();

-- Prevent evidence/adjudication history from being rewritten in place.
create or replace function atlas.prevent_company_operating_knowledge_history_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
begin
  raise exception '% is append-only', tg_table_name;
end;
$$;

create trigger company_operating_knowledge_evidence_append_only
before update or delete on atlas.company_operating_knowledge_evidence
for each row execute function atlas.prevent_company_operating_knowledge_history_mutation_v1();

create trigger company_operating_knowledge_adjudications_append_only
before update or delete on atlas.company_operating_knowledge_adjudications
for each row execute function atlas.prevent_company_operating_knowledge_history_mutation_v1();

-- Runtime resolver. Only established knowledge may become executable context.
-- More keys in scope_match means more specific. precedence breaks specificity tiers.
-- A top-rank tie remains an explicit conflict unless the tied effects/statements are identical.
create or replace function atlas.resolve_company_operating_knowledge_v1(
  p_organization_id uuid,
  p_knowledge_kind text,
  p_context jsonb,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not atlas.is_organization_member(p_organization_id) then
    raise exception 'organization membership required';
  end if;

  if p_context is null or jsonb_typeof(p_context) <> 'object' then
    raise exception 'p_context must be a JSON object';
  end if;

  with candidates as (
    select
      k.*,
      (select count(*)::integer from jsonb_object_keys(k.scope_match)) as specificity
    from atlas.company_operating_knowledge k
    where k.organization_id = p_organization_id
      and k.knowledge_kind = p_knowledge_kind
      and k.status = 'established'
      and (k.organization_unit_id is null
        or k.organization_unit_id = nullif(p_context->>'organization_unit_id', '')::uuid)
      and coalesce(k.effective_from, '-infinity'::timestamptz) <= p_as_of
      and coalesce(k.effective_to, 'infinity'::timestamptz) > p_as_of
      and p_context @> k.scope_match
  ), ranked as (
    select
      c.*,
      dense_rank() over (order by c.specificity desc, c.precedence desc) as rank_no
    from candidates c
  ), top_rank as (
    select * from ranked where rank_no = 1
  ), summary as (
    select
      count(*)::integer as match_count,
      count(distinct (effect::text, statement))::integer as distinct_result_count,
      coalesce(jsonb_agg(jsonb_build_object(
        'id', id,
        'stable_key', stable_key,
        'version', version,
        'title', title,
        'statement', statement,
        'effect', effect,
        'scope_match', scope_match,
        'specificity', specificity,
        'precedence', precedence,
        'effective_from', effective_from,
        'review_after', review_after
      ) order by stable_key, version), '[]'::jsonb) as matches
    from top_rank
  )
  select jsonb_build_object(
    'resolution_state', case
      when match_count = 0 then 'not_found'
      when distinct_result_count > 1 then 'conflict'
      else 'resolved'
    end,
    'organization_id', p_organization_id,
    'knowledge_kind', p_knowledge_kind,
    'context', p_context,
    'as_of', p_as_of,
    'matches', matches,
    'resolved_effect', case
      when match_count > 0 and distinct_result_count = 1 then matches->0->'effect'
      else null
    end,
    'resolved_statement', case
      when match_count > 0 and distinct_result_count = 1 then matches->0->'statement'
      else null
    end
  )
  into v_result
  from summary;

  return v_result;
end;
$$;

alter table atlas.company_operating_knowledge enable row level security;
alter table atlas.company_operating_knowledge_evidence enable row level security;
alter table atlas.company_operating_knowledge_adjudications enable row level security;

-- Canonical tables remain service-owned. Members receive governed runtime reads through the resolver.
revoke all on atlas.company_operating_knowledge from public, anon, authenticated;
revoke all on atlas.company_operating_knowledge_evidence from public, anon, authenticated;
revoke all on atlas.company_operating_knowledge_adjudications from public, anon, authenticated;

grant select, insert, update, delete on atlas.company_operating_knowledge to service_role;
grant select, insert, update, delete on atlas.company_operating_knowledge_evidence to service_role;
grant select, insert, update, delete on atlas.company_operating_knowledge_adjudications to service_role;

revoke all on function atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz) from public;
revoke all on function atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz) from anon;
grant execute on function atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz) to authenticated;

revoke all on function atlas.guard_company_operating_knowledge_scope_v1() from public, anon, authenticated;
revoke all on function atlas.guard_established_company_operating_knowledge_mutation_v1() from public, anon, authenticated;
revoke all on function atlas.prevent_company_operating_knowledge_history_mutation_v1() from public, anon, authenticated;

grant usage on schema atlas to authenticated, service_role;
