create table if not exists instrument.v40_cutpoints(
 feature_no int primary key, feature_name text not null, q20 double precision, q40 double precision, q60 double precision, q80 double precision
);
insert into instrument.v40_cutpoints values
(1,'left_mean_len',3.25,3.75,4.0,4.5),
(2,'right_mean_len',3.25,3.75,4.0,4.5),
(3,'left_sd_len',0.707106781186548,0.82915619758885,1.11803398874989,1.29903810567666),
(4,'right_sd_len',0.707106781186548,0.82915619758885,1.11803398874989,1.29903810567666),
(5,'left_final_rate',0.0,0.25,0.25,0.5),
(6,'right_final_rate',0.0,0.25,0.25,0.5),
(7,'left_mean_equality_complexity',0.916666666666667,0.95,1.0,1.0),
(8,'right_mean_equality_complexity',0.916666666666667,0.95,1.0,1.0),
(9,'left_mean_abs_len_delta',0.666666666666667,1.0,1.66666666666667,2.0),
(10,'right_mean_abs_len_delta',0.666666666666667,1.0,1.66666666666667,2.0)
on conflict(feature_no) do nothing;

create table if not exists instrument.v40_target_inventory as
with counts as (
 select center_intrinsic,count(*)::bigint n from instrument.v40_center_blind_windows where not holdout group by center_intrinsic
), ranked as (
 select center_intrinsic,n,row_number() over(order by n desc,center_intrinsic asc) rank from counts
)
select rank::int,center_intrinsic,n from ranked where rank<=64;
create unique index if not exists v40_target_inventory_target_idx on instrument.v40_target_inventory(center_intrinsic);

create table if not exists instrument.v40_binned_windows as
with q as (select * from instrument.v40_cutpoints),
cp as (
 select
  max(q20) filter(where feature_no=1) f1q20,max(q40) filter(where feature_no=1) f1q40,max(q60) filter(where feature_no=1) f1q60,max(q80) filter(where feature_no=1) f1q80,
  max(q20) filter(where feature_no=2) f2q20,max(q40) filter(where feature_no=2) f2q40,max(q60) filter(where feature_no=2) f2q60,max(q80) filter(where feature_no=2) f2q80,
  max(q20) filter(where feature_no=3) f3q20,max(q40) filter(where feature_no=3) f3q40,max(q60) filter(where feature_no=3) f3q60,max(q80) filter(where feature_no=3) f3q80,
  max(q20) filter(where feature_no=4) f4q20,max(q40) filter(where feature_no=4) f4q40,max(q60) filter(where feature_no=4) f4q60,max(q80) filter(where feature_no=4) f4q80,
  max(q20) filter(where feature_no=5) f5q20,max(q40) filter(where feature_no=5) f5q40,max(q60) filter(where feature_no=5) f5q60,max(q80) filter(where feature_no=5) f5q80,
  max(q20) filter(where feature_no=6) f6q20,max(q40) filter(where feature_no=6) f6q40,max(q60) filter(where feature_no=6) f6q60,max(q80) filter(where feature_no=6) f6q80,
  max(q20) filter(where feature_no=7) f7q20,max(q40) filter(where feature_no=7) f7q40,max(q60) filter(where feature_no=7) f7q60,max(q80) filter(where feature_no=7) f7q80,
  max(q20) filter(where feature_no=8) f8q20,max(q40) filter(where feature_no=8) f8q40,max(q60) filter(where feature_no=8) f8q60,max(q80) filter(where feature_no=8) f8q80,
  max(q20) filter(where feature_no=9) f9q20,max(q40) filter(where feature_no=9) f9q40,max(q60) filter(where feature_no=9) f9q60,max(q80) filter(where feature_no=9) f9q80,
  max(q20) filter(where feature_no=10) f10q20,max(q40) filter(where feature_no=10) f10q40,max(q60) filter(where feature_no=10) f10q60,max(q80) filter(where feature_no=10) f10q80
 from q
)
select w.center_id,w.book,w.chapter,w.verse,w.position,w.block_index,w.holdout,
       coalesce(t.center_intrinsic,'OTHER') as target,
       case when w.left_mean_len<=cp.f1q20 then 1 when w.left_mean_len<=cp.f1q40 then 2 when w.left_mean_len<=cp.f1q60 then 3 when w.left_mean_len<=cp.f1q80 then 4 else 5 end f1,
       case when w.right_mean_len<=cp.f2q20 then 1 when w.right_mean_len<=cp.f2q40 then 2 when w.right_mean_len<=cp.f2q60 then 3 when w.right_mean_len<=cp.f2q80 then 4 else 5 end f2,
       case when w.left_sd_len<=cp.f3q20 then 1 when w.left_sd_len<=cp.f3q40 then 2 when w.left_sd_len<=cp.f3q60 then 3 when w.left_sd_len<=cp.f3q80 then 4 else 5 end f3,
       case when w.right_sd_len<=cp.f4q20 then 1 when w.right_sd_len<=cp.f4q40 then 2 when w.right_sd_len<=cp.f4q60 then 3 when w.right_sd_len<=cp.f4q80 then 4 else 5 end f4,
       case when w.left_final_rate<=cp.f5q20 then 1 when w.left_final_rate<=cp.f5q40 then 2 when w.left_final_rate<=cp.f5q60 then 3 when w.left_final_rate<=cp.f5q80 then 4 else 5 end f5,
       case when w.right_final_rate<=cp.f6q20 then 1 when w.right_final_rate<=cp.f6q40 then 2 when w.right_final_rate<=cp.f6q60 then 3 when w.right_final_rate<=cp.f6q80 then 4 else 5 end f6,
       case when w.left_mean_equality_complexity<=cp.f7q20 then 1 when w.left_mean_equality_complexity<=cp.f7q40 then 2 when w.left_mean_equality_complexity<=cp.f7q60 then 3 when w.left_mean_equality_complexity<=cp.f7q80 then 4 else 5 end f7,
       case when w.right_mean_equality_complexity<=cp.f8q20 then 1 when w.right_mean_equality_complexity<=cp.f8q40 then 2 when w.right_mean_equality_complexity<=cp.f8q60 then 3 when w.right_mean_equality_complexity<=cp.f8q80 then 4 else 5 end f8,
       case when w.left_mean_abs_len_delta<=cp.f9q20 then 1 when w.left_mean_abs_len_delta<=cp.f9q40 then 2 when w.left_mean_abs_len_delta<=cp.f9q60 then 3 when w.left_mean_abs_len_delta<=cp.f9q80 then 4 else 5 end f9,
       case when w.right_mean_abs_len_delta<=cp.f10q20 then 1 when w.right_mean_abs_len_delta<=cp.f10q40 then 2 when w.right_mean_abs_len_delta<=cp.f10q60 then 3 when w.right_mean_abs_len_delta<=cp.f10q80 then 4 else 5 end f10,
       w.left_distinct_intrinsic_count f11,w.right_distinct_intrinsic_count f12,w.cross_side_same_skeleton_pairs f13,w.boundary_bridge::int f14
from instrument.v40_center_blind_windows w cross join cp
left join instrument.v40_target_inventory t on t.center_intrinsic=w.center_intrinsic;
create unique index if not exists v40_binned_windows_center_idx on instrument.v40_binned_windows(center_id);
create index if not exists v40_binned_windows_split_idx on instrument.v40_binned_windows(holdout,book,block_index,center_id);
create index if not exists v40_binned_windows_target_idx on instrument.v40_binned_windows(target);

create table if not exists instrument.v40_target_counts as
select target,count(*)::bigint n from instrument.v40_binned_windows where not holdout group by target;
create unique index if not exists v40_target_counts_target_idx on instrument.v40_target_counts(target);