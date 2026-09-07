create table if not exists instrument.v41_null_permutations (
  k integer primary key,
  s1 integer not null,s2 integer not null,s3 integer not null,s4 integer not null,
  s5 integer not null,s6 integer not null,s7 integer not null,s8 integer not null
);

insert into instrument.v41_null_permutations(k,s1,s2,s3,s4,s5,s6,s7,s8)
select k,
  a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8]
from (
  select k,array_agg(off order by md5('v41-position-null-'||lpad(k::text,2,'0')||'|'||off::text)) a
  from generate_series(1,20) k
  cross join unnest(array[-4,-3,-2,-1,1,2,3,4]) off
  group by k
) q
on conflict(k) do update set s1=excluded.s1,s2=excluded.s2,s3=excluded.s3,s4=excluded.s4,s5=excluded.s5,s6=excluded.s6,s7=excluded.s7,s8=excluded.s8;

create table if not exists instrument.v41_null_features (
  k integer not null,
  center_id bigint not null,
  true_y text not null,
  center_skeleton text not null,
  m4_l integer not null,m4_r integer not null,m4_f integer not null,
  m3_l integer not null,m3_r integer not null,m3_f integer not null,
  m2_l integer not null,m2_r integer not null,m2_f integer not null,
  m1_l integer not null,m1_r integer not null,m1_f integer not null,
  p1_l integer not null,p1_r integer not null,p1_f integer not null,
  p2_l integer not null,p2_r integer not null,p2_f integer not null,
  p3_l integer not null,p3_r integer not null,p3_f integer not null,
  p4_l integer not null,p4_r integer not null,p4_f integer not null,
  dl_l1 integer not null,dr_l1 integer not null,
  dl_l2 integer not null,dr_l2 integer not null,
  dl_l3 integer not null,dr_l3 integer not null,
  dl_r1 integer not null,dr_r1 integer not null,
  dl_r2 integer not null,dr_r2 integer not null,
  dl_r3 integer not null,dr_r3 integer not null,
  xshared integer not null,xboundary integer not null,
  primary key(k,center_id)
);

create or replace function instrument.v41_build_null_features(null_k integer)
returns bigint
language plpgsql
as $function$
declare n bigint;
begin
  delete from instrument.v41_null_features where k=null_k;
  insert into instrument.v41_null_features(
    k,center_id,true_y,center_skeleton,
    m4_l,m4_r,m4_f,m3_l,m3_r,m3_f,m2_l,m2_r,m2_f,m1_l,m1_r,m1_f,
    p1_l,p1_r,p1_f,p2_l,p2_r,p2_f,p3_l,p3_r,p3_f,p4_l,p4_r,p4_f,
    dl_l1,dr_l1,dl_l2,dr_l2,dl_l3,dr_l3,dl_r1,dr_r1,dl_r2,dr_r2,dl_r3,dr_r3,
    xshared,xboundary)
  select null_k,w.y,w.y,w.center_skeleton,
    t1.len_bin,least(t1.repeat_excess,2),t1.terminal_final::int,
    t2.len_bin,least(t2.repeat_excess,2),t2.terminal_final::int,
    t3.len_bin,least(t3.repeat_excess,2),t3.terminal_final::int,
    t4.len_bin,least(t4.repeat_excess,2),t4.terminal_final::int,
    t5.len_bin,least(t5.repeat_excess,2),t5.terminal_final::int,
    t6.len_bin,least(t6.repeat_excess,2),t6.terminal_final::int,
    t7.len_bin,least(t7.repeat_excess,2),t7.terminal_final::int,
    t8.len_bin,least(t8.repeat_excess,2),t8.terminal_final::int,
    least(3,greatest(-3,t2.len-t1.len)),least(2,greatest(-2,t2.repeat_excess-t1.repeat_excess)),
    least(3,greatest(-3,t3.len-t2.len)),least(2,greatest(-2,t3.repeat_excess-t2.repeat_excess)),
    least(3,greatest(-3,t4.len-t3.len)),least(2,greatest(-2,t4.repeat_excess-t3.repeat_excess)),
    least(3,greatest(-3,t6.len-t5.len)),least(2,greatest(-2,t6.repeat_excess-t5.repeat_excess)),
    least(3,greatest(-3,t7.len-t6.len)),least(2,greatest(-2,t7.repeat_excess-t6.repeat_excess)),
    least(3,greatest(-3,t8.len-t7.len)),least(2,greatest(-2,t8.repeat_excess-t7.repeat_excess)),
    (select least(3,count(distinct x)) from unnest(t4.chars) x where x=any(t5.chars))::int,
    (t4.chars[array_length(t4.chars,1)]=t5.chars[1])::int
  from instrument.v41_train w
  join instrument.v41_null_permutations p on p.k=null_k
  join instrument.v41_hebrew_tokens t1 on t1.id=w.center_id+p.s1
  join instrument.v41_hebrew_tokens t2 on t2.id=w.center_id+p.s2
  join instrument.v41_hebrew_tokens t3 on t3.id=w.center_id+p.s3
  join instrument.v41_hebrew_tokens t4 on t4.id=w.center_id+p.s4
  join instrument.v41_hebrew_tokens t5 on t5.id=w.center_id+p.s5
  join instrument.v41_hebrew_tokens t6 on t6.id=w.center_id+p.s6
  join instrument.v41_hebrew_tokens t7 on t7.id=w.center_id+p.s7
  join instrument.v41_hebrew_tokens t8 on t8.id=w.center_id+p.s8
  where w.holdout;
  get diagnostics n=row_count;
  return n;
end
$function$;

create table if not exists instrument.v41_null_accum (
  k integer not null,
  center_id bigint not null,
  max_score double precision not null,
  sumexp double precision not null,
  true_score double precision,
  primary key(k,center_id)
);

create table if not exists instrument.v41_null_results (
  k integer primary key,
  n bigint not null,
  ce_nats double precision not null,
  created_at timestamptz not null default now()
);

create or replace function instrument.v41_null_score_batch(null_k integer, lo integer, hi integer)
returns bigint
language sql
as $function$
with scores as (
 select f.center_id,f.true_y,tr.y,
 ln(tr.n::double precision/(select sum(n)::double precision from instrument.v41_target_counts))
 +c1.score+c2.score+c3.score+c4.score+c5.score+c6.score+c7.score+c8.score
 +t1.score+t2.score+t3.score+t4.score+t5.score+t6.score+x.score as score
 from instrument.v41_null_features f cross join instrument.v41_target_rank tr
 join instrument.v41_pos_components c1 on c1.comp=1 and c1.y=tr.y and c1.l=f.m4_l and c1.rr=f.m4_r and c1.ff=f.m4_f
 join instrument.v41_pos_components c2 on c2.comp=2 and c2.y=tr.y and c2.l=f.m3_l and c2.rr=f.m3_r and c2.ff=f.m3_f
 join instrument.v41_pos_components c3 on c3.comp=3 and c3.y=tr.y and c3.l=f.m2_l and c3.rr=f.m2_r and c3.ff=f.m2_f
 join instrument.v41_pos_components c4 on c4.comp=4 and c4.y=tr.y and c4.l=f.m1_l and c4.rr=f.m1_r and c4.ff=f.m1_f
 join instrument.v41_pos_components c5 on c5.comp=5 and c5.y=tr.y and c5.l=f.p1_l and c5.rr=f.p1_r and c5.ff=f.p1_f
 join instrument.v41_pos_components c6 on c6.comp=6 and c6.y=tr.y and c6.l=f.p2_l and c6.rr=f.p2_r and c6.ff=f.p2_f
 join instrument.v41_pos_components c7 on c7.comp=7 and c7.y=tr.y and c7.l=f.p3_l and c7.rr=f.p3_r and c7.ff=f.p3_f
 join instrument.v41_pos_components c8 on c8.comp=8 and c8.y=tr.y and c8.l=f.p4_l and c8.rr=f.p4_r and c8.ff=f.p4_f
 join instrument.v41_traj_components t1 on t1.comp=1 and t1.y=tr.y and t1.dl=f.dl_l1 and t1.dr=f.dr_l1
 join instrument.v41_traj_components t2 on t2.comp=2 and t2.y=tr.y and t2.dl=f.dl_l2 and t2.dr=f.dr_l2
 join instrument.v41_traj_components t3 on t3.comp=3 and t3.y=tr.y and t3.dl=f.dl_l3 and t3.dr=f.dr_l3
 join instrument.v41_traj_components t4 on t4.comp=4 and t4.y=tr.y and t4.dl=f.dl_r1 and t4.dr=f.dr_r1
 join instrument.v41_traj_components t5 on t5.comp=5 and t5.y=tr.y and t5.dl=f.dl_r2 and t5.dr=f.dr_r2
 join instrument.v41_traj_components t6 on t6.comp=6 and t6.y=tr.y and t6.dl=f.dl_r3 and t6.dr=f.dr_r3
 join instrument.v41_cross_components x on x.y=tr.y and x.xshared=f.xshared and x.xboundary=f.xboundary
 where f.k=null_k and tr.r between lo and hi
), bm as (
 select center_id,max(score) bmax,max(score) filter(where y=true_y) btrue from scores group by center_id
), ba as (
 select s.center_id,bm.bmax,sum(exp(s.score-bm.bmax)) bsum,bm.btrue from scores s join bm using(center_id) group by s.center_id,bm.bmax,bm.btrue
), up as (
 insert into instrument.v41_null_accum(k,center_id,max_score,sumexp,true_score)
 select null_k,center_id,bmax,bsum,btrue from ba
 on conflict(k,center_id) do update set
   sumexp=instrument.v41_null_accum.sumexp*exp(instrument.v41_null_accum.max_score-greatest(instrument.v41_null_accum.max_score,excluded.max_score))
          +excluded.sumexp*exp(excluded.max_score-greatest(instrument.v41_null_accum.max_score,excluded.max_score)),
   max_score=greatest(instrument.v41_null_accum.max_score,excluded.max_score),
   true_score=coalesce(instrument.v41_null_accum.true_score,excluded.true_score)
 returning 1
)
select count(*)::bigint from up;
$function$;

create or replace function instrument.v41_run_null(null_k integer)
returns double precision
language plpgsql
as $function$
declare i integer; ce double precision; nn bigint;
begin
  delete from instrument.v41_null_accum where k=null_k;
  for i in 0..12 loop
    perform instrument.v41_null_score_batch(null_k,1+i*5,least(65,5+i*5));
  end loop;
  select count(*),avg((max_score+ln(sumexp))-true_score) into nn,ce
  from instrument.v41_null_accum where k=null_k and true_score is not null;
  if nn<>71248 then raise exception 'V41 null % incomplete: % centers',null_k,nn; end if;
  insert into instrument.v41_null_results(k,n,ce_nats) values(null_k,nn,ce)
  on conflict(k) do update set n=excluded.n,ce_nats=excluded.ce_nats,created_at=now();
  return ce;
end
$function$;