create table if not exists instrument.v40_context_null_features as
with centers as (
 select w.center_id,w.book,w.block_index,w.target,w.f1,w.f3,w.f5,w.f7,w.f9,w.f11,
        l4.skeleton l4s,l3.skeleton l3s,l2.skeleton l2s,l1.skeleton l1s,l1.last_char l1last
 from instrument.v40_binned_windows w
 join instrument.v40_hebrew_tokens l1 on l1.id=w.center_id-1 and l1.book=w.book and l1.block_index=w.block_index and l1.holdout=true
 join instrument.v40_hebrew_tokens l2 on l2.id=w.center_id-2 and l2.book=w.book and l2.block_index=w.block_index and l2.holdout=true
 join instrument.v40_hebrew_tokens l3 on l3.id=w.center_id-3 and l3.book=w.book and l3.block_index=w.block_index and l3.holdout=true
 join instrument.v40_hebrew_tokens l4 on l4.id=w.center_id-4 and l4.book=w.book and l4.block_index=w.block_index and l4.holdout=true
 where w.holdout
), candidates as (
 select c.*,k,(10+k) d,
        case when p0.id is not null and p1.id is not null and p2.id is not null and p3.id is not null then p0.id else n0.id end r0id,
        case when p0.id is not null and p1.id is not null and p2.id is not null and p3.id is not null then p1.id else n1.id end r1id,
        case when p0.id is not null and p1.id is not null and p2.id is not null and p3.id is not null then p2.id else n2.id end r2id,
        case when p0.id is not null and p1.id is not null and p2.id is not null and p3.id is not null then p3.id else n3.id end r3id
 from centers c cross join generate_series(1,20) k
 left join instrument.v40_hebrew_tokens p0 on p0.id=c.center_id+(10+k) and p0.book=c.book and p0.block_index=c.block_index and p0.holdout=true
 left join instrument.v40_hebrew_tokens p1 on p1.id=c.center_id+(10+k)+1 and p1.book=c.book and p1.block_index=c.block_index and p1.holdout=true
 left join instrument.v40_hebrew_tokens p2 on p2.id=c.center_id+(10+k)+2 and p2.book=c.book and p2.block_index=c.block_index and p2.holdout=true
 left join instrument.v40_hebrew_tokens p3 on p3.id=c.center_id+(10+k)+3 and p3.book=c.book and p3.block_index=c.block_index and p3.holdout=true
 left join instrument.v40_hebrew_tokens n0 on n0.id=c.center_id-(10+k) and n0.book=c.book and n0.block_index=c.block_index and n0.holdout=true
 left join instrument.v40_hebrew_tokens n1 on n1.id=c.center_id-(10+k)+1 and n1.book=c.book and n1.block_index=c.block_index and n1.holdout=true
 left join instrument.v40_hebrew_tokens n2 on n2.id=c.center_id-(10+k)+2 and n2.book=c.book and n2.block_index=c.block_index and n2.holdout=true
 left join instrument.v40_hebrew_tokens n3 on n3.id=c.center_id-(10+k)+3 and n3.book=c.book and n3.block_index=c.block_index and n3.holdout=true
), picked as (
 select c.*,r0.len r0len,r1.len r1len,r2.len r2len,r3.len r3len,
        r0.terminal_final r0final,r1.terminal_final r1final,r2.terminal_final r2final,r3.terminal_final r3final,
        r0.equality_complexity r0eq,r1.equality_complexity r1eq,r2.equality_complexity r2eq,r3.equality_complexity r3eq,
        r0.intrinsic r0intr,r1.intrinsic r1intr,r2.intrinsic r2intr,r3.intrinsic r3intr,
        r0.skeleton r0s,r1.skeleton r1s,r2.skeleton r2s,r3.skeleton r3s,r0.first_char r0first
 from candidates c
 join instrument.v40_hebrew_tokens r0 on r0.id=c.r0id
 join instrument.v40_hebrew_tokens r1 on r1.id=c.r1id
 join instrument.v40_hebrew_tokens r2 on r2.id=c.r2id
 join instrument.v40_hebrew_tokens r3 on r3.id=c.r3id
)
select center_id,book,block_index,target,k,f1,f3,f5,f7,f9,f11,
       (r0len+r1len+r2len+r3len)::double precision/4.0 right_mean_len,
       sqrt(greatest(0.0,(r0len*r0len+r1len*r1len+r2len*r2len+r3len*r3len)::double precision/4.0-power((r0len+r1len+r2len+r3len)::double precision/4.0,2))) right_sd_len,
       (r0final::int+r1final::int+r2final::int+r3final::int)::double precision/4.0 right_final_rate,
       (r0eq+r1eq+r2eq+r3eq)/4.0 right_mean_equality_complexity,
       (abs(r1len-r0len)+abs(r2len-r1len)+abs(r3len-r2len))::double precision/3.0 right_mean_abs_len_delta,
       (select count(distinct x) from unnest(array[r0intr,r1intr,r2intr,r3intr]) x)::int right_distinct_intrinsic_count,
       least(4,(l4s=r0s)::int+(l4s=r1s)::int+(l4s=r2s)::int+(l4s=r3s)::int+(l3s=r0s)::int+(l3s=r1s)::int+(l3s=r2s)::int+(l3s=r3s)::int+(l2s=r0s)::int+(l2s=r1s)::int+(l2s=r2s)::int+(l2s=r3s)::int+(l1s=r0s)::int+(l1s=r1s)::int+(l1s=r2s)::int+(l1s=r3s)::int)::int cross_side_same_skeleton_pairs,
       (l1last=r0first)::int boundary_bridge
from picked;
create index if not exists v40_context_null_features_k_idx on instrument.v40_context_null_features(k,center_id);
create index if not exists v40_context_null_features_target_idx on instrument.v40_context_null_features(target);