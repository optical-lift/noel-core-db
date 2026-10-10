
do $fix$
declare ddl text;
begin
 ddl:=pg_get_functiondef('draft.get_noel_reality_ecosystem_bridges_v1(text,integer)'::regprocedure);
 if position('end recovery_status' in ddl)=0 or position('sqrt(greatest(total_corpus_tokens,1)::numeric),3)' in ddl)=0 then
   raise exception 'Unexpected SQL revision; refusing patch';
 end if;
 ddl:=replace(ddl,
 'end recovery_status
  from stats s',
 'end recovery_status,
    (select count(*) from
      unnest(tsvector_to_array(to_tsvector(''english'',coalesce(
        (select n.original_definition from draft.noel_reality_nodes n where n.node_id=(select root.node_id from root)),'''')))) rt(token)
      join unnest(tsvector_to_array(to_tsvector(''english'',coalesce(s.original_definition,'''')))) ct(token)
        on rt.token=ct.token
    )::integer founder_stem_overlap
  from stats s');
 ddl:=replace(ddl,
    'sqrt(greatest(total_corpus_tokens,1)::numeric),3)',
    'sqrt(greatest(total_corpus_tokens,1)::numeric) + (founder_stem_overlap::numeric*2),3)');
 ddl:=replace(ddl,
    '''total_corpus_tokens'',total_corpus_tokens,',
    '''total_corpus_tokens'',total_corpus_tokens, ''shared_founder_definition_stems'',founder_stem_overlap,');
 ddl:=replace(ddl,
   '''method'',''Multi-pool convergence:',
   '''method'',''Multi-pool convergence and lexically shared founder-definition stems used only for attention ranking:');
 execute ddl;
end
$fix$;
