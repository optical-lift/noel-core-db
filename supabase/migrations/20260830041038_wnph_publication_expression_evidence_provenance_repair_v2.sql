alter table wnph.publication_expression_block_evidence
  drop constraint publication_expression_block_evidence_evidence_role_check;

alter table wnph.publication_expression_block_evidence
  add constraint publication_expression_block_evidence_evidence_role_check
  check (evidence_role in ('independent_text_witness','same_surrogate_derivative','source_repository','editorial_support'));

update wnph.publication_expression_block_evidence be
set evidence_role='same_surrogate_derivative',
    notes='Machine-readable OCR derivative of the same governed LOC/IA surrogate. Useful for publication collation, but contributes zero additional historical-witness count and is not source-image verification.'
from wnph.evidence_sources es
where es.id=be.evidence_source_id
  and es.canonical_key='internet-archive:ia:wishfairydewydea00colv:djvu-text'
  and be.evidence_role='independent_text_witness';

create or replace function public.wnph_record_publication_expression_block_v2(
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
  p_evidence_bindings jsonb default '[]'::jsonb,
  p_evidence jsonb default '{}'::jsonb,
  p_supersedes_decision_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public'
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
  v_binding jsonb;
  v_evidence_key text;
  v_evidence_role text;
  v_evidence_notes text;
  v_evidence_source wnph.evidence_sources%rowtype;
begin
  select * into v_expression from wnph.expressions where canonical_key=p_expression_key;
  if v_expression.id is null then raise exception 'WNPH publication expression: Expression not found' using errcode='P0002'; end if;
  if coalesce(btrim(p_decision_key),'')='' or coalesce(btrim(p_block_key),'')='' then
    raise exception 'WNPH publication expression: decision key and block key are required' using errcode='22023';
  end if;
  if p_publication_state not in ('admitted','review','rejected') then raise exception 'WNPH publication expression: invalid publication state' using errcode='22023'; end if;
  if p_decision_basis not in ('source_verified','multi_witness_agreement','editorial_reconstruction_high_confidence','structural_adjudication') then raise exception 'WNPH publication expression: invalid decision basis' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' then raise exception 'WNPH publication expression: evidence must be an object' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_evidence_bindings,'[]'::jsonb))<>'array' then raise exception 'WNPH publication expression: evidence bindings must be an array' using errcode='22023'; end if;

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
    if v_old.expression_id<>v_expression.id or v_old.block_key<>p_block_key then
      raise exception 'WNPH publication expression: supersession cannot cross Expression or block identity' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=v_old.id) then
      raise exception 'WNPH publication expression: superseded decision is not the active leaf' using errcode='55000';
    end if;
  elsif exists(
    select 1 from wnph.publication_expression_blocks b
    where b.expression_id=v_expression.id and b.block_key=p_block_key
      and not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id)
  ) then
    raise exception 'WNPH publication expression: active block already exists; supersede it explicitly' using errcode='23505';
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
      'diplomatic_source_state_unchanged',true,
      'evidence_roles_explicit',true
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

  for v_binding in select value from jsonb_array_elements(coalesce(p_evidence_bindings,'[]'::jsonb)) loop
    if jsonb_typeof(v_binding)<>'object' then raise exception 'WNPH publication expression: each evidence binding must be an object' using errcode='22023'; end if;
    v_evidence_key:=nullif(btrim(v_binding->>'source_key'),'');
    v_evidence_role:=nullif(btrim(v_binding->>'evidence_role'),'');
    v_evidence_notes:=nullif(btrim(v_binding->>'notes'),'');
    if v_evidence_key is null or v_evidence_role is null then
      raise exception 'WNPH publication expression: each evidence binding requires source_key and evidence_role' using errcode='22023';
    end if;
    if v_evidence_role not in ('independent_text_witness','same_surrogate_derivative','source_repository','editorial_support') then
      raise exception 'WNPH publication expression: unsupported evidence role %',v_evidence_role using errcode='22023';
    end if;
    select * into v_evidence_source from wnph.evidence_sources where canonical_key=v_evidence_key;
    if v_evidence_source.id is null then raise exception 'WNPH publication expression: evidence source % not found',v_evidence_key using errcode='P0002'; end if;
    if v_evidence_role='independent_text_witness' and coalesce((v_evidence_source.metadata->>'historical_witness_count_delta')::integer,1)=0 then
      raise exception 'WNPH publication expression: evidence source % declares zero historical-witness delta and cannot be labeled independent',v_evidence_key using errcode='55000';
    end if;
    insert into wnph.publication_expression_block_evidence(publication_expression_block_id,evidence_source_id,evidence_role,notes)
    values(v_block_id,v_evidence_source.id,v_evidence_role,coalesce(v_evidence_notes,
      case v_evidence_role
        when 'same_surrogate_derivative' then 'Derivative access layer of the same governed surrogate; useful for collation but not an additional historical witness.'
        when 'independent_text_witness' then 'Independent historical/textual witness used for publication collation.'
        when 'source_repository' then 'Repository/access evidence supporting source custody.'
        else 'Editorial support evidence.'
      end));
  end loop;

  return jsonb_build_object(
    'publication_expression_block_id',v_block_id,
    'expression_key',p_expression_key,
    'block_key',p_block_key,
    'publication_state',p_publication_state,
    'decision_basis',p_decision_basis,
    'confidence',p_confidence,
    'evidence_binding_count',jsonb_array_length(coalesce(p_evidence_bindings,'[]'::jsonb))
  );
end;
$$;

revoke all on function public.wnph_record_publication_expression_block_v1(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],text[],jsonb,text) from service_role;
revoke all on function public.wnph_record_publication_expression_block_v1(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],text[],jsonb,text) from public,anon,authenticated;

revoke all on function public.wnph_record_publication_expression_block_v2(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.wnph_record_publication_expression_block_v2(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],jsonb,jsonb,text) to service_role;

comment on function public.wnph_record_publication_expression_block_v2(text,text,text,text,integer,text,text,text,text,text,numeric,text,text[],jsonb,jsonb,text) is 'Writes governed Publication Expression blocks with explicit evidence roles. Same-surrogate OCR/access derivatives must never be mislabeled as independent historical witnesses.';