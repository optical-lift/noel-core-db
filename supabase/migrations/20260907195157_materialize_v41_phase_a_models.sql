drop table if exists instrument.v41_target_inventory;
create table instrument.v41_target_inventory as
select target,n,row_number() over(order by n desc,target) rank from (
 select target,count(*)::bigint n from instrument.v41_windows where not holdout group by target
) x order by n desc,target limit 64;

drop table if exists instrument.v41_train;
create table instrument.v41_train as
select w.*,case when i.target is null then 'OTHER' else w.target end y
from instrument.v41_windows w left join instrument.v41_target_inventory i on i.target=w.target;
create index v41_train_split_idx on instrument.v41_train(holdout,center_id);

drop table if exists instrument.v41_target_counts;
create table instrument.v41_target_counts as select y,count(*)::bigint n from instrument.v41_train where not holdout group by y;

-- ordered P1 feature counts
 drop table if exists instrument.v41_p1_feature_counts;
create table instrument.v41_p1_feature_counts as
select y,feature_no,feature_value,count(*)::bigint n from (
 select y,1 feature_no,m4_l::text feature_value from instrument.v41_train where not holdout union all
 select y,2,m4_r::text from instrument.v41_train where not holdout union all select y,3,m4_f::text from instrument.v41_train where not holdout union all
 select y,4,m3_l::text from instrument.v41_train where not holdout union all select y,5,m3_r::text from instrument.v41_train where not holdout union all select y,6,m3_f::text from instrument.v41_train where not holdout union all
 select y,7,m2_l::text from instrument.v41_train where not holdout union all select y,8,m2_r::text from instrument.v41_train where not holdout union all select y,9,m2_f::text from instrument.v41_train where not holdout union all
 select y,10,m1_l::text from instrument.v41_train where not holdout union all select y,11,m1_r::text from instrument.v41_train where not holdout union all select y,12,m1_f::text from instrument.v41_train where not holdout union all
 select y,13,p1_l::text from instrument.v41_train where not holdout union all select y,14,p1_r::text from instrument.v41_train where not holdout union all select y,15,p1_f::text from instrument.v41_train where not holdout union all
 select y,16,p2_l::text from instrument.v41_train where not holdout union all select y,17,p2_r::text from instrument.v41_train where not holdout union all select y,18,p2_f::text from instrument.v41_train where not holdout union all
 select y,19,p3_l::text from instrument.v41_train where not holdout union all select y,20,p3_r::text from instrument.v41_train where not holdout union all select y,21,p3_f::text from instrument.v41_train where not holdout union all
 select y,22,p4_l::text from instrument.v41_train where not holdout union all select y,23,p4_r::text from instrument.v41_train where not holdout union all select y,24,p4_f::text from instrument.v41_train where not holdout union all
 select y,25,dl_l1::text from instrument.v41_train where not holdout union all select y,26,dr_l1::text from instrument.v41_train where not holdout union all
 select y,27,dl_l2::text from instrument.v41_train where not holdout union all select y,28,dr_l2::text from instrument.v41_train where not holdout union all
 select y,29,dl_l3::text from instrument.v41_train where not holdout union all select y,30,dr_l3::text from instrument.v41_train where not holdout union all
 select y,31,dl_r1::text from instrument.v41_train where not holdout union all select y,32,dr_r1::text from instrument.v41_train where not holdout union all
 select y,33,dl_r2::text from instrument.v41_train where not holdout union all select y,34,dr_r2::text from instrument.v41_train where not holdout union all
 select y,35,dl_r3::text from instrument.v41_train where not holdout union all select y,36,dr_r3::text from instrument.v41_train where not holdout union all
 select y,37,xshared::text from instrument.v41_train where not holdout union all select y,38,xboundary::text from instrument.v41_train where not holdout
) z group by y,feature_no,feature_value;
create index v41_p1_fc_idx on instrument.v41_p1_feature_counts(y,feature_no,feature_value);

drop table if exists instrument.v41_feature_alphabets;
create table instrument.v41_feature_alphabets as select feature_no,count(distinct feature_value)::int k,array_agg(distinct feature_value order by feature_value) vals from instrument.v41_p1_feature_counts group by feature_no;

-- compact P1 params
 drop table if exists instrument.v41_p1_params;
create table instrument.v41_p1_params as
with total as (select sum(n)::double precision n from instrument.v41_target_counts), cells as (
 select tc.y,fa.feature_no,v.feature_value,tc.n::double precision yn,fa.k,coalesce(fc.n,0)::double precision cnt
 from instrument.v41_target_counts tc cross join instrument.v41_feature_alphabets fa
 cross join lateral unnest(fa.vals) v(feature_value)
 left join instrument.v41_p1_feature_counts fc on fc.y=tc.y and fc.feature_no=fa.feature_no and fc.feature_value=v.feature_value
), em as (select y,jsonb_object_agg(feature_no||':'||feature_value,ln((cnt+0.5)/(yn+0.5*k))) emissions from cells group by y)
select tc.y,ln(tc.n::double precision/t.n) log_prior,em.emissions from instrument.v41_target_counts tc cross join total t join em using(y);

-- P2 pooled family counts: L over 8 positions, R over 8, F over 8, DL over 6, DR over 6, Xshared, Xboundary.
drop table if exists instrument.v41_p2_counts;
create table instrument.v41_p2_counts as
select y,family,value,count(*)::bigint n from (
 select y,'L' family,v::text value from instrument.v41_train cross join lateral unnest(array[m4_l,m3_l,m2_l,m1_l,p1_l,p2_l,p3_l,p4_l]) v where not holdout union all
 select y,'R',v::text from instrument.v41_train cross join lateral unnest(array[m4_r,m3_r,m2_r,m1_r,p1_r,p2_r,p3_r,p4_r]) v where not holdout union all
 select y,'F',v::text from instrument.v41_train cross join lateral unnest(array[m4_f,m3_f,m2_f,m1_f,p1_f,p2_f,p3_f,p4_f]) v where not holdout union all
 select y,'DL',v::text from instrument.v41_train cross join lateral unnest(array[dl_l1,dl_l2,dl_l3,dl_r1,dl_r2,dl_r3]) v where not holdout union all
 select y,'DR',v::text from instrument.v41_train cross join lateral unnest(array[dr_l1,dr_l2,dr_l3,dr_r1,dr_r2,dr_r3]) v where not holdout union all
 select y,'XS',xshared::text from instrument.v41_train where not holdout union all
 select y,'XB',xboundary::text from instrument.v41_train where not holdout
) q group by y,family,value;
create index v41_p2_counts_idx on instrument.v41_p2_counts(y,family,value);

drop table if exists instrument.v41_p2_params;
create table instrument.v41_p2_params as
with fam as (select family,count(distinct value)::int k,array_agg(distinct value order by value) vals from instrument.v41_p2_counts group by family), mult(family,m) as (values ('L',8),('R',8),('F',8),('DL',6),('DR',6),('XS',1),('XB',1)), total as (select sum(n)::double precision n from instrument.v41_target_counts), cells as (
 select tc.y,f.family,v.value,tc.n::double precision yn,f.k,m.m,coalesce(c.n,0)::double precision cnt
 from instrument.v41_target_counts tc cross join fam f join mult m using(family) cross join lateral unnest(f.vals) v(value)
 left join instrument.v41_p2_counts c on c.y=tc.y and c.family=f.family and c.value=v.value
), em as (select y,jsonb_object_agg(family||':'||value,ln((cnt+0.5)/(yn*m+0.5*k))) emissions from cells group by y)
select tc.y,ln(tc.n::double precision/t.n) log_prior,em.emissions from instrument.v41_target_counts tc cross join total t join em using(y);