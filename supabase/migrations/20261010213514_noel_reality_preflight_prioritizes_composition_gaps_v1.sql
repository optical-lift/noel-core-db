
create or replace function draft.get_noel_reality_preflight_v1(
 p_lookup text,
 p_max_depth integer default 4,
 p_token_limit integer default 25
) returns jsonb
language sql stable security invoker
set search_path = ''
as $body$
select coalesce(draft.get_noel_reality_context_v1(p_lookup,p_max_depth),'{}'::jsonb)
 || jsonb_build_object(
    'live_source_tokens',
      coalesce((select jsonb_agg(to_jsonb(tok)
        order by tok.canonical_book_code,tok.chapter,tok.verse,tok.token_position)
      from draft.get_noel_reality_tokens_v1(p_lookup,p_token_limit,0,null) tok),'[]'::jsonb),
    'token_scope',
      'Page of source-corpus occurrences; not a replacement for the full occurrence field. Use get_noel_reality_tokens_v1 with offset to continue.',
    'ecosystem_composition_gaps',
      draft.get_noel_reality_composition_gaps_v1(p_lookup,12),
    'ecosystem_bridges',
      draft.get_noel_reality_ecosystem_bridges_v1(p_lookup,12),
    'ecosystem_attention',
      draft.get_noel_reality_ecosystem_v1(p_lookup,12),
    'ecosystem_attention_instruction',
      'Before marking a pool recovered or complete, surface words requiring attention: (1) unexamined founder words adjacent to an existing MT verse composition; (2) unexamined founder words where two or more recovered lexical pools converge; (3) wider source-corpus lexical neighbors. Preserve source-token citations and state whether each candidate is unrecovered or partially recovered. Mere co-occurrence, similarities between founder definitions, or an unreviewed companion word never ratify a new lexical definition, typed graph edge or inherited reality category. Review longer lists using the individual discovery functions.'
 );
$body$;
revoke all on function draft.get_noel_reality_preflight_v1(text,integer,integer) from public,anon,authenticated;
grant execute on function draft.get_noel_reality_preflight_v1(text,integer,integer) to service_role;
