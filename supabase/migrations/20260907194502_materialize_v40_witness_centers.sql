drop table if exists instrument.v40_witness_centers;
create table instrument.v40_witness_centers as
with q as (
  select source_token_id,min(codepoint)::int codepoint
  from draft.canon_masoretic_marks
  where witness_key='mt_noel_current' and codepoint between 1425 and 1455
  group by source_token_id having count(*)=1
)
select b.center_id,b.book,b.chapter,b.verse,b.position,b.block_index,b.holdout,
       b.target,b.f1,b.f2,b.f3,b.f4,b.f5,b.f6,b.f7,b.f8,b.f9,b.f10,b.f11,b.f12,b.f13,b.f14,
       t.skeleton,t.intrinsic,q.codepoint
from instrument.v40_binned_windows b
join instrument.v40_hebrew_tokens t on t.id=b.center_id
join draft.ot_canonical_tokens_stage s on s.book=b.book and s.chapter=b.chapter and s.verse=b.verse and s.position=b.position
join q on q.source_token_id=s.source_token_id;
create unique index v40_witness_centers_id_idx on instrument.v40_witness_centers(center_id);
create index v40_witness_centers_split_idx on instrument.v40_witness_centers(holdout,codepoint);
create index v40_witness_centers_intrinsic_idx on instrument.v40_witness_centers(intrinsic);
create index v40_witness_centers_skeleton_idx on instrument.v40_witness_centers(skeleton);