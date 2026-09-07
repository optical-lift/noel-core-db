drop table if exists instrument.v40_m0_counts;
create table instrument.v40_m0_counts as
select codepoint,count(*)::bigint n
from instrument.v40_witness_centers where not holdout group by codepoint;

drop table if exists instrument.v40_m1_feature_counts;
create table instrument.v40_m1_feature_counts as
select codepoint,feature_no,feature_value,count(*)::bigint n
from (
  select codepoint,1 feature_no,f1::text feature_value from instrument.v40_witness_centers where not holdout union all
  select codepoint,2,f2::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,3,f3::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,4,f4::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,5,f5::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,6,f6::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,7,f7::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,8,f8::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,9,f9::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,10,f10::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,11,f11::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,12,f12::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,13,f13::text from instrument.v40_witness_centers where not holdout union all
  select codepoint,14,f14::text from instrument.v40_witness_centers where not holdout
) x group by codepoint,feature_no,feature_value;
create index v40_m1_feature_counts_idx on instrument.v40_m1_feature_counts(codepoint,feature_no,feature_value);

drop table if exists instrument.v40_m1_params;
create table instrument.v40_m1_params as
with total as (select sum(n)::double precision n from instrument.v40_m0_counts),
marks as (select codepoint,n::double precision n from instrument.v40_m0_counts),
keys as (select feature_no,k from instrument.v40_feature_alphabets),
vals as (select feature_no,unnest(values_seen)::text feature_value from instrument.v40_feature_alphabets),
allcells as (
 select m.codepoint,k.feature_no,v.feature_value,m.n,k.k,
        coalesce(c.n,0)::double precision cnt
 from marks m cross join keys k join vals v using(feature_no)
 left join instrument.v40_m1_feature_counts c on c.codepoint=m.codepoint and c.feature_no=k.feature_no and c.feature_value=v.feature_value
), em as (
 select codepoint,jsonb_object_agg(feature_no||':'||feature_value,ln((cnt+0.5)/(n+0.5*k))) emissions
 from allcells group by codepoint
)
select m.codepoint,ln(m.n/t.n) log_prior,e.emissions
from marks m cross join total t join em e using(codepoint);

drop table if exists instrument.v40_m2_counts;
create table instrument.v40_m2_counts as
select intrinsic,codepoint,count(*)::bigint n from instrument.v40_witness_centers where not holdout group by intrinsic,codepoint;
drop table if exists instrument.v40_m2_totals;
create table instrument.v40_m2_totals as
select intrinsic,count(*)::bigint n from instrument.v40_witness_centers where not holdout group by intrinsic;
create index v40_m2_counts_idx on instrument.v40_m2_counts(intrinsic,codepoint);
create unique index v40_m2_totals_idx on instrument.v40_m2_totals(intrinsic);

drop table if exists instrument.v40_m4_counts;
create table instrument.v40_m4_counts as
select skeleton,codepoint,count(*)::bigint n from instrument.v40_witness_centers where not holdout group by skeleton,codepoint;
drop table if exists instrument.v40_m4_totals;
create table instrument.v40_m4_totals as
select skeleton,count(*)::bigint n from instrument.v40_witness_centers where not holdout group by skeleton;
create index v40_m4_counts_idx on instrument.v40_m4_counts(skeleton,codepoint);
create unique index v40_m4_totals_idx on instrument.v40_m4_totals(skeleton);