
do $fix$
declare ddl text;
begin
  ddl:=pg_get_functiondef('draft.get_noel_reality_ecosystem_bridges_v1(text,integer)'::regprocedure);
  if position('order by attention_score desc,curated_bridge_verses desc,bridge_verses desc,candidate_strong' in ddl)=0 then
    raise exception 'Expected bridge ranking SQL not found; abort rather than silently patch';
  end if;
  ddl:=replace(ddl,
    'order by attention_score desc,curated_bridge_verses desc,bridge_verses desc,candidate_strong',
    'order by (total_corpus_tokens<=1000) desc,attention_score desc,curated_bridge_verses desc,bridge_verses desc,candidate_strong');
  ddl:=replace(ddl,'limit least(greatest(coalesce(p_limit,8),1),30)',
      'limit least(greatest(coalesce(p_limit,8),1),150)');
  execute ddl;
end
$fix$;
