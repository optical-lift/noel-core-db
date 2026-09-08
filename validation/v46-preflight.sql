-- V46 Regime-Conditioned Grammar Recombination Test
-- Frozen preflight checks. Read-only. No experiment scoring.
-- Date: 2026-09-07
--
-- Purpose:
--   1. Verify preserved V41-V44 lineage counts.
--   2. Apply the preregistered block-hash development/replication split.
--   3. Measure exact motif support under the frozen motif lengths/support rules.
--
-- This script must not alter state definitions, holdout membership, or source data.
--
-- IMPORTANT CORRECTION BEFORE MODEL FITTING:
--   `block_index` is only unique within book. The preserved block identifier is
--   therefore `(book, block_index)`. The original first execution incorrectly
--   aggregated repeated block_index values across books. The preregistered hash
--   rule itself remains unchanged in substance: it is applied to the complete
--   preserved block identifier as `book:block_index`.

\echo 'V46 lineage and split check'
with blocks as (
  select book,
         block_index,
         holdout,
         count(*) as n,
         mod(abs(hashtextextended(book||':'||block_index::text,46)),10) as bucket
  from instrument.v42_token_index
  group by book, block_index, holdout
)
select
  count(*) filter (where holdout=false) as nonholdout_blocks,
  count(*) filter (where holdout=false and bucket<7) as development_blocks,
  count(*) filter (where holdout=false and bucket>=7) as internal_replication_blocks,
  sum(n) filter (where holdout=false) as nonholdout_tokens,
  sum(n) filter (where holdout=false and bucket<7) as development_tokens,
  sum(n) filter (where holdout=false and bucket>=7) as internal_replication_tokens,
  count(*) filter (where holdout=true) as outer_holdout_blocks,
  sum(n) filter (where holdout=true) as outer_holdout_tokens
from blocks;

\echo 'V46 motif support check on development partition'
with s as (
  select t.book,t.block_index,t.holdout,t.rn,
         coalesce(i.rank,65) as st,
         mod(abs(hashtextextended(t.book||':'||t.block_index::text,46)),10) as bucket
  from instrument.v42_token_index t
  left join instrument.v41_target_inventory i on i.target=t.y
), w as (
  select *,
    lag(st,1) over(partition by book,block_index order by rn) p1,
    lag(st,2) over(partition by book,block_index order by rn) p2,
    lag(st,3) over(partition by book,block_index order by rn) p3,
    lag(st,4) over(partition by book,block_index order by rn) p4,
    lag(st,5) over(partition by book,block_index order by rn) p5
  from s
  where holdout=false
), motifs as (
  select book,block_index,bucket,
    array[p1,st]::text as m2,
    array[p2,p1,st]::text as m3,
    array[p3,p2,p1,st]::text as m4,
    array[p5,p4,p3,p2,p1,st]::text as m6
  from w
  where p5 is not null
    and bucket < 7
), c2 as (
  select m2,count(*) n,count(distinct (book,block_index)) blocks from motifs group by m2
), c3 as (
  select m3,count(*) n,count(distinct (book,block_index)) blocks from motifs group by m3
), c4 as (
  select m4,count(*) n,count(distinct (book,block_index)) blocks from motifs group by m4
), c6 as (
  select m6,count(*) n,count(distinct (book,block_index)) blocks from motifs group by m6
)
select 2 as motif_length,count(*) distinct_motifs,
       count(*) filter(where n>=100) supported_100,
       count(*) filter(where n>=300) supported_300,
       max(n) max_support
from c2
union all
select 3,count(*),count(*) filter(where n>=100),count(*) filter(where n>=300),max(n) from c3
union all
select 4,count(*),count(*) filter(where n>=100),count(*) filter(where n>=300),max(n) from c4
union all
select 6,count(*),count(*) filter(where n>=100),count(*) filter(where n>=300),max(n) from c6
order by motif_length;

-- Corrected first execution before any V46 model fitting/scoring (2026-09-07):
-- nonholdout_blocks=160
-- development_blocks=110
-- internal_replication_blocks=50
-- nonholdout_tokens=235209
-- development_tokens=158503
-- internal_replication_tokens=76706
-- outer_holdout_blocks=41
-- outer_holdout_tokens=71576
--
-- Corrected motif support on development:
-- length 2: distinct=2645, >=100=216, >=300=100, max=5071
-- length 3: distinct=21543, >=100=236, >=300=54, max=958
-- length 4: distinct=66681, >=100=53, >=300=0, max=211
-- length 6: distinct=145550, >=100=0, >=300=0, max=30
--
-- Consequence under the frozen rules:
-- length-4 contexts can participate in variable-order prediction when support
-- reaches 100, but decisive recombination cells requiring motif support >=300
-- can only originate from length-2 or length-3 motifs in this partition.
