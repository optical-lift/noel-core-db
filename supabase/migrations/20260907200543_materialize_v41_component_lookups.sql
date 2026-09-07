drop table if exists instrument.v41_p1_logprob;
create table instrument.v41_p1_logprob as
with cells as (
 select tc.y,fa.feature_no,v.feature_value,tc.n::double precision yn,fa.k,coalesce(fc.n,0)::double precision cnt
 from instrument.v41_target_counts tc cross join instrument.v41_feature_alphabets fa
 cross join lateral unnest(fa.vals) v(feature_value)
 left join instrument.v41_p1_feature_counts fc on fc.y=tc.y and fc.feature_no=fa.feature_no and fc.feature_value=v.feature_value
)
select y,feature_no,feature_value,ln((cnt+0.5)/(yn+0.5*k)) logp from cells;
create unique index v41_p1_logprob_idx on instrument.v41_p1_logprob(y,feature_no,feature_value);

-- Position-specific L/R/F triple components.
drop table if exists instrument.v41_pos_components;
create table instrument.v41_pos_components as
with comps(comp,fl,fr,ff) as (values (1,1,2,3),(2,4,5,6),(3,7,8,9),(4,10,11,12),(5,13,14,15),(6,16,17,18),(7,19,20,21),(8,22,23,24))
select c.comp,tc.y,l.feature_value::int l,r.feature_value::int rr,f.feature_value::int ff,l.logp+r.logp+f.logp score
from comps c cross join instrument.v41_target_counts tc
join instrument.v41_p1_logprob l on l.y=tc.y and l.feature_no=c.fl
join instrument.v41_p1_logprob r on r.y=tc.y and r.feature_no=c.fr
join instrument.v41_p1_logprob f on f.y=tc.y and f.feature_no=c.ff;
create index v41_pos_components_idx on instrument.v41_pos_components(comp,y,l,rr,ff);

-- Position-specific DL/DR components.
drop table if exists instrument.v41_traj_components;
create table instrument.v41_traj_components as
with comps(comp,fdl,fdr) as (values (1,25,26),(2,27,28),(3,29,30),(4,31,32),(5,33,34),(6,35,36))
select c.comp,tc.y,dl.feature_value::int dl,dr.feature_value::int dr,dl.logp+dr.logp score
from comps c cross join instrument.v41_target_counts tc
join instrument.v41_p1_logprob dl on dl.y=tc.y and dl.feature_no=c.fdl
join instrument.v41_p1_logprob dr on dr.y=tc.y and dr.feature_no=c.fdr;
create index v41_traj_components_idx on instrument.v41_traj_components(comp,y,dl,dr);

drop table if exists instrument.v41_cross_components;
create table instrument.v41_cross_components as
select tc.y,x.feature_value::int xshared,b.feature_value::int xboundary,x.logp+b.logp score
from instrument.v41_target_counts tc
join instrument.v41_p1_logprob x on x.y=tc.y and x.feature_no=37
join instrument.v41_p1_logprob b on b.y=tc.y and b.feature_no=38;
create index v41_cross_components_idx on instrument.v41_cross_components(y,xshared,xboundary);

-- P2 pooled relational log-prob table from frozen pooled counts.
drop table if exists instrument.v41_p2_logprob;
create table instrument.v41_p2_logprob as
with fam as (select family,count(distinct value)::int k,array_agg(distinct value order by value) vals from instrument.v41_p2_counts group by family), mult(family,m) as (values ('L',8),('R',8),('F',8),('DL',6),('DR',6),('XS',1),('XB',1)), cells as (
 select tc.y,f.family,v.value,tc.n::double precision yn,f.k,m.m,coalesce(c.n,0)::double precision cnt
 from instrument.v41_target_counts tc cross join fam f join mult m using(family) cross join lateral unnest(f.vals) v(value)
 left join instrument.v41_p2_counts c on c.y=tc.y and c.family=f.family and c.value=v.value
)
select y,family,value,ln((cnt+0.5)/(yn*m+0.5*k)) logp from cells;
create unique index v41_p2_logprob_idx on instrument.v41_p2_logprob(y,family,value);

drop table if exists instrument.v41_p2_micro_components;
create table instrument.v41_p2_micro_components as
select tc.y,l.value::int l,r.value::int rr,f.value::int ff,l.logp+r.logp+f.logp score
from instrument.v41_target_counts tc
join instrument.v41_p2_logprob l on l.y=tc.y and l.family='L'
join instrument.v41_p2_logprob r on r.y=tc.y and r.family='R'
join instrument.v41_p2_logprob f on f.y=tc.y and f.family='F';
create index v41_p2_micro_components_idx on instrument.v41_p2_micro_components(y,l,rr,ff);

drop table if exists instrument.v41_p2_traj_components;
create table instrument.v41_p2_traj_components as
select tc.y,dl.value::int dl,dr.value::int dr,dl.logp+dr.logp score
from instrument.v41_target_counts tc
join instrument.v41_p2_logprob dl on dl.y=tc.y and dl.family='DL'
join instrument.v41_p2_logprob dr on dr.y=tc.y and dr.family='DR';
create index v41_p2_traj_components_idx on instrument.v41_p2_traj_components(y,dl,dr);

drop table if exists instrument.v41_p2_cross_components;
create table instrument.v41_p2_cross_components as
select tc.y,x.value::int xshared,b.value::int xboundary,x.logp+b.logp score
from instrument.v41_target_counts tc
join instrument.v41_p2_logprob x on x.y=tc.y and x.family='XS'
join instrument.v41_p2_logprob b on b.y=tc.y and b.family='XB';
create index v41_p2_cross_components_idx on instrument.v41_p2_cross_components(y,xshared,xboundary);