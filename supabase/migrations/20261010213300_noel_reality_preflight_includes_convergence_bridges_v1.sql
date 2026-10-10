
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
    'ecosystem_attention',
      draft.get_noel_reality_ecosystem_v1(p_lookup,12),
    'ecosystem_bridges',
      draft.get_noel_reality_ecosystem_bridges_v1(p_lookup,12),
    'ecosystem_attention_instruction',
      'Report source-attested unexamined or partially recovered founder words BEFORE marking this pool complete. First inspect lexical co-occurrences in curated passages; also inspect multi-pool bridge candidates. A companion word is a research prompt, not an established lexical meaning, functional edge, or inherited reality category. Read the full discovery functions if the shortlist is insufficient.'
 );
$body$;
revoke all on function draft.get_noel_reality_preflight_v1(text,integer,integer) from public,anon,authenticated;
grant execute on function draft.get_noel_reality_preflight_v1(text,integer,integer) to service_role;
