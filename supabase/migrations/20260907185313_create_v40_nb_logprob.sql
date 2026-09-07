create table if not exists instrument.v40_nb_logprob as
with total as (select sum(n)::double precision n from instrument.v40_target_counts),
targets as (select target,n::double precision n from instrument.v40_target_counts),
vals as (select feature_no,unnest(values_seen) feature_value,k from instrument.v40_feature_alphabets),
allcells as (
 select t.target,t.n target_n,v.feature_no,v.feature_value,v.k,coalesce(c.n,0)::double precision cell_n
 from targets t cross join vals v
 left join instrument.v40_feature_counts c on c.target=t.target and c.feature_no=v.feature_no and c.feature_value=v.feature_value
)
select a.target,a.feature_no,a.feature_value,
       ln(a.target_n/(select n from total)) as log_prior,
       ln((a.cell_n+0.5)/(a.target_n+0.5*a.k)) as log_emission
from allcells a;
create unique index if not exists v40_nb_logprob_idx on instrument.v40_nb_logprob(feature_no,feature_value,target);
create index if not exists v40_nb_logprob_target_idx on instrument.v40_nb_logprob(target,feature_no);