create table if not exists instrument.v39_witness_tokens as
with m as (
  select source_token_id,min(codepoint)::int as mark
  from draft.canon_masoretic_marks
  where witness_key='mt_noel_current' and codepoint between 1425 and 1455
  group by source_token_id
  having count(*)=1
)
select t.id,t.book,t.block_index,t.holdout,t.skeleton,t.intrinsic,m.mark,
       l.rcoarse as left_rcoarse,l.rpair as left_rpair,
       r.rcoarse as right_rcoarse,r.rpair as right_rpair
from instrument.v39_hebrew_tokens t
join draft.ot_canonical_tokens_stage src on src.id=t.id
join m on m.source_token_id=src.source_token_id
left join instrument.v39_hebrew_relations l on l.right_id=t.id and l.book=t.book and l.block_index=t.block_index and l.holdout=t.holdout
left join instrument.v39_hebrew_relations r on r.left_id=t.id and r.book=t.book and r.block_index=t.block_index and r.holdout=t.holdout;
create unique index if not exists v39_witness_tokens_id_idx on instrument.v39_witness_tokens(id);
create index if not exists v39_witness_tokens_split_idx on instrument.v39_witness_tokens(holdout,mark);
create index if not exists v39_witness_tokens_intrinsic_idx on instrument.v39_witness_tokens(intrinsic);
create index if not exists v39_witness_tokens_skeleton_idx on instrument.v39_witness_tokens(skeleton);