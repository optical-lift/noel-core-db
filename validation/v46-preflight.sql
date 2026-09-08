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

\echo 'V46 lineage and split check'
with base as (
  select block_index, holdout, rn, y
  from instrument.v42_token_index
), blocks as (
  select block_index,
         count(*) filter (where holdout = false) as nonholdout_tokens,
         count(*) filter (where holdout = true) as holdout_tokens,
         mod(abs(hashtextextended(block_index::text,46)),10) as bucket
  from base
  group by block_index
)
select
  count(*) as blocks_total,
  count(*) filter (where nonholdout_tokens > 0) as nonholdout_blocks,
  sum(nonholdout_tokens) as nonholdout_tokens,
  sum(nonholdout_tokens) filter (where bucket < 7) as development_tokens,
  sum(nonholdout_tokens) filter (where bucket >= 7) as internal_replication_tokens,
  sum(holdout_tokens) as outer_holdout_tokens
from blocks;

\echo 'V46 motif support check on development partition'
with s as (
  select t.block_index,t.holdout,t.rn,
         coalesce(i.rank,65) as st,
         mod(abs(hashtextextended(t.block_index::text,46)),10) as bucket
  from instrument.v42_token_index t
  left join instrument.v41_target_inventory i on i.target=t.y
), w as (
  select *,
    lag(st,1) over(partition by block_index order by rn) p1,
    lag(st,2) over(partition by block_index order by rn) p2,
    lag(st,3) over(partition by block_index order by rn) p3,
    lag(st,4) over(partition by block_index order by rn) p4,
    lag(st,5) over(partition by block_index order by rn) p5
  from s
  where holdout=false
), motifs as (
  select block_index,bucket,
    array[p1,st]::text as m2,
    array[p2,p1,st]::text as m3,
    array[p3,p2,p1,st]::text as m4,
    array[p5,p4,p3,p2,p1,st]::text as m6
  from w
  where p5 is not null
    and bucket < 7
), c2 as (
  select m2,count(*) n,count(distinct block_index) blocks from motifs group by m2
), c3 as (
  select m3,count(*) n,count(distinct block_index) blocks from motifs group by m3
), c4 as (
  select m4,count(*) n,count(distinct block_index) blocks from motifs group by m4
), c6 as (
  select m6,count(*) n,count(distinct block_index) blocks from motifs group by m6
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

-- Expected first execution (2026-09-07):
-- blocks_total=30
-- nonholdout_blocks=26
-- nonholdout_tokens=235209
-- development_tokens=117630
-- internal_replication_tokens=117579
-- outer_holdout_tokens=71576
--
-- Note: the preregistered 70/30 hash rule produces an approximately 50/50
-- token split because intact blocks are highly unequal in size. The rule is
-- retained unchanged after freezing.
--
-- Motif support on first execution:
-- length 2: distinct=2502, >=100=184, >=300=80, max=3678
-- length 3: distinct=19165, >=100=164, >=300=33, max=670
-- length 4: distinct=56851, >=100=16, >=300=0, max=130
-- length 6: distinct=113289, >=100=0, >=300=0, max=11
--
-- Consequence under the frozen rules:
-- length-4 contexts can participate in variable-order prediction when support
-- reaches 100, but decisive recombination cells requiring motif support >=300
-- can only originate from length-2 or length-3 motifs in this partition.
