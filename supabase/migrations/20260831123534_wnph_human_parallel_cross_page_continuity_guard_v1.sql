do $patch$
declare
  v_def text;
  v_old text := $old$if v_is_first and coalesce(v_batch.stats->>'starts_inside_prior_semantic_unit','false')::boolean then v_risks:=v_risks||'"batch_starts_inside_prior_semantic_unit"'::jsonb; end if;$old$;
  v_new text := $new$if v_is_first and coalesce(v_batch.stats->>'starts_inside_prior_semantic_unit','false')::boolean then v_risks:=v_risks||'"batch_starts_inside_prior_semantic_unit"'::jsonb; end if;
      if v_ws.ordinal=(select min(o_cur.ordinal) from wnph.publication_source_observations o_cur where o_cur.source_asset_id=v_asset.id and o_cur.processor->>'provider'='Wikisource' and o_cur.processor->>'engine'='ProofreadPage' and o_cur.metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations c_cur where c_cur.supersedes_observation_id=o_cur.id))
         and exists(
           select 1
           from wnph.publication_source_assets a_prev
           join lateral (
             select o_prev.text_candidate
             from wnph.publication_source_observations o_prev
             where o_prev.source_asset_id=a_prev.id
               and o_prev.processor->>'provider'='Wikisource'
               and o_prev.processor->>'engine'='ProofreadPage'
               and o_prev.metadata->>'bulk_evidence'='true'
               and not exists(select 1 from wnph.publication_source_observations c_prev where c_prev.supersedes_observation_id=o_prev.id)
             order by o_prev.ordinal desc,o_prev.created_at desc limit 1
           ) prior_last on true
           where a_prev.source_package_id=v_batch.source_package_id
             and (a_prev.source_locator->>'sequence_index')::integer=v_page-1
             and not exists(select 1 from wnph.publication_source_assets ca_prev where ca_prev.supersedes_asset_id=a_prev.id)
             and btrim(prior_last.text_candidate) !~ '[.!?][”’"'')\]]?$'
         ) then v_risks:=v_risks||'"cross_page_semantic_join_required"'::jsonb; end if;$new$;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='wnph' and p.proname='run_bulk_parallel_reconstruction_v1';
  if position(v_old in v_def)=0 then raise exception 'WNPH cross-page guard: runner patch target not found'; end if;
  execute replace(v_def,v_old,v_new);
end;
$patch$;