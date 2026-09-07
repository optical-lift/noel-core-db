create table if not exists instrument.v40_center_blind_windows as
select c.id as center_id,c.book,c.chapter,c.verse,c.position,c.block_index,c.holdout,c.intrinsic as center_intrinsic,
       (l4.len+l3.len+l2.len+l1.len)::double precision/4.0 as left_mean_len,
       (r1.len+r2.len+r3.len+r4.len)::double precision/4.0 as right_mean_len,
       sqrt(greatest(0.0, (l4.len*l4.len+l3.len*l3.len+l2.len*l2.len+l1.len*l1.len)::double precision/4.0 - power((l4.len+l3.len+l2.len+l1.len)::double precision/4.0,2))) as left_sd_len,
       sqrt(greatest(0.0, (r1.len*r1.len+r2.len*r2.len+r3.len*r3.len+r4.len*r4.len)::double precision/4.0 - power((r1.len+r2.len+r3.len+r4.len)::double precision/4.0,2))) as right_sd_len,
       ((l4.terminal_final::int+l3.terminal_final::int+l2.terminal_final::int+l1.terminal_final::int)::double precision/4.0) as left_final_rate,
       ((r1.terminal_final::int+r2.terminal_final::int+r3.terminal_final::int+r4.terminal_final::int)::double precision/4.0) as right_final_rate,
       (l4.equality_complexity+l3.equality_complexity+l2.equality_complexity+l1.equality_complexity)/4.0 as left_mean_equality_complexity,
       (r1.equality_complexity+r2.equality_complexity+r3.equality_complexity+r4.equality_complexity)/4.0 as right_mean_equality_complexity,
       (abs(l3.len-l4.len)+abs(l2.len-l3.len)+abs(l1.len-l2.len))::double precision/3.0 as left_mean_abs_len_delta,
       (abs(r2.len-r1.len)+abs(r3.len-r2.len)+abs(r4.len-r3.len))::double precision/3.0 as right_mean_abs_len_delta,
       (select count(distinct x) from unnest(array[l4.intrinsic,l3.intrinsic,l2.intrinsic,l1.intrinsic]) x)::int as left_distinct_intrinsic_count,
       (select count(distinct x) from unnest(array[r1.intrinsic,r2.intrinsic,r3.intrinsic,r4.intrinsic]) x)::int as right_distinct_intrinsic_count,
       least(4,
         (l4.skeleton=r1.skeleton)::int+(l4.skeleton=r2.skeleton)::int+(l4.skeleton=r3.skeleton)::int+(l4.skeleton=r4.skeleton)::int+
         (l3.skeleton=r1.skeleton)::int+(l3.skeleton=r2.skeleton)::int+(l3.skeleton=r3.skeleton)::int+(l3.skeleton=r4.skeleton)::int+
         (l2.skeleton=r1.skeleton)::int+(l2.skeleton=r2.skeleton)::int+(l2.skeleton=r3.skeleton)::int+(l2.skeleton=r4.skeleton)::int+
         (l1.skeleton=r1.skeleton)::int+(l1.skeleton=r2.skeleton)::int+(l1.skeleton=r3.skeleton)::int+(l1.skeleton=r4.skeleton)::int
       )::int as cross_side_same_skeleton_pairs,
       (l1.last_char=r1.first_char) as boundary_bridge
from instrument.v40_hebrew_tokens c
join instrument.v40_hebrew_tokens l1 on l1.id=c.id-1 and l1.book=c.book and l1.block_index=c.block_index and l1.holdout=c.holdout
join instrument.v40_hebrew_tokens l2 on l2.id=c.id-2 and l2.book=c.book and l2.block_index=c.block_index and l2.holdout=c.holdout
join instrument.v40_hebrew_tokens l3 on l3.id=c.id-3 and l3.book=c.book and l3.block_index=c.block_index and l3.holdout=c.holdout
join instrument.v40_hebrew_tokens l4 on l4.id=c.id-4 and l4.book=c.book and l4.block_index=c.block_index and l4.holdout=c.holdout
join instrument.v40_hebrew_tokens r1 on r1.id=c.id+1 and r1.book=c.book and r1.block_index=c.block_index and r1.holdout=c.holdout
join instrument.v40_hebrew_tokens r2 on r2.id=c.id+2 and r2.book=c.book and r2.block_index=c.block_index and r2.holdout=c.holdout
join instrument.v40_hebrew_tokens r3 on r3.id=c.id+3 and r3.book=c.book and r3.block_index=c.block_index and r3.holdout=c.holdout
join instrument.v40_hebrew_tokens r4 on r4.id=c.id+4 and r4.book=c.book and r4.block_index=c.block_index and r4.holdout=c.holdout;

create unique index if not exists v40_center_blind_windows_center_idx on instrument.v40_center_blind_windows(center_id);
create index if not exists v40_center_blind_windows_split_idx on instrument.v40_center_blind_windows(holdout,book,block_index,center_id);
create index if not exists v40_center_blind_windows_target_idx on instrument.v40_center_blind_windows(center_intrinsic);