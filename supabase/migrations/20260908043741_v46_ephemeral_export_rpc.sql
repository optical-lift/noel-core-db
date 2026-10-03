create or replace function public.v46_export_development()
returns table(book text, block_index integer, n_tokens bigint, state_sequence text)
language sql
security definer
set search_path = pg_catalog, public, instrument
as $$
  with s as (
    select
      t.book,
      t.block_index,
      t.rn,
      coalesce(i.rank,65)::int as state_id,
      mod(abs(hashtextextended(t.book||':'||t.block_index::text,46)),10) as bucket
    from instrument.v42_token_index t
    left join instrument.v41_target_inventory i on i.target=t.y
    where t.holdout=false
  )
  select
    s.book::text,
    s.block_index::integer,
    count(*)::bigint as n_tokens,
    string_agg(s.state_id::text, ',' order by s.rn) as state_sequence
  from s
  where s.bucket < 7
  group by s.book, s.block_index
  order by s.book, s.block_index;
$$;
revoke all on function public.v46_export_development() from public, anon, authenticated;
grant execute on function public.v46_export_development() to service_role;