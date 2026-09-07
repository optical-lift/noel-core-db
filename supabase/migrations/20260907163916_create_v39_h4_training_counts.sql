create table if not exists instrument.v39_h4_counts as
select cur.intrinsic||'||'||rprev.rcoarse||'||'||rleft.rcoarse as ctx,
       case when s.state is null then 'OTHER' else nxt.intrinsic end as y,
       count(*)::bigint as n
from instrument.v39_hebrew_tokens cur
join instrument.v39_hebrew_tokens nxt on nxt.id=cur.id+1 and nxt.book=cur.book and nxt.block_index=cur.block_index
join instrument.v39_hebrew_relations rleft on rleft.right_id=cur.id
join instrument.v39_hebrew_relations rprev on rprev.right_id=cur.id-1
left join instrument.v39_top64_states s on s.state=nxt.intrinsic
where not cur.holdout and not nxt.holdout and not rleft.holdout and not rprev.holdout
  and rleft.book=cur.book and rleft.block_index=cur.block_index
  and rprev.book=cur.book and rprev.block_index=cur.block_index
group by cur.intrinsic||'||'||rprev.rcoarse||'||'||rleft.rcoarse,
         case when s.state is null then 'OTHER' else nxt.intrinsic end;
create index if not exists v39_h4_counts_idx on instrument.v39_h4_counts(ctx,y);