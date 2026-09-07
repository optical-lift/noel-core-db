create table if not exists instrument.v40_context_null_binned as
with cp as (
 select
  max(q20) filter(where feature_no=2) f2q20,max(q40) filter(where feature_no=2) f2q40,max(q60) filter(where feature_no=2) f2q60,max(q80) filter(where feature_no=2) f2q80,
  max(q20) filter(where feature_no=4) f4q20,max(q40) filter(where feature_no=4) f4q40,max(q60) filter(where feature_no=4) f4q60,max(q80) filter(where feature_no=4) f4q80,
  max(q20) filter(where feature_no=6) f6q20,max(q40) filter(where feature_no=6) f6q40,max(q60) filter(where feature_no=6) f6q60,max(q80) filter(where feature_no=6) f6q80,
  max(q20) filter(where feature_no=8) f8q20,max(q40) filter(where feature_no=8) f8q40,max(q60) filter(where feature_no=8) f8q60,max(q80) filter(where feature_no=8) f8q80,
  max(q20) filter(where feature_no=10) f10q20,max(q40) filter(where feature_no=10) f10q40,max(q60) filter(where feature_no=10) f10q60,max(q80) filter(where feature_no=10) f10q80
 from instrument.v40_cutpoints
)
select n.center_id,n.book,n.block_index,n.target,n.k,n.f1,n.f3,n.f5,n.f7,n.f9,n.f11,
 case when n.right_mean_len<=cp.f2q20 then 1 when n.right_mean_len<=cp.f2q40 then 2 when n.right_mean_len<=cp.f2q60 then 3 when n.right_mean_len<=cp.f2q80 then 4 else 5 end f2,
 case when n.right_sd_len<=cp.f4q20 then 1 when n.right_sd_len<=cp.f4q40 then 2 when n.right_sd_len<=cp.f4q60 then 3 when n.right_sd_len<=cp.f4q80 then 4 else 5 end f4,
 case when n.right_final_rate<=cp.f6q20 then 1 when n.right_final_rate<=cp.f6q40 then 2 when n.right_final_rate<=cp.f6q60 then 3 when n.right_final_rate<=cp.f6q80 then 4 else 5 end f6,
 case when n.right_mean_equality_complexity<=cp.f8q20 then 1 when n.right_mean_equality_complexity<=cp.f8q40 then 2 when n.right_mean_equality_complexity<=cp.f8q60 then 3 when n.right_mean_equality_complexity<=cp.f8q80 then 4 else 5 end f8,
 case when n.right_mean_abs_len_delta<=cp.f10q20 then 1 when n.right_mean_abs_len_delta<=cp.f10q40 then 2 when n.right_mean_abs_len_delta<=cp.f10q60 then 3 when n.right_mean_abs_len_delta<=cp.f10q80 then 4 else 5 end f10,
 n.right_distinct_intrinsic_count f12,n.cross_side_same_skeleton_pairs f13,n.boundary_bridge f14
from instrument.v40_context_null_features n cross join cp;
create unique index if not exists v40_context_null_binned_idx on instrument.v40_context_null_binned(k,center_id);