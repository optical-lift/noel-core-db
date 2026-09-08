-- V46 frozen development-sequence export
-- Read-only. Does not open internal replication or outer holdout.
-- Date: 2026-09-07
--
-- Emits one row per preserved (book, block_index) development block.
-- State ids are V41 ranks 1..64 with OTHER=65.
-- The split is the preregistered deterministic hash on book:block_index, seed 46.

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
  book,
  block_index,
  count(*) as n_tokens,
  string_agg(state_id::text, ',' order by rn) as state_sequence
from s
where bucket < 7
group by book, block_index
order by book, block_index;
