create table if not exists wnph.publication_expression_blocks (
  id uuid primary key default gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  decision_key text not null unique check (btrim(decision_key) <> ''),
  block_key text not null check (btrim(block_key) <> ''),
  parent_block_id uuid references wnph.publication_expression_blocks(id),
  ordinal integer not null check (ordinal >= 0),
  block_type text not null check (btrim(block_type) <> ''),
  semantic_role text,
  text_content text,
  publication_state text not null check (publication_state in ('admitted','review','rejected')),
  decision_basis text not null check (decision_basis in ('source_verified','multi_witness_agreement','editorial_reconstruction_high_confidence','structural_adjudication')),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  text_sha256 text,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  supersedes_block_id uuid references wnph.publication_expression_blocks(id),
  created_at timestamptz not null default now(),
  check (supersedes_block_id is null or supersedes_block_id <> id),
  check ((text_content is null and text_sha256 is null) or (text_content is not null and text_sha256 ~ '^[0-9a-f]{64}$'))
);

create unique index if not exists publication_expression_blocks_active_key_uq
on wnph.publication_expression_blocks(expression_id, block_key)
where supersedes_block_id is null;

create index if not exists publication_expression_blocks_parent_idx
on wnph.publication_expression_blocks(parent_block_id, ordinal);

create index if not exists publication_expression_blocks_expression_idx
on wnph.publication_expression_blocks(expression_id, ordinal);

create table if not exists wnph.publication_expression_block_sources (
  id uuid primary key default gen_random_uuid(),
  publication_expression_block_id uuid not null references wnph.publication_expression_blocks(id) on delete cascade,
  source_block_id uuid not null references wnph.publication_source_blocks(id),
  source_role text not null default 'source_candidate' check (source_role in ('source_candidate','source_verified','structural_basis')),
  notes text,
  created_at timestamptz not null default now(),
  unique(publication_expression_block_id, source_block_id, source_role)
);
create index if not exists publication_expression_block_sources_source_idx
on wnph.publication_expression_block_sources(source_block_id);

create table if not exists wnph.publication_expression_block_evidence (
  id uuid primary key default gen_random_uuid(),
  publication_expression_block_id uuid not null references wnph.publication_expression_blocks(id) on delete cascade,
  evidence_source_id uuid not null references wnph.evidence_sources(id),
  evidence_role text not null check (evidence_role in ('independent_text_witness','source_repository','editorial_support')),
  notes text,
  created_at timestamptz not null default now(),
  unique(publication_expression_block_id, evidence_source_id, evidence_role)
);
create index if not exists publication_expression_block_evidence_source_idx
on wnph.publication_expression_block_evidence(evidence_source_id);

create or replace function wnph.validate_publication_expression_block_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, wnph, public
as $$
declare
  v_parent wnph.publication_expression_blocks%rowtype;
  v_old wnph.publication_expression_blocks%rowtype;
begin
  if tg_op='UPDATE' then
    raise exception 'WNPH publication expression block: rows are immutable; supersede with a new row' using errcode='55000';
  end if;
  if jsonb_typeof(new.evidence) <> 'object' then
    raise exception 'WNPH publication expression block: evidence must be an object' using errcode='22023';
  end if;
  if new.text_content is null then
    new.text_sha256 := null;
  else
    new.text_sha256 := encode(extensions.digest(convert_to(new.text_content,'UTF8'),'sha256'),'hex');
  end if;
  if new.publication_state='admitted' then
    if coalesce(new.confidence,0) < 0.90 then
      raise exception 'WNPH publication expression block: admitted text requires confidence >= 0.90' using errcode='55000';
    end if;
    if coalesce((new.evidence->>'publication_admission')::boolean,false) is not true then
      raise exception 'WNPH publication expression block: admitted text requires evidence.publication_admission=true' using errcode='55000';
    end if;
    if coalesce((new.evidence->>'source_image_verification_required')::boolean,true) is true then
      raise exception 'WNPH publication expression block: publication lane must explicitly state source_image_verification_required=false' using errcode='55000';
    end if;
  end if;
  if new.parent_block_id is not null then
    select * into v_parent from wnph.publication_expression_blocks where id=new.parent_block_id;
    if v_parent.id is null or v_parent.expression_id<>new.expression_id then
      raise exception 'WNPH publication expression block: parent must belong to the same Expression' using errcode='55000';
    end if;
  end if;
  if new.supersedes_block_id is not null then
    select * into v_old from wnph.publication_expression_blocks where id=new.supersedes_block_id;
    if v_old.id is null or v_old.expression_id<>new.expression_id or v_old.block_key<>new.block_key then
      raise exception 'WNPH publication expression block: supersession must preserve Expression and block key' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=v_old.id) then
      raise exception 'WNPH publication expression block: supersession fork is not allowed' using errcode='55000';
    end if;
  elsif exists(
    select 1 from wnph.publication_expression_blocks b
    where b.expression_id=new.expression_id and b.block_key=new.block_key
      and not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id)
  ) then
    raise exception 'WNPH publication expression block: active block key already exists; supersede explicitly' using errcode='23505';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_publication_expression_block_v1 on wnph.publication_expression_blocks;
create trigger trg_validate_publication_expression_block_v1
before insert or update on wnph.publication_expression_blocks
for each row execute function wnph.validate_publication_expression_block_v1();

create or replace function public.wnph_record_publication_expression_block_v1(
  p_expression_key text,
  p_decision_key text,
  p_block_key text,
  p_parent_block_key text,
  p_ordinal integer,
  p_block_type text,
  p_semantic_role text,
  p_text_content text,
  p_publication_state text,
  p_decision_basis text,
  p_confidence numeric,
  p_derivation_method text,
  p_basis_source_block_keys text[],
  p_evidence_source_keys text[],
  p_evidence jsonb,
  p_supersedes_decision_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, wnph, public
as $$
declare
  v_expression wnph.expressions%rowtype;
  v_parent_id uuid;
  v_old wnph.publication_expression_blocks%rowtype;
  v_block_id uuid;
  v_source_key text;
  v_source wnph.publication_source_blocks%rowtype;
  v_source_work_id uuid;
  v_source_role text;
  v_evidence_key text;
  v_evidence_source_id uuid;
begin
  select * into v_expression from wnph.expressions where canonical_key=p_expression_key;
  if v_expression.id is null then raise exception 'WNPH publication expression: Expression not found' using errcode='P0002'; end if;
  if coalesce(btrim(p_decision_key),'')='' or coalesce(btrim(p_block_key),'')='' then
    raise exception 'WNPH publication expression: decision key and block key are required' using errcode='22023';
  end if;
  if p_publication_state not in ('admitted','review','rejected') then raise exception 'WNPH publication expression: invalid publication state' using errcode='22023'; end if;
  if p_decision_basis not in ('source_verified','multi_witness_agreement','editorial_reconstruction_high_confidence','structural_adjudication') then raise exception 'WNPH publication expression: invalid decision basis' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' then raise exception 'WNPH publication expression: evidence must be an object' using errcode='22023'; end if;

  if p_parent_block_key is not null then
    select b.id into v_parent_id
    from wnph.publication_expression_blocks b
    where b.expression_id=v_expression.id and b.block_key=p_parent_block_key
      and not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id)
    order by b.created_at desc limit 1;
    if v_parent_id is null then raise exception 'WNPH publication expression: parent block not found' using errcode='P0002'; end if;
  end if;

  if p_supersedes_decision_key is not null then
    select * into v_old from wnph.publication_expression_blocks where decision_key=p_supersedes_decision_key;
    if v_old.id is null then raise exception 'WNPH publication expression: superseded decision not found' using errcode='P0002'; end if;
  end if;

  if coalesce(cardinality(p_basis_source_block_keys),0)=0 then
    raise exception 'WNPH publication expression: at least one governed source block is required' using errcode='55000';
  end if;

  foreach v_source_key in array p_basis_source_block_keys loop
    select * into v_source
    from wnph.publication_source_blocks b
    where b.block_key=v_source_key
      and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)
    order by b.created_at desc limit 1;
    if v_source.id is null then raise exception 'WNPH publication expression: source block % not found',v_source_key using errcode='P0002'; end if;
    select e.work_id into v_source_work_id
    from wnph.publication_source_packages sp join wnph.expressions e on e.id=sp.expression_id
    where sp.id=v_source.source_package_id;
    if v_source_work_id is distinct from v_expression.work_id then
      raise exception 'WNPH publication expression: source block crosses Work identity' using errcode='55000';
    end if;
  end loop;

  insert into wnph.publication_expression_blocks(
    expression_id,decision_key,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,
    publication_state,decision_basis,confidence,derivation_method,evidence,supersedes_block_id
  ) values(
    v_expression.id,p_decision_key,p_block_key,v_parent_id,p_ordinal,p_block_type,p_semantic_role,p_text_content,
    p_publication_state,p_decision_basis,p_confidence,p_derivation_method,
    coalesce(p_evidence,'{}'::jsonb) || jsonb_build_object(
      'publication_expression_key',p_expression_key,
      'source_image_verification_required',false,
      'diplomatic_source_state_unchanged',true
    ),
    v_old.id
  ) returning id into v_block_id;

  foreach v_source_key in array p_basis_source_block_keys loop
    select * into v_source
    from wnph.publication_source_blocks b
    where b.block_key=v_source_key
      and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)
    order by b.created_at desc limit 1;
    v_source_role := case when v_source.reading_state='verified' then 'source_verified' when v_source.block_type in ('chapter','content_stream') then 'structural_basis' else 'source_candidate' end;
    insert into wnph.publication_expression_block_sources(publication_expression_block_id,source_block_id,source_role,notes)
    values(v_block_id,v_source.id,v_source_role,'Publication Expression derives from this governed source block without mutating its diplomatic/forensic state.');
  end loop;

  foreach v_evidence_key in array coalesce(p_evidence_source_keys,'{}'::text[]) loop
    select id into v_evidence_source_id from wnph.evidence_sources where canonical_key=v_evidence_key;
    if v_evidence_source_id is null then raise exception 'WNPH publication expression: evidence source % not found',v_evidence_key using errcode='P0002'; end if;
    insert into wnph.publication_expression_block_evidence(publication_expression_block_id,evidence_source_id,evidence_role,notes)
    values(v_block_id,v_evidence_source_id,'independent_text_witness','Independent witness used for publication collation; it is not treated as source-image verification.');
  end loop;

  return jsonb_build_object('publication_expression_block_id',v_block_id,'expression_key',p_expression_key,'block_key',p_block_key,'publication_state',p_publication_state,'decision_basis',p_decision_basis,'confidence',p_confidence);
end;
$$;

create or replace view public.v_wnph_publication_expression_master_v1 as
select
  e.canonical_key as expression_key,
  e.work_id,
  b.id as publication_expression_block_id,
  b.block_key,
  pb.block_key as parent_block_key,
  b.ordinal,
  b.block_type,
  b.semantic_role,
  b.text_content,
  b.publication_state,
  b.decision_basis,
  b.confidence,
  b.derivation_method,
  b.text_sha256,
  b.evidence,
  b.created_at
from wnph.publication_expression_blocks b
join wnph.expressions e on e.id=b.expression_id
left join wnph.publication_expression_blocks pb on pb.id=b.parent_block_id
where not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id);

insert into wnph.expressions(canonical_key,work_id,expression_type,language_code,status,identity_confidence,summary)
select
  'wish-fairy-dewy-dear:wnph-publication-e1',
  e.work_id,
  'editorially_collated_publication_expression',
  'en',
  'established',
  'high',
  'WNPH publication Expression derived from the governed historical source package. Diplomatic/source verification remains separate; publication blocks may admit high-confidence multi-witness or editorially reconstructed readings with explicit provenance.'
from wnph.expressions e
where e.canonical_key='wish-fairy-dewy-dear:e1'
  and not exists(select 1 from wnph.expressions x where x.canonical_key='wish-fairy-dewy-dear:wnph-publication-e1');

revoke all on wnph.publication_expression_blocks from public, anon, authenticated;
revoke all on wnph.publication_expression_block_sources from public, anon, authenticated;
revoke all on wnph.publication_expression_block_evidence from public, anon, authenticated;
grant select on wnph.publication_expression_blocks to service_role;
grant select on wnph.publication_expression_block_sources to service_role;
grant select on wnph.publication_expression_block_evidence to service_role;
revoke all on function public.wnph_record_publication_expression_block_v1(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],text[],jsonb,text) from public, anon, authenticated;
grant execute on function public.wnph_record_publication_expression_block_v1(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],text[],jsonb,text) to service_role;
grant select on public.v_wnph_publication_expression_master_v1 to service_role;