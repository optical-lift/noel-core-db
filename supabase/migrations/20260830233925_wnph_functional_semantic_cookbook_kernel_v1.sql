create table wnph.publication_semantic_units (
  id uuid primary key default gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  unit_key text not null,
  parent_unit_id uuid references wnph.publication_semantic_units(id),
  ordinal integer not null default 0 check (ordinal >= 0),
  unit_type text not null check (btrim(unit_type) <> ''),
  source_title text,
  semantic_status text not null check (semantic_status in ('candidate','verified','adjudicated','rejected')),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  properties jsonb not null default '{}'::jsonb check (jsonb_typeof(properties)='object'),
  source_provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(source_provenance)='object'),
  supersedes_unit_id uuid references wnph.publication_semantic_units(id),
  created_at timestamptz not null default now(),
  check (supersedes_unit_id is null or supersedes_unit_id <> id)
);

create table wnph.publication_semantic_claims (
  id uuid primary key default gen_random_uuid(),
  semantic_unit_id uuid not null references wnph.publication_semantic_units(id),
  source_block_id uuid not null references wnph.publication_source_blocks(id),
  claim_key text not null,
  ordinal integer not null default 0 check (ordinal >= 0),
  claim_kind text not null check (btrim(claim_kind) <> ''),
  subject_key text,
  predicate text not null check (btrim(predicate) <> ''),
  object_text text,
  quantity_value numeric,
  quantity_unit text,
  quantity_text text,
  temporal_text text,
  condition_text text,
  claim_status text not null check (claim_status in ('candidate','verified','adjudicated','rejected')),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  properties jsonb not null default '{}'::jsonb check (jsonb_typeof(properties)='object'),
  source_provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(source_provenance)='object'),
  supersedes_claim_id uuid references wnph.publication_semantic_claims(id),
  created_at timestamptz not null default now(),
  check (supersedes_claim_id is null or supersedes_claim_id <> id)
);

create index publication_semantic_units_expression_idx on wnph.publication_semantic_units(expression_id, ordinal);
create index publication_semantic_units_package_idx on wnph.publication_semantic_units(source_package_id);
create index publication_semantic_claims_unit_idx on wnph.publication_semantic_claims(semantic_unit_id, ordinal);
create index publication_semantic_claims_source_block_idx on wnph.publication_semantic_claims(source_block_id);

create or replace function wnph.validate_publication_semantic_unit_v1()
returns trigger language plpgsql set search_path='pg_catalog','wnph' as $$
declare
  v_package_expression uuid;
  v_parent wnph.publication_semantic_units%rowtype;
  v_old wnph.publication_semantic_units%rowtype;
begin
  if tg_op <> 'INSERT' then
    raise exception 'WNPH semantic unit: rows are append-only; supersede with a new row';
  end if;
  select expression_id into v_package_expression from wnph.publication_source_packages where id=new.source_package_id;
  if v_package_expression is null or v_package_expression <> new.expression_id then
    raise exception 'WNPH semantic unit: source package must belong to the same Expression';
  end if;
  if new.parent_unit_id is not null then
    select * into v_parent from wnph.publication_semantic_units where id=new.parent_unit_id;
    if v_parent.id is null or v_parent.expression_id<>new.expression_id or v_parent.source_package_id<>new.source_package_id then
      raise exception 'WNPH semantic unit: parent must belong to the same Expression and source package';
    end if;
  end if;
  if new.supersedes_unit_id is not null then
    select * into v_old from wnph.publication_semantic_units where id=new.supersedes_unit_id;
    if v_old.id is null or v_old.expression_id<>new.expression_id or v_old.unit_key<>new.unit_key then
      raise exception 'WNPH semantic unit: supersession must preserve Expression and unit_key';
    end if;
    if exists(select 1 from wnph.publication_semantic_units c where c.supersedes_unit_id=v_old.id) then
      raise exception 'WNPH semantic unit: supersession fork is not allowed';
    end if;
  elsif exists(select 1 from wnph.publication_semantic_units u where u.expression_id=new.expression_id and u.unit_key=new.unit_key and not exists(select 1 from wnph.publication_semantic_units c where c.supersedes_unit_id=u.id)) then
    raise exception 'WNPH semantic unit: active unit_key already exists';
  end if;
  if new.semantic_status in ('verified','adjudicated') and coalesce((new.source_provenance->>'source_verified')::boolean,false)<>true then
    raise exception 'WNPH semantic unit: verified/adjudicated status requires explicit source_verified provenance';
  end if;
  return new;
end $$;

create trigger publication_semantic_units_validate_v1
before insert or update or delete on wnph.publication_semantic_units
for each row execute function wnph.validate_publication_semantic_unit_v1();

create or replace function wnph.validate_publication_semantic_claim_v1()
returns trigger language plpgsql set search_path='pg_catalog','wnph' as $$
declare
  v_unit wnph.publication_semantic_units%rowtype;
  v_block wnph.publication_source_blocks%rowtype;
  v_old wnph.publication_semantic_claims%rowtype;
begin
  if tg_op <> 'INSERT' then
    raise exception 'WNPH semantic claim: rows are append-only; supersede with a new row';
  end if;
  select * into v_unit from wnph.publication_semantic_units where id=new.semantic_unit_id;
  select * into v_block from wnph.publication_source_blocks where id=new.source_block_id;
  if v_unit.id is null or v_block.id is null or v_block.source_package_id<>v_unit.source_package_id then
    raise exception 'WNPH semantic claim: source block must belong to the semantic unit source package';
  end if;
  if new.supersedes_claim_id is not null then
    select * into v_old from wnph.publication_semantic_claims where id=new.supersedes_claim_id;
    if v_old.id is null or v_old.semantic_unit_id<>new.semantic_unit_id or v_old.claim_key<>new.claim_key then
      raise exception 'WNPH semantic claim: supersession must preserve semantic unit and claim_key';
    end if;
    if exists(select 1 from wnph.publication_semantic_claims c where c.supersedes_claim_id=v_old.id) then
      raise exception 'WNPH semantic claim: supersession fork is not allowed';
    end if;
  elsif exists(select 1 from wnph.publication_semantic_claims c where c.semantic_unit_id=new.semantic_unit_id and c.claim_key=new.claim_key and not exists(select 1 from wnph.publication_semantic_claims n where n.supersedes_claim_id=c.id)) then
    raise exception 'WNPH semantic claim: active claim_key already exists';
  end if;
  if new.claim_status in ('verified','adjudicated') then
    if v_block.reading_state not in ('verified','adjudicated') then
      raise exception 'WNPH semantic claim: verified/adjudicated claim requires verified/adjudicated source text';
    end if;
    if v_unit.semantic_status not in ('verified','adjudicated') then
      raise exception 'WNPH semantic claim: verified/adjudicated claim requires verified/adjudicated semantic unit';
    end if;
    if coalesce((new.source_provenance->>'source_verified')::boolean,false)<>true then
      raise exception 'WNPH semantic claim: verified/adjudicated claim requires explicit source_verified provenance';
    end if;
  end if;
  return new;
end $$;

create trigger publication_semantic_claims_validate_v1
before insert or update or delete on wnph.publication_semantic_claims
for each row execute function wnph.validate_publication_semantic_claim_v1();