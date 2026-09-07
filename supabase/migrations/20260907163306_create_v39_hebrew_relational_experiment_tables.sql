create table if not exists instrument.v39_hebrew_tokens as
with base as (
  select id,book,chapter,verse,position,((chapter-1)/5)::int as block_index,
         regexp_replace(hebrew_surface,'[^א-ת]','','g') as skeleton
  from draft.ot_canonical_tokens_stage
), blocks as (
  select distinct book, block_index from base
), ranked as (
  select book,block_index,row_number() over(order by md5('v39-hebrew-relational-holdout|'||book||':'||block_index),book,block_index) as r
  from blocks
), arr as (
  select b.*, regexp_split_to_array(b.skeleton,'') as chars, (r.r<=41) as holdout
  from base b join ranked r using(book,block_index)
), feat as (
  select a.*,
         coalesce((select string_agg(array_position(a.chars,a.chars[g])::text,'.' order by g) from generate_subscripts(a.chars,1) g),'') as eq_pattern,
         (case when cardinality(a.chars)>0 then a.chars[cardinality(a.chars)] in ('ך','ם','ן','ף','ץ') else false end) as terminal_final
  from arr a
)
select id,book,chapter,verse,position,block_index,holdout,skeleton,chars,
       cardinality(chars)::int as len,eq_pattern,terminal_final,
       cardinality(chars)::text||'|'||eq_pattern||'|'||terminal_final::text as intrinsic
from feat;

create unique index if not exists v39_hebrew_tokens_id_idx on instrument.v39_hebrew_tokens(id);
create index if not exists v39_hebrew_tokens_split_idx on instrument.v39_hebrew_tokens(holdout,book,block_index,id);
create index if not exists v39_hebrew_tokens_intrinsic_idx on instrument.v39_hebrew_tokens(intrinsic);

create table if not exists instrument.v39_hebrew_relations as
with t as (
  select * from instrument.v39_hebrew_tokens
), pairs as (
  select a.id as left_id,b.id as right_id,a.book,a.block_index,a.holdout,
         a.skeleton as left_skeleton,b.skeleton as right_skeleton,
         a.intrinsic as left_intrinsic,b.intrinsic as right_intrinsic,
         a.chars as ac,b.chars as bc,a.len as alen,b.len as blen,
         a.terminal_final as afinal,b.terminal_final as bfinal
  from t a join t b on b.id=a.id+1 and b.book=a.book and b.block_index=a.block_index and b.holdout=a.holdout
), f as (
  select p.*,
    least(8,alen)::text as alen_bin,
    least(8,blen)::text as blen_bin,
    case when blen-alen < -3 then 'LT-3' when blen-alen > 3 then 'GT3' else (blen-alen)::text end as dlen_bin,
    least(3,(select count(*) from (select distinct x from unnest(ac) x intersect select distinct y from unnest(bc) y) s))::text as shared_bin,
    (alen>0 and blen>0 and ac[1]=bc[1]) as same_first,
    (alen>0 and blen>0 and ac[alen]=bc[blen]) as same_last,
    (alen>0 and blen>0 and ac[alen]=bc[1]) as boundary_continuity,
    (left_skeleton=right_skeleton) as exact_repeat,
    (select string_agg(array_position(ac||bc,(ac||bc)[g])::text,'.' order by g) from generate_subscripts(ac||bc,1) g) as pair_all_pattern
  from pairs p
)
select left_id,right_id,book,block_index,holdout,left_intrinsic,right_intrinsic,
       alen_bin||','||blen_bin||','||dlen_bin||','||shared_bin||','||same_first::text||','||same_last::text||','||boundary_continuity::text||','||exact_repeat::text||','||afinal::text||','||bfinal::text as rcoarse,
       split_part(pair_all_pattern,'.',1) as _dummy,
       pair_all_pattern
from f;

alter table instrument.v39_hebrew_relations add column if not exists rpair text;
update instrument.v39_hebrew_relations r
set rpair = (
  select string_agg(v,'.' order by ord)
  from (
    select ord, case when ord=(select len from instrument.v39_hebrew_tokens where id=r.left_id)+1 then '|'||val else val end as v
    from unnest(string_to_array(r.pair_all_pattern,'.')) with ordinality z(val,ord)
  ) q
);
alter table instrument.v39_hebrew_relations drop column if exists _dummy;
create unique index if not exists v39_hebrew_relations_pair_idx on instrument.v39_hebrew_relations(left_id,right_id);
create index if not exists v39_hebrew_relations_split_idx on instrument.v39_hebrew_relations(holdout,book,block_index,right_id);
create index if not exists v39_hebrew_relations_rcoarse_idx on instrument.v39_hebrew_relations(rcoarse);
create index if not exists v39_hebrew_relations_rpair_idx on instrument.v39_hebrew_relations(rpair);