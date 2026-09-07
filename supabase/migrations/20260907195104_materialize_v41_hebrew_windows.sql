drop table if exists instrument.v41_hebrew_tokens;
create table instrument.v41_hebrew_tokens as
select t.id,t.book,t.chapter,t.verse,t.position,
       ((t.chapter-1)/5)::int block_index,
       (md5('v41-hebrew-position-field|'||t.book||':'||((t.chapter-1)/5)::int) in (
         select md5('v41-hebrew-position-field|'||book||':'||block_index)
         from (
           select book,block_index from (
             select book,((chapter-1)/5)::int block_index,
                    row_number() over(order by md5('v41-hebrew-position-field|'||book||':'||((chapter-1)/5)::int),book,((chapter-1)/5)::int) r
             from draft.ot_canonical_tokens_stage group by book,((chapter-1)/5)::int
           ) z where r<=41
         ) h
       )) as holdout,
       t.skeleton,t.chars,t.len,t.intrinsic,t.distinct_consonants,t.terminal_final,
       least(greatest(t.len-t.distinct_consonants,0),2)::int repeat_excess,
       case when t.len<=8 then t.len else 9 end::int len_bin
from instrument.v40_hebrew_tokens t;
create unique index v41_hebrew_tokens_id_idx on instrument.v41_hebrew_tokens(id);
create index v41_hebrew_tokens_split_idx on instrument.v41_hebrew_tokens(holdout,book,block_index,id);

 drop table if exists instrument.v41_windows;
create table instrument.v41_windows as
select c.id center_id,c.book,c.chapter,c.verse,c.position,c.block_index,c.holdout,c.skeleton center_skeleton,c.intrinsic target,
       a4.len_bin m4_l,a4.repeat_excess m4_r,a4.terminal_final::int m4_f,
       a3.len_bin m3_l,a3.repeat_excess m3_r,a3.terminal_final::int m3_f,
       a2.len_bin m2_l,a2.repeat_excess m2_r,a2.terminal_final::int m2_f,
       a1.len_bin m1_l,a1.repeat_excess m1_r,a1.terminal_final::int m1_f,
       b1.len_bin p1_l,b1.repeat_excess p1_r,b1.terminal_final::int p1_f,
       b2.len_bin p2_l,b2.repeat_excess p2_r,b2.terminal_final::int p2_f,
       b3.len_bin p3_l,b3.repeat_excess p3_r,b3.terminal_final::int p3_f,
       b4.len_bin p4_l,b4.repeat_excess p4_r,b4.terminal_final::int p4_f,
       greatest(-3,least(3,a3.len-a4.len)) dl_l1,
       greatest(-2,least(2,a3.repeat_excess-a4.repeat_excess)) dr_l1,
       greatest(-3,least(3,a2.len-a3.len)) dl_l2,
       greatest(-2,least(2,a2.repeat_excess-a3.repeat_excess)) dr_l2,
       greatest(-3,least(3,a1.len-a2.len)) dl_l3,
       greatest(-2,least(2,a1.repeat_excess-a2.repeat_excess)) dr_l3,
       greatest(-3,least(3,b2.len-b1.len)) dl_r1,
       greatest(-2,least(2,b2.repeat_excess-b1.repeat_excess)) dr_r1,
       greatest(-3,least(3,b3.len-b2.len)) dl_r2,
       greatest(-2,least(2,b3.repeat_excess-b2.repeat_excess)) dr_r2,
       greatest(-3,least(3,b4.len-b3.len)) dl_r3,
       greatest(-2,least(2,b4.repeat_excess-b3.repeat_excess)) dr_r3,
       least(3,(select count(*) from (select distinct x from unnest(a1.chars) x intersect select distinct y from unnest(b1.chars) y) q))::int xshared,
       (a1.chars[array_length(a1.chars,1)] = b1.chars[1])::int xboundary
from instrument.v41_hebrew_tokens c
join instrument.v41_hebrew_tokens a1 on a1.id=c.id-1 and a1.book=c.book and a1.block_index=c.block_index and a1.holdout=c.holdout
join instrument.v41_hebrew_tokens a2 on a2.id=c.id-2 and a2.book=c.book and a2.block_index=c.block_index and a2.holdout=c.holdout
join instrument.v41_hebrew_tokens a3 on a3.id=c.id-3 and a3.book=c.book and a3.block_index=c.block_index and a3.holdout=c.holdout
join instrument.v41_hebrew_tokens a4 on a4.id=c.id-4 and a4.book=c.book and a4.block_index=c.block_index and a4.holdout=c.holdout
join instrument.v41_hebrew_tokens b1 on b1.id=c.id+1 and b1.book=c.book and b1.block_index=c.block_index and b1.holdout=c.holdout
join instrument.v41_hebrew_tokens b2 on b2.id=c.id+2 and b2.book=c.book and b2.block_index=c.block_index and b2.holdout=c.holdout
join instrument.v41_hebrew_tokens b3 on b3.id=c.id+3 and b3.book=c.book and b3.block_index=c.block_index and b3.holdout=c.holdout
join instrument.v41_hebrew_tokens b4 on b4.id=c.id+4 and b4.book=c.book and b4.block_index=c.block_index and b4.holdout=c.holdout;
create unique index v41_windows_id_idx on instrument.v41_windows(center_id);
create index v41_windows_split_idx on instrument.v41_windows(holdout,book,block_index,center_id);