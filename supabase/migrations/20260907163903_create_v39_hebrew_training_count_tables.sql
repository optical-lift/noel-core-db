create table if not exists instrument.v39_top64_states as
select intrinsic as state, row_number() over(order by count(*) desc,intrinsic)::int as rank
from instrument.v39_hebrew_tokens
where not holdout
group by intrinsic
order by count(*) desc,intrinsic
limit 64;
create unique index if not exists v39_top64_states_state_idx on instrument.v39_top64_states(state);

create table if not exists instrument.v39_h1_counts as
select cur.intrinsic as ctx,
       case when s.state is null then 'OTHER' else nxt.intrinsic end as y,
       count(*)::bigint as n
from instrument.v39_hebrew_tokens cur
join instrument.v39_hebrew_tokens nxt on nxt.id=cur.id+1 and nxt.book=cur.book and nxt.block_index=cur.block_index
left join instrument.v39_top64_states s on s.state=nxt.intrinsic
where not cur.holdout and not nxt.holdout
group by cur.intrinsic,case when s.state is null then 'OTHER' else nxt.intrinsic end;
create index if not exists v39_h1_counts_idx on instrument.v39_h1_counts(ctx,y);

create table if not exists instrument.v39_h2_counts as
select cur.intrinsic||'||'||rel.rcoarse as ctx,
       case when s.state is null then 'OTHER' else nxt.intrinsic end as y,
       count(*)::bigint as n
from instrument.v39_hebrew_tokens cur
join instrument.v39_hebrew_tokens nxt on nxt.id=cur.id+1 and nxt.book=cur.book and nxt.block_index=cur.block_index
join instrument.v39_hebrew_relations rel on rel.right_id=cur.id
left join instrument.v39_top64_states s on s.state=nxt.intrinsic
where not cur.holdout and not nxt.holdout and not rel.holdout
group by cur.intrinsic||'||'||rel.rcoarse,case when s.state is null then 'OTHER' else nxt.intrinsic end;
create index if not exists v39_h2_counts_idx on instrument.v39_h2_counts(ctx,y);

create table if not exists instrument.v39_h3_counts as
select cur.intrinsic||'||'||rel.rpair as ctx,
       case when s.state is null then 'OTHER' else nxt.intrinsic end as y,
       count(*)::bigint as n
from instrument.v39_hebrew_tokens cur
join instrument.v39_hebrew_tokens nxt on nxt.id=cur.id+1 and nxt.book=cur.book and nxt.block_index=cur.block_index
join instrument.v39_hebrew_relations rel on rel.right_id=cur.id
left join instrument.v39_top64_states s on s.state=nxt.intrinsic
where not cur.holdout and not nxt.holdout and not rel.holdout
group by cur.intrinsic||'||'||rel.rpair,case when s.state is null then 'OTHER' else nxt.intrinsic end;
create index if not exists v39_h3_counts_idx on instrument.v39_h3_counts(ctx,y);