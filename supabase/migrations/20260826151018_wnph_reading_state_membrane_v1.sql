-- WNPH reading-state membrane v1
--
-- Separate immediately useful, provenance-bearing reading text from the higher
-- assurance states that require source verification and canonical admission proof.
-- One semantic publication source remains authoritative; assurance is a property
-- of each text-bearing block, not a reason to create a parallel OCR/text master.
--
-- Historical source blocks are append-only. Pre-membrane verified text therefore
-- remains byte-for-byte untouched; its effective state is resolved from the source
-- verification provenance it already carries.

alter table wnph.publication_source_blocks
  add column reading_state text;

alter table wnph.publication_source_blocks
  add constraint publication_source_blocks_reading_state_ck
  check (
    (text_content is null and reading_state is null)
    or
    (
      text_content is not null
      and (
        reading_state is null
        or reading_state in ('candidate','usable','verified','adjudicated')
      )
    )
  );

comment on column wnph.publication_source_blocks.reading_state is
  'Explicit assurance state for newly admitted reading text in the single semantic publication source: candidate -> usable -> verified -> adjudicated. NULL is retained only for pre-membrane historical text; resolve_publication_source_block_reading_state_v1 maps those legacy rows from their existing verification provenance.';

create or replace function wnph.resolve_publication_source_block_reading_state_v1(
  p_reading_state text,
  p_text_content text,
  p_source_provenance jsonb
)
returns text
language sql
immutable
set search_path to 'pg_catalog','wnph'
as $function$
  select case
    when p_text_content is null then null
    when p_reading_state is not null then p_reading_state
    when coalesce(p_source_provenance->>'verification_status','') in ('source_image_verified','source_text_verified') then 'verified'
    else 'candidate'
  end;
$function$;

revoke all on function wnph.resolve_publication_source_block_reading_state_v1(text,text,jsonb) from public,anon,authenticated,service_role;

comment on function wnph.resolve_publication_source_block_reading_state_v1(text,text,jsonb) is
  'Resolves the effective reading state without mutating append-only historical blocks. New text declares reading_state explicitly; pre-membrane source-verified text resolves to verified.';

create or replace function wnph.validate_publication_source_block_insert_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_parent_package uuid;
  v_superseded_package uuid;
  v_superseded_key text;
begin
  if new.parent_block_id is not null then
    select b.source_package_id into v_parent_package
    from wnph.publication_source_blocks b
    where b.id=new.parent_block_id;

    if v_parent_package is null or v_parent_package <> new.source_package_id then
      raise exception 'WNPH publication source block: parent block must belong to the same source package';
    end if;
  end if;

  if new.supersedes_block_id is not null then
    select b.source_package_id,b.block_key
      into v_superseded_package,v_superseded_key
    from wnph.publication_source_blocks b
    where b.id=new.supersedes_block_id;

    if v_superseded_package is null or v_superseded_package <> new.source_package_id then
      raise exception 'WNPH publication source block: superseded block must belong to the same source package';
    end if;
    if new.block_key <> v_superseded_key then
      raise exception 'WNPH publication source block: supersession must retain the logical block_key';
    end if;
    if exists(
      select 1 from wnph.publication_source_blocks b
      where b.supersedes_block_id=new.supersedes_block_id
    ) then
      raise exception 'WNPH publication source block: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1 from wnph.publication_source_blocks b
    where b.source_package_id=new.source_package_id
      and b.block_key=new.block_key
  ) then
    raise exception 'WNPH publication source block: duplicate unsuperseded block_key %',new.block_key;
  end if;

  if new.text_content is null then
    if new.reading_state is not null then
      raise exception 'WNPH reading text: non-text block may not declare reading_state';
    end if;
    return new;
  end if;

  if btrim(new.text_content)='' then
    raise exception 'WNPH reading text: text_content may not be blank';
  end if;
  if new.reading_state is null then
    raise exception 'WNPH reading text: new text-bearing block requires explicit reading_state';
  end if;
  if jsonb_typeof(new.source_provenance->'source_locators') <> 'array'
     or jsonb_array_length(new.source_provenance->'source_locators')=0 then
    raise exception 'WNPH reading text: text-bearing block requires at least one source locator';
  end if;
  if coalesce(new.source_provenance->>'text_authority','')='' then
    raise exception 'WNPH reading text: text-bearing block requires explicit text_authority';
  end if;

  if new.reading_state in ('candidate','usable') then
    if coalesce(new.source_provenance->>'derivation_method','')='' then
      raise exception 'WNPH derived reading text: candidate/usable block requires explicit derivation_method';
    end if;
  elsif new.reading_state in ('verified','adjudicated') then
    if coalesce(new.source_provenance->>'verification_status','') not in ('source_image_verified','source_text_verified') then
      raise exception 'WNPH verified reading text: verified/adjudicated block requires source verification';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_block_insert_v1() from public,anon,authenticated,service_role;

create or replace function wnph.validate_canonical_text_admission_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_case uuid;
begin
  if new.text_content is null or new.reading_state not in ('verified','adjudicated') then
    return null;
  end if;

  select p.recovery_case_id into v_case
  from wnph.publication_source_packages p
  where p.id=new.source_package_id;

  if v_case is null then
    raise exception 'WNPH canonical text admission: source package recovery case not found';
  end if;

  if not exists(
    select 1
    from wnph.transmission_act_objects out_obj
    join wnph.transmission_acts act on act.id=out_obj.transmission_act_id
    where out_obj.publication_source_block_id=new.id
      and out_obj.direction='output'
      and act.recovery_case_id=v_case
      and coalesce((act.metadata->>'canonical_text_admission')::boolean,false)=true
      and (
        new.reading_state <> 'adjudicated'
        or coalesce((act.metadata->>'canonical_text_adjudication')::boolean,false)=true
      )
      and exists(
        select 1
        from wnph.transmission_act_objects in_obj
        where in_obj.transmission_act_id=act.id
          and in_obj.direction='input'
          and in_obj.surrogate_id is not null
      )
      and exists(
        select 1
        from wnph.transmission_act_evidence ev
        where ev.transmission_act_id=act.id
          and ev.support_role='supports'
      )
  ) then
    raise exception 'WNPH canonical text admission: % text block % lacks governed admission proof appropriate to its reading_state',new.reading_state,new.block_key;
  end if;

  return null;
end;
$function$;

revoke all on function wnph.validate_canonical_text_admission_v1() from public,anon,authenticated,service_role;

comment on function wnph.validate_canonical_text_admission_v1() is
  'Deferred high-assurance membrane. Candidate/usable reading text may exist immediately with provenance; verified/adjudicated text must be governed canonical-text-admission output with source surrogate and supporting evidence, and adjudicated text must additionally carry canonical_text_adjudication=true.';