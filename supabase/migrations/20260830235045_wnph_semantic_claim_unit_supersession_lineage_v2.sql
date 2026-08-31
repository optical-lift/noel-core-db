create or replace function wnph.validate_publication_semantic_claim_v1()
returns trigger language plpgsql set search_path='pg_catalog','wnph' as $$
declare
  v_unit wnph.publication_semantic_units%rowtype;
  v_block wnph.publication_source_blocks%rowtype;
  v_old wnph.publication_semantic_claims%rowtype;
  v_old_unit wnph.publication_semantic_units%rowtype;
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
    if v_old.id is null or v_old.claim_key<>new.claim_key then
      raise exception 'WNPH semantic claim: supersession must preserve claim_key';
    end if;

    select * into v_old_unit from wnph.publication_semantic_units where id=v_old.semantic_unit_id;
    if v_old_unit.id is null or v_old_unit.source_package_id<>v_unit.source_package_id then
      raise exception 'WNPH semantic claim: supersession may not cross source packages';
    end if;

    if v_old.semantic_unit_id<>new.semantic_unit_id
       and v_unit.supersedes_unit_id is distinct from v_old.semantic_unit_id then
      raise exception 'WNPH semantic claim: claim may move only to the direct superseding semantic unit';
    end if;

    if exists(select 1 from wnph.publication_semantic_claims c where c.supersedes_claim_id=v_old.id) then
      raise exception 'WNPH semantic claim: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1 from wnph.publication_semantic_claims c
    where c.semantic_unit_id=new.semantic_unit_id
      and c.claim_key=new.claim_key
      and not exists(select 1 from wnph.publication_semantic_claims n where n.supersedes_claim_id=c.id)
  ) then
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