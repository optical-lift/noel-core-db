create table if not exists instrument.v40_hebrew_tokens as
with hb(book,block_index) as (
 values
 ('Neh',2),('Isa',5),('Psa',14),('Gen',3),('Eze',4),('Lev',4),('Gen',1),('Deu',3),('Exo',1),('Psa',4),
 ('Neh',1),('Zec',2),('Hag',0),('2Ch',0),('Deu',4),('1Ki',3),('Psa',6),('1Ch',5),('Job',0),('Psa',17),
 ('Num',2),('Exo',2),('Dan',1),('Gen',9),('Job',2),('Isa',10),('Sng',0),('Job',3),('Gen',0),('Jer',5),
 ('Jer',10),('Deu',5),('1Ch',4),('1Ch',0),('Dan',2),('Lev',3),('1Sa',0),('Num',5),('Deu',0),('Eze',7),('1Ch',3)
)
select t.id,t.book,t.chapter,t.verse,t.position,t.block_index,
       (h.book is not null) as holdout,
       t.skeleton,t.chars,t.len,t.eq_pattern,t.terminal_final,t.intrinsic,
       (select count(distinct x) from unnest(t.chars) x)::int as distinct_consonants,
       case when t.len>0 then (select count(distinct x) from unnest(t.chars) x)::double precision/t.len else 0 end as equality_complexity,
       t.chars[1] as first_char,
       t.chars[array_length(t.chars,1)] as last_char
from instrument.v39_hebrew_tokens t
left join hb h on h.book=t.book and h.block_index=t.block_index;

create unique index if not exists v40_hebrew_tokens_id_idx on instrument.v40_hebrew_tokens(id);
create index if not exists v40_hebrew_tokens_split_idx on instrument.v40_hebrew_tokens(holdout,book,block_index,id);
create index if not exists v40_hebrew_tokens_intrinsic_idx on instrument.v40_hebrew_tokens(intrinsic);
create index if not exists v40_hebrew_tokens_skeleton_idx on instrument.v40_hebrew_tokens(skeleton);