create table if not exists instrument.v40_feature_counts as
select u.feature_no,u.feature_value,w.target,count(*)::bigint n
from instrument.v40_binned_windows w
cross join lateral (values
 (1,w.f1::text),(2,w.f2::text),(3,w.f3::text),(4,w.f4::text),(5,w.f5::text),(6,w.f6::text),(7,w.f7::text),
 (8,w.f8::text),(9,w.f9::text),(10,w.f10::text),(11,w.f11::text),(12,w.f12::text),(13,w.f13::text),(14,w.f14::text)
) u(feature_no,feature_value)
where not w.holdout
group by u.feature_no,u.feature_value,w.target;
create unique index if not exists v40_feature_counts_idx on instrument.v40_feature_counts(feature_no,feature_value,target);
create index if not exists v40_feature_counts_target_idx on instrument.v40_feature_counts(target,feature_no);

create table if not exists instrument.v40_feature_alphabets as
select feature_no,count(distinct feature_value)::int k,array_agg(distinct feature_value order by feature_value) values_seen
from instrument.v40_feature_counts group by feature_no;
create unique index if not exists v40_feature_alphabets_idx on instrument.v40_feature_alphabets(feature_no);