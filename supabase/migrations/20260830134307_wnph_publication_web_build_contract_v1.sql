create or replace function public.wnph_html_escape_v1(p_text text)
returns text
language sql
immutable
strict
as $$
  select replace(replace(replace(replace(replace(p_text,'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),'''','&#39;')
$$;

create or replace function public.wnph_publication_web_build_v1(p_expression_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','wnph','public'
as $$
declare
  v_expr wnph.expressions%rowtype;
  v_work wnph.historical_works%rowtype;
  v_snapshot jsonb;
  v_author text;
  v_body text:='';
  v_html text;
  v_hash text;
  v_current_chapter integer:=0;
  v_chapter_open boolean:=false;
  v_front_emitted boolean:=false;
  v_row record;
  v_figures text;
  v_toc text;
begin
  select * into v_expr from wnph.expressions where canonical_key=p_expression_key;
  if v_expr.id is null then raise exception 'WNPH web build: Expression not found' using errcode='P0002'; end if;
  select * into v_work from wnph.historical_works where id=v_expr.work_id;
  v_snapshot:=public.wnph_publication_expression_snapshot_v3(p_expression_key);
  if coalesce((v_snapshot->>'reproducible_build_ready')::boolean,false) is not true then
    raise exception 'WNPH web build: publication master has % unreceipted media placements',v_snapshot->>'unreceipted_media_count' using errcode='55000';
  end if;

  select string_agg(ca.preferred_label,', ' order by c.role,ca.preferred_label)
  into v_author
  from wnph.work_creator_credits c join wnph.creator_authorities ca on ca.id=c.creator_id
  where c.work_id=v_expr.work_id and c.role='author'
    and not exists(select 1 from wnph.work_creator_credits x where x.supersedes_credit_id=c.id);

  select '<ol>'||coalesce(string_agg(
    '<li><a href="#chapter-'||c.ordinal||'">'||public.wnph_html_escape_v1(c.text_content)||
    case when t.text_content is not null then ' — '||public.wnph_html_escape_v1(t.text_content) else '' end||'</a></li>',
    '' order by c.ordinal),'')||'</ol>'
  into v_toc
  from wnph.publication_expression_blocks c
  left join wnph.publication_expression_blocks t
    on t.parent_block_id=c.id and t.semantic_role='chapter_title'
    and not exists(select 1 from wnph.publication_expression_blocks tc where tc.supersedes_block_id=t.id)
  where c.expression_id=v_expr.id and c.block_type='chapter' and c.publication_state='admitted'
    and not exists(select 1 from wnph.publication_expression_blocks cc where cc.supersedes_block_id=c.id);

  for v_row in
    select * from public.v_wnph_expression_render_input_v1
    where expression_key=p_expression_key order by render_path
  loop
    if v_row.semantic_role='front_matter' then
      continue;
    elsif v_row.semantic_role='title_page' then
      if not v_front_emitted then
        select coalesce(string_agg(
          '<figure class="wnph-plate" data-placement-key="'||public.wnph_html_escape_v1(m.placement_key)||'" data-raster-sha256="'||r.raster_sha256||'">'||
          '<img src="'||public.wnph_html_escape_v1(r.fetch_uri)||'" alt="" data-alt-text-status="'||public.wnph_html_escape_v1(coalesce(m.accessibility->>'alt_text_status','unspecified'))||'"/>'||
          '<figcaption>Historical illustration · source '||public.wnph_html_escape_v1(m.source_asset_key)||'</figcaption></figure>',
          '' order by m.sequence_ordinal,m.placement_key),'')
        into v_figures
        from public.v_wnph_expression_media_input_v1 m
        join public.v_wnph_expression_publication_raster_input_v1 r
          on r.expression_key=m.expression_key and r.placement_key=m.placement_key
        where m.expression_key=p_expression_key and m.anchor_kind='front_matter';
        v_body:=v_body||coalesce(v_figures,'');
        v_front_emitted:=true;
      end if;
      v_body:=v_body||'<section class="title-page">';
    elsif v_row.semantic_role='edition_rights_page' then
      v_body:=v_body||'</section><section class="rights-page"><p>Underlying work: public domain in the United States.</p></section>';
    elsif v_row.semantic_role='table_of_contents' then
      v_body:=v_body||'<nav class="toc"><h2>Contents</h2>'||coalesce(v_toc,'<ol></ol>')||'</nav>';
    elsif v_row.semantic_role='half_title' then
      v_body:=v_body||'<h1 class="half-title">'||public.wnph_html_escape_v1(coalesce(v_row.text_content,''))||'</h1>';
    elsif v_row.block_type='chapter' then
      if v_chapter_open then v_body:=v_body||'</section>'; end if;
      v_current_chapter:=v_row.ordinal;
      v_chapter_open:=true;
      v_body:=v_body||'<section class="chapter" id="chapter-'||v_current_chapter||'" data-chapter-number="'||v_current_chapter||'"><p class="chapter-label">'||public.wnph_html_escape_v1(coalesce(v_row.text_content,''))||'</p>';
    elsif v_row.semantic_role='chapter_title' then
      v_body:=v_body||'<h2>'||public.wnph_html_escape_v1(coalesce(v_row.text_content,''))||'</h2>';
      select coalesce(string_agg(
        '<div class="placement-fallback" data-placement-resolution="chapter-opening-fallback-from-source-surface-boundary">'||
        '<figure class="wnph-plate" data-placement-key="'||public.wnph_html_escape_v1(m.placement_key)||'" data-anchor-kind="'||public.wnph_html_escape_v1(m.anchor_kind)||'" data-raster-sha256="'||r.raster_sha256||'">'||
        '<img src="'||public.wnph_html_escape_v1(r.fetch_uri)||'" alt="" data-alt-text-status="'||public.wnph_html_escape_v1(coalesce(m.accessibility->>'alt_text_status','unspecified'))||'"/>'||
        '<figcaption>Historical illustration · source '||public.wnph_html_escape_v1(m.source_asset_key)||'</figcaption></figure></div>',
        '' order by m.sequence_ordinal,m.placement_key),'')
      into v_figures
      from public.v_wnph_expression_media_input_v1 m
      join public.v_wnph_expression_publication_raster_input_v1 r
        on r.expression_key=m.expression_key and r.placement_key=m.placement_key
      where m.expression_key=p_expression_key
        and nullif(m.anchor_data->>'chapter_number','')::integer=v_current_chapter;
      v_body:=v_body||coalesce(v_figures,'');
    elsif v_row.semantic_role='title' then
      v_body:=v_body||'<h1>'||public.wnph_html_escape_v1(coalesce(v_row.text_content,''))||'</h1>';
    elsif v_row.semantic_role='author' then
      v_body:=v_body||'<p class="author">By '||public.wnph_html_escape_v1(coalesce(v_row.text_content,''))||'</p>';
    elsif v_row.block_type='paragraph' then
      v_body:=v_body||'<p>'||public.wnph_html_escape_v1(coalesce(v_row.text_content,''))||'</p>';
    end if;
  end loop;
  if v_chapter_open then v_body:=v_body||'</section>'; end if;

  v_html:='<!doctype html><html lang="'||public.wnph_html_escape_v1(coalesce(v_work.language_code,'en'))||'"><head><meta charset="utf-8"/>'||
    '<meta name="viewport" content="width=device-width,initial-scale=1"/>'||
    '<meta name="wnph-master-sha256" content="'||(v_snapshot->>'render_master_sha256')||'"/>'||
    '<meta name="wnph-snapshot-contract" content="'||(v_snapshot->>'contract_version')||'"/>'||
    '<title>'||public.wnph_html_escape_v1(v_work.canonical_label)||'</title>'||
    '<style>body{max-width:44rem;margin:0 auto;padding:2rem;font-family:Georgia,serif;line-height:1.55}.title-page,.rights-page,.toc,.half-title,.chapter{margin:4rem 0}.title-page{text-align:center}.author{text-align:center}.chapter-label{text-align:center;letter-spacing:.08em}.chapter h2{text-align:center}.wnph-plate{margin:3rem auto;text-align:center}.wnph-plate img{max-width:100%;height:auto}.wnph-plate figcaption{font-size:.75rem;opacity:.65}.toc ol{padding-left:1.5rem}</style></head><body data-expression-key="'||public.wnph_html_escape_v1(p_expression_key)||'" data-master-sha256="'||(v_snapshot->>'render_master_sha256')||'">'||v_body||'</body></html>';

  v_hash:=encode(extensions.digest(convert_to(v_html,'UTF8'),'sha256'),'hex');
  return jsonb_build_object(
    'contract_version','wnph_publication_web_build_v1',
    'expression_key',p_expression_key,
    'master_snapshot',v_snapshot,
    'title',v_work.canonical_label,
    'author',v_author,
    'media_placement_count',v_snapshot->'media_placement_count',
    'output_media_type','text/html; charset=utf-8',
    'output_sha256',v_hash,
    'html',v_html,
    'placement_resolution_note','Source-surface-boundary plates use a chapter-opening fallback in web build v1 until paragraph-span anchoring is available.'
  );
end;
$$;

revoke all on function public.wnph_html_escape_v1(text) from public,anon,authenticated;
grant execute on function public.wnph_html_escape_v1(text) to service_role;
revoke all on function public.wnph_publication_web_build_v1(text) from public,anon,authenticated;
grant execute on function public.wnph_publication_web_build_v1(text) to service_role;

comment on function public.wnph_publication_web_build_v1(text) is 'Deterministic semantic HTML manifestation builder over a reproducible snapshot-v3 Publication Expression. Refuses builds with unreceipted media and returns exact HTML SHA-256.';